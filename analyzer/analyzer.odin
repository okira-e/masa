package analyzer

import "../syntax"
import "core:fmt"
import "core:strings"

// nocheckin: Check the context.allocator allocations
Analyzer :: struct {
	source: string,
	env:    ^Scope,

	t_number: ^Symbol,
	t_string: ^Symbol,
	t_bool:   ^Symbol,
	t_any:    ^Symbol,

	// A stack representing if we're inside a function and what it should return
	fn_contexts: [dynamic]Fn_Context,
}

Fn_Context :: struct {
	return_types: []Type,
	async:        bool,
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
	a.fn_contexts = make([dynamic]Fn_Context)
}

destroy :: proc(a: ^Analyzer) {
	assert(len(a.fn_contexts) == 0)
	delete(a.fn_contexts)

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

inside_function :: proc(a: ^Analyzer) -> bool {
	return len(a.fn_contexts) > 0
}

current_fn_context :: proc(a: ^Analyzer) -> Fn_Context {
	assert(inside_function(a))
	return a.fn_contexts[len(a.fn_contexts) - 1]
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
		if !inside_function(a) {
			return analyzer_error(.Return_Outside_Function, stmt.keyword.span)
		}

		return check_return_stmt(a, stmt)
	}

	return analyzer_error(
		.Illegal_Statement,
		syntax.span_of_stmt(stmt),
		Illegal_Context_Error_Data{ctx = .Statement},
	)
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
			is_type_alias_decl := len(val) == len(stmt.names)
			if is_type_alias_decl {
				for value in val {
					rhs, is_ident := value.(^syntax.Ident_Expr)
					if !is_ident {
						is_type_alias_decl = false
						break
					}

					lexeme := a.source[rhs.token.span.start:rhs.token.span.end]
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
					name := a.source[name_tok.span.start:name_tok.span.end]
					if _, dup := a.env.symbols[name]; dup {
						return analyzer_error(
							.Variable_Redeclaration,
							name_tok.span,
							Name_Error_Data{role = .Value},
						)
					}
				}

				for name_tok, i in stmt.names {
					rhs := val[i].(^syntax.Ident_Expr)
					lexeme := a.source[rhs.token.span.start:rhs.token.span.end]
					sym, found := resolve_ident(a, lexeme)
					assert(found)

					name := a.source[name_tok.span.start:name_tok.span.end]
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
		t, err := resolve_type(a, type)
		if err != nil do return err
		declared_type = t
	}

	checked_values: [dynamic]Checked_Value
	if stmt_values, has := stmt.value.?; has {
		values, err := check_expr_list(a, stmt_values[:])
		if err != nil do return err
		checked_values = values

		if len(checked_values) != len(stmt.names) {
			return analyzer_error(
				.Target_Value_Count_Mismatch,
				stmt.span,
				Count_Error_Data{expected = len(stmt.names), actual = len(checked_values)},
			)
		}

		if declared_type, ok := declared_type.?; ok {
			for value, i in checked_values {
				if value.type == nil do continue

				match, match_err := type_eq(declared_type, value.type)
				if match_err != nil do return match_err

				if !match {
					return analyzer_error(
						.Type_Mismatch_On_Declaration,
						value.span,
						Indexed_Error_Data{index = i},
					)
				}
			}
		}
	}

	if declared_type == nil && len(checked_values) == 0 {
		first_name := stmt.names[0]
		last_name  := stmt.names[len(stmt.names) - 1]
		return analyzer_error(
			.Declaration_Type_Missing,
			syntax.span_join(first_name.span, last_name.span),
		)
	}

	for name_token, i in stmt.names {
		name := a.source[name_token.span.start:name_token.span.end]

		// Since shadowing is allowed, check only the current scope for duplicates
		if _, dup := a.env.symbols[name]; dup {
			return analyzer_error(
				.Variable_Redeclaration,
				name_token.span,
				Name_Error_Data{role = .Variable},
			)
		}

		final_type: Type
		if declared_type, ok := declared_type.?; ok {
			final_type = declared_type
		} else {
			assert(len(checked_values) == len(stmt.names))
			final_type = checked_values[i].type
			if final_type == nil {
				return analyzer_error(.Declaration_Type_Missing, name_token.span)
			}
		}

		sym := new_symbol(
			Var_Symbol{constant = stmt.constant, decl_token = name_token, type = final_type},
		)

		stmt.decl_kind = .Value // As opposed to a type alias

		append(&a.env.owned_symbols, sym)
		a.env.symbols[name] = sym
	}

	return nil
}

check_fn_decl_stmt :: proc(a: ^Analyzer, stmt: ^syntax.Fn_Decl_Stmt) -> Maybe(Analyzer_Error) {

	// Type check
	if declared_type, ok := stmt.type.?; ok {
		declared_fn_type, is_fn_type := declared_type.variant.(syntax.Fn_Type)
		if !is_fn_type {
			return analyzer_error(
				.Fn_Declaration_Signature_Mismatch,
				declared_type.span,
				Fn_Declaration_Signature_Error_Data{reason = .Declared_Type},
			)
		}
		signature_span := stmt.lit.span
		if block, has_block := stmt.lit.block.?; has_block {
			signature_span.end = block.span.start
		}

		if declared_fn_type.async != stmt.lit.async {
			return analyzer_error(
				.Fn_Declaration_Signature_Mismatch,
				signature_span,
				Fn_Declaration_Signature_Error_Data{reason = .Async},
			)
		}

		if len(declared_fn_type.params) != len(stmt.lit.args) {
			return analyzer_error(
				.Fn_Declaration_Signature_Mismatch,
				signature_span,
				Fn_Declaration_Signature_Error_Data {
					reason   = .Parameter_Count,
					expected = len(declared_fn_type.params),
					actual   = len(stmt.lit.args),
				},
			)
		}

		for param, i in declared_fn_type.params {
			param_t, err1 := resolve_type(a, param)
			if err1 != nil do return err1
			arg_t, err2 := resolve_type(a, stmt.lit.args[i].type)
			if err2 != nil do return err2

			matches, err := type_eq(param_t, arg_t)
			if err != nil do return err

			if !matches {
				return analyzer_error(
					.Fn_Declaration_Signature_Mismatch,
					stmt.lit.args[i].type.span,
					Fn_Declaration_Signature_Error_Data {
						reason = .Parameter_Type,
						index  = i,
					},
				)
			}
		}

		actual_returns: [dynamic]syntax.Type
		if returns, has_returns := stmt.lit.return_type.?; has_returns {
			actual_returns = returns
		}

		if len(declared_fn_type.returns) != len(actual_returns) {
			return analyzer_error(
				.Fn_Declaration_Signature_Mismatch,
				signature_span,
				Fn_Declaration_Signature_Error_Data {
					reason   = .Return_Count,
					expected = len(declared_fn_type.returns),
					actual   = len(actual_returns),
				},
			)
		}

		for declared_return, i in declared_fn_type.returns {
			declared_return_t, declared_err := resolve_type(a, declared_return)
			if declared_err != nil do return declared_err
			actual_return_t, actual_err := resolve_type(a, actual_returns[i])
			if actual_err != nil do return actual_err

			matches, err := type_eq(declared_return_t, actual_return_t)
			if err != nil do return err
			if !matches {
				return analyzer_error(
					.Fn_Declaration_Signature_Mismatch,
					actual_returns[i].span,
					Fn_Declaration_Signature_Error_Data {
						reason = .Return_Type,
						index  = i,
					},
				)
			}
		}
	}

	name := a.source[stmt.name.span.start:stmt.name.span.end]
	if _, exists := a.env.symbols[name]; exists {
		return analyzer_error(
			.Duplicate_Fn_Definition,
			stmt.name.span,
			Name_Error_Data{role = .Function},
		)
	}

	// We know the type is Fn_Type. We don't care.
	fn_type, err := check_fn_expr(a, &stmt.lit)
	if err != nil do return err

	sym := new_symbol(Fn_Symbol{name = name, type = fn_type, literal = stmt.lit})

	append(&a.env.owned_symbols, sym)
	a.env.symbols[name] = sym

	return nil
}

check_fn_expr :: proc(a: ^Analyzer, expr: ^syntax.Fn_Literal_Expr) -> (Fn_Type, Maybe(Analyzer_Error)) {
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
		arg_name := a.source[arg.name.span.start:arg.name.span.end]
		if seen[arg_name] {
			return {}, analyzer_error(.Duplicate_Fn_Argument_Definition, arg.name.span, Name_Error_Data{role = .Argument})
		}

		seen[arg_name] = true
		args_types[i]  = arg_type
	}

	// Create symbols out of the arguments and add them to the captured_symbols only if
	// if the block exists and this is not a stub declaration. We don't want to allocate
	// data here that we do not use or free.
	if expr.block != nil {
		for arg, i in expr.args {
			arg_name := a.source[arg.name.span.start:arg.name.span.end]
			sym := new_symbol(
				Var_Symbol {
					constant   = true,
					decl_token = arg.name,
					type       = args_types[i],
					is_arg     = true,
				},
			)

			captured_symbols[i] = Block_Capture {
				name    = arg_name,
				sym     = sym,
				mutable = false,
			}
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
	}

	declared_returns := return_types != nil ? return_types.?[:] : []Type{}
	append(&a.fn_contexts, Fn_Context {
		return_types = declared_returns,
		async        = expr.async,
	})
	defer pop(&a.fn_contexts)

	if block, ok := expr.block.?; ok {
		err := check_block_stmt(a, block, true, declared_returns, captured_symbols[:])
		if err != nil do return {}, err
	}

	// Check if the function returns
	if block, ok := expr.block.?; ok && return_types != nil && !always_terminates(a, block) {
		return {}, analyzer_error(.Missing_Return, expr.span)
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
			append(&spans, syntax.span_of_expr(returned_expr))
		}
	}

	fn_context := current_fn_context(a)
	if len(values) != len(fn_context.return_types) {
		return analyzer_error(
			.Return_Count_Mismatch,
			return_stmt.span,
			Count_Error_Data{expected = len(fn_context.return_types), actual = len(values)},
		)
	}

	for value_type, i in values {
		matches, err := type_eq(value_type, fn_context.return_types[i])
		if err != nil do return err

		if !matches {
			return analyzer_error(.Return_Type_Mismatch, spans[i], Indexed_Error_Data{index = i})
		}
	}

	return nil
}

check_fn_call :: proc(a: ^Analyzer, stmt: ^syntax.Fn_Call_Stmt) -> Maybe(Analyzer_Error) {
	name := a.source[stmt.call.name.span.start:stmt.call.name.span.end]
	sym, found := resolve_ident(a, name)
	if !found {
		return analyzer_error(
			.Undefined_Variable,
			stmt.call.name.span,
			Name_Error_Data{role = .Function},
		)
	}

	is_callable := false

	if _, ok := sym^.(Fn_Symbol); ok {
		is_callable = true
	} else if var_sym, ok := sym^.(Var_Symbol); ok {
		_, is_callable = var_sym.type.(Fn_Type)
	}

	if !is_callable {
		return analyzer_error(.Not_Callable, stmt.call.name.span)
	}

	// Return types are discarded in a call statement
	_, err := check_fn_call_expr(a, &stmt.call)
	if err != nil do return err

	return nil
}

check_ident_assignment :: proc(a: ^Analyzer, stmt: ^syntax.Ident_Assignment_Stmt) -> Maybe(Analyzer_Error) {
	if len(stmt.names) == 0 {
		return nil
	}

	values, err := check_expr_list(a, stmt.value[:])
	if err != nil do return err

	if len(values) != len(stmt.names) {
		return analyzer_error(
			.Target_Value_Count_Mismatch,
			stmt.span,
			Count_Error_Data{expected = len(stmt.names), actual = len(values)},
		)
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
			return analyzer_error(.Variable_Constant, name.span, Name_Error_Data{role = .Function})

		case Type_Symbol:
			return analyzer_error(
				.Type_In_Value_Position,
				name.span,
				Name_Error_Data{role = .Type},
			)
		}

		if var.constant {
			return analyzer_error(.Variable_Constant, name.span, Name_Error_Data{role = .Variable})
		}

		value_type := values[i].type
		if value_type == nil do continue

		match, match_err := type_eq(var.type, value_type)
		if match_err != nil do return match_err

		if !match {
			return analyzer_error(.Type_Mismatch_On_Assignment, name.span)
		}
	}

	return nil
}

Checked_Value :: struct {
	type: Type,
	span: syntax.Span,
}

check_expr_list :: proc(a: ^Analyzer, exprs: []syntax.Expr) -> ([dynamic]Checked_Value, Maybe(Analyzer_Error)) {
	values := make([dynamic]Checked_Value, allocator = context.temp_allocator)
	for expr in exprs {
		types, err := check_expr(a, expr)
		if err != nil do return values, err

		for type in types {
			append(&values, Checked_Value{type = type, span = syntax.span_of_expr(expr)})
		}
	}

	return values, nil
}

check_if_stmt :: proc(a: ^Analyzer, stmt: ^syntax.If_Stmt) -> Maybe(Analyzer_Error) {
	cond_type, err := check_single_expr(a, stmt.condition)
	if err != nil do return err
	cond_type_symbol, sure := cond_type.(^Symbol)
	if !sure {
		return analyzer_error(.Condition_Not_Bool, syntax.span_of_expr(stmt.condition))
	}

	if cond_type_symbol != a.t_bool {
		return analyzer_error(.Condition_Not_Bool, syntax.span_of_expr(stmt.condition))
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
	name:    string,
	sym:     ^Symbol,
	mutable: bool,
}

check_block_stmt :: proc(
	a:    ^Analyzer,
	stmt: ^syntax.Block_Stmt,
	// Determines if the keyword can appear at all.
	allow_return_keyword: bool,
	declared_returns:     []Type,
	captured_symbols:     []Block_Capture,
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
check_expr :: proc(a: ^Analyzer, expr: syntax.Expr) -> ([]Type, Maybe(Analyzer_Error)) {
	switch expr in expr {
	case ^syntax.Literal_Expr:
		lit_kind, ok := expr.token.literal_kind.?
		assert(ok)
		switch lit_kind {
		case .Number:
			return one_value(a.t_number), nil
		case .String:
			return one_value(a.t_string), nil
		case .Bool:
			return one_value(a.t_bool), nil
		case .Nil:
			return one_value(nil), nil
		}

	case ^syntax.Fn_Literal_Expr:
		t, err := check_fn_expr(a, expr)
		if err != nil do return nil, err
		return one_value(t), nil

	case ^syntax.Unary_Expr:
		t, err := check_unary(a, expr)
		if err != nil do return nil, err
		return one_value(t), nil

	case ^syntax.Binary_Expr:
		t, err := check_binary(a, expr)
		if err != nil do return nil, err
		return one_value(t), nil

	case ^syntax.Grouping_Expr:
		// Transparent: a group forwards the value list of its inner expression.
		return check_expr(a, expr.expr)

	case ^syntax.Ident_Expr:
		sym, err := resolve_symbol(a, expr.token)
		if err != nil do return nil, err
		// Check symbol type
		switch s in sym {
		case Var_Symbol:
			return one_value(s.type), nil

		case Fn_Symbol:
			return one_value(s.type), nil

		case Type_Symbol:
			return nil, analyzer_error(
				.Type_In_Value_Position,
				expr.token.span,
				Name_Error_Data{role = .Type},
			)
		}


	case ^syntax.Logical_Expr:
		t, err := check_logical(a, expr)
		if err != nil do return nil, err
		return one_value(t), nil

	case ^syntax.Fn_Call_Expr:
		return check_fn_call_expr(a, expr)
	}

	assert(false)
	unreachable()
}

// The value list produced by a function call: the callee's resolved return
// types (already computed at declaration time), or none for a void call.
check_fn_call_expr :: proc(a: ^Analyzer, expr: ^syntax.Fn_Call_Expr) -> ([]Type, Maybe(Analyzer_Error)) {
	name := a.source[expr.name.span.start:expr.name.span.end]
	sym, found := resolve_ident(a, name)
	if !found {
		return nil, analyzer_error(
			.Undefined_Variable,
			expr.name.span,
			Name_Error_Data{role = .Function},
		)
	}

	fn_type: Fn_Type
	switch s in sym^ {
	case Fn_Symbol:
		if s.literal.block == nil {
			return nil, analyzer_error(.Call_To_Stub, expr.name.span)
		}
		fn_type = s.type

	case Var_Symbol:
		type, callable := s.type.(Fn_Type)
		if !callable {
			return nil, analyzer_error(.Not_Callable, expr.name.span)
		}
		fn_type = type

	case Type_Symbol:
		return nil, analyzer_error(.Not_Callable, expr.name.span)
	}

	// Check arguments match the declared parameters
	if len(expr.args) != len(fn_type.args) {
		data := Count_Error_Data {
			expected = len(fn_type.args),
			actual   = len(expr.args),
		}
		return {}, analyzer_error(.Argument_Count_Mismatch, expr.name.span, data)
	}

	// check type against declared one
	for passed_arg, i in expr.args {
		arg_type, err := check_single_expr(a, passed_arg)
		if err != nil do return nil, err

		param_type := fn_type.args[i]
		assert(param_type != nil)

		matches, merr := type_eq(arg_type, param_type)
		if merr != nil do return nil, merr
		if !matches {
			return nil, analyzer_error(
				.Argument_Type_Mismatch,
				syntax.span_of_expr(passed_arg),
				Indexed_Error_Data{index = i},
			)
		}
	}

	rets, has := fn_type.return_types.?
	if !has {
		expr.return_count = 0
		return {}, nil // void call: no values
	}
	expr.return_count = len(rets)

	return rets[:], nil
}

type_from_token :: proc(a: ^Analyzer, tok: syntax.Token) -> (Type, Maybe(Analyzer_Error)) {
	#partial switch tok.kind {
	case .Literal:
		lit_kind, ok := tok.literal_kind.?
		assert(ok)
		switch lit_kind {
		case .Number:
			return a.t_number, nil
		case .String:
			return a.t_string, nil
		case .Bool:
			return a.t_bool, nil
		case .Nil:
			return nil, nil
		}

	case .Ident:
		sym, err := resolve_symbol(a, tok)
		if err != nil do return nil, err

		#partial switch s in sym {
		case Var_Symbol:
			return s.type, nil
		case Fn_Symbol:
			return s.type, nil
		}
		return nil, analyzer_error(
			.Type_In_Value_Position,
			tok.span,
			Name_Error_Data{role = .Type},
		)
	}

	return nil, analyzer_error(
		.Illegal_Statement,
		tok.span,
		Illegal_Context_Error_Data{ctx = .Call_Argument},
	)
}

check_single_expr :: proc(a: ^Analyzer, expr: syntax.Expr) -> (Type, Maybe(Analyzer_Error)) {
	types, err := check_expr(a, expr)
	if err != nil do return nil, err
	if len(types) != 1 {
		return nil, analyzer_error(
			.Multi_Value_In_Single_Context,
			syntax.span_of_expr(expr),
			Count_Error_Data{expected = 1, actual = len(types)},
		)
	}

	return types[0], nil
}

// Returns either a number symbol or a bool
check_unary :: proc(a: ^Analyzer, expr: ^syntax.Unary_Expr) -> (^Symbol, Maybe(Analyzer_Error)) {
	operand_type, err := check_single_expr(a, expr.right)
	if err != nil do return nil, err

	operand, ok := operand_type.(^Symbol)
	if !ok {
		return nil, analyzer_error(
			.Operator_Type_Mismatch,
			syntax.span_of_expr(expr.right),
			Operator_Error_Data{reason = .Unsupported_Operand, operator_span = expr.op_span},
		)
	}

	span := syntax.span_of_expr(expr.right)
	#partial switch expr.op {
	case .Minus:
		if operand != a.t_number {
			return nil, analyzer_error(
				.Operator_Type_Mismatch,
				span,
				Operator_Error_Data{reason = .Unary_Requires_Number, operator_span = expr.op_span},
			)
		}

		return a.t_number, nil

	case .Bang:
		if operand != a.t_bool {
			return nil, analyzer_error(
				.Operator_Type_Mismatch,
				span,
				Operator_Error_Data{reason = .Unary_Requires_Bool, operator_span = expr.op_span},
			)
		}

		return a.t_bool, nil
	}

	assert(false)
	unreachable()
}

check_binary :: proc(a: ^Analyzer, v: ^syntax.Binary_Expr) -> (^Symbol, Maybe(Analyzer_Error)) {
	left_type, lerr := check_single_expr(a, v.left)
	if lerr != nil do return nil, lerr

	left, ok := left_type.(^Symbol)
	if !ok {
		return nil, analyzer_error(
			.Operator_Type_Mismatch,
			syntax.span_of_expr(v.left),
			Operator_Error_Data{reason = .Left_Operand_Not_Value, operator_span = v.op_span},
		)
	}

	right_type, rerr := check_single_expr(a, v.right)
	if rerr != nil do return nil, rerr

	right, sure := right_type.(^Symbol)
	if !sure {
		return nil, analyzer_error(
			.Operator_Type_Mismatch,
			syntax.span_of_expr(v.right),
			Operator_Error_Data{reason = .Right_Operand_Not_Value, operator_span = v.op_span},
		)
	}

	span := syntax.span_of_expr(v.left)
	#partial switch v.op {
	case .Plus, .Minus, .Star, .Slash:
		if left != a.t_number || right != a.t_number {
			return nil, analyzer_error(
				.Operator_Type_Mismatch,
				span,
				Operator_Error_Data {
					reason = .Arithmetic_Requires_Numbers,
					operator_span = v.op_span,
				},
			)
		}

		return a.t_number, nil

	case .Greater, .Greater_Equal, .Less, .Less_Equal:
		if left != a.t_number || right != a.t_number {
			return nil, analyzer_error(
				.Operator_Type_Mismatch,
				span,
				Operator_Error_Data {
					reason = .Comparison_Requires_Numbers,
					operator_span = v.op_span,
				},
			)
		}

		return a.t_bool, nil

	case .Equal_Equal, .Bang_Equal:
		match, err := type_eq(left, right)
		if err != nil do return {}, err

		if !match {
			return nil, analyzer_error(
				.Operator_Type_Mismatch,
				span,
				Operator_Error_Data {
					reason = .Equality_Requires_Matching_Types,
					operator_span = v.op_span,
				},
			)
		}

		return a.t_bool, nil
	}

	assert(false)
	unreachable()
}

// Returns a bool symbol
check_logical :: proc(a: ^Analyzer, expr: ^syntax.Logical_Expr) -> (^Symbol, Maybe(Analyzer_Error)) {
	left_type, lerr := check_single_expr(a, expr.left)
	if lerr != nil do return nil, lerr

	left, ok := left_type.(^Symbol)
	if !ok {
		return nil, analyzer_error(
			.Operator_Type_Mismatch,
			syntax.span_of_expr(expr.left),
			Operator_Error_Data {
				reason        = .Logical_Left_Requires_Bool,
				operator_span = expr.op_span,
			},
		)
	}

	right_type, rerr := check_single_expr(a, expr.right)
	if rerr != nil do return nil, rerr

	right, sure := right_type.(^Symbol)
	if !sure {
		return nil, analyzer_error(
			.Operator_Type_Mismatch,
			syntax.span_of_expr(expr.right),
			Operator_Error_Data {
				reason        = .Logical_Right_Requires_Bool,
				operator_span = expr.op_span,
			},
		)
	}

	if left != a.t_bool || right != a.t_bool {
		return nil, analyzer_error(
			.Operator_Type_Mismatch,
			syntax.span_of_expr(expr.left),
			Operator_Error_Data{
				reason        = .Logical_Requires_Bools,
				operator_span = expr.op_span,
			},
		)
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
resolve_type :: proc(a: ^Analyzer, type: syntax.Type) -> (Type, Maybe(Analyzer_Error)) {
	switch v in type.variant {
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
	return nil, analyzer_error(.Undefined_Type, type.span)
}

// Resolve a name expected to refer to a type (declaration type position).
resolve_token :: proc(a: ^Analyzer, name_tok: syntax.Token) -> (^Symbol, Maybe(Analyzer_Error)) {
	name := a.source[name_tok.span.start:name_tok.span.end]
	sym, found := resolve_ident(a, name)
	if !found {
		return nil, analyzer_error(.Undefined_Type, name_tok.span, Name_Error_Data{role = .Type})
	}

	if _, is_type := sym^.(Type_Symbol); !is_type {
		return nil, analyzer_error(
			.Value_Used_As_Type,
			name_tok.span,
			Name_Error_Data{role = .Value},
		)
	}

	return sym, nil
}

// Resolve a name expected to refer to a variable (expression/assignment position).
resolve_symbol :: proc(a: ^Analyzer, name_tok: syntax.Token) -> (^Symbol, Maybe(Analyzer_Error)) {
	name := a.source[name_tok.span.start:name_tok.span.end]
	sym, found := resolve_ident(a, name)

	if !found {
		return nil, analyzer_error(
			.Undefined_Variable,
			name_tok.span,
			Name_Error_Data{role = .Variable},
		)
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

		if a.async != b.async {
			return false, nil
		}

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

	does_expr_terminate :: proc(expr: syntax.Expr) -> bool {
		#partial switch e in expr {
		case ^syntax.Fn_Call_Expr:
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
		name := a.source[s.call.name.span.start:s.call.name.span.end]
		sym, found := resolve_ident(a, name)
		if !found do return false

		fn_sym, ok := sym^.(Fn_Symbol)
		if !ok do return false

		block, has_block := fn_sym.literal.block.?
		if !has_block || len(block.stmts) == 0 do return false

		return always_terminates(a, block.stmts[len(block.stmts) - 1])

	case ^syntax.If_Stmt:
		return(
			s.else_branch != nil &&
			always_terminates(a, s.then_block) &&
			always_terminates(a, s.else_branch.?)
		)

	case ^syntax.Block_Stmt:
		// @Performance: We Require a return statement to always be present
		// in the last line of any function to improve compiler performance.
		return len(s.stmts) > 0 && always_terminates(a, s.stmts[len(s.stmts) - 1])

	case ^syntax.Return_Stmt:
		return true

	case ^syntax.Fn_Decl_Stmt:
	}

	return false // ironic
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
	s := new_symbol(Type_Symbol{name = name})
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
	kind: Analyzer_Error_Kind,
	span: syntax.Span,
	data: Maybe(Analyzer_Error_Data),
}

Analyzer_Error_Data :: struct {
	value: Analyzer_Error_Data_Value,
}

Analyzer_Error_Data_Value :: union {
	Name_Error_Data,
	Count_Error_Data,
	Indexed_Error_Data,
	Operator_Error_Data,
	Illegal_Context_Error_Data,
	Fn_Declaration_Signature_Error_Data,
}

Name_Error_Data :: struct {
	role: Name_Role,
}

Name_Role :: enum u8 {
	Variable,
	Function,
	Type,
	Argument,
	Value,
}

Count_Error_Data :: struct {
	expected: int,
	actual:   int,
}

Indexed_Error_Data :: struct {
	index: int,
}

Operator_Error_Data :: struct {
	reason:        Operator_Error_Reason,
	operator_span: syntax.Span,
}

Operator_Error_Reason :: enum u8 {
	Unsupported_Operand,
	Unary_Requires_Number,
	Unary_Requires_Bool,
	Left_Operand_Not_Value,
	Right_Operand_Not_Value,
	Arithmetic_Requires_Numbers,
	Comparison_Requires_Numbers,
	Equality_Requires_Matching_Types,
	Logical_Left_Requires_Bool,
	Logical_Right_Requires_Bool,
	Logical_Requires_Bools,
}

Illegal_Context_Error_Data :: struct {
	ctx: Illegal_Context,
}

Illegal_Context :: enum u8 {
	Statement,
	Call_Argument,
}

Fn_Declaration_Signature_Error_Data :: struct {
	reason:   Fn_Declaration_Signature_Mismatch_Reason,
	index:    int,
	expected: int,
	actual:   int,
}

Fn_Declaration_Signature_Mismatch_Reason :: enum u8 {
	Declared_Type,
	Async,
	Parameter_Count,
	Parameter_Type,
	Return_Count,
	Return_Type,
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
	Fn_Declaration_Signature_Mismatch,
	Target_Value_Count_Mismatch,
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

analyzer_error :: proc {
	analyzer_error_without_data,
	analyzer_error_with_data,
}

analyzer_error_without_data :: proc(
	kind: Analyzer_Error_Kind,
	span: syntax.Span,
) -> Analyzer_Error {
	return Analyzer_Error{kind = kind, span = span}
}

analyzer_error_with_data :: proc(
	kind: Analyzer_Error_Kind,
	span: syntax.Span,
	value: $T,
) -> Analyzer_Error {
	data := Analyzer_Error_Data {
		value = value,
	}
	return Analyzer_Error{kind = kind, span = span, data = data}
}

error_message :: proc(
	err: Analyzer_Error,
	source: string,
	allocator := context.allocator,
) -> string {
	name := source_for_span(source, err.span)

	switch err.kind {
	case .Undefined_Variable:
		data, ok := err.data.?
		assert(ok)
		name_data, is_name := data.value.(Name_Error_Data)
		assert(is_name)
		noun := name_data.role == .Function ? "function" : "variable"
		return fmt.aprintf("undefined %s '%s'", noun, name, allocator = allocator)

	case .Undefined_Type:
		if data, ok := err.data.?; ok {
			_, ok := data.value.(Name_Error_Data)
			assert(ok)
			return fmt.aprintf("undefined type '%s'", name, allocator = allocator)
		}
		return fmt.aprintf("missing type", allocator = allocator)

	case .Value_Used_As_Type:
		return fmt.aprintf("value '%s' cannot be used as a type", name, allocator = allocator)

	case .Variable_Redeclaration:
		return fmt.aprintf(
			"name '%s' is already declared in this scope",
			name,
			allocator = allocator,
		)

	case .Duplicate_Fn_Definition:
		return fmt.aprintf("function '%s' is already defined", name, allocator = allocator)

	case .Duplicate_Fn_Argument_Definition:
		return fmt.aprintf("argument '%s' is already defined", name, allocator = allocator)

	case .Variable_Constant:
		data, ok := err.data.?
		assert(ok)
		name_data, is_name := data.value.(Name_Error_Data)
		assert(is_name)
		noun := name_data.role == .Function ? "function" : "variable"
		return fmt.aprintf("cannot reassign constant %s '%s'", noun, name, allocator = allocator)

	case .Type_Mismatch_On_Assignment:
		return fmt.aprintf(
			"assigned value does not match the type of '%s'",
			name,
			allocator = allocator,
		)

	case .Type_Mismatch_On_Declaration:
		data, ok := err.data.?
		assert(ok)
		indexed_data, is_indexed := data.value.(Indexed_Error_Data)
		assert(is_indexed)
		return fmt.aprintf(
			"initializer %d does not match the declared type",
			indexed_data.index + 1,
			allocator = allocator,
		)

	case .Fn_Declaration_Signature_Mismatch:
		data, ok := err.data.?
		assert(ok)
		signature_data, is_signature := data.value.(Fn_Declaration_Signature_Error_Data)
		assert(is_signature)
		switch signature_data.reason {
		case .Declared_Type:
			return fmt.aprintf(
				"a function definition must be declared with a function type",
				allocator = allocator,
			)
		case .Async:
			return fmt.aprintf(
				"function definition's async modifier does not match its declared type",
				allocator = allocator,
			)
		case .Parameter_Count:
			return fmt.aprintf(
				"declared function type expects %d parameters, definition has %d",
				signature_data.expected,
				signature_data.actual,
				allocator = allocator,
			)
		case .Parameter_Type:
			return fmt.aprintf(
				"parameter %d does not match the declared function type",
				signature_data.index + 1,
				allocator = allocator,
			)
		case .Return_Count:
			return fmt.aprintf(
				"declared function type expects %d return values, definition has %d",
				signature_data.expected,
				signature_data.actual,
				allocator = allocator,
			)
		case .Return_Type:
			return fmt.aprintf(
				"return type %d does not match the declared function type",
				signature_data.index + 1,
				allocator = allocator,
			)
		}

	case .Declaration_Type_Missing:
		return fmt.aprintf("declaration requires a type or initial value", allocator = allocator)

	case .Type_In_Value_Position:
		return fmt.aprintf("type '%s' cannot be used as a value", name, allocator = allocator)

	case .Operator_Type_Mismatch:
		data, ok := err.data.?
		assert(ok)
		operator_data, is_operator := data.value.(Operator_Error_Data)
		assert(is_operator)
		op := source_for_span(source, operator_data.operator_span)
		switch operator_data.reason {
		case .Unsupported_Operand:
			return fmt.aprintf(
				"operator '%s' cannot be applied to this value",
				op,
				allocator = allocator,
			)
		case .Unary_Requires_Number:
			return fmt.aprintf(
				"operator '%s' requires a number operand",
				op,
				allocator = allocator,
			)
		case .Unary_Requires_Bool:
			return fmt.aprintf("operator '%s' requires a bool operand", op, allocator = allocator)
		case .Left_Operand_Not_Value:
			return fmt.aprintf(
				"left operand of '%s' is not a supported value",
				op,
				allocator = allocator,
			)
		case .Right_Operand_Not_Value:
			return fmt.aprintf(
				"right operand of '%s' is not a supported value",
				op,
				allocator = allocator,
			)
		case .Arithmetic_Requires_Numbers:
			return fmt.aprintf("operator '%s' requires number operands", op, allocator = allocator)
		case .Comparison_Requires_Numbers:
			return fmt.aprintf("operator '%s' requires number operands", op, allocator = allocator)
		case .Equality_Requires_Matching_Types:
			return fmt.aprintf(
				"operator '%s' requires operands of the same type",
				op,
				allocator = allocator,
			)
		case .Logical_Left_Requires_Bool:
			return fmt.aprintf("left operand of '%s' must be a bool", op, allocator = allocator)
		case .Logical_Right_Requires_Bool:
			return fmt.aprintf("right operand of '%s' must be a bool", op, allocator = allocator)
		case .Logical_Requires_Bools:
			return fmt.aprintf("operator '%s' requires bool operands", op, allocator = allocator)
		}

	case .Condition_Not_Bool:
		return fmt.aprintf("if condition must be a bool", allocator = allocator)

	case .Not_Callable:
		return fmt.aprintf("value '%s' is not callable", name, allocator = allocator)

	case .Call_To_Stub:
		return fmt.aprintf(
			"function '%s' has no body and cannot be called",
			name,
			allocator = allocator,
		)

	case .Argument_Count_Mismatch:
		data, ok := err.data.?
		assert(ok)
		count_data, is_count := data.value.(Count_Error_Data)
		assert(is_count)
		if count_data.expected == 1 {
			return fmt.aprintf(
				"expected 1 argument, received %d",
				count_data.actual,
				allocator = allocator,
			)
		}
		return fmt.aprintf(
			"expected %d arguments, received %d",
			count_data.expected,
			count_data.actual,
			allocator = allocator,
		)

	case .Argument_Type_Mismatch:
		data, ok := err.data.?
		assert(ok)
		indexed_data, is_indexed := data.value.(Indexed_Error_Data)
		assert(is_indexed)
		return fmt.aprintf(
			"argument %d does not match its parameter type",
			indexed_data.index + 1,
			allocator = allocator,
		)

	case .Missing_Return:
		return fmt.aprintf("function does not return a value on every path", allocator = allocator)

	case .Return_Type_Mismatch:
		data, ok := err.data.?
		assert(ok)
		indexed_data, is_indexed := data.value.(Indexed_Error_Data)
		assert(is_indexed)
		return fmt.aprintf(
			"return value %d does not match its declared type",
			indexed_data.index + 1,
			allocator = allocator,
		)

	case .Return_Count_Mismatch:
		data, ok := err.data.?
		assert(ok)
		count_data, is_count := data.value.(Count_Error_Data)
		assert(is_count)
		if count_data.expected == 1 {
			return fmt.aprintf(
				"expected 1 return value, received %d",
				count_data.actual,
				allocator = allocator,
			)
		}
		return fmt.aprintf(
			"expected %d return values, received %d",
			count_data.expected,
			count_data.actual,
			allocator = allocator,
		)

	case .Target_Value_Count_Mismatch:
		data, ok := err.data.?
		assert(ok)
		count_data, is_count := data.value.(Count_Error_Data)
		assert(is_count)
		return fmt.aprintf(
			"expected %d values for assignment targets, received %d",
			count_data.expected,
			count_data.actual,
			allocator = allocator,
		)

	case .Return_Outside_Function:
		return fmt.aprintf(
			"'return' can only appear inside a function body",
			allocator = allocator,
		)

	case .Illegal_Statement:
		data, ok := err.data.?
		assert(ok)
		context_data, is_context := data.value.(Illegal_Context_Error_Data)
		assert(is_context)
		if context_data.ctx == .Call_Argument {
			return fmt.aprintf("unsupported call argument", allocator = allocator)
		}
		return fmt.aprintf("statement is not allowed in this position", allocator = allocator)

	case .Void_In_Comparison:
		return fmt.aprintf("a call returning no value cannot be compared", allocator = allocator)

	case .Multi_Value_In_Single_Context:
		data, ok := err.data.?
		assert(ok)
		count_data, is_count := data.value.(Count_Error_Data)
		assert(is_count)
		return fmt.aprintf(
			"expected one value, expression produces %d",
			count_data.actual,
			allocator = allocator,
		)
	}

	unreachable()
}

@(private)
error_hint :: proc(err: Analyzer_Error) -> Maybe(string) {
	#partial switch err.kind {
	case .Variable_Constant:
		return "declare with ':=' instead of '::' if it needs to change"

	case .Type_Mismatch_On_Assignment:
		return "the value's type doesn't match the variable's declared type"

	case .Type_Mismatch_On_Declaration:
		return "the value's type doesn't match the declared type"

	case .Fn_Declaration_Signature_Mismatch:
		return "make the function definition's signature match its declared function type"

	case .Target_Value_Count_Mismatch:
		return "the number of values must match the number of targets"

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
		return(
			"a call returning several values can only be used in a return, declaration, or assignment" \
		)
	}

	return nil
}

@(private)
source_for_span :: proc(source: string, span: syntax.Span) -> string {
	start := clamp(span.start, 0, len(source))
	end := clamp(span.end, start, len(source))
	return source[start:end]
}

format_error :: proc(
	err: Analyzer_Error,
	source: string,
	allocator := context.allocator,
) -> string {
	start := clamp(err.span.start, 0, len(source))
	end := clamp(err.span.end, start, len(source))

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
	message := error_message(err, source, context.temp_allocator)
	hint := error_hint(err)

	b: strings.Builder
	strings.builder_init(&b, allocator)

	fmt.sbprintf(&b, "error: %s\n", message)
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
	write_source_padding(&b, source[line_start:start])
	write_repeat(&b, '^', caret_count)
	if hint != nil {
		strings.write_byte(&b, ' ')
		strings.write_string(&b, hint.?)
	}
	strings.write_byte(&b, '\n')

	return strings.to_string(b)
}

@(private)
write_source_padding :: proc(b: ^strings.Builder, source_prefix: string) {
	for i in 0 ..< len(source_prefix) {
		strings.write_byte(b, source_prefix[i] == '\t' ? '\t' : ' ')
	}
}

@(private)
write_repeat :: proc(b: ^strings.Builder, c: byte, n: int) {
	for _ in 0 ..< n do strings.write_byte(b, c)
}
