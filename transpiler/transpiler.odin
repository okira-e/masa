package transpiler

import "../syntax"
import "core:strings"

Transpiler :: struct {
	source: string,
	output: strings.Builder,
	indent: int,
}

init :: proc(t: ^Transpiler, source: string) {
	t.source = source
	t.output = strings.builder_make()
	t.indent = 0
}

destroy :: proc(t: ^Transpiler) {
	strings.builder_destroy(&t.output)
}

transpile :: proc(t: ^Transpiler, stmts: []^syntax.Stmt) -> string {
	emit_headers(t);

	for stmt in stmts {
		emit_stmt(t, stmt)
		strings.write_byte(&t.output, '\n')
	}

	return strings.to_string(t.output)
}

emit_headers :: proc(t: ^Transpiler) {
	strings.write_string(&t.output, "\"use strict\";\n\n");
}

emit_stmt :: proc(t: ^Transpiler, stmt: ^syntax.Stmt, do_indent := true) {
	switch s in stmt {
	case syntax.Expr_Stmt:
		if do_indent do write_indent(t)
		emit_expr(t, s.expr)
		strings.write_byte(&t.output, ';')

	case syntax.Ident_Decl_Stmt:
		if do_indent do write_indent(t)
		emit_ident_declaration(t, s)
		strings.write_byte(&t.output, ';')

	case syntax.Ident_Assignment_Stmt:
		if do_indent do write_indent(t)
		emit_ident_assignment(t, s)
		strings.write_byte(&t.output, ';')

	case syntax.If_Stmt:
		if do_indent do write_indent(t)
		emit_if(t, s)

	case syntax.Block_Stmt:
		if do_indent do write_indent(t)
		emit_block(t, s)
	}
}

emit_if :: proc(t: ^Transpiler, stmt: syntax.If_Stmt) {
	strings.write_string(&t.output, "if (")
	emit_expr(t, stmt.condition)
	strings.write_string(&t.output, ") ")
	emit_stmt(t, stmt.then_block, false)
	if else_stmt, has := stmt.else_branch.?; has {
		strings.write_string(&t.output, " else ")
		emit_stmt(t, else_stmt)
	}
}

emit_ident_declaration :: proc(t: ^Transpiler, stmt: syntax.Ident_Decl_Stmt) {
	strings.write_string(&t.output, stmt.constant ? "const " : "let ")
	emit_ident_token(t, stmt.name)

	if stmt_val, ok := stmt.value.?; ok {
		strings.write_string(&t.output, " = ")
		emit_expr(t, stmt_val)
	}
}

emit_ident_assignment :: proc(t: ^Transpiler, stmt: syntax.Ident_Assignment_Stmt) {
	emit_ident_token(t, stmt.name)
	strings.write_string(&t.output, " = ")
	emit_expr(t, stmt.value)
}

emit_block :: proc(t: ^Transpiler, stmt: syntax.Block_Stmt) {
	strings.write_string(&t.output, "{\n")
	t.indent += 1
	for inner in stmt.stmts {
		emit_stmt(t, inner)
		strings.write_byte(&t.output, '\n')
	}
	t.indent -= 1
	write_indent(t)
	strings.write_byte(&t.output, '}')
}

emit_expr :: proc(t: ^Transpiler, expr: ^syntax.Expr) {
	switch v in expr.expr {
	case syntax.Literal_Expr:
		write_lexeme(t, v.token)

	case syntax.Unary_Expr:
		#partial switch v.op {
		case .Minus:
			strings.write_byte(&t.output, '-')
		case .Bang:
			strings.write_byte(&t.output, '!')
		}
		emit_expr(t, v.right)

	case syntax.Binary_Expr:
		emit_expr(t, v.left)
		strings.write_byte(&t.output, ' ')
		strings.write_string(&t.output, js_binary_op(v.op))
		strings.write_byte(&t.output, ' ')
		emit_expr(t, v.right)

	case syntax.Grouping_Expr:
		strings.write_byte(&t.output, '(')
		emit_expr(t, v.expr)
		strings.write_byte(&t.output, ')')

	case syntax.Ident_Expr:
		emit_ident_token(t, v.token)

	case syntax.Logical_Expr:
		emit_expr(t, v.left)
		strings.write_string(&t.output, v.op == .And ? " && " : " || ")
		emit_expr(t, v.right)
	}
}

// Emits an identifier. Mangles the name with a `$` prefix if it would collide with a
// JS reserved word.
emit_ident_token :: proc(t: ^Transpiler, token: syntax.Token) {
	name := t.source[token.lexeme_start:token.lexeme_end]
	if is_js_reserved(name) {
		strings.write_byte(&t.output, '$')
	}
	strings.write_string(&t.output, name)
}

write_lexeme :: proc(t: ^Transpiler, tok: syntax.Token) {
	strings.write_string(&t.output, t.source[tok.lexeme_start:tok.lexeme_end])
}

write_indent :: proc(t: ^Transpiler) {
	for _ in 0 ..< t.indent {
		strings.write_string(&t.output, "  ")
	}
}

js_binary_op :: proc(op: syntax.Token_Kind) -> string {
	#partial switch op {
	case .Plus: return "+"
	case .Minus: return "-"
	case .Star: return "*"
	case .Slash: return "/"
	case .Equal_Equal: return "==="
	case .Bang_Equal: return "!=="
	case .Less: return "<"
	case .Less_Equal: return "<="
	case .Greater: return ">"
	case .Greater_Equal: return ">="
	}
	unreachable()
}

is_js_reserved :: proc(name: string) -> bool {
	for w in JS_RESERVED {
		if w == name do return true
	}
	return false
}

// JS reserved words. Anything that would be a syntax error in JS if used as an
// identifier — keywords, future reserved, contextual reserved. Some entries
// (like `if`, `else`) can't actually appear because masa reserves them too,
// but listing them is harmless and future-proof.
JS_RESERVED := []string {
	"abstract",
	"arguments",
	"await",
	"boolean",
	"break",
	"byte",
	"case",
	"catch",
	"char",
	"class",
	"const",
	"continue",
	"debugger",
	"default",
	"delete",
	"do",
	"double",
	"else",
	"enum",
	"eval",
	"export",
	"extends",
	"false",
	"final",
	"finally",
	"float",
	"for",
	"function",
	"goto",
	"if",
	"implements",
	"import",
	"in",
	"instanceof",
	"int",
	"interface",
	"let",
	"long",
	"native",
	"new",
	"null",
	"package",
	"private",
	"protected",
	"public",
	"return",
	"short",
	"static",
	"super",
	"switch",
	"synchronized",
	"this",
	"throw",
	"throws",
	"transient",
	"true",
	"try",
	"typeof",
	"var",
	"void",
	"volatile",
	"while",
	"with",
	"yield",
}
