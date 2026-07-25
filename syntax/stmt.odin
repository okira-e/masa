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
}

Ident_Decl_Stmt :: struct {
	names:     [dynamic]Token,
	value:     Maybe([dynamic]^Expr),
	constant:  bool,
	// Can be nil if no type was specified in the declaration
	type:      Maybe(Type),
	// Set in: analyzer
	decl_kind: Decl_Kind,
}

Ident_Assignment_Stmt :: struct {
	names: [dynamic]Token,
	value: [dynamic]^Expr, // nocheckin: Rename to values
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
}

Fn_Arg :: struct {
	name: Token,
	type: Type,
}

Fn_Receiver :: struct {
	param_name: string,
	on:         Token,
}

Fn_Call_Stmt :: struct {
	call: Fn_Call_Expr,
	// name:    Token,
	// args:    [dynamic]^Expr,
	// awaited: bool,
}

If_Stmt :: struct {
	condition:   ^Expr,
	then_block:  Stmt,
	// Should either be a Block_Stmt of an If_Stmt
	else_branch: Maybe(Stmt),
}

Block_Stmt :: struct {
	stmts: []Stmt,
}

Return_Stmt :: struct {
	exprs: [dynamic]^Expr,
}

Decl_Kind :: enum {
	Value,
	Type_Alias,
}

