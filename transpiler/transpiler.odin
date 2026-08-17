package transpiler

import "../syntax"
import "core:strings"

Transpiler :: struct {
	source:         string,
	output_builder: strings.Builder,
	indent:         int,
}

init :: proc(t: ^Transpiler, source: string) {
	t.source         = source
	t.output_builder = strings.builder_make()
	t.indent         = 0
}

destroy :: proc(t: ^Transpiler) {
	strings.builder_destroy(&t.output_builder)
}

transpile :: proc(t: ^Transpiler, stmts: []syntax.Stmt) -> string {
	emit_headers(t)

	for stmt in stmts {
		written_anything := emit_stmt(t, stmt)
		if written_anything {
			strings.write_byte(&t.output_builder, '\n')
		}
	}

	return strings.to_string(t.output_builder)
}

emit_headers :: proc(t: ^Transpiler) {
	strings.write_string(&t.output_builder, USE_STRICT_PREFIX)
}

// Returns if it actually wrote something or not
emit_stmt :: proc(t: ^Transpiler, stmt: syntax.Stmt, do_indent := true) -> bool {
	switch s in stmt {
	case ^syntax.Expr_Stmt:
		if do_indent do write_indent(t)
		emit_expr(t, s.expr)
		strings.write_byte(&t.output_builder, ';')

	case ^syntax.Ident_Decl_Stmt:
		if s.decl_kind == .Type_Alias {
			return false
		}

		if do_indent do write_indent(t)
		emit_ident_declaration(t, s)
		strings.write_byte(&t.output_builder, ';')

	case ^syntax.Fn_Decl_Stmt:
		if s.lit.block == nil {
			return false
		}

		if do_indent do write_indent(t)
		emit_fn_declaration(t, s)

	case ^syntax.Fn_Call_Stmt:
		if do_indent do write_indent(t)
		emit_fn_call(t, s)
		strings.write_byte(&t.output_builder, ';')

	case ^syntax.Ident_Assignment_Stmt:
		if do_indent do write_indent(t)
		emit_ident_assignment(t, s)
		strings.write_byte(&t.output_builder, ';')

	case ^syntax.If_Stmt:
		if do_indent do write_indent(t)
		emit_if(t, s)

	case ^syntax.Block_Stmt:
		if do_indent do write_indent(t)
		emit_block(t, s)

	case ^syntax.Return_Stmt:
		if do_indent do write_indent(t)
		emit_return_stmt(t, s)
	}

	return true
}

emit_if :: proc(t: ^Transpiler, stmt: ^syntax.If_Stmt) {
	strings.write_string(&t.output_builder, "if (")
	emit_expr(t, stmt.condition)
	strings.write_string(&t.output_builder, ") ")
	emit_stmt(t, stmt.then_block, false)
	if else_stmt, has := stmt.else_branch.?; has {
		strings.write_string(&t.output_builder, " else ")
		emit_stmt(t, else_stmt, false)
	}
}

emit_ident_declaration :: proc(t: ^Transpiler, stmt: ^syntax.Ident_Decl_Stmt) {
	values: [dynamic]syntax.Expr
	has_values := false
	if stmt_val, ok := stmt.value.?; ok {
		values     = stmt_val
		has_values = true
	}

	strings.write_string(&t.output_builder, stmt.constant ? "const " : "let ")

	Pair :: struct {
		names: [dynamic]syntax.Token,
		value: syntax.Expr,
	}

	pairs := make([dynamic]Pair, 0, len(stmt.names))
	defer {
		for var in pairs {
			delete(var.names)
		}
		delete(pairs)
	}

	// Populate pairs to get matching `names->values`:
	//   a, b := 5, 10
	//   -> let a = 5, b = 10;
	//   x, y, z := foo(), 5
	//   -> let [x, y] = foo(), z = 5;
	//
	if has_values {
		name_i := 0
		for value in values {
			skip := 1
			if call, is_call := value.(^syntax.Fn_Call_Expr); is_call {
				if count, ok := call.return_count.?; ok {
					skip = count
				}
			}

			pair: Pair
			for j in 0 ..< skip {
				append(&pair.names, stmt.names[name_i + j])
			}
			pair.value = value
			append(&pairs, pair)

			name_i += skip
		}

		for pair, i in pairs {
			if i > 0 do strings.write_string(&t.output_builder, ", ")

			if len(pair.names) == 1 {
				emit_ident_token(t, pair.names[0])
			} else {
				strings.write_string(&t.output_builder, "[")
				for name, j in pair.names {
					if j > 0 do strings.write_string(&t.output_builder, ", ")
					emit_ident_token(t, name)
				}
				strings.write_string(&t.output_builder, "]")
			}

			strings.write_string(&t.output_builder, " = ")
			emit_expr(t, pair.value)
		}
	} else {
		for name, i in stmt.names {
			if i > 0 do strings.write_string(&t.output_builder, ", ")
			emit_ident_token(t, name)
		}
	}
}

emit_fn_declaration :: proc(t: ^Transpiler, stmt: ^syntax.Fn_Decl_Stmt) {
	if stmt.lit.block == nil {
		return
	}

	emit_fn_literal(t, &stmt.lit, stmt.name)
}

emit_fn_literal :: proc(t: ^Transpiler, fn: ^syntax.Fn_Literal_Expr, name: Maybe(syntax.Token)) {
	if fn.async {
		strings.write_string(&t.output_builder, "async function ")
	} else {
		strings.write_string(&t.output_builder, "function ")
	}

	// name
	if name, ok := name.?; ok {
		emit_ident_token(t, name)
	}

	// args
	strings.write_string(&t.output_builder, "(")
	for arg, i in fn.args {
		if i != 0 do strings.write_string(&t.output_builder, ", ")

		if is_js_reserved(t.source[arg.name.span.start:arg.name.span.end]) {
			strings.write_byte(&t.output_builder, '$')
		}
		strings.write_string(&t.output_builder, t.source[arg.name.span.start:arg.name.span.end])
	}
	strings.write_string(&t.output_builder, ") ")

	// block
	if block, ok := fn.block.?; ok {
		emit_block(t, block)
	}
}

emit_fn_call :: proc(t: ^Transpiler, stmt: ^syntax.Fn_Call_Stmt) {
	if stmt.call.awaited {
		strings.write_string(&t.output_builder, "await ")
	}

	if is_js_reserved(t.source[stmt.call.name.span.start:stmt.call.name.span.end]) {
		strings.write_byte(&t.output_builder, '$')
	}
	write_lexeme(t, stmt.call.name)
	strings.write_string(&t.output_builder, "(")

	for arg, i in stmt.call.args {
		if i != 0 {
			strings.write_string(&t.output_builder, ", ")
		}

		emit_expr(t, arg)
	}

	strings.write_string(&t.output_builder, ")")
}

emit_ident_assignment :: proc(t: ^Transpiler, stmt: ^syntax.Ident_Assignment_Stmt) {
	Pair :: struct {
		names: [dynamic]syntax.Token,
		value: syntax.Expr,
	}

	pairs := make([dynamic]Pair, 0, len(stmt.names))
	defer {
		for pair in pairs {
			delete(pair.names)
		}
		delete(pairs)
	}

	name_i := 0
	for value in stmt.value {
		skip := 1
		if call, is_call := value.(^syntax.Fn_Call_Expr); is_call {
			if count, ok := call.return_count.?; ok {
				skip = count
			}
		}

		pair: Pair
		for j in 0 ..< skip {
			append(&pair.names, stmt.names[name_i + j])
		}
		pair.value = value
		append(&pairs, pair)

		name_i += skip
	}

	for pair, i in pairs {
		if i > 0 do strings.write_string(&t.output_builder, ", ")

		if len(pair.names) == 1 {
			emit_ident_token(t, pair.names[0])
		} else {
			strings.write_byte(&t.output_builder, '[')
			for name, j in pair.names {
				if j > 0 do strings.write_string(&t.output_builder, ", ")
				emit_ident_token(t, name)
			}
			strings.write_byte(&t.output_builder, ']')
		}

		strings.write_string(&t.output_builder, " = ")
		emit_expr(t, pair.value)
	}
}

emit_block :: proc(t: ^Transpiler, stmt: ^syntax.Block_Stmt) {
	strings.write_string(&t.output_builder, "{\n")
	t.indent += 1
	for inner in stmt.stmts {
		written_anything := emit_stmt(t, inner)
		if written_anything {
			strings.write_byte(&t.output_builder, '\n')
		}
	}
	t.indent -= 1
	write_indent(t)
	strings.write_byte(&t.output_builder, '}')
}

emit_return_stmt :: proc(t: ^Transpiler, stmt: ^syntax.Return_Stmt) {
	strings.write_string(&t.output_builder, "return")
	// Multi-value returns are emitted as a JS array.
	if len(stmt.exprs) == 1 {
		strings.write_byte(&t.output_builder, ' ')
		emit_expr(t, stmt.exprs[0])

	} else if len(stmt.exprs) > 1 {
		strings.write_string(&t.output_builder, " [")
		for e, i in stmt.exprs {
			if i != 0 do strings.write_string(&t.output_builder, ", ")

			if call, ok := e.(^syntax.Fn_Call_Expr); ok {
				if count, resolved := call.return_count.?; resolved && count > 1 {
					strings.write_string(&t.output_builder, "...")
				}
			}
			emit_expr(t, e)
		}
		strings.write_byte(&t.output_builder, ']')
	}

	strings.write_byte(&t.output_builder, ';')
}

emit_expr :: proc(t: ^Transpiler, expr: syntax.Expr) {
	switch expr in expr {
	case ^syntax.Literal_Expr:
		write_lexeme(t, expr.token)

	case ^syntax.Unary_Expr:
		#partial switch expr.op {
		case .Minus:
			strings.write_byte(&t.output_builder, '-')
		case .Bang:
			strings.write_byte(&t.output_builder, '!')
		}
		emit_expr(t, expr.right)

	case ^syntax.Binary_Expr:
		emit_expr(t, expr.left)
		strings.write_byte(&t.output_builder, ' ')
		strings.write_string(&t.output_builder, js_binary_op(expr.op))
		strings.write_byte(&t.output_builder, ' ')
		emit_expr(t, expr.right)

	case ^syntax.Grouping_Expr:
		strings.write_byte(&t.output_builder, '(')
		emit_expr(t, expr.expr)
		strings.write_byte(&t.output_builder, ')')

	case ^syntax.Ident_Expr:
		emit_ident_token(t, expr.token)

	case ^syntax.Fn_Literal_Expr:
		emit_fn_literal(t, expr, nil)

	case ^syntax.Logical_Expr:
		emit_expr(t, expr.left)
		strings.write_string(&t.output_builder, expr.op == .And ? " && " : " || ")
		emit_expr(t, expr.right)

	case ^syntax.Fn_Call_Expr:
		emit_ident_token(t, expr.name)
		strings.write_byte(&t.output_builder, '(')
		for arg, i in expr.args {
			if i != 0 do strings.write_string(&t.output_builder, ", ")
			emit_expr(t, arg)
		}
		strings.write_byte(&t.output_builder, ')')
	}
}

// Emits an identifier. Mangles the name with a `$` prefix if it would collide with a
// JS reserved word.
emit_ident_token :: proc(t: ^Transpiler, token: syntax.Token) {
	name := t.source[token.span.start:token.span.end]
	if is_js_reserved(name) {
		strings.write_byte(&t.output_builder, '$')
	}
	strings.write_string(&t.output_builder, name)
}

write_lexeme :: proc(t: ^Transpiler, tok: syntax.Token) {
	strings.write_string(&t.output_builder, t.source[tok.span.start:tok.span.end])
}

write_indent :: proc(t: ^Transpiler) {
	for _ in 0 ..< t.indent {
		strings.write_string(&t.output_builder, "  ")
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
// identifier - keywords, future reserved, contextual reserved. Some entries
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
