package main

import "core:fmt"
import "core:mem"
import "core:os"
import "lexer"
import "parser"

main :: proc() {
	args := os.args

	if len(args) < 2 {
		fmt.fprintf(os.stderr, "Usage: masa <file.masa>\n")
		os.exit(1)
	}

	filepath := args[1]

	source, success := os.read_entire_file(filepath)
	if !success {
		fmt.fprintf(os.stderr, "Failed to read the \"%s\" file", filepath)
		os.exit(1)
	}

	fmt.printf("Charachters: \n")
	for b in source {
		if b == '\n' {
			fmt.printf("\\n")
		} else {
			fmt.printf("%c", b)
		}
	}
	fmt.println()
	fmt.println()

	l := lexer.Lexer{}
	lexer.init(&l)

	tokens, lexing_err := lexer.scan(&l, transmute(string)source)
	defer delete(tokens)
	if lexing_err != nil {
		fmt.fprintf(os.stderr, "Error while scanning: %s\n", lexing_err)
		os.exit(1)
	}
	_ = tokens

	arena: mem.Dynamic_Arena
	mem.dynamic_arena_init(&arena)
	arena_alloc := mem.dynamic_arena_allocator(&arena)

	p: parser.Parser
	parser.init(&p, tokens[:], arena_alloc)
	exprs, _ := parser.parse(&p)
	defer delete(exprs)
	defer mem.dynamic_arena_destroy(&arena)

}
