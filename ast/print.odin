package ast

import "../syntax"
import "core:fmt"

print_expr :: proc(expr: ^syntax.Expr) {
	switch expr_kind in expr.expr {
	case syntax.Literal_Expr:
		{

		}
	case syntax.Unary_Expr:
		{

		}
	case syntax.Binary_Expr:
		{

		}
	case syntax.Grouping_Expr:
		{

		}
	}
}
