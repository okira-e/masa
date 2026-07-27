package syntax

Stmt :: union {
	^Expr_Stmt,
	^Ident_Decl_Stmt,
	^Ident_Assignment_Stmt,
	^Fn_Decl_Stmt,
	^Fn_Call_Stmt,
	^If_Stmt,
	^Block_Stmt,
	^Return_Stmt,
}

Expr_Stmt :: struct {
	expr: ^Expr,
	span: Span,
}

Ident_Decl_Stmt :: struct {
	names:     [dynamic]Token,
	value:     Maybe([dynamic]^Expr),
	constant:  bool,
	op:        Token,
	// Can be nil if no type was specified in the declaration
	type:      Maybe(Type),
	// Set in: analyzer
	decl_kind: Decl_Kind,
	span:      Span,
}

Ident_Assignment_Stmt :: struct {
	names: [dynamic]Token,
	value: [dynamic]^Expr, // nocheckin: Rename to values
	op:    Token,
	span:  Span,
}

Fn_Decl_Stmt :: struct {
	name:     Token,
	// The function's signature and body. Shared with anonymous Fn_Literal_Expr values.
	lit:      Fn_Literal_Expr,
	// The declared type from the typed constant form (`foo: fn()->T : fn()->T {}`).
	// nil for the bare `foo :: fn` form.
	type:     Maybe(Type),
	// Maybe this should be in the lit?
	receiver: Maybe(Fn_Receiver),
	span:     Span,
}

Fn_Arg :: struct {
	name: Token,
	type: Type,
	span: Span,
}

Fn_Receiver :: struct {
	param_name: string,
	on:         Token,
	span:       Span,
}

Fn_Call_Stmt :: struct {
	call: Fn_Call_Expr,
	// name:    Token,
	// args:    [dynamic]^Expr,
	// awaited: bool,
	span: Span,
}

If_Stmt :: struct {
	keyword:     Token,
	condition:   ^Expr,
	then_block:  Stmt,
	// Should either be a Block_Stmt of an If_Stmt
	else_branch: Maybe(Stmt),
	span:        Span,
}

Block_Stmt :: struct {
	stmts: []Stmt,
	span:  Span,
}

Return_Stmt :: struct {
	keyword: Token,
	exprs:   [dynamic]^Expr,
	span:    Span,
}

Decl_Kind :: enum {
	Value,
	Type_Alias,
}

span_of_stmt :: proc(stmt: Stmt) -> Span {
	switch s in stmt {
	case ^Expr_Stmt:
		return s.span
	case ^Ident_Decl_Stmt:
		return s.span
	case ^Ident_Assignment_Stmt:
		return s.span
	case ^Fn_Decl_Stmt:
		return s.span
	case ^Fn_Call_Stmt:
		return s.span
	case ^If_Stmt:
		return s.span
	case ^Block_Stmt:
		return s.span
	case ^Return_Stmt:
		return s.span
	}

	unreachable()
}
