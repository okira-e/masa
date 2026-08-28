package ast

import "../syntax"
import "core:strings"

build_ast_from_stmts :: proc(b: ^strings.Builder, source: string, stmts: []syntax.Stmt) {
	for stmt, index in stmts {
		if index > 0 do strings.write_byte(b, '\n')
		build_ast_from_stmt(b, source, stmt)
	}
}

// @TODO: Make for a better output than the current one for printing the AST
build_ast_from_stmt :: proc(b: ^strings.Builder, source: string, stmt: syntax.Stmt) {
	switch st in stmt {
	case ^syntax.Expr_Stmt:
		build_ast_from_expr(b, source, st.expr)

	case ^syntax.Ident_Decl_Stmt:
		strings.write_byte(b, '(')
		strings.write_string(b, st.constant ? "::" : ":=")
		for name in st.names {
			strings.write_byte(b, ' ')
			strings.write_string(b, source[name.span.start:name.span.end])
			if decl_type, has_type := st.type.?; has_type {
				strings.write_byte(b, ':')
				build_ast_from_type(b, source, decl_type)
			}
		}

		value, ok := st.value.?
		if ok {
			build_ast_from_ident_rhs(b, source, value[:])
		} else {
			strings.write_string(b, " ---")
		}

		strings.write_byte(b, ')')

	case ^syntax.Fn_Decl_Stmt:
		strings.write_string(b, "(fn ")
		name := source[st.name.span.start:st.name.span.end]
		strings.write_string(b, name)

		if receiver, ok := st.receiver.?; ok {
			strings.write_string(b, " (receiver ")
			strings.write_string(b, receiver.param_name)
			strings.write_byte(b, ' ')
			on := source[receiver.on.span.start:receiver.on.span.end]
			strings.write_string(b, on)
			strings.write_byte(b, ')')
		}

		build_ast_from_fn_lit(b, source, &st.lit)

		strings.write_byte(b, ')')

	case ^syntax.Fn_Call_Stmt:
		build_ast_from_fn_call(b, source, st)

	case ^syntax.Ident_Assignment_Stmt:
		strings.write_byte(b, '(')
		strings.write_string(b, "=")
		for name in st.names {
			strings.write_byte(b, ' ')
			strings.write_string(b, source[name.span.start:name.span.end])
		}
		build_ast_from_ident_rhs(b, source, st.values[:])
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

	case ^syntax.For_Stmt:
		strings.write_string(b, "(for ")
		switch variant in st.variant {
		case syntax.Condition_For:
			build_ast_from_expr(b, source, variant.condition)

		case syntax.Traditional_For:
			build_ast_from_stmt(b, source, variant.initializer)
			strings.write_string(b, "; ")
			build_ast_from_expr(b, source, variant.condition)
			strings.write_string(b, "; ")
			build_ast_from_stmt(b, source, variant.post)

		case syntax.Range_For:
			strings.write_string(b, source[variant.capture_ident.span.start:variant.capture_ident.span.end])
			if iterator, has_iterator := variant.iterator.?; has_iterator {
				strings.write_string(b, ", ")
				strings.write_string(b, source[iterator.span.start:iterator.span.end])
			}
			strings.write_string(b, " in ")
			if range, has_range := variant.range.?; has_range {
				build_ast_from_expr(b, source, range.lower)
				strings.write_string(b, "..")
				build_ast_from_expr(b, source, range.upper)
			} else if iterable, has_iterable := variant.iterable.?; has_iterable {
				strings.write_string(b, source[iterable.span.start:iterable.span.end])
			}
		}
		strings.write_byte(b, ' ')
		build_ast_from_stmt(b, source, st.block)
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

build_ast_from_ident_rhs :: proc(b: ^strings.Builder, source: string, rhs: []syntax.Expr) {
	for value in rhs {
		strings.write_byte(b, ' ')
		build_ast_from_expr(b, source, value)
	}
}

build_ast_from_fn_call :: proc(b: ^strings.Builder, source: string, call: ^syntax.Fn_Call_Stmt) {
	strings.write_string(b, "(call ")
	if call.call.awaited do strings.write_string(b, "await ")
	strings.write_string(b, source[call.call.name.span.start:call.call.name.span.end])
	for arg in call.call.args {
		strings.write_byte(b, ' ')
		build_ast_from_expr(b, source, arg)
	}
	strings.write_byte(b, ')')
}
