package syntax

import "core:log"

Expr_Kind :: union {
	Literal_Expr,
	Unary_Expr,
	Binary_Expr,
	Grouping_Expr,
}

Expr :: struct {
	expr: Expr_Kind,
}

Literal_Expr :: struct {
	token: Token, // Since lexemes are not actaully stored in token, it's cheap to copy
}

Unary_Expr :: struct {
	op:    Token_Kind,
	right: ^Expr,
}

Binary_Expr :: struct {
	left:  ^Expr,
	op:    Token_Kind,
	right: ^Expr,
}

Grouping_Expr :: struct {
	expr: ^Expr,
}

expr_eq :: proc(a: ^Expr, b: ^Expr) -> bool {
	if a == nil || b == nil {
		return false
	}

	switch a_expr in a.expr {
	case Binary_Expr:
		{
			if _, ok := b.expr.(Binary_Expr); !ok {
				log.info("HERE: Binary_Expr")
				return false
			}

			casted_a := a.expr.(Binary_Expr)
			casted_b := b.expr.(Binary_Expr)

			return(
				expr_eq(casted_a.left, casted_b.left) &&
				casted_a.op == casted_b.op &&
				expr_eq(casted_a.right, casted_b.right) \
			)
		}
	case Literal_Expr:
		{
			if _, ok := b.expr.(Literal_Expr); !ok {
				log.info("HERE: Literal_Expr")
				return false
			}

			return a.expr.(Literal_Expr).token == b.expr.(Literal_Expr).token
		}
	case Unary_Expr:
		{
			if _, ok := b.expr.(Unary_Expr); !ok {
				log.info("HERE: Unary_Expr")
				return false
			}

			casted_a := a.expr.(Unary_Expr)
			casted_b := b.expr.(Unary_Expr)

			return expr_eq(casted_a.right, casted_b.right) && casted_a.op == casted_b.op
		}
	case Grouping_Expr:
		{
			if _, ok := b.expr.(Grouping_Expr); !ok {
				log.info("HERE: Grouping_Expr")
				return false
			}

			casted_a := a.expr.(Grouping_Expr)
			casted_b := b.expr.(Grouping_Expr)

			return expr_eq(casted_a.expr, casted_b.expr)
		}
	}

	return true
}
