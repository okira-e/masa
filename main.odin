package main

import "core:time"
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
	print_ast:    bool `args:"name=print-ast"`,
	emit_js:      bool `args:"name=emit-js"`,
	show_metrics: bool `args:"name=show-metrics"`,
}

main :: proc() {
	args := os.args[1:]
	if len(args) == 0 {
		fmt.fprintf(os.stderr, "Usage: masa run <file.masa>\n")
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

	//
	// Lexing
	//

	start := time.tick_now()
	tokens, lexing_err := lexer.scan(&l, transmute(string)source)
	defer delete(tokens)
	if lexing_err != nil {
		fmt.fprint(os.stderr, lexer.format_error(lexing_err.?, transmute(string)source))
		os.exit(1)
	}
	// lexer.print_tokens(transmute(string)source, tokens)
    lexing_duration := time.tick_since(start)

    //
	// Parsing
	//

	p: parser.Parser
	parser.init(&p, tokens[:], arena_alloc)
	start = time.tick_now()
	stmts, parser_err := parser.parse(&p)
	defer delete(stmts)
	if parser_err != nil {
		fmt.fprint(os.stderr, parser.format_error(parser_err.?, transmute(string)source))
		os.exit(1)
	}
    parsing_duration := time.tick_since(start)
	if app_flags.print_ast {
		print_ast(stmts[:], transmute(string)source)
	}
	// for it in stmts do fmt.println("STMT:", it)

	//
	// Lexical analysis
	//

	a: analyzer.Analyzer
	analyzer.init(&a, transmute(string)source)
	defer analyzer.destroy(&a)
	start = time.tick_now()
	analyzer_err := analyzer.analyze(&a, stmts[:])
	if err, ok := analyzer_err.?; ok {
		fmt.fprint(os.stderr, analyzer.format_error(err, transmute(string)source, context.temp_allocator))
		os.exit(1)
	}
    analyzing_duration := time.tick_since(start)

    //
	// Transpilation to JavaScript
	//

	tr: transpiler.Transpiler
	transpiler.init(&tr, transmute(string)source)
	defer transpiler.destroy(&tr)
	start = time.tick_now()
	js := transpiler.transpile(&tr, stmts[:])
    transpiling_duration := time.tick_since(start)

	handle_js(app_flags, js)

	if app_flags.show_metrics {
		loc := len(strings.split_lines(transmute(string)source))
		print_metrics(
			loc,
			lexing_duration,
			parsing_duration,
			analyzing_duration,
			transpiling_duration
		)
	}
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
		err = os.remove_all("js-out")
		if err != nil {
			fmt.fprintf(os.stderr, "Failed to remove the emitted files directory: %v\n", err)
			os.exit(1)
		}
	}
}

print_metrics :: proc(loc: int, lexing_duration, parsing_duration, analyzing_duration, transpiling_duration: time.Duration) {
	fmt.printf("\n")
	fmt.printf("Compiled %d lines of code.\n", loc)
    fmt.printf("Lexing took:           %v\n", lexing_duration)
    fmt.printf("Parsing took:          %v\n", lexing_duration)
    fmt.printf("Lexical analysis took: %v\n", lexing_duration)
    fmt.printf("Transpiling took:      %v\n", lexing_duration)
	fmt.printf("\n")
}

@(private = "file")
print_ast :: proc(stmts: []syntax.Stmt, source: string) {
	builder := strings.builder_make()
	ast.build_ast_from_stmts(&builder, source, stmts)
	out := strings.to_string(builder)
	defer delete(out)
	fmt.println(out)
}
