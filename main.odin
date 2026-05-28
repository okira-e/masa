package main

import "analyzer"
import "ast"
import "core:flags"
import "core:fmt"
import "core:mem"
import "core:os"
import "core:strings"
import "lexer"
import "parser"
import "syntax"
import "transpiler"

App_Flags :: struct {
	print_ast: bool `args:"name=print-ast"`,
	emit_js:   bool `args:"name=emit-js"`,
}

main :: proc() {
	args := os.args[1:]
	if len(args) == 0 {
		fmt.fprintf(os.stderr, "Usage: masa <file.masa>\n")
		os.exit(1)
	}

	// Set up flags
	app_flags: App_Flags
	err := flags.parse(&app_flags, os.args[2:], .Unix)
	if err != nil {
		flags.print_errors(typeid_of(App_Flags), err, os.args[0], .Unix)
		return
	}

	filepath := args[0]
	source, read_file_err := os.read_entire_file_from_path(filepath, allocator = context.allocator)
	if read_file_err != nil {
		fmt.fprintf(os.stderr, "Failed to read the \"%s\" file with: %s", filepath, read_file_err)
		os.exit(1)
	}
	defer delete(source)

	arena: mem.Dynamic_Arena
	mem.dynamic_arena_init(&arena)
	arena_alloc := mem.dynamic_arena_allocator(&arena)
	defer mem.dynamic_arena_destroy(&arena)

	l := lexer.Lexer{}
	lexer.init(&l, arena_alloc)

	// Lexing

	tokens, lexing_err := lexer.scan(&l, transmute(string)source)
	defer delete(tokens)
	if lexing_err != nil {
		fmt.fprintf(os.stderr, "Error while scanning: %v\n", lexing_err)
		os.exit(1)
	}

	// Parsing

	p: parser.Parser
	parser.init(&p, tokens[:], arena_alloc)
	stmts, parser_err := parser.parse(&p)
	defer delete(stmts)
	if parser_err != nil {
		fmt.fprintf(os.stderr, "Error while parsing: %v\n", parser_err)
		os.exit(1)
	}
	if app_flags.print_ast {
		print_ast(stmts[:], transmute(string)source)
	}

	// Static analysis

	a: analyzer.Analyzer
	analyzer.init(&a, transmute(string)source)
	defer analyzer.destroy(&a)
	analyzer_err := analyzer.analyze(&a, stmts[:])
	if analyzer_err != nil {
		fmt.fprintf(os.stderr, "Error while analyzing: %v\n", analyzer_err)
		os.exit(1)
	}

	// Transpilation to JavaScript

	tr: transpiler.Transpiler
	transpiler.init(&tr, transmute(string)source)
	defer transpiler.destroy(&tr)
	js := transpiler.transpile(&tr, stmts[:])
	handle_js(app_flags, js)
}

handle_js :: proc(app_flags: App_Flags, js: string) {
	err := os.mkdir("js-out")
	if err != nil && err != .Exist {
		fmt.fprintf(os.stderr, "Failed to create js-out: %v\n", err)
		os.exit(1)
	}

	err = os.write_entire_file("js-out/main.js", js)
	if err != nil {
		fmt.fprintf(os.stderr, "Failed to create emitted files: %v\n", err)
		os.exit(1)
	}

	if !app_flags.emit_js {
		os.remove_all("js-out")
	}
}

@(private = "file")
print_ast :: proc(stmts: []^syntax.Stmt, source: string) {
	builder := strings.builder_make()
	for stmt in stmts {
		ast.build_ast_from_stmt(&builder, source, stmt)
	}
	out := strings.to_string(builder)
	defer delete(out)
	fmt.println(out)
}
