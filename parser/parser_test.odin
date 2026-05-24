package parser

import "../ast"
import "../syntax"
import "core:log"
import "core:mem"
import "core:strings"
import "core:testing"

@(test)
test_basic_expressions :: proc(t: ^testing.T) {
	tests := []Test {
		Test {
			name = "smoke",
			source = "1 / (2 * -5) + 1 == 3 == 4",
			input = []syntax.Token {
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
			expected = syntax.Expr {
				expr = syntax.Binary_Expr {
					left = &syntax.Expr {
						expr = syntax.Binary_Expr {
							left = &syntax.Expr {
								expr = syntax.Binary_Expr {
									left = &syntax.Expr {
										expr = syntax.Binary_Expr {
											left = &syntax.Expr {
												expr = syntax.Literal_Expr {
													token = make_token(.Literal, 0, 1),
												},
											},
											op = .Slash,
											right = &syntax.Expr {
												expr = syntax.Grouping_Expr {
													expr = &syntax.Expr {
														expr = syntax.Binary_Expr {
															left = &syntax.Expr {
																expr = syntax.Literal_Expr {
																	token = make_token(
																		.Literal,
																		5,
																		6,
																	),
																},
															},
															op = .Star,
															right = &syntax.Expr {
																expr = syntax.Unary_Expr {
																	op = .Minus,
																	right = &syntax.Expr {
																		expr = syntax.Literal_Expr {
																			token = make_token(
																				.Literal,
																				10,
																				11,
																			),
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
									op = .Plus,
									right = &syntax.Expr {
										expr = syntax.Literal_Expr {
											token = make_token(.Literal, 15, 16),
										},
									},
								},
							},
							op = .Equal_Equal,
							right = &syntax.Expr {
								expr = syntax.Literal_Expr{token = make_token(.Literal, 20, 21)},
							},
						},
					},
					op = .Equal_Equal,
					right = &syntax.Expr {
						expr = syntax.Literal_Expr{token = make_token(.Literal, 25, 26)},
					},
				},
			},
		},
		Test {
			name = "grouping overrides precedence",
			source = "(1 + 2) * 3",
			input = []syntax.Token {
				make_token(.Left_Paren, 0, 1), // (
				make_token(.Literal, 1, 2), // 1
				make_token(.Plus, 3, 4), // +
				make_token(.Literal, 5, 6), // 2
				make_token(.Right_Paren, 6, 7), // )
				make_token(.Star, 8, 9), // *
				make_token(.Literal, 10, 11), // 3
				make_token(.EOF, 11, 12),
			},
			expected = syntax.Expr {
				expr = syntax.Binary_Expr {
					left = &syntax.Expr {
						expr = syntax.Grouping_Expr {
							expr = &syntax.Expr {
								expr = syntax.Binary_Expr {
									left = &syntax.Expr {
										expr = syntax.Literal_Expr {
											token = make_token(.Literal, 1, 2),
										},
									},
									op = .Plus,
									right = &syntax.Expr {
										expr = syntax.Literal_Expr {
											token = make_token(.Literal, 5, 6),
										},
									},
								},
							},
						},
					},
					op = .Star,
					right = &syntax.Expr {
						expr = syntax.Literal_Expr{token = make_token(.Literal, 10, 11)},
					},
				},
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
			name = "nested binary expressions",
			source = "1 > 2 == 3",
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
		Test {
			name = "term addition",
			source = "1 + 2",
			input = []syntax.Token {
				make_token(.Literal, 0, 1), // 1
				make_token(.Plus, 2, 3), // +
				make_token(.Literal, 4, 5), // 2
				make_token(.EOF, 5, 6),
			},
			expected = syntax.Expr {
				expr = syntax.Binary_Expr {
					left = &syntax.Expr {
						expr = syntax.Literal_Expr{token = make_token(.Literal, 0, 1)},
					},
					op = .Plus,
					right = &syntax.Expr {
						expr = syntax.Literal_Expr{token = make_token(.Literal, 4, 5)},
					},
				},
			},
		},
		Test {
			name = "term subtraction",
			source = "5 - 3",
			input = []syntax.Token {
				make_token(.Literal, 0, 1), // 5
				make_token(.Minus, 2, 3), // -
				make_token(.Literal, 4, 5), // 3
				make_token(.EOF, 5, 6),
			},
			expected = syntax.Expr {
				expr = syntax.Binary_Expr {
					left = &syntax.Expr {
						expr = syntax.Literal_Expr{token = make_token(.Literal, 0, 1)},
					},
					op = .Minus,
					right = &syntax.Expr {
						expr = syntax.Literal_Expr{token = make_token(.Literal, 4, 5)},
					},
				},
			},
		},
		Test {
			name = "factor multiplication",
			source = "2 * 3",
			input = []syntax.Token {
				make_token(.Literal, 0, 1), // 2
				make_token(.Star, 2, 3), // *
				make_token(.Literal, 4, 5), // 3
				make_token(.EOF, 5, 6),
			},
			expected = syntax.Expr {
				expr = syntax.Binary_Expr {
					left = &syntax.Expr {
						expr = syntax.Literal_Expr{token = make_token(.Literal, 0, 1)},
					},
					op = .Star,
					right = &syntax.Expr {
						expr = syntax.Literal_Expr{token = make_token(.Literal, 4, 5)},
					},
				},
			},
		},
		Test {
			name = "factor division",
			source = "10 / 2",
			input = []syntax.Token {
				make_token(.Literal, 0, 1), // 10
				make_token(.Slash, 2, 3), // /
				make_token(.Literal, 4, 5), // 2
				make_token(.EOF, 5, 6),
			},
			expected = syntax.Expr {
				expr = syntax.Binary_Expr {
					left = &syntax.Expr {
						expr = syntax.Literal_Expr{token = make_token(.Literal, 0, 1)},
					},
					op = .Slash,
					right = &syntax.Expr {
						expr = syntax.Literal_Expr{token = make_token(.Literal, 4, 5)},
					},
				},
			},
		},
		Test {
			name = "unary negation",
			source = "-5",
			input = []syntax.Token {
				make_token(.Minus, 0, 1), // -
				make_token(.Literal, 1, 2), // 5
				make_token(.EOF, 2, 3),
			},
			expected = syntax.Expr {
				expr = syntax.Unary_Expr {
					op = .Minus,
					right = &syntax.Expr {
						expr = syntax.Literal_Expr{token = make_token(.Literal, 1, 2)},
					},
				},
			},
		},
		Test {
			name = "unary logical not",
			source = "!true",
			input = []syntax.Token {
				make_token(.Bang, 0, 1), // !
				make_token(.Literal, 1, 2), // true
				make_token(.EOF, 2, 3),
			},
			expected = syntax.Expr {
				expr = syntax.Unary_Expr {
					op = .Bang,
					right = &syntax.Expr {
						expr = syntax.Literal_Expr{token = make_token(.Literal, 1, 2)},
					},
				},
			},
		},
		Test {
			name = "double unary",
			source = "--5",
			input = []syntax.Token {
				make_token(.Minus, 0, 1), // -
				make_token(.Minus, 1, 2), // -
				make_token(.Literal, 2, 3), // 5
				make_token(.EOF, 3, 4),
			},
			expected = syntax.Expr {
				expr = syntax.Unary_Expr {
					op = .Minus,
					right = &syntax.Expr {
						expr = syntax.Unary_Expr {
							op = .Minus,
							right = &syntax.Expr {
								expr = syntax.Literal_Expr{token = make_token(.Literal, 2, 3)},
							},
						},
					},
				},
			},
		},
		Test {
			name = "precedence: multiplication before addition",
			source = "1 + 2 * 3",
			input = []syntax.Token {
				make_token(.Literal, 0, 1), // 1
				make_token(.Plus, 2, 3), // +
				make_token(.Literal, 4, 5), // 2
				make_token(.Star, 6, 7), // *
				make_token(.Literal, 8, 9), // 3
				make_token(.EOF, 9, 10),
			},
			expected = syntax.Expr {
				expr = syntax.Binary_Expr {
					left = &syntax.Expr {
						expr = syntax.Literal_Expr{token = make_token(.Literal, 0, 1)},
					},
					op = .Plus,
					right = &syntax.Expr {
						expr = syntax.Binary_Expr {
							left = &syntax.Expr {
								expr = syntax.Literal_Expr{token = make_token(.Literal, 4, 5)},
							},
							op = .Star,
							right = &syntax.Expr {
								expr = syntax.Literal_Expr{token = make_token(.Literal, 8, 9)},
							},
						},
					},
				},
			},
		},
		Test {
			name = "precedence: division before subtraction",
			source = "10 - 6 / 2",
			input = []syntax.Token {
				make_token(.Literal, 0, 1), // 10
				make_token(.Minus, 2, 3), // -
				make_token(.Literal, 4, 5), // 6
				make_token(.Slash, 6, 7), // /
				make_token(.Literal, 8, 9), // 2
				make_token(.EOF, 9, 10),
			},
			expected = syntax.Expr {
				expr = syntax.Binary_Expr {
					left = &syntax.Expr {
						expr = syntax.Literal_Expr{token = make_token(.Literal, 0, 1)},
					},
					op = .Minus,
					right = &syntax.Expr {
						expr = syntax.Binary_Expr {
							left = &syntax.Expr {
								expr = syntax.Literal_Expr{token = make_token(.Literal, 4, 5)},
							},
							op = .Slash,
							right = &syntax.Expr {
								expr = syntax.Literal_Expr{token = make_token(.Literal, 8, 9)},
							},
						},
					},
				},
			},
		},
		Test {
			name = "precedence: unary before multiplication",
			source = "-2 * 3",
			input = []syntax.Token {
				make_token(.Minus, 0, 1), // -
				make_token(.Literal, 1, 2), // 2
				make_token(.Star, 3, 4), // *
				make_token(.Literal, 5, 6), // 3
				make_token(.EOF, 6, 7),
			},
			expected = syntax.Expr {
				expr = syntax.Binary_Expr {
					left = &syntax.Expr {
						expr = syntax.Unary_Expr {
							op = .Minus,
							right = &syntax.Expr {
								expr = syntax.Literal_Expr{token = make_token(.Literal, 1, 2)},
							},
						},
					},
					op = .Star,
					right = &syntax.Expr {
						expr = syntax.Literal_Expr{token = make_token(.Literal, 5, 6)},
					},
				},
			},
		},
		Test {
			name = "complex precedence",
			source = "1 + 2 * 3 > 4",
			input = []syntax.Token {
				make_token(.Literal, 0, 1), // 1
				make_token(.Plus, 2, 3), // +
				make_token(.Literal, 4, 5), // 2
				make_token(.Star, 6, 7), // *
				make_token(.Literal, 8, 9), // 3
				make_token(.Greater, 10, 11), // >
				make_token(.Literal, 12, 13), // 4
				make_token(.EOF, 13, 14),
			},
			expected = syntax.Expr {
				expr = syntax.Binary_Expr {
					left = &syntax.Expr {
						expr = syntax.Binary_Expr {
							left = &syntax.Expr {
								expr = syntax.Literal_Expr{token = make_token(.Literal, 0, 1)},
							},
							op = .Plus,
							right = &syntax.Expr {
								expr = syntax.Binary_Expr {
									left = &syntax.Expr {
										expr = syntax.Literal_Expr {
											token = make_token(.Literal, 4, 5),
										},
									},
									op = .Star,
									right = &syntax.Expr {
										expr = syntax.Literal_Expr {
											token = make_token(.Literal, 8, 9),
										},
									},
								},
							},
						},
					},
					op = .Greater,
					right = &syntax.Expr {
						expr = syntax.Literal_Expr{token = make_token(.Literal, 12, 13)},
					},
				},
			},
		},
		// Operator chaining tests (multiple operators at same precedence level)
		Test {
			name = "chained addition (left associative)",
			source = "1 + 2 + 3",
			input = []syntax.Token {
				make_token(.Literal, 0, 1), // 1
				make_token(.Plus, 2, 3), // +
				make_token(.Literal, 4, 5), // 2
				make_token(.Plus, 6, 7), // +
				make_token(.Literal, 8, 9), // 3
				make_token(.EOF, 9, 10),
			},
			expected = syntax.Expr {
				expr = syntax.Binary_Expr {
					left = &syntax.Expr {
						expr = syntax.Binary_Expr {
							left = &syntax.Expr {
								expr = syntax.Literal_Expr{token = make_token(.Literal, 0, 1)},
							},
							op = .Plus,
							right = &syntax.Expr {
								expr = syntax.Literal_Expr{token = make_token(.Literal, 4, 5)},
							},
						},
					},
					op = .Plus,
					right = &syntax.Expr {
						expr = syntax.Literal_Expr{token = make_token(.Literal, 8, 9)},
					},
				},
			},
		},
		Test {
			name = "chained multiplication (left associative)",
			source = "2 * 3 * 4",
			input = []syntax.Token {
				make_token(.Literal, 0, 1), // 2
				make_token(.Star, 2, 3), // *
				make_token(.Literal, 4, 5), // 3
				make_token(.Star, 6, 7), // *
				make_token(.Literal, 8, 9), // 4
				make_token(.EOF, 9, 10),
			},
			expected = syntax.Expr {
				expr = syntax.Binary_Expr {
					left = &syntax.Expr {
						expr = syntax.Binary_Expr {
							left = &syntax.Expr {
								expr = syntax.Literal_Expr{token = make_token(.Literal, 0, 1)},
							},
							op = .Star,
							right = &syntax.Expr {
								expr = syntax.Literal_Expr{token = make_token(.Literal, 4, 5)},
							},
						},
					},
					op = .Star,
					right = &syntax.Expr {
						expr = syntax.Literal_Expr{token = make_token(.Literal, 8, 9)},
					},
				},
			},
		},
		Test {
			name = "mixed addition and subtraction",
			source = "10 + 5 - 3",
			input = []syntax.Token {
				make_token(.Literal, 0, 1), // 10
				make_token(.Plus, 2, 3), // +
				make_token(.Literal, 4, 5), // 5
				make_token(.Minus, 6, 7), // -
				make_token(.Literal, 8, 9), // 3
				make_token(.EOF, 9, 10),
			},
			expected = syntax.Expr {
				expr = syntax.Binary_Expr {
					left = &syntax.Expr {
						expr = syntax.Binary_Expr {
							left = &syntax.Expr {
								expr = syntax.Literal_Expr{token = make_token(.Literal, 0, 1)},
							},
							op = .Plus,
							right = &syntax.Expr {
								expr = syntax.Literal_Expr{token = make_token(.Literal, 4, 5)},
							},
						},
					},
					op = .Minus,
					right = &syntax.Expr {
						expr = syntax.Literal_Expr{token = make_token(.Literal, 8, 9)},
					},
				},
			},
		},
		Test {
			name = "mixed multiplication and division",
			source = "12 * 2 / 3",
			input = []syntax.Token {
				make_token(.Literal, 0, 1), // 12
				make_token(.Star, 2, 3), // *
				make_token(.Literal, 4, 5), // 2
				make_token(.Slash, 6, 7), // /
				make_token(.Literal, 8, 9), // 3
				make_token(.EOF, 9, 10),
			},
			expected = syntax.Expr {
				expr = syntax.Binary_Expr {
					left = &syntax.Expr {
						expr = syntax.Binary_Expr {
							left = &syntax.Expr {
								expr = syntax.Literal_Expr{token = make_token(.Literal, 0, 1)},
							},
							op = .Star,
							right = &syntax.Expr {
								expr = syntax.Literal_Expr{token = make_token(.Literal, 4, 5)},
							},
						},
					},
					op = .Slash,
					right = &syntax.Expr {
						expr = syntax.Literal_Expr{token = make_token(.Literal, 8, 9)},
					},
				},
			},
		},
		Test {
			name = "chained equality",
			source = "1 == 2 == 3",
			input = []syntax.Token {
				make_token(.Literal, 0, 1), // 1
				make_token(.Equal_Equal, 2, 4), // ==
				make_token(.Literal, 5, 6), // 2
				make_token(.Equal_Equal, 7, 9), // ==
				make_token(.Literal, 10, 11), // 3
				make_token(.EOF, 11, 12),
			},
			expected = syntax.Expr {
				expr = syntax.Binary_Expr {
					left = &syntax.Expr {
						expr = syntax.Binary_Expr {
							left = &syntax.Expr {
								expr = syntax.Literal_Expr{token = make_token(.Literal, 0, 1)},
							},
							op = .Equal_Equal,
							right = &syntax.Expr {
								expr = syntax.Literal_Expr{token = make_token(.Literal, 5, 6)},
							},
						},
					},
					op = .Equal_Equal,
					right = &syntax.Expr {
						expr = syntax.Literal_Expr{token = make_token(.Literal, 10, 11)},
					},
				},
			},
		},
		Test {
			name = "mixed equality operators",
			source = "1 == 2 != 3",
			input = []syntax.Token {
				make_token(.Literal, 0, 1), // 1
				make_token(.Equal_Equal, 2, 4), // ==
				make_token(.Literal, 5, 6), // 2
				make_token(.Bang_Equal, 7, 9), // !=
				make_token(.Literal, 10, 11), // 3
				make_token(.EOF, 11, 12),
			},
			expected = syntax.Expr {
				expr = syntax.Binary_Expr {
					left = &syntax.Expr {
						expr = syntax.Binary_Expr {
							left = &syntax.Expr {
								expr = syntax.Literal_Expr{token = make_token(.Literal, 0, 1)},
							},
							op = .Equal_Equal,
							right = &syntax.Expr {
								expr = syntax.Literal_Expr{token = make_token(.Literal, 5, 6)},
							},
						},
					},
					op = .Bang_Equal,
					right = &syntax.Expr {
						expr = syntax.Literal_Expr{token = make_token(.Literal, 10, 11)},
					},
				},
			},
		},
		Test {
			name = "chained comparison",
			source = "1 < 2 < 3",
			input = []syntax.Token {
				make_token(.Literal, 0, 1), // 1
				make_token(.Less, 2, 3), // <
				make_token(.Literal, 4, 5), // 2
				make_token(.Less, 6, 7), // <
				make_token(.Literal, 8, 9), // 3
				make_token(.EOF, 9, 10),
			},
			expected = syntax.Expr {
				expr = syntax.Binary_Expr {
					left = &syntax.Expr {
						expr = syntax.Binary_Expr {
							left = &syntax.Expr {
								expr = syntax.Literal_Expr{token = make_token(.Literal, 0, 1)},
							},
							op = .Less,
							right = &syntax.Expr {
								expr = syntax.Literal_Expr{token = make_token(.Literal, 4, 5)},
							},
						},
					},
					op = .Less,
					right = &syntax.Expr {
						expr = syntax.Literal_Expr{token = make_token(.Literal, 8, 9)},
					},
				},
			},
		},
		Test {
			name = "long chained expression",
			source = "1 + 2 + 3 + 4",
			input = []syntax.Token {
				make_token(.Literal, 0, 1), // 1
				make_token(.Plus, 2, 3), // +
				make_token(.Literal, 4, 5), // 2
				make_token(.Plus, 6, 7), // +
				make_token(.Literal, 8, 9), // 3
				make_token(.Plus, 10, 11), // +
				make_token(.Literal, 12, 13), // 4
				make_token(.EOF, 13, 14),
			},
			expected = syntax.Expr {
				expr = syntax.Binary_Expr {
					left = &syntax.Expr {
						expr = syntax.Binary_Expr {
							left = &syntax.Expr {
								expr = syntax.Binary_Expr {
									left = &syntax.Expr {
										expr = syntax.Literal_Expr {
											token = make_token(.Literal, 0, 1),
										},
									},
									op = .Plus,
									right = &syntax.Expr {
										expr = syntax.Literal_Expr {
											token = make_token(.Literal, 4, 5),
										},
									},
								},
							},
							op = .Plus,
							right = &syntax.Expr {
								expr = syntax.Literal_Expr{token = make_token(.Literal, 8, 9)},
							},
						},
					},
					op = .Plus,
					right = &syntax.Expr {
						expr = syntax.Literal_Expr{token = make_token(.Literal, 12, 13)},
					},
				},
			},
		},
		Test {
			name = "multiple groupings with equality",
			source = "(1 + 2 == (2 + 1))",
			input = []syntax.Token {
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
			expected = syntax.Expr {
				expr = syntax.Grouping_Expr {
					expr = &syntax.Expr {
						expr = syntax.Binary_Expr {
							left = &syntax.Expr {
								expr = syntax.Binary_Expr {
									left = &syntax.Expr {
										expr = syntax.Literal_Expr {
											token = make_token(.Literal, 1, 2),
										},
									},
									op = .Plus,
									right = &syntax.Expr {
										expr = syntax.Literal_Expr {
											token = make_token(.Literal, 5, 6),
										},
									},
								},
							},
							op = .Equal_Equal,
							right = &syntax.Expr {
								expr = syntax.Grouping_Expr {
									expr = &syntax.Expr {
										expr = syntax.Binary_Expr {
											left = &syntax.Expr {
												expr = syntax.Literal_Expr {
													token = make_token(.Literal, 11, 12),
												},
											},
											op = .Plus,
											right = &syntax.Expr {
												expr = syntax.Literal_Expr {
													token = make_token(.Literal, 15, 16),
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

		got := stmts[0]^.(syntax.Expr_Stmt).expr

		expected := test.expected
		if !syntax.expr_eq(got, &expected) {
			log_ast(test.source, stmts[:])
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
			error_kind   = .UnclosedParen,
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

@(private = "file")
make_token :: proc(kind: syntax.Token_Kind, start: int, end: int) -> syntax.Token {
	return syntax.Token {
		kind = kind,
		line = 1,
		lexeme_start = start,
		lexeme_end = end,
		column = start,
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
log_ast :: proc(source: string, stmts: []^syntax.Stmt) {
	for stmt, i in stmts {
		builder := strings.builder_make()
		defer strings.builder_destroy(&builder)

		log.infof("Printing AST for stmt %d", i + 1)
		ast.build_ast_from_stmt(&builder, source, stmt)
		log.info(strings.to_string(builder))
	}
}
