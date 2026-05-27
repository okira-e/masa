package analyzer

import "../syntax"

Analyzer :: struct {
	source: string,
	env:    map[string]Decl_Info,
}

Decl_Info :: struct {
	constant:   bool,
	decl_token: syntax.Token,
}

init :: proc(analyzer: ^Analyzer, source: string) {
	analyzer.source = source
	analyzer.env = make(map[string]Decl_Info)
}

destroy :: proc(analyzer: ^Analyzer) {
	delete(analyzer.env)
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
		if _, exists := analyzer.env[name]; exists {
			return Analyzer_Error {
				kind = .Variable_Redeclaration,
				token = stmt.name,
				message = "variable already declared",
			}
		}
		analyzer.env[name] = Decl_Info {
			constant   = stmt.mutable,
			decl_token = stmt.name,
		}

	case syntax.Ident_Assignment_Stmt:
		err := check_expr(analyzer, stmt.value)
		if err != nil do return err

		name := analyzer.source[stmt.name.lexeme_start:stmt.name.lexeme_end]
		var, exists := analyzer.env[name]
		if !exists {
			return Analyzer_Error {
				kind = .Variable_Undeclared,
				token = stmt.name,
				message = "variable not declared",
			}
		}

		if !var.constant {
			return Analyzer_Error {
				kind = .Variable_Constant,
				token = stmt.name,
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
		// No new scope yet — blocks share the enclosing env, matching the
		// interpreter's behavior. Block scope is a separate change.
		for inner in stmt.stmts {
			if err := check_stmt(analyzer, inner); err != nil do return err
		}
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
		if _, exists := analyzer.env[name]; !exists {
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

