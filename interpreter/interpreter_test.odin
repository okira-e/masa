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
	val, err := run("x := 5\nx := 6\nx")
	testing.expect(t, err == nil)
	n, ok := val.(f64)
	testing.expect(t, ok)
	testing.expectf(t, n == 6, "got %v", n)
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
		switch s in stmt {
		case syntax.Expr_Stmt:
			val, err := eval(&interp, s.expr)
			if err != nil do return nil, err
			last_val = val
		case syntax.Ident_Decl_Stmt:
			val, err := eval(&interp, s.value)
			if err != nil do return nil, err
			name := source[s.name.lexeme_start:s.name.lexeme_end]
			interp.env[name] = val
		}
	}

	return last_val, nil
}
