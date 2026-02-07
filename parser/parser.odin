package parser

import "../syntax"
import "core:mem"

/*

Parser development guide/rules:
	- Outer loop doesn't advance
	- Each rule advances on match
	- On a match, you can use other rules
	- Remain simple

*/

/*
Grammer in BNF notation:

- expression 	-> equality ;
- equality 		-> comparison ( ( "!=" | "==" ) comparison )* ;
- comparison 	-> term ( ( ">" | ">=" | "<" | "<=" ) term )* ;
- term 			-> factor ( ( "-" | "+" ) factor )* ;
- factor 		-> unary ( ( "/" | "*" ) unary )* ;
- unary 		-> ( "!" | "-" ) unary | primary ;
- primary 		-> NUMBER | STRING | "true" | "false" | "nil" | "(" expression ")" ;
*/
Parser :: struct {
	tokens:  []syntax.Token,
	current: int,
	alloc:   mem.Allocator,
}

init :: proc(parser: ^Parser, tokens: []syntax.Token, alloc: mem.Allocator = context.allocator) {
	parser.current = 0
	parser.tokens = tokens
	parser.alloc = alloc
}

parse :: proc(parser: ^Parser) -> ([dynamic]^syntax.Expr, Maybe(Parser_Error)) {
	exprs := [dynamic]^syntax.Expr{}

	for !is_at_end(parser) {
		append(&exprs, parse_expr(parser))
	}

	return exprs, nil
}

parse_expr :: proc(parser: ^Parser) -> ^syntax.Expr {
	expr := parse_equality(parser)

	return expr
}

parse_equality :: proc(parser: ^Parser) -> ^syntax.Expr {
	expr := parse_comparison(parser)

	for {
		current_token, _ := get_current_token(parser)
		if !matches(current_token.kind, .Bang_Equal, .Equal_Equal) {
			break
		}

		_, _ = advance(parser)

		result := new(syntax.Expr, parser.alloc)
		result^ = syntax.Expr {
			expr = syntax.Binary_Expr {
				left = expr,
				op = current_token.kind,
				right = parse_comparison(parser),
			},
		}
		expr = result
	}

	return expr
}

parse_comparison :: proc(parser: ^Parser) -> ^syntax.Expr {
	expr := parse_term(parser)

	for {
		current_token, _ := get_current_token(parser)
		if !matches(current_token.kind, .Greater, .Greater_Equal, .Less, .Less_Equal) {
			break
		}

		_, _ = advance(parser)

		result := new(syntax.Expr, parser.alloc)
		result^ = syntax.Expr {
			expr = syntax.Binary_Expr {
				left = expr,
				op = current_token.kind,
				right = parse_term(parser),
			},
		}
		expr = result
	}

	return expr
}

parse_term :: proc(parser: ^Parser) -> ^syntax.Expr {
	expr := parse_factor(parser)

	for {
		current_token, _ := get_current_token(parser)
		if !matches(current_token.kind, .Minus, .Plus) {
			break
		}

		_, _ = advance(parser)

		result := new(syntax.Expr, parser.alloc)
		result^ = syntax.Expr {
			expr = syntax.Binary_Expr {
				left = expr,
				op = current_token.kind,
				right = parse_factor(parser),
			},
		}
		expr = result
	}

	return expr
}

parse_factor :: proc(parser: ^Parser) -> ^syntax.Expr {
	expr := parse_unary(parser)

	for {
		current_token, _ := get_current_token(parser)
		if !matches(current_token.kind, .Slash, .Star) {
			break
		}

		_, _ = advance(parser)

		result := new(syntax.Expr, parser.alloc)
		result^ = syntax.Expr {
			expr = syntax.Binary_Expr {
				left = expr,
				op = current_token.kind,
				right = parse_unary(parser),
			},
		}
		expr = result
	}

	return expr
}

parse_unary :: proc(parser: ^Parser) -> ^syntax.Expr {
	current_token, _ := get_current_token(parser)
	if matches(current_token.kind, .Bang, .Minus) {
		_, _ = advance(parser)

		result := new(syntax.Expr, parser.alloc)
		result^ = syntax.Expr {
			expr = syntax.Unary_Expr{op = current_token.kind, right = parse_unary(parser)},
		}
		return result
	}

	return parse_primary(parser)
}

parse_primary :: proc(parser: ^Parser) -> ^syntax.Expr {
	expr := new(syntax.Expr, parser.alloc)

	current_token, _ := get_current_token(parser)
	#partial switch current_token.kind {
	case .Literal:
		{
			result := syntax.Expr {
				expr = syntax.Literal_Expr{token = current_token},
			}
			expr^ = result
			_, _ = advance(parser)
		}
	case .Left_Paren:
		{
			_, _ = advance(parser)
			expr_inner := parse_expr(parser)

			if parser.tokens[parser.current].kind != .Right_Paren {
				panic("Let's all panic together. I'll start")
			}

			_, _ = advance(parser)

			expr^ = syntax.Expr {
				expr = syntax.Grouping_Expr{expr = expr_inner},
			}
		}
	case:
		{
			panic("unreachable?")
		}
	}

	return expr
}

// Advances and returns: previous token, success
@(private)
advance :: proc(parser: ^Parser) -> (syntax.Token, bool) {
	prev := parser.tokens[parser.current]
	_, ok := peek(parser)
	if ok {
		parser.current += 1
		return prev, true
	}

	return syntax.Token{}, false
}

@(private)
peek :: proc(parser: ^Parser) -> (^syntax.Token, bool) {
	if parser.current >= len(parser.tokens) - 1 {
		return nil, false
	}

	return &parser.tokens[parser.current + 1], true
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

// Returns the current token with a flag for if the current token is the EOF one.
@(private)
get_current_token :: proc(parser: ^Parser) -> (syntax.Token, bool) {
	token := parser.tokens[parser.current]
	return token, token.kind == .EOF
}

Parser_Error :: enum {}

parser_error_to_string :: proc(err: Parser_Error) -> string {
	return ""
}
