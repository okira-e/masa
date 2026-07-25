package analyzer

import "../syntax"
import "core:fmt"
import "core:strings"

// nocheckin: Check the context.allocator allocations
Analyzer :: struct {
	source:        string,
	env:           ^Scope,

	t_number:      ^Symbol,
	t_string:      ^Symbol,
	t_bool:        ^Symbol,
	t_any:         ^Symbol,

	inside_func_body: bool,
	should_return:    []Type
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
	Fn_Symbol,
}

Var_Symbol :: struct {
	constant:   bool,
	decl_token: syntax.Token,
	type:       Type,
	is_arg:     bool,
}

Type_Symbol :: struct {
	name:       string,
	decl_token: syntax.Token,
}

Fn_Symbol :: struct {
	name:    string,
	type:    Fn_Type,
	literal: syntax.Fn_Literal_Expr,
}

Type :: union {
	^Symbol,
	Fn_Type,
	// Multi_Value,
}

Fn_Type :: struct {
	return_types: Maybe([dynamic]Type),
	args:         [dynamic]Type,
	async:        bool,
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

analyze :: proc(a: ^Analyzer, stmts: []syntax.Stmt) -> Maybe(Analyzer_Error) {
	for stmt in stmts {
		err := check_stmt(a, stmt)
		if err != nil do return err
	}

	return nil
}

check_stmt :: proc(a: ^Analyzer, stmt: syntax.Stmt) -> Maybe(Analyzer_Error) {
	// This switch as to handle every statement because any statement can appear
	// anywhere
	switch stmt in stmt {
	case ^syntax.Expr_Stmt:
		// Evaluation is discarded
		_, err := check_expr(a, stmt.expr)
		return err

	case ^syntax.Ident_Decl_Stmt:
		return check_ident_decl(a, stmt)

	case ^syntax.Fn_Decl_Stmt:
		return check_fn_decl_stmt(a, stmt)

	case ^syntax.Fn_Call_Stmt:
		return check_fn_call(a, stmt)

	case ^syntax.Ident_Assignment_Stmt:
		return check_ident_assignment(a, stmt)

	case ^syntax.If_Stmt:
		return check_if_stmt(a, stmt)

	case ^syntax.Block_Stmt:
		return check_block_stmt(a, stmt, false, []Type{}, []Block_Capture{})

	case ^syntax.Return_Stmt:
		if !a.inside_func_body {
			return Analyzer_Error {
				kind    = .Return_Outside_Function,
				span    = span_of_exprs(stmt.exprs[:]),
				message = "'return' can only appear inside a function body",
			}
		}

		return check_return_stmt(a, stmt)
	}

	return Analyzer_Error {
		kind    = .Illegal_Statement,
		// span    = // nocheckin
		message = "this statement is not allowed here",
	}
}

check_ident_decl :: proc(a: ^Analyzer, stmt: ^syntax.Ident_Decl_Stmt) -> Maybe(Analyzer_Error) {
	if len(stmt.names) == 0 {
		return nil
	}

	//
	// Handle type declarations `A :: B` where the RHS type is a pre-defined symbol.
	// No appending to owned_symbols happen here.
	//

	if stmt.constant && stmt.type == nil {
		if val, ok := stmt.value.?; ok {
			is_type_alias_decl := true
			if len(val) == len(stmt.names) {
				for value in val {
					rhs, is_ident := value.expr.(syntax.Ident_Expr)
					if !is_ident {
						is_type_alias_decl = false
						break
					}

					lexeme := a.source[rhs.token.lexeme_start:rhs.token.lexeme_end]
					sym, found := resolve_ident(a, lexeme)
					if !found {
						is_type_alias_decl = false
						break
					}

					if _, is_type := sym^.(Type_Symbol); !is_type {
						is_type_alias_decl = false
						break
					}
				}
			}

			if is_type_alias_decl {
				for name_tok in stmt.names {
					name := a.source[name_tok.lexeme_start:name_tok.lexeme_end]
					if _, dup := a.env.symbols[name]; dup {
						return Analyzer_Error {
							kind    = .Variable_Redeclaration,
							span    = span_of(name_tok),
							message = "name already declared in this scope",
						}
					}
				}

				for name_tok, i in stmt.names {
					rhs := val[i].expr.(syntax.Ident_Expr)
					lexeme := a.source[rhs.token.lexeme_start:rhs.token.lexeme_end]
					sym, found := resolve_ident(a, lexeme)
					assert(found)

					name := a.source[name_tok.lexeme_start:name_tok.lexeme_end]
					a.env.symbols[name] = sym
				}

				stmt.decl_kind = .Type_Alias
				return nil
			}
		}
	}

	//
	// Handle constant/mutable declarations with a value rhs either with a declared type or without.
	//

	declared_type: Maybe(Type) = nil
	if type, has_declared_type := stmt.type.?; has_declared_type {
		resolved_type, err := resolve_type(a, type)
		if err != nil do return err
		declared_type = resolved_type
	}

	value_type: Maybe(Type) = nil
	if stmt_values, has := stmt.value.?; has {
		for value, i in stmt_values {
			type, err := check_single_expr(a, value)
			if err != nil do return err
			if i == 0 {
				value_type = type
			}

			if declared_type, ok := declared_type.?; ok {
				match, match_err := type_eq(declared_type, type)
				if match_err != nil do return match_err

				if declared_type != nil && type != nil && !match {
					return Analyzer_Error {
						kind    = .Type_Mismatch_On_Declaration,
						span    = value.span,
						message = "type mismatch",
					}
				}
			}
		}
	}

	if declared_type == nil && value_type == nil {
		first_name := stmt.names[0]
		last_name := stmt.names[len(stmt.names) - 1]
		return Analyzer_Error {
			kind    = .Declaration_Type_Missing,
			span    = syntax.Span{start = first_name.lexeme_start, end = last_name.lexeme_end},
			message = "declaration must either define a type or a value to infer the type from",
		}
	}

	final_type := declared_type != nil ? declared_type.? : value_type.? // one has to exist
	for name_token in stmt.names {
		name := a.source[name_token.lexeme_start:name_token.lexeme_end]

		// Since shadowing is allowed, check only the current scope for duplicates
		if _, dup := a.env.symbols[name]; dup {
			return Analyzer_Error {
				kind    = .Variable_Redeclaration,
				span    = span_of(name_token),
				message = "name already declared in this scope",
			}
		}

		sym := new_symbol(Var_Symbol {
			constant   = stmt.constant,
			decl_token = name_token,
			type       = final_type,
		})
		stmt.decl_kind = .Value

		append(&a.env.owned_symbols, sym)
		a.env.symbols[name] = sym
	}

	return nil
}

check_fn_decl_stmt :: proc(a: ^Analyzer, stmt: ^syntax.Fn_Decl_Stmt) -> Maybe(Analyzer_Error) {
	name := a.source[stmt.name.lexeme_start:stmt.name.lexeme_end]
	if _, exists := a.env.symbols[name]; exists {
		return Analyzer_Error{
			kind    = .Duplicate_Fn_Definition,
			span    = span_of(stmt.name),
			message = "function already defined"
		}
	}

	// We know the type is Fn_Type. We don't care.
	fn_type, err := check_fn_expr(a, stmt.lit)
	if err != nil do return err

	sym := new_symbol(Fn_Symbol {
		name    = name,
		type    = fn_type,
		literal = stmt.lit,
	})

	append(&a.env.owned_symbols, sym)
	a.env.symbols[name] = sym

	return nil
}

check_fn_expr :: proc(a: ^Analyzer, expr: syntax.Fn_Literal_Expr) -> (Fn_Type, Maybe(Analyzer_Error)) {
	a.inside_func_body = true
	defer a.inside_func_body = false
	defer a.should_return = []Type{}

	//
	// type check arguments
	//
	seen := make(map[string]bool, len(expr.args))
	defer delete(seen)
	args_types := make([dynamic]Type, len(expr.args), allocator = context.temp_allocator)

	// Args as symbols that will be passed down to check_block_stmt when we call it.
	captured_symbols := make([dynamic]Block_Capture, len(expr.args), allocator = context.temp_allocator)
	defer delete(captured_symbols)

	for arg, i in expr.args {
		arg_type, err := resolve_type(a, arg.type)
		if err != nil do return {}, err

		// duplicate
		arg_name := a.source[arg.name.lexeme_start:arg.name.lexeme_end]
		if seen[arg_name] {
			return {}, Analyzer_Error {
				kind    = .Duplicate_Fn_Argument_Definition,
				span    = span_of(arg.name),
				message = "duplicate argument name found"
			}
		}

		seen[arg_name] = true
		args_types[i] = arg_type
	}
	
	for arg, i in expr.args {
		arg_name := a.source[arg.name.lexeme_start:arg.name.lexeme_end]
		sym := new_symbol(Var_Symbol {
			constant   = true,
			decl_token = arg.name,
			type       = args_types[i],
			is_arg     = true,
		})

		captured_symbols[i] = Block_Capture {
			name    = arg_name,
			sym     = sym,
			mutable = false,
		}
	}


	//
	// type check returns (in the signature)
	//
	return_types: Maybe([dynamic]Type) = nil
	if declared_returns, ok := expr.return_type.?; ok {
		resolved := make([dynamic]Type, len(declared_returns), allocator = context.temp_allocator)

		for declared_return, i in declared_returns {
			rt, err := resolve_type(a, declared_return)
			if err != nil do return {}, err

			resolved[i] = rt
		}

		return_types = resolved
		if return_types, ok := return_types.?; ok {
			a.should_return = return_types[:]
		} else {
			a.should_return = []Type{}
		}
	}

	if block, ok := expr.block.?; ok {
		declared_returns := return_types != nil ? return_types.?[:] : []Type{}
		err := check_block_stmt(a, block, true, declared_returns, captured_symbols[:])
		if err != nil do return {}, err
	}

	// Check if the function returns
	if block, ok := expr.block.?; ok && return_types != nil && !always_terminates(a, block) {
		return {}, Analyzer_Error {
			kind    = .Missing_Return,
			// span    = // nocheckin: What's the span here?,
			// message = "number of returned values doesn't match the declared return types",
		}
	}

	// nocheckin: Checks usage of await inside an async/non-async function

	return Fn_Type {
		return_types = return_types,
		args         = args_types,
		async        = expr.async,
	}, nil
}

check_return_stmt :: proc(a: ^Analyzer, return_stmt: ^syntax.Return_Stmt) -> Maybe(Analyzer_Error) {
	values := make([dynamic]Type,        0, len(return_stmt.exprs), allocator = context.temp_allocator)
	spans  := make([dynamic]syntax.Span, 0, len(return_stmt.exprs), allocator = context.temp_allocator)
	for returned_expr in return_stmt.exprs {
		types, err := check_expr(a, returned_expr)
		if err != nil do return err
		for t in types {
			append(&values, t)
			append(&spans, returned_expr.span)
		}
	}

	if len(values) != len(a.should_return) {
		return Analyzer_Error {
			kind    = .Return_Count_Mismatch,
			span    = span_of_exprs(return_stmt.exprs[:]),
			message = "number of returned values doesn't match the declared return types",
		}
	}

	for value_type, i in values {
		matches, err := type_eq(value_type, a.should_return[i])
		if err != nil do return err

		if !matches {
			return Analyzer_Error {
				kind    = .Return_Type_Mismatch,
				span    = spans[i],
				message = "returned value's type doesn't match the declared return type",
			}
		}
	}

	return nil
}

check_fn_call :: proc(a: ^Analyzer, stmt: ^syntax.Fn_Call_Stmt) -> Maybe(Analyzer_Error) {
	name := a.source[stmt.call.name.lexeme_start:stmt.call.name.lexeme_end]
	sym, found := resolve_ident(a, name)
	if !found {
		return Analyzer_Error {
			kind    = .Undefined_Variable,
			span    = span_of(stmt.call.name), // nocheckin: Check the span thing is working with multiple error messages
			message = "undefined function",
		}
	}

	is_callable := false

	if _, ok := sym^.(Fn_Symbol); ok {
		is_callable = true
	} else if var_sym, ok := sym^.(Var_Symbol); ok {
		_, is_callable = var_sym.type.(Fn_Type)
	}

	if !is_callable {
		return Analyzer_Error{
			kind    = .Not_Callable,
			span    = span_of(stmt.call.name),
			message = "value is not a function and cannot be called",
		}
	}

	// Return types are discarded in a call statement
	_, err := check_fn_call_expr(a, stmt.call)
	if err != nil do return err

	return nil
}

check_ident_assignment :: proc(a: ^Analyzer, stmt: ^syntax.Ident_Assignment_Stmt) -> Maybe(Analyzer_Error) {
	if len(stmt.names) == 0 {
		return nil
	}

	value_types := make([dynamic]Type, allocator = context.temp_allocator)
	for value in stmt.value {
		value_type, err := check_single_expr(a, value)
		if err != nil do return err
		append(&value_types, value_type)
	}

	for name, i in stmt.names {
		sym, rerr := resolve_symbol(a, name)
		if rerr != nil do return rerr

		var: Var_Symbol
		switch s in sym^ {
		case Var_Symbol:
			var = s

		case Fn_Symbol:
			// A named function is declared with '::' (or the typed-constant form),
			// which is constant, so it can't be reassigned.
			return Analyzer_Error {
				kind    = .Variable_Constant,
				span    = span_of(name),
				message = "cannot reassign a function declared as a constant",
			}

		case Type_Symbol:
			return Analyzer_Error {
				kind    = .Type_In_Value_Position,
				span    = span_of(name),
				message = "type used in value position",
			}
		}

		if var.constant {
			return Analyzer_Error {
				kind    = .Variable_Constant,
				span    = span_of(name),
				message = "variable is declared as a constant and thus cannot be changed",
			}
		}

		value_type := value_types[min(i, len(value_types) - 1)]

		match, match_err := type_eq(var.type, value_type)
		if match_err != nil do return match_err

		if value_type != nil && !match {
			return Analyzer_Error {
				kind    = .Type_Mismatch_On_Assignment,
				span    = span_of(name),
				message = "type mismatch",
			}
		}
	}

	return nil
}

check_if_stmt :: proc(a: ^Analyzer, stmt: ^syntax.If_Stmt) -> Maybe(Analyzer_Error) {
	cond_type, err := check_single_expr(a, stmt.condition)
	if err != nil do return err
	cond_type_symbol, sure := cond_type.(^Symbol)
	if !sure {
		return Analyzer_Error {
			kind    = .Condition_Not_Bool,
			span    = stmt.condition.span,
			message = "if condition must be a bool",
		}
	}

	if cond_type_symbol != a.t_bool {
		return Analyzer_Error {
			kind    = .Condition_Not_Bool,
			span    = stmt.condition.span,
			message = "if condition must be a bool",
		}
	}

	err = check_stmt(a, stmt.then_block)
	if err != nil do return err

	if else_stmt, has := stmt.else_branch.?; has {
		err = check_stmt(a, else_stmt)
		if err != nil do return err
	}

	return nil
}

Block_Capture :: struct {
	name:   string,
	sym:    ^Symbol,
	mutable: bool,
}

check_block_stmt :: proc(
	a: ^Analyzer,
	stmt: ^syntax.Block_Stmt,
	// Determines if the keyword can appear at all.
	allow_return_keyword: bool,
	declared_returns: []Type,
	captured_symbols: []Block_Capture,
) -> Maybe(Analyzer_Error) {
	new_scope := make_scope(a.env)
	a.env = new_scope
	defer {
		a.env = new_scope.parent.?
		free_scope(new_scope)
	}

	// Setup any captured symbols (like arguments for a function that we're analyzing the body for)
	// in the current env.
	for sym in captured_symbols {
		a.env.symbols[sym.name] = sym.sym
		append(&a.env.owned_symbols, sym.sym)
	}

	for stmt in stmt.stmts {
		err := check_stmt(a, stmt)
		if err != nil do return err
	}

	return nil
}

// The full list of values an expression yields. Most produce exactly one; a
// call can produce several (or none, for a void call). Positions that require a
// single value should go through check_single instead.
check_expr :: proc(a: ^Analyzer, expr: ^syntax.Expr) -> ([]Type, Maybe(Analyzer_Error)) {
	switch expr in expr.expr {
	case syntax.Literal_Expr:
		lit_kind, ok := expr.token.literal_kind.?
		assert(ok)
		switch lit_kind {
		case .Number: return one_value(a.t_number), nil
		case .String: return one_value(a.t_string), nil
		case .Bool:   return one_value(a.t_bool),   nil
		case .Nil:    return one_value(nil),        nil
		}

	case syntax.Fn_Literal_Expr:
		t, err := check_fn_expr(a, expr)
		if err != nil do return nil, err
		return one_value(t), nil

	case syntax.Unary_Expr:
		t, err := check_unary(a, expr)
		if err != nil do return nil, err
		return one_value(t), nil

	case syntax.Binary_Expr:
		t, err := check_binary(a, expr)
		if err != nil do return nil, err
		return one_value(t), nil

	case syntax.Grouping_Expr:
		// Transparent: a group forwards the value list of its inner expression.
		return check_expr(a, expr.expr)

	case syntax.Ident_Expr:
		sym, err := resolve_symbol(a, expr.token)
		if err != nil do return nil, err
		// Check symbol type
		switch s in sym {
		case Var_Symbol:
			return one_value(s.type), nil

		case Fn_Symbol:
			return one_value(s.type), nil

		case Type_Symbol:
			return nil, Analyzer_Error {
				kind    = .Type_In_Value_Position,
				span    = span_of(s.decl_token),
				message = "type used in value position",
			}
		}
		

	case syntax.Logical_Expr:
		t, err := check_logical(a, expr)
		if err != nil do return nil, err
		return one_value(t), nil

	case syntax.Fn_Call_Expr:
		return check_fn_call_expr(a, expr)
	}

	assert(false)
	unreachable()
}

// The value list produced by a function call: the callee's resolved return
// types (already computed at declaration time), or none for a void call.
check_fn_call_expr :: proc(a: ^Analyzer, expr: syntax.Fn_Call_Expr) -> ([]Type, Maybe(Analyzer_Error)) {
	name := a.source[expr.name.lexeme_start:expr.name.lexeme_end]
	sym, found := resolve_ident(a, name)
	if !found {
		return nil, Analyzer_Error {
			kind    = .Undefined_Variable,
			span    = span_of(expr.name),
			message = "undefined function",
		}
	}

	fn_sym, ok := sym^.(Fn_Symbol)
	if !ok {
		return nil, Analyzer_Error {
			kind    = .Not_Callable,
			span    = span_of(expr.name),
			message = "value is not a function and cannot be called",
		}
	}

	if fn_sym.literal.block == nil {
		return nil, Analyzer_Error {
			kind    = .Call_To_Stub,
			span    = span_of(expr.name),
			message = "cannot call a function that has no body",
		}
	}

	// Check arguments match the declared parameters
	if len(expr.args) != len(fn_sym.literal.args) {
		return {}, Analyzer_Error {
			kind    = .Argument_Count_Mismatch,
			span    = span_of(expr.name),
			message = "the number of arguments doesn't match the function's parameters",
		}
	}

	// check type against declared one
	for passed_arg, i in expr.args {
		arg_type, err := check_single_expr(a, passed_arg)
		if err != nil do return nil, err

		param_type := fn_sym.type.args[i]
		assert(param_type != nil)

		matches, merr := type_eq(arg_type, param_type)
		if merr != nil do return nil, merr
		if !matches {
			return nil, Analyzer_Error {
				kind    = .Argument_Type_Mismatch,
				span    = passed_arg.span,
				message = "an argument's type doesn't match the function's parameter",
			}
		}
	}


	rets, has := fn_sym.type.return_types.?
	if !has do return {}, nil // void call: no values

	return rets[:], nil
}

type_from_token :: proc(a: ^Analyzer, tok: syntax.Token) -> (Type, Maybe(Analyzer_Error)) {
	#partial switch tok.kind {
	case .Literal:
		lit_kind, ok := tok.literal_kind.?
		assert(ok)
		switch lit_kind {
		case .Number: return a.t_number, nil
		case .String: return a.t_string, nil
		case .Bool:   return a.t_bool,   nil
		case .Nil:    return nil,         nil
		}

	case .Ident:
		sym, err := resolve_symbol(a, tok)
		if err != nil do return nil, err
		#partial switch s in sym {
		case Var_Symbol: return s.type, nil
		case Fn_Symbol:  return s.type, nil
		}
		return nil, Analyzer_Error {
			kind    = .Type_In_Value_Position,
			span    = span_of(tok),
			message = "type used in value position",
		}
	}

	return nil, Analyzer_Error {
		kind    = .Illegal_Statement,
		span    = span_of(tok),
		message = "unsupported call argument",
	}
}

check_single_expr :: proc(a: ^Analyzer, expr: ^syntax.Expr) -> (Type, Maybe(Analyzer_Error)) {
	types, err := check_expr(a, expr)
	if err != nil do return nil, err
	if len(types) != 1 {
		return nil, Analyzer_Error {
			kind    = .Multi_Value_In_Single_Context,
			span    = expr.span,
			message = "expression must produce exactly one value here",
		}
	}

	return types[0], nil
}

// Returns either a number symbol or a bool
check_unary :: proc(a: ^Analyzer, expr: syntax.Unary_Expr) -> (^Symbol, Maybe(Analyzer_Error)) {
	operand_type, err := check_single_expr(a, expr.right)
	if err != nil do return nil, err
	operand, ok := operand_type.(^Symbol)
	if !ok {
		return nil, Analyzer_Error {
			kind    = .Operator_Type_Mismatch,
			span    = expr.right.span,
			message = "operand is not a value that supports this operator",
		}
	}

	span := expr.right.span
	#partial switch expr.op {
	case .Minus:
		if operand != a.t_number {
			return nil, Analyzer_Error {
				kind    = .Operator_Type_Mismatch,
				span    = span,
				message = "unary '-' requires a number",
			}
		}

		return a.t_number, nil

	case .Bang:
		if operand != a.t_bool {
			return nil, Analyzer_Error {
				kind    = .Operator_Type_Mismatch,
				span    = span,
				message = "unary '!' requires a bool",
			}
		}

		return a.t_bool, nil
	}

	assert(false)
	unreachable()
}

check_binary :: proc(a: ^Analyzer, v: syntax.Binary_Expr) -> (^Symbol, Maybe(Analyzer_Error)) {
	left_type, lerr := check_single_expr(a, v.left)
	if lerr != nil do return nil, lerr
	left, ok := left_type.(^Symbol)
	if !ok {
		return nil, Analyzer_Error {
			kind    = .Operator_Type_Mismatch,
			span    = v.left.span,
			message = "left operand is not a value that supports this operator",
		}
	}

	right_type, rerr := check_single_expr(a, v.right)
	if rerr != nil do return nil, rerr
	right, sure := right_type.(^Symbol)
	if !sure {
		return nil, Analyzer_Error {
			kind    = .Operator_Type_Mismatch,
			span    = v.right.span,
			message = "right operand is not a value that supports this operator",
		}
	}

	span := v.left.span
	#partial switch v.op {
	case .Plus, .Minus, .Star, .Slash:
		if left != a.t_number || right != a.t_number {
			return nil, Analyzer_Error {
				kind    = .Operator_Type_Mismatch,
				span    = span,
				message = "arithmetic operator requires numbers",
			}
		}

		return a.t_number, nil

	case .Greater, .Greater_Equal, .Less, .Less_Equal:
		if left != a.t_number || right != a.t_number {
			return nil, Analyzer_Error {
				kind    = .Operator_Type_Mismatch,
				span    = span,
				message = "comparison operator requires numbers",
			}
		}

		return a.t_bool, nil

	case .Equal_Equal, .Bang_Equal:
		match, err := type_eq(left, right)
		if err != nil do return {}, err

		if !match {
			return nil, Analyzer_Error {
				kind    = .Operator_Type_Mismatch,
				span    = span,
				message = "equality requires operands of the same type",
			}
		}

		return a.t_bool, nil
	}

	assert(false)
	unreachable()
}

// Returns a bool symbol
check_logical :: proc(a: ^Analyzer, expr: syntax.Logical_Expr) -> (^Symbol, Maybe(Analyzer_Error)) {
	left_type, lerr := check_single_expr(a, expr.left)
	if lerr != nil do return nil, lerr

	left, ok := left_type.(^Symbol)
	if !ok {
		return nil, Analyzer_Error {
			kind    = .Operator_Type_Mismatch,
			span    = expr.left.span,
			message = "left operand of a logical operator is not a bool",
		}
	}

	right_type, rerr := check_single_expr(a, expr.right)
	if rerr != nil do return nil, rerr
	right, sure := right_type.(^Symbol)
	if !sure {
		return nil, Analyzer_Error {
			kind    = .Operator_Type_Mismatch,
			span    = expr.right.span,
			message = "right operand of a logical operator is not a bool",
		}
	}

	if left != a.t_bool || right != a.t_bool {
		return nil, Analyzer_Error {
			kind    = .Operator_Type_Mismatch,
			span    = expr.left.span,
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

// Resolve a syntactic type reference into a resolved analyzer `Type`. Recurses
// through function types so `fn(number) -> string` resolves its params/returns.
resolve_type :: proc(a: ^Analyzer, node: syntax.Type) -> (Type, Maybe(Analyzer_Error)) {
	switch v in node.variant {
	case syntax.Token:
		sym, err := resolve_token(a, v)
		if err != nil do return nil, err
		return sym, nil

	case syntax.Fn_Type:
		args := make([dynamic]Type, 0, len(v.params), allocator = context.temp_allocator)
		for param in v.params {
			pt, err := resolve_type(a, param)
			if err != nil do return nil, err
			append(&args, pt)
		}

		return_types: Maybe([dynamic]Type) = nil
		if len(v.returns) > 0 {
			resolved := make([dynamic]Type, 0, len(v.returns), allocator = context.temp_allocator)
			for ret in v.returns {
				rt, err := resolve_type(a, ret)
				if err != nil do return nil, err
				append(&resolved, rt)
			}
			return_types = resolved
		}

		return Fn_Type{args = args, return_types = return_types, async = v.async}, nil
	}

	// Zero-value type node (shouldn't happen for parsed input).
	return nil, Analyzer_Error {
		kind    = .Undefined_Type,
		span    = node.span,
		message = "missing type",
	}
}

// Resolve a name expected to refer to a type (declaration type position).
resolve_token :: proc(a: ^Analyzer, name_tok: syntax.Token) -> (^Symbol, Maybe(Analyzer_Error)) {
	name := a.source[name_tok.lexeme_start:name_tok.lexeme_end]
	sym, found := resolve_ident(a, name)
	if !found {
		return nil, Analyzer_Error {
			kind    = .Undefined_Type,
			span    = span_of(name_tok),
			message = "undefined type",
		}
	}

	if _, is_type := sym^.(Type_Symbol); !is_type {
		return nil, Analyzer_Error {
			kind    = .Value_Used_As_Type,
			span    = span_of(name_tok),
			message = "expected a type but found a value",
		}
	}

	return sym, nil
}

// Resolve a name expected to refer to a variable (expression/assignment position).
resolve_symbol :: proc(a: ^Analyzer, name_tok: syntax.Token) -> (^Symbol, Maybe(Analyzer_Error)) {
	name := a.source[name_tok.lexeme_start:name_tok.lexeme_end]
	sym, found := resolve_ident(a, name)

	if !found {
		return nil, Analyzer_Error {
			kind    = .Undefined_Variable,
			span    = span_of(name_tok),
			message = "undefined variable",
		}
	}

	return sym, nil
}

// Two *symbols* are equal if they are the same allocated pointer. Other types
// are matches accordingly.
type_eq :: proc(a: Type, b: Type) -> (bool, Maybe(Analyzer_Error)) {
	assert(a != nil)
	assert(b != nil)

	switch a in a {
	case ^Symbol:
		b, ok := b.(^Symbol)
		if !ok do return false, nil

		return a == b, nil
	
	case Fn_Type:
		b, ok := b.(Fn_Type)
		if !ok do return false, nil

		if a.async != b.async do return false, nil

		//
		// Args
		//

		if len(a.args) != len(b.args) do return false, nil
		for arg, i in a.args {
			match, err := type_eq(arg, b.args[i])
			if err != nil do return false, err
			if !match do return false, nil
		}

		//
		// Returns
		//

		a_rets, a_has := a.return_types.?
		b_rets, b_has := b.return_types.?
		if a_has != b_has do return false, nil
		if a_has {
			if len(a_rets) != len(b_rets) do return false, nil
			for ret, i in a_rets {
				match, err := type_eq(ret, b_rets[i])
				if err != nil do return false, err
				if !match do return false, nil
			}
		}

		return true, nil
	}

	assert(false)
	unreachable()
}

// Decides if the statement can fall through in execution or not
always_terminates :: proc(a: ^Analyzer, stmt: syntax.Stmt) -> bool {

	does_expr_terminate :: proc(expr: ^syntax.Expr) -> bool {
		#partial switch e in expr.expr {
		case syntax.Fn_Call_Expr:
			// @TODO: Functions like panic might have a #terminates that would be handled here
		}

		return false
	}

	// This is not a partial switch to remind us to extend this for
	// whenever we add a new statement.
	switch s in stmt {
	case ^syntax.Expr_Stmt:
		return does_expr_terminate(s.expr)

	case ^syntax.Ident_Decl_Stmt:
		if values, ok := s.value.?; ok {
			terminates := false
			for value in values {
				if does_expr_terminate(value) {
					terminates = true
					break
				}
			}

			return terminates
		}

	case ^syntax.Ident_Assignment_Stmt:
		terminates := false
		for value in s.value {
			if does_expr_terminate(value) {
				terminates = true
				break
			}
		}

		return terminates

	case ^syntax.Fn_Call_Stmt:
		name := a.source[s.call.name.lexeme_start:s.call.name.lexeme_end]
		sym, err := resolve_ident(a, name)
		fn_sym, ok := sym.(Fn_Symbol)
		assert(ok)
		assert(fn_sym.literal.block != nil)

		return always_terminates(a, fn_sym.literal.block.?.stmts[len(fn_sym.literal.block.?.stmts)-1])

	case ^syntax.If_Stmt:
		return s.else_branch != nil &&
			always_terminates(a, s.then_block) &&
			always_terminates(a, s.else_branch.?)

	case ^syntax.Block_Stmt:
		// @Performance: We Require a return statement to always be present
		// in the last line of any function to improve compiler performance.
		return len(s.stmts) > 0 && always_terminates(a, s.stmts[len(s.stmts)-1])

	case ^syntax.Return_Stmt:
		return true

	case ^syntax.Fn_Decl_Stmt:
	}

	return false // ironic
}

// A token's lexeme span. Lets token-rooted diagnostics (names, types) share the
// same span-based error path as expression-rooted ones (which carry expr.span).
span_of :: proc(tok: syntax.Token) -> syntax.Span {
	return syntax.Span{start = tok.lexeme_start, end = tok.lexeme_end}
}

// Best-effort span for a list of expressions (e.g. a return statement's values).
// Falls back to an empty span when there's nothing to point at.
span_of_exprs :: proc(exprs: []^syntax.Expr) -> syntax.Span {
	if len(exprs) > 0 do return exprs[0].span
	return {}
}

new_symbol :: proc(value: Symbol) -> ^Symbol {
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
	s := new_symbol(Type_Symbol{ name = name })
	append(&scope.owned_symbols, s)
	scope.symbols[name] = s
	return s
}

// Wrap a single value type as a one-element value list.
@(private)
one_value :: proc(t: Type) -> []Type {
	s := make([]Type, 1, allocator = context.temp_allocator)
	s[0] = t
	return s
}


Analyzer_Error :: struct {
	kind:    Analyzer_Error_Kind,
	span:    syntax.Span,
	message: string,
}

Analyzer_Error_Kind :: enum u8 {
	Undefined_Variable,
	Undefined_Type,
	Value_Used_As_Type,
	Variable_Redeclaration,
	Duplicate_Fn_Definition,
	Duplicate_Fn_Argument_Definition,
	Variable_Constant,
	Type_Mismatch_On_Assignment,
	Type_Mismatch_On_Declaration,
	Declaration_Type_Missing,
	Type_In_Value_Position,
	Operator_Type_Mismatch,
	Condition_Not_Bool,
	Not_Callable,
	Call_To_Stub,
	Argument_Count_Mismatch,
	Argument_Type_Mismatch,
	Missing_Return,
	Return_Type_Mismatch,
	Return_Count_Mismatch,
	Return_Outside_Function,
	Illegal_Statement,
	Void_In_Comparison,
	Multi_Value_In_Single_Context,
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

	case .Value_Used_As_Type:
		return "you may have meant a type with this name"

	case .Not_Callable:
		return "only functions can be called with '()'"

	case .Argument_Count_Mismatch:
		return "the number of arguments doesn't match the function's parameters"

	case .Argument_Type_Mismatch:
		return "an argument's type doesn't match the function's parameter"

	case .Missing_Return:
		return "every path through the function must return a value"

	case .Return_Type_Mismatch:
		return "the returned value's type doesn't match the declared return type"

	case .Return_Count_Mismatch:
		return "the number of returned values doesn't match the declared return types"

	case .Return_Outside_Function:
		return "'return' can only appear inside a function body"

	case .Illegal_Statement:
		return "this kind of statement isn't allowed in this position"

	case .Void_In_Comparison:
		return "a call returning no value can't be used in a comparison"

	case .Multi_Value_In_Single_Context:
		return "a call returning several values can only be used in a return, declaration, or assignment"
	}

	return nil
}

format_error :: proc(err: Analyzer_Error, source: string, allocator := context.allocator) -> string {
	start := clamp(err.span.start, 0, len(source))
	end   := clamp(err.span.end,   start, len(source))

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
