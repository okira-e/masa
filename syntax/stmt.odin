package syntax

Stmt :: union {
	Expr_Stmt,
}

Expr_Stmt :: struct {
	expr: ^Expr,
}
