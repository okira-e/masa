package transpiler

import "../analyzer"
import "../lexer"
import "../parser"
import "core:mem"
import "core:testing"

@(test)
test_let_decl :: proc(t: ^testing.T) {
	expect_js(t, "x := 5", "let x = 5;\n")
}

@(test)
test_const_decl :: proc(t: ^testing.T) {
	expect_js(t, "x :: 5", "const x = 5;\n")
}

@(test)
test_assignment :: proc(t: ^testing.T) {
	expect_js(t, "x := 5\nx = 10", "let x = 5;\nx = 10;\n")
}

@(test)
test_arithmetic :: proc(t: ^testing.T) {
	expect_js(t, "1 + 2 * 3", "1 + 2 * 3;\n")
}

@(test)
test_grouping :: proc(t: ^testing.T) {
	expect_js(t, "(1 + 2) * 3", "(1 + 2) * 3;\n")
}

@(test)
test_unary :: proc(t: ^testing.T) {
	expect_js(t, "x := -5", "let x = -5;\n")
}

@(test)
test_strict_equality :: proc(t: ^testing.T) {
	expect_js(t, "1 == 2", "1 === 2;\n")
}

@(test)
test_strict_inequality :: proc(t: ^testing.T) {
	expect_js(t, "1 != 2", "1 !== 2;\n")
}

@(test)
test_comparison :: proc(t: ^testing.T) {
	expect_js(t, "1 <= 2", "1 <= 2;\n")
}

@(test)
test_logical_and :: proc(t: ^testing.T) {
	expect_js(t, "1 == 1 and 2 == 2", "1 === 1 && 2 === 2;\n")
}

@(test)
test_logical_or :: proc(t: ^testing.T) {
	expect_js(t, "1 == 1 or 2 == 2", "1 === 1 || 2 === 2;\n")
}

@(test)
test_string_literal :: proc(t: ^testing.T) {
	expect_js(t, `s := "hi"`, "let s = \"hi\";\n")
}

@(test)
test_if :: proc(t: ^testing.T) {
	expect_js(
		t,
		"y := 0\nif 1 == 1 { y = 5 }",
		"let y = 0;\nif (1 === 1) {\n  y = 5;\n}\n",
	)
}

@(test)
test_if_else :: proc(t: ^testing.T) {
	expect_js(
		t,
		"y := 0\nif 1 == 2 { y = 1 } else { y = 2 }",
		"let y = 0;\nif (1 === 2) {\n  y = 1;\n} else {\n  y = 2;\n}\n",
	)
}

@(test)
test_else_if_chain :: proc(t: ^testing.T) {
	expect_js(
		t,
		"y := 0\nif 1 == 2 { y = 1 } else if 1 == 1 { y = 2 } else { y = 3 }",
		"let y = 0;\nif (1 === 2) {\n  y = 1;\n} else if (1 === 1) {\n  y = 2;\n} else {\n  y = 3;\n}\n",
	)
}

@(test)
test_bare_block :: proc(t: ^testing.T) {
	expect_js(t, "{ x := 5 }", "{\n  let x = 5;\n}\n")
}

@(test)
test_nested_blocks :: proc(t: ^testing.T) {
	expect_js(
		t,
		"if 1 == 1 { if 2 == 2 { x := 5 } }",
		"if (1 === 1) {\n  if (2 === 2) {\n    let x = 5;\n  }\n}\n",
	)
}

@(test)
test_reserved_word_mangled :: proc(t: ^testing.T) {
	// `class` is a JS reserved word; masa allows it as an identifier.
	expect_js(t, "class := 5", "let $class = 5;\n")
}

@(test)
test_reserved_word_mangled_consistently :: proc(t: ^testing.T) {
	// Declaration and reference both get the same mangled name.
	expect_js(t, "class := 5\nclass = 10", "let $class = 5;\n$class = 10;\n")
}

@(test)
test_underscore_prefix_not_mangled :: proc(t: ^testing.T) {
	// `_class` is not a JS reserved word; emit as-is. No collision with
	// the mangled `class` since `$` is the prefix.
	expect_js(t, "_class := 5", "let _class = 5;\n")
}

@(test)
test_comment_dropped :: proc(t: ^testing.T) {
	// Comments don't appear in the AST, so they're absent from the output.
	expect_js(t, "x := 5 // why this value", "let x = 5;\n")
}

@(private)
expect_js :: proc(t: ^testing.T, source: string, expected: string) {
	arena: mem.Dynamic_Arena
	mem.dynamic_arena_init(&arena)
	defer mem.dynamic_arena_destroy(&arena)
	arena_alloc := mem.dynamic_arena_allocator(&arena)

	l := lexer.Lexer{}
	lexer.init(&l, arena_alloc)
	tokens, _ := lexer.scan(&l, source)
	defer delete(tokens)

	p: parser.Parser
	parser.init(&p, tokens[:], arena_alloc)
	stmts, _ := parser.parse(&p)
	defer delete(stmts)

	a: analyzer.Analyzer
	analyzer.init(&a, source)
	defer analyzer.destroy(&a)
	if aerr := analyzer.analyze(&a, stmts[:]); aerr != nil {
		testing.expectf(t, false, "%s: analyzer failed: %v", source, aerr)
		return
	}

	tr: Transpiler
	init(&tr, source)
	defer destroy(&tr)
	got := transpile(&tr, stmts[:])

	testing.expectf(
		t,
		got == expected,
		"%s:\ngot:      %q\nexpected: %q",
		source,
		got,
		expected,
	)
}
