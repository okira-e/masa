package ast

import "../syntax"
import "core:strings"
import "core:testing"

@(test)
test_build_ast_from_expr_smoke :: proc(t: ^testing.T) {
	source := "1 + 2 * (3 - 4)"

	ast := &syntax.Binary_Expr {
		left  = &syntax.Literal_Expr {
			token = syntax.Token {
				kind = .Literal,
				span = {start = 0, end = 1}, // "1"
				line = 1,
				column = 1,
				literal_kind = .Number,
			},
		},
		op    = .Plus,
		right = &syntax.Binary_Expr {
			left  = &syntax.Literal_Expr {
				token = syntax.Token {
					kind = .Literal,
					span = {start = 4, end = 5}, // "2"
					line = 1,
					column = 5,
					literal_kind = .Number,
				},
			},
			op    = .Star,
			right = &syntax.Grouping_Expr {
				expr = &syntax.Binary_Expr {
					left  = &syntax.Literal_Expr {
						token = syntax.Token {
							kind = .Literal,
							span = {start = 9, end = 10}, // "3"
							line = 1,
							column = 10,
							literal_kind = .Number,
						},
					},
					op    = .Minus,
					right = &syntax.Literal_Expr {
						token = syntax.Token {
							kind = .Literal,
							span = {start = 13, end = 14}, // "4"
							line = 1,
							column = 14,
							literal_kind = .Number,
						},
					},
				},
			},
		},
	}

	builder := strings.builder_make()
	defer strings.builder_destroy(&builder)
	build_ast_from_expr(&builder, source, ast)
	out := strings.to_string(builder)

	expected := "(+ 1 (* 2 (- 3 4)))"

	if out != expected {
		testing.expectf(t, false, "smoke test failed. expected: %s. got: %s", expected, out)
		testing.fail_now(t)
	}
}

@(test)
test_ast_printer_basic :: proc(t: ^testing.T) {
	tests := []struct {
		name:     string,
		source:   string,
		input:    syntax.Expr,
		expected: string,
	} {
		{
			name     = "literal expression",
			source   = "42",
			input    = &syntax.Literal_Expr {
				token = syntax.Token {
					kind = .Literal,
					span = {start = 0, end = 2}, // "42"
					line = 1,
					column = 1,
					literal_kind = .Number,
				},
			},
			expected = "42",
		},
		{
			name     = "unary expression",
			source   = "-5",
			input    = &syntax.Unary_Expr {
				op    = .Minus,
				right = &syntax.Literal_Expr {
					token = syntax.Token {
						kind = .Literal,
						span = {start = 1, end = 2}, // "5"
						line = 1,
						column = 2,
						literal_kind = .Number,
					},
				},
			},
			expected = "(- 5)",
		},
		{
			name     = "grouping expression",
			source   = "(5)",
			input    = &syntax.Grouping_Expr {
				expr = &syntax.Literal_Expr {
					token = syntax.Token {
						kind = .Literal,
						span = {start = 1, end = 2}, // "5"
						line = 1,
						column = 2,
						literal_kind = .Number,
					},
				},
			},
			expected = "5",
		},
		{
			name     = "nested binary expression",
			source   = "1 + 2 * 3",
			input    = &syntax.Binary_Expr {
				left  = &syntax.Literal_Expr {
					token = syntax.Token {
						kind = .Literal,
						span = {start = 0, end = 1}, // "1"
						line = 1,
						column = 1,
						literal_kind = .Number,
					},
				},
				op    = .Plus,
				right = &syntax.Binary_Expr {
					left  = &syntax.Literal_Expr {
						token = syntax.Token {
							kind = .Literal,
							span = {start = 4, end = 5}, // "2"
							line = 1,
							column = 5,
							literal_kind = .Number,
						},
					},
					op    = .Star,
					right = &syntax.Literal_Expr {
						token = syntax.Token {
							kind = .Literal,
							span = {start = 8, end = 9}, // "3"
							line = 1,
							column = 9,
							literal_kind = .Number,
						},
					},
				},
			},
			expected = "(+ 1 (* 2 3))",
		},
	}

	for test in tests {
		ast := test.input

		builder := strings.builder_make()
		defer strings.builder_destroy(&builder)

		build_ast_from_expr(&builder, test.source, ast)
		out := strings.to_string(builder)

		if out != test.expected {
			testing.expectf(
				t,
				false,
				"test %s failed. expected: %s. got: %s",
				test.name,
				test.expected,
				out,
			)
			testing.fail_now(t)
		}
	}
}

@(test)
test_for_statement_ast :: proc(t: ^testing.T) {
	source := "for true {}"
	loop := &syntax.For_Stmt {
		keyword = syntax.Token{kind = .Keyword, keyword = .For, span = {start = 0, end = 3}},
		variant = syntax.Condition_For {
			condition = &syntax.Literal_Expr {
				token = syntax.Token{kind = .Literal, literal_kind = .Bool, span = {start = 4, end = 8}},
				span = {start = 4, end = 8},
			},
		},
		block = &syntax.Block_Stmt{stmts = []syntax.Stmt{}, span = {start = 9, end = 11}},
		span  = {start = 0, end = 11},
	}

	builder := strings.builder_make()
	defer strings.builder_destroy(&builder)
	build_ast_from_stmt(&builder, source, loop)
	actual := strings.to_string(builder)
	testing.expectf(t, actual == "(for true {  })", "got %q", actual)

	source = "for i := 0; i < 1; i = i + 1 {}"
	init_names := make([dynamic]syntax.Token)
	defer delete(init_names)
	append(&init_names, syntax.Token{kind = .Ident, span = {start = 4, end = 5}})
	init_values := make([dynamic]syntax.Expr)
	defer delete(init_values)
	append(&init_values, &syntax.Literal_Expr {
		token = syntax.Token{kind = .Literal, literal_kind = .Number, span = {start = 9, end = 10}},
		span = {start = 9, end = 10},
	})
	initializer := &syntax.Ident_Decl_Stmt {
		names = init_names,
		value = init_values,
		span = {start = 4, end = 10},
	}

	condition := &syntax.Binary_Expr {
		left = &syntax.Ident_Expr {
			token = syntax.Token{kind = .Ident, span = {start = 12, end = 13}},
			span = {start = 12, end = 13},
		},
		op = .Less,
		right = &syntax.Literal_Expr {
			token = syntax.Token{kind = .Literal, literal_kind = .Number, span = {start = 16, end = 17}},
			span = {start = 16, end = 17},
		},
		span = {start = 12, end = 17},
	}

	post_names := make([dynamic]syntax.Token)
	defer delete(post_names)
	append(&post_names, syntax.Token{kind = .Ident, span = {start = 19, end = 20}})
	post_values := make([dynamic]syntax.Expr)
	defer delete(post_values)
	append(&post_values, &syntax.Binary_Expr {
		left = &syntax.Ident_Expr {
			token = syntax.Token{kind = .Ident, span = {start = 23, end = 24}},
			span = {start = 23, end = 24},
		},
		op = .Plus,
		right = &syntax.Literal_Expr {
			token = syntax.Token{kind = .Literal, literal_kind = .Number, span = {start = 27, end = 28}},
			span = {start = 27, end = 28},
		},
		span = {start = 23, end = 28},
	})
	post := &syntax.Ident_Assignment_Stmt {
		names = post_names,
		values = post_values,
		span = {start = 19, end = 28},
	}
	initializer_stmt: syntax.Stmt = initializer
	post_stmt: syntax.Stmt = post

	loop = &syntax.For_Stmt {
		keyword = syntax.Token{kind = .Keyword, keyword = .For, span = {start = 0, end = 3}},
		variant = syntax.Traditional_For {
			initializer = initializer_stmt,
			condition = condition,
			post = post_stmt,
		},
		block = &syntax.Block_Stmt{stmts = []syntax.Stmt{}, span = {start = 29, end = 31}},
		span  = {start = 0, end = 31},
	}

	strings.builder_reset(&builder)
	build_ast_from_stmt(&builder, source, loop)
	actual = strings.to_string(builder)
	testing.expectf(t, actual == "(for (:= i 0); (< i 1); (= i (+ i 1)) {  })", "got %q", actual)

	source = "for val, i in 2..5 {}"
	loop = &syntax.For_Stmt {
		keyword = syntax.Token{kind = .Keyword, keyword = .For, span = {start = 0, end = 3}},
		variant = syntax.Range_For {
			capture_ident = syntax.Token{kind = .Ident, span = {start = 4, end = 7}},
			iterator = syntax.Token{kind = .Ident, span = {start = 9, end = 10}},
			range = syntax.Range {
				lower = &syntax.Literal_Expr {
					token = syntax.Token{kind = .Literal, literal_kind = .Number, span = {start = 14, end = 15}},
					span = {start = 14, end = 15},
				},
				upper = &syntax.Literal_Expr {
					token = syntax.Token{kind = .Literal, literal_kind = .Number, span = {start = 17, end = 18}},
					span = {start = 17, end = 18},
				},
			},
		},
		block = &syntax.Block_Stmt{stmts = []syntax.Stmt{}, span = {start = 19, end = 21}},
		span  = {start = 0, end = 21},
	}

	strings.builder_reset(&builder)
	build_ast_from_stmt(&builder, source, loop)
	actual = strings.to_string(builder)
	testing.expectf(t, actual == "(for val, i in 2..5 {  })", "got %q", actual)
}
