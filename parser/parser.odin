package parser

import "../syntax"
import "core:fmt"
import "core:mem"
import "core:strings"

// Grammar in BNF notation:
// 
// Statements:
// - program          -> ( statement TERMINATOR )* ;
// - statement        -> ident_decl
//                     | ident_assignment
//                     | if_stmt
//                     | block
//                     | fn_call
//                     | expr_stmt ;
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

init :: proc(p: ^Parser, tokens: []syntax.Token, allocator := context.allocator) {
	p.current   = 0
	p.tokens    = tokens
	p.allocator = allocator
}

parse :: proc(p: ^Parser) -> ([dynamic]^syntax.Stmt, Maybe(Parser_Error)) {
	if len(p.tokens) == 0 {
		return nil, Parser_Error{kind = .Empty_Tokens, message = "No tokens found"}
	}

	if p.tokens[len(p.tokens) - 1].kind != .EOF {
		return nil, Parser_Error {
			kind = .Missing_EOF,
			message = "Missing EOF token at the end of the token list",
		}
	}

	// worst case: assume one statement per token
	stmts := make([dynamic]^syntax.Stmt, 0, len(p.tokens), allocator = p.allocator)

	for !is_at_end(p) {
		skip_trivia(p)
		if is_at_end(p) {
			break
		}

		stmt, parser_err := parse_stmt(p)
		if parser_err != nil do return stmts, parser_err

		append(&stmts, stmt)

		term_err := expect_terminator(p)
		if term_err != nil do return stmts, term_err
	}

	return stmts, nil
}

parse_stmt :: proc(p: ^Parser) -> (^syntax.Stmt, Maybe(Parser_Error)) {
	current := current(p)
	#partial switch current.kind {
	case .Ident:
		next, ok := next(p)
		if ok {
			#partial switch next.kind {
			case .Colon_Equal, .Colon_Colon, .Colon:
				return parse_decl(p)

			case .Equal:
				return parse_ident_assignment(p)
			}
		}

	case .Keyword:
		return parse_keyword(p, current)

	case .Left_Brace:
		return parse_block(p)
	}

	// TODO: statements that depend on the next token like assignments.

	// Expression statements
	expr, err := parse_expr(p)
	if err != nil do return nil, err

	stmt := new(syntax.Stmt, allocator = p.allocator)
	stmt^ = syntax.Expr_Stmt{expr = expr}
	return stmt, nil
}

parse_keyword :: proc(p: ^Parser, token: syntax.Token) -> (^syntax.Stmt, Maybe(Parser_Error)) {
	keyword, ok := token.keyword.?
	assert(ok)

	#partial switch keyword {
	case .If:
		return parse_if(p)

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

parse_if :: proc(p: ^Parser) -> (^syntax.Stmt, Maybe(Parser_Error)) {
	advance(p) // consume `if`

	condition, cond_err := parse_expr(p)
	if cond_err != nil do return nil, cond_err

	skip_trivia(p)

	then_block, then_err := parse_block(p)
	if then_err != nil do return nil, then_err

	else_branch: Maybe(^syntax.Stmt)
	tok := current(p)
	if tok.kind == .Keyword && tok.keyword == .Else {
		advance(p) // consume `else`
		skip_trivia(p)

		next := current(p)
		if next.kind == .Keyword && next.keyword == .If {
			else_stmt, err := parse_if(p)
			if err != nil do return nil, err
			else_branch = else_stmt
		} else {
			else_stmt, err := parse_block(p)
			if err != nil do return nil, err
			else_branch = else_stmt
		}
	}

	stmt := new(syntax.Stmt, allocator = p.allocator)
	stmt^ = syntax.If_Stmt {
		condition   = condition,
		then_block  = then_block,
		else_branch = else_branch,
	}

	return stmt, nil
}

parse_ident_assignment :: proc(p: ^Parser) -> (^syntax.Stmt, Maybe(Parser_Error)) {
	name := current(p)
	advance(p)

	advance(p) // '='

	value, err := parse_expr(p)
	if err != nil do return nil, err

	stmt := new(syntax.Stmt, allocator = p.allocator)
	stmt^ = syntax.Ident_Assignment_Stmt{value = value, name = name}
	return stmt, nil
}

parse_decl :: proc(p: ^Parser) -> (^syntax.Stmt, Maybe(Parser_Error)) {
	name := current(p)
	advance(p)

	stmt: ^syntax.Stmt
	#partial switch current(p).kind {
	case .Colon_Equal, .Colon_Colon:
		op := current(p)
		advance(p)

		if current(p).kind == .Keyword { // Non-Identifiers
			err: Maybe(Parser_Error)
			stmt, err = parse_non_ident_decls(p, name)
			if err != nil do return nil, err
		} else { // Identifiers
			value, err := parse_expr(p)
			if err != nil do return nil, err

			value_stmt := new(syntax.Stmt, allocator = p.allocator)
			value_stmt^ = syntax.Expr_Stmt { expr = value }

			stmt = new(syntax.Stmt, allocator = p.allocator)
			stmt^ = syntax.Ident_Decl_Stmt {
				name      = name,
				value     = value_stmt,
				constant  = op.kind == .Colon_Colon,
				type      = nil,
			}
		}

	case .Colon:
		advance(p)

		// Either a non-keyword ident token or a type-keyword
		if current(p).kind != .Ident {
			return nil, Parser_Error {
				kind    = .Incorrect_Type_Expr,
				message = "expected a built-in or a user-defined type after ':'",
				token   = current(p),
			}
		}

		type_token := current(p)
		advance(p)

		value: Maybe(^syntax.Expr)
		constant := false
		if current(p).kind == .Equal || current(p).kind == .Colon {
			if current(p).kind == .Colon {
				constant = true
			}

			advance(p) // '=' or ':'
			err: Maybe(Parser_Error)
			value, err = parse_expr(p)
			if err != nil do return nil, err
		}

		value_stmt: Maybe(^syntax.Stmt) = nil
		if value, ok := value.?; ok {
			value_stmt = new(syntax.Stmt, allocator = p.allocator)
			value_stmt.?^ = syntax.Expr_Stmt { expr = value }
		}

		stmt = new(syntax.Stmt, allocator = p.allocator)
		stmt^ = syntax.Ident_Decl_Stmt {
			name     = name,
			value    = value_stmt,
			constant = constant,
			type     = syntax.Type{ token = type_token },
		}

	case:
		return nil, Parser_Error {
			kind    = .Unexpected_Token,
			message = "expected ':=', '::', or ':' after identifier in declaration",
			token   = current(p),
		}
	}

	return stmt, nil
}

// Things like functions, structs, interfaces, etc
parse_non_ident_decls :: proc(p: ^Parser, name: syntax.Token) -> (^syntax.Stmt, Maybe(Parser_Error)) {
	current := current(p)
	assert(current.kind == .Keyword && current.keyword != nil)

	stmt: ^syntax.Stmt
	#partial switch current.keyword.? {
	case .Fn, .Async:
		is_async := current.keyword.? == .Fn ? false : true

		err: Maybe(Parser_Error)
		stmt, err = parse_fn_decl_stmt(p, name, is_async)
		if err != nil do return nil, err
	}

	return stmt, nil
}

parse_fn_decl_stmt :: proc(p: ^Parser, name: syntax.Token, async: bool) -> (^syntax.Stmt, Maybe(Parser_Error)) {
	if async {
		advance(p) // consume 'async'
	}
	advance(p) // consume 'fn'
	skip_trivia(p)

	if current(p).kind != .Left_Paren {
		return nil, Parser_Error {
			kind    = .Unexpected_Token,
			message = "expected a '(' after 'fn' to declare a function",
			token   = current(p),
		}
	}

	advance(p) // consume '('

	// Parse arguments
	args := make([dynamic]syntax.Fn_Arg, allocator = p.allocator)
	if current(p).kind != .Right_Paren {
		err: Maybe(Parser_Error)
		skip_trivia(p)
		args, err = parse_arg(p, .Comma)
		if err != nil do return nil, err
		skip_trivia(p)
	}
	
	// Should close the parenthesis after arguments
	if current(p).kind != .Right_Paren {
		return nil, Parser_Error {
			kind    = .Unexpected_Token,
			message = "expected a ')' to end function arguments",
			token   = current(p),
		}
	}
	
	advance(p) // consume ')'

	// Return(s)
	return_type: Maybe([dynamic]syntax.Token)
	if next, ok := next(p); ok && current(p).kind == .Minus && next.kind == .Greater {
		advance(p) // consume '-'
		advance(p) // consume '>'
		skip_trivia(p)

		returns: Maybe(Parser_Error)
		return_type, returns = parse_returns(p)
		if returns != nil do return nil, returns
	}

	block_stmt: Maybe(^syntax.Block_Stmt)
	if current(p).kind == .Left_Brace {
		value_stmt, err := parse_block(p)
		if err != nil do return nil, err
		ok: bool
		block_stmt, ok = &value_stmt.(syntax.Block_Stmt)
		assert(ok)
	}

	stmt := new(syntax.Stmt, allocator = p.allocator)
	stmt^ = syntax.Fn_Decl_Stmt {
		name  = name,
		block = block_stmt, // Addressing since it was cast to value struct not a ptr
		stub  = block_stmt == nil ? true : false,
		async = async,
		args  = args,
		return_type = return_type,
	}

	return stmt, nil
}

// Parses a function's return type(s): either a single bare type `string`, or a
// parenthesized, comma-separated list `(string, number)`. Parentheses are
// required for more than one return value.
parse_returns :: proc(p: ^Parser) -> (Maybe([dynamic]syntax.Token), Maybe(Parser_Error)) {
	returns := make([dynamic]syntax.Token, allocator = p.allocator)

	// Single, unparenthesized return type
	if current(p).kind != .Left_Paren {
		if current(p).kind != .Ident {
			return nil, Parser_Error {
				kind    = .Unexpected_Token,
				message = "expected a return type after '->'",
				token   = current(p),
			}
		}
		append(&returns, current(p))
		advance(p) // the return type
		return returns, nil
	}

	// Parenthesized list of return types
	advance(p) // consume '('
	for {
		skip_trivia(p)
		if current(p).kind == .Right_Paren {
			break
		}

		if current(p).kind != .Ident {
			return nil, Parser_Error {
				kind    = .Unexpected_Token,
				message = "expected a return type inside '( )'",
				token   = current(p),
			}
		}
		append(&returns, current(p))
		advance(p) // the return type

		skip_trivia(p)
		if current(p).kind != .Comma {
			break
		}
		advance(p) // ','
	}

	skip_trivia(p)
	if current(p).kind != .Right_Paren {
		return nil, Parser_Error {
			kind    = .Unexpected_Token,
			message = "expected a ')' to end function return types",
			token   = current(p),
		}
	}
	advance(p) // consume ')'

	return returns, nil
}

parse_arg :: proc(p: ^Parser, separator: syntax.Token_Kind) -> ([dynamic]syntax.Fn_Arg, Maybe(Parser_Error)) {
	args := make([dynamic]syntax.Fn_Arg, allocator = p.allocator)
	
	for {
		skip_trivia(p)
		if current(p).kind == .Right_Paren {
			break
		}
		
		if current(p).kind != .Ident {
			return nil, Parser_Error {
				kind    = .Unexpected_Token,
				message = "expected argument to start with a name",
				token   = current(p),
			}
		}
		arg_name := current(p)
		advance(p) // the arg name
		
		if current(p).kind != .Colon {
			return nil, Parser_Error {
				kind    = .Unexpected_Token,
				message = "expected ':' after argument name",
				token   = current(p),
			}
		}
		advance(p) // ':'

		if current(p).kind != .Ident {
			return nil, Parser_Error {
				kind    = .Unexpected_Token,
				message = "expected a type after ':' when specifying an argument",
				token   = current(p),
			}
		}
		arg_type := current(p)
		append(&args, syntax.Fn_Arg{ name = arg_name, type = arg_type })
		
		advance(p) // arg type

		skip_trivia(p)

		if current(p).kind != separator {
			break
		}
		
		advance(p) // separator
	}
	
	return args, nil
}

// unused
parse_fn_call :: proc(p: ^Parser) -> (^syntax.Stmt, Maybe(Parser_Error)) {
	advance(p) // '('

	args := make([dynamic]syntax.Token, allocator = p.allocator)
	for {
		if current(p).kind == .Right_Paren {
			break
		}

		arg := current(p)
		append(&args, arg)
	}
	
	return {}, nil
}

parse_block :: proc(p: ^Parser) -> (^syntax.Stmt, Maybe(Parser_Error)) {
	open := current(p)
	if open.kind != .Left_Brace {
		return nil, Parser_Error {
			kind    = .Unexpected_Token,
			message = "expected '{' to start block",
			token   = open,
		}
	}
	advance(p)

	inner := make([dynamic]^syntax.Stmt, 0, 8, allocator = p.allocator)

	for {
		skip_trivia(p)

		tok := current(p)
		if tok.kind == .Right_Brace {
			advance(p)
			break
		}
		if tok.kind == .EOF {
			return nil, Parser_Error {
				kind = .Unexpected_EOF,
				message = "unexpected EOF while parsing block — missing '}'",
				token = tok,
			}
		}

		s, err := parse_stmt(p)
		if err != nil do return nil, err
		append(&inner, s)

		term_err := expect_terminator(p)
		if term_err != nil do return nil, term_err
	}

	stmt := new(syntax.Stmt, allocator = p.allocator)
	stmt^ = syntax.Block_Stmt{stmts = inner[:]}
	return stmt, nil
}

parse_expr :: proc(p: ^Parser) -> (^syntax.Expr, Maybe(Parser_Error)) {
	expr, err := parse_logic_or(p)
	if err != nil do return expr, err

	return expr, nil
}

parse_logic_or :: proc(p: ^Parser) -> (^syntax.Expr, Maybe(Parser_Error)) {
	expr, err := parse_logic_and(p)
	if err != nil do return expr, err

	for {
		tok := current(p)
		if tok.kind == .EOF || tok.kind != .Keyword || tok.keyword != .Or {
			break
		}

		advance(p)

		right, rerr := parse_logic_and(p)
		if rerr != nil do return expr, rerr

		result := new(syntax.Expr, allocator = p.allocator)
		result^ = syntax.Expr {
			expr = syntax.Logical_Expr{left = expr, op = .Or, right = right},
		}
		expr = result
	}

	return expr, nil
}

parse_logic_and :: proc(p: ^Parser) -> (^syntax.Expr, Maybe(Parser_Error)) {
	expr, err := parse_equality(p)
	if err != nil do return expr, err

	for {
		tok := current(p)
		if tok.kind == .EOF || tok.kind != .Keyword || tok.keyword != .And {
			break
		}

		advance(p)

		right, rerr := parse_equality(p)
		if rerr != nil do return expr, rerr

		result := new(syntax.Expr, allocator = p.allocator)
		result^ = syntax.Expr {
			expr = syntax.Logical_Expr{left = expr, op = .And, right = right},
		}
		expr = result
	}

	return expr, nil
}

parse_equality :: proc(p: ^Parser) -> (^syntax.Expr, Maybe(Parser_Error)) {
	expr, err := parse_comparison(p)
	if err != nil do return expr, err

	for {
		current_token := current(p)
		if current_token.kind == .EOF || !matches(current_token.kind, .Bang_Equal, .Equal_Equal) {
			break
		}

		advance(p)

		right, err := parse_comparison(p)
		if err != nil do return expr, err

		result := new(syntax.Expr, allocator = p.allocator)
		result^ = syntax.Expr {
			expr = syntax.Binary_Expr{left = expr, op = current_token.kind, right = right},
		}
		expr = result
	}

	return expr, nil
}

parse_comparison :: proc(p: ^Parser) -> (^syntax.Expr, Maybe(Parser_Error)) {
	expr, err := parse_term(p)
	if err != nil do return expr, err

	for {
		current_token := current(p)
		if current_token.kind == .EOF || !matches(current_token.kind, .Greater, .Greater_Equal, .Less, .Less_Equal) {
			break
		}

		advance(p)

		right, err := parse_term(p)
		if err != nil do return expr, err

		result := new(syntax.Expr, allocator = p.allocator)
		result^ = syntax.Expr {
			expr = syntax.Binary_Expr{left = expr, op = current_token.kind, right = right},
		}
		expr = result
	}

	return expr, nil
}

parse_term :: proc(p: ^Parser) -> (^syntax.Expr, Maybe(Parser_Error)) {
	expr, err := parse_factor(p)
	if err != nil do return expr, err

	for {
		current_token := current(p)
		if current_token.kind == .EOF || !matches(current_token.kind, .Minus, .Plus) {
			break
		}

		advance(p)

		right, err := parse_factor(p)
		if err != nil do return expr, err

		result := new(syntax.Expr, allocator = p.allocator)
		result^ = syntax.Expr {
			expr = syntax.Binary_Expr{left = expr, op = current_token.kind, right = right},
		}
		expr = result
	}

	return expr, nil
}

parse_factor :: proc(p: ^Parser) -> (^syntax.Expr, Maybe(Parser_Error)) {
	expr, err := parse_unary(p)
	if err != nil do return expr, err

	for {
		current_token := current(p)
		if current_token.kind == .EOF || !matches(current_token.kind, .Slash, .Star) {
			break
		}

		advance(p)

		right, err := parse_unary(p)
		if err != nil do return expr, err

		result := new(syntax.Expr, allocator = p.allocator)
		result^ = syntax.Expr {
			expr = syntax.Binary_Expr{left = expr, op = current_token.kind, right = right},
		}
		expr = result
	}

	return expr, nil
}

parse_unary :: proc(p: ^Parser) -> (^syntax.Expr, Maybe(Parser_Error)) {
	current_token := current(p)
	if current_token.kind == .EOF {
		return nil, Parser_Error {
			kind = .Unexpected_EOF,
			message = "Unexpected \"EOF\" token while parsing unary",
			token = p.tokens[max(p.current - 1, 0)],
		}
	}

	if matches(current_token.kind, .Bang, .Minus) {
		advance(p)

		right, err := parse_unary(p)
		if err != nil do return nil, err

		result := new(syntax.Expr, allocator = p.allocator)
		result^ = syntax.Expr {
			expr = syntax.Unary_Expr{op = current_token.kind, right = right},
		}
		return result, nil
	}

	return parse_primary(p)
}

parse_primary :: proc(p: ^Parser) -> (^syntax.Expr, Maybe(Parser_Error)) {
	expr := new(syntax.Expr, allocator = p.allocator)

	current_token := current(p)
	if current_token.kind == .EOF {
		return expr, Parser_Error {
			kind = .Unexpected_EOF,
			message = "Unexpected \"EOF\" token while parsing primary",
			token = p.tokens[max(p.current - 1, 0)],
		}
	}

	#partial switch current_token.kind {
	case .Literal:
		result := syntax.Expr {
			expr = syntax.Literal_Expr{token = current_token},
		}
		expr^ = result
		advance(p)

	case .Ident:
		expr^ = syntax.Expr {
			expr = syntax.Ident_Expr{token = current_token},
		}
		advance(p)

	case .Left_Paren:
		advance(p)
		expr_inner, err := parse_expr(p)
		if err != nil do return expr, err

		current_token := current(p)
		if current_token.kind == .EOF || current_token.kind != .Right_Paren {
			return expr, Parser_Error {
				kind = .UnclosedParen,
				message = "Expected a \")\" token",
				token = current_token,
			}
		}

		advance(p)

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
advance :: proc(p: ^Parser) -> (syntax.Token, bool) {
	prev := current(p)
	if prev.kind != .EOF {
		p.current += 1
		return prev, true
	} else {
		return {}, false
	}
}

next :: proc(p: ^Parser) -> (syntax.Token, bool) {
	if p.current >= len(p.tokens) - 1 {
		return {}, false
	}

	return p.tokens[p.current + 1], true
}

is_at_end :: proc(p: ^Parser) -> bool {
	return p.current < len(p.tokens) && current(p).kind == .EOF
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
current :: proc(p: ^Parser) -> syntax.Token {
	return p.tokens[p.current]
}

// Consumes comments and new lines
skip_trivia :: proc(p: ^Parser) {
	for {
		kind := current(p).kind
		if kind != .New_Line && kind != .Comment do break
		advance(p)
	}
}

// Requires the current token to be a valid statement terminator: newline, EOF,
// or '}' (so blocks can end without a trailing newline). Trailing comments are
// skipped first since they end at the line break anyway.
expect_terminator :: proc(p: ^Parser) -> Maybe(Parser_Error) {
	for current(p).kind == .Comment {
		advance(p)
	}
	tok := current(p)
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
