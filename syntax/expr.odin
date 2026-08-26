package syntax

Expr :: union {
	^Literal_Expr,
	^Unary_Expr,
	^Binary_Expr,
	^Grouping_Expr,
	^Ident_Expr,
	^Logical_Expr,
	^Fn_Call_Expr,
	^Fn_Literal_Expr,
}

Literal_Expr :: struct {
	token: Token,
	span:  Span,
}

Unary_Expr :: struct {
	op:      Token_Kind,
	op_span: Span,
	right:   Expr,
	span:    Span,
}

Binary_Expr :: struct {
	left:    Expr,
	op:      Token_Kind,
	op_span: Span,
	right:   Expr,
	span:    Span,
}

Grouping_Expr :: struct {
	expr: Expr,
	span: Span,
}

Ident_Expr :: struct {
	token: Token,
	span:  Span,
	// Set by the analyzer when this identifier names a compile-time value.
	constant_value: Maybe(Expr),
	// Set by the analyzer when this identifier resolves to a named function.
	resolved_fn: Maybe(^Fn_Decl_Stmt),
}

Logical_Expr :: struct {
	left:    Expr,
	op:      Keyword, // .And or .Or
	op_span: Span,
	right:   Expr,
	span:    Span,
}

Fn_Call_Expr :: struct {
	name:    Token,
	args:    [dynamic]Expr,
	awaited: bool,
	span:    Span,
	// Set by the analyzer: nil until resolved, then the number of produced values.
	return_count: Maybe(int),
	/*
	Set when the callee resolves to a procedure alias at compile time.

	Example:
		callback :: foo
	*/
	constant_callee: Maybe(Expr),
	/*
	Set when the callee resolves directly to a named function rather than
	through a mutable variable (`foo := fn() {}`).

	Example:
		foo :: fn() {}
	*/
	resolved_fn: Maybe(^Fn_Decl_Stmt),
}

Fn_Literal_Expr :: struct {
	block:       Maybe(^Block_Stmt),
	// Syntactic (unresolved) return types. The analyzer resolves these into
	// its own `Type` during checking. One entry per declared return value.
	return_type: Maybe([dynamic]Type),
	args:        [dynamic]Fn_Arg,
	async:       bool,
	span:        Span,
}

span_of_expr :: proc(expr: Expr) -> Span {
	switch e in expr {
	case ^Literal_Expr:    return e.span
	case ^Unary_Expr:      return e.span
	case ^Binary_Expr:     return e.span
	case ^Grouping_Expr:   return e.span
	case ^Ident_Expr:      return e.span
	case ^Logical_Expr:    return e.span
	case ^Fn_Call_Expr:    return e.span
	case ^Fn_Literal_Expr: return e.span
	}

	assert(false)
	unreachable()
}

expr_eq :: proc(a: Expr, b: Expr) -> bool {
	if a == nil || b == nil {
		return false
	}

	switch casted_a in a {
	case ^Binary_Expr:
		casted_b, ok := b.(^Binary_Expr)
		if !ok do return false
		return(
			expr_eq(casted_a.left, casted_b.left) &&
			casted_a.op == casted_b.op &&
			expr_eq(casted_a.right, casted_b.right) \
		)

	case ^Literal_Expr:
		casted_b, ok := b.(^Literal_Expr)
		return ok && casted_a.token == casted_b.token

	case ^Unary_Expr:
		casted_b, ok := b.(^Unary_Expr)
		return ok && casted_a.op == casted_b.op && expr_eq(casted_a.right, casted_b.right)

	case ^Grouping_Expr:
		casted_b, ok := b.(^Grouping_Expr)
		return ok && expr_eq(casted_a.expr, casted_b.expr)

	case ^Ident_Expr:
		casted_b, ok := b.(^Ident_Expr)
		return ok && casted_a.token == casted_b.token

	case ^Logical_Expr:
		casted_b, ok := b.(^Logical_Expr)
		if !ok do return false
		return(
			expr_eq(casted_a.left, casted_b.left) &&
			casted_a.op == casted_b.op &&
			expr_eq(casted_a.right, casted_b.right) \
		)

	case ^Fn_Call_Expr:
		casted_b, ok := b.(^Fn_Call_Expr)
		if !ok || casted_a.name != casted_b.name || len(casted_a.args) != len(casted_b.args) {
			return false
		}
		for arg, i in casted_a.args {
			if !expr_eq(arg, casted_b.args[i]) do return false
		}
		return true

	case ^Fn_Literal_Expr:
		casted_b, ok := b.(^Fn_Literal_Expr)
		if !ok || casted_a.async != casted_b.async {
			return false
		}

		_, a_has_block := casted_a.block.?
		_, b_has_block := casted_b.block.?
		if a_has_block != b_has_block || len(casted_a.args) != len(casted_b.args) {
			return false
		}
		for arg, i in casted_a.args {
			if arg.name != casted_b.args[i].name || !type_eq(arg.type, casted_b.args[i].type) {
				return false
			}
		}

		a_ret, a_has_ret := casted_a.return_type.?
		b_ret, b_has_ret := casted_b.return_type.?
		if a_has_ret != b_has_ret do return false
		if a_has_ret {
			if len(a_ret) != len(b_ret) do return false
			for ret, i in a_ret {
				if !type_eq(ret, b_ret[i]) do return false
			}
		}
		return true
	}

	return false
}
