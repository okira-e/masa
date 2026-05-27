package ast

import "../syntax"
import "core:strings"

build_ast_from_stmt :: proc(builder: ^strings.Builder, source: string, stmt: ^syntax.Stmt) {
	switch st in stmt {
	case syntax.Expr_Stmt:
		build_ast_from_expr(builder, source, st.expr)

	case syntax.Ident_Decl_Stmt:
		strings.write_byte(builder, '(')
		strings.write_string(builder, st.mutable ? ":=" : "::")
		strings.write_byte(builder, ' ')
		name := source[st.name.lexeme_start:st.name.lexeme_end]
		strings.write_string(builder, name)
		strings.write_byte(builder, ' ')
		build_ast_from_expr(builder, source, st.value)
		strings.write_byte(builder, ')')

	case syntax.Ident_Assignment_Stmt:
		strings.write_byte(builder, '(')
		strings.write_string(builder, "=")
		strings.write_byte(builder, ' ')
		name := source[st.name.lexeme_start:st.name.lexeme_end]
		strings.write_string(builder, name)
		strings.write_byte(builder, ' ')
		build_ast_from_expr(builder, source, st.value)
		strings.write_byte(builder, ')')

	case syntax.If_Stmt:
		strings.write_string(builder, "(if ")
		build_ast_from_expr(builder, source, st.condition)
		strings.write_byte(builder, ' ')
		build_ast_from_stmt(builder, source, st.then_block)
		if else_stmt, has_else := st.else_branch.?; has_else {
			strings.write_byte(builder, ' ')
			build_ast_from_stmt(builder, source, else_stmt)
		}
		strings.write_byte(builder, ')')

	case syntax.Block_Stmt:
		strings.write_string(builder, "{ ")
		for s, i in st.stmts {
			if i > 0 do strings.write_byte(builder, ' ')
			build_ast_from_stmt(builder, source, s)
		}
		strings.write_string(builder, " }")
	}
}
