package transpiler

import "core:fmt"
import "../analyzer"
import "../lexer"
import "../parser"
import "core:mem"
import "core:strings"
import "core:testing"

@(private)
USE_STRICT_PREFIX :: "\"use strict\";\n\n"

@(test)
test_let_decl :: proc(t: ^testing.T) {
	expect_js(t, "x := 5", "let x = 5;\n")
}

@(test)
test_const_decl :: proc(t: ^testing.T) {
	expect_js(t, "x :: 5", "const x = 5;\n")
}

@(test)
test_type_alias_decl :: proc(t: ^testing.T) {
	expect_js(t, "x :: string", "")
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

//
// Function declarations
//

@(test)
test_fn_decl_empty :: proc(t: ^testing.T) {
	expect_js(t, "foo :: fn() {}", "function foo() {\n}\n")
}

@(test)
test_fn_decl_erases_parameter_types :: proc(t: ^testing.T) {
	expect_js(
		t,
		"join :: fn(left: string, right: string) {}",
		"function join(left, right) {\n}\n",
	)
}

@(test)
test_fn_decl_erases_return_type :: proc(t: ^testing.T) {
	expect_js(
		t,
		"identity :: fn(value: number) -> number { return value }",
		"function identity(value) {\n  return value;\n}\n",
	)
}

@(test)
test_fn_decl_body :: proc(t: ^testing.T) {
	expect_js(
		t,
		"add :: fn(left: number, right: number) -> number { result := left + right\nreturn result }",
		"function add(left, right) {\n  let result = left + right;\n  return result;\n}\n",
	)
}

@(test)
test_typed_const_fn_decl :: proc(t: ^testing.T) {
	expect_js(
		t,
		"identity: fn(number) -> number : fn(value: number) -> number { return value }",
		"function identity(value) {\n  return value;\n}\n",
	)
}

@(test)
test_async_fn_decl :: proc(t: ^testing.T) {
	expect_js(
		t,
		"load :: async fn(id: number) -> number { return id }",
		"async function load(id) {\n  return id;\n}\n",
	)
}

@(test)
test_fn_decl_bare_return :: proc(t: ^testing.T) {
	expect_js(
		t,
		"stop :: fn() { return }",
		"function stop() {\n  return;\n}\n",
	)
}

@(test)
test_fn_decl_multiple_return_values :: proc(t: ^testing.T) {
	expect_js(
		t,
		`pair :: fn() -> (number, string) { return 1, "one" }`,
		"function pair() {\n  return [1, \"one\"];\n}\n",
	)
}

@(test)
test_fn_decl_branching_returns :: proc(t: ^testing.T) {
	expect_js(
		t,
		"choose :: fn(condition: bool) -> number { if condition { return 1 } else { return 2 } }",
		"function choose(condition) {\n  if (condition) {\n    return 1;\n  } else {\n    return 2;\n  }\n}\n",
	)
}

@(test)
test_fn_stub_emits_nothing :: proc(t: ^testing.T) {
	expect_js(t, "external :: fn(value: number) -> number", "")
}

@(test)
test_async_fn_stub_emits_nothing :: proc(t: ^testing.T) {
	expect_js(t, "external :: async fn(value: number) -> number", "")
}

//
// Function values
//

@(test)
test_mutable_fn_value :: proc(t: ^testing.T) {
	expect_js(
		t,
		"callback := fn() {}",
		"let callback = function () {\n};\n",
	)
}

@(test)
test_mutable_fn_value_with_signature :: proc(t: ^testing.T) {
	expect_js(
		t,
		"identity: fn(number) -> number = fn(value: number) -> number { return value }",
		"let identity = function (value) {\n  return value;\n};\n",
	)
}

@(test)
test_mutable_async_fn_value :: proc(t: ^testing.T) {
	expect_js(
		t,
		"work := async fn() -> number { return 1 }",
		"let work = async function () {\n  return 1;\n};\n",
	)
}

@(test)
test_fn_value_in_multi_declaration :: proc(t: ^testing.T) {
	expect_js(
		t,
		"value, callback := 5, fn() {}",
		"let value = 5, callback = function () {\n};\n",
	)
}

@(test)
test_fn_value_assignment :: proc(t: ^testing.T) {
	expect_js(
		t,
		"callback := fn() {}\ncallback = fn() {}",
		"let callback = function () {\n};\ncallback = function () {\n};\n",
	)
}

//
// Function calls
//

@(test)
test_fn_call_statement :: proc(t: ^testing.T) {
	expect_js(
		t,
		"foo :: fn() {}\nfoo()",
		"function foo() {\n}\nfoo();\n",
	)
}

@(test)
test_fn_call_arguments :: proc(t: ^testing.T) {
	expect_js(
		t,
		`print_pair :: fn(value: number, label: string) {}
print_pair(1 + 2, "three")`,
		"function print_pair(value, label) {\n}\nprint_pair(1 + 2, \"three\");\n",
	)
}

@(test)
test_fn_call_in_declaration :: proc(t: ^testing.T) {
	expect_js(
		t,
		"one :: fn() -> number { return 1 }\nvalue := one()",
		"function one() {\n  return 1;\n}\nlet value = one();\n",
	)
}

@(test)
test_fn_call_in_assignment :: proc(t: ^testing.T) {
	expect_js(
		t,
		"one :: fn() -> number { return 1 }\nvalue := 0\nvalue = one()",
		"function one() {\n  return 1;\n}\nlet value = 0;\nvalue = one();\n",
	)
}

@(test)
test_nested_fn_calls :: proc(t: ^testing.T) {
	expect_js(
		t,
		"identity :: fn(value: number) -> number { return value }\nresult := identity(identity(1))",
		"function identity(value) {\n  return value;\n}\nlet result = identity(identity(1));\n",
	)
}

@(test)
test_fn_call_in_expression :: proc(t: ^testing.T) {
	expect_js(
		t,
		"one :: fn() -> number { return 1 }\nresult := one() + one() * 2",
		"function one() {\n  return 1;\n}\nlet result = one() + one() * 2;\n",
	)
}

@(test)
test_fn_returns_fn_call :: proc(t: ^testing.T) {
	expect_js(
		t,
		"identity :: fn(value: number) -> number { return value }\nforward :: fn(value: number) -> number { return identity(value) }",
		"function identity(value) {\n  return value;\n}\nfunction forward(value) {\n  return identity(value);\n}\n",
	)
}

@(test)
test_mutable_fn_value_call :: proc(t: ^testing.T) {
	expect_js(
		t,
		"identity := fn(value: number) -> number { return value }\nresult := identity(1)",
		"let identity = function (value) {\n  return value;\n};\nlet result = identity(1);\n",
	)
}

@(test)
test_mutable_fn_value_closure :: proc(t: ^testing.T) {
	expect_js(
		t,
		"offset := 2\nadd_offset := fn(value: number) -> number { return value + offset }\nresult := add_offset(3)",
		"let offset = 2;\nlet add_offset = function (value) {\n  return value + offset;\n};\nlet result = add_offset(3);\n",
	)
}

@(test)
test_async_fn_call_without_await :: proc(t: ^testing.T) {
	expect_js(
		t,
		"load :: async fn() -> number { return 1 }\nresult := load()",
		"async function load() {\n  return 1;\n}\nlet result = load();\n",
	)
}

@(test)
test_fn_parameter_trailing_comma_is_dropped :: proc(t: ^testing.T) {
	expect_js(
		t,
		"identity :: fn(value: number,) -> number { return value }",
		"function identity(value) {\n  return value;\n}\n",
	)
}

@(test)
test_fn_call_trailing_comma_is_dropped :: proc(t: ^testing.T) {
	expect_js(
		t,
		"identity :: fn(value: number) -> number { return value }\nresult := identity(1,)",
		"function identity(value) {\n  return value;\n}\nlet result = identity(1);\n",
	)
}

//
// Callbacks
//

@(test)
test_fn_typed_parameter :: proc(t: ^testing.T) {
	expect_js(
		t,
		"apply :: fn(callback: fn(number) -> number, value: number) -> number { return callback(value) }",
		"function apply(callback, value) {\n  return callback(value);\n}\n",
	)
}

@(test)
test_named_fn_passed_as_argument :: proc(t: ^testing.T) {
	expect_js(
		t,
		"apply :: fn(callback: fn(number) -> number, value: number) -> number { return callback(value) }\nidentity :: fn(value: number) -> number { return value }\nresult := apply(identity, 1)",
		"function apply(callback, value) {\n  return callback(value);\n}\nfunction identity(value) {\n  return value;\n}\nlet result = apply(identity, 1);\n",
	)
}

@(test)
test_fn_literal_passed_as_argument :: proc(t: ^testing.T) {
	expect_js(
		t,
		"apply :: fn(callback: fn(number) -> number, value: number) -> number { return callback(value) }\nresult := apply(fn(value: number) -> number { return value }, 1)",
		"function apply(callback, value) {\n  return callback(value);\n}\nlet result = apply(function (value) {\n  return value;\n}, 1);\n",
	)
}

@(test)
test_fn_returns_fn_value :: proc(t: ^testing.T) {
	expect_js(
		t,
		"make_identity :: fn() -> fn(number) -> number { return fn(value: number) -> number { return value } }\nidentity := make_identity()\nresult := identity(1)",
		"function make_identity() {\n  return function (value) {\n    return value;\n  };\n}\nlet identity = make_identity();\nlet result = identity(1);\n",
	)
}

//
// Multiple return values
//

@(test)
test_multi_return_call_destructures_mutable_decl :: proc(t: ^testing.T) {
	expect_js(
		t,
		`pair :: fn() -> (number, string) { return 1, "one" }
number_value, string_value := pair()`,
		"function pair() {\n  return [1, \"one\"];\n}\nlet [number_value, string_value] = pair();\n",
	)
}

@(test)
test_multi_return_call_destructures_const_decl :: proc(t: ^testing.T) {
	expect_js(
		t,
		`pair :: fn() -> (number, string) { return 1, "one" }
number_value, string_value :: pair()`,
		"function pair() {\n  return [1, \"one\"];\n}\nconst [number_value, string_value] = pair();\n",
	)
}

@(test)
test_multi_return_call_destructures_assignment :: proc(t: ^testing.T) {
	expect_js(
		t,
		`pair :: fn() -> (number, string) { return 1, "one" }
number_value := 0
string_value := ""
number_value, string_value = pair()`,
		"function pair() {\n  return [1, \"one\"];\n}\nlet number_value = 0;\nlet string_value = \"\";\n[number_value, string_value] = pair();\n",
	)
}

@(test)
test_multi_return_call_forwarded :: proc(t: ^testing.T) {
	expect_js(
		t,
		`pair :: fn() -> (number, string) { return 1, "one" }
forward :: fn() -> (number, string) { return pair() }`,
		"function pair() {\n  return [1, \"one\"];\n}\nfunction forward() {\n  return pair();\n}\n",
	)
}

//
// Hoisting and names
//

@(test)
test_const_fn_decl_is_hoisted :: proc(t: ^testing.T) {
	expect_js(
		t,
		"foo()\nfoo :: fn() {}",
		"foo();\nfunction foo() {\n}\n",
	)
}

@(test)
test_const_fn_dependency_is_hoisted :: proc(t: ^testing.T) {
	expect_js(
		t,
		"first :: fn() -> number { return second() }\nsecond :: fn() -> number { return 2 }\nresult := first()",
		"function first() {\n  return second();\n}\nfunction second() {\n  return 2;\n}\nlet result = first();\n",
	)
}

@(test)
test_recursive_fn_decl :: proc(t: ^testing.T) {
	expect_js(
		t,
		"countdown :: fn(value: number) -> number { if value == 0 { return 0 }\nreturn countdown(value - 1) }",
		"function countdown(value) {\n  if (value === 0) {\n    return 0;\n  }\n  return countdown(value - 1);\n}\n",
	)
}

@(test)
test_reserved_fn_name_and_parameter_are_mangled :: proc(t: ^testing.T) {
	expect_js(
		t,
		"class :: fn(default: number) -> number { return default }\nresult := class(1)",
		"function $class($default) {\n  return $default;\n}\nlet result = $class(1);\n",
	)
}

@(test)
test_reserved_fn_call_statement_is_mangled :: proc(t: ^testing.T) {
	expect_js(
		t,
		"class :: fn() {}\nclass()",
		"function $class() {\n}\n$class();\n",
	)
}

@(test)
test_reserved_mutable_fn_name_is_mangled :: proc(t: ^testing.T) {
	expect_js(
		t,
		"class := fn() {}\nclass()",
		"let $class = function () {\n};\n$class();\n",
	)
}

@(private)
expect_js :: proc(t: ^testing.T, source: string, expected: string, loc := #caller_location) {
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
	if err := analyzer.analyze(&a, stmts[:]); err != nil {
		testing.expectf(t, false, "analyzer failed: %v", err, loc = loc)
		return
	}

	tr: Transpiler
	init(&tr, source)
	defer destroy(&tr)
	got := transpile(&tr, stmts[:])

	// Strip the "use strict"
	got = strings.trim_prefix(got, USE_STRICT_PREFIX)

	testing.expectf(
		t,
		got == expected,
		"%s:\ngot:      %q\nexpected: %q",
		source,
		got,
		expected,
		loc = loc
	)
}
