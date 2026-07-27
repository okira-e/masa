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
	// `foo: T : fn` is the same hoisted function declaration as `foo :: fn`,
	// just carrying an explicit declared type.
	expect_ok(t, "foo: fn() -> number : fn() -> number { return 5 }")
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
test_call_async_fn_without_await :: proc(t: ^testing.T) {
	// Await is out of scope; calling an async fn type-checks like any other call.
	expect_ok(t, "foo :: async fn() -> number { return 5 }\nx := foo() + 1")
}

// @(test)
// test_call_before_declaration_hoisting :: proc(t: ^testing.T) {
// 	// Function declarations are hoisted, so a call may precede the declaration.
// 	expect_ok(t, "foo()\nfoo :: fn() {}")
// }

// @(test)
// test_typed_constant_fn_decl_hoisted :: proc(t: ^testing.T) {
// 	// The typed-constant form is a `::`-equivalent definition, so it hoists too.
// 	expect_ok(t, "foo()\nfoo: fn() : fn() {}")
// }
//
// @(test)
// test_mutable_fn_not_hoisted :: proc(t: ^testing.T) {
// 	// Contrast with hoisting: a `:=` fn is an ordinary value binding, not a
// 	// definition, so it is NOT hoisted - calling it beforehand is undefined.
// 	expect_kind(t, "foo()\nfoo := fn() {}", .Undefined_Variable)
// }

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
