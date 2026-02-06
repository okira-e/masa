package parser

import "../ast"
import "../syntax"
import "core:log"
import "core:mem"
import "core:strings"
import "core:testing"

@(test)
test_parser_smoke :: proc(t: ^testing.T) {
	tests := []Test {
		Test {
			name = "simple expression",
			input = []syntax.Token {
				make_token(.Literal, 0, 1),
				make_token(.Equal_Equal, 2, 4),
				make_token(.Literal, 6, 7),
				make_token(.EOF, 7, 8),
			},
			expected = syntax.Expr {
				expr = syntax.Binary_Expr {
					left = &syntax.Expr {
						expr = syntax.Literal_Expr{token = make_token(.Literal, 0, 1)},
					},
					op = .Equal_Equal,
					right = &syntax.Expr {
						expr = syntax.Literal_Expr{token = make_token(.Literal, 6, 7)},
					},
				},
			},
		},
		Test {
			name = "simple nested expression",
			input = []syntax.Token {
				make_token(.Literal, 0, 1), // 1
				make_token(.Greater, 2, 3), // >
				make_token(.Literal, 4, 5), // 2
				make_token(.Equal_Equal, 6, 8), // ==
				make_token(.Literal, 9, 10), // 3
				make_token(.EOF, 10, 11),
			},
			expected = syntax.Expr {
				expr = syntax.Binary_Expr {
					left = &syntax.Expr {
						expr = syntax.Binary_Expr {
							left = &syntax.Expr {
								expr = syntax.Literal_Expr{token = make_token(.Literal, 0, 1)},
							},
							op = .Greater,
							right = &syntax.Expr {
								expr = syntax.Literal_Expr{token = make_token(.Literal, 4, 5)},
							},
						},
					},
					op = .Equal_Equal,
					right = &syntax.Expr {
						expr = syntax.Literal_Expr{token = make_token(.Literal, 9, 10)},
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
		exprs, err := parse(&parser)
		defer delete(exprs)
		defer mem.dynamic_arena_destroy(&arena)

		builder := strings.builder_make()
		defer strings.builder_destroy(&builder)

		if err != nil {
			ast.build_ast_from_expr(&builder, "", exprs[0])
			log.info(strings.to_string(builder))

			testing.expectf(t, false, "unexpected error in %s: %v", test.name, err)
			testing.fail_now(t)
		}

		if len(exprs) != 1 {
			ast.build_ast_from_expr(&builder, "", exprs[0])
			log.info(strings.to_string(builder))

			testing.expectf(t, false, "%s: expected 1 statement, got %d", test.name, len(exprs))
			testing.fail_now(t)
		}

		got := exprs[0]

		expected := test.expected
		if !syntax.expr_eq(got, &expected) {
			ast.build_ast_from_expr(&builder, "", exprs[0])
			log.infof("AST: %s", strings.to_string(builder))

			testing.expectf(
				t,
				false,
				"%s: assertion failed.\nExpected: %v\nFound: %v",
				test.name,
				test.expected,
				got^,
			)
			testing.fail_now(t)
		}
	}
}

@(private = "file")
make_token :: proc(kind: syntax.Token_Kind, start: int, end: int) -> syntax.Token {
	return syntax.Token{kind = kind, line = 1, lexeme_start = start, lexeme_end = end}
}

@(private = "file")
Test :: struct {
	name:     string,
	input:    []syntax.Token,
	expected: syntax.Expr,
}
