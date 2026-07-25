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
//                     | return_stmt
//                     | expr_stmt ;
// - return_stmt      -> "return" ( expression ( "," expression )* )? ;
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

parse :: proc(p: ^Parser) -> ([dynamic]syntax.Stmt, Maybe(Parser_Error)) {
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
	stmts := make([dynamic]syntax.Stmt, 0, len(p.tokens), allocator = p.allocator)

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

parse_stmt :: proc(p: ^Parser) -> (syntax.Stmt, Maybe(Parser_Error)) {
	next, _ := next(p)
	#partial switch current(p).kind {
	case .Ident:

		#partial switch next.kind {
		case .Colon_Equal, .Colon_Colon, .Colon:
			names := make([dynamic]syntax.Token, allocator = p.allocator)
			append(&names, current(p))
			advance(p) // the name
			return parse_decl(p, names)

		case .Equal:
			names := make([dynamic]syntax.Token, allocator = p.allocator)
			append(&names, current(p))
			advance(p) // the name
			return parse_ident_assignment(p, names)

		case .Comma:
			return parse_multi_target(p)

		case .Left_Paren:
			return parse_fn_call(p)
		}

	case .Keyword:
		return parse_keyword(p, current(p))

	case .Left_Brace:
		return parse_block(p)
	}

	// TODO: statements that depend on the next token like assignments.

	// Expression statements
	expr, err := parse_expr(p)
	if err != nil do return nil, err

	expr_stmt := new(syntax.Expr_Stmt, allocator = p.allocator)
	expr_stmt.expr = expr

	return expr_stmt, nil
}

parse_keyword :: proc(p: ^Parser, token: syntax.Token) -> (syntax.Stmt, Maybe(Parser_Error)) {
	keyword, ok := token.keyword.?
	assert(ok)

	#partial switch keyword {
	case .If:
		return parse_if(p)

	case .Return:
		return parse_return(p)

	case .Else:
		return nil, Parser_Error {
			kind = .Else_With_No_If,
			message = "'else' has no matching 'if' - it must follow '}' on the same line",
			token = token,
		}
	}

	return nil, Parser_Error {
		kind = .Unexpected_Token,
		message = "keyword cannot start a statement",
		token = token,
	}
}

parse_if :: proc(p: ^Parser) -> (syntax.Stmt, Maybe(Parser_Error)) {
	advance(p) // consume `if`

	condition, cond_err := parse_expr(p)
	if cond_err != nil do return nil, cond_err

	skip_trivia(p)

	then_block, then_err := parse_block(p)
	if then_err != nil do return nil, then_err

	else_branch: Maybe(syntax.Stmt)
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

	stmt := new(syntax.If_Stmt, allocator = p.allocator)
	stmt^ = syntax.If_Stmt {
		condition   = condition,
		then_block  = then_block,
		else_branch = else_branch,
	}

	return stmt, nil
}

parse_return :: proc(p: ^Parser) -> (syntax.Stmt, Maybe(Parser_Error)) {
	advance(p) // consume `return`

	exprs: [dynamic]^syntax.Expr
	if terminates_statement(current(p).kind) {
		exprs = make([dynamic]^syntax.Expr, allocator = p.allocator)
	} else {
		values, err := parse_ident_rhs(p)
		if err != nil do return nil, err
		exprs = values
	}

	stmt := new(syntax.Return_Stmt, allocator = p.allocator)
	stmt.exprs = exprs

	return stmt, nil
}

// Reports whether a token kind ends the current statement without contributing
// to it: a newline, end of input, block close, or a trailing comment.
@(private)
terminates_statement :: proc(kind: syntax.Token_Kind) -> bool {
	return kind == .New_Line || kind == .EOF || kind == .Right_Brace || kind == .Comment
}

// Expects the cursor positioned at the '=' operator, with the target names
// already collected by the caller.
parse_ident_assignment :: proc(p: ^Parser, names: [dynamic]syntax.Token) -> (syntax.Stmt, Maybe(Parser_Error)) {
	advance(p) // '='

	value, err := parse_ident_rhs(p)
	if err != nil do return nil, err

	stmt := new(syntax.Ident_Assignment_Stmt, allocator = p.allocator)
	stmt.value = value
	stmt.names = names
	return stmt, nil
}

parse_ident_rhs :: proc(p: ^Parser) -> ([dynamic]^syntax.Expr, Maybe(Parser_Error)) {
	exprs := make([dynamic]^syntax.Expr, allocator = p.allocator)
	for {
		value, err := parse_expr(p)
		if err != nil do return nil, err
		append(&exprs, value)

		if current(p).kind != .Comma do break
		advance(p) // ','
		skip_trivia(p)
	}

	return exprs, nil
}

parse_multi_target :: proc(p: ^Parser) -> (syntax.Stmt, Maybe(Parser_Error)) {
	names := make([dynamic]syntax.Token, allocator = p.allocator)

	for {
		if current(p).kind != .Ident {
			return nil, Parser_Error {
				kind    = .Unexpected_Token,
				message = "expected an identifier in the target list",
				token   = current(p),
			}
		}
		append(&names, current(p))
		advance(p) // the identifier

		if current(p).kind != .Comma do break
		advance(p) // ','
		skip_trivia(p)
	}

	#partial switch current(p).kind {
	case .Colon_Colon, .Colon_Equal, .Colon:
		return parse_decl(p, names)

	case .Equal:
		return parse_ident_assignment(p, names)

	case:
		return nil, Parser_Error {
			kind    = .Unexpected_Token,
			message = "expected ':=', '::', ':', or '=' after the target list",
			token   = current(p),
		}
	}
}

parse_decl :: proc(p: ^Parser, names: [dynamic]syntax.Token) -> (syntax.Stmt, Maybe(Parser_Error)) {
	stmt: syntax.Stmt
	#partial switch current(p).kind {
	case .Colon_Equal:
		advance(p) // ':='

		value, err := parse_ident_rhs(p)
		if err != nil do return nil, err

		decl_stmt := new(syntax.Ident_Decl_Stmt, allocator = p.allocator)
		decl_stmt^ = syntax.Ident_Decl_Stmt {
			names    = names,
			value    = value,
			constant = false,
			type     = nil,
		}
		stmt = decl_stmt

	case .Colon_Colon:
		advance(p) // '::'

		if len(names) == 1 {
			if is_fn_keyword(current(p)) {
				return parse_named_definition(p, names[0], nil)
			}
		}

		value, err := parse_ident_rhs(p)
		if err != nil do return nil, err

		if len(names) > 1 {
			ferr := reject_fn_literals(value)
			if ferr != nil do return nil, ferr
		}

		decl_stmt := new(syntax.Ident_Decl_Stmt, allocator = p.allocator)
		decl_stmt^ = syntax.Ident_Decl_Stmt {
			names    = names,
			value    = value,
			constant = true,
			type     = nil,
		}
		stmt = decl_stmt

	case .Colon:
		advance(p) // ':'

		decl_type, type_err := parse_type(p)
		if type_err != nil do return nil, type_err

		value: Maybe([dynamic]^syntax.Expr)
		constant := false
		if current(p).kind == .Equal || current(p).kind == .Colon {
			constant = current(p).kind == .Colon
			advance(p) // '=' or ':'

			// A typed constant (`:`) to a single-name definition keyword is the
			// same hoisted definition as `foo :: fn`, carrying its declared type.
			if constant && len(names) == 1 && is_fn_keyword(current(p)) {
				return parse_named_definition(p, names[0], decl_type)
			}

			rhs, err := parse_ident_rhs(p)
			if err != nil do return nil, err

			if constant && len(names) > 1 {
				if ferr := reject_fn_literals(rhs); ferr != nil do return nil, ferr
			}
			value = rhs
		}

		decl_stmt := new(syntax.Ident_Decl_Stmt, allocator = p.allocator)
		decl_stmt^ = syntax.Ident_Decl_Stmt {
			names    = names,
			value    = value,
			constant = constant,
			type     = decl_type,
		}
		stmt = decl_stmt

	case:
		return nil, Parser_Error {
			kind    = .Unexpected_Token,
			message = "expected ':=', '::', or ':' after identifier in declaration",
			token   = current(p),
		}
	}

	return stmt, nil
}

// Parses a should-be-hoisted named constant definition (bound with `::`, or a typed `:`).
parse_named_definition :: proc(p: ^Parser, name: syntax.Token, type: Maybe(syntax.Type)) -> (syntax.Stmt, Maybe(Parser_Error)) {
	current := current(p)
	assert(current.kind == .Keyword && current.keyword != nil)

	stmt: syntax.Stmt
	#partial switch current.keyword.? {
	case .Fn, .Async:
		err: Maybe(Parser_Error)
		stmt, err = parse_fn_decl_stmt(p, name, type)
		if err != nil do return nil, err
	}

	return stmt, nil
}

// Wraps a function literal in a named declaration. The cursor is positioned at
// the leading `fn` or `async` keyword.
parse_fn_decl_stmt :: proc(p: ^Parser, name: syntax.Token, type: Maybe(syntax.Type)) -> (syntax.Stmt, Maybe(Parser_Error)) {
	lit, err := parse_fn_lit(p)
	if err != nil do return nil, err

	stmt := new(syntax.Fn_Decl_Stmt, allocator = p.allocator)
	stmt^ = syntax.Fn_Decl_Stmt {
		name = name,
		lit  = lit,
		type = type,
	}

	return stmt, nil
}

parse_fn_lit :: proc(p: ^Parser) -> (syntax.Fn_Literal_Expr, Maybe(Parser_Error)) {
	async := false
	if current(p).kind == .Keyword && current(p).keyword == .Async {
		async = true
		advance(p) // consume 'async'
		skip_trivia(p)
	}

	if !(current(p).kind == .Keyword && current(p).keyword == .Fn) {
		return {}, Parser_Error {
			kind    = .Unexpected_Token,
			message = "expected 'fn' to begin a function literal",
			token   = current(p),
		}
	}
	advance(p) // consume 'fn'
	skip_trivia(p)

	if current(p).kind != .Left_Paren {
		return {}, Parser_Error {
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
		if err != nil do return {}, err
		skip_trivia(p)
	}

	// Should close the parenthesis after arguments
	if current(p).kind != .Right_Paren {
		return {}, Parser_Error {
			kind    = .Unexpected_Token,
			message = "expected a ')' to end function arguments",
			token   = current(p),
		}
	}

	advance(p) // consume ')'

	// Return(s)
	return_type: Maybe([dynamic]syntax.Type)
	if next, ok := next(p); ok && current(p).kind == .Minus && next.kind == .Greater {
		advance(p) // consume '-'
		advance(p) // consume '>'
		skip_trivia(p)

		returns: Maybe(Parser_Error)
		return_type, returns = parse_returns(p)
		if returns != nil do return {}, returns
	}

	block_stmt: Maybe(^syntax.Block_Stmt)
	if current(p).kind == .Left_Brace {
		value_stmt, err := parse_block(p)
		if err != nil do return {}, err
		ok: bool
		block_stmt, ok = value_stmt.(^syntax.Block_Stmt)
		assert(ok)
	}

	return syntax.Fn_Literal_Expr {
		block = block_stmt,
		async = async,
		args = args,
		return_type = return_type,
	}, nil
}

parse_type :: proc(p: ^Parser) -> (syntax.Type, Maybe(Parser_Error)) {
	start := current(p)

	if is_fn_keyword(current(p)) {
		ref, err := parse_fn_type(p)
		if err != nil do return {}, err
		return syntax.Type{variant = ref, span = make_span(start, p)}, nil

	} else if current(p).kind == .Ident {
		tok := current(p)
		advance(p) // the type name
		return syntax.Type{variant = tok, span = make_span(start, p)}, nil
	}

	return {}, Parser_Error {
		kind    = .Incorrect_Type_Expr,
		message = "expected a built-in or a user-defined type",
		token   = current(p),
	}
}

// Similar to parse_fn_lit but no body and no arg names
parse_fn_type :: proc(p: ^Parser) -> (syntax.Fn_Type, Maybe(Parser_Error)) {
	async := false
	if current(p).kind == .Keyword && current(p).keyword == .Async {
		async = true
		advance(p) // 'async'
		skip_trivia(p)
	}

	if !(current(p).kind == .Keyword && current(p).keyword == .Fn) {
		return {}, Parser_Error {
			kind    = .Unexpected_Token,
			message = "expected 'fn' to begin a function type",
			token   = current(p),
		}
	}
	advance(p) // 'fn'
	skip_trivia(p)

	if current(p).kind != .Left_Paren {
		return {}, Parser_Error {
			kind    = .Unexpected_Token,
			message = "expected a '(' after 'fn' in a function type",
			token   = current(p),
		}
	}
	advance(p) // '('

	params := make([dynamic]syntax.Type, allocator = p.allocator)
	for {
		skip_trivia(p)
		if current(p).kind == .Right_Paren {
			break
		}

		param, err := parse_type(p)
		if err != nil do return {}, err
		append(&params, param)

		skip_trivia(p)
		if current(p).kind != .Comma {
			break
		}
		advance(p) // ','
	}

	skip_trivia(p)
	if current(p).kind != .Right_Paren {
		return {}, Parser_Error {
			kind    = .Unexpected_Token,
			message = "expected a ')' to end function type parameters",
			token   = current(p),
		}
	}
	advance(p) // ')'

	returns := make([dynamic]syntax.Type, allocator = p.allocator)
	if next, ok := next(p); ok && current(p).kind == .Minus && next.kind == .Greater {
		advance(p) // '-'
		advance(p) // '>'
		skip_trivia(p)

		rets, err := parse_returns(p)
		if err != nil do return {}, err
		if r, ok := rets.?; ok {
			returns = r
		}
	}

	return syntax.Fn_Type{params = params, returns = returns, async = async}, nil
}

parse_returns :: proc(p: ^Parser) -> (Maybe([dynamic]syntax.Type), Maybe(Parser_Error)) {
	returns := make([dynamic]syntax.Type, allocator = p.allocator)

	// Single, unparenthesized return type
	if current(p).kind != .Left_Paren {
		ret, err := parse_type(p)
		if err != nil do return nil, err
		append(&returns, ret)
		return returns, nil
	}

	// Parenthesized list of return types
	advance(p) // consume '('
	for {
		skip_trivia(p)
		if current(p).kind == .Right_Paren {
			break
		}

		ret, err := parse_type(p)
		if err != nil do return nil, err
		append(&returns, ret)

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

// nocheckin: Check the trailing commma dunno what happens currently
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

		arg_type, type_err := parse_type(p)
		if type_err != nil do return nil, type_err
		append(&args, syntax.Fn_Arg{ name = arg_name, type = arg_type })

		skip_trivia(p)

		if current(p).kind != separator {
			break
		}
		
		advance(p) // separator
	}
	
	return args, nil
}

parse_call :: proc(p: ^Parser) -> (syntax.Token, [dynamic]^syntax.Expr, Maybe(Parser_Error)) {
	name := current(p)
	advance(p) // name
	advance(p) // '('

	args := make([dynamic]^syntax.Expr, allocator = p.allocator)
	for {
		skip_trivia(p)
		if current(p).kind == .Right_Paren {
			break
		}

		expr, err := parse_expr(p)
		if err != nil do return {}, nil, err

		append(&args, expr)

		skip_trivia(p)
		if current(p).kind != .Comma {
			break
		}
		advance(p) // ','
	}

	if current(p).kind != .Right_Paren {
		return name, args, Parser_Error {
			kind    = .Unexpected_Token,
			message = "expected ')' to end function call arguments",
			token   = current(p),
		}
	}
	advance(p) // ')'

	return name, args, nil
}

parse_fn_call :: proc(p: ^Parser) -> (syntax.Stmt, Maybe(Parser_Error)) {
	name, args, err := parse_call(p)
	if err != nil do return nil, err

	stmt := new(syntax.Fn_Call_Stmt, allocator = p.allocator)
	stmt^ = syntax.Fn_Call_Stmt {
		call = syntax.Fn_Call_Expr {
			name = name,
			args = args,
			awaited = false, // nocheckin
		}
	}

	return stmt, nil
}

parse_block :: proc(p: ^Parser) -> (syntax.Stmt, Maybe(Parser_Error)) {
	open := current(p)
	if open.kind != .Left_Brace {
		return nil, Parser_Error {
			kind    = .Unexpected_Token,
			message = "expected '{' to start block",
			token   = open,
		}
	}
	advance(p)

	inner := make([dynamic]syntax.Stmt, 0, 8, allocator = p.allocator)

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
				message = "unexpected EOF while parsing block - missing '}'",
				token = tok,
			}
		}

		s, err := parse_stmt(p)
		if err != nil do return nil, err
		append(&inner, s)

		term_err := expect_terminator(p)
		if term_err != nil do return nil, term_err
	}

	stmt := new(syntax.Block_Stmt, allocator = p.allocator)
	stmt.stmts = inner[:]
	return stmt, nil
}

parse_expr :: proc(p: ^Parser) -> (^syntax.Expr, Maybe(Parser_Error)) {
	expr, err := parse_logic_or(p)
	if err != nil do return expr, err

	return expr, nil
}

parse_logic_or :: proc(p: ^Parser) -> (^syntax.Expr, Maybe(Parser_Error)) {
	start := current(p)
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
			span = make_span(start, p),
		}
		expr = result
	}

	return expr, nil
}

parse_logic_and :: proc(p: ^Parser) -> (^syntax.Expr, Maybe(Parser_Error)) {
	start := current(p)
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
			span = make_span(start, p),
		}
		expr = result
	}

	return expr, nil
}

parse_equality :: proc(p: ^Parser) -> (^syntax.Expr, Maybe(Parser_Error)) {
	start := current(p)
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
			span = make_span(start, p),
		}
		expr = result
	}

	return expr, nil
}

parse_comparison :: proc(p: ^Parser) -> (^syntax.Expr, Maybe(Parser_Error)) {
	start := current(p)
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
			span = make_span(start, p),
		}
		expr = result
	}

	return expr, nil
}

parse_term :: proc(p: ^Parser) -> (^syntax.Expr, Maybe(Parser_Error)) {
	start := current(p)
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
			span = make_span(start, p),
		}
		expr = result
	}

	return expr, nil
}

parse_factor :: proc(p: ^Parser) -> (^syntax.Expr, Maybe(Parser_Error)) {
	start := current(p)
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
			span = make_span(start, p),
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
			span = make_span(current_token, p),
		}
		return result, nil
	}

	return parse_primary(p)
}

parse_primary :: proc(p: ^Parser) -> (^syntax.Expr, Maybe(Parser_Error)) {
	expr := new(syntax.Expr, allocator = p.allocator)

	tok := current(p)
	if tok.kind == .EOF {
		return expr, Parser_Error {
			kind = .Unexpected_EOF,
			message = "Unexpected \"EOF\" token while parsing primary",
			token = p.tokens[max(p.current - 1, 0)],
		}
	}

	#partial switch tok.kind {
	case .Literal:
		result := syntax.Expr {
			expr = syntax.Literal_Expr{token = tok},
		}
		expr^ = result
		advance(p)

	case .Ident:
		if n, ok := next(p); ok && n.kind == .Left_Paren { // function call
			name, args, err := parse_call(p)
			if err != nil do return expr, err
			expr^ = syntax.Expr {
				expr = syntax.Fn_Call_Expr{
					name = name,
					args = args,
					awaited = false // nocheckin
				},
			}
		} else {
			expr^ = syntax.Expr {
				expr = syntax.Ident_Expr{token = tok},
			}
			advance(p)
		}

	case .Left_Paren:
		advance(p)
		expr_inner, err := parse_expr(p)
		if err != nil do return expr, err

		current_token := current(p)
		if current_token.kind == .EOF || current_token.kind != .Right_Paren {
			return expr, Parser_Error {
				kind = .Unclosed_Paren,
				message = "Expected a \")\" token",
				token = current_token,
			}
		}

		advance(p)

		expr^ = syntax.Expr {
			expr = syntax.Grouping_Expr{expr = expr_inner},
		}

	case .Keyword:
		if !is_fn_keyword(tok) {
			return expr, Parser_Error {
				kind = .Unexpected_Token,
				message = "Unexpected keyword while parsing primary",
				token = tok,
			}
		}

		// Anonymous function literal
		lit, err := parse_fn_lit(p)
		if err != nil do return expr, err
		expr^ = syntax.Expr {
			expr = lit,
		}

	case:
		return expr, Parser_Error {
			kind = .Unexpected_Token,
			message = "Unexpected token while parsing primary",
			token = tok,
		}

	}

	// tok is the first token of the this expression.
	// The cursor has passed the expression so make_span taks the prev as the end
	expr.span = make_span(tok, p)
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

prev_token :: proc(p: ^Parser) -> syntax.Token {
	return p.tokens[max(p.current - 1, 0)]
}

make_span :: proc(start: syntax.Token, p: ^Parser) -> syntax.Span {
	return syntax.Span{start = start.lexeme_start, end = prev_token(p).lexeme_end}
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
	if tok.kind == .New_Line || tok.kind == .EOF || tok.kind == .Right_Brace {
		return nil
	}

	return Parser_Error {
		kind = .Missing_Terminator,
		message = "expected newline, '}', or end of input after statement",
		token = tok,
	}
}

// Reports whether the token begins a function literal: `fn` or `async`.
@(private)
is_fn_keyword :: proc(token: syntax.Token) -> bool {
	if token.kind != .Keyword do return false
	kw, ok := token.keyword.?
	assert(ok)
	return ok && (kw == .Fn || kw == .Async)
}

// Rule A: a function literal may not appear in a multi-name constant
// declaration - a definition must bind exactly one name.
@(private)
reject_fn_literals :: proc(exprs: [dynamic]^syntax.Expr) -> Maybe(Parser_Error) {
	for expr in exprs {
		if _, ok := expr.expr.(syntax.Fn_Literal_Expr); ok {
			return Parser_Error {
				kind    = .Fn_In_Multi_Decl,
				message = "a function definition must bind a single name; it cannot appear in a multi-name '::' declaration",
				token   = syntax.Token {
					lexeme_start = expr.span.start,
					lexeme_end   = expr.span.end,
				},
			}
		}
	}

	return nil
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
	Unclosed_Paren,
	Unexpected_Token,
	Else_With_No_If,
	Missing_Terminator,
	Incorrect_Type_Expr,
	Fn_In_Multi_Decl,
}

@(private)
error_hint :: proc(kind: Parser_Error_Kind) -> Maybe(string) {
	#partial switch kind {
	case .Unexpected_EOF:
		return "input ended before the statement was complete"
		
	case .Unclosed_Paren:
		return "add a matching ')'"
		
	case .Incorrect_Type_Expr:
		return "expected a built-in or user-defined type name"
		
	case .Else_With_No_If:
		return "'else' must follow '}' on the same line"
		
	case .Missing_Terminator:
		return "expected newline, '}', or end of input"

	case .Fn_In_Multi_Decl:
		return "give the function its own single-name '::' declaration"
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
