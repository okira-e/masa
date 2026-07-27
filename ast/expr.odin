package ast

import "../syntax"
import "core:strings"

// Builds a string AST tree from an expression.
//
// This function takes the source code of the expression to capture the lexemes since they
// do not get stored on the token in this compiler.
build_ast_from_expr :: proc(b: ^strings.Builder, source: string, expr: ^syntax.Expr) {
	switch expr in expr.expr {
	case syntax.Literal_Expr:
		{
			lexeme := "---"
			if source != "" {
				lexeme = get_lexeme_from_source(
					source,
					expr.token.span.start,
					expr.token.span.end,
				)
			}
			strings.write_string(b, lexeme)
		}
	case syntax.Unary_Expr:
		{
			strings.write_byte(b, '(')
				strings.write_string(b, get_string_for_op(expr.op))
			strings.write_byte(b, ' ')
			build_ast_from_expr(b, source, expr.right)
			strings.write_byte(b, ')')
		}
	case syntax.Binary_Expr:
		{
			strings.write_byte(b, '(')
				strings.write_string(b, get_string_for_op(expr.op))
			strings.write_byte(b, ' ')
			build_ast_from_expr(b, source, expr.left)
			strings.write_byte(b, ' ')
			build_ast_from_expr(b, source, expr.right)
			strings.write_byte(b, ')')
		}
	case syntax.Grouping_Expr:
		{
			// Precedence presentation by grouping things in parenthesis is already
			// encoded in the ast by nesting. We don't need really need to add parenthesis
			// or do anything.
			build_ast_from_expr(b, source, expr.expr)
		}
	case syntax.Ident_Expr:
		{
			lexeme := get_lexeme_from_source(
				source,
				expr.token.span.start,
				expr.token.span.end,
			)
			strings.write_string(b, lexeme)
		}
	case syntax.Logical_Expr:
		{
			strings.write_byte(b, '(')
				strings.write_string(b, expr.op == .And ? "and" : "or")
			strings.write_byte(b, ' ')
			build_ast_from_expr(b, source, expr.left)
			strings.write_byte(b, ' ')
			build_ast_from_expr(b, source, expr.right)
			strings.write_byte(b, ')')
		}
	case syntax.Fn_Call_Expr:
		{
			strings.write_string(b, "(call ")
			strings.write_string(b, get_lexeme_from_source(source, expr.name.span.start, expr.name.span.end))
			for arg in expr.args {
				strings.write_byte(b, ' ')
				build_ast_from_expr(b, source, arg)
			}
			strings.write_byte(b, ')')
		}
	case syntax.Fn_Literal_Expr:
		{
			strings.write_string(b, "(fn")
			build_ast_from_fn_lit(b, source, expr)
			strings.write_byte(b, ')')
		}
	}
}

// Writes the shared parts of a function (async flag, args, returns, body). Used by
// both anonymous Fn_Literal_Expr values and named Fn_Decl_Stmt declarations.
build_ast_from_fn_lit :: proc(b: ^strings.Builder, source: string, lit: syntax.Fn_Literal_Expr) {
	if lit.async {
		strings.write_string(b, " async")
	}

	strings.write_string(b, " (args")
	for arg in lit.args {
		strings.write_byte(b, ' ')
		strings.write_string(b, source[arg.name.span.start:arg.name.span.end])
		strings.write_byte(b, ':')
		build_ast_from_type(b, source, arg.type)
	}
	strings.write_byte(b, ')')

	if return_type, ok := lit.return_type.?; ok {
		strings.write_string(b, " (returns")
		for ret in return_type {
			strings.write_byte(b, ' ')
			build_ast_from_type(b, source, ret)
		}
		strings.write_byte(b, ')')
	}

	if block, ok := lit.block.?; ok {
		strings.write_byte(b, ' ')
		stmt_block: syntax.Stmt = block
		build_ast_from_stmt(b, source, stmt_block)
	}
}

// Renders a syntactic type reference: a named type, or a nested function type
// like `(fn (params number) (returns string))`.
build_ast_from_type :: proc(b: ^strings.Builder, source: string, t: syntax.Type) {
	switch v in t.variant {
	case syntax.Token:
		strings.write_string(b, source[v.span.start:v.span.end])

	case syntax.Fn_Type:
		strings.write_string(b, "(fn")
		if v.async do strings.write_string(b, " async")

		strings.write_string(b, " (params")
		for p in v.params {
			strings.write_byte(b, ' ')
			build_ast_from_type(b, source, p)
		}
		strings.write_byte(b, ')')

		if len(v.returns) > 0 {
			strings.write_string(b, " (returns")
			for r in v.returns {
				strings.write_byte(b, ' ')
				build_ast_from_type(b, source, r)
			}
			strings.write_byte(b, ')')
		}

		strings.write_byte(b, ')')
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

get_lexeme_from_source :: proc(source: string, start: int, end: int) -> string {
	assert(start >= 0 && end <= len(source) && start <= end)
	return source[start:end]
}
