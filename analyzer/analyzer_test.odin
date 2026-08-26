package analyzer

import "../lexer"
import "../parser"
import "core:mem"
import "core:strings"
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
test_typed_constant_cannot_be_reassigned_in_block :: proc(t: ^testing.T) {
	err := check("x : number : 5\n{ x = 10 }")
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
test_error_caret_preserves_tab_alignment :: proc(t: ^testing.T) {
	source := "foo :: fn() -> string {\n\treturn\n}"
	err := check(source)
	e, ok := err.?
	testing.expect(t, ok, "expected return count mismatch")
	if !ok do return

	formatted := format_error(e, source)
	defer delete(formatted)

	testing.expectf(
		t,
		strings.contains(formatted, "  | \t^^^^^^"),
		"caret line does not preserve tab indentation:\n%s",
		formatted,
	)
}

@(test)
test_error_message_uses_name_payload_after_analyzer_destroy :: proc(t: ^testing.T) {
	expect_message(t, "missing()", "undefined function 'missing'")
}

@(test)
test_error_message_uses_count_payload_after_analyzer_destroy :: proc(t: ^testing.T) {
	expect_message(t, "foo :: fn(a: number) {}\nfoo()", "expected 1 argument, received 0")
}

@(test)
test_target_count_message_uses_expanded_value_count :: proc(t: ^testing.T) {
	expect_message(
		t,
		"pair :: fn() -> (number, string) { return 1, \"ok\" }\nx := pair()",
		"expected 1 values for assignment targets, received 2",
	)
}

@(test)
test_error_message_uses_argument_index_payload :: proc(t: ^testing.T) {
	expect_message(
		t,
		"foo :: fn(a: number, b: string) {}\nfoo(1, 2)",
		"argument 2 does not match its parameter type",
	)
}

@(test)
test_error_message_uses_operator_span_payload :: proc(t: ^testing.T) {
	expect_message(t, "x := true + 1", "operator '+' requires number operands")
}

@(test)
test_type_in_value_error_uses_reference_span :: proc(t: ^testing.T) {
	source := "x := number"
	err := check(source)
	e, ok := err.?
	testing.expect(t, ok, "expected type-in-value-position error")
	if !ok do return

	testing.expectf(
		t,
		source[e.span.start:e.span.end] == "number",
		"error span points to %q",
		source[e.span.start:e.span.end],
	)
	message := error_message(e, source)
	defer delete(message)
	testing.expectf(t, message == "type 'number' cannot be used as a value", "got %q", message)
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
	// `y` is a variable, not a type - using it in a type annotation fails.
	err := check("y := 5\nx : y = 10")
	e, ok := err.?
	testing.expect(t, ok)
	testing.expectf(t, e.kind == .Value_Used_As_Type, "got %v", e.kind)
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

//
// Declaring functions - valid
//

@(test)
test_fn_decl_no_args_no_returns :: proc(t: ^testing.T) {
	expect_ok(t, "foo :: fn() {}")
}

@(test)
test_fn_decl_with_args :: proc(t: ^testing.T) {
	expect_ok(t, "foo :: fn(x: number, y: string) {}")
}

@(test)
test_fn_decl_single_return :: proc(t: ^testing.T) {
	expect_ok(t, "foo :: fn() -> number { return 5 }")
}

@(test)
test_fn_decl_multiple_returns :: proc(t: ^testing.T) {
	expect_ok(t, "foo :: fn() -> (number, string) { return 5, \"hi\" }")
}

@(test)
test_fn_decl_uses_arg_in_body :: proc(t: ^testing.T) {
	// Parameters are in scope inside the body.
	expect_ok(t, "foo :: fn(x: number) -> number { return x }")
}

@(test)
test_mutable_fn_value_binding :: proc(t: ^testing.T) {
	// `:=` binds a value: a single-name fn is a mutable variable holding a
	// function value, not a hoisted function declaration. Still valid to declare.
	expect_ok(t, "foo := fn() {}")
}

@(test)
test_typed_constant_fn_decl :: proc(t: ^testing.T) {
	expect_ok(t, "foo: fn() -> number : fn() -> number { return 5 }")
}

@(test)
test_typed_constant_async_fn_decl :: proc(t: ^testing.T) {
	expect_ok(
		t,
		"load: async fn(number) -> number : async fn(id: number) -> number { return id }",
	)
}

@(test)
test_typed_constant_fn_decl_signature_mismatches :: proc(t: ^testing.T) {
	expect_fn_decl_signature_mismatch(
		t,
		"foo: number : fn() {}",
		.Declared_Type,
	)
	expect_fn_decl_signature_mismatch(
		t,
		"foo: fn(number) -> number : fn() -> number { return 1 }",
		.Parameter_Count,
		expected = 1,
		actual = 0,
	)
	expect_fn_decl_signature_mismatch(
		t,
		"foo: fn(number) -> number : fn(value: string) -> number { return 1 }",
		.Parameter_Type,
		index = 0,
	)
	expect_fn_decl_signature_mismatch(
		t,
		"foo: fn() -> number : fn() {}",
		.Return_Count,
		expected = 1,
		actual = 0,
	)
	expect_fn_decl_signature_mismatch(
		t,
		"foo: fn() -> (number, string) : fn() -> number { return 1 }",
		.Return_Count,
		expected = 2,
		actual = 1,
	)
	expect_fn_decl_signature_mismatch(
		t,
		"foo: fn() -> number : fn() -> string { return \"wrong\" }",
		.Return_Type,
		index = 0,
	)
	expect_fn_decl_signature_mismatch(
		t,
		"foo: fn() -> number : async fn() -> number { return 1 }",
		.Async,
	)
}

@(test)
test_typed_mutable_fn_value_binding :: proc(t: ^testing.T) {
	// The typed `=` form is mutable, so it too is a value binding, not a decl.
	expect_ok(t, "foo: fn() -> number = fn() -> number { return 5 }")
}

@(test)
test_fn_decl_stub :: proc(t: ^testing.T) {
	// Signature-only forward declaration: no body, so no missing-return check.
	expect_ok(t, "foo :: fn()")
}

@(test)
test_fn_decl_stub_with_return_type :: proc(t: ^testing.T) {
	expect_ok(t, "foo :: fn() -> number")
}

@(test)
test_void_fn_bare_return :: proc(t: ^testing.T) {
	// A bare `return` in a function with no return types is valid.
	expect_ok(t, "foo :: fn() { return }")
}

@(test)
test_async_fn_decl :: proc(t: ^testing.T) {
	expect_ok(t, "foo :: async fn() {}")
}

@(test)
test_async_fn_decl_with_args_and_return :: proc(t: ^testing.T) {
	expect_ok(t, "foo :: async fn(x: number) -> number { return x }")
}

@(test)
test_async_fn_stub :: proc(t: ^testing.T) {
	expect_ok(t, "foo :: async fn()")
}

//
// Declaring functions - errors
//

@(test)
test_duplicate_fn_definition :: proc(t: ^testing.T) {
	expect_kind(t, "foo :: fn() {}\nfoo :: fn() {}", .Duplicate_Fn_Definition)
}

@(test)
test_duplicate_fn_argument :: proc(t: ^testing.T) {
	expect_kind(t, "foo :: fn(x: number, x: number) {}", .Duplicate_Fn_Argument_Definition)
}

@(test)
test_fn_undefined_arg_type :: proc(t: ^testing.T) {
	expect_kind(t, "foo :: fn(x: Bogus) {}", .Undefined_Type)
}

@(test)
test_fn_value_used_as_arg_type :: proc(t: ^testing.T) {
	expect_kind(t, "n := 5\nfoo :: fn(x: n) {}", .Value_Used_As_Type)
}

@(test)
test_fn_undefined_return_type :: proc(t: ^testing.T) {
	expect_kind(t, "foo :: fn() -> Bogus { return 5 }", .Undefined_Type)
}

@(test)
test_fn_value_used_as_return_type :: proc(t: ^testing.T) {
	expect_kind(t, "n := 5\nfoo :: fn() -> n { return 5 }", .Value_Used_As_Type)
}

@(test)
test_const_fn_cannot_be_reassigned :: proc(t: ^testing.T) {
	// `::` is constant, so a declared function cannot be reassigned.
	expect_kind(t, "foo :: fn() {}\nfoo = fn() {}", .Variable_Constant)
}

@(test)
test_typed_constant_fn_cannot_be_reassigned :: proc(t: ^testing.T) {
	// The typed-constant (`:`) form is equally constant.
	expect_kind(t, "foo: fn() : fn() {}\nfoo = fn() {}", .Variable_Constant)
}

//
// Return-flow
//

// -- Valids

@(test)
test_return_all_branches_return :: proc(t: ^testing.T) {
	// Both the then and else branches return → every path is covered.
	expect_ok(t, "foo :: fn() -> number { if true { return 10 } else { return 5 } }")
}

@(test)
test_return_if_then_trailing_return :: proc(t: ^testing.T) {
	// The if returns; the fall-through is covered by a trailing return.
	expect_ok(t, "foo :: fn() -> number { if true { return 10 }\nreturn 5 }")
}

@(test)
test_return_fn_literal :: proc(t: ^testing.T) {
	expect_ok(
		t,
		"make_identity :: fn() -> fn(number) -> number { return fn(value: number) -> number { return value } }",
	)
}

@(test)
test_return_after_nested_fn_literal :: proc(t: ^testing.T) {
	expect_ok(
		t,
		"foo :: fn() -> number { nested := fn() -> number { return 1 }\nreturn 2 }",
	)
}

// -- Errors

@(test)
test_missing_return :: proc(t: ^testing.T) {
	// Declares a return type but the body never returns.
	expect_kind(t, "foo :: fn() -> number {}", .Missing_Return)
}

@(test)
test_missing_return_on_some_paths :: proc(t: ^testing.T) {
	// `if` returns, but the implicit else path falls through without a return.
	expect_kind(t, "foo :: fn() -> number { if true { return 1 } }", .Missing_Return)
}

@(test)
test_missing_return_empty_else :: proc(t: ^testing.T) {
	// An else exists but is empty, so that path falls through without returning.
	expect_kind(t, "foo :: fn() -> number { if true { return 1 } else {} }", .Missing_Return)
}

@(test)
test_return_type_mismatch :: proc(t: ^testing.T) {
	expect_kind(t, "foo :: fn() -> number { return \"hi\" }", .Return_Type_Mismatch)
}

@(test)
test_return_undefined_variable :: proc(t: ^testing.T) {
	// The return expression is resolved/typed before any return-type comparison,
	// so an unknown name is Undefined_Variable, not Return_Type_Mismatch.
	expect_kind(t, "foo :: fn() -> number { return missing }", .Undefined_Variable)
}

@(test)
test_return_too_few_values :: proc(t: ^testing.T) {
	expect_kind(t, "foo :: fn() -> (number, number) { return 5 }", .Return_Count_Mismatch)
}

@(test)
test_return_too_many_values :: proc(t: ^testing.T) {
	expect_kind(t, "foo :: fn() -> number { return 5, 6 }", .Return_Count_Mismatch)
}

@(test)
test_return_value_from_void_fn :: proc(t: ^testing.T) {
	expect_kind(t, "foo :: fn() { return 5 }", .Return_Count_Mismatch)
}

@(test)
test_bare_return_with_return_type :: proc(t: ^testing.T) {
	expect_kind(t, "foo :: fn() -> number { return }", .Return_Count_Mismatch)
}

@(test)
test_return_outside_function :: proc(t: ^testing.T) {
	expect_kind(t, "return 5", .Return_Outside_Function)
}

//
// Function bodies check
//

@(test)
test_fn_body_undefined_variable :: proc(t: ^testing.T) {
	expect_kind(t, "foo :: fn() { y + 1 }", .Undefined_Variable)
}

@(test)
test_fn_body_type_error :: proc(t: ^testing.T) {
	expect_kind(t, "foo :: fn() { x := 1 + \"hi\" }", .Operator_Type_Mismatch)
}

@(test)
test_function_literal_captures_outer_argument_and_local :: proc(t: ^testing.T) {
	expect_ok(
		t,
		"make_adder :: fn(base: number) -> fn(number) -> number { offset := 1\nreturn fn(value: number) -> number { return base + offset + value } }",
	)
}

@(test)
test_local_declaration_cannot_redeclare_function_argument :: proc(t: ^testing.T) {
	expect_kind(
		t,
		"foo :: fn(value: number) { value := 1 }",
		.Variable_Redeclaration,
	)
}

@(test)
test_function_argument_cannot_be_assigned :: proc(t: ^testing.T) {
	expect_kind(t, "foo :: fn(value: number) { value = 1 }", .Variable_Constant)
}

@(test)
test_function_arguments_are_constant_for_all_primitive_types :: proc(t: ^testing.T) {
	expect_kind(t, `foo :: fn(value: string) { value = "changed" }`, .Variable_Constant)
	expect_kind(t, "foo :: fn(value: bool) { value = false }", .Variable_Constant)
}

@(test)
test_function_typed_argument_cannot_be_assigned :: proc(t: ^testing.T) {
	expect_kind(
		t,
		"foo :: fn(callback: fn()) { callback = fn() {} }",
		.Variable_Constant,
	)
	expect_kind(
		t,
		"foo :: fn(callback: async fn()) { callback = async fn() {} }",
		.Variable_Constant,
	)
}

@(test)
test_aliased_type_argument_cannot_be_assigned :: proc(t: ^testing.T) {
	expect_kind(
		t,
		"User :: number\nfoo :: fn(user: User) { user = 1 }",
		.Variable_Constant,
	)
}

@(test)
test_function_argument_cannot_be_assigned_in_nested_block :: proc(t: ^testing.T) {
	expect_kind(
		t,
		"foo :: fn(value: number) { { value = 1 } }",
		.Variable_Constant,
	)
}

@(test)
test_captured_function_argument_cannot_be_assigned :: proc(t: ^testing.T) {
	expect_kind(
		t,
		"outer :: fn(value: number) { mutate :: fn() { value = 1 } }",
		.Variable_Constant,
	)
}

@(test)
test_function_argument_cannot_be_a_multi_assignment_target :: proc(t: ^testing.T) {
	expect_kind(
		t,
		"foo :: fn(value: number) { local := 0\nlocal, value = 1, 2 }",
		.Variable_Constant,
	)
}

@(test)
test_async_function_argument_cannot_be_assigned :: proc(t: ^testing.T) {
	expect_kind(
		t,
		"foo :: async fn(value: number) { value = 1 }",
		.Variable_Constant,
	)
}

@(test)
test_function_literal_argument_cannot_be_assigned :: proc(t: ^testing.T) {
	expect_kind(
		t,
		"callback := fn(value: number) { value = 1 }",
		.Variable_Constant,
	)
}

@(test)
test_function_value_does_not_escape_block :: proc(t: ^testing.T) {
	expect_kind(t, "{ callback := fn() {} }\ncallback()", .Undefined_Variable)
}

@(test)
test_duplicate_name_in_multi_declaration :: proc(t: ^testing.T) {
	expect_kind(t, "value, value := 1, 2", .Variable_Redeclaration)
}

@(test)
test_same_function_name_allowed_in_sibling_blocks :: proc(t: ^testing.T) {
	expect_ok(t, "{ local :: fn() {} }\n{ local :: fn() {} }")
}

@(test)
test_return_inside_nested_plain_block :: proc(t: ^testing.T) {
	expect_ok(t, "foo :: fn() -> number { { return 1 } }")
}

//
// Assigning function values (function literal as an RHS value)
//

@(test)
test_fn_literal_in_value_list :: proc(t: ^testing.T) {
	expect_ok(t, "a, b := 5, fn() {}")
}

@(test)
test_fn_literal_in_list_missing_return :: proc(t: ^testing.T) {
	// The literal's body is checked even when it appears as a value.
	expect_kind(t, "a, b := 5, fn() -> number {}", .Missing_Return)
}

@(test)
test_fn_literal_in_list_body_error :: proc(t: ^testing.T) {
	expect_kind(t, "a, b := 5, fn() { z + 1 }", .Undefined_Variable)
}

//
// Calling functions - valid
//

@(test)
test_call_declared_fn_stmt :: proc(t: ^testing.T) {
	expect_ok(t, "foo :: fn() {}\nfoo()")
}

@(test)
test_call_in_expression_position :: proc(t: ^testing.T) {
	// A call returning number can take part in arithmetic.
	expect_ok(t, "foo :: fn() -> number { return 5 }\nx := foo() + 1")
}

@(test)
test_call_with_correct_args :: proc(t: ^testing.T) {
	expect_ok(t, "foo :: fn(a: number, b: string) {}\nfoo(1, \"x\")")
}

@(test)
test_call_result_feeds_another_decl :: proc(t: ^testing.T) {
	expect_ok(
		t,
		"add :: fn(a: number, b: number) -> number { return a + b }\nx := add(1, 2)\ny := x + 1",
	)
}

@(test)
test_call_nested_calls :: proc(t: ^testing.T) {
	expect_ok(t, "id :: fn(a: number) -> number { return a }\nx := id(id(1))")
}

@(test)
test_multiple_targets_call :: proc(t: ^testing.T) {
	expect_ok(t, "foo :: fn() -> (number, string) { return 1, \"hi\" }\nx, y := foo()")
}

@(test)
test_multiple_targets_receive_corresponding_types :: proc(t: ^testing.T) {
	expect_ok(
		t,
		"foo :: fn() -> (number, string) { return 1, \"hi\" }\nuse_number :: fn(value: number) {}\nuse_string :: fn(value: string) {}\nx, y := foo()\nuse_number(x)\nuse_string(y)",
	)
}

@(test)
test_multiple_targets_flatten_mixed_rhs :: proc(t: ^testing.T) {
	expect_ok(
		t,
		"foo :: fn() -> (number, string) { return 1, \"hi\" }\nuse_number :: fn(value: number) {}\nuse_string :: fn(value: string) {}\nx, y, z := 0, foo()\nuse_number(x)\nuse_number(y)\nuse_string(z)",
	)
}

@(test)
test_multiple_constant_targets_call :: proc(t: ^testing.T) {
	expect_non_constant(
		t,
		"foo :: fn() -> (number, string) { return 1, \"hi\" }\nx, y :: foo()",
		.Function_Call,
	)
}

@(test)
test_multiple_targets_call_count_mismatch :: proc(t: ^testing.T) {
	expect_kind(
		t,
		"foo :: fn() -> (number, string) { return 1, \"hi\" }\nx := foo()",
		.Target_Value_Count_Mismatch,
	)
}

@(test)
test_multiple_target_assignment_call :: proc(t: ^testing.T) {
	expect_ok(
		t,
		"foo :: fn() -> (number, string) { return 1, \"hi\" }\nx := 0\ny := \"\"\nx, y = foo()",
	)
}

@(test)
test_multiple_target_assignment_count_mismatch :: proc(t: ^testing.T) {
	expect_kind(
		t,
		"foo :: fn() -> (number, string) { return 1, \"hi\" }\nx := 0\nx = foo()",
		.Target_Value_Count_Mismatch,
	)
}

@(test)
test_multiple_target_assignment_type_mismatch :: proc(t: ^testing.T) {
	expect_kind(
		t,
		"foo :: fn() -> (string, number) { return \"hi\", 1 }\nx := 0\ny := \"\"\nx, y = foo()",
		.Type_Mismatch_On_Assignment,
	)
}

@(test)
test_multiple_values_forwarded_from_return_call :: proc(t: ^testing.T) {
	expect_ok(
		t,
		"pair :: fn() -> (number, string) { return 1, \"ok\" }\nforward :: fn() -> (number, string) { return pair() }",
	)
}

@(test)
test_multiple_values_flatten_mixed_return_rhs :: proc(t: ^testing.T) {
	expect_ok(
		t,
		"pair :: fn() -> (number, string) { return 1, \"ok\" }\nforward :: fn() -> (number, number, string) { return 0, pair() }",
	)
}

@(test)
test_multiple_values_flatten_multiple_calls :: proc(t: ^testing.T) {
	expect_ok(
		t,
		"pair :: fn() -> (number, string) { return 1, \"ok\" }\na, b, c, d := pair(), pair()",
	)
}

@(test)
test_multiple_values_too_few_for_targets :: proc(t: ^testing.T) {
	expect_kind(
		t,
		"one :: fn() -> number { return 1 }\nx, y := one()",
		.Target_Value_Count_Mismatch,
	)
}

@(test)
test_void_call_produces_zero_target_values :: proc(t: ^testing.T) {
	expect_kind(t, "noop :: fn() {}\nx := noop()", .Target_Value_Count_Mismatch)
}

@(test)
test_multiple_values_rejected_in_single_value_contexts :: proc(t: ^testing.T) {
	expect_kind(
		t,
		"pair :: fn() -> (number, number) { return 1, 2 }\nx := pair() + 1",
		.Multi_Value_In_Single_Context,
	)
	expect_kind(
		t,
		"pair :: fn() -> (bool, bool) { return true, false }\nif pair() {}",
		.Multi_Value_In_Single_Context,
	)
	expect_kind(
		t,
		"pair :: fn() -> (number, number) { return 1, 2 }\nconsume :: fn(value: number) {}\nconsume(pair())",
		.Multi_Value_In_Single_Context,
	)
}

@(test)
test_typed_multiple_targets_check_expanded_values :: proc(t: ^testing.T) {
	expect_ok(
		t,
		"numbers :: fn() -> (number, number) { return 1, 2 }\nx, y: number = numbers()",
	)
	expect_kind(
		t,
		"pair :: fn() -> (number, string) { return 1, \"ok\" }\nx, y: number = pair()",
		.Type_Mismatch_On_Declaration,
	)
}

@(test)
test_multiple_target_direct_assignment :: proc(t: ^testing.T) {
	expect_ok(t, "x := 0\ny := \"\"\nx, y = 1, \"ok\"")
}

@(test)
test_multiple_target_assignment_rejects_constant_target :: proc(t: ^testing.T) {
	expect_kind(
		t,
		"pair :: fn() -> (number, number) { return 1, 2 }\nx :: 0\ny := 0\nx, y = pair()",
		.Variable_Constant,
	)
}

@(test)
test_return_call_reports_expanded_value_type_index :: proc(t: ^testing.T) {
	expect_message(
		t,
		"pair :: fn() -> (number, string) { return 1, \"ok\" }\nforward :: fn() -> (number, number) { return pair() }",
		"return value 2 does not match its declared type",
	)
}


@(test)
test_call_async_fn_without_await :: proc(t: ^testing.T) {
	// Await is out of scope; calling an async fn type-checks like any other call.
	expect_ok(t, "foo :: async fn() -> number { return 5 }\nx := foo() + 1")
}

@(test)
test_await_non_async_function :: proc(t: ^testing.T) {
	expect_kind(t, "foo :: fn() {}\nfoo().await", .Await_Non_Async_Function)
}

@(test)
test_call_before_declaration_hoisting :: proc(t: ^testing.T) {
	// Function declarations are hoisted, so a call may precede the declaration.
	expect_ok(t, "foo()\nfoo :: fn() {}")
}

@(test)
test_typed_constant_fn_decl_hoisted :: proc(t: ^testing.T) {
	// The typed-constant form is a `::`-equivalent definition, so it hoists too.
	expect_ok(t, "foo()\nfoo: fn() : fn() {}")
}

@(test)
test_mutable_fn_not_hoisted :: proc(t: ^testing.T) {
	// A `:=` fn is an ordinary value binding, so it remains source ordered.
	expect_kind(t, "foo()\nfoo := fn() {}", .Undefined_Variable)
}

@(test)
test_direct_recursion :: proc(t: ^testing.T) {
	expect_ok(
		t,
		"countdown :: fn(value: number) -> number { if value == 0 { return 0 }\nreturn countdown(value - 1) }",
	)
}

@(test)
test_mutual_recursion :: proc(t: ^testing.T) {
	expect_ok(
		t,
		"even :: fn(value: number) -> bool { if value == 0 { return true }\nreturn odd(value - 1) }\nodd :: fn(value: number) -> bool { if value == 0 { return false }\nreturn even(value - 1) }",
	)
}

@(test)
test_function_body_can_reference_later_function :: proc(t: ^testing.T) {
	expect_ok(t, "first :: fn() { second() }\nsecond :: fn() {}")
}

@(test)
test_function_body_cannot_reference_later_variable :: proc(t: ^testing.T) {
	expect_kind(
		t,
		"read :: fn() -> number { return later }\nlater := 1",
		.Undefined_Variable,
	)
}

@(test)
test_hoisted_function_signature_uses_earlier_type_alias :: proc(t: ^testing.T) {
	expect_ok(t, "Num :: number\nconsume(1)\nconsume :: fn(value: Num) {}")
}

@(test)
test_function_local_hoisted_function_captures_argument :: proc(t: ^testing.T) {
	expect_ok(
		t,
		"outer :: fn(value: number) -> number { return local()\nlocal :: fn() -> number { return value } }",
	)
}

@(test)
test_block_local_function_is_hoisted :: proc(t: ^testing.T) {
	expect_ok(t, "{\nlocal()\nlocal :: fn() {}\n}")
}

@(test)
test_block_local_function_does_not_escape :: proc(t: ^testing.T) {
	expect_kind(t, "{ local :: fn() {} }\nlocal()", .Undefined_Variable)
}

@(test)
test_block_hoisted_function_shadows_outer_function :: proc(t: ^testing.T) {
	expect_ok(
		t,
		"choose :: fn(value: number) {}\n{\nchoose()\nchoose :: fn() {}\n}",
	)
}

@(test)
test_hoisted_stub_call_reports_stub :: proc(t: ^testing.T) {
	expect_kind(t, "external()\nexternal :: fn()", .Call_To_Stub)
}

@(test)
test_hoisted_function_name_collisions_follow_source_order :: proc(t: ^testing.T) {
	expect_kind(t, "foo := 1\nfoo :: fn() {}", .Duplicate_Fn_Definition)
	expect_kind(t, "foo :: fn() {}\nfoo := 1", .Variable_Redeclaration)
	expect_kind(t, "Thing :: number\nThing :: fn() {}", .Duplicate_Fn_Definition)
	expect_kind(t, "Thing :: fn() {}\nThing :: number", .Variable_Redeclaration)
}

@(test)
test_constant_value_is_hoisted :: proc(t: ^testing.T) {
	expect_ok(t, "value := answer\nanswer :: 42")
}

@(test)
test_constant_dependencies_are_resolved_out_of_order :: proc(t: ^testing.T) {
	expect_ok(t, "first :: second + 1\nsecond :: 41\nvalue: number = first")
}

@(test)
test_forward_type_alias_chain :: proc(t: ^testing.T) {
	expect_ok(t, "value: First = 1\nFirst :: Second\nSecond :: number")
}

@(test)
test_function_signature_uses_later_type_alias :: proc(t: ^testing.T) {
	expect_ok(t, "consume(1)\nconsume :: fn(value: Num) {}\nNum :: number")
}

@(test)
test_constant_definition_cycle :: proc(t: ^testing.T) {
	expect_kind(t, "first :: second\nsecond :: first", .Cyclic_Constant_Definition)
	expect_kind(
		t,
		"first :: second + 1\nsecond :: first + 1",
		.Cyclic_Constant_Definition,
	)
}

@(test)
test_block_constant_is_hoisted_and_shadows_outer :: proc(t: ^testing.T) {
	expect_ok(
		t,
		"answer :: \"outer\"\n{ value: number = answer\nanswer :: 42 }",
	)
}

@(test)
test_block_constant_does_not_escape :: proc(t: ^testing.T) {
	expect_kind(t, "{ answer :: 42 }\nvalue := answer", .Undefined_Variable)
}

@(test)
test_constant_rejects_function_argument :: proc(t: ^testing.T) {
	expect_non_constant(
		t,
		"outer :: fn(value: number) -> number { return result\nresult :: value + 1 }",
		.Function_Argument,
	)
}

@(test)
test_constant_rejects_function_call :: proc(t: ^testing.T) {
	expect_non_constant(
		t,
		"value := first\nfirst :: read_second()\nread_second :: fn() -> number { return second }\nsecond :: 41",
		.Function_Call,
	)
}

@(test)
test_function_call_is_rejected_before_runtime_dependency_cycle :: proc(t: ^testing.T) {
	expect_non_constant(
		t,
		"first :: read_first()\nread_first :: fn() -> number { return first }",
		.Function_Call,
	)
}

@(test)
test_constant_rejects_call_before_inspecting_function_body :: proc(t: ^testing.T) {
	expect_non_constant(
		t,
		"mutable := 1\nconstant :: read()\nread :: fn() -> number { return mutable }",
		.Function_Call,
	)
}

@(test)
test_constant_rejects_mutable_variable :: proc(t: ^testing.T) {
	expect_non_constant(
		t,
		"mutable := 1\nconstant :: mutable + 1",
		.Mutable_Variable,
	)
}

@(test)
test_typed_constant_rejects_function_call :: proc(t: ^testing.T) {
	expect_non_constant(
		t,
		"produce :: fn() -> number { return 1 }\nanswer: number : produce()",
		.Function_Call,
	)
}

@(test)
test_constant_rejects_calls_nested_in_expressions :: proc(t: ^testing.T) {
	expect_non_constant(
		t,
		"produce :: fn() -> number { return 1 }\nanswer :: 1 + produce()",
		.Function_Call,
	)
	expect_non_constant(
		t,
		"produce :: fn() -> number { return 1 }\nanswer :: -(produce())",
		.Function_Call,
	)
	expect_non_constant(
		t,
		"produce :: fn() -> bool { return true }\nanswer :: false or produce()",
		.Function_Call,
	)
}

@(test)
test_constant_rejects_mutable_variable_from_outer_scope :: proc(t: ^testing.T) {
	expect_non_constant(
		t,
		"mutable := 1\n{ answer :: mutable + 1 }",
		.Mutable_Variable,
	)
}

@(test)
test_constant_allows_nested_compile_time_expressions :: proc(t: ^testing.T) {
	expect_ok(t, "first :: 40\nsecond :: -(first + 2)\nanswer: number = second")
	expect_ok(t, "first :: true\nsecond :: false or (first and true)\nanswer: bool = second")
}

@(test)
test_constant_allows_named_function_value :: proc(t: ^testing.T) {
	expect_ok(
		t,
		"callback :: operation\noperation :: fn() -> number { return 1 }\nanswer := callback()",
	)
}

@(test)
test_repeated_forward_function_references_reuse_resolved_header :: proc(t: ^testing.T) {
	expect_ok(t, "operation()\noperation()\noperation :: fn() {}")
}

@(test)
test_multi_hop_procedure_alias_with_argument :: proc(t: ^testing.T) {
	expect_ok(
		t,
		"foo :: fn(num: number) -> number { return num }\nbar :: foo\nzezo :: bar\nresult := zezo(5)",
	)
}

@(test)
test_procedure_alias_preserves_parameter_checks :: proc(t: ^testing.T) {
	expect_kind(
		t,
		"foo :: fn(num: number) -> number { return num }\nbar :: foo\nzezo :: bar\nzezo()",
		.Argument_Count_Mismatch,
	)
	expect_kind(
		t,
		"foo :: fn(num: number) -> number { return num }\nbar :: foo\nzezo :: bar\nzezo(\"five\")",
		.Argument_Type_Mismatch,
	)
}

@(test)
test_procedure_alias_to_stub_cannot_be_called :: proc(t: ^testing.T) {
	expect_kind(
		t,
		"external :: fn(value: number) -> number\nfirst :: external\nsecond :: first\nsecond(1)",
		.Call_To_Stub,
	)
}

@(test)
test_forward_multi_hop_procedure_alias :: proc(t: ^testing.T) {
	expect_ok(
		t,
		"result := zezo(5)\nzezo :: bar\nbar :: foo\nfoo :: fn(num: number) -> number { return num }",
	)
}

@(test)
test_typed_procedure_alias :: proc(t: ^testing.T) {
	expect_ok(
		t,
		"foo :: fn(num: number) -> number { return num }\nbar: fn(number) -> number : foo\nresult := bar(5)",
	)
}

@(test)
test_function_can_recurse_through_forward_alias :: proc(t: ^testing.T) {
	expect_ok(t, "foo :: fn() { alias() }\nalias :: foo")
}

@(test)
test_non_constant_expression_messages :: proc(t: ^testing.T) {
	expect_message(
		t,
		"produce :: fn() -> number { return 1 }\nanswer :: produce()",
		"function calls cannot be used in compile-time constant definitions",
	)
	expect_message(
		t,
		"mutable := 1\nanswer :: mutable",
		"mutable variable 'mutable' cannot be used in a compile-time constant definition",
	)
}

//
// Callable function variables
//

@(test)
test_call_var_function :: proc(t: ^testing.T) {
	expect_ok(t, "x := fn() {}\nx()")
}

@(test)
test_call_var_function_with_arguments :: proc(t: ^testing.T) {
	expect_ok(
		t,
		"identity := fn(value: number) -> number { return value }\nidentity(1)",
	)
}

@(test)
test_call_var_function_in_expression :: proc(t: ^testing.T) {
	expect_ok(
		t,
		"identity := fn(value: number) -> number { return value }\nresult := identity(1)",
	)
}

@(test)
test_call_typed_var_function :: proc(t: ^testing.T) {
	expect_ok(
		t,
		"identity: fn(number) -> number = fn(value: number) -> number { return value }\nresult := identity(1)",
	)
}

@(test)
test_typed_var_function_without_value :: proc(t: ^testing.T) {
	expect_ok(t, "callback: fn(number) -> number\ncallback(1)")
}

@(test)
test_typed_var_function_assigned_after_declaration :: proc(t: ^testing.T) {
	expect_ok(
		t,
		"callback: fn(number) -> number\ncallback = fn(value: number) -> number { return value }\nresult := callback(1)",
	)
}

@(test)
test_var_function_can_be_reassigned :: proc(t: ^testing.T) {
	expect_ok(
		t,
		"callback := fn(value: number) -> number { return value }\ncallback = fn(value: number) -> number { return value + 1 }\nresult := callback(1)",
	)
}

@(test)
test_var_function_can_initialize_another_var :: proc(t: ^testing.T) {
	expect_ok(
		t,
		"identity := fn(value: number) -> number { return value }\ncallback := identity\nresult := callback(1)",
	)
}

@(test)
test_call_returned_function_var :: proc(t: ^testing.T) {
	expect_ok(
		t,
		"make_identity :: fn() -> fn(number) -> number { return fn(value: number) -> number { return value } }\nidentity := make_identity()\nresult := identity(1)",
	)
}

@(test)
test_call_async_var_function :: proc(t: ^testing.T) {
	expect_ok(
		t,
		"load := async fn() -> number { return 1 }\nresult := load()",
	)
}

@(test)
test_call_multiple_var_functions :: proc(t: ^testing.T) {
	expect_ok(t, "first, second := fn() {}, fn() {}\nfirst()\nsecond()")
}

@(test)
test_var_function_passed_as_argument :: proc(t: ^testing.T) {
	expect_ok(
		t,
		"consume :: fn(callback: fn(number) -> number) {}\nidentity := fn(value: number) -> number { return value }\nconsume(identity)",
	)
}

@(test)
test_fn_argument_is_callable :: proc(t: ^testing.T) {
	expect_ok(
		t,
		"apply :: fn(callback: fn(number) -> number, value: number) -> number { return callback(value) }\nidentity := fn(value: number) -> number { return value }\nresult := apply(identity, 1)",
	)
}

@(test)
test_call_var_function_too_few_args :: proc(t: ^testing.T) {
	expect_kind(
		t,
		"identity := fn(value: number) -> number { return value }\nresult := identity()",
		.Argument_Count_Mismatch,
	)
}

@(test)
test_call_var_function_too_many_args :: proc(t: ^testing.T) {
	expect_kind(
		t,
		"identity := fn(value: number) -> number { return value }\nresult := identity(1, 2)",
		.Argument_Count_Mismatch,
	)
}

@(test)
test_call_var_function_argument_type_mismatch :: proc(t: ^testing.T) {
	expect_kind(
		t,
		"identity := fn(value: number) -> number { return value }\nresult := identity(\"wrong\")",
		.Argument_Type_Mismatch,
	)
}

@(test)
test_var_function_assignment_type_mismatch :: proc(t: ^testing.T) {
	expect_kind(
		t,
		"callback := fn(value: number) -> number { return value }\ncallback = fn(value: string) -> string { return value }",
		.Type_Mismatch_On_Assignment,
	)
}

@(test)
test_structurally_equal_function_types :: proc(t: ^testing.T) {
	expect_ok(
		t,
		"callback: async fn(number) -> number = async fn(value: number) -> number { return value }",
	)
	expect_ok(
		t,
		"callback: fn() -> (number, string) = fn() -> (number, string) { return 1, \"ok\" }",
	)
	expect_ok(
		t,
		"callback: fn(fn(number) -> number) -> fn(number) -> number = fn(inner: fn(number) -> number) -> fn(number) -> number { return inner }",
	)
}

@(test)
test_function_type_async_mismatch :: proc(t: ^testing.T) {
	expect_kind(
		t,
		"callback: fn() = async fn() {}",
		.Type_Mismatch_On_Declaration,
	)
}

@(test)
test_function_type_argument_count_mismatch :: proc(t: ^testing.T) {
	expect_kind(
		t,
		"callback: fn(number) = fn() {}",
		.Type_Mismatch_On_Declaration,
	)
}

@(test)
test_function_type_argument_type_mismatch :: proc(t: ^testing.T) {
	expect_kind(
		t,
		"callback: fn(number) = fn(value: string) {}",
		.Type_Mismatch_On_Declaration,
	)
}

@(test)
test_function_type_return_presence_mismatch :: proc(t: ^testing.T) {
	expect_kind(
		t,
		"callback: fn() = fn() -> number { return 1 }",
		.Type_Mismatch_On_Declaration,
	)
}

@(test)
test_function_type_return_count_mismatch :: proc(t: ^testing.T) {
	expect_kind(
		t,
		"callback: fn() -> number = fn() -> (number, string) { return 1, \"ok\" }",
		.Type_Mismatch_On_Declaration,
	)
}

@(test)
test_function_type_return_type_mismatch :: proc(t: ^testing.T) {
	expect_kind(
		t,
		"callback: fn() -> number = fn() -> string { return \"wrong\" }",
		.Type_Mismatch_On_Declaration,
	)
}

@(test)
test_nested_function_type_mismatch :: proc(t: ^testing.T) {
	expect_kind(
		t,
		"callback: fn(fn(number) -> number) = fn(inner: fn(string) -> number) {}",
		.Type_Mismatch_On_Declaration,
	)
}

@(test)
test_named_function_passed_as_argument :: proc(t: ^testing.T) {
	expect_ok(
		t,
		"consume :: fn(callback: fn(number) -> number) {}\nidentity :: fn(value: number) -> number { return value }\nconsume(identity)",
	)
}

@(test)
test_named_function_argument_signature_mismatch :: proc(t: ^testing.T) {
	expect_kind(
		t,
		"consume :: fn(callback: fn(number) -> number) {}\nidentity :: fn(value: string) -> string { return value }\nconsume(identity)",
		.Argument_Type_Mismatch,
	)
}

@(test)
test_named_function_returned_as_function_value :: proc(t: ^testing.T) {
	expect_ok(
		t,
		"identity :: fn(value: number) -> number { return value }\nget_identity :: fn() -> fn(number) -> number { return identity }",
	)
}

@(test)
test_returned_function_signature_mismatch :: proc(t: ^testing.T) {
	expect_kind(
		t,
		"make :: fn() -> fn(number) -> number { return fn(value: string) -> string { return value } }",
		.Return_Type_Mismatch,
	)
}

//
// Calling functions - errors
//

@(test)
test_call_undefined_fn :: proc(t: ^testing.T) {
	expect_kind(t, "foo()", .Undefined_Variable)
}

@(test)
test_call_non_function :: proc(t: ^testing.T) {
	expect_kind(t, "x := 5\nx()", .Not_Callable)
}

@(test)
test_call_stub_function :: proc(t: ^testing.T) {
	// A stub (signature-only) function has no body, so it cannot be called.
	expect_kind(t, "foo :: fn()\nfoo()", .Call_To_Stub)
}

@(test)
test_call_non_function_in_expression :: proc(t: ^testing.T) {
	expect_kind(t, "x := 5\ny := x()", .Not_Callable)
}

@(test)
test_call_too_few_args :: proc(t: ^testing.T) {
	expect_kind(t, "foo :: fn(a: number) {}\nfoo()", .Argument_Count_Mismatch)
}

@(test)
test_call_too_many_args :: proc(t: ^testing.T) {
	expect_kind(t, "foo :: fn() {}\nfoo(1)", .Argument_Count_Mismatch)
}

@(test)
test_call_argument_type_mismatch :: proc(t: ^testing.T) {
	expect_kind(t, "foo :: fn(a: number) {}\nfoo(\"hi\")", .Argument_Type_Mismatch)
}

//
// Calling functions in expression position (exercises check_call_expr)
//

@(test)
test_call_expr_too_few_args :: proc(t: ^testing.T) {
	expect_kind(
		t,
		"foo :: fn(a: number) -> number { return a }\nx := foo()",
		.Argument_Count_Mismatch,
	)
}

@(test)
test_call_expr_too_many_args :: proc(t: ^testing.T) {
	expect_kind(t, "foo :: fn() -> number { return 5 }\nx := foo(1)", .Argument_Count_Mismatch)
}

@(test)
test_call_expr_multi_param_too_few :: proc(t: ^testing.T) {
	expect_kind(
		t,
		"foo :: fn(a: number, b: number) -> number { return a }\nx := foo(1)",
		.Argument_Count_Mismatch,
	)
}

@(test)
test_call_expr_arg_type_mismatch_literal :: proc(t: ^testing.T) {
	expect_kind(
		t,
		"foo :: fn(a: number) -> number { return a }\nx := foo(\"hi\")",
		.Argument_Type_Mismatch,
	)
}

@(test)
test_call_expr_arg_type_mismatch_ident :: proc(t: ^testing.T) {
	expect_kind(
		t,
		"foo :: fn(a: number) -> number { return a }\ns := \"hi\"\nx := foo(s)",
		.Argument_Type_Mismatch,
	)
}

@(test)
test_call_expr_fn_value_as_arg_mismatch :: proc(t: ^testing.T) {
	expect_kind(
		t,
		"foo :: fn(a: number) -> number { return a }\nbar :: fn() {}\nx := foo(bar)",
		.Argument_Type_Mismatch,
	)
}

@(test)
test_call_expr_undefined_arg :: proc(t: ^testing.T) {
	expect_kind(
		t,
		"foo :: fn(a: number) -> number { return a }\nx := foo(missing)",
		.Undefined_Variable,
	)
}

@(test)
test_call_expr_type_name_as_arg :: proc(t: ^testing.T) {
	expect_kind(
		t,
		"foo :: fn(a: number) -> number { return a }\nx := foo(number)",
		.Type_In_Value_Position,
	)
}

@(test)
test_call_expr_correct_literal_arg :: proc(t: ^testing.T) {
	expect_ok(t, "foo :: fn(a: number) -> number { return a }\nx := foo(1)")
}

@(test)
test_call_expr_correct_ident_arg :: proc(t: ^testing.T) {
	expect_ok(t, "foo :: fn(a: number) -> number { return a }\nn := 5\nx := foo(n)")
}

//
// Calling functions in statement position (exercises check_fn_call).
// check_fn_call does not yet perform count/type/argument-resolution checks, so
// these currently FAIL; they pin the behavior required to finish the feature.
//

@(test)
test_call_stmt_arg_type_mismatch_ident :: proc(t: ^testing.T) {
	expect_kind(t, "foo :: fn(a: number) {}\ns := \"hi\"\nfoo(s)", .Argument_Type_Mismatch)
}

@(test)
test_call_stmt_undefined_arg :: proc(t: ^testing.T) {
	expect_kind(t, "foo :: fn(a: number) {}\nfoo(missing)", .Undefined_Variable)
}

@(test)
test_call_stmt_type_name_as_arg :: proc(t: ^testing.T) {
	expect_kind(t, "foo :: fn(a: number) {}\nfoo(number)", .Type_In_Value_Position)
}

@(test)
test_call_stmt_multi_param_too_few :: proc(t: ^testing.T) {
	expect_kind(t, "foo :: fn(a: number, b: number) {}\nfoo(1)", .Argument_Count_Mismatch)
}

@(test)
test_call_stmt_correct_ident_arg :: proc(t: ^testing.T) {
	expect_ok(t, "foo :: fn(a: number) {}\nn := 5\nfoo(n)")
}

// Asserts analysis of `source` fails with exactly `kind`.
@(private)
expect_kind :: proc(
	t: ^testing.T,
	source: string,
	kind: Analyzer_Error_Kind,
	loc := #caller_location,
) {
	err := check(source)
	e, ok := err.?
	testing.expectf(t, ok, "%q: expected a %v error, got none", source, kind, loc = loc)
	if ok {
		testing.expectf(t, e.kind == kind, "%q: got %v, want %v", source, e.kind, kind, loc = loc)
	}
}

@(private)
expect_non_constant :: proc(
	t: ^testing.T,
	source: string,
	reason: Non_Constant_Expression_Reason,
	loc := #caller_location,
) {
	err := check(source)
	e, has_error := err.?
	testing.expectf(t, has_error, "%q: expected a non-constant expression error, got none", source, loc = loc)
	if !has_error do return

	testing.expectf(
		t,
		e.kind == .Non_Constant_Expression,
		"%q: got %v, want Non_Constant_Expression",
		source,
		e.kind,
		loc = loc,
	)
	if e.kind != .Non_Constant_Expression do return

	data, has_data := e.data.?
	testing.expectf(t, has_data, "%q: non-constant expression error has no data", source, loc = loc)
	if !has_data do return

	constant_data, is_constant := data.value.(Non_Constant_Expression_Error_Data)
	testing.expectf(t, is_constant, "%q: non-constant expression error has the wrong data type", source, loc = loc)
	if !is_constant do return

	testing.expectf(
		t,
		constant_data.reason == reason,
		"%q: got reason %v, want %v",
		source,
		constant_data.reason,
		reason,
		loc = loc,
	)
}

@(private)
expect_fn_decl_signature_mismatch :: proc(
	t: ^testing.T,
	source: string,
	reason: Fn_Declaration_Signature_Mismatch_Reason,
	index := 0,
	expected := 0,
	actual := 0,
	loc := #caller_location,
) {
	err := check(source)
	e, has_error := err.?
	testing.expectf(t, has_error, "%q: expected a function declaration signature error, got none", source, loc = loc)
	if !has_error do return

	testing.expectf(
		t,
		e.kind == .Fn_Declaration_Signature_Mismatch,
		"%q: got %v, want Fn_Declaration_Signature_Mismatch",
		source,
		e.kind,
		loc = loc,
	)
	if e.kind != .Fn_Declaration_Signature_Mismatch do return

	data, has_data := e.data.?
	testing.expectf(t, has_data, "%q: signature mismatch has no data", source, loc = loc)
	if !has_data do return

	signature_data, is_signature := data.value.(Fn_Declaration_Signature_Error_Data)
	testing.expectf(t, is_signature, "%q: signature mismatch has the wrong data type", source, loc = loc)
	if !is_signature do return

	testing.expectf(t, signature_data.reason == reason, "%q: got reason %v, want %v", source, signature_data.reason, reason, loc = loc)
	testing.expectf(t, signature_data.index == index, "%q: got index %d, want %d", source, signature_data.index, index, loc = loc)
	testing.expectf(t, signature_data.expected == expected, "%q: got expected count %d, want %d", source, signature_data.expected, expected, loc = loc)
	testing.expectf(t, signature_data.actual == actual, "%q: got actual count %d, want %d", source, signature_data.actual, actual, loc = loc)
}

// Asserts analysis of `source` succeeds with no error.
@(private)
expect_ok :: proc(t: ^testing.T, source: string, loc := #caller_location) {
	err := check(source)
	testing.expectf(t, err == nil, "%q: unexpected error %v", source, err, loc = loc)
}

@(private)
expect_message :: proc(t: ^testing.T, source, expected: string, loc := #caller_location) {
	err := check(source)
	e, ok := err.?
	testing.expectf(t, ok, "%q: expected an analyzer error, got none", source, loc = loc)
	if !ok do return

	message := error_message(e, source)
	defer delete(message)
	testing.expectf(t, message == expected, "got %q, want %q", message, expected, loc = loc)
}

@(private)
check :: proc(source: string) -> Maybe(Analyzer_Error) {
	arena: mem.Dynamic_Arena
	mem.dynamic_arena_init(&arena)
	defer mem.dynamic_arena_destroy(&arena)
	arena_alloc := mem.dynamic_arena_allocator(&arena)

	l := lexer.Lexer{}
	lexer.init(&l, arena_alloc)
	tokens, lexer_err := lexer.scan(&l, source)
	assert(lexer_err == nil, "analyzer test source must lex successfully")
	defer delete(tokens)

	p: parser.Parser
	parser.init(&p, tokens[:], arena_alloc)
	stmts, parser_err := parser.parse(&p)
	assert(parser_err == nil, "analyzer test source must parse successfully")
	defer delete(stmts)

	a: Analyzer
	init(&a, source)
	defer destroy(&a)
	return analyze(&a, stmts[:])
}
