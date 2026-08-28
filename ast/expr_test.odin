package ast

import "../lexer"
import "../parser"
import "core:mem"
import "core:strings"
import "core:testing"

Ast_Case :: struct {
	name:     string,
	source:   string,
	expected: string,
}

@(test)
test_expression_ast_from_source :: proc(t: ^testing.T) {
	tests := []Ast_Case {
		{name = "number literal", source = "42", expected = "42"},
		{name = "string literal", source = `"masa"`, expected = `"masa"`},
		{name = "bool literal", source = "true", expected = "true"},
		{name = "identifier", source = "value", expected = "value"},
		{name = "unary minus", source = "-5", expected = "(- 5)"},
		{name = "unary bang", source = "!false", expected = "(! false)"},
		{name = "addition", source = "1 + 2", expected = "(+ 1 2)"},
		{name = "subtraction", source = "1 - 2", expected = "(- 1 2)"},
		{name = "multiplication", source = "1 * 2", expected = "(* 1 2)"},
		{name = "division", source = "1 / 2", expected = "(/ 1 2)"},
		{name = "equal", source = "1 == 2", expected = "(== 1 2)"},
		{name = "not equal", source = "1 != 2", expected = "(!= 1 2)"},
		{name = "less", source = "1 < 2", expected = "(< 1 2)"},
		{name = "less equal", source = "1 <= 2", expected = "(<= 1 2)"},
		{name = "greater", source = "1 > 2", expected = "(> 1 2)"},
		{name = "greater equal", source = "1 >= 2", expected = "(>= 1 2)"},
		{name = "logical and", source = "true and false", expected = "(and true false)"},
		{name = "logical or", source = "true or false", expected = "(or true false)"},
		{
			name = "grouping and precedence",
			source = "(1 + 2) * 3",
			expected = "(* (+ 1 2) 3)",
		},
		{
			name = "call expression",
			source = "result := add(1, 2)",
			expected = "(:= result (call add 1 2))",
		},
		{
			name = "awaited call expression",
			source = "result := load(1).await",
			expected = "(:= result (call await load 1))",
		},
		{
			name = "function literal",
			source = "callback := fn(value: number) -> number { return value }",
			expected = "(:= callback (fn (args value:number) (returns number) { (return value) }))",
		},
		{
			name = "async function literal",
			source = "callback := async fn() -> number { return 1 }",
			expected = "(:= callback (fn async (args) (returns number) { (return 1) }))",
		},
	}

	expect_ast_cases(t, tests)
}

@(test)
test_statement_ast_from_source :: proc(t: ^testing.T) {
	tests := []Ast_Case {
		{name = "expression statement", source = "1 + 2", expected = "(+ 1 2)"},
		{name = "mutable declaration", source = "value := 1", expected = "(:= value 1)"},
		{name = "constant declaration", source = "answer :: 42", expected = "(:: answer 42)"},
		{
			name = "typed mutable declaration",
			source = "value: number = 1",
			expected = "(:= value:number 1)",
		},
		{
			name = "typed constant declaration",
			source = "answer: number : 42",
			expected = "(:: answer:number 42)",
		},
		{
			name = "bare typed declaration",
			source = "value: number",
			expected = "(:= value:number ---)",
		},
		{
			name = "multi declaration",
			source = "left, right: number = 1, 2",
			expected = "(:= left:number right:number 1 2)",
		},
		{
			name = "multi assignment",
			source = "left, right = 1, 2",
			expected = "(= left right 1 2)",
		},
		{name = "call statement", source = "run(1)", expected = "(call run 1)"},
		{name = "awaited call statement", source = "run(1).await", expected = "(call await run 1)"},
		{
			name = "if else",
			source = "if true { value := 1 } else { value := 2 }",
			expected = "(if true { (:= value 1) } { (:= value 2) })",
		},
		{
			name = "else if",
			source = "if false { value := 1 } else if true { value := 2 }",
			expected = "(if false { (:= value 1) } (if true { (:= value 2) }))",
		},
		{
			name = "block",
			source = "{ value := 1\nvalue = 2 }",
			expected = "{ (:= value 1) (= value 2) }",
		},
		{name = "bare return", source = "return", expected = "(return)"},
		{
			name = "multi return",
			source = `return 1, "one"`,
			expected = `(return 1 "one")`,
		},
	}

	expect_ast_cases(t, tests)
}

@(test)
test_function_and_type_ast_from_source :: proc(t: ^testing.T) {
	tests := []Ast_Case {
		{
			name = "named function",
			source = "identity :: fn(value: number) -> number { return value }",
			expected = "(fn identity (args value:number) (returns number) { (return value) })",
		},
		{
			name = "async named function",
			source = "load :: async fn(value: number) -> number { return value }",
			expected = "(fn load async (args value:number) (returns number) { (return value) })",
		},
		{
			name = "function stub",
			source = "external :: fn(value: number) -> number",
			expected = "(fn external (args value:number) (returns number))",
		},
		{
			name = "function typed argument and return",
			source = "apply :: fn(callback: fn(number) -> number) -> fn(number) -> number",
			expected = "(fn apply (args callback:(fn (params number) (returns number))) (returns (fn (params number) (returns number))))",
		},
		{
			name = "async function typed variable",
			source = "callback: async fn(number) -> number",
			expected = "(:= callback:(fn async (params number) (returns number)) ---)",
		},
		{
			name = "multiple function return types",
			source = "pair :: fn() -> (number, string) { return 1, \"one\" }",
			expected = "(fn pair (args) (returns number string) { (return 1 \"one\") })",
		},
	}

	expect_ast_cases(t, tests)
}

@(test)
test_loop_ast_from_source :: proc(t: ^testing.T) {
	tests := []Ast_Case {
		{
			name = "condition loop",
			source = "for true {}",
			expected = "(for true {  })",
		},
		{
			name = "traditional loop",
			source = "for i := 0; i < 2; i = i + 1 {}",
			expected = "(for (:= i 0); (< i 2); (= i (+ i 1)) {  })",
		},
		{
			name = "range loop",
			source = "for value in 1..3 {}",
			expected = "(for value in 1..3 {  })",
		},
		{
			name = "range loop with iterator",
			source = "for value, index in 1..3 {}",
			expected = "(for value, index in 1..3 {  })",
		},
		{
			name = "range loop with discarded iterator",
			source = "for value, _ in 1..3 {}",
			expected = "(for value in 1..3 {  })",
		},
	}

	expect_ast_cases(t, tests)
}

@(test)
test_program_ast_from_source :: proc(t: ^testing.T) {
	source := `counter := 0
for index := 0; index < 2; index = index + 1 {
	counter = counter + index
}
if counter == 1 {
	callback := fn(value: number) -> number { return value }
	result := callback(counter)
} else {
	result := 0
}`
	expected := `(:= counter 0)
(for (:= index 0); (< index 2); (= index (+ index 1)) { (= counter (+ counter index)) })
(if (== counter 1) { (:= callback (fn (args value:number) (returns number) { (return value) })) (:= result (call callback counter)) } { (:= result 0) })`

	actual, ok := render_source_ast(t, source)
	if !ok do return
	defer delete(actual)
	testing.expectf(t, actual == expected, "program AST mismatch\nexpected: %s\nactual:   %s", expected, actual)
}

@(private = "file")
expect_ast_cases :: proc(t: ^testing.T, tests: []Ast_Case) {
	for test in tests {
		actual, ok := render_source_ast(t, test.source)
		if !ok do continue

		testing.expectf(
			t,
			actual == test.expected,
			"%s AST mismatch\nexpected: %s\nactual:   %s",
			test.name,
			test.expected,
			actual,
		)
		delete(actual)
	}
}

@(private = "file")
render_source_ast :: proc(t: ^testing.T, source: string) -> (string, bool) {
	arena: mem.Dynamic_Arena
	mem.dynamic_arena_init(&arena)
	defer mem.dynamic_arena_destroy(&arena)
	arena_alloc := mem.dynamic_arena_allocator(&arena)

	l: lexer.Lexer
	lexer.init(&l, arena_alloc)
	tokens, lexer_err := lexer.scan(&l, source)
	defer delete(tokens)
	if lexer_err != nil {
		testing.expectf(t, false, "lexer failed for %q: %v", source, lexer_err)
		return "", false
	}

	p: parser.Parser
	parser.init(&p, tokens[:], arena_alloc)
	stmts, parser_err := parser.parse(&p)
	defer delete(stmts)
	if parser_err != nil {
		testing.expectf(t, false, "parser failed for %q: %v", source, parser_err)
		return "", false
	}

	builder := strings.builder_make()
	defer strings.builder_destroy(&builder)
	build_ast_from_stmts(&builder, source, stmts[:])

	result, clone_err := strings.clone(strings.to_string(builder))
	if clone_err != nil {
		testing.expectf(t, false, "failed to clone AST output for %q: %v", source, clone_err)
		return "", false
	}
	return result, true
}
