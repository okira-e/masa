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

@(test)
test_typed_decl_mutable_with_value :: proc(t: ^testing.T) {
	// x : number = 5  →  declared, mutable, value present. Using x is fine.
	err := check("x : number = 5\nx + 1")
	testing.expectf(t, err == nil, "unexpected error: %v", err)
}

@(test)
test_typed_decl_constant_with_value :: proc(t: ^testing.T) {
	// x : number : 5  →  declared, constant. Reading is fine.
	err := check("x : number : 5\nx + 1")
	testing.expectf(t, err == nil, "unexpected error: %v", err)
}

@(test)
test_typed_decl_mutable_rejects_initializer_type_mismatch :: proc(t: ^testing.T) {
	err := check("x : number = \"hello\"")
	e, ok := err.?
	testing.expect(t, ok)
	testing.expectf(t, e.kind == .Type_Mismatch_On_Declaration, "got %v", e.kind)
}

@(test)
test_typed_decl_constant_rejects_initializer_type_mismatch :: proc(t: ^testing.T) {
	err := check("x : bool : 123")
	e, ok := err.?
	testing.expect(t, ok)
	testing.expectf(t, e.kind == .Type_Mismatch_On_Declaration, "got %v", e.kind)
}

@(test)
test_typed_decl_no_value :: proc(t: ^testing.T) {
	// x : number  →  declared but uninitialized. Analyzer accepts since the
	// name is in scope; runtime init is a separate concern.
	err := check("x : number\nx + 1")
	testing.expectf(t, err == nil, "unexpected error: %v", err)
}

@(test)
test_typed_constant_cannot_be_reassigned :: proc(t: ^testing.T) {
	err := check("x : number : 5\nx = 10")
	e, ok := err.?
	testing.expect(t, ok)
	testing.expectf(t, e.kind == .Variable_Constant, "got %v", e.kind)
}

@(test)
test_typed_mutable_can_be_reassigned :: proc(t: ^testing.T) {
	err := check("x : number = 5\nx = 10")
	testing.expectf(t, err == nil, "unexpected error: %v", err)
}

@(test)
test_typed_decl_no_value_can_be_assigned_matching_type :: proc(t: ^testing.T) {
	err := check("x : number\nx = 10")
	testing.expectf(t, err == nil, "unexpected error: %v", err)
}

@(test)
test_typed_mutable_rejects_assignment_type_mismatch :: proc(t: ^testing.T) {
	err := check("x : number = 5\nx = false")
	e, ok := err.?
	testing.expect(t, ok)
	testing.expectf(t, e.kind == .Type_Mismatch_On_Assignment, "got %v", e.kind)
}

@(test)
test_untyped_constant_cannot_be_reassigned :: proc(t: ^testing.T) {
	// Regression: ensure the untyped `::` path also records constant correctly.
	err := check("pi :: 3\npi = 5")
	e, ok := err.?
	testing.expect(t, ok)
	testing.expectf(t, e.kind == .Variable_Constant, "got %v", e.kind)
}

@(test)
test_untyped_mutable_can_be_reassigned :: proc(t: ^testing.T) {
	err := check("x := 5\nx = 10")
	testing.expectf(t, err == nil, "unexpected error: %v", err)
}

@(test)
test_untyped_mutable_rejects_assignment_type_mismatch :: proc(t: ^testing.T) {
	err := check("x := 5\nx = \"hello\"")
	e, ok := err.?
	testing.expect(t, ok)
	testing.expectf(t, e.kind == .Type_Mismatch_On_Assignment, "got %v", e.kind)
}

@(test)
test_typed_redeclaration :: proc(t: ^testing.T) {
	err := check("x : number = 5\nx : number = 10")
	e, ok := err.?
	testing.expect(t, ok)
	testing.expectf(t, e.kind == .Variable_Redeclaration, "got %v", e.kind)
}

@(test)
test_typed_undefined_identifier :: proc(t: ^testing.T) {
	err := check("x : User = 5")
	e, ok := err.?
	testing.expect(t, ok)
	testing.expectf(t, e.kind == .Undefined_Type, "got %v", e.kind)
}

@(test)
test_variable_in_type_position :: proc(t: ^testing.T) {
	// `y` is a variable, not a type — using it in a type annotation fails.
	err := check("y := 5\nx : y = 10")
	e, ok := err.?
	testing.expect(t, ok)
	testing.expectf(t, e.kind == .Variable_In_Type_Position, "got %v", e.kind)
}

@(test)
test_type_in_value_position :: proc(t: ^testing.T) {
	// Type name used as a value.
	err := check("x := number")
	e, ok := err.?
	testing.expect(t, ok)
	testing.expectf(t, e.kind == .Type_In_Value_Position, "got %v", e.kind)
}

@(test)
test_arithmetic_requires_numbers :: proc(t: ^testing.T) {
	err := check("x := 1 + \"hi\"")
	e, ok := err.?
	testing.expect(t, ok)
	testing.expectf(t, e.kind == .Operator_Type_Mismatch, "got %v", e.kind)
}

@(test)
test_comparison_requires_numbers :: proc(t: ^testing.T) {
	err := check("x := true < 3")
	e, ok := err.?
	testing.expect(t, ok)
	testing.expectf(t, e.kind == .Operator_Type_Mismatch, "got %v", e.kind)
}

@(test)
test_equality_requires_same_types :: proc(t: ^testing.T) {
	err := check("x := 1 == \"hi\"")
	e, ok := err.?
	testing.expect(t, ok)
	testing.expectf(t, e.kind == .Operator_Type_Mismatch, "got %v", e.kind)
}

@(test)
test_unary_minus_requires_number :: proc(t: ^testing.T) {
	err := check("x := -true")
	e, ok := err.?
	testing.expect(t, ok)
	testing.expectf(t, e.kind == .Operator_Type_Mismatch, "got %v", e.kind)
}

@(test)
test_unary_bang_requires_bool :: proc(t: ^testing.T) {
	err := check("x := !5")
	e, ok := err.?
	testing.expect(t, ok)
	testing.expectf(t, e.kind == .Operator_Type_Mismatch, "got %v", e.kind)
}

@(test)
test_logical_requires_bools :: proc(t: ^testing.T) {
	err := check("x := true and 5")
	e, ok := err.?
	testing.expect(t, ok)
	testing.expectf(t, e.kind == .Operator_Type_Mismatch, "got %v", e.kind)
}

@(test)
test_if_condition_must_be_bool :: proc(t: ^testing.T) {
	err := check("if 5 { }")
	e, ok := err.?
	testing.expect(t, ok)
	testing.expectf(t, e.kind == .Condition_Not_Bool, "got %v", e.kind)
}

@(test)
test_type_alias_accepted :: proc(t: ^testing.T) {
	// `Num` aliases `number` and is identity-equal, so a number literal fits.
	err := check("Num :: number\nx : Num = 5")
	testing.expectf(t, err == nil, "unexpected error: %v", err)
}

@(test)
test_type_alias_chain :: proc(t: ^testing.T) {
	err := check("Num :: number\nAgain :: Num\nx : Again = 5")
	testing.expectf(t, err == nil, "unexpected error: %v", err)
}

@(test)
test_shadow_builtin_then_use_literal :: proc(t: ^testing.T) {
	// `string :: number` shadows the universe-scope `string` in package scope.
	// The string literal still points to the universe built-in via the captured
	// handle, so its type is identity-different from the shadowed `string`.
	err := check("string :: number\nx : string = \"hi\"")
	e, ok := err.?
	testing.expect(t, ok)
	testing.expectf(t, e.kind == .Type_Mismatch_On_Declaration, "got %v", e.kind)
}

@(test)
test_shadow_builtin_then_use_matching_value :: proc(t: ^testing.T) {
	// After `string :: number`, `x : string = 5` is valid: `string` now means number.
	err := check("string :: number\nx : string = 5")
	testing.expectf(t, err == nil, "unexpected error: %v", err)
}

@(test)
test_string_literal_typecheck :: proc(t: ^testing.T) {
	err := check("x : string = \"hi\"")
	testing.expectf(t, err == nil, "unexpected error: %v", err)
}

@(test)
test_bool_literal_typecheck :: proc(t: ^testing.T) {
	err := check("x : bool = true")
	testing.expectf(t, err == nil, "unexpected error: %v", err)
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
