package syntax

Stmt :: union {
	Expr_Stmt,
	Ident_Decl_Stmt,
	Ident_Assignment_Stmt,
	If_Stmt,
	Block_Stmt,
}

Expr_Stmt :: struct {
	expr: ^Expr,
}

Ident_Decl_Stmt :: struct {
	name:          Token,
	value:         Maybe(^Expr),
	constant:      bool,
	type:          Maybe(Type),
	// Set in: analyzer
	decl_kind:     Decl_Kind,
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