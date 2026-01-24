package syntax

Expr_Kind :: union {
	Literal_Expr,
	Unary_Expr,
	Binary_Expr,
	Grouping_Expr,
}

Expr :: struct {
	expr: Expr_Kind,
}

Literal_Expr :: struct {
	token: Token, // Since lexemes are not actaully stored in token, it's cheap to copy
}

Unary_Expr :: struct {
	op:    Token_Kind,
	right: ^Expr,
}

Binary_Expr :: struct {
	left:  ^Expr,
	op:    Token_Kind,
	right: ^Expr,
}

Grouping_Expr :: struct {
	expr: ^Expr,
}
