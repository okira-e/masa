package analyzer

import "../syntax"
import "core:fmt"
import "core:strings"

Analyzer :: struct {
	source:   string,
	env:      ^Scope,

	t_number: ^Symbol,
	t_string: ^Symbol,
	t_bool:   ^Symbol,
	t_any:    ^Symbol,
}

Scope :: struct {
	symbols: map[string]^Symbol,
	parent:  Maybe(^Scope),

	// References pointers to defined symbols for destroying later. If the symbol is an alias to
	// a pre-defined symbol, it doesn't go here, only the `symbols` map so that the aliased reference
	// isn't deleted with the alias symbol.
	owned_symbols: [dynamic]^Symbol,
}

Symbol :: union {
	Var_Symbol,
	Type_Symbol,
}

Var_Symbol :: struct {
	constant:   bool,
	decl_token: syntax.Token,
	type:       ^Symbol,
}

Type_Symbol :: struct {
	name:       string,
	decl_token: syntax.Token,
}

init :: proc(a: ^Analyzer, source: string) {
	a.source = source

	universe := make_scope(nil)
	a.t_number = declare_type(universe, "number")
	a.t_string = declare_type(universe, "string")
	a.t_bool   = declare_type(universe, "bool")
	a.t_any    = declare_type(universe, "any")

	a.env = make_scope(universe)
}

destroy :: proc(a: ^Analyzer) {
	current: Maybe(^Scope) = a.env
	for current != nil {
		s := current.?
		next := s.parent
		free_scope(s)
		current = next
	}
}

analyze :: proc(a: ^Analyzer, stmts: []^syntax.Stmt) -> Maybe(Analyzer_Error) {
	for stmt in stmts {
		err := check_stmt(a, stmt)
		if err != nil do return err
	}

	return nil
}

check_stmt :: proc(a: ^Analyzer, stmt: ^syntax.Stmt) -> Maybe(Analyzer_Error) {
	switch &stmt in stmt {
	case syntax.Expr_Stmt:
		_, err := check_expr(a, stmt.expr)
		return err

	case syntax.Ident_Decl_Stmt:
		return check_ident_decl(a, &stmt)

	case syntax.Ident_Assignment_Stmt:
		return check_ident_assignment(a, stmt)

	case syntax.If_Stmt:
		return check_if_stmt(a, stmt)

	case syntax.Block_Stmt:
		return check_block_stmt(a, stmt)
	}

	return nil
}

check_ident_decl :: proc(a: ^Analyzer, stmt: ^syntax.Ident_Decl_Stmt) -> Maybe(Analyzer_Error) {
	new_name := a.source[stmt.name.lexeme_start:stmt.name.lexeme_end]

	// 
	// Handle type declarations `A :: B` where the rhs type is a pre-defined ident.
	// No appending to owned_symbols happen here.
	//

	if stmt.constant && stmt.type == nil {
		if val, ok := stmt.value.?; ok {
			if ident_expr, ok := val.expr.(syntax.Ident_Expr); ok {
				rhs_lexeme := a.source[ident_expr.token.lexeme_start:ident_expr.token.lexeme_end]
				if sym, found := resolve_ident(a, rhs_lexeme); found {
					if _, is_type := sym^.(Type_Symbol); is_type {
						if _, dup := a.env.symbols[new_name]; dup { // dupe in this scope since we allow shadowing
							return Analyzer_Error {
								kind    = .Variable_Redeclaration,
								token   = stmt.name,
								message = "name already declared in this scope",
							}
						}

						stmt.decl_kind = .Type_Alias
						a.env.symbols[new_name] = sym

						return nil
					}
				}
			}
		}
	}

	//
	// Handle constant/mutable declarations with a value rhs either with a declared type or without.
	//

	declared_type: ^Symbol = nil
	if ref, has := stmt.type.?; has {
		t, err := resolve_type(a, ref.token)
		if err != nil do return err
		declared_type = t
	}

	value_type: ^Symbol = nil
	if val, has := stmt.value.?; has {
		t, err := check_expr(a, val)
		if err != nil do return err
		value_type = t
	}

	if declared_type == nil && value_type == nil {
		return Analyzer_Error {
			kind    = .Declaration_Type_Missing,
			token   = stmt.name,
			message = "declaration must either define a type or a value to infer the type from",
		}
	}

	if declared_type != nil && value_type != nil && !match_type(declared_type, value_type) {
		return Analyzer_Error {
			kind    = .Type_Mismatch_On_Declaration,
			token   = stmt.name,
			message = "type mismatch",
		}
	}

	// Since shadowing is allowed, check only the current scope for duplicates
	if _, dup := a.env.symbols[new_name]; dup {
		return Analyzer_Error {
			kind    = .Variable_Redeclaration,
			token   = stmt.name,
			message = "name already declared in this scope",
		}
	}

	final_type := declared_type != nil ? declared_type : value_type
	sym := make_symbol(Var_Symbol {
		constant   = stmt.constant,
		decl_token = stmt.name,
		type       = final_type,
	})

	append(&a.env.owned_symbols, sym)

	stmt.decl_kind = .Value
	a.env.symbols[new_name] = sym

	return nil
}

check_ident_assignment :: proc(a: ^Analyzer, stmt: syntax.Ident_Assignment_Stmt) -> Maybe(Analyzer_Error) {
	value_type, err := check_expr(a, stmt.value)
	if err != nil do return err

	sym, rerr := resolve_var(a, stmt.name)
	if rerr != nil do return rerr
	var_sym := sym^.(Var_Symbol)

	if var_sym.constant {
		return Analyzer_Error {
			kind    = .Variable_Constant,
			token   = stmt.name,
			message = "variable is declared as a constant and thus cannot be changed",
		}
	}

	if value_type != nil && !match_type(var_sym.type, value_type) {
		return Analyzer_Error {
			kind    = .Type_Mismatch_On_Assignment,
			token   = stmt.name,
			message = "type mismatch",
		}
	}

	return nil
}

check_if_stmt :: proc(a: ^Analyzer, stmt: syntax.If_Stmt) -> Maybe(Analyzer_Error) {
	cond_type, err := check_expr(a, stmt.condition)
	if err != nil do return err

	if cond_type != a.t_bool {
		return Analyzer_Error {
			kind    = .Condition_Not_Bool,
			token   = first_token(stmt.condition),
			message = "if condition must be a bool",
		}
	}

	if err := check_stmt(a, stmt.then_block); err != nil do return err
	if else_stmt, has := stmt.else_branch.?; has {
		if err := check_stmt(a, else_stmt); err != nil do return err
	}

	return nil
}

check_block_stmt :: proc(a: ^Analyzer, stmt: syntax.Block_Stmt) -> Maybe(Analyzer_Error) {
	new_scope := make_scope(a.env)
	a.env = new_scope
	defer {
		a.env = new_scope.parent.?
		free_scope(new_scope)
	}

	for inner in stmt.stmts {
		if err := check_stmt(a, inner); err != nil do return err
	}

	return nil
}

check_expr :: proc(a: ^Analyzer, expr: ^syntax.Expr) -> (^Symbol, Maybe(Analyzer_Error)) {
	switch v in expr.expr {
	case syntax.Literal_Expr:
		lit_kind, ok := v.token.literal_kind.?
		assert(ok)
		switch lit_kind {
		case .Number:
			return a.t_number, nil
			
		case .String:
			return a.t_string, nil
			
		case .Bool:
			return a.t_bool,   nil
			
		case .Nil:
			return nil, nil
		}

	case syntax.Unary_Expr:
		return check_unary(a, v)

	case syntax.Binary_Expr:
		return check_binary(a, v)

	case syntax.Grouping_Expr:
		return check_expr(a, v.expr)

	case syntax.Ident_Expr:
		sym, err := resolve_var(a, v.token)
		if err != nil do return nil, err
		return sym^.(Var_Symbol).type, nil

	case syntax.Logical_Expr:
		return check_logical(a, v)
	}

	assert(false)
	unreachable()
}

check_unary :: proc(a: ^Analyzer, v: syntax.Unary_Expr) -> (^Symbol, Maybe(Analyzer_Error)) {
	operand, err := check_expr(a, v.right)
	if err != nil do return nil, err

	tok := first_token(v.right)
	#partial switch v.op {
	case .Minus:
		if operand != a.t_number {
			return nil, Analyzer_Error {
				kind    = .Operator_Type_Mismatch,
				token   = tok,
				message = "unary '-' requires a number",
			}
		}
		return a.t_number, nil
	case .Bang:
		if operand != a.t_bool {
			return nil, Analyzer_Error {
				kind    = .Operator_Type_Mismatch,
				token   = tok,
				message = "unary '!' requires a bool",
			}
		}
		return a.t_bool, nil
	}

	assert(false)
	unreachable()
}

check_binary :: proc(a: ^Analyzer, v: syntax.Binary_Expr) -> (^Symbol, Maybe(Analyzer_Error)) {
	left, lerr := check_expr(a, v.left)
	if lerr != nil do return nil, lerr
	right, rerr := check_expr(a, v.right)
	if rerr != nil do return nil, rerr

	tok := first_token(v.left)
	#partial switch v.op {
	case .Plus, .Minus, .Star, .Slash:
		if left != a.t_number || right != a.t_number {
			return nil, Analyzer_Error {
				kind    = .Operator_Type_Mismatch,
				token   = tok,
				message = "arithmetic operator requires numbers",
			}
		}

		return a.t_number, nil

	case .Greater, .Greater_Equal, .Less, .Less_Equal:
		if left != a.t_number || right != a.t_number {
			return nil, Analyzer_Error {
				kind    = .Operator_Type_Mismatch,
				token   = tok,
				message = "comparison operator requires numbers",
			}
		}

		return a.t_bool, nil

	case .Equal_Equal, .Bang_Equal:
		if !match_type(left, right) {
			return nil, Analyzer_Error {
				kind    = .Operator_Type_Mismatch,
				token   = tok,
				message = "equality requires operands of the same type",
			}
		}

		return a.t_bool, nil
	}

	assert(false)
	unreachable()
}

check_logical :: proc(a: ^Analyzer, v: syntax.Logical_Expr) -> (^Symbol, Maybe(Analyzer_Error)) {
	left, lerr := check_expr(a, v.left)
	if lerr != nil do return nil, lerr
	right, rerr := check_expr(a, v.right)
	if rerr != nil do return nil, rerr

	if left != a.t_bool || right != a.t_bool {
		return nil, Analyzer_Error {
			kind    = .Operator_Type_Mismatch,
			token   = first_token(v.left),
			message = "logical operator requires bools",
		}
	}

	return a.t_bool, nil
}

// Walk from the current scope up to universe.
resolve_ident :: proc(a: ^Analyzer, name: string) -> (^Symbol, bool) {
	current: Maybe(^Scope) = a.env
	for current != nil {
		scope := current.?
		if sym, ok := scope.symbols[name]; ok do return sym, true
		current = scope.parent
	}
	return nil, false
}

// Resolve a name expected to refer to a type (declaration type position).
resolve_type :: proc(a: ^Analyzer, name_tok: syntax.Token) -> (^Symbol, Maybe(Analyzer_Error)) {
	name := a.source[name_tok.lexeme_start:name_tok.lexeme_end]
	sym, found := resolve_ident(a, name)
	if !found {
		return nil, Analyzer_Error {
			kind    = .Undefined_Type,
			token   = name_tok,
			message = "undefined type",
		}
	}
	if _, is_type := sym^.(Type_Symbol); !is_type {
		return nil, Analyzer_Error {
			kind    = .Variable_In_Type_Position,
			token   = name_tok,
			message = "expected a type but found a variable",
		}
	}

	return sym, nil
}

// Resolve a name expected to refer to a variable (expression/assignment position).
resolve_var :: proc(a: ^Analyzer, name_tok: syntax.Token) -> (^Symbol, Maybe(Analyzer_Error)) {
	name := a.source[name_tok.lexeme_start:name_tok.lexeme_end]
	sym, found := resolve_ident(a, name)
	if !found {
		return nil, Analyzer_Error {
			kind    = .Undefined_Variable,
			token   = name_tok,
			message = "undefined variable",
		}
	}
	if _, is_var := sym^.(Var_Symbol); !is_var {
		return nil, Analyzer_Error {
			kind    = .Type_In_Value_Position,
			token   = name_tok,
			message = "type used in value position",
		}
	}

	return sym, nil
}

// Two types are equal if they are the same Symbol allocation.
match_type :: proc(a, b: ^Symbol) -> bool {
	return a == b
}

// Representative token for an expression.
first_token :: proc(expr: ^syntax.Expr) -> syntax.Token {
	switch v in expr.expr {
	case syntax.Literal_Expr:  return v.token
	case syntax.Ident_Expr:    return v.token
	case syntax.Unary_Expr:    return first_token(v.right)
	case syntax.Binary_Expr:   return first_token(v.left)
	case syntax.Grouping_Expr: return first_token(v.expr)
	case syntax.Logical_Expr:  return first_token(v.left)
	}

	return {}
}

make_symbol :: proc(value: Symbol) -> ^Symbol {
	s := new(Symbol)
	s^ = value
	return s
}

make_scope :: proc(parent: Maybe(^Scope)) -> ^Scope {
	s := new(Scope)
	s^ = {
		symbols       = make(map[string]^Symbol),
		owned_symbols = make([dynamic]^Symbol),
		parent        = parent,
	}

	return s
}

free_scope :: proc(s: ^Scope) {
	for sym in s.owned_symbols {
		free(sym)
	}

	delete(s.owned_symbols)
	delete(s.symbols)
	free(s)
}

declare_type :: proc(scope: ^Scope, name: string) -> ^Symbol {
	s := make_symbol(Type_Symbol{ name = name })
	append(&scope.owned_symbols, s)
	scope.symbols[name] = s
	return s
}

Analyzer_Error :: struct {
	kind:    Analyzer_Error_Kind,
	token:   syntax.Token,
	message: string,
}

Analyzer_Error_Kind :: enum u8 {
	Undefined_Variable,
	Undefined_Type,
	Variable_Redeclaration,
	Variable_Constant,
	Type_Mismatch_On_Assignment,
	Type_Mismatch_On_Declaration,
	Declaration_Type_Missing,
	Type_In_Value_Position,
	Variable_In_Type_Position,
	Operator_Type_Mismatch,
	Condition_Not_Bool,
}

@(private)
error_hint :: proc(kind: Analyzer_Error_Kind) -> Maybe(string) {
	#partial switch kind {
	case .Variable_Constant:
		return "declare with ':=' instead of '::' if it needs to change"
		
	case .Type_Mismatch_On_Assignment:
		return "the value's type doesn't match the variable's declared type"
		
	case .Type_Mismatch_On_Declaration:
		return "the value's type doesn't match the declared type"
		
	case .Declaration_Type_Missing:
		return "add a type annotation or an initial value"
		
	case .Type_In_Value_Position:
		return "you may have meant a variable with this name"
		
	case .Variable_In_Type_Position:
		return "you may have meant a type with this name"
	}

	return nil
}

// Renders a rustc-style diagnostic. Uses err.token's lexeme span for the
// source location and err.message as the headline.
format_error :: proc(err: Analyzer_Error, source: string, allocator := context.allocator) -> string {
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

	return strings.to_string(b)
}

@(private)
write_repeat :: proc(b: ^strings.Builder, c: byte, n: int) {
	for _ in 0..<n do strings.write_byte(b, c)
}
