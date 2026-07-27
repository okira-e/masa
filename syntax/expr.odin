package syntax

Expr_Variant :: union {
	Literal_Expr,
	Unary_Expr,
	Binary_Expr,
	Grouping_Expr,
	Ident_Expr,
	Logical_Expr,
	Fn_Call_Expr,
	Fn_Literal_Expr,
}

Expr :: struct {
	expr: Expr_Variant,
	span: Span,
}

Literal_Expr :: struct {
	token: Token,
}

Unary_Expr :: struct {
	op:      Token_Kind,
	op_span: Span,
	right:   ^Expr,
}

Binary_Expr :: struct {
	left:    ^Expr,
	op:      Token_Kind,
	op_span: Span,
	right:   ^Expr,
}

Grouping_Expr :: struct {
	expr: ^Expr,
}

Ident_Expr :: struct {
	token: Token,
}

Logical_Expr :: struct {
	left:    ^Expr,
	op:      Keyword, // .And or .Or
	op_span: Span,
	right:   ^Expr,
}

Fn_Call_Expr :: struct {
	name:    Token,
	args:    [dynamic]^Expr,
	awaited: bool,
	span:    Span,
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

expr_eq :: proc(a: ^Expr, b: ^Expr) -> bool {
	if a == nil || b == nil {
		return false
	}

	switch a_expr in a.expr {
	case Binary_Expr:
		{
			if _, ok := b.expr.(Binary_Expr); !ok {
				return false
			}

			casted_a := a.expr.(Binary_Expr)
			casted_b := b.expr.(Binary_Expr)

			return(
				expr_eq(casted_a.left, casted_b.left) &&
				casted_a.op == casted_b.op &&
				expr_eq(casted_a.right, casted_b.right) \
			)
		}
	case Literal_Expr:
		{
			if _, ok := b.expr.(Literal_Expr); !ok {
				return false
			}

			return a.expr.(Literal_Expr).token == b.expr.(Literal_Expr).token
		}
	case Unary_Expr:
		{
			if _, ok := b.expr.(Unary_Expr); !ok {
				return false
			}

			casted_a := a.expr.(Unary_Expr)
			casted_b := b.expr.(Unary_Expr)

			return expr_eq(casted_a.right, casted_b.right) && casted_a.op == casted_b.op
		}
	case Grouping_Expr:
		{
			if _, ok := b.expr.(Grouping_Expr); !ok {
				return false
			}

			casted_a := a.expr.(Grouping_Expr)
			casted_b := b.expr.(Grouping_Expr)

			return expr_eq(casted_a.expr, casted_b.expr)
		}
	case Ident_Expr:
		{
			if _, ok := b.expr.(Ident_Expr); !ok {
				return false
			}

			return a.expr.(Ident_Expr).token == b.expr.(Ident_Expr).token
		}
	case Logical_Expr:
		{
			if _, ok := b.expr.(Logical_Expr); !ok {
				return false
			}

			casted_a := a.expr.(Logical_Expr)
			casted_b := b.expr.(Logical_Expr)

			return(
				expr_eq(casted_a.left, casted_b.left) &&
				casted_a.op == casted_b.op &&
				expr_eq(casted_a.right, casted_b.right) \
			)
		}
	case Fn_Call_Expr:
		{
			if _, ok := b.expr.(Fn_Call_Expr); !ok {
				return false
			}

			casted_a := a.expr.(Fn_Call_Expr)
			casted_b := b.expr.(Fn_Call_Expr)

			if casted_a.name != casted_b.name {
				return false
			}
			if len(casted_a.args) != len(casted_b.args) {
				return false
			}
			for arg, i in casted_a.args {
				if arg != casted_b.args[i] {
					return false
				}
			}
			return true
		}
	case Fn_Literal_Expr:
		{
			casted_b, ok := b.expr.(Fn_Literal_Expr)
			if !ok {
				return false
			}

			casted_a := a.expr.(Fn_Literal_Expr)

			if casted_a.async != casted_b.async {
				return false
			}

			_, a_has_block := casted_a.block.?
			_, b_has_block := casted_b.block.?
			if a_has_block != b_has_block {
				return false
			}

			if len(casted_a.args) != len(casted_b.args) {
				return false
			}
			for arg, i in casted_a.args {
				if arg.name != casted_b.args[i].name || !type_eq(arg.type, casted_b.args[i].type) {
					return false
				}
			}

			a_ret, a_has_ret := casted_a.return_type.?
			b_ret, b_has_ret := casted_b.return_type.?
			if a_has_ret != b_has_ret {
				return false
			}
			if a_has_ret {
				if len(a_ret) != len(b_ret) {
					return false
				}
				for ret, i in a_ret {
					if !type_eq(ret, b_ret[i]) {
						return false
					}
				}
			}

			return true
		}
	}

	return false
}
