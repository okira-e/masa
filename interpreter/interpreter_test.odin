package interpreter

import "../lexer"
import "../parser"
import "../syntax"
import "core:mem"
import "core:testing"

@(test)
test_arithmetic :: proc(t: ^testing.T) {
	cases := []struct {
		source:   string,
		expected: f64,
	} {
		{"42", 42},
		{"2 + 3", 5},
		{"7 - 2", 5},
		{"3 * 4", 12},
		{"10 / 4", 2.5},
		{"-5", -5},
		{"2 + 3 * 4", 14},
		{"(2 + 3) * 4", 20},
		{"2 * (1 + 2)", 6},
	}

	for c in cases {
		val, err := run(c.source)
		testing.expectf(t, err == nil, "%s: unexpected error %v", c.source, err)
		n, ok := val.(f64)
		testing.expectf(t, ok, "%s: not a number, got %v", c.source, val)
		testing.expectf(t, n == c.expected, "%s: got %v, expected %v", c.source, n, c.expected)
	}
}

@(test)
test_equality :: proc(t: ^testing.T) {
	cases := []struct {
		source:   string,
		expected: bool,
	} {
		{"1 == 1", true},
		{"1 == 2", false},
		{"1 != 2", true},
		{"1 != 1", false},
		{`"a" == "a"`, true},
		{`"a" == "b"`, false},
		{`1 == "1"`, false},
		{"2 * (1 + 2) == 6", true},
	}

	for c in cases {
		val, err := run(c.source)
		testing.expectf(t, err == nil, "%s: unexpected error %v", c.source, err)
		b, ok := val.(bool)
		testing.expectf(t, ok, "%s: not a bool, got %v", c.source, val)
		testing.expectf(t, b == c.expected, "%s: got %v, expected %v", c.source, b, c.expected)
	}
}

@(test)
test_comparison :: proc(t: ^testing.T) {
	cases := []struct {
		source:   string,
		expected: bool,
	} {
		{"1 < 2", true},
		{"2 < 1", false},
		{"2 <= 2", true},
		{"3 > 2", true},
		{"2 > 3", false},
		{"3 >= 3", true},
	}

	for c in cases {
		val, err := run(c.source)
		testing.expectf(t, err == nil, "%s: unexpected error %v", c.source, err)
		b, ok := val.(bool)
		testing.expectf(t, ok, "%s: not a bool, got %v", c.source, val)
		testing.expectf(t, b == c.expected, "%s: got %v, expected %v", c.source, b, c.expected)
	}
}

@(test)
test_string_literal :: proc(t: ^testing.T) {
	val, err := run(`"hello"`)
	testing.expect(t, err == nil)
	s, ok := val.(string)
	testing.expect(t, ok)
	testing.expectf(t, s == "hello", "got %q", s)
}

@(test)
test_division_by_zero :: proc(t: ^testing.T) {
	_, err := run("1 / 0")
	e, ok := err.?
	testing.expect(t, ok)
	testing.expectf(t, e == .Division_By_Zero, "got %v", e)
}

@(test)
test_type_error :: proc(t: ^testing.T) {
	_, err := run(`1 + "x"`)
	e, ok := err.?
	testing.expect(t, ok)
	testing.expectf(t, e == .Type_Error, "got %v", e)
}

@(test)
test_variables :: proc(t: ^testing.T) {
	cases := []struct {
		source:   string,
		expected: f64,
	} {
		{"x := 5\nx", 5},
		{"x := 5\nx + 1", 6},
		{"pi :: 3\npi * 2", 6},
		{"a := 1\nb := 2\na + b", 3},
	}

	for c in cases {
		val, err := run(c.source)
		testing.expectf(t, err == nil, "%s: unexpected error %v", c.source, err)
		n, ok := val.(f64)
		testing.expectf(t, ok, "%s: not a number, got %v", c.source, val)
		testing.expectf(t, n == c.expected, "%s: got %v, expected %v", c.source, n, c.expected)
	}
}

@(test)
test_redeclaration :: proc(t: ^testing.T) {
	_, err := run("x := 5\nx := 6")
	e, ok := err.?
	testing.expect(t, ok)
	testing.expectf(t, e == .Variable_Redeclaration, "got %v", e)
}

@(test)
test_if_then_runs :: proc(t: ^testing.T) {
	val, err := run("if 1 == 1 { y := 5 }\ny")
	testing.expectf(t, err == nil, "unexpected error %v", err)
	n, ok := val.(f64)
	testing.expect(t, ok)
	testing.expectf(t, n == 5, "got %v", n)
}

@(test)
test_if_else_picks_branch :: proc(t: ^testing.T) {
	val, err := run("if 1 == 2 { y := 1 } else { y := 2 }\ny")
	testing.expectf(t, err == nil, "unexpected error %v", err)
	n, ok := val.(f64)
	testing.expect(t, ok)
	testing.expectf(t, n == 2, "got %v", n)
}

@(test)
test_if_no_else_skips :: proc(t: ^testing.T) {
	val, err := run("if 1 == 2 { y := 1 }\n42")
	testing.expectf(t, err == nil, "unexpected error %v", err)
	n, ok := val.(f64)
	testing.expect(t, ok)
	testing.expectf(t, n == 42, "got %v", n)
}

@(test)
test_else_if_chain :: proc(t: ^testing.T) {
	val, err := run("if 1 == 2 { y := 1 } else if 1 == 1 { y := 2 } else { y := 3 }\ny")
	testing.expectf(t, err == nil, "unexpected error %v", err)
	n, ok := val.(f64)
	testing.expect(t, ok)
	testing.expectf(t, n == 2, "got %v", n)
}

@(test)
test_if_condition_must_be_bool :: proc(t: ^testing.T) {
	_, err := run("if 5 { y := 1 }")
	e, ok := err.?
	testing.expect(t, ok)
	testing.expectf(t, e == .Type_Error, "got %v", e)
}

@(test)
test_logical_and :: proc(t: ^testing.T) {
	cases := []struct {
		source:   string,
		expected: bool,
	} {
		{"1 == 1 and 2 == 2", true},
		{"1 == 1 and 2 == 3", false},
		{"1 == 2 and 2 == 2", false},
	}
	for c in cases {
		val, err := run(c.source)
		testing.expectf(t, err == nil, "%s: unexpected error %v", c.source, err)
		b, ok := val.(bool)
		testing.expectf(t, ok, "%s: not a bool, got %v", c.source, val)
		testing.expectf(t, b == c.expected, "%s: got %v, expected %v", c.source, b, c.expected)
	}
}

@(test)
test_logical_or :: proc(t: ^testing.T) {
	cases := []struct {
		source:   string,
		expected: bool,
	} {
		{"1 == 1 or 2 == 3", true},
		{"1 == 2 or 2 == 2", true},
		{"1 == 2 or 2 == 3", false},
	}
	for c in cases {
		val, err := run(c.source)
		testing.expectf(t, err == nil, "%s: unexpected error %v", c.source, err)
		b, ok := val.(bool)
		testing.expectf(t, ok, "%s: not a bool, got %v", c.source, val)
		testing.expectf(t, b == c.expected, "%s: got %v, expected %v", c.source, b, c.expected)
	}
}

@(test)
test_and_short_circuit :: proc(t: ^testing.T) {
	// undefined_var would error if evaluated; short-circuit means it isn't.
	val, err := run("1 == 2 and undefined_var")
	testing.expectf(t, err == nil, "unexpected error %v", err)
	b, ok := val.(bool)
	testing.expect(t, ok)
	testing.expectf(t, b == false, "got %v", b)
}

@(test)
test_or_short_circuit :: proc(t: ^testing.T) {
	val, err := run("1 == 1 or undefined_var")
	testing.expectf(t, err == nil, "unexpected error %v", err)
	b, ok := val.(bool)
	testing.expect(t, ok)
	testing.expectf(t, b == true, "got %v", b)
}

@(test)
test_logical_strict_left :: proc(t: ^testing.T) {
	_, err := run("1 and 1 == 1")
	e, ok := err.?
	testing.expect(t, ok)
	testing.expectf(t, e == .Type_Error, "got %v", e)
}

@(test)
test_logical_strict_right :: proc(t: ^testing.T) {
	// Left evaluates to true, right is a number → Type_Error
	_, err := run("1 == 1 and 5")
	e, ok := err.?
	testing.expect(t, ok)
	testing.expectf(t, e == .Type_Error, "got %v", e)
}

@(test)
test_logical_precedence :: proc(t: ^testing.T) {
	// `true or (true and false)` = true. If `and` bound looser, result would be false.
	val, err := run("1 == 1 or 1 == 1 and 1 == 2")
	testing.expectf(t, err == nil, "unexpected error %v", err)
	b, ok := val.(bool)
	testing.expect(t, ok)
	testing.expectf(t, b == true, "got %v", b)
}

@(test)
test_undefined_variable :: proc(t: ^testing.T) {
	_, err := run("x")
	e, ok := err.?
	testing.expect(t, ok)
	testing.expectf(t, e == .Undefined_Variable, "got %v", e)
}

@(private)
run :: proc(source: string) -> (Value, Maybe(Eval_Error)) {
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

	interp: Interpreter
	init(&interp, source)
	defer destroy(&interp)

	last_val: Value
	for stmt in stmts {
		if expr_stmt, is_expr := stmt^.(syntax.Expr_Stmt); is_expr {
			val, err := eval(&interp, expr_stmt.expr)
			if err != nil do return nil, err
			last_val = val
		} else {
			err := eval_stmt(&interp, stmt)
			if err != nil do return nil, err
		}
	}

	return last_val, nil
}
