package analyzer

import "../lexer"
import "../parser"
import "core:mem"
import "core:testing"

@(test)
test_undefined_variable :: proc(t: ^testing.T) {
	err := check("x")
	e, ok := err.?
	testing.expect(t, ok)
	testing.expectf(t, e.kind == .Undefined_Variable, "got %v", e.kind)
}

@(test)
test_undefined_in_expression :: proc(t: ^testing.T) {
	err := check("x := 5\ny + 1")
	e, ok := err.?
	testing.expect(t, ok)
	testing.expectf(t, e.kind == .Undefined_Variable, "got %v", e.kind)
}

@(test)
test_self_reference_in_decl :: proc(t: ^testing.T) {
	// RHS is checked before the name is added → `x` not yet defined.
	err := check("x := x + 1")
	e, ok := err.?
	testing.expect(t, ok)
	testing.expectf(t, e.kind == .Undefined_Variable, "got %v", e.kind)
}

@(test)
test_redeclaration :: proc(t: ^testing.T) {
	err := check("x := 5\nx := 6")
	e, ok := err.?
	testing.expect(t, ok)
	testing.expectf(t, e.kind == .Variable_Redeclaration, "got %v", e.kind)
}

@(test)
test_redeclaration_across_kinds :: proc(t: ^testing.T) {
	err := check("x := 5\nx :: 6")
	e, ok := err.?
	testing.expect(t, ok)
	testing.expectf(t, e.kind == .Variable_Redeclaration, "got %v", e.kind)
}

@(test)
test_valid_program :: proc(t: ^testing.T) {
	err := check("x := 5\ny := x + 1\nif y == 6 { z := y }")
	testing.expectf(t, err == nil, "unexpected error %v", err)
}

@(test)
test_ident_in_if_condition :: proc(t: ^testing.T) {
	err := check("if missing == 1 { }")
	e, ok := err.?
	testing.expect(t, ok)
	testing.expectf(t, e.kind == .Undefined_Variable, "got %v", e.kind)
}

@(test)
test_ident_in_block :: proc(t: ^testing.T) {
	err := check("{ missing + 1 }")
	e, ok := err.?
	testing.expect(t, ok)
	testing.expectf(t, e.kind == .Undefined_Variable, "got %v", e.kind)
}

@(test)
test_ident_declared_in_block :: proc(t: ^testing.T) {
	source := "{ a := 5 }\na + 1"
	err := check(source)
	e, ok := err.?
	testing.expect(t, ok)
	testing.expectf(t, e.kind == .Undefined_Variable, "got %v", e.kind)
}

@(private)
check :: proc(source: string) -> Maybe(Analyzer_Error) {
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

	a: Analyzer
	init(&a, source)
	defer destroy(&a)
	return analyze(&a, stmts[:])
}
