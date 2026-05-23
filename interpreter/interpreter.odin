package interpreter

import "core:fmt"
import "../syntax"
import "core:strconv"

Value :: union {
	f64,
	string,
	bool,
}

interpret :: proc(source: string, exprs: []^syntax.Expr) -> Maybe(Eval_Error) {
	for expr in exprs {
		val, err := eval(source, expr)
		if err != nil do return err

		fmt.println("VAL:", val)
	}

	return nil
}

eval :: proc(source: string, expr: ^syntax.Expr) -> (Value, Maybe(Eval_Error)) {
	switch &v in expr.expr {
	case syntax.Literal_Expr:
		return eval_literal(source, &v)

	case syntax.Unary_Expr:
		return eval_unary(source, &v)

	case syntax.Binary_Expr:
		return eval_binary(source, &v)

	case syntax.Grouping_Expr:
		return eval(source, v.expr)
	}

	unreachable()
}

eval_literal :: proc(source: string, literal: ^syntax.Literal_Expr) -> (Value, Maybe(Eval_Error)) {
	kind, has_kind := literal.token.literal_kind.?
	assert(has_kind)

	lexeme := source[literal.token.lexeme_start:literal.token.lexeme_end]
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

	unreachable()
}

eval_unary :: proc(source: string, unary: ^syntax.Unary_Expr) -> (Value, Maybe(Eval_Error)) {
	right, err := eval(source, unary.right)
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

	unreachable()
}

eval_binary :: proc(source: string, binary: ^syntax.Binary_Expr) -> (Value, Maybe(Eval_Error)) {
	left, lerr := eval(source, binary.left)
	if lerr != nil do return nil, lerr

	right, rerr := eval(source, binary.right)
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
		if rn == 0 {
			return nil, .Division_By_Zero
		}

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

	unreachable()
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

	unreachable()
}

Eval_Error :: enum {
	Invalid_Literal,
	Type_Error,
	Division_By_Zero,
}
