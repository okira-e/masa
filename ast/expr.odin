package ast

import "../syntax"
import "core:strings"

// Builds a string AST tree from an expression.
//
// This function takes the source code of the expression to capture the lexemes since they
// do not get stored on the token in this compiler.
build_ast_from_expr :: proc(builder: ^strings.Builder, source: string, expr: ^syntax.Expr) {
	switch expr in expr.expr {
	case syntax.Literal_Expr:
		{
			lexeme := "---"
			if source != "" {
				lexeme = get_lexeme_from_source(
					source,
					expr.token.lexeme_start,
					expr.token.lexeme_end,
				)
			}
			strings.write_string(builder, lexeme)
		}
	case syntax.Unary_Expr:
		{
			strings.write_byte(builder, '(')
			strings.write_string(builder, get_string_for_op(expr.op))
			strings.write_byte(builder, ' ')
			build_ast_from_expr(builder, source, expr.right)
			strings.write_byte(builder, ')')
		}
	case syntax.Binary_Expr:
		{
			strings.write_byte(builder, '(')
			strings.write_string(builder, get_string_for_op(expr.op))
			strings.write_byte(builder, ' ')
			build_ast_from_expr(builder, source, expr.left)
			strings.write_byte(builder, ' ')
			build_ast_from_expr(builder, source, expr.right)
			strings.write_byte(builder, ')')
		}
	case syntax.Grouping_Expr:
		{
			// Presedence presentation by grouping things in paranthesis is already
			// encoded in the ast by nesting. We don't need really need to add paranthesis
			// or do anything.
			build_ast_from_expr(builder, source, expr.expr)
		}
	}
}

@(private)
get_string_for_op :: proc(op: syntax.Token_Kind) -> string {
	#partial switch op {
	case .Plus:
		return "+"
	case .Minus:
		return "-"
	case .Star:
		return "*"
	case .Slash:
		return "/"

	case .Equal_Equal:
		return "=="
	case .Bang_Equal:
		return "!="

	case .Less:
		return "<"
	case .Less_Equal:
		return "<="
	case .Greater:
		return ">"
	case .Greater_Equal:
		return ">="

	case .Equal:
		return "="
	}

	assert(false, "token passed is not a valid binary operation")
	return ""
}

@(private)
get_lexeme_from_source :: proc(source: string, start: int, end: int) -> string {
	assert(start >= 0 && end <= len(source) && start <= end)
	return source[start:end]
}

