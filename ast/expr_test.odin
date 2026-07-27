package ast

import "../syntax"
import "core:strings"
import "core:testing"

@(test)
test_build_ast_from_expr_smoke :: proc(t: ^testing.T) {
	source := "1 + 2 * (3 - 4)"

	ast := syntax.Expr {
		expr = syntax.Binary_Expr {
			left  = &syntax.Expr {
				expr = syntax.Literal_Expr {
					token = syntax.Token {
						kind         = .Literal,
						span         = {start = 0, end = 1}, // "1"
						line         = 1,
						column       = 1,
						literal_kind = .Number,
					},
				},
			},
			op    = .Plus,
			right = &syntax.Expr {
				expr = syntax.Binary_Expr {
					left  = &syntax.Expr {
						expr = syntax.Literal_Expr {
							token = syntax.Token {
								kind         = .Literal,
								span         = {start = 4, end = 5}, // "2"
								line         = 1,
								column       = 5,
								literal_kind = .Number,
							},
						},
					},
					op    = .Star,
					right = &syntax.Expr {
						expr = syntax.Grouping_Expr {
							expr = &syntax.Expr {
								expr = syntax.Binary_Expr {
									left  = &syntax.Expr {
										expr = syntax.Literal_Expr {
											token = syntax.Token {
												kind         = .Literal,
												span         = {start = 9, end = 10}, // "3"
												line         = 1,
												column       = 10,
												literal_kind = .Number,
											},
										},
									},
									op    = .Minus,
									right = &syntax.Expr {
										expr = syntax.Literal_Expr {
											token = syntax.Token {
												kind         = .Literal,
												span         = {start = 13, end = 14}, // "4"
												line         = 1,
												column       = 14,
												literal_kind = .Number,
											},
										},
									},
								},
							},
						},
					},
				},
			},
		},
	}

	builder := strings.builder_make()
	defer strings.builder_destroy(&builder)
	build_ast_from_expr(&builder, source, &ast)
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
			name = "literal expression",
			source = "42",
			input = syntax.Expr {
				expr = syntax.Literal_Expr {
					token = syntax.Token {
						kind         = .Literal,
						span         = {start = 0, end = 2}, // "42"
						line         = 1,
						column       = 1,
						literal_kind = .Number,
					},
				},
			},
			expected = "42",
		},
		{
			name = "unary expression",
			source = "-5",
			input = syntax.Expr {
				expr = syntax.Unary_Expr {
					op    = .Minus,
					right = &syntax.Expr {
						expr = syntax.Literal_Expr {
							token = syntax.Token {
								kind         = .Literal,
								span         = {start = 1, end = 2}, // "5"
								line         = 1,
								column       = 2,
								literal_kind = .Number,
							},
						},
					},
				},
			},
			expected = "(- 5)",
		},
		{
			name = "grouping expression",
			source = "(5)",
			input = syntax.Expr {
				expr = syntax.Grouping_Expr {
					expr = &syntax.Expr {
						expr = syntax.Literal_Expr {
							token = syntax.Token {
								kind         = .Literal,
								span         = {start = 1, end = 2}, // "5"
								line         = 1,
								column       = 2,
								literal_kind = .Number,
							},
						},
					},
				},
			},
			expected = "5",
		},
		{
			name = "nested binary expression",
			source = "1 + 2 * 3",
			input = syntax.Expr {
				expr = syntax.Binary_Expr {
					left  = &syntax.Expr {
						expr = syntax.Literal_Expr {
							token = syntax.Token {
								kind         = .Literal,
								span         = {start = 0, end = 1}, // "1"
								line         = 1,
								column       = 1,
								literal_kind = .Number,
							},
						},
					},
					op    = .Plus,
					right = &syntax.Expr {
						expr = syntax.Binary_Expr {
							left  = &syntax.Expr {
								expr = syntax.Literal_Expr {
									token = syntax.Token {
										kind         = .Literal,
										span         = {start = 4, end = 5}, // "2"
										line         = 1,
										column       = 5,
										literal_kind = .Number,
									},
								},
							},
							op    = .Star,
							right = &syntax.Expr {
								expr = syntax.Literal_Expr {
									token = syntax.Token {
										kind         = .Literal,
										span         = {start = 8, end = 9}, // "3"
										line         = 1,
										column       = 9,
										literal_kind = .Number,
									},
								},
							},
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

		build_ast_from_expr(&builder, test.source, &ast)
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
