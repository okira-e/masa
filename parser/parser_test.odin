package parser

import "../ast"
import "../lexer"
import "../syntax"
import "core:log"
import "core:mem"
import "core:strings"
import "core:testing"

@(test)
test_basic_expressions :: proc(t: ^testing.T) {
	tests := []Test {
		Test {
			name     = "smoke",
			source   = "1 / (2 * -5) + 1 == 3 == 4",
			input    = []syntax.Token {
				make_token(.Literal, 0, 1), // 1
				make_token(.Slash, 2, 3), // /
				make_token(.Left_Paren, 4, 5), // (
				make_token(.Literal, 5, 6), // 2
				make_token(.Star, 7, 8), // *
				make_token(.Minus, 9, 10), // -
				make_token(.Literal, 10, 11), // 5
				make_token(.Right_Paren, 11, 12), // )
				make_token(.Plus, 13, 14), // +
				make_token(.Literal, 15, 16), // 1
				make_token(.Equal_Equal, 17, 19), // ==
				make_token(.Literal, 20, 21), // 3
				make_token(.Equal_Equal, 22, 24), // ==
				make_token(.Literal, 25, 26), // 4
				make_token(.EOF, 26, 27),
			},
			expected = &syntax.Binary_Expr {
				left = &syntax.Binary_Expr {
					left = &syntax.Binary_Expr {
						left = &syntax.Binary_Expr {
							left = &syntax.Literal_Expr{token = make_token(.Literal, 0, 1)},
							op = .Slash,
							right = &syntax.Grouping_Expr {
								expr = &syntax.Binary_Expr {
									left = &syntax.Literal_Expr {
										token = make_token(.Literal, 5, 6),
									},
									op = .Star,
									right = &syntax.Unary_Expr {
										op = .Minus,
										right = &syntax.Literal_Expr {
											token = make_token(.Literal, 10, 11),
										},
									},
								},
							},
						},
						op = .Plus,
						right = &syntax.Literal_Expr{token = make_token(.Literal, 15, 16)},
					},
					op = .Equal_Equal,
					right = &syntax.Literal_Expr{token = make_token(.Literal, 20, 21)},
				},
				op = .Equal_Equal,
				right = &syntax.Literal_Expr{token = make_token(.Literal, 25, 26)},
			},
		},
		Test {
			name     = "grouping overrides precedence",
			source   = "(1 + 2) * 3",
			input    = []syntax.Token {
				make_token(.Left_Paren, 0, 1), // (
				make_token(.Literal, 1, 2), // 1
				make_token(.Plus, 3, 4), // +
				make_token(.Literal, 5, 6), // 2
				make_token(.Right_Paren, 6, 7), // )
				make_token(.Star, 8, 9), // *
				make_token(.Literal, 10, 11), // 3
				make_token(.EOF, 11, 12),
			},
			expected = &syntax.Binary_Expr {
				left = &syntax.Grouping_Expr {
					expr = &syntax.Binary_Expr {
						left = &syntax.Literal_Expr{token = make_token(.Literal, 1, 2)},
						op = .Plus,
						right = &syntax.Literal_Expr{token = make_token(.Literal, 5, 6)},
					},
				},
				op = .Star,
				right = &syntax.Literal_Expr{token = make_token(.Literal, 10, 11)},
			},
		},
		Test {
			name = "binary expression",
			source = "1 == 2",
			input = []syntax.Token {
				make_token(.Literal, 0, 1),
				make_token(.Equal_Equal, 2, 4),
				make_token(.Literal, 6, 7),
				make_token(.EOF, 7, 8),
			},
			expected = &syntax.Binary_Expr {
				left = &syntax.Literal_Expr{token = make_token(.Literal, 0, 1)},
				op = .Equal_Equal,
				right = &syntax.Literal_Expr{token = make_token(.Literal, 6, 7)},
			},
		},
		Test {
			name     = "nested binary expressions",
			source   = "1 > 2 == 3",
			input    = []syntax.Token {
				make_token(.Literal, 0, 1), // 1
				make_token(.Greater, 2, 3), // >
				make_token(.Literal, 4, 5), // 2
				make_token(.Equal_Equal, 6, 8), // ==
				make_token(.Literal, 9, 10), // 3
				make_token(.EOF, 10, 11),
			},
			expected = &syntax.Binary_Expr {
				left = &syntax.Binary_Expr {
					left = &syntax.Literal_Expr{token = make_token(.Literal, 0, 1)},
					op = .Greater,
					right = &syntax.Literal_Expr{token = make_token(.Literal, 4, 5)},
				},
				op = .Equal_Equal,
				right = &syntax.Literal_Expr{token = make_token(.Literal, 9, 10)},
			},
		},
		Test {
			name     = "term addition",
			source   = "1 + 2",
			input    = []syntax.Token {
				make_token(.Literal, 0, 1), // 1
				make_token(.Plus, 2, 3), // +
				make_token(.Literal, 4, 5), // 2
				make_token(.EOF, 5, 6),
			},
			expected = &syntax.Binary_Expr {
				left = &syntax.Literal_Expr{token = make_token(.Literal, 0, 1)},
				op = .Plus,
				right = &syntax.Literal_Expr{token = make_token(.Literal, 4, 5)},
			},
		},
		Test {
			name     = "term subtraction",
			source   = "5 - 3",
			input    = []syntax.Token {
				make_token(.Literal, 0, 1), // 5
				make_token(.Minus, 2, 3), // -
				make_token(.Literal, 4, 5), // 3
				make_token(.EOF, 5, 6),
			},
			expected = &syntax.Binary_Expr {
				left = &syntax.Literal_Expr{token = make_token(.Literal, 0, 1)},
				op = .Minus,
				right = &syntax.Literal_Expr{token = make_token(.Literal, 4, 5)},
			},
		},
		Test {
			name     = "factor multiplication",
			source   = "2 * 3",
			input    = []syntax.Token {
				make_token(.Literal, 0, 1), // 2
				make_token(.Star, 2, 3), // *
				make_token(.Literal, 4, 5), // 3
				make_token(.EOF, 5, 6),
			},
			expected = &syntax.Binary_Expr {
				left = &syntax.Literal_Expr{token = make_token(.Literal, 0, 1)},
				op = .Star,
				right = &syntax.Literal_Expr{token = make_token(.Literal, 4, 5)},
			},
		},
		Test {
			name     = "factor division",
			source   = "10 / 2",
			input    = []syntax.Token {
				make_token(.Literal, 0, 1), // 10
				make_token(.Slash, 2, 3), // /
				make_token(.Literal, 4, 5), // 2
				make_token(.EOF, 5, 6),
			},
			expected = &syntax.Binary_Expr {
				left = &syntax.Literal_Expr{token = make_token(.Literal, 0, 1)},
				op = .Slash,
				right = &syntax.Literal_Expr{token = make_token(.Literal, 4, 5)},
			},
		},
		Test {
			name     = "unary negation",
			source   = "-5",
			input    = []syntax.Token {
				make_token(.Minus, 0, 1), // -
				make_token(.Literal, 1, 2), // 5
				make_token(.EOF, 2, 3),
			},
			expected = &syntax.Unary_Expr {
				op = .Minus,
				right = &syntax.Literal_Expr{token = make_token(.Literal, 1, 2)},
			},
		},
		Test {
			name     = "unary logical not",
			source   = "!true",
			input    = []syntax.Token {
				make_token(.Bang, 0, 1), // !
				make_token(.Literal, 1, 2), // true
				make_token(.EOF, 2, 3),
			},
			expected = &syntax.Unary_Expr {
				op = .Bang,
				right = &syntax.Literal_Expr{token = make_token(.Literal, 1, 2)},
			},
		},
		Test {
			name     = "double unary",
			source   = "--5",
			input    = []syntax.Token {
				make_token(.Minus, 0, 1), // -
				make_token(.Minus, 1, 2), // -
				make_token(.Literal, 2, 3), // 5
				make_token(.EOF, 3, 4),
			},
			expected = &syntax.Unary_Expr {
				op = .Minus,
				right = &syntax.Unary_Expr {
					op = .Minus,
					right = &syntax.Literal_Expr{token = make_token(.Literal, 2, 3)},
				},
			},
		},
		Test {
			name     = "precedence: multiplication before addition",
			source   = "1 + 2 * 3",
			input    = []syntax.Token {
				make_token(.Literal, 0, 1), // 1
				make_token(.Plus, 2, 3), // +
				make_token(.Literal, 4, 5), // 2
				make_token(.Star, 6, 7), // *
				make_token(.Literal, 8, 9), // 3
				make_token(.EOF, 9, 10),
			},
			expected = &syntax.Binary_Expr {
				left = &syntax.Literal_Expr{token = make_token(.Literal, 0, 1)},
				op = .Plus,
				right = &syntax.Binary_Expr {
					left = &syntax.Literal_Expr{token = make_token(.Literal, 4, 5)},
					op = .Star,
					right = &syntax.Literal_Expr{token = make_token(.Literal, 8, 9)},
				},
			},
		},
		Test {
			name     = "precedence: division before subtraction",
			source   = "10 - 6 / 2",
			input    = []syntax.Token {
				make_token(.Literal, 0, 1), // 10
				make_token(.Minus, 2, 3), // -
				make_token(.Literal, 4, 5), // 6
				make_token(.Slash, 6, 7), // /
				make_token(.Literal, 8, 9), // 2
				make_token(.EOF, 9, 10),
			},
			expected = &syntax.Binary_Expr {
				left = &syntax.Literal_Expr{token = make_token(.Literal, 0, 1)},
				op = .Minus,
				right = &syntax.Binary_Expr {
					left = &syntax.Literal_Expr{token = make_token(.Literal, 4, 5)},
					op = .Slash,
					right = &syntax.Literal_Expr{token = make_token(.Literal, 8, 9)},
				},
			},
		},
		Test {
			name     = "precedence: unary before multiplication",
			source   = "-2 * 3",
			input    = []syntax.Token {
				make_token(.Minus, 0, 1), // -
				make_token(.Literal, 1, 2), // 2
				make_token(.Star, 3, 4), // *
				make_token(.Literal, 5, 6), // 3
				make_token(.EOF, 6, 7),
			},
			expected = &syntax.Binary_Expr {
				left = &syntax.Unary_Expr {
					op = .Minus,
					right = &syntax.Literal_Expr{token = make_token(.Literal, 1, 2)},
				},
				op = .Star,
				right = &syntax.Literal_Expr{token = make_token(.Literal, 5, 6)},
			},
		},
		Test {
			name     = "complex precedence",
			source   = "1 + 2 * 3 > 4",
			input    = []syntax.Token {
				make_token(.Literal, 0, 1), // 1
				make_token(.Plus, 2, 3), // +
				make_token(.Literal, 4, 5), // 2
				make_token(.Star, 6, 7), // *
				make_token(.Literal, 8, 9), // 3
				make_token(.Greater, 10, 11), // >
				make_token(.Literal, 12, 13), // 4
				make_token(.EOF, 13, 14),
			},
			expected = &syntax.Binary_Expr {
				left = &syntax.Binary_Expr {
					left = &syntax.Literal_Expr{token = make_token(.Literal, 0, 1)},
					op = .Plus,
					right = &syntax.Binary_Expr {
						left = &syntax.Literal_Expr{token = make_token(.Literal, 4, 5)},
						op = .Star,
						right = &syntax.Literal_Expr{token = make_token(.Literal, 8, 9)},
					},
				},
				op = .Greater,
				right = &syntax.Literal_Expr{token = make_token(.Literal, 12, 13)},
			},
		},
		// Operator chaining tests (multiple operators at same precedence level)
		Test {
			name     = "chained addition (left associative)",
			source   = "1 + 2 + 3",
			input    = []syntax.Token {
				make_token(.Literal, 0, 1), // 1
				make_token(.Plus, 2, 3), // +
				make_token(.Literal, 4, 5), // 2
				make_token(.Plus, 6, 7), // +
				make_token(.Literal, 8, 9), // 3
				make_token(.EOF, 9, 10),
			},
			expected = &syntax.Binary_Expr {
				left = &syntax.Binary_Expr {
					left = &syntax.Literal_Expr{token = make_token(.Literal, 0, 1)},
					op = .Plus,
					right = &syntax.Literal_Expr{token = make_token(.Literal, 4, 5)},
				},
				op = .Plus,
				right = &syntax.Literal_Expr{token = make_token(.Literal, 8, 9)},
			},
		},
		Test {
			name     = "chained multiplication (left associative)",
			source   = "2 * 3 * 4",
			input    = []syntax.Token {
				make_token(.Literal, 0, 1), // 2
				make_token(.Star, 2, 3), // *
				make_token(.Literal, 4, 5), // 3
				make_token(.Star, 6, 7), // *
				make_token(.Literal, 8, 9), // 4
				make_token(.EOF, 9, 10),
			},
			expected = &syntax.Binary_Expr {
				left = &syntax.Binary_Expr {
					left = &syntax.Literal_Expr{token = make_token(.Literal, 0, 1)},
					op = .Star,
					right = &syntax.Literal_Expr{token = make_token(.Literal, 4, 5)},
				},
				op = .Star,
				right = &syntax.Literal_Expr{token = make_token(.Literal, 8, 9)},
			},
		},
		Test {
			name     = "mixed addition and subtraction",
			source   = "10 + 5 - 3",
			input    = []syntax.Token {
				make_token(.Literal, 0, 1), // 10
				make_token(.Plus, 2, 3), // +
				make_token(.Literal, 4, 5), // 5
				make_token(.Minus, 6, 7), // -
				make_token(.Literal, 8, 9), // 3
				make_token(.EOF, 9, 10),
			},
			expected = &syntax.Binary_Expr {
				left = &syntax.Binary_Expr {
					left = &syntax.Literal_Expr{token = make_token(.Literal, 0, 1)},
					op = .Plus,
					right = &syntax.Literal_Expr{token = make_token(.Literal, 4, 5)},
				},
				op = .Minus,
				right = &syntax.Literal_Expr{token = make_token(.Literal, 8, 9)},
			},
		},
		Test {
			name     = "mixed multiplication and division",
			source   = "12 * 2 / 3",
			input    = []syntax.Token {
				make_token(.Literal, 0, 1), // 12
				make_token(.Star, 2, 3), // *
				make_token(.Literal, 4, 5), // 2
				make_token(.Slash, 6, 7), // /
				make_token(.Literal, 8, 9), // 3
				make_token(.EOF, 9, 10),
			},
			expected = &syntax.Binary_Expr {
				left = &syntax.Binary_Expr {
					left = &syntax.Literal_Expr{token = make_token(.Literal, 0, 1)},
					op = .Star,
					right = &syntax.Literal_Expr{token = make_token(.Literal, 4, 5)},
				},
				op = .Slash,
				right = &syntax.Literal_Expr{token = make_token(.Literal, 8, 9)},
			},
		},
		Test {
			name     = "chained equality",
			source   = "1 == 2 == 3",
			input    = []syntax.Token {
				make_token(.Literal, 0, 1), // 1
				make_token(.Equal_Equal, 2, 4), // ==
				make_token(.Literal, 5, 6), // 2
				make_token(.Equal_Equal, 7, 9), // ==
				make_token(.Literal, 10, 11), // 3
				make_token(.EOF, 11, 12),
			},
			expected = &syntax.Binary_Expr {
				left = &syntax.Binary_Expr {
					left = &syntax.Literal_Expr{token = make_token(.Literal, 0, 1)},
					op = .Equal_Equal,
					right = &syntax.Literal_Expr{token = make_token(.Literal, 5, 6)},
				},
				op = .Equal_Equal,
				right = &syntax.Literal_Expr{token = make_token(.Literal, 10, 11)},
			},
		},
		Test {
			name     = "mixed equality operators",
			source   = "1 == 2 != 3",
			input    = []syntax.Token {
				make_token(.Literal, 0, 1), // 1
				make_token(.Equal_Equal, 2, 4), // ==
				make_token(.Literal, 5, 6), // 2
				make_token(.Bang_Equal, 7, 9), // !=
				make_token(.Literal, 10, 11), // 3
				make_token(.EOF, 11, 12),
			},
			expected = &syntax.Binary_Expr {
				left = &syntax.Binary_Expr {
					left = &syntax.Literal_Expr{token = make_token(.Literal, 0, 1)},
					op = .Equal_Equal,
					right = &syntax.Literal_Expr{token = make_token(.Literal, 5, 6)},
				},
				op = .Bang_Equal,
				right = &syntax.Literal_Expr{token = make_token(.Literal, 10, 11)},
			},
		},
		Test {
			name     = "chained comparison",
			source   = "1 < 2 < 3",
			input    = []syntax.Token {
				make_token(.Literal, 0, 1), // 1
				make_token(.Less, 2, 3), // <
				make_token(.Literal, 4, 5), // 2
				make_token(.Less, 6, 7), // <
				make_token(.Literal, 8, 9), // 3
				make_token(.EOF, 9, 10),
			},
			expected = &syntax.Binary_Expr {
				left = &syntax.Binary_Expr {
					left = &syntax.Literal_Expr{token = make_token(.Literal, 0, 1)},
					op = .Less,
					right = &syntax.Literal_Expr{token = make_token(.Literal, 4, 5)},
				},
				op = .Less,
				right = &syntax.Literal_Expr{token = make_token(.Literal, 8, 9)},
			},
		},
		Test {
			name     = "long chained expression",
			source   = "1 + 2 + 3 + 4",
			input    = []syntax.Token {
				make_token(.Literal, 0, 1), // 1
				make_token(.Plus, 2, 3), // +
				make_token(.Literal, 4, 5), // 2
				make_token(.Plus, 6, 7), // +
				make_token(.Literal, 8, 9), // 3
				make_token(.Plus, 10, 11), // +
				make_token(.Literal, 12, 13), // 4
				make_token(.EOF, 13, 14),
			},
			expected = &syntax.Binary_Expr {
				left = &syntax.Binary_Expr {
					left = &syntax.Binary_Expr {
						left = &syntax.Literal_Expr{token = make_token(.Literal, 0, 1)},
						op = .Plus,
						right = &syntax.Literal_Expr{token = make_token(.Literal, 4, 5)},
					},
					op = .Plus,
					right = &syntax.Literal_Expr{token = make_token(.Literal, 8, 9)},
				},
				op = .Plus,
				right = &syntax.Literal_Expr{token = make_token(.Literal, 12, 13)},
			},
		},
		Test {
			name     = "multiple groupings with equality",
			source   = "(1 + 2 == (2 + 1))",
			input    = []syntax.Token {
				make_token(.Left_Paren, 0, 1), // (
				make_token(.Literal, 1, 2), // 1
				make_token(.Plus, 3, 4), // +
				make_token(.Literal, 5, 6), // 2
				make_token(.Equal_Equal, 7, 9), // ==
				make_token(.Left_Paren, 10, 11), // (
				make_token(.Literal, 11, 12), // 2
				make_token(.Plus, 13, 14), // +
				make_token(.Literal, 15, 16), // 1
				make_token(.Right_Paren, 16, 17), // )
				make_token(.Right_Paren, 17, 18), // )
				make_token(.EOF, 18, 19),
			},
			expected = &syntax.Grouping_Expr {
				expr = &syntax.Binary_Expr {
					left = &syntax.Binary_Expr {
						left = &syntax.Literal_Expr{token = make_token(.Literal, 1, 2)},
						op = .Plus,
						right = &syntax.Literal_Expr{token = make_token(.Literal, 5, 6)},
					},
					op = .Equal_Equal,
					right = &syntax.Grouping_Expr {
						expr = &syntax.Binary_Expr {
							left = &syntax.Literal_Expr{token = make_token(.Literal, 11, 12)},
							op = .Plus,
							right = &syntax.Literal_Expr{token = make_token(.Literal, 15, 16)},
						},
					},
				},
			},
		},
	}

	for test, i in tests {
		arena: mem.Dynamic_Arena
		mem.dynamic_arena_init(&arena)
		arena_alloc := mem.dynamic_arena_allocator(&arena)

		parser: Parser
		init(&parser, test.input, arena_alloc)
		stmts, parser_err := parse(&parser)
		defer delete(stmts)
		defer mem.dynamic_arena_destroy(&arena)

		if parser_err != nil {
			log_ast(test.source, stmts[:])
			testing.expectf(t, false, "%s: unexpected error: %v", test.name, parser_err)
			testing.fail_now(t)
		}

		if len(stmts) != 1 {
			log_ast(test.source, stmts[:])
			testing.expectf(t, false, "%s: expected 1 statement, got %d", test.name, len(stmts))
			testing.fail_now(t)
		}

		got := stmts[0].(^syntax.Expr_Stmt).expr

		expected := test.expected
		if !syntax.expr_eq(got, expected) {
			log_ast(test.source, stmts[:])
			testing.expectf(
				t,
				false,
				"%s: assertion failed.\nExpected: %v\nFound: %v",
				test.name,
				test.expected,
				got,
			)
			testing.fail_now(t)
		}
	}
}

@(test)
test_basic_expressions_errors :: proc(t: ^testing.T) {
	tests := []Test {
		Test {
			name         = "unexpected EOF",
			source       = "1 /",
			input        = []syntax.Token {
				make_token(.Literal, 0, 1), // 1
				make_token(.Slash, 2, 3), // /
				make_token(.EOF, 26, 27),
			},
			should_error = true,
			error_kind   = .Unexpected_EOF,
		},
		Test {
			name         = "unclosed parenthesis",
			source       = "(1 + 2 / ( 4",
			input        = []syntax.Token {
				make_token(.Left_Paren, 0, 1), // (
				make_token(.Literal, 1, 2), // 1
				make_token(.Plus, 3, 4), // +
				make_token(.Literal, 5, 6), // 2
				make_token(.Slash, 7, 8), // /
				make_token(.Left_Paren, 9, 10), // (
				make_token(.Literal, 11, 12), // 4
				make_token(.EOF, 12, 13),
			},
			should_error = true,
			error_kind   = .Unclosed_Paren,
		},
		Test {
			name         = "single open paren",
			source       = "(",
			input        = []syntax.Token {
				make_token(.Left_Paren, 0, 1), // (
				make_token(.EOF, 12, 13),
			},
			should_error = true,
			error_kind   = .Unexpected_EOF,
		},
		Test {
			name         = "unexpected closing parenthesis",
			source       = ") 1",
			input        = []syntax.Token {
				make_token(.Right_Paren, 0, 1), // )
				make_token(.Literal, 2, 3), // 1
				make_token(.EOF, 12, 13),
			},
			should_error = true,
			error_kind   = .Unexpected_Token,
		},
		Test {
			name         = "operator instead of an expression",
			source       = "1 == +",
			input        = []syntax.Token {
				make_token(.Literal, 0, 1), // 1
				make_token(.Equal_Equal, 2, 4), // ==
				make_token(.Plus, 5, 6), // +
				make_token(.EOF, 6, 7),
			},
			should_error = true,
			error_kind   = .Unexpected_Token,
		},
		Test {
			name         = "missing statement terminator",
			source       = "1 2",
			input        = []syntax.Token {
				make_token(.Literal, 0, 1), // 1
				make_token(.Literal, 2, 3), // 2
				make_token(.EOF, 3, 4),
			},
			should_error = true,
			error_kind   = .Missing_Terminator,
		},
		Test {
			name         = "decl: missing type after colon",
			source       = "x :",
			input        = []syntax.Token {
				make_token(.Ident, 0, 1), // x
				make_token(.Colon, 2, 3), // :
				make_token(.EOF, 3, 4),
			},
			should_error = true,
			error_kind   = .Incorrect_Type_Expr,
		},
		Test {
			name         = "decl: literal where type expected",
			source       = "x : 5",
			input        = []syntax.Token {
				make_token(.Ident, 0, 1), // x
				make_token(.Colon, 2, 3), // :
				make_token(.Literal, 4, 5), // 5
				make_token(.EOF, 5, 6),
			},
			should_error = true,
			error_kind   = .Incorrect_Type_Expr,
		},
		Test {
			name         = "decl: non-type keyword as type",
			source       = "x : if = 5",
			input        = []syntax.Token {
				make_token(.Ident, 0, 1), // x
				make_token(.Colon, 2, 3), // :
				make_token(.Keyword, 4, 6, kw = .If), // if
				make_token(.Equal, 7, 8), // =
				make_token(.Literal, 9, 10), // 5
				make_token(.EOF, 10, 11),
			},
			should_error = true,
			error_kind   = .Incorrect_Type_Expr,
		},
	}

	for test, i in tests {
		arena: mem.Dynamic_Arena
		mem.dynamic_arena_init(&arena)
		arena_alloc := mem.dynamic_arena_allocator(&arena)

		parser: Parser
		init(&parser, test.input, arena_alloc)
		stmts, parser_err := parse(&parser)
		defer delete(stmts)
		defer mem.dynamic_arena_destroy(&arena)

		// error_str := parser_error_to_string(parser_err.?, alloc = context.allocator)
		// defer delete(error_str)
		// log.infof("Error: %v", error_str)

		if test.should_error && parser_err == nil {
			testing.expectf(
				t,
				false,
				"%s: test passed when it was expected to error with: %v.",
				test.name,
				test.error_kind,
			)
			testing.fail_now(t)
		}

		if test.should_error && parser_err.?.kind != test.error_kind {
			testing.expectf(
				t,
				false,
				"%s: expected %v error. Found %v.",
				test.name,
				test.error_kind,
				parser_err.?.kind,
			)
			testing.fail_now(t)
		}
	}
}

@(test)
test_declarations :: proc(t: ^testing.T) {
	Decl_Test :: struct {
		name:      string,
		source:    string,
		input:     []syntax.Token,
		constant:  bool,
		has_type:  bool,
		type_name: string,
		has_value: bool,
	}

	tests := []Decl_Test {
		// x := 5
		Decl_Test {
			name = "untyped mutable",
			source = "x := 5",
			input = []syntax.Token {
				make_token(.Ident, 0, 1),
				make_token(.Colon_Equal, 2, 4),
				make_token(.Literal, 5, 6),
				make_token(.EOF, 6, 7),
			},
			constant = false,
			has_type = false,
			has_value = true,
		},
		// x :: 5
		Decl_Test {
			name = "untyped constant",
			source = "x :: 5",
			input = []syntax.Token {
				make_token(.Ident, 0, 1),
				make_token(.Colon_Colon, 2, 4),
				make_token(.Literal, 5, 6),
				make_token(.EOF, 6, 7),
			},
			constant = true,
			has_type = false,
			has_value = true,
		},
		// x : number = 5
		Decl_Test {
			name = "typed mutable with value",
			source = "x : number = 5",
			input = []syntax.Token {
				make_token(.Ident, 0, 1),
				make_token(.Colon, 2, 3),
				make_token(.Ident, 4, 10),
				make_token(.Equal, 11, 12),
				make_token(.Literal, 13, 14),
				make_token(.EOF, 14, 15),
			},
			constant = false,
			has_type = true,
			type_name = "number",
			has_value = true,
		},
		// x : number : 5
		Decl_Test {
			name = "typed constant with value",
			source = "x : number : 5",
			input = []syntax.Token {
				make_token(.Ident, 0, 1),
				make_token(.Colon, 2, 3),
				make_token(.Ident, 4, 10),
				make_token(.Colon, 11, 12),
				make_token(.Literal, 13, 14),
				make_token(.EOF, 14, 15),
			},
			constant = true,
			has_type = true,
			type_name = "number",
			has_value = true,
		},
		// x : number
		Decl_Test {
			name = "typed bare (no value)",
			source = "x : number",
			input = []syntax.Token {
				make_token(.Ident, 0, 1),
				make_token(.Colon, 2, 3),
				make_token(.Ident, 4, 10),
				make_token(.EOF, 10, 11),
			},
			constant = false,
			has_type = true,
			type_name = "number",
			has_value = false,
		},
		// y : bool = true
		Decl_Test {
			name = "typed mutable bool",
			source = "y : bool = true",
			input = []syntax.Token {
				make_token(.Ident, 0, 1),
				make_token(.Colon, 2, 3),
				make_token(.Ident, 4, 8),
				make_token(.Equal, 9, 10),
				make_token(.Literal, 11, 15),
				make_token(.EOF, 15, 16),
			},
			constant = false,
			has_type = true,
			type_name = "bool",
			has_value = true,
		},
		// x : string = "hi"
		Decl_Test {
			name = "typed mutable string",
			source = `x : string = "hi"`,
			input = []syntax.Token {
				make_token(.Ident, 0, 1),
				make_token(.Colon, 2, 3),
				make_token(.Ident, 4, 10),
				make_token(.Equal, 11, 12),
				make_token(.Literal, 13, 17),
				make_token(.EOF, 17, 18),
			},
			constant = false,
			has_type = true,
			type_name = "string",
			has_value = true,
		},
		// x : Foo = 5 (user-defined type identifier)
		Decl_Test {
			name = "typed mutable user-defined type",
			source = "x : Foo = 5",
			input = []syntax.Token {
				make_token(.Ident, 0, 1),
				make_token(.Colon, 2, 3),
				make_token(.Ident, 4, 7),
				make_token(.Equal, 8, 9),
				make_token(.Literal, 10, 11),
				make_token(.EOF, 11, 12),
			},
			constant = false,
			has_type = true,
			type_name = "Foo",
			has_value = true,
		},
	}

	for test in tests {
		arena: mem.Dynamic_Arena
		mem.dynamic_arena_init(&arena)
		arena_alloc := mem.dynamic_arena_allocator(&arena)
		defer mem.dynamic_arena_destroy(&arena)

		parser: Parser
		init(&parser, test.input, arena_alloc)
		stmts, parser_err := parse(&parser)
		defer delete(stmts)

		if parser_err != nil {
			testing.expectf(t, false, "%s: unexpected error: %v", test.name, parser_err)
			continue
		}
		if len(stmts) != 1 {
			testing.expectf(t, false, "%s: expected 1 stmt, got %d", test.name, len(stmts))
			continue
		}

		decl, ok := stmts[0].(^syntax.Ident_Decl_Stmt)
		if !ok {
			testing.expectf(t, false, "%s: stmt is not an Ident_Decl_Stmt", test.name)
			continue
		}

		testing.expectf(
			t,
			decl.constant == test.constant,
			"%s: constant=%v, want %v",
			test.name,
			decl.constant,
			test.constant,
		)

		decl_type, has_type := decl.type.?
		testing.expectf(
			t,
			has_type == test.has_type,
			"%s: has_type=%v, want %v",
			test.name,
			has_type,
			test.has_type,
		)
		if test.has_type {
			type_tok := decl_type.variant.(syntax.Token)
			got := test.source[type_tok.span.start:type_tok.span.end]
			testing.expectf(
				t,
				got == test.type_name,
				"%s: type lexeme=%q, want %q",
				test.name,
				got,
				test.type_name,
			)
		}

		_, value_ok := decl.value.?
		testing.expectf(
			t,
			value_ok == test.has_value,
			"%s: has_value=%v, want %v",
			test.name,
			value_ok,
			test.has_value,
		)
	}
}

@(test)
test_function_declarations :: proc(t: ^testing.T) {
	Fn_Decl_Test :: struct {
		name:              string,
		source:            string,
		async:             bool,
		stub:              bool,
		arg_names:         []string,
		arg_types:         []string,
		return_types:      []string,
		// The typed-constant form (`foo: fn()->T : fn()->T {}`) records a declared
		// type on the Fn_Decl_Stmt; the bare `foo :: fn` form leaves it nil.
		has_declared_type: bool,
	}

	tests := []Fn_Decl_Test {
		{name = "no arguments, no returns, with body", source = "foo :: fn() {}"},
		{
			name = "one bare return type",
			source = "foo :: fn() -> number {}",
			return_types = []string{"number"},
		},
		{
			name = "one parenthesized return type",
			source = "foo :: fn() -> (number) {}",
			return_types = []string{"number"},
		},
		{
			name = "multiple return types",
			source = "foo :: fn() -> (number, string) {}",
			return_types = []string{"number", "string"},
		},
		{
			name = "one argument",
			source = "foo :: fn(x: number) {}",
			arg_names = []string{"x"},
			arg_types = []string{"number"},
		},
		{
			name = "multiple arguments and one return",
			source = "foo :: fn(x: number, name: string) -> number {}",
			arg_names = []string{"x", "name"},
			arg_types = []string{"number", "string"},
			return_types = []string{"number"},
		},
		{
			name = "async with multiple returns",
			source = "foo :: async fn(x: number) -> (number, number) {}",
			async = true,
			arg_names = []string{"x"},
			arg_types = []string{"number"},
			return_types = []string{"number", "number"},
		},
		{name = "stub", source = "foo :: fn()", stub = true},
		{
			name = "typed constant fn declaration",
			source = "foo: fn() -> number : fn() -> number { return 5 }",
			return_types = []string{"number"},
			has_declared_type = true,
		},
		{
			name = "typed constant async fn declaration",
			source = "foo: async fn(number) -> number : async fn(value: number) -> number { return value }",
			async = true,
			arg_names = []string{"value"},
			arg_types = []string{"number"},
			return_types = []string{"number"},
			has_declared_type = true,
		},
	}

	for test in tests {
		arena: mem.Dynamic_Arena
		mem.dynamic_arena_init(&arena)
		arena_alloc := mem.dynamic_arena_allocator(&arena)
		defer mem.dynamic_arena_destroy(&arena)

		l: lexer.Lexer
		lexer.init(&l, arena_alloc)
		tokens, lexer_err := lexer.scan(&l, test.source)
		if lexer_err != nil {
			testing.expectf(t, false, "%s: unexpected lexer error: %v", test.name, lexer_err)
			continue
		}

		p: Parser
		init(&p, tokens[:], arena_alloc)
		stmts, parser_err := parse(&p)
		if parser_err != nil {
			testing.expectf(t, false, "%s: unexpected parser error: %v", test.name, parser_err)
			continue
		}
		if len(stmts) != 1 {
			testing.expectf(t, false, "%s: expected 1 statement, got %d", test.name, len(stmts))
			continue
		}

		decl, ok := stmts[0].(^syntax.Fn_Decl_Stmt)
		if !ok {
			testing.expectf(t, false, "%s: expected Fn_Decl_Stmt", test.name)
			continue
		}

		testing.expectf(
			t,
			token_text(test.source, decl.name) == "foo",
			"%s: wrong function name",
			test.name,
		)
		_, has_declared_type := decl.type.?
		testing.expectf(
			t,
			has_declared_type == test.has_declared_type,
			"%s: declared-type presence=%v, want %v",
			test.name,
			has_declared_type,
			test.has_declared_type,
		)
		testing.expectf(
			t,
			decl.lit.async == test.async,
			"%s: async=%v, want %v",
			test.name,
			decl.lit.async,
			test.async,
		)
		testing.expectf(
			t,
			(decl.lit.block == nil) == test.stub,
			"%s: stub=%v, want %v",
			test.name,
			decl.lit.block == nil,
			test.stub,
		)
		_, has_block := decl.lit.block.?
		testing.expectf(
			t,
			has_block == !test.stub,
			"%s: body presence does not match stub state",
			test.name,
		)

		testing.expectf(
			t,
			len(decl.lit.args) == len(test.arg_names),
			"%s: got %d args, want %d",
			test.name,
			len(decl.lit.args),
			len(test.arg_names),
		)
		for arg, i in decl.lit.args {
			if i >= len(test.arg_names) do break
			testing.expectf(
				t,
				token_text(test.source, arg.name) == test.arg_names[i],
				"%s: wrong argument %d name",
				test.name,
				i,
			)
			testing.expectf(
				t,
				token_text(test.source, arg.type.variant.(syntax.Token)) == test.arg_types[i],
				"%s: wrong argument %d type",
				test.name,
				i,
			)
		}

		returns, has_returns := decl.lit.return_type.?
		testing.expectf(
			t,
			has_returns == (len(test.return_types) > 0),
			"%s: return presence mismatch",
			test.name,
		)
		if has_returns {
			testing.expectf(
				t,
				len(returns) == len(test.return_types),
				"%s: got %d returns, want %d",
				test.name,
				len(returns),
				len(test.return_types),
			)
			for return_type, i in returns {
				if i >= len(test.return_types) do break
				testing.expectf(
					t,
					token_text(test.source, return_type.variant.(syntax.Token)) ==
					test.return_types[i],
					"%s: wrong return type %d",
					test.name,
					i,
				)
			}
		}
	}
}

@(test)
test_return_statements :: proc(t: ^testing.T) {
	// `return` followed by zero or more comma-separated value expressions.
	Return_Test :: struct {
		name:        string,
		source:      string,
		value_count: int,
	}

	tests := []Return_Test {
		{name = "bare return", source = "return", value_count = 0},
		{name = "single value", source = "return 5", value_count = 1},
		{name = "multiple values", source = "return 5, 6", value_count = 2},
		{name = "expression value", source = "return 1 + 2", value_count = 1},
	}

	for test in tests {
		arena: mem.Dynamic_Arena
		mem.dynamic_arena_init(&arena)
		arena_alloc := mem.dynamic_arena_allocator(&arena)
		defer mem.dynamic_arena_destroy(&arena)

		l: lexer.Lexer
		lexer.init(&l, arena_alloc)
		tokens, lexer_err := lexer.scan(&l, test.source)
		if lexer_err != nil {
			testing.expectf(t, false, "%s: unexpected lexer error: %v", test.name, lexer_err)
			continue
		}

		p: Parser
		init(&p, tokens[:], arena_alloc)
		stmts, parser_err := parse(&p)
		if parser_err != nil {
			testing.expectf(t, false, "%s: unexpected parser error: %v", test.name, parser_err)
			continue
		}
		if len(stmts) != 1 {
			testing.expectf(t, false, "%s: expected 1 statement, got %d", test.name, len(stmts))
			continue
		}

		ret, ok := stmts[0].(^syntax.Return_Stmt)
		if !ok {
			testing.expectf(t, false, "%s: expected Return_Stmt", test.name)
			continue
		}
		testing.expectf(
			t,
			len(ret.exprs) == test.value_count,
			"%s: got %d values, want %d",
			test.name,
			len(ret.exprs),
			test.value_count,
		)
	}
}

@(test)
test_return_inside_fn_body :: proc(t: ^testing.T) {
	// The keyword parses inside a block, so a function body holds a Return_Stmt.
	source := "foo :: fn() -> number { return 5 }"

	arena: mem.Dynamic_Arena
	mem.dynamic_arena_init(&arena)
	arena_alloc := mem.dynamic_arena_allocator(&arena)
	defer mem.dynamic_arena_destroy(&arena)

	l: lexer.Lexer
	lexer.init(&l, arena_alloc)
	tokens, lexer_err := lexer.scan(&l, source)
	if lexer_err != nil {
		testing.expectf(t, false, "unexpected lexer error: %v", lexer_err)
		return
	}

	p: Parser
	init(&p, tokens[:], arena_alloc)
	stmts, parser_err := parse(&p)
	if parser_err != nil {
		testing.expectf(t, false, "unexpected parser error: %v", parser_err)
		return
	}
	if len(stmts) != 1 {
		testing.expectf(t, false, "expected 1 statement, got %d", len(stmts))
		return
	}

	decl, ok := stmts[0].(^syntax.Fn_Decl_Stmt)
	if !ok {
		testing.expectf(t, false, "expected Fn_Decl_Stmt")
		return
	}
	blk, has_block := decl.lit.block.?
	if !has_block {
		testing.expectf(t, false, "function has no body")
		return
	}
	if len(blk.stmts) != 1 {
		testing.expectf(t, false, "expected 1 body statement, got %d", len(blk.stmts))
		return
	}
	ret, is_return := blk.stmts[0].(^syntax.Return_Stmt)
	testing.expectf(t, is_return, "body statement should be a Return_Stmt")
	if is_return {
		testing.expectf(t, len(ret.exprs) == 1, "expected 1 return value, got %d", len(ret.exprs))
	}
}

@(test)
test_expr_spans :: proc(t: ^testing.T) {
	// Each expression's span should cover its full source extent. `start`/`end` are
	// byte offsets into `source` whose slice should equal `lexeme`. When `decl` is
	// set the source is a `x := <expr>` declaration and the span of the single RHS
	// value is checked (lets us reach call/fn-literal nodes, which aren't statements).
	Span_Test :: struct {
		name:   string,
		source: string,
		lexeme: string,
		decl:   bool,
		// Which RHS value to check when `decl` is set.
		index:  int,
	}

	tests := []Span_Test {
		{name = "literal", source = "42", lexeme = "42"},
		{name = "binary chain", source = "1 + 2 * 3", lexeme = "1 + 2 * 3"},
		{name = "unary", source = "-5", lexeme = "-5"},
		{name = "grouping includes parens", source = "(1 + 2)", lexeme = "(1 + 2)"},
		{name = "logical", source = "a and b", lexeme = "a and b"},
		{name = "call with args", source = "x := foo(a, b)", lexeme = "foo(a, b)", decl = true},
		{
			name = "fn literal in list",
			source = "a, b := 1, fn(p: number) {}",
			lexeme = "fn(p: number) {}",
			decl = true,
			index = 1,
		},
	}

	for test in tests {
		arena: mem.Dynamic_Arena
		mem.dynamic_arena_init(&arena)
		arena_alloc := mem.dynamic_arena_allocator(&arena)
		defer mem.dynamic_arena_destroy(&arena)

		l: lexer.Lexer
		lexer.init(&l, arena_alloc)
		tokens, lexer_err := lexer.scan(&l, test.source)
		if lexer_err != nil {
			testing.expectf(t, false, "%s: unexpected lexer error: %v", test.name, lexer_err)
			continue
		}

		p: Parser
		init(&p, tokens[:], arena_alloc)
		stmts, parser_err := parse(&p)
		if parser_err != nil {
			testing.expectf(t, false, "%s: unexpected parser error: %v", test.name, parser_err)
			continue
		}
		if len(stmts) != 1 {
			testing.expectf(t, false, "%s: expected 1 statement, got %d", test.name, len(stmts))
			continue
		}

		expr: syntax.Expr
		if test.decl {
			decl, ok := stmts[0].(^syntax.Ident_Decl_Stmt)
			if !ok {
				testing.expectf(t, false, "%s: expected Ident_Decl_Stmt", test.name)
				continue
			}
			value, has_value := decl.value.?
			if !has_value || test.index >= len(value) {
				testing.expectf(t, false, "%s: RHS value %d missing", test.name, test.index)
				continue
			}
			expr = value[test.index]
		} else {
			expr_stmt, ok := stmts[0].(^syntax.Expr_Stmt)
			if !ok {
				testing.expectf(t, false, "%s: expected Expr_Stmt", test.name)
				continue
			}
			expr = expr_stmt.expr
		}

		span := syntax.span_of_expr(expr)
		if span.start < 0 || span.end > len(test.source) || span.start > span.end {
			testing.expectf(t, false, "%s: span out of bounds: %v", test.name, span)
			continue
		}
		got := test.source[span.start:span.end]
		testing.expectf(
			t,
			got == test.lexeme,
			"%s: span covers %q, want %q",
			test.name,
			got,
			test.lexeme,
		)
	}
}

@(test)
test_statement_spans :: proc(t: ^testing.T) {
	tests := []struct {
		name:     string,
		source:   string,
		expected: string,
	} {
		{name = "expression", source = "42\n", expected = "42"},
		{name = "untyped declaration", source = "x := 5\n", expected = "x := 5"},
		{name = "typed declaration", source = "x: number\n", expected = "x: number"},
		{name = "assignment", source = "x = 5\n", expected = "x = 5"},
		{name = "call", source = "foo(1)\n", expected = "foo(1)"},
		{name = "bare return", source = "return\n", expected = "return"},
		{name = "multi return", source = "return 1, 2\n", expected = "return 1, 2"},
		{name = "empty block", source = "{}\n", expected = "{}"},
		{name = "multiline block", source = "{\n  x := 1\n}\n", expected = "{\n  x := 1\n}"},
		{name = "if else", source = "if true {} else {}\n", expected = "if true {} else {}"},
		{name = "function stub", source = "foo :: fn()\n", expected = "foo :: fn()"},
		{
			name = "function declaration",
			source = "foo :: fn(a: number) -> number {\n  return a\n}\n",
			expected = "foo :: fn(a: number) -> number {\n  return a\n}",
		},
	}

	for test in tests {
		arena: mem.Dynamic_Arena
		mem.dynamic_arena_init(&arena)
		arena_alloc := mem.dynamic_arena_allocator(&arena)
		defer mem.dynamic_arena_destroy(&arena)

		l: lexer.Lexer
		lexer.init(&l, arena_alloc)
		tokens, lexer_err := lexer.scan(&l, test.source)
		if lexer_err != nil {
			testing.expectf(t, false, "%s: unexpected lexer error: %v", test.name, lexer_err)
			continue
		}

		p: Parser
		init(&p, tokens[:], arena_alloc)
		stmts, parser_err := parse(&p)
		if parser_err != nil {
			testing.expectf(t, false, "%s: unexpected parser error: %v", test.name, parser_err)
			continue
		}
		if len(stmts) != 1 {
			testing.expectf(t, false, "%s: expected 1 statement, got %d", test.name, len(stmts))
			continue
		}

		expect_span_text(t, test.source, syntax.span_of_stmt(stmts[0]), test.expected, test.name)
	}
}

@(test)
test_statement_component_spans :: proc(t: ^testing.T) {
	source := "x := foo(1)\nx = 2\nif true {}\n"

	arena: mem.Dynamic_Arena
	mem.dynamic_arena_init(&arena)
	arena_alloc := mem.dynamic_arena_allocator(&arena)
	defer mem.dynamic_arena_destroy(&arena)

	l: lexer.Lexer
	lexer.init(&l, arena_alloc)
	tokens, lexer_err := lexer.scan(&l, source)
	testing.expectf(t, lexer_err == nil, "unexpected lexer error: %v", lexer_err)
	if lexer_err != nil do return

	p: Parser
	init(&p, tokens[:], arena_alloc)
	stmts, parser_err := parse(&p)
	testing.expectf(t, parser_err == nil, "unexpected parser error: %v", parser_err)
	if parser_err != nil do return
	testing.expectf(t, len(stmts) == 3, "expected 3 statements, got %d", len(stmts))
	if len(stmts) != 3 do return

	decl, is_decl := stmts[0].(^syntax.Ident_Decl_Stmt)
	testing.expect(t, is_decl, "expected declaration")
	if is_decl {
		expect_span_text(t, source, decl.op.span, ":=", "declaration operator")
		values, has_value := decl.value.?
		if has_value && len(values) == 1 {
			call, is_call := values[0].(^syntax.Fn_Call_Expr)
			testing.expect(t, is_call, "expected call expression")
			if is_call {
				expect_span_text(t, source, call.span, "foo(1)", "call expression")
			}
		}
	}

	assignment, is_assignment := stmts[1].(^syntax.Ident_Assignment_Stmt)
	testing.expect(t, is_assignment, "expected assignment")
	if is_assignment {
		expect_span_text(t, source, assignment.op.span, "=", "assignment operator")
	}

	if_stmt, is_if := stmts[2].(^syntax.If_Stmt)
	testing.expect(t, is_if, "expected if statement")
	if is_if {
		expect_span_text(t, source, if_stmt.keyword.span, "if", "if keyword")
	}
}

@(test)
test_nested_node_spans :: proc(t: ^testing.T) {
	source := "foo :: async fn(cb: fn(number) -> string) -> number {\n  return 1\n}"

	arena: mem.Dynamic_Arena
	mem.dynamic_arena_init(&arena)
	arena_alloc := mem.dynamic_arena_allocator(&arena)
	defer mem.dynamic_arena_destroy(&arena)

	l: lexer.Lexer
	lexer.init(&l, arena_alloc)
	tokens, lexer_err := lexer.scan(&l, source)
	testing.expectf(t, lexer_err == nil, "unexpected lexer error: %v", lexer_err)
	if lexer_err != nil do return

	p: Parser
	init(&p, tokens[:], arena_alloc)
	stmts, parser_err := parse(&p)
	testing.expectf(t, parser_err == nil, "unexpected parser error: %v", parser_err)
	if parser_err != nil || len(stmts) != 1 do return

	decl, ok := stmts[0].(^syntax.Fn_Decl_Stmt)
	testing.expect(t, ok, "expected Fn_Decl_Stmt")
	if !ok do return

	expect_span_text(t, source, decl.span, source, "function declaration")
	expect_span_text(
		t,
		source,
		decl.lit.span,
		"async fn(cb: fn(number) -> string) -> number {\n  return 1\n}",
		"function literal",
	)
	testing.expectf(t, len(decl.lit.args) == 1, "expected one function argument")
	if len(decl.lit.args) != 1 do return

	arg := decl.lit.args[0]
	expect_span_text(t, source, arg.span, "cb: fn(number) -> string", "function argument")
	expect_span_text(t, source, arg.type.span, "fn(number) -> string", "argument type")

	fn_type, is_fn_type := arg.type.variant.(syntax.Fn_Type)
	testing.expect(t, is_fn_type, "expected function argument type")
	if is_fn_type {
		expect_span_text(t, source, fn_type.span, "fn(number) -> string", "function type")
	}

	block, has_block := decl.lit.block.?
	testing.expect(t, has_block, "expected function body")
	if !has_block do return
	expect_span_text(t, source, block.span, "{\n  return 1\n}", "function block")
	testing.expectf(t, len(block.stmts) == 1, "expected one body statement")
	if len(block.stmts) != 1 do return

	ret, is_return := block.stmts[0].(^syntax.Return_Stmt)
	testing.expect(t, is_return, "expected return statement")
	if is_return {
		expect_span_text(t, source, ret.span, "return 1", "return statement")
		expect_span_text(t, source, ret.keyword.span, "return", "return keyword")
	}
}

@(test)
test_nested_expression_and_operator_spans :: proc(t: ^testing.T) {
	source := "1 + 2 * -3 and true"

	arena: mem.Dynamic_Arena
	mem.dynamic_arena_init(&arena)
	arena_alloc := mem.dynamic_arena_allocator(&arena)
	defer mem.dynamic_arena_destroy(&arena)

	l: lexer.Lexer
	lexer.init(&l, arena_alloc)
	tokens, lexer_err := lexer.scan(&l, source)
	testing.expectf(t, lexer_err == nil, "unexpected lexer error: %v", lexer_err)
	if lexer_err != nil do return

	p: Parser
	init(&p, tokens[:], arena_alloc)
	stmts, parser_err := parse(&p)
	testing.expectf(t, parser_err == nil, "unexpected parser error: %v", parser_err)
	if parser_err != nil || len(stmts) != 1 do return

	stmt, ok := stmts[0].(^syntax.Expr_Stmt)
	testing.expect(t, ok, "expected Expr_Stmt")
	if !ok do return
	expect_span_text(t, source, stmt.span, source, "expression statement")

	logical, is_logical := stmt.expr.(^syntax.Logical_Expr)
	testing.expect(t, is_logical, "expected Logical_Expr")
	if !is_logical do return
	expect_span_text(t, source, logical.op_span, "and", "logical operator")
	expect_span_text(t, source, syntax.span_of_expr(logical.left), "1 + 2 * -3", "logical left")
	expect_span_text(t, source, syntax.span_of_expr(logical.right), "true", "logical right")

	plus, is_plus := logical.left.(^syntax.Binary_Expr)
	testing.expect(t, is_plus, "expected addition")
	if !is_plus do return
	expect_span_text(t, source, plus.op_span, "+", "addition operator")
	expect_span_text(t, source, syntax.span_of_expr(plus.left), "1", "addition left")
	expect_span_text(t, source, syntax.span_of_expr(plus.right), "2 * -3", "addition right")

	product, is_product := plus.right.(^syntax.Binary_Expr)
	testing.expect(t, is_product, "expected multiplication")
	if !is_product do return
	expect_span_text(t, source, product.op_span, "*", "multiplication operator")

	negative, is_negative := product.right.(^syntax.Unary_Expr)
	testing.expect(t, is_negative, "expected unary expression")
	if !is_negative do return
	expect_span_text(t, source, syntax.span_of_expr(product.right), "-3", "unary expression")
	expect_span_text(t, source, negative.op_span, "-", "unary operator")
	expect_span_text(t, source, syntax.span_of_expr(negative.right), "3", "unary operand")
}

@(test)
test_function_calls :: proc(t: ^testing.T) {
	Call_Test :: struct {
		name:   string,
		source: string,
		args:   []string,
	}

	tests := []Call_Test {
		{name = "no arguments", source = "foo()"},
		{name = "one argument", source = "foo(1)", args = []string{"1"}},
		{name = "multiple arguments", source = "foo(a, b)", args = []string{"a", "b"}},
	}

	for test in tests {
		arena: mem.Dynamic_Arena
		mem.dynamic_arena_init(&arena)
		arena_alloc := mem.dynamic_arena_allocator(&arena)
		defer mem.dynamic_arena_destroy(&arena)

		l: lexer.Lexer
		lexer.init(&l, arena_alloc)
		tokens, lexer_err := lexer.scan(&l, test.source)
		if lexer_err != nil {
			testing.expectf(t, false, "%s: unexpected lexer error: %v", test.name, lexer_err)
			continue
		}

		p: Parser
		init(&p, tokens[:], arena_alloc)
		stmts, parser_err := parse(&p)
		if parser_err != nil {
			testing.expectf(t, false, "%s: unexpected parser error: %v", test.name, parser_err)
			continue
		}
		if len(stmts) != 1 {
			testing.expectf(t, false, "%s: expected 1 statement, got %d", test.name, len(stmts))
			continue
		}

		call, ok := stmts[0].(^syntax.Fn_Call_Stmt)
		if !ok {
			testing.expectf(t, false, "%s: expected Fn_Call_Stmt", test.name)
			continue
		}
		testing.expectf(
			t,
			token_text(test.source, call.call.name) == "foo",
			"%s: wrong call name",
			test.name,
		)
		testing.expectf(
			t,
			len(call.call.args) == len(test.args),
			"%s: got %d args, want %d",
			test.name,
			len(call.call.args),
			len(test.args),
		)
		for arg, i in call.call.args {
			if i >= len(test.args) do break
			testing.expectf(
				t,
				arg_text(test.source, arg) == test.args[i],
				"%s: wrong call argument %d",
				test.name,
				i,
			)
		}
	}
}

@(test)
test_function_call_single_targets :: proc(t: ^testing.T) {
	Target_Test :: struct {
		name:        string,
		source:      string,
		declaration: bool,
		constant:    bool,
	}

	tests := []Target_Test {
		{name = "mutable declaration", source = "a := foo()", declaration = true},
		{
			name = "constant declaration",
			source = "a :: foo()",
			declaration = true,
			constant = true,
		},
		{name = "assignment to existing target", source = "a = foo()"},
	}

	for test in tests {
		arena: mem.Dynamic_Arena
		mem.dynamic_arena_init(&arena)
		arena_alloc := mem.dynamic_arena_allocator(&arena)
		defer mem.dynamic_arena_destroy(&arena)

		l: lexer.Lexer
		lexer.init(&l, arena_alloc)
		tokens, lexer_err := lexer.scan(&l, test.source)
		if lexer_err != nil {
			testing.expectf(t, false, "%s: unexpected lexer error: %v", test.name, lexer_err)
			continue
		}

		p: Parser
		init(&p, tokens[:], arena_alloc)
		stmts, parser_err := parse(&p)
		if parser_err != nil {
			testing.expectf(t, false, "%s: unexpected parser error: %v", test.name, parser_err)
			continue
		}
		if len(stmts) != 1 {
			testing.expectf(t, false, "%s: expected 1 statement, got %d", test.name, len(stmts))
			continue
		}

		if test.declaration {
			decl, ok := stmts[0].(^syntax.Ident_Decl_Stmt)
			if !ok {
				testing.expectf(t, false, "%s: expected Ident_Decl_Stmt", test.name)
				continue
			}
			testing.expectf(
				t,
				len(decl.names) == 1,
				"%s: got %d targets, want 1",
				test.name,
				len(decl.names),
			)
			if len(decl.names) == 0 do continue
			testing.expectf(
				t,
				token_text(test.source, decl.names[0]) == "a",
				"%s: wrong target name",
				test.name,
			)
			testing.expectf(
				t,
				decl.constant == test.constant,
				"%s: constant=%v, want %v",
				test.name,
				decl.constant,
				test.constant,
			)
			value, has_value := decl.value.?
			if !has_value {
				testing.expectf(t, false, "%s: declaration has no function call value", test.name)
				continue
			}
			call, is_call := expect_single_call(t, test.name, value)
			if !is_call do continue
			testing.expectf(
				t,
				token_text(test.source, call.name) == "foo",
				"%s: wrong call name",
				test.name,
			)
		} else {
			assignment, ok := stmts[0].(^syntax.Ident_Assignment_Stmt)
			if !ok {
				testing.expectf(t, false, "%s: expected Ident_Assignment_Stmt", test.name)
				continue
			}
			testing.expectf(
				t,
				len(assignment.names) == 1,
				"%s: got %d targets, want 1",
				test.name,
				len(assignment.names),
			)
			if len(assignment.names) == 0 do continue
			testing.expectf(
				t,
				token_text(test.source, assignment.names[0]) == "a",
				"%s: wrong target name",
				test.name,
			)
			call, is_call := expect_single_call(t, test.name, assignment.values)
			if !is_call do continue
			testing.expectf(
				t,
				token_text(test.source, call.name) == "foo",
				"%s: wrong call name",
				test.name,
			)
		}
	}
}

@(test)
test_function_call_multiple_targets :: proc(t: ^testing.T) {
	Target_Test :: struct {
		name:        string,
		source:      string,
		declaration: bool,
		constant:    bool,
		args:        []string,
	}

	tests := []Target_Test {
		{name = "mutable declaration", source = "a, b := foo()", declaration = true},
		{
			name = "constant declaration",
			source = "a, b :: foo()",
			declaration = true,
			constant = true,
		},
		{name = "assignment to existing targets", source = "a, b = foo()"},
		{
			name = "assignment with one call argument",
			source = "a, b = foo(x)",
			args = []string{"x"},
		},
		{
			name = "assignment with multiple call arguments",
			source = "a, b = foo(x, y)",
			args = []string{"x", "y"},
		},
	}

	for test in tests {
		arena: mem.Dynamic_Arena
		mem.dynamic_arena_init(&arena)
		arena_alloc := mem.dynamic_arena_allocator(&arena)
		defer mem.dynamic_arena_destroy(&arena)

		l: lexer.Lexer
		lexer.init(&l, arena_alloc)
		tokens, lexer_err := lexer.scan(&l, test.source)
		if lexer_err != nil {
			testing.expectf(t, false, "%s: unexpected lexer error: %v", test.name, lexer_err)
			continue
		}

		p: Parser
		init(&p, tokens[:], arena_alloc)
		stmts, parser_err := parse(&p)
		if parser_err != nil {
			testing.expectf(t, false, "%s: unexpected parser error: %v", test.name, parser_err)
			continue
		}
		if len(stmts) != 1 {
			testing.expectf(t, false, "%s: expected 1 statement, got %d", test.name, len(stmts))
			continue
		}

		rhs: [dynamic]syntax.Expr
		if test.declaration {
			decl, ok := stmts[0].(^syntax.Ident_Decl_Stmt)
			if !ok {
				testing.expectf(t, false, "%s: expected Ident_Decl_Stmt", test.name)
				continue
			}
			testing.expectf(
				t,
				decl.constant == test.constant,
				"%s: constant=%v, want %v",
				test.name,
				decl.constant,
				test.constant,
			)
			expect_target_names(t, test.name, test.source, decl.names[:])
			value, has_value := decl.value.?
			if !has_value {
				testing.expectf(t, false, "%s: declaration has no value", test.name)
				continue
			}
			rhs = value
		} else {
			assignment, ok := stmts[0].(^syntax.Ident_Assignment_Stmt)
			if !ok {
				testing.expectf(t, false, "%s: expected Ident_Assignment_Stmt", test.name)
				continue
			}
			expect_target_names(t, test.name, test.source, assignment.names[:])
			rhs = assignment.values
		}

		call, ok := expect_single_call(t, test.name, rhs)
		if !ok do continue
		testing.expectf(
			t,
			token_text(test.source, call.name) == "foo",
			"%s: wrong call name",
			test.name,
		)
		testing.expectf(
			t,
			len(call.args) == len(test.args),
			"%s: got %d args, want %d",
			test.name,
			len(call.args),
			len(test.args),
		)
		for arg, i in call.args {
			if i >= len(test.args) do break
			testing.expectf(
				t,
				arg_text(test.source, arg) == test.args[i],
				"%s: wrong call argument %d",
				test.name,
				i,
			)
		}
	}
}

@(test)
test_multiple_direct_rhs_values :: proc(t: ^testing.T) {
	Rhs_Test :: struct {
		name:        string,
		source:      string,
		declaration: bool,
		constant:    bool,
	}

	tests := []Rhs_Test {
		{name = "mutable declaration", source = "a, b := 1, 2", declaration = true},
		{
			name = "constant declaration",
			source = "a, b :: 1, 2",
			declaration = true,
			constant = true,
		},
		{name = "assignment to existing targets", source = "a, b = 1, 2"},
	}

	for test in tests {
		arena: mem.Dynamic_Arena
		mem.dynamic_arena_init(&arena)
		arena_alloc := mem.dynamic_arena_allocator(&arena)
		defer mem.dynamic_arena_destroy(&arena)

		l: lexer.Lexer
		lexer.init(&l, arena_alloc)
		tokens, lexer_err := lexer.scan(&l, test.source)
		if lexer_err != nil {
			testing.expectf(t, false, "%s: unexpected lexer error: %v", test.name, lexer_err)
			continue
		}

		p: Parser
		init(&p, tokens[:], arena_alloc)
		stmts, parser_err := parse(&p)
		if parser_err != nil {
			testing.expectf(t, false, "%s: unexpected parser error: %v", test.name, parser_err)
			continue
		}
		if len(stmts) != 1 {
			testing.expectf(t, false, "%s: expected 1 statement, got %d", test.name, len(stmts))
			continue
		}

		rhs: [dynamic]syntax.Expr
		if test.declaration {
			decl, ok := stmts[0].(^syntax.Ident_Decl_Stmt)
			if !ok {
				testing.expectf(t, false, "%s: expected Ident_Decl_Stmt", test.name)
				continue
			}
			testing.expectf(
				t,
				decl.constant == test.constant,
				"%s: constant=%v, want %v",
				test.name,
				decl.constant,
				test.constant,
			)
			expect_target_names(t, test.name, test.source, decl.names[:])
			value, has_value := decl.value.?
			if !has_value {
				testing.expectf(t, false, "%s: declaration has no value", test.name)
				continue
			}
			rhs = value
		} else {
			assignment, ok := stmts[0].(^syntax.Ident_Assignment_Stmt)
			if !ok {
				testing.expectf(t, false, "%s: expected Ident_Assignment_Stmt", test.name)
				continue
			}
			expect_target_names(t, test.name, test.source, assignment.names[:])
			rhs = assignment.values
		}

		testing.expectf(t, len(rhs) == 2, "%s: got %d values, want 2", test.name, len(rhs))
	}
}

@(test)
test_multiple_call_rhs_values :: proc(t: ^testing.T) {
	// One call per target: `a, b := foo(x), foo(y)`.
	sources := []string {
		"a, b := foo(x), foo(y)",
		"a, b :: foo(x), foo(y)",
		"a, b = foo(x), foo(y)",
	}

	for source in sources {
		arena: mem.Dynamic_Arena
		mem.dynamic_arena_init(&arena)
		arena_alloc := mem.dynamic_arena_allocator(&arena)
		defer mem.dynamic_arena_destroy(&arena)

		rhs, ok := parse_single_rhs(t, source, arena_alloc)
		if !ok do continue

		testing.expectf(t, len(rhs) == 2, "%s: got %d values, want 2", source, len(rhs))
		if len(rhs) != 2 do continue

		first, first_ok := rhs[0].(^syntax.Fn_Call_Expr)
		second, second_ok := rhs[1].(^syntax.Fn_Call_Expr)
		if !first_ok || !second_ok {
			testing.expectf(t, false, "%s: both RHS values should be Call_Expr", source)
			continue
		}
		testing.expectf(
			t,
			token_text(source, first.name) == "foo" && token_text(source, second.name) == "foo",
			"%s: wrong call name",
			source,
		)
		testing.expectf(
			t,
			len(first.args) == 1 && arg_text(source, first.args[0]) == "x",
			"%s: wrong first call arg",
			source,
		)
		testing.expectf(
			t,
			len(second.args) == 1 && arg_text(source, second.args[0]) == "y",
			"%s: wrong second call arg",
			source,
		)
	}
}

@(test)
test_mixed_rhs_values :: proc(t: ^testing.T) {
	// First value is a plain expression, second is a call: `a, b := 5, foo()`.
	sources := []string{"a, b := 5, foo()", "a, b = 5, foo()"}

	for source in sources {
		arena: mem.Dynamic_Arena
		mem.dynamic_arena_init(&arena)
		arena_alloc := mem.dynamic_arena_allocator(&arena)
		defer mem.dynamic_arena_destroy(&arena)

		rhs, ok := parse_single_rhs(t, source, arena_alloc)
		if !ok do continue

		testing.expectf(t, len(rhs) == 2, "%s: got %d values, want 2", source, len(rhs))
		if len(rhs) != 2 do continue

		_, lit_ok := rhs[0].(^syntax.Literal_Expr)
		call, call_ok := rhs[1].(^syntax.Fn_Call_Expr)
		testing.expectf(t, lit_ok, "%s: first value should be a literal expr", source)
		testing.expectf(t, call_ok, "%s: second value should be a Call_Expr", source)
		if call_ok {
			testing.expectf(
				t,
				token_text(source, call.name) == "foo",
				"%s: wrong call name",
				source,
			)
		}
	}
}

@(test)
test_fn_literal_in_rhs :: proc(t: ^testing.T) {
	// A function literal can appear as a value in a multi-name *mutable* (`:=`) or
	// assignment (`=`) list. Multi-name constant (`::`) lists reject fn literals -
	// see test_multi_name_const_rejects_fn_literal.
	Lit_Test :: struct {
		name:      string,
		source:    string,
		// Index of the value expected to be a function literal.
		lit_index: int,
	}

	tests := []Lit_Test {
		{name = "literal then fn", source = "a, b := 5, fn() {}", lit_index = 1},
		{name = "fn then literal", source = "a, b := fn() {}, 5", lit_index = 0},
		{name = "async fn", source = "a, b := 5, async fn() {}", lit_index = 1},
		{name = "fn literal in multiple assignment", source = "a, b = 5, fn() {}", lit_index = 1},
	}

	for test in tests {
		arena: mem.Dynamic_Arena
		mem.dynamic_arena_init(&arena)
		arena_alloc := mem.dynamic_arena_allocator(&arena)
		defer mem.dynamic_arena_destroy(&arena)

		rhs, ok := parse_single_rhs(t, test.source, arena_alloc)
		if !ok do continue

		testing.expectf(t, len(rhs) == 2, "%s: got %d values, want 2", test.name, len(rhs))
		if len(rhs) != 2 do continue

		lit, lit_ok := rhs[test.lit_index].(^syntax.Fn_Literal_Expr)
		if !lit_ok {
			testing.expectf(
				t,
				false,
				"%s: value %d should be a Fn_Literal_Expr",
				test.name,
				test.lit_index,
			)
			continue
		}

		_, has_block := lit.block.?
		testing.expectf(t, has_block, "%s: function literal should have a body", test.name)
		testing.expectf(
			t,
			lit.async == strings.contains(test.source, "async"),
			"%s: async mismatch",
			test.name,
		)
	}
}

@(test)
test_multi_name_const_rejects_fn_literal :: proc(t: ^testing.T) {
	// Rule A: a function literal may not appear in a multi-name constant (`::`)
	// declaration - a definition must bind exactly one name. The mutable (`:=`)
	// and assignment (`=`) forms treat the literal as an ordinary value.
	Case :: struct {
		name:         string,
		source:       string,
		should_error: bool,
	}

	tests := []Case {
		{name = "literal then fn", source = "a, b :: 5, fn() {}", should_error = true},
		{name = "fn then literal", source = "a, b :: fn() {}, 5", should_error = true},
		{name = "async fn", source = "a, b :: 5, async fn() {}", should_error = true},
		{name = "three names", source = "a, b, c :: 1, fn() {}, 3", should_error = true},
		{name = "typed constant", source = "a, b : number : 5, fn() {}", should_error = true},
		{name = "mutable allows fn", source = "a, b := 5, fn() {}", should_error = false},
		{
			name = "typed mutable allows fn",
			source = "a, b : number = 5, fn() {}",
			should_error = false,
		},
		{name = "assignment allows fn", source = "a, b = 5, fn() {}", should_error = false},
	}

	for test in tests {
		arena: mem.Dynamic_Arena
		mem.dynamic_arena_init(&arena)
		arena_alloc := mem.dynamic_arena_allocator(&arena)
		defer mem.dynamic_arena_destroy(&arena)

		l: lexer.Lexer
		lexer.init(&l, arena_alloc)
		tokens, lexer_err := lexer.scan(&l, test.source)
		if lexer_err != nil {
			testing.expectf(t, false, "%s: unexpected lexer error: %v", test.name, lexer_err)
			continue
		}

		p: Parser
		init(&p, tokens[:], arena_alloc)
		_, parser_err := parse(&p)

		err, has_err := parser_err.?
		testing.expectf(
			t,
			has_err == test.should_error,
			"%s: got error=%v, want %v (err=%v)",
			test.name,
			has_err,
			test.should_error,
			parser_err,
		)
		if test.should_error && has_err {
			testing.expectf(
				t,
				err.kind == .Fn_In_Multi_Decl,
				"%s: got %v, want Fn_In_Multi_Decl",
				test.name,
				err.kind,
			)
		}
	}
}

@(test)
test_single_name_mutable_fn_is_value_binding :: proc(t: ^testing.T) {
	// A mutable single-name fn binds a *value*: an Ident_Decl_Stmt holding a
	// Fn_Literal_Expr - NOT a hoisted Fn_Decl_Stmt (that is the `::` / typed `:` form).
	// Holds for both the untyped `:=` and the typed `=` forms.
	Case :: struct {
		name:     string,
		source:   string,
		has_type: bool,
	}

	tests := []Case {
		{name = "untyped \":=\"", source = "foo := fn() {}", has_type = false},
		{
			name = "typed \"=\"",
			source = "foo: fn() -> number = fn() -> number { return 5 }",
			has_type = true,
		},
	}

	for test in tests {
		arena: mem.Dynamic_Arena
		mem.dynamic_arena_init(&arena)
		arena_alloc := mem.dynamic_arena_allocator(&arena)
		defer mem.dynamic_arena_destroy(&arena)

		l: lexer.Lexer
		lexer.init(&l, arena_alloc)
		tokens, lexer_err := lexer.scan(&l, test.source)
		if lexer_err != nil {
			testing.expectf(t, false, "%s: unexpected lexer error: %v", test.name, lexer_err)
			continue
		}

		p: Parser
		init(&p, tokens[:], arena_alloc)
		stmts, parser_err := parse(&p)
		if parser_err != nil {
			testing.expectf(t, false, "%s: unexpected parser error: %v", test.name, parser_err)
			continue
		}
		if len(stmts) != 1 {
			testing.expectf(t, false, "%s: expected 1 statement, got %d", test.name, len(stmts))
			continue
		}

		if _, is_fn_decl := stmts[0].(^syntax.Fn_Decl_Stmt); is_fn_decl {
			testing.expectf(t, false, "%s: expected Ident_Decl_Stmt, got Fn_Decl_Stmt", test.name)
			continue
		}

		decl, ok := stmts[0].(^syntax.Ident_Decl_Stmt)
		if !ok {
			testing.expectf(t, false, "%s: expected Ident_Decl_Stmt", test.name)
			continue
		}
		testing.expectf(t, !decl.constant, "%s: expected a mutable declaration", test.name)

		_, has_type := decl.type.?
		testing.expectf(
			t,
			has_type == test.has_type,
			"%s: type presence=%v, want %v",
			test.name,
			has_type,
			test.has_type,
		)

		value, has_value := decl.value.?
		if !has_value || len(value) != 1 {
			testing.expectf(t, false, "%s: expected exactly one RHS value", test.name)
			continue
		}
		_, is_lit := value[0].(^syntax.Fn_Literal_Expr)
		testing.expectf(t, is_lit, "%s: RHS value should be a Fn_Literal_Expr", test.name)
	}
}

//
// Function call arguments - parser errors
//

@(test)
test_call_argument_errors :: proc(t: ^testing.T) {
	expect_parse_error(t, "foo(1", .Unexpected_Token) // missing ')'
	expect_parse_error(t, "foo(1 2)", .Unexpected_Token) // missing ','
}

// A trailing comma in a call argument list is currently accepted (deliberate
// leniency). Encoded so a future change to reject it is a conscious decision.
@(test)
test_call_trailing_comma :: proc(t: ^testing.T) {
	expect_parse_ok(t, "foo(a,)")
}

//
// Function parameters - parser errors
//

@(test)
test_fn_param_errors :: proc(t: ^testing.T) {
	expect_parse_error(t, "foo :: fn(x) {}", .Unexpected_Token) // missing ': type'
	expect_parse_error(t, "foo :: fn(x:) {}", .Incorrect_Type_Expr) // missing type
	expect_parse_error(t, "foo :: fn(1: number) {}", .Unexpected_Token) // non-ident name
}

// Mirror of test_call_trailing_comma for the parameter list.
@(test)
test_fn_param_trailing_comma :: proc(t: ^testing.T) {
	expect_parse_ok(t, "foo :: fn(x: number,) {}")
}

// A parameter's type may itself be a function type.
@(test)
test_fn_param_function_typed :: proc(t: ^testing.T) {
	arena: mem.Dynamic_Arena
	mem.dynamic_arena_init(&arena)
	arena_alloc := mem.dynamic_arena_allocator(&arena)
	defer mem.dynamic_arena_destroy(&arena)

	source := "foo :: fn(cb: fn() -> number) {}"

	l: lexer.Lexer
	lexer.init(&l, arena_alloc)
	tokens, lexer_err := lexer.scan(&l, source)
	testing.expectf(t, lexer_err == nil, "unexpected lexer error: %v", lexer_err)

	p: Parser
	init(&p, tokens[:], arena_alloc)
	stmts, parser_err := parse(&p)
	testing.expectf(t, parser_err == nil, "unexpected parser error: %v", parser_err)
	if parser_err != nil do return
	testing.expectf(t, len(stmts) == 1, "expected 1 statement, got %d", len(stmts))
	if len(stmts) != 1 do return

	decl, ok := stmts[0].(^syntax.Fn_Decl_Stmt)
	testing.expect(t, ok, "expected Fn_Decl_Stmt")
	if !ok do return
	testing.expectf(t, len(decl.lit.args) == 1, "expected 1 param, got %d", len(decl.lit.args))
	if len(decl.lit.args) != 1 do return
	testing.expectf(t, token_text(source, decl.lit.args[0].name) == "cb", "wrong param name")
	_, is_fn := decl.lit.args[0].type.variant.(syntax.Fn_Type)
	testing.expect(t, is_fn, "param type should be a Fn_Type")
}

@(test)
test_function_type_declarations :: proc(t: ^testing.T) {
	Case :: struct {
		name:          string,
		source:        string,
		async:         bool,
		param_count:   int,
		return_count:  int,
		nested_param:  bool,
		nested_return: bool,
	}

	tests := []Case {
		{
			name = "typed variable",
			source = "callback: fn(number) -> number",
			param_count = 1,
			return_count = 1,
		},
		{
			name = "async multi parameter and return",
			source = "callback: async fn(number, string) -> (number, string)",
			async = true,
			param_count = 2,
			return_count = 2,
		},
		{
			name = "nested parameter and return",
			source = "callback: fn(fn(number) -> number) -> fn(string) -> string",
			param_count = 1,
			return_count = 1,
			nested_param = true,
			nested_return = true,
		},
	}

	for test in tests {
		arena: mem.Dynamic_Arena
		mem.dynamic_arena_init(&arena)
		arena_alloc := mem.dynamic_arena_allocator(&arena)
		defer mem.dynamic_arena_destroy(&arena)

		l: lexer.Lexer
		lexer.init(&l, arena_alloc)
		tokens, lexer_err := lexer.scan(&l, test.source)
		if lexer_err != nil {
			testing.expectf(t, false, "%s: unexpected lexer error: %v", test.name, lexer_err)
			continue
		}

		p: Parser
		init(&p, tokens[:], arena_alloc)
		stmts, parser_err := parse(&p)
		if parser_err != nil {
			testing.expectf(t, false, "%s: unexpected parser error: %v", test.name, parser_err)
			continue
		}
		if len(stmts) != 1 {
			testing.expectf(t, false, "%s: expected 1 statement, got %d", test.name, len(stmts))
			continue
		}

		decl, ok := stmts[0].(^syntax.Ident_Decl_Stmt)
		if !ok {
			testing.expectf(t, false, "%s: expected Ident_Decl_Stmt", test.name)
			continue
		}

		decl_type, has_type := decl.type.?
		if !has_type {
			testing.expectf(t, false, "%s: declaration has no type", test.name)
			continue
		}

		fn_type, is_fn := decl_type.variant.(syntax.Fn_Type)
		if !is_fn {
			testing.expectf(t, false, "%s: declaration type should be Fn_Type", test.name)
			continue
		}

		testing.expectf(
			t,
			fn_type.async == test.async,
			"%s: async=%v, want %v",
			test.name,
			fn_type.async,
			test.async,
		)
		testing.expectf(
			t,
			len(fn_type.params) == test.param_count,
			"%s: got %d params, want %d",
			test.name,
			len(fn_type.params),
			test.param_count,
		)
		testing.expectf(
			t,
			len(fn_type.returns) == test.return_count,
			"%s: got %d returns, want %d",
			test.name,
			len(fn_type.returns),
			test.return_count,
		)

		if test.nested_param && len(fn_type.params) > 0 {
			_, nested := fn_type.params[0].variant.(syntax.Fn_Type)
			testing.expectf(t, nested, "%s: first parameter should be a function type", test.name)
		}
		if test.nested_return && len(fn_type.returns) > 0 {
			_, nested := fn_type.returns[0].variant.(syntax.Fn_Type)
			testing.expectf(t, nested, "%s: first return should be a function type", test.name)
		}
	}
}

@(test)
test_function_literal_returns_function_type :: proc(t: ^testing.T) {
	source := "make_identity :: fn() -> fn(number) -> number { return fn(value: number) -> number { return value } }"

	arena: mem.Dynamic_Arena
	mem.dynamic_arena_init(&arena)
	arena_alloc := mem.dynamic_arena_allocator(&arena)
	defer mem.dynamic_arena_destroy(&arena)

	l: lexer.Lexer
	lexer.init(&l, arena_alloc)
	tokens, lexer_err := lexer.scan(&l, source)
	testing.expectf(t, lexer_err == nil, "unexpected lexer error: %v", lexer_err)
	if lexer_err != nil do return

	p: Parser
	init(&p, tokens[:], arena_alloc)
	stmts, parser_err := parse(&p)
	testing.expectf(t, parser_err == nil, "unexpected parser error: %v", parser_err)
	if parser_err != nil || len(stmts) != 1 do return

	decl, ok := stmts[0].(^syntax.Fn_Decl_Stmt)
	testing.expect(t, ok, "expected Fn_Decl_Stmt")
	if !ok do return

	returns, has_returns := decl.lit.return_type.?
	testing.expect(t, has_returns, "function should have a return type")
	if !has_returns || len(returns) != 1 do return

	fn_type, is_fn := returns[0].variant.(syntax.Fn_Type)
	testing.expect(t, is_fn, "return type should be Fn_Type")
	if !is_fn do return
	testing.expectf(
		t,
		len(fn_type.params) == 1,
		"got %d nested params, want 1",
		len(fn_type.params),
	)
	testing.expectf(
		t,
		len(fn_type.returns) == 1,
		"got %d nested returns, want 1",
		len(fn_type.returns),
	)
}

@(test)
test_function_type_trailing_commas :: proc(t: ^testing.T) {
	expect_parse_ok(t, "callback: fn(number,)")
	expect_parse_ok(t, "callback: fn() -> (number, string,)")
	expect_parse_ok(t, "foo :: fn() -> (number, string,) { return 1, \"ok\" }")
}

@(test)
test_function_type_errors :: proc(t: ^testing.T) {
	expect_parse_error(t, "callback: fn(", .Incorrect_Type_Expr)
	expect_parse_error(t, "callback: fn(number", .Unexpected_Token)
	expect_parse_error(t, "callback: fn() ->", .Incorrect_Type_Expr)
	expect_parse_error(t, "callback: fn() -> (number", .Unexpected_Token)
	expect_parse_error(t, "foo :: fn() ->", .Incorrect_Type_Expr)
}

// @(test) Don't know if we should disallow with because of interop
// test_bodyless_function_values_are_rejected :: proc(t: ^testing.T) {
// 	// A missing body denotes a signature-only named declaration. A function value
// 	// must have a runtime value, so the same syntax is invalid on a value RHS.
// 	expect_parse_error(t, "callback := fn()",       .Unexpected_Token)
// 	expect_parse_error(t, "callback := async fn()", .Unexpected_Token)
// 	expect_parse_error(t, "callback: fn() = fn()",  .Unexpected_Token)
// }

@(test)
test_declaration_and_return_list_errors :: proc(t: ^testing.T) {
	expect_parse_error(t, "a, := 1", .Unexpected_Token)
	expect_parse_error(t, "a, b 1", .Unexpected_Token)
	expect_parse_error(t, "a, b :=", .Unexpected_EOF)
	expect_parse_error(t, "a, b := 1,", .Unexpected_EOF)
	expect_parse_error(t, "return 1,", .Unexpected_EOF)
}

@(test)
test_call_expression_arguments :: proc(t: ^testing.T) {
	expect_parse_ok(t, "foo(1 + 2)") // arithmetic argument
	expect_parse_ok(t, "foo(bar(1))") // nested call argument (statement position)
	expect_parse_ok(t, "x := id(id(1))") // nested call argument (expression position)
}

// Parses a single decl/assignment statement and returns its RHS expression list.
@(private = "file")
parse_single_rhs :: proc(
	t: ^testing.T,
	source: string,
	alloc: mem.Allocator,
) -> (
	[dynamic]syntax.Expr,
	bool,
) {
	l: lexer.Lexer
	lexer.init(&l, alloc)
	tokens, lexer_err := lexer.scan(&l, source)
	if lexer_err != nil {
		testing.expectf(t, false, "%s: unexpected lexer error: %v", source, lexer_err)
		return nil, false
	}

	p: Parser
	init(&p, tokens[:], alloc)
	stmts, parser_err := parse(&p)
	if parser_err != nil {
		testing.expectf(t, false, "%s: unexpected parser error: %v", source, parser_err)
		return nil, false
	}
	if len(stmts) != 1 {
		testing.expectf(t, false, "%s: expected 1 statement, got %d", source, len(stmts))
		return nil, false
	}

	#partial switch s in stmts[0] {
	case ^syntax.Ident_Decl_Stmt:
		value, has_value := s.value.?
		if !has_value {
			testing.expectf(t, false, "%s: declaration has no value", source)
			return nil, false
		}
		return value, true
	case ^syntax.Ident_Assignment_Stmt:
		return s.values, true
	}

	testing.expectf(t, false, "%s: expected a decl or assignment statement", source)
	return nil, false
}

@(private = "file")
token_text :: proc(source: string, token: syntax.Token) -> string {
	return source[token.span.start:token.span.end]
}

@(private = "file")
expect_span_text :: proc(
	t: ^testing.T,
	source: string,
	span: syntax.Span,
	expected, label: string,
	loc := #caller_location,
) {
	if !syntax.span_is_valid(span, len(source)) {
		testing.expectf(
			t,
			false,
			"%s: invalid span %v for source length %d",
			label,
			span,
			len(source),
			loc = loc,
		)
		return
	}

	actual := source[span.start:span.end]
	testing.expectf(
		t,
		actual == expected,
		"%s: span covers %q, want %q",
		label,
		actual,
		expected,
		loc = loc,
	)
}

// The source text an argument expression spans. Call arguments are now full
// expressions, so their text comes from the expression's span rather than a token.
@(private = "file")
arg_text :: proc(source: string, arg: syntax.Expr) -> string {
	span := syntax.span_of_expr(arg)
	return source[span.start:span.end]
}

// Lexes and parses `source`, asserting it succeeds.
@(private = "file")
expect_parse_ok :: proc(t: ^testing.T, source: string, loc := #caller_location) {
	arena: mem.Dynamic_Arena
	mem.dynamic_arena_init(&arena)
	arena_alloc := mem.dynamic_arena_allocator(&arena)
	defer mem.dynamic_arena_destroy(&arena)

	l: lexer.Lexer
	lexer.init(&l, arena_alloc)
	tokens, lexer_err := lexer.scan(&l, source)
	if lexer_err != nil {
		testing.expectf(t, false, "%q: unexpected lexer error: %v", source, lexer_err, loc = loc)
		return
	}

	p: Parser
	init(&p, tokens[:], arena_alloc)
	_, parser_err := parse(&p)
	testing.expectf(
		t,
		parser_err == nil,
		"%q: unexpected parser error: %v",
		source,
		parser_err,
		loc = loc,
	)
}

// Lexes and parses `source`, asserting it fails with exactly `kind`.
@(private = "file")
expect_parse_error :: proc(
	t: ^testing.T,
	source: string,
	kind: Parser_Error_Kind,
	loc := #caller_location,
) {
	arena: mem.Dynamic_Arena
	mem.dynamic_arena_init(&arena)
	arena_alloc := mem.dynamic_arena_allocator(&arena)
	defer mem.dynamic_arena_destroy(&arena)

	l: lexer.Lexer
	lexer.init(&l, arena_alloc)
	tokens, lexer_err := lexer.scan(&l, source)
	if lexer_err != nil {
		testing.expectf(t, false, "%q: unexpected lexer error: %v", source, lexer_err, loc = loc)
		return
	}

	p: Parser
	init(&p, tokens[:], arena_alloc)
	_, parser_err := parse(&p)
	e, ok := parser_err.?
	testing.expectf(t, ok, "%q: expected a %v error, got none", source, kind, loc = loc)
	if ok {
		testing.expectf(t, e.kind == kind, "%q: got %v, want %v", source, e.kind, kind, loc = loc)
	}
}

@(private = "file")
expect_target_names :: proc(t: ^testing.T, name, source: string, names: []syntax.Token) {
	testing.expectf(t, len(names) == 2, "%s: got %d targets, want 2", name, len(names))
	if len(names) < 2 do return
	testing.expectf(t, token_text(source, names[0]) == "a", "%s: first target is not a", name)
	testing.expectf(t, token_text(source, names[1]) == "b", "%s: second target is not b", name)
}

// Asserts the RHS holds a single expression that is a function call.
@(private = "file")
expect_single_call :: proc(
	t: ^testing.T,
	name: string,
	rhs: [dynamic]syntax.Expr,
) -> (
	^syntax.Fn_Call_Expr,
	bool,
) {
	if len(rhs) != 1 {
		testing.expectf(t, false, "%s: expected single call RHS, got %d values", name, len(rhs))
		return nil, false
	}
	call, ok := rhs[0].(^syntax.Fn_Call_Expr)
	if !ok {
		testing.expectf(t, false, "%s: RHS value is not a Call_Expr", name)
		return nil, false
	}
	return call, true
}

@(private = "file")
make_token :: proc(
	kind: syntax.Token_Kind,
	start: int,
	end: int,
	kw: Maybe(syntax.Keyword) = nil,
) -> syntax.Token {
	return syntax.Token {
		kind = kind,
		line = 1,
		span = {start = start, end = end},
		column = start,
		keyword = kw,
	}
}

@(private = "file")
Test :: struct {
	name:         string,
	input:        []syntax.Token,
	source:       string,
	expected:     syntax.Expr,
	should_error: bool,
	error_kind:   Parser_Error_Kind,
}

@(private = "file")
log_ast :: proc(source: string, stmts: []syntax.Stmt) {
	for stmt, i in stmts {
		builder := strings.builder_make()
		defer strings.builder_destroy(&builder)

		log.infof("Printing AST for stmt %d", i + 1)
		ast.build_ast_from_stmt(&builder, source, stmt)
		log.info(strings.to_string(builder))
	}
}
