package analyzer

import "../syntax"
import "core:mem"

Analyzer :: struct {
	source: string,
	env:    ^Scope,
}

Scope :: struct {
	symbols: map[string]Symbol,
	// parent being nil is the global scope
	parent:  Maybe(^Scope),
}

Symbol :: struct {
	constant: bool,
	token:    syntax.Token,
}

init :: proc(analyzer: ^Analyzer, source: string) {
	analyzer.source = source
	scope := new(Scope)
	scope^ = {
		symbols = make(map[string]Symbol), // TODO: Optimize
		parent = nil,
	}
	analyzer.env = scope
}

destroy :: proc(analyzer: ^Analyzer) {
	current_scope: Maybe(^Scope) = analyzer.env
	for current_scope != nil {
		temp := current_scope
		current_scope = temp.?.parent
		delete(temp.?.symbols)
		free(temp.?)
	}
}

analyze :: proc(analyzer: ^Analyzer, stmts: []^syntax.Stmt) -> Maybe(Analyzer_Error) {
	for stmt in stmts {
		err := check_stmt(analyzer, stmt)
		if err != nil do return err
	}

	return nil
}

check_stmt :: proc(analyzer: ^Analyzer, stmt: ^syntax.Stmt) -> Maybe(Analyzer_Error) {
	switch stmt in stmt {
	case syntax.Expr_Stmt:
		return check_expr(analyzer, stmt.expr)

	case syntax.Ident_Decl_Stmt:
		err := check_expr(analyzer, stmt.value)
		if err != nil do return err

		name := analyzer.source[stmt.name.lexeme_start:stmt.name.lexeme_end]
		if _, exists := resolve_ident(analyzer, name); exists {
			return Analyzer_Error {
				kind    = .Variable_Redeclaration,
				token   = stmt.name,
				message = "variable already declared",
			}
		}
		analyzer.env.symbols[name] = Symbol {
			constant = stmt.mutable,
			token    = stmt.name,
		}

	case syntax.Ident_Assignment_Stmt:
		err := check_expr(analyzer, stmt.value)
		if err != nil do return err

		name := analyzer.source[stmt.name.lexeme_start:stmt.name.lexeme_end]
		var, exists := resolve_ident(analyzer, name)
		if !exists {
			return Analyzer_Error {
				kind    = .Variable_Undeclared,
				token   = stmt.name,
				message = "variable not declared",
			}
		}

		if !var.constant {
			return Analyzer_Error {
				kind    = .Variable_Constant,
				token   = stmt.name,
				message = "variable is decalred as a constant and thus cannot be changed",
			}
		}

	case syntax.If_Stmt:
		if err := check_expr(analyzer, stmt.condition); err != nil do return err
		if err := check_stmt(analyzer, stmt.then_block); err != nil do return err
		if else_stmt, has_else := stmt.else_branch.?; has_else {
			if err := check_stmt(analyzer, else_stmt); err != nil do return err
		}

	case syntax.Block_Stmt:
		// Add a new scope
		new_scope := new(Scope)
		new_scope^ = {
			symbols = make(map[string]Symbol),
			parent = analyzer.env,
		}
		analyzer.env = new_scope

		for inner in stmt.stmts {
			err := check_stmt(analyzer, inner)
			if err != nil do return err
		}

		analyzer.env = new_scope.parent.?
		delete(new_scope.symbols)
		free(new_scope)
	}

	return nil
}

check_expr :: proc(analyzer: ^Analyzer, expr: ^syntax.Expr) -> Maybe(Analyzer_Error) {
	switch v in expr.expr {
	case syntax.Literal_Expr:
		return nil

	case syntax.Unary_Expr:
		return check_expr(analyzer, v.right)

	case syntax.Binary_Expr:
		err := check_expr(analyzer, v.left)
		if err != nil do return err

		return check_expr(analyzer, v.right)

	case syntax.Grouping_Expr:
		return check_expr(analyzer, v.expr)

	case syntax.Ident_Expr:
		name := analyzer.source[v.token.lexeme_start:v.token.lexeme_end]
		if _, exists := resolve_ident(analyzer, name); !exists {
			return Analyzer_Error {
				kind = .Undefined_Variable,
				token = v.token,
				message = "undefined variable",
			}
		}
		return nil

	case syntax.Logical_Expr:
		err := check_expr(analyzer, v.left)
		if err != nil do return err
		return check_expr(analyzer, v.right)
	}

	assert(false)
	unreachable()
}

// Walk from the current block scope upward to find the identifier
resolve_ident :: proc(analyzer: ^Analyzer, name: string) -> (Symbol, bool) {
	current_scope: Maybe(^Scope) = analyzer.env
	for current_scope != nil {
		val, ok := current_scope.?.symbols[name]
		if ok {
			return val, ok
		}

		current_scope = current_scope.?.parent
	}

	return Symbol{}, false
}

Analyzer_Error :: struct {
	kind:    Analyzer_Error_Kind,
	token:   syntax.Token,
	message: string,
}

Analyzer_Error_Kind :: enum {
	Undefined_Variable,
	Variable_Redeclaration,
	Variable_Undeclared,
	Variable_Constant,
}

