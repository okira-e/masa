package interpreter

import "../lexer"
import "../parser"
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
	exprs, _ := parser.parse(&p)
	defer delete(exprs)

	return eval(source, exprs[0])
}
