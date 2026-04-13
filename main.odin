package main

import "ast"
import "core:flags"
import "core:fmt"
import "core:mem"
import "core:os"
import "core:strings"
import "lexer"
import "parser"
import "syntax"

App_Flags :: struct {
	print_ast: bool `args:"name=print-ast"`,
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

	tokens, lexing_err := lexer.scan(&l, transmute(string)source)
	defer delete(tokens)
	if lexing_err != nil {
		fmt.fprintf(os.stderr, "Error while scanning: %s\n", lexing_err)
		os.exit(1)
	}
	_ = tokens

	p: parser.Parser
	parser.init(&p, tokens[:], arena_alloc)
	exprs, _ := parser.parse(&p)
	defer delete(exprs)

	if app_flags.print_ast {
		print_ast(exprs[:], transmute(string)source)
	}
}

@(private = "file")
print_ast :: proc(exprs: []^syntax.Expr, source: string) {
	builder := strings.builder_make()
	for expr in exprs {
		ast.build_ast_from_expr(&builder, source, expr)
	}
	out := strings.to_string(builder)
	defer delete(out)
	fmt.println(out)
}
