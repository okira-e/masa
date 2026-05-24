package parser

import "core:os"
import "../syntax"
import "core:fmt"
import "core:mem"

/*

Parser development guide/rules:
	- Outer loop doesn't advance
	- Each rule advances on match
	- On a match, you can use other rules
	- Remain simple

*/

/*
Grammar in BNF notation:

- expression 	-> logic_or ;
- logic_or 		-> logic_and ( "or" logic_and )* ;
- logic_and 	-> equality ( "and" equality )* ;
- equality 		-> comparison ( ( "!=" | "==" ) comparison )* ;
- comparison 	-> term ( ( ">" | ">=" | "<" | "<=" ) term )* ;
- term 			-> factor ( ( "-" | "+" ) factor )* ;
- factor 		-> unary ( ( "/" | "*" ) unary )* ;
- unary 		-> ( "!" | "-" ) unary | primary ;
- primary 		-> NUMBER | STRING | "true" | "false" | "nil" | "(" expression ")" ;
*/
Parser :: struct {
	tokens:    []syntax.Token,
	current:   int,
	allocator: mem.Allocator,
}

init :: proc(parser: ^Parser, tokens: []syntax.Token, allocator := context.allocator) {
	parser.current = 0
	parser.tokens = tokens
	parser.allocator = allocator
}

parse :: proc(parser: ^Parser) -> ([dynamic]^syntax.Stmt, Maybe(Parser_Error)) {
	if len(parser.tokens) == 0 {
		return nil, Parser_Error{kind = .Empty_Tokens, message = "No tokens found"}
	}

	if parser.tokens[len(parser.tokens) - 1].kind != .EOF {
		return nil, Parser_Error {
			kind = .Missing_EOF,
			message = "Missing EOF token at the end of the token list",
		}
	}

	// worst case: assume one statement per token
	stmts := make([dynamic]^syntax.Stmt, 0, len(parser.tokens), allocator = parser.allocator)

	for !is_at_end(parser) {
		skip_newlines(parser)
		if is_at_end(parser) {
			break
		}

		stmt, parser_err := parse_stmt(parser)
		if parser_err != nil do return stmts, parser_err

		append(&stmts, stmt)
		skip_newlines(parser)
	}

	return stmts, nil
}

parse_stmt :: proc(parser: ^Parser) -> (^syntax.Stmt, Maybe(Parser_Error)) {
	current := parser.tokens[parser.current]
	#partial switch current.kind {
	case .Ident:
		next, ok := peek_next(parser)
		if ok && (next.kind == .Colon_Equal || next.kind == .Colon_Colon) {
			return parse_ident_decl(parser)
		}

	case .Keyword:
		return parse_keyword(parser, current)
	}

	// TODO: statements that depend on the next token like assignments.

	// Expression statements
	expr, err := parse_expr(parser)
	if err != nil do return nil, err

	stmt := new(syntax.Stmt, allocator = parser.allocator)
	stmt^ = syntax.Expr_Stmt{expr = expr}
	return stmt, nil
}

parse_keyword :: proc(parser: ^Parser, token: syntax.Token) -> (^syntax.Stmt, Maybe(Parser_Error)) {
	keyword, ok := token.keyword.?
	assert(ok)

	#partial switch keyword {
	case .If:
		return parse_if(parser)

	case .Else:
		return nil, Parser_Error {
			kind = .Else_With_No_If,
			message = "'else' without a matching 'if'",
			token = token,
		}
	}

	return nil, Parser_Error {
		kind = .Unexpected_Token,
		message = "keyword cannot start a statement",
		token = token,
	}
}

parse_if :: proc(parser: ^Parser) -> (^syntax.Stmt, Maybe(Parser_Error)) {
	advance(parser) // consume `if`

	condition, cond_err := parse_expr(parser)
	if cond_err != nil do return nil, cond_err

	skip_newlines(parser)

	then_block, then_err := parse_block(parser)
	if then_err != nil do return nil, then_err

	else_branch: Maybe(^syntax.Stmt)
	tok := parser.tokens[parser.current]
	if tok.kind == .Keyword && tok.keyword == .Else {
		advance(parser) // consume `else`
		skip_newlines(parser)

		next := parser.tokens[parser.current]
		if next.kind == .Keyword && next.keyword == .If {
			else_stmt, err := parse_if(parser)
			if err != nil do return nil, err
			else_branch = else_stmt
		} else {
			else_stmt, err := parse_block(parser)
			if err != nil do return nil, err
			else_branch = else_stmt
		}
	}

	stmt := new(syntax.Stmt, allocator = parser.allocator)
	stmt^ = syntax.If_Stmt {
		condition   = condition,
		then_block  = then_block,
		else_branch = else_branch,
	}

	return stmt, nil
}

parse_ident_decl :: proc(parser: ^Parser) -> (^syntax.Stmt, Maybe(Parser_Error)) {
	name := parser.tokens[parser.current]
	advance(parser)

	op := parser.tokens[parser.current]
	advance(parser)

	value, err := parse_expr(parser)
	if err != nil do return nil, err

	stmt := new(syntax.Stmt, allocator = parser.allocator)
	stmt^ = syntax.Ident_Decl_Stmt {
		name    = name,
		value   = value,
		mutable = op.kind == .Colon_Equal,
	}

	return stmt, nil
}

parse_block :: proc(parser: ^Parser) -> (^syntax.Stmt, Maybe(Parser_Error)) {
	open := parser.tokens[parser.current]
	if open.kind != .Left_Brace {
		return nil, Parser_Error {
			kind = .Unexpected_Token,
			message = "expected '{' to start block",
			token = open,
		}
	}
	advance(parser)

	inner := make([dynamic]^syntax.Stmt, 0, 8, allocator = parser.allocator)

	for {
		skip_newlines(parser)

		tok := parser.tokens[parser.current]
		if tok.kind == .Right_Brace {
			advance(parser)
			break
		}
		if tok.kind == .EOF {
			return nil, Parser_Error {
				kind = .Unexpected_EOF,
				message = "unexpected EOF while parsing block — missing '}'",
				token = tok,
			}
		}

		s, err := parse_stmt(parser)
		if err != nil do return nil, err
		append(&inner, s)
	}

	stmt := new(syntax.Stmt, allocator = parser.allocator)
	stmt^ = syntax.Block_Stmt{stmts = inner[:]}
	return stmt, nil
}

parse_expr :: proc(parser: ^Parser) -> (^syntax.Expr, Maybe(Parser_Error)) {
	expr, err := parse_logic_or(parser)
	if err != nil do return expr, err

	return expr, nil
}

parse_logic_or :: proc(parser: ^Parser) -> (^syntax.Expr, Maybe(Parser_Error)) {
	expr, err := parse_logic_and(parser)
	if err != nil do return expr, err

	for {
		tok, is_eof := get_current_token(parser)
		if is_eof || tok.kind != .Keyword || tok.keyword != .Or {
			break
		}

		advance(parser)

		right, rerr := parse_logic_and(parser)
		if rerr != nil do return expr, rerr

		result := new(syntax.Expr, allocator = parser.allocator)
		result^ = syntax.Expr {
			expr = syntax.Logical_Expr{left = expr, op = .Or, right = right},
		}
		expr = result
	}

	return expr, nil
}

parse_logic_and :: proc(parser: ^Parser) -> (^syntax.Expr, Maybe(Parser_Error)) {
	expr, err := parse_equality(parser)
	if err != nil do return expr, err

	for {
		tok, is_eof := get_current_token(parser)
		if is_eof || tok.kind != .Keyword || tok.keyword != .And {
			break
		}

		advance(parser)

		right, rerr := parse_equality(parser)
		if rerr != nil do return expr, rerr

		result := new(syntax.Expr, allocator = parser.allocator)
		result^ = syntax.Expr {
			expr = syntax.Logical_Expr{left = expr, op = .And, right = right},
		}
		expr = result
	}

	return expr, nil
}

parse_equality :: proc(parser: ^Parser) -> (^syntax.Expr, Maybe(Parser_Error)) {
	expr, err := parse_comparison(parser)
	if err != nil do return expr, err

	for {
		current_token, is_eof := get_current_token(parser)
		if is_eof || !matches(current_token.kind, .Bang_Equal, .Equal_Equal) {
			break
		}

		advance(parser)

		right, err := parse_comparison(parser)
		if err != nil do return expr, err

		result := new(syntax.Expr, allocator = parser.allocator)
		result^ = syntax.Expr {
			expr = syntax.Binary_Expr{left = expr, op = current_token.kind, right = right},
		}
		expr = result
	}

	return expr, nil
}

parse_comparison :: proc(parser: ^Parser) -> (^syntax.Expr, Maybe(Parser_Error)) {
	expr, err := parse_term(parser)
	if err != nil do return expr, err

	for {
		current_token, is_eof := get_current_token(parser)
		if is_eof || !matches(current_token.kind, .Greater, .Greater_Equal, .Less, .Less_Equal) {
			break
		}

		advance(parser)

		right, err := parse_term(parser)
		if err != nil do return expr, err

		result := new(syntax.Expr, allocator = parser.allocator)
		result^ = syntax.Expr {
			expr = syntax.Binary_Expr{left = expr, op = current_token.kind, right = right},
		}
		expr = result
	}

	return expr, nil
}

parse_term :: proc(parser: ^Parser) -> (^syntax.Expr, Maybe(Parser_Error)) {
	expr, err := parse_factor(parser)
	if err != nil do return expr, err

	for {
		current_token, is_eof := get_current_token(parser)
		if is_eof || !matches(current_token.kind, .Minus, .Plus) {
			break
		}

		advance(parser)

		right, err := parse_factor(parser)
		if err != nil do return expr, err

		result := new(syntax.Expr, allocator = parser.allocator)
		result^ = syntax.Expr {
			expr = syntax.Binary_Expr{left = expr, op = current_token.kind, right = right},
		}
		expr = result
	}

	return expr, nil
}

parse_factor :: proc(parser: ^Parser) -> (^syntax.Expr, Maybe(Parser_Error)) {
	expr, err := parse_unary(parser)
	if err != nil do return expr, err

	for {
		current_token, is_eof := get_current_token(parser)
		if is_eof || !matches(current_token.kind, .Slash, .Star) {
			break
		}

		advance(parser)

		right, err := parse_unary(parser)
		if err != nil do return expr, err

		result := new(syntax.Expr, allocator = parser.allocator)
		result^ = syntax.Expr {
			expr = syntax.Binary_Expr{left = expr, op = current_token.kind, right = right},
		}
		expr = result
	}

	return expr, nil
}

parse_unary :: proc(parser: ^Parser) -> (^syntax.Expr, Maybe(Parser_Error)) {
	current_token, is_eof := get_current_token(parser)
	if is_eof {
		return nil, Parser_Error {
			kind = .Unexpected_EOF,
			message = "Unexpected \"EOF\" token while parsing unary",
			token = parser.tokens[max(parser.current - 1, 0)],
		}
	}

	if matches(current_token.kind, .Bang, .Minus) {
		advance(parser)

		right, err := parse_unary(parser)
		if err != nil do return nil, err

		result := new(syntax.Expr, allocator = parser.allocator)
		result^ = syntax.Expr {
			expr = syntax.Unary_Expr{op = current_token.kind, right = right},
		}
		return result, nil
	}

	return parse_primary(parser)
}

parse_primary :: proc(parser: ^Parser) -> (^syntax.Expr, Maybe(Parser_Error)) {
	expr := new(syntax.Expr, allocator = parser.allocator)

	current_token, is_eof := get_current_token(parser)
	if is_eof {
		return expr, Parser_Error {
			kind = .Unexpected_EOF,
			message = "Unexpected \"EOF\" token while parsing primary",
			token = parser.tokens[max(parser.current - 1, 0)],
		}
	}

	#partial switch current_token.kind {
	case .Literal:
		result := syntax.Expr {
			expr = syntax.Literal_Expr{token = current_token},
		}
		expr^ = result
		advance(parser)

	case .Ident:
		expr^ = syntax.Expr {
			expr = syntax.Ident_Expr{token = current_token},
		}
		advance(parser)

	case .Left_Paren:
		advance(parser)
		expr_inner, err := parse_expr(parser)
		if err != nil do return expr, err

		current_token, is_eof := get_current_token(parser)
		if is_eof || current_token.kind != .Right_Paren {
			return expr, Parser_Error {
				kind = .UnclosedParen,
				message = "Expected a \")\" token",
				token = current_token,
			}
		}

		advance(parser)

		expr^ = syntax.Expr {
			expr = syntax.Grouping_Expr{expr = expr_inner},
		}

	case:
		return expr, Parser_Error {
			kind = .Unexpected_Token,
			message = "Unexpected token while parsing primary",
			token = current_token,
		}

	}

	return expr, nil
}

// Advances and returns: previous token, success
advance :: proc(parser: ^Parser) -> (syntax.Token, bool) {
	prev := parser.tokens[parser.current]
	if prev.kind != .EOF {
		parser.current += 1
		return prev, true
	} else {
		return syntax.Token{}, false
	}
}

peek_next :: proc(parser: ^Parser) -> (syntax.Token, bool) {
	if parser.current >= len(parser.tokens) - 1 {
		return syntax.Token{}, false
	}

	return parser.tokens[parser.current + 1], true
}

is_at_end :: proc(parser: ^Parser) -> bool {
	return parser.current < len(parser.tokens) && parser.tokens[parser.current].kind == .EOF
}

matches :: proc(lhs: syntax.Token_Kind, rhs: ..syntax.Token_Kind) -> bool {
	for r in rhs {
		if r == lhs {
			return true
		}
	}

	return false
}

// Returns the current token with a flag for if the token is the EOF one.
get_current_token :: proc(parser: ^Parser) -> (syntax.Token, bool) {
	token := parser.tokens[parser.current]
	if token.kind == .EOF {
		return syntax.Token{}, true
	}

	return token, false
}

skip_newlines :: proc(parser: ^Parser) {
	for parser.tokens[parser.current].kind == .New_Line {
		advance(parser)
	}
}

Parser_Error :: struct {
	kind:    Parser_Error_Kind,
	token:   syntax.Token,
	message: string,
}

Parser_Error_Kind :: enum {
	Unexpected_EOF,
	Empty_Tokens,
	Missing_EOF,
	UnclosedParen,
	Unexpected_Token,
	Else_With_No_If,
}

parser_error_to_string :: proc(err: Parser_Error, allocator := context.allocator) -> string {
	switch err.kind {
	case .Unexpected_EOF:
		return fmt.aprintf(
			"Unexpected EOF token at line %d, column %d",
			err.token.line,
			err.token.column,
			allocator = allocator,
		)

	case .Empty_Tokens:
		return fmt.aprintf("No tokens found", allocator = allocator)

	case .Missing_EOF:
		return fmt.aprintf("Missing EOF token at the end of the token list", allocator = allocator)

	case .UnclosedParen:
		return fmt.aprintf(
			"Expected a \")\" token to close the parenthesis opened at line %d, column %d",
			err.token.line,
			err.token.column,
			allocator = allocator,
		)

	case .Unexpected_Token:
		return fmt.aprintf(
			"Unexpected token of kind %s at line %d, column %d",
			err.token.kind,
			err.token.line,
			err.token.column,
			allocator = allocator,
		)

	case .Else_With_No_If:
		return fmt.aprintf(
			"Found an else with no if",
			err.token.kind,
			err.token.line,
			err.token.column,
			allocator = allocator,
		)
	}

	return fmt.aprintf("", allocator = allocator)
}
