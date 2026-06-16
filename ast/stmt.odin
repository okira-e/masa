package ast

import "core:fmt"
import "../syntax"
import "core:strings"

build_ast_from_stmt :: proc(builder: ^strings.Builder, source: string, stmt: ^syntax.Stmt) {
	switch st in stmt {
	case syntax.Expr_Stmt:
		build_ast_from_expr(builder, source, st.expr)

	case syntax.Ident_Decl_Stmt:
		strings.write_byte(builder, '(')
		strings.write_string(builder, st.constant ? "::" : ":=")
		strings.write_byte(builder, ' ')
		name := source[st.name.lexeme_start:st.name.lexeme_end]
		strings.write_string(builder, name)
		strings.write_byte(builder, ' ')

		value, ok := st.value.?
		if ok {
			expr_stmt, ok := value.(syntax.Expr_Stmt)
			assert(ok)
			build_ast_from_expr(builder, source, expr_stmt.expr)
		} else {
			strings.write_string(builder, "---")
		}

		strings.write_byte(builder, ')')

	case syntax.Fn_Decl_Stmt:
	    strings.write_string(builder, "(fn ")
	    name := source[st.name.lexeme_start:st.name.lexeme_end]
	    strings.write_string(builder, name)

	    if receiver, ok := st.receiver.?; ok {
	        strings.write_string(builder, " (receiver ")
	        strings.write_string(builder, receiver.param_name)
	        strings.write_byte(builder, ' ')
	        on := source[receiver.on.lexeme_start:receiver.on.lexeme_end]
	        strings.write_string(builder, on)
	        strings.write_byte(builder, ')')
	    }

	    if st.async {
	        strings.write_string(builder, " async")
	    }

	    strings.write_string(builder, " (args")
	    for arg in st.args {
	        strings.write_byte(builder, ' ')
	        strings.write_string(builder, source[arg.name.lexeme_start:arg.name.lexeme_end])
	        strings.write_byte(builder, ':')
	        typ := source[arg.type.lexeme_start:arg.type.lexeme_end]
	        strings.write_string(builder, typ)
	    }
	    strings.write_byte(builder, ')')

	    if return_type, ok := st.return_type.?; ok {
	        strings.write_string(builder, " (returns")
	        for tok in return_type {
	            strings.write_byte(builder, ' ')
	            rt := source[tok.lexeme_start:tok.lexeme_end]
	            strings.write_string(builder, rt)
	        }
	        strings.write_byte(builder, ')')
	    }

	    if block, ok := st.block.?; ok {
	        strings.write_byte(builder, ' ')
	        stmt_block: syntax.Stmt = block^
	        build_ast_from_stmt(builder, source, &stmt_block)
	    }

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
