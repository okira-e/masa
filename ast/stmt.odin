package ast

import "../syntax"
import "core:strings"

build_ast_from_stmt :: proc(builder: ^strings.Builder, source: string, stmt: ^syntax.Stmt) {
	#partial switch st in stmt {
	case syntax.Expr_Stmt:
		{
			build_ast_from_expr(builder, source, st.expr)
		}
	}
}
