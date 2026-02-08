package parser

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

- expression 	-> equality ;
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

parse :: proc(parser: ^Parser) -> ([dynamic]^syntax.Expr, Maybe(Parser_Error)) {
	if len(parser.tokens) == 0 {
		return nil, Parser_Error{kind = .Empty_Tokens, message = "No tokens found"}
	}

	if parser.tokens[len(parser.tokens) - 1].kind != .EOF {
		return nil, Parser_Error {
			kind = .Missing_EOF,
			message = "Missing EOF token at the end of the token list",
		}
	}

	// worst case: assume one expression per token
	exprs := make([dynamic]^syntax.Expr, 0, len(parser.tokens), allocator = parser.allocator)

	for !is_at_end(parser) {
		expr, parser_err := parse_expr(parser)
		if parser_err != nil {
			return exprs, parser_err
		}

		append(&exprs, expr)
	}

	return exprs, nil
}

parse_expr :: proc(parser: ^Parser) -> (^syntax.Expr, Maybe(Parser_Error)) {
	expr, err := parse_equality(parser)
	if err != nil {
		return expr, err
	}

	return expr, nil
}

parse_equality :: proc(parser: ^Parser) -> (^syntax.Expr, Maybe(Parser_Error)) {
	expr, err := parse_comparison(parser)
	if err != nil {
		return expr, err
	}

	for {
		current_token, isEOF := get_current_token(parser)
		if isEOF || !matches(current_token.kind, .Bang_Equal, .Equal_Equal) {
			break
		}

		advance(parser)

		right, err := parse_comparison(parser)
		if err != nil {
			return expr, err
		}

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
	if err != nil {
		return expr, err
	}

	for {
		current_token, isEOF := get_current_token(parser)
		if isEOF || !matches(current_token.kind, .Greater, .Greater_Equal, .Less, .Less_Equal) {
			break
		}

		advance(parser)

		right, err := parse_term(parser)
		if err != nil {
			return expr, err
		}

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
	if err != nil {
		return expr, err
	}

	for {
		current_token, isEOF := get_current_token(parser)
		if isEOF || !matches(current_token.kind, .Minus, .Plus) {
			break
		}

		advance(parser)

		right, err := parse_factor(parser)
		if err != nil {
			return expr, err
		}

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
	if err != nil {
		return expr, err
	}

	for {
		current_token, isEOF := get_current_token(parser)
		if isEOF || !matches(current_token.kind, .Slash, .Star) {
			break
		}

		advance(parser)

		right, err := parse_unary(parser)
		if err != nil {
			return expr, err
		}

		result := new(syntax.Expr, allocator = parser.allocator)
		result^ = syntax.Expr {
			expr = syntax.Binary_Expr{left = expr, op = current_token.kind, right = right},
		}
		expr = result
	}

	return expr, nil
}

parse_unary :: proc(parser: ^Parser) -> (^syntax.Expr, Maybe(Parser_Error)) {
	current_token, isEOF := get_current_token(parser)
	if isEOF {
		return nil, Parser_Error {
			kind = .Unexpected_EOF,
			message = "Unexpected \"EOF\" token while parsing unary",
			token = parser.tokens[max(parser.current - 1, 0)],
		}
	}

	if matches(current_token.kind, .Bang, .Minus) {
		advance(parser)

		right, err := parse_unary(parser)
		if err != nil {
			return nil, err
		}

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

	current_token, isEOF := get_current_token(parser)
	if isEOF {
		return expr, Parser_Error {
			kind = .Unexpected_EOF,
			message = "Unexpected \"EOF\" token while parsing primary",
			token = parser.tokens[max(parser.current - 1, 0)],
		}
	}

	#partial switch current_token.kind {
	case .Literal:
		{
			result := syntax.Expr {
				expr = syntax.Literal_Expr{token = current_token},
			}
			expr^ = result
			advance(parser)
		}
	case .Left_Paren:
		{
			advance(parser)
			expr_inner, err := parse_expr(parser)
			if err != nil {
				return expr, err
			}

			current_token, isEOF := get_current_token(parser)
			if isEOF || current_token.kind != .Right_Paren {
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
		}
	case:
		{
			return expr, Parser_Error {
				kind = .Unexpected_Token,
				message = "Unexpected token while parsing primary",
				token = current_token,
			}
		}
	}

	return expr, nil
}

// Advances and returns: previous token, success
@(private)
advance :: proc(parser: ^Parser) -> (syntax.Token, bool) {
	prev := parser.tokens[parser.current]
	if prev.kind != .EOF {
		parser.current += 1
		return prev, true
	} else {
		return syntax.Token{}, false
	}
}

@(private)
peek :: proc(parser: ^Parser) -> ^syntax.Token {
	assert(parser.current < len(parser.tokens))
	return &parser.tokens[parser.current + 1]
}

@(private)
is_at_end :: proc(parser: ^Parser) -> bool {
	return parser.current < len(parser.tokens) && parser.tokens[parser.current].kind == .EOF
}

@(private)
matches :: proc(lhs: syntax.Token_Kind, rhs: ..syntax.Token_Kind) -> bool {
	for r in rhs {
		if r == lhs {
			return true
		}
	}

	return false
}

// Returns the current token with a flag for if the token is the EOF one.
@(private)
get_current_token :: proc(parser: ^Parser) -> (syntax.Token, bool) {
	token := parser.tokens[parser.current]
	if token.kind == .EOF {
		return syntax.Token{}, true
	}

	return token, false
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
}

parser_error_to_string :: proc(err: Parser_Error, alloc := context.allocator) -> string {
	switch err.kind {
	case .Unexpected_EOF:
		return fmt.aprintf(
			"Unexpected EOF token at line %d, column %d",
			err.token.line,
			err.token.column,
			allocator = alloc,
		)

	case .Empty_Tokens:
		return fmt.aprintf("No tokens found", allocator = alloc)

	case .Missing_EOF:
		return fmt.aprintf("Missing EOF token at the end of the token list", allocator = alloc)

	case .UnclosedParen:
		return fmt.aprintf(
			"Expected a \")\" token to close the parenthesis opened at line %d, column %d",
			err.token.line,
			err.token.column,
			allocator = alloc,
		)

	case .Unexpected_Token:
		return fmt.aprintf(
			"Unexpected token of kind %s at line %d, column %d",
			err.token.kind,
			err.token.line,
			err.token.column,
			allocator = alloc,
		)
	}

	return fmt.aprintf("", allocator = alloc)
}
