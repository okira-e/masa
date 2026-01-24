package parser

import "../syntax"

/*
Grammer in BNF notation:

- expression -> literal | unary | binary | grouping
- literal    -> NUMBER | STRING | "true" | "false" | "nil"
- grouping   -> "(" expression ")"
- unary      -> ( "-" | "!" ) expression
- binary     -> expression operator expression
- operator   -> "==" | "!=" | "<" | "<=" | ">" | ">=" | "+" | "-" | "*" | "/"
*/
Parser :: struct {}

init :: proc(parser: ^Parser) {

}

parse :: proc(parser: ^Parser, tokens: [dynamic]syntax.Token) {

}
