package main

import "core:fmt"
import "core:os"
import "lexer"

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
			fmt.printf("%s", b)
		}
	}
	fmt.println()
	fmt.println()

	lxr := lexer.Lexer{}
	lexer.init(&lxr)

	tokens, err := lexer.scan(&lxr, transmute(string)source)
	defer delete(tokens)
	if err != nil {
		fmt.fprintf(os.stderr, "Error while scanning: %s\n", err)
		os.exit(1)
	}
	_ = tokens
}
