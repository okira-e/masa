package ast

import "../syntax"
import "core:strings"

// @TODO: Make for a better output than the current one for printing the AST
build_ast_from_stmt :: proc(b: ^strings.Builder, source: string, stmt: syntax.Stmt) {
	switch st in stmt {
	case ^syntax.Expr_Stmt:
		build_ast_from_expr(b, source, st.expr)

	case ^syntax.Ident_Decl_Stmt:
		// @TODO: Print the full `x: number = 5` statement instead of just saying "(:= x 5)"
		// Maybe it should be "(= (: x number) 5)"?
		strings.write_byte(b, '(')
		strings.write_string(b, st.constant ? "::" : ":=")
		for name in st.names {
			strings.write_byte(b, ' ')
			strings.write_string(b, source[name.lexeme_start:name.lexeme_end])
		}

		value, ok := st.value.?
		if ok {
			build_ast_from_ident_rhs(b, source, value)
		} else {
			strings.write_string(b, " ---")
		}

		strings.write_byte(b, ')')

	case ^syntax.Fn_Decl_Stmt:
	    strings.write_string(b, "(fn ")
	    name := source[st.name.lexeme_start:st.name.lexeme_end]
	    strings.write_string(b, name)

	    if receiver, ok := st.receiver.?; ok {
	        strings.write_string(b, " (receiver ")
	        strings.write_string(b, receiver.param_name)
	        strings.write_byte(b, ' ')
	        on := source[receiver.on.lexeme_start:receiver.on.lexeme_end]
	        strings.write_string(b, on)
	        strings.write_byte(b, ')')
	    }

	    build_ast_from_fn_lit(b, source, st.lit)

	    strings.write_byte(b, ')')

	case ^syntax.Fn_Call_Stmt:
		build_ast_from_fn_call(b, source, st)

	case ^syntax.Ident_Assignment_Stmt:
		strings.write_byte(b, '(')
		strings.write_string(b, "=")
		for name in st.names {
			strings.write_byte(b, ' ')
			strings.write_string(b, source[name.lexeme_start:name.lexeme_end])
		}
		build_ast_from_ident_rhs(b, source, st.value)
		strings.write_byte(b, ')')

	case ^syntax.If_Stmt:
		strings.write_string(b, "(if ")
		build_ast_from_expr(b, source, st.condition)
		strings.write_byte(b, ' ')
		build_ast_from_stmt(b, source, st.then_block)
		if else_stmt, has_else := st.else_branch.?; has_else {
			strings.write_byte(b, ' ')
			build_ast_from_stmt(b, source, else_stmt)
		}
		strings.write_byte(b, ')')

	case ^syntax.Block_Stmt:
		strings.write_string(b, "{ ")
		for s, i in st.stmts {
			if i > 0 do strings.write_byte(b, ' ')
			build_ast_from_stmt(b, source, s)
		}
		strings.write_string(b, " }")

	case ^syntax.Return_Stmt:
		strings.write_string(b, "(return")
		for e in st.exprs {
			strings.write_byte(b, ' ')
			build_ast_from_expr(b, source, e)
		}
		strings.write_byte(b, ')')
	}
}

build_ast_from_ident_rhs :: proc(b: ^strings.Builder, source: string, rhs: [dynamic]^syntax.Expr) {
	for value in rhs {
		strings.write_byte(b, ' ')
		build_ast_from_expr(b, source, value)
	}
}

build_ast_from_fn_call :: proc(b: ^strings.Builder, source: string, call: ^syntax.Fn_Call_Stmt) {
	strings.write_string(b, "(call ")
	if call.call.awaited do strings.write_string(b, "await ")
	strings.write_string(b, source[call.call.name.lexeme_start:call.call.name.lexeme_end])
	for arg in call.call.args {
		strings.write_byte(b, ' ')
		build_ast_from_expr(b, source, arg)
	}
	strings.write_byte(b, ')')
}
