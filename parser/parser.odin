package parser

import "../syntax"
import "core:fmt"
import "core:mem"
import "core:strings"

// Grammar in BNF notation:
// 
// Statements:
// - program          -> ( statement TERMINATOR )* ;
// - statement        -> ident_decl | ident_assignment | if_stmt | block | expr_stmt ;
// - ident_decl       -> IDENT ( ":=" | "::" ) expression
//                     | IDENT ":" TYPE ( ( "=" | ":" ) expression )? ;
// - ident_assignment -> IDENT "=" expression ;
// - if_stmt          -> "if" expression block ( "else" ( if_stmt | block ) )? ;
// - block            -> "{" ( statement TERMINATOR )* "}" ;
// - expr_stmt        -> expression ;
// - TYPE             -> "bool" | "number" | "any" | "string" ;
// 
// Expressions:
// - expression -> logic_or ;
// - logic_or   -> logic_and ( "or" logic_and )* ;
// - logic_and  -> equality ( "and" equality )* ;
// - equality   -> comparison ( ( "!=" | "==" ) comparison )* ;
// - comparison -> term ( ( ">" | ">=" | "<" | "<=" ) term )* ;
// - term       -> factor ( ( "-" | "+" ) factor )* ;
// - factor     -> unary ( ( "/" | "*" ) unary )* ;
// - unary      -> ( "!" | "-" ) unary | primary ;
// - primary    -> NUMBER | STRING | IDENT | "(" expression ")" ;
// 
// Notes:
// - TERMINATOR is satisfied by NEWLINE, EOF, or a following "}" (end of block).
// - Comments and consecutive newlines between statements are trivia and skipped.
// - IDENT is any identifier token; keywords ("if", "else", "and", "or") don't match.
// - "and"/"or" are lexed as keyword tokens, not operator punctuation.
// - ident_decl mutability: ":=" is mutable, "::" is constant.
//   For typed declarations, the initializer separator picks mutability:
//   "= expr" → mutable, ": expr" → constant. No initializer → bare typed decl.
Parser :: struct {
	tokens:    []syntax.Token,
	current:   int,
	allocator: mem.Allocator,
}

init :: proc(parser: ^Parser, tokens: []syntax.Token, allocator := context.allocator) {
	parser.current   = 0
	parser.tokens    = tokens
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
		skip_trivia(parser)
		if is_at_end(parser) {
			break
		}

		stmt, parser_err := parse_stmt(parser)
		if parser_err != nil do return stmts, parser_err

		append(&stmts, stmt)

		term_err := expect_terminator(parser)
		if term_err != nil do return stmts, term_err
	}

	return stmts, nil
}

parse_stmt :: proc(parser: ^Parser) -> (^syntax.Stmt, Maybe(Parser_Error)) {
	current := parser.tokens[parser.current]
	#partial switch current.kind {
	case .Ident:
		next, ok := peek_next(parser)
		if ok {
			#partial switch next.kind {
			case .Colon_Equal, .Colon_Colon, .Colon:
				return parse_ident_decl(parser)

			case .Equal:
				return parse_ident_assignment(parser)
			}
		}

	case .Keyword:
		return parse_keyword(parser, current)

	case .Left_Brace:
		return parse_block(parser)
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
			message = "'else' has no matching 'if' — it must follow '}' on the same line",
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

	skip_trivia(parser)

	then_block, then_err := parse_block(parser)
	if then_err != nil do return nil, then_err

	else_branch: Maybe(^syntax.Stmt)
	tok := parser.tokens[parser.current]
	if tok.kind == .Keyword && tok.keyword == .Else {
		advance(parser) // consume `else`
		skip_trivia(parser)

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

parse_ident_assignment :: proc(parser: ^Parser) -> (^syntax.Stmt, Maybe(Parser_Error)) {
	name := parser.tokens[parser.current]
	advance(parser)

	advance(parser) // '='

	value, err := parse_expr(parser)
	if err != nil do return nil, err

	stmt := new(syntax.Stmt, allocator = parser.allocator)
	stmt^ = syntax.Ident_Assignment_Stmt{value = value, name = name}
	return stmt, nil
}

parse_ident_decl :: proc(parser: ^Parser) -> (^syntax.Stmt, Maybe(Parser_Error)) {
	name := parser.tokens[parser.current]
	advance(parser)

	stmt: ^syntax.Stmt
	#partial switch parser.tokens[parser.current].kind {
	case .Colon_Equal, .Colon_Colon:
		op := parser.tokens[parser.current]
		advance(parser)

		value, err := parse_expr(parser)
		if err != nil do return nil, err

		stmt = new(syntax.Stmt, allocator = parser.allocator)
		stmt^ = syntax.Ident_Decl_Stmt {
			name     = name,
			value    = value,
			constant = op.kind == .Colon_Colon,
			type     = nil,
		}

	case .Colon:
		advance(parser)

		current := parser.tokens[parser.current]
		// Either a non-keyword ident token or a type-keyword
		if current.kind != .Ident {
			return nil, Parser_Error {
				kind    = .Incorrect_Type_Expr,
				message = "expected a built-in or a user-defined type after ':'",
				token   = current,
			}
		}

		type_token := parser.tokens[parser.current]
		advance(parser)

		value: Maybe(^syntax.Expr)
		constant := false
		current = parser.tokens[parser.current]
		if current.kind == .Equal || current.kind == .Colon {
			if current.kind == .Colon {
				constant = true
			}

			advance(parser) // '=' or ':'
			err: Maybe(Parser_Error)
			value, err = parse_expr(parser)
			if err != nil do return nil, err
		}

		stmt = new(syntax.Stmt, allocator = parser.allocator)
		stmt^ = syntax.Ident_Decl_Stmt {
			name     = name,
			value    = value,
			constant = constant,
			type     = syntax.Type{ token = type_token },
		}

	case:
		return nil, Parser_Error {
			kind    = .Unexpected_Token,
			message = "expected ':=', '::', or ':' after identifier in declaration",
			token   = parser.tokens[parser.current],
		}
	}

	return stmt, nil
}

parse_block :: proc(parser: ^Parser) -> (^syntax.Stmt, Maybe(Parser_Error)) {
	open := parser.tokens[parser.current]
	if open.kind != .Left_Brace {
		return nil, Parser_Error {
			kind    = .Unexpected_Token,
			message = "expected '{' to start block",
			token   = open,
		}
	}
	advance(parser)

	inner := make([dynamic]^syntax.Stmt, 0, 8, allocator = parser.allocator)

	for {
		skip_trivia(parser)

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

		term_err := expect_terminator(parser)
		if term_err != nil do return nil, term_err
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
		return {}, false
	}
}

peek_next :: proc(parser: ^Parser) -> (syntax.Token, bool) {
	if parser.current >= len(parser.tokens) - 1 {
		return {}, false
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
		return {}, true
	}

	return token, false
}

skip_trivia :: proc(parser: ^Parser) {
	for {
		kind := parser.tokens[parser.current].kind
		if kind != .New_Line && kind != .Comment do break
		advance(parser)
	}
}

// Requires the current token to be a valid statement terminator: newline, EOF,
// or '}' (so blocks can end without a trailing newline). Trailing comments are
// skipped first since they end at the line break anyway.
expect_terminator :: proc(parser: ^Parser) -> Maybe(Parser_Error) {
	for parser.tokens[parser.current].kind == .Comment {
		advance(parser)
	}
	tok := parser.tokens[parser.current]
	if tok.kind == .New_Line || tok.kind == .EOF || tok.kind == .Right_Brace do return nil
	return Parser_Error {
		kind = .Missing_Terminator,
		message = "expected newline, '}', or end of input after statement",
		token = tok,
	}
}

Parser_Error :: struct {
	kind:    Parser_Error_Kind,
	token:   syntax.Token,
	message: string,
}

Parser_Error_Kind :: enum u8 {
	Unexpected_EOF,
	Empty_Tokens,
	Missing_EOF,
	UnclosedParen,
	Unexpected_Token,
	Else_With_No_If,
	Missing_Terminator,
	Incorrect_Type_Expr,
}

@(private)
error_hint :: proc(kind: Parser_Error_Kind) -> Maybe(string) {
	#partial switch kind {
	case .Unexpected_EOF:
		return "input ended before the statement was complete"
		
	case .UnclosedParen:
		return "add a matching ')'"
		
	case .Incorrect_Type_Expr:
		return "expected a built-in or user-defined type name"
		
	case .Else_With_No_If:
		return "'else' must follow '}' on the same line"
		
	case .Missing_Terminator:
		return "expected newline, '}', or end of input"
	}

	return nil
}

format_error :: proc(err: Parser_Error, source: string, allocator := context.allocator) -> string {
	if err.kind == .Empty_Tokens || err.kind == .Missing_EOF {
		return fmt.aprintf("error: %s\n", err.message, allocator = allocator)
	}

	start := clamp(err.token.lexeme_start, 0, len(source))
	end   := clamp(err.token.lexeme_end,   start, len(source))

	line_start := 0
	for i := start - 1; i >= 0; i -= 1 {
		if source[i] == '\n' {
			line_start = i + 1
			break
		}
	}

	line_end := len(source)
	for i := start; i < len(source); i += 1 {
		if source[i] == '\n' {
			line_end = i
			break
		}
	}

	line_no := 1
	for i := 0; i < start; i += 1 {
		if source[i] == '\n' do line_no += 1
	}

	column := start - line_start + 1
	span_end := min(end, line_end)
	caret_count := max(span_end - start, 1)

	line_text := source[line_start:line_end]
	hint := error_hint(err.kind)

	b: strings.Builder
	strings.builder_init(&b, allocator)

	fmt.sbprintf(&b, "error: %s\n", err.message)
	fmt.sbprintf(&b, "  --> line %d, column %d\n", line_no, column)

	gutter_str := fmt.tprintf("%d", line_no)
	gutter := len(gutter_str)

	write_repeat(&b, ' ', gutter + 1)
	strings.write_string(&b, " |\n")

	strings.write_byte(&b, ' ')
	strings.write_string(&b, gutter_str)
	strings.write_string(&b, " | ")
	strings.write_string(&b, line_text)
	strings.write_byte(&b, '\n')

	write_repeat(&b, ' ', gutter + 1)
	strings.write_string(&b, " | ")
	write_repeat(&b, ' ', column - 1)
	write_repeat(&b, '^', caret_count)
	if hint != nil {
		strings.write_byte(&b, ' ')
		strings.write_string(&b, hint.?)
	}
	strings.write_byte(&b, '\n')

	return strings.to_string(b) // @Allocation
}

@(private)
write_repeat :: proc(b: ^strings.Builder, c: byte, n: int) {
	for _ in 0..<n do strings.write_byte(b, c)
}
