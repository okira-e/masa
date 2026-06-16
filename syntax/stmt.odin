package syntax

Stmt :: union {
	Expr_Stmt,
	Ident_Decl_Stmt,
	Ident_Assignment_Stmt,
	Fn_Decl_Stmt,
	If_Stmt,
	Block_Stmt,
}

Expr_Stmt :: struct {
	expr: ^Expr,
}

Ident_Decl_Stmt :: struct {
	name:          Token,
	// Could either be a value expression or a block statement in the case of function declaration
	value:         Maybe(^Stmt),
	constant:      bool,
	type:          Maybe(Type),
	// Set in: analyzer
	decl_kind:     Decl_Kind,
}

Fn_Decl_Stmt :: struct {
	name:        Token,
	block:       Maybe(^Block_Stmt),
	return_type: Maybe([dynamic]Token),
	args:        [dynamic]Fn_Arg,
	receiver:    Maybe(Fn_Receiver),
	async:       bool,
	// A function declaration that's just a signature without a body
	stub:        bool,
}

Fn_Arg :: struct {
	name: Token,
	type: Token,
}

Fn_Receiver :: struct {
	param_name: string,
	on:         Token,
}

Fn_Call_Stmt :: struct {
	name:    Token,
	args:    [dynamic]Token,
	awaited: bool,
}

Ident_Assignment_Stmt :: struct {
	name:  Token,
	value: ^Expr,
}

If_Stmt :: struct {
	condition:   ^Expr,
	then_block:  ^Stmt,
	// Should either be a Block_Stmt of an If_Stmt
	else_branch: Maybe(^Stmt),
}

Block_Stmt :: struct {
	stmts: []^Stmt,
}

Decl_Kind :: enum {
	Value,
	Type_Alias,
}