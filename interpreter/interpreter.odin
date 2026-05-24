package interpreter

import "core:fmt"
import "../syntax"
import "core:strconv"

Value :: union {
	f64,
	string,
	bool,
}

Interpreter :: struct {
	source: string,
	env:    map[string]Value,
}

// The env map uses the default heap allocator — Odin maps require cache-line
// alignment that the dynamic arena doesn't satisfy. Call destroy to free it.
init :: proc(interp: ^Interpreter, source: string) {
	interp.source = source
	interp.env = make(map[string]Value)
}

destroy :: proc(interp: ^Interpreter) {
	delete(interp.env)
}

interpret :: proc(interp: ^Interpreter, stmts: []^syntax.Stmt) -> Maybe(Eval_Error) {
	for stmt in stmts {
		err := eval_stmt(interp, stmt)
		if err != nil do return err
	}

	return nil
}

eval_stmt :: proc(interp: ^Interpreter, stmt: ^syntax.Stmt) -> Maybe(Eval_Error) {
	switch stmt in stmt {
	case syntax.Ident_Decl_Stmt:
		val, err := eval(interp, stmt.value)
		if err != nil do return err

		name := interp.source[stmt.name.lexeme_start:stmt.name.lexeme_end]
		if _, ok := interp.env[name]; ok {
			return .Variable_Redeclaration
		}

		interp.env[name] = val

	case syntax.Expr_Stmt:
		val, err := eval(interp, stmt.expr)
		if err != nil do return err

		fmt.println("VAL:", val)

	case syntax.If_Stmt:
		cond_val, err := eval(interp, stmt.condition)
		if err != nil do return err

		cond_bool, ok := cond_val.(bool)
		if !ok do return .Type_Error

		if cond_bool {
			return eval_stmt(interp, stmt.then_block)
		}
		if else_stmt, has_else := stmt.else_branch.?; has_else {
			return eval_stmt(interp, else_stmt)
		}

	case syntax.Block_Stmt:
		for s in stmt.stmts {
			err := eval_stmt(interp, s)
			if err != nil do return err
		}
	}

	return nil
}

eval :: proc(interp: ^Interpreter, expr: ^syntax.Expr) -> (Value, Maybe(Eval_Error)) {
	switch &v in expr.expr {
	case syntax.Literal_Expr:
		return eval_literal(interp, &v)

	case syntax.Unary_Expr:
		return eval_unary(interp, &v)

	case syntax.Binary_Expr:
		return eval_binary(interp, &v)

	case syntax.Grouping_Expr:
		return eval(interp, v.expr)

	case syntax.Ident_Expr:
		return eval_ident(interp, &v)

	case syntax.Logical_Expr:
		return eval_logical(interp, &v)
	}

	assert(false)
	unreachable()
}

eval_literal :: proc(interp: ^Interpreter, literal: ^syntax.Literal_Expr) -> (Value, Maybe(Eval_Error)) {
	kind, has_kind := literal.token.literal_kind.?
	assert(has_kind)

	lexeme := interp.source[literal.token.lexeme_start:literal.token.lexeme_end]
	switch kind {
	case .Number:
		n, ok := strconv.parse_f64(lexeme)
		if !ok do return nil, .Invalid_Literal

		return n, nil

	case .String:
		return lexeme[1:len(lexeme) - 1], nil

	case .Bool:
		return lexeme == "true", nil

	case .Nil:
		return nil, nil
	}

	assert(false)
	unreachable()
}

eval_unary :: proc(interp: ^Interpreter, unary: ^syntax.Unary_Expr) -> (Value, Maybe(Eval_Error)) {
	right, err := eval(interp, unary.right)
	if err != nil do return nil, err

	#partial switch unary.op {
	case .Minus:
		n, ok := right.(f64)
		if !ok do return nil, .Type_Error

		return -n, nil

	case .Bang:
		b, ok := right.(bool)
		if !ok do return nil, .Type_Error

		return !b, nil

	}

	assert(false)
	unreachable()
}

eval_binary :: proc(interp: ^Interpreter, binary: ^syntax.Binary_Expr) -> (Value, Maybe(Eval_Error)) {
	left, lerr := eval(interp, binary.left)
	if lerr != nil do return nil, lerr

	right, rerr := eval(interp, binary.right)
	if rerr != nil do return nil, rerr

	#partial switch binary.op {
	case .Equal_Equal:
		return values_equal(left, right), nil

	case .Bang_Equal:
		return !values_equal(left, right), nil
	}

	ln, ok_l := left.(f64)
	rn, ok_r := right.(f64)
	if !ok_l || !ok_r do return nil, .Type_Error

	#partial switch binary.op {
	case .Plus:
		return ln + rn, nil

	case .Minus:
		return ln - rn, nil

	case .Star:
		return ln * rn, nil

	case .Slash:
		if rn == 0 do return nil, .Division_By_Zero

		return ln / rn, nil

	case .Less:
		return ln < rn, nil

	case .Less_Equal:
		return ln <= rn, nil

	case .Greater:
		return ln > rn, nil

	case .Greater_Equal:
		return ln >= rn, nil
	}

	assert(false)
	unreachable()
}

eval_ident :: proc(interp: ^Interpreter, ident: ^syntax.Ident_Expr) -> (Value, Maybe(Eval_Error)) {
	name := interp.source[ident.token.lexeme_start:ident.token.lexeme_end]
	val, ok := interp.env[name]
	if !ok do return nil, .Undefined_Variable

	return val, nil
}

eval_logical :: proc(interp: ^Interpreter, logical: ^syntax.Logical_Expr) -> (Value, Maybe(Eval_Error)) {
	left, lerr := eval(interp, logical.left)
	if lerr != nil do return nil, lerr

	lb, ok := left.(bool)
	if !ok do return nil, .Type_Error

	// Short-circuit: only eval right when needed.
	if logical.op == .Or && lb do return true, nil
	if logical.op == .And && !lb do return false, nil

	right, rerr := eval(interp, logical.right)
	if rerr != nil do return nil, rerr

	rb, ok2 := right.(bool)
	if !ok2 do return nil, .Type_Error

	return rb, nil
}

values_equal :: proc(a, b: Value) -> bool {
	if a == nil && b == nil {
		return true
	}
	if a == nil || b == nil {
		return false
	}

	switch av in a {
	case f64:
		bv, ok := b.(f64)
		return ok && av == bv

	case string:
		bv, ok := b.(string)
		return ok && av == bv

	case bool:
		bv, ok := b.(bool)
		return ok && av == bv
	}

	assert(false)
	unreachable()
}

Eval_Error :: enum {
	Invalid_Literal,
	Type_Error,
	Division_By_Zero,
	Undefined_Variable,
	Variable_Redeclaration,
}
