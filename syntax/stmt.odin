package syntax

Stmt :: union {
	Expr_Stmt,
	Ident_Decl_Stmt,
}

Expr_Stmt :: struct {
	expr: ^Expr,
}

Ident_Decl_Stmt :: struct {
	name:    Token,
	value:   ^Expr,
	mutable: bool,
}
