package lexer

import "../syntax"
import "core:testing"

@(test)
test_lexer_smoke :: proc(t: ^testing.T) {
	tests := []Test {
		{
			name     = "Smoke test",
			input    = `( } ) / } // comment with "quotes" and //
""
// "disabled unterminated
// comment after bad string
// "" ""
"// not a comment"
/
""
123
0
4.7
camel_case // This an identifier
_message := "Hello World!"
{`,
			expected = []syntax.Token_Kind {
				.Left_Paren,
				.Right_Brace,
				.Right_Paren,
				.Slash,
				.Right_Brace,
				.Comment,
				.New_Line,
				.Literal,
				.New_Line,
				.Comment,
				.New_Line,
				.Comment,
				.New_Line,
				.Comment,
				.New_Line,
				.Literal,
				.New_Line,
				.Slash,
				.New_Line,
				.Literal,
				.New_Line,
				.Literal, // 123
				.New_Line,
				.Literal, // 0
				.New_Line,
				.Literal, // 4.7
				.New_Line,
				.Ident,
				.Comment,
				.New_Line,
				.Ident,
				.Colon_Equal,
				.Literal,
				.New_Line,
				.Left_Brace,
				.EOF,
			},
		},
	}

	for tt in tests {
		lexer := Lexer{}
		init(&lexer)
		tokens, err := scan(&lexer, tt.input)
		defer delete(tokens)
		if err != nil {
			print_tokens(tt.input, tokens)
			testing.expectf(t, false, "unexpected error in %s: %v", tt.name, err)
			testing.fail_now(t)
		}

		if len(tokens) != len(tt.expected) {
			print_tokens(tt.input, tokens)
			testing.expectf(
				t,
				false,
				"%s: expected %d tokens, got %d",
				tt.name,
				len(tt.expected),
				len(tokens),
			)
			testing.fail_now(t)
		}

		for expected_kind, i in tt.expected {
			if tokens[i].kind != expected_kind {
				print_tokens(tt.input, tokens)
				testing.expectf(
					t,
					false,
					"%s: token %d: expected kind %v, got %v",
					tt.name,
					i,
					expected_kind,
					tokens[i].kind,
				)
				testing.fail_now(t)
			}
		}
	}
}

@(test)
test_lexer_single_tokens :: proc(t: ^testing.T) {
	tests := []Test {
		{
			name = "left parenthesis",
			input = "(",
			expected = []syntax.Token_Kind{.Left_Paren, .EOF},
		},
		{name = "slash", input = "/", expected = []syntax.Token_Kind{.Slash, .EOF}},
		{name = "newline", input = "\n", expected = []syntax.Token_Kind{.New_Line, .EOF}},
		{name = "comment", input = "// hello", expected = []syntax.Token_Kind{.Comment, .EOF}},
	}

	for tt in tests {
		lexer := Lexer{}
		init(&lexer)
		tokens, err := scan(&lexer, tt.input)
		defer delete(tokens)
		if err != nil {
			print_tokens(tt.input, tokens)
			testing.expectf(t, false, "unexpected error in %s: %v", tt.name, err)
			testing.fail_now(t)
		}

		if len(tokens) != len(tt.expected) {
			print_tokens(tt.input, tokens)
			testing.expectf(
				t,
				false,
				"%s: expected %d tokens, got %d",
				tt.name,
				len(tt.expected),
				len(tokens),
			)
			testing.fail_now(t)
		}

		for expected_kind, i in tt.expected {
			if tokens[i].kind != expected_kind {
				print_tokens(tt.input, tokens)
				testing.expectf(
					t,
					false,
					"%s: token %d: expected kind %v, got %v",
					tt.name,
					i,
					expected_kind,
					tokens[i].kind,
				)
				testing.fail_now(t)
			}
		}
	}
}

@(test)
test_lexer_multiple_tokens :: proc(t: ^testing.T) {
	tests := []Test {
		{
			name = "parentheses pair",
			input = "()",
			expected = []syntax.Token_Kind{.Left_Paren, .Right_Paren, .EOF},
		},
		{
			name = "mixed brackets",
			input = "({)}",
			expected = []syntax.Token_Kind {
				.Left_Paren,
				.Left_Brace,
				.Right_Paren,
				.Right_Brace,
				.EOF,
			},
		},
		{
			name = "slash and brace",
			input = "/}",
			expected = []syntax.Token_Kind{.Slash, .Right_Brace, .EOF},
		},
		{
			name = "comment and newline",
			input = "// comment\n",
			expected = []syntax.Token_Kind{.Comment, .New_Line, .EOF},
		},
	}

	for tt in tests {
		lexer := Lexer{}
		init(&lexer)
		tokens, err := scan(&lexer, tt.input)
		defer delete(tokens)
		if err != nil {
			print_tokens(tt.input, tokens)
			testing.expectf(t, false, "unexpected error in %s: %v", tt.name, err)
			testing.fail_now(t)
		}

		if len(tokens) != len(tt.expected) {
			print_tokens(tt.input, tokens)
			testing.expectf(
				t,
				false,
				"%s: expected %d tokens, got %d",
				tt.name,
				len(tt.expected),
				len(tokens),
			)
			testing.fail_now(t)
		}

		for expected_kind, i in tt.expected {
			if tokens[i].kind != expected_kind {
				print_tokens(tt.input, tokens)
				testing.expectf(
					t,
					false,
					"%s: token %d: expected kind %v, got %v",
					tt.name,
					i,
					expected_kind,
					tokens[i].kind,
				)
				testing.fail_now(t)
			}
		}
	}
}

@(test)
test_lexer_with_whitespace :: proc(t: ^testing.T) {
	tests := []Test {
		{
			name = "spaces between tokens",
			input = "( )",
			expected = []syntax.Token_Kind{.Left_Paren, .Right_Paren, .EOF},
		},
		{
			name = "tabs between tokens",
			input = "{\t}",
			expected = []syntax.Token_Kind{.Left_Brace, .Right_Brace, .EOF},
		},
		{
			name = "carriage return ignored",
			input = "(\r)",
			expected = []syntax.Token_Kind{.Left_Paren, .Right_Paren, .EOF},
		},
		{
			name = "multiple spaces",
			input = "(   )",
			expected = []syntax.Token_Kind{.Left_Paren, .Right_Paren, .EOF},
		},
	}

	for tt in tests {
		lexer := Lexer{}
		init(&lexer)
		tokens, err := scan(&lexer, tt.input)
		defer delete(tokens)
		if err != nil {
			print_tokens(tt.input, tokens)
			testing.expectf(t, false, "unexpected error in %s: %v", tt.name, err)
			testing.fail_now(t)
		}

		if len(tokens) != len(tt.expected) {
			print_tokens(tt.input, tokens)
			testing.expectf(
				t,
				false,
				"%s: expected %d tokens, got %d",
				tt.name,
				len(tt.expected),
				len(tokens),
			)
			testing.fail_now(t)
		}

		for expected_kind, i in tt.expected {
			if tokens[i].kind != expected_kind {
				print_tokens(tt.input, tokens)
				testing.expectf(
					t,
					false,
					"%s: token %d: expected kind %v, got %v",
					tt.name,
					i,
					expected_kind,
					tokens[i].kind,
				)
				testing.fail_now(t)
			}
		}
	}
}

@(test)
test_lexer_comments :: proc(t: ^testing.T) {
	tests := []Test {
		{
			name = "simple comment",
			input = "// Hi there hello",
			expected = []syntax.Token_Kind{.Comment, .EOF},
		},
		{
			name = "comment with newline",
			input = "// comment\n",
			expected = []syntax.Token_Kind{.Comment, .New_Line, .EOF},
		},
		{
			name = "multiple comments",
			input = "// first\n// second",
			expected = []syntax.Token_Kind{.Comment, .New_Line, .Comment, .EOF},
		},
		{
			name = "comment after token",
			input = "{ // comment",
			expected = []syntax.Token_Kind{.Left_Brace, .Comment, .EOF},
		},
		{name = "empty comment", input = "//", expected = []syntax.Token_Kind{.Comment, .EOF}},
	}

	for tt in tests {
		lexer := Lexer{}
		init(&lexer)
		tokens, err := scan(&lexer, tt.input)
		defer delete(tokens)
		if err != nil {
			print_tokens(tt.input, tokens)
			testing.expectf(t, false, "unexpected error in %s: %v", tt.name, err)
			testing.fail_now(t)
		}

		if len(tokens) != len(tt.expected) {
			print_tokens(tt.input, tokens)
			testing.expectf(
				t,
				false,
				"%s: expected %d tokens, got %d",
				tt.name,
				len(tt.expected),
				len(tokens),
			)
			testing.fail_now(t)
		}

		for expected_kind, i in tt.expected {
			if tokens[i].kind != expected_kind {
				print_tokens(tt.input, tokens)
				testing.expectf(
					t,
					false,
					"%s: token %d: expected kind %v, got %v",
					tt.name,
					i,
					expected_kind,
					tokens[i].kind,
				)
				testing.fail_now(t)
			}
		}
	}
}

@(test)
test_lexer_line_and_column_tracking :: proc(t: ^testing.T) {
	input := "(\n)"

	lexer := Lexer{}
	init(&lexer)
	tokens, err := scan(&lexer, input)
	defer delete(tokens)
	if err != nil {
		print_tokens(input, tokens)
		testing.expectf(t, false, "unexpected error: %v", err)
		testing.fail_now(t)
	}

	// First token: '(' on line 1
	if tokens[0].line != 1 {
		print_tokens(input, tokens)
		testing.expectf(t, false, "expected first token on line 1, got line %d", tokens[0].line)
		testing.fail_now(t)
	}

	// Second token: '\n' on line 1
	if tokens[1].line != 1 {
		print_tokens(input, tokens)
		testing.expectf(t, false, "expected second token on line 1, got line %d", tokens[1].line)
		testing.fail_now(t)
	}

	// Third token: ')' on line 2
	if tokens[2].line != 2 {
		print_tokens(input, tokens)
		testing.expectf(t, false, "expected third token on line 2, got line %d", tokens[2].line)
		testing.fail_now(t)
	}

	if len(tokens) < 4 || tokens[3].kind != .EOF {
		print_tokens(input, tokens)
		testing.expectf(t, false, "expected EOF token at end of input")
		testing.fail_now(t)
	}
}

@(test)
test_lexer_lexeme_ranges :: proc(t: ^testing.T) {
	input := "(){}"

	lexer := Lexer{}
	init(&lexer)
	tokens, err := scan(&lexer, input)
	defer delete(tokens)
	if err != nil {
		print_tokens(input, tokens)
		testing.expectf(t, false, "unexpected error: %v", err)
		testing.fail_now(t)
	}

	if len(tokens) == 0 || tokens[len(tokens) - 1].kind != .EOF {
		print_tokens(input, tokens)
		testing.expectf(t, false, "expected EOF token at end of input")
		testing.fail_now(t)
	}

	for tok, i in tokens {
		if tok.kind == .EOF {
			continue
		}

		lexeme := input[tok.lexeme_start:tok.lexeme_end]

		expected := ""
		#partial switch tok.kind {
		case .Left_Paren:
			expected = "("
		case .Right_Paren:
			expected = ")"
		case .Left_Brace:
			expected = "{"
		case .Right_Brace:
			expected = "}"
		}

		if lexeme != expected {
			print_tokens(input, tokens)
			testing.expectf(t, false, "token %d: expected lexeme %q, got %q", i, expected, lexeme)
			testing.fail_now(t)
		}
	}
}

@(test)
test_lexer_empty_input :: proc(t: ^testing.T) {
	input := ""

	lexer := Lexer{}
	init(&lexer)
	tokens, err := scan(&lexer, input)
	defer delete(tokens)
	if err != nil {
		print_tokens(input, tokens)
		testing.expectf(t, false, "unexpected error: %v", err)
		testing.fail_now(t)
	}

	if len(tokens) != 1 {
		print_tokens(input, tokens)
		testing.expectf(t, false, "expected 1 token for empty input, got %d", len(tokens))
		testing.fail_now(t)
	}

	if len(tokens) != 1 || tokens[0].kind != .EOF {
		print_tokens(input, tokens)
		testing.expectf(t, false, "expected EOF token for empty input")
		testing.fail_now(t)
	}
}

@(test)
test_lexer_declaration_and_assignment :: proc(t: ^testing.T) {
	tests := []Test {
		{name = "assignment equal", input = "=", expected = []syntax.Token_Kind{.Equal, .EOF}},
		{
			name = "equal equal comparison",
			input = "==",
			expected = []syntax.Token_Kind{.Equal_Equal, .EOF},
		},
		{
			name = "declarative assignment",
			input = ":=",
			expected = []syntax.Token_Kind{.Colon_Equal, .EOF},
		},
		{
			name = "comptime declarative assignment",
			input = "::",
			expected = []syntax.Token_Kind{.Colon_Colon, .EOF},
		},
		{
			name = "variable runtime declarative assignment",
			input = "x := 5",
			expected = []syntax.Token_Kind{.Ident, .Colon_Equal, .Literal, .EOF},
		},
		{
			name = "variable comptime declarative assignment",
			input = "main :: fn",
			expected = []syntax.Token_Kind{.Ident, .Colon_Colon, .Keyword, .EOF},
		},
		{
			name = "variable assignment",
			input = "x = 10",
			expected = []syntax.Token_Kind{.Ident, .Equal, .Literal, .EOF},
		},
	}

	for tt in tests {
		lexer := Lexer{}
		init(&lexer)
		tokens, err := scan(&lexer, tt.input)
		defer delete(tokens)
		if err != nil {
			print_tokens(tt.input, tokens)
			testing.expectf(t, false, "unexpected error in %s: %v", tt.name, err)
			testing.fail_now(t)
		}

		if len(tokens) < len(tt.expected) {
			print_tokens(tt.input, tokens)
			testing.expectf(
				t,
				false,
				"%s: expected at least %d tokens, got %d",
				tt.name,
				len(tt.expected),
				len(tokens),
			)
			testing.fail_now(t)
		}

		for expected_kind, i in tt.expected {
			if tokens[i].kind != expected_kind {
				print_tokens(tt.input, tokens)
				testing.expectf(
					t,
					false,
					"%s: token %d: expected kind %v, got %v",
					tt.name,
					i,
					expected_kind,
					tokens[i].kind,
				)
				testing.fail_now(t)
			}
		}
	}
}

@(test)
test_lexer_bang_equal :: proc(t: ^testing.T) {
	tests := []Test {
		{name = "bang equal", input = "!=", expected = []syntax.Token_Kind{.Bang_Equal, .EOF}},
		{name = "bang alone", input = "!", expected = []syntax.Token_Kind{.Bang, .EOF}},
		{
			name = "bang not followed by equal",
			input = "!x",
			expected = []syntax.Token_Kind{.Bang, .Ident, .EOF},
		},
	}

	for tt in tests {
		lexer := Lexer{}
		init(&lexer)
		tokens, err := scan(&lexer, tt.input)
		defer delete(tokens)
		if err != nil {
			print_tokens(tt.input, tokens)
			testing.expectf(t, false, "unexpected error in %s: %v", tt.name, err)
			testing.fail_now(t)
		}

		if len(tokens) < len(tt.expected) {
			print_tokens(tt.input, tokens)
			testing.expectf(
				t,
				false,
				"%s: expected at least %d tokens, got %d",
				tt.name,
				len(tt.expected),
				len(tokens),
			)
			testing.fail_now(t)
		}

		for expected_kind, i in tt.expected {
			if tokens[i].kind != expected_kind {
				print_tokens(tt.input, tokens)
				testing.expectf(
					t,
					false,
					"%s: token %d: expected kind %v, got %v",
					tt.name,
					i,
					expected_kind,
					tokens[i].kind,
				)
				testing.fail_now(t)
			}
		}
	}
}

@(test)
test_lexer_strings :: proc(t: ^testing.T) {
	tests := []Test {
		{
			name = "empty string",
			input = `""`,
			expect_error = false,
			expected = []syntax.Token_Kind{.Literal, .EOF},
		},
		{
			name = "simple string",
			input = `"hello"`,
			expect_error = false,
			expected = []syntax.Token_Kind{.Literal, .EOF},
		},
		{
			name = "string with spaces",
			input = `"hello world"`,
			expect_error = false,
			expected = []syntax.Token_Kind{.Literal, .EOF},
		},
		{
			name = "string with special characters",
			input = `"!@#$%^&*()"`,
			expect_error = false,
			expected = []syntax.Token_Kind{.Literal, .EOF},
		},
		{
			name = "string with numbers",
			input = `"123456"`,
			expect_error = false,
			expected = []syntax.Token_Kind{.Literal, .EOF},
		},
		{
			name = "string with mixed content",
			input = `"Hello123!@#"`,
			expect_error = false,
			expected = []syntax.Token_Kind{.Literal, .EOF},
		},
		{
			name = "unterminated string at end",
			input = `"hello`,
			expect_error = true,
			expected = {},
		},
		{
			name = "unterminated string with newline",
			input = "\"hello\n",
			expect_error = true,
			expected = {},
		},
		{name = "single double quote", input = `"`, expect_error = true, expected = {}},
		{
			name = "multiple strings",
			input = `"one" "two"`,
			expect_error = false,
			expected = []syntax.Token_Kind{.Literal, .Literal, .EOF},
		},
		{
			name = "string followed by tokens",
			input = `"hello"()`,
			expect_error = false,
			expected = []syntax.Token_Kind{.Literal, .Left_Paren, .Right_Paren, .EOF},
		},
		{
			name = "tokens followed by string",
			input = `()"world"`,
			expect_error = false,
			expected = []syntax.Token_Kind{.Left_Paren, .Right_Paren, .Literal, .EOF},
		},
		{
			name = "string with tabs",
			input = "\"hello\tworld\"",
			expect_error = false,
			expected = []syntax.Token_Kind{.Literal, .EOF},
		},
		{
			name = "string with only spaces",
			input = `"   "`,
			expect_error = false,
			expected = []syntax.Token_Kind{.Literal, .EOF},
		},
		{
			name = "string at start of input",
			input = `"start" {}`,
			expect_error = false,
			expected = []syntax.Token_Kind{.Literal, .Left_Brace, .Right_Brace, .EOF},
		},
		{
			name = "string at end of input",
			input = `{} "end"`,
			expect_error = false,
			expected = []syntax.Token_Kind{.Left_Brace, .Right_Brace, .Literal, .EOF},
		},
	}

	for tt in tests {
		lexer := Lexer{}
		init(&lexer)
		tokens, err := scan(&lexer, tt.input)
		defer delete(tokens)
		if tt.expect_error {
			if err == nil {
				print_tokens(tt.input, tokens)
				testing.expectf(t, false, "%s: expected error but got none", tt.name)
				testing.fail_now(t)
			}
			continue
		}

		if err != nil {
			print_tokens(tt.input, tokens)
			testing.expectf(t, false, "unexpected error in %s: %v", tt.name, err)
			testing.fail_now(t)
		}

		if len(tokens) != len(tt.expected) {
			print_tokens(tt.input, tokens)
			testing.expectf(
				t,
				false,
				"%s: expected %d tokens, got %d",
				tt.name,
				len(tt.expected),
				len(tokens),
			)
			testing.fail_now(t)
		}

		for expected_kind, i in tt.expected {
			if tokens[i].kind != expected_kind {
				print_tokens(tt.input, tokens)
				testing.expectf(
					t,
					false,
					"%s: token %d: expected kind %v, got %v",
					tt.name,
					i,
					expected_kind,
					tokens[i].kind,
				)
				testing.fail_now(t)
			}
		}
	}
}

@(test)
test_lexer_string_lexeme_content :: proc(t: ^testing.T) {
	tests := []Test {
		{name = "simple string lexeme", input = `"hello"`, expected_string = `"hello"`},
		{
			name = "string with spaces lexeme",
			input = `"hello world"`,
			expected_string = `"hello world"`,
		},
	}

	for tt in tests {
		lexer := Lexer{}
		init(&lexer)
		tokens, err := scan(&lexer, tt.input)
		defer delete(tokens)
		if err != nil {
			print_tokens(tt.input, tokens)
			testing.expectf(t, false, "unexpected error in %s: %v", tt.name, err)
			testing.fail_now(t)
		}

		if len(tokens) != 2 {
			print_tokens(tt.input, tokens)
			testing.expectf(t, false, "%s: expected 2 tokens, got %d", tt.name, len(tokens))
			testing.fail_now(t)
		}

		if tokens[1].kind != .EOF {
			print_tokens(tt.input, tokens)
			testing.expectf(t, false, "%s: expected EOF token at end of input", tt.name)
			testing.fail_now(t)
		}

		tok := tokens[0]
		if tok.kind != .Literal {
			print_tokens(tt.input, tokens)
			testing.expectf(t, false, "%s: expected Literal, got %v", tt.name, tok.kind)
			testing.fail_now(t)
		}

		lexeme := tt.input[tok.lexeme_start:tok.lexeme_end]
		if lexeme != tt.expected_string {
			print_tokens(tt.input, tokens)
			testing.expectf(
				t,
				false,
				"%s: expected lexeme %q, got %q",
				tt.name,
				tt.expected_string,
				lexeme,
			)
			testing.fail_now(t)
		}
	}
}

@(test)
test_lexer_string_literal_kind :: proc(t: ^testing.T) {
	input := `"test"`

	lexer := Lexer{}
	init(&lexer)
	tokens, err := scan(&lexer, input)
	defer delete(tokens)
	if err != nil {
		print_tokens(input, tokens)
		testing.expectf(t, false, "unexpected error: %v", err)
		testing.fail_now(t)
	}

	if len(tokens) != 2 {
		print_tokens(input, tokens)
		testing.expectf(t, false, "expected 2 tokens, got %d", len(tokens))
		testing.fail_now(t)
	}

	if tokens[1].kind != .EOF {
		print_tokens(input, tokens)
		testing.expectf(t, false, "expected EOF token at end of input")
		testing.fail_now(t)
	}

	tok := tokens[0]
	if tok.literal_kind == nil {
		print_tokens(input, tokens)
		testing.expectf(t, false, "expected string token to have literal kind")
		testing.fail_now(t)
	}

	if tok.literal_kind != .String {
		print_tokens(input, tokens)
		testing.expectf(t, false, "expected String literal kind, got %v", tok.literal_kind)
		testing.fail_now(t)
	}
}

@(test)
test_lexer_numbers_and_dots :: proc(t: ^testing.T) {
	tests := []Test {
		{
			name = "empty dot",
			input = ".",
			expected = []syntax.Token_Kind{.Dot, .EOF},
			expect_error = false,
		},
		{
			name = "leading dot to an identifier",
			input = ".x",
			expected = []syntax.Token_Kind{.Dot, .Ident, .EOF},
			expect_error = false,
		},
		{
			name = "trailing dot",
			input = "x.",
			expected = []syntax.Token_Kind{.Ident, .Dot, .EOF},
			expect_error = false,
		},
		{
			name = "simple number",
			input = "42",
			expected = []syntax.Token_Kind{.Literal, .EOF},
			expect_error = false,
		},
		{
			name = "simple decimal",
			input = "42.0",
			expected = []syntax.Token_Kind{.Literal, .EOF},
			expect_error = false,
		},
		{
			name = "leading dot to a number",
			input = ".42",
			expected = []syntax.Token_Kind{.Literal, .EOF},
			expect_error = false,
		},
		{name = "multiple dots", input = "42.0.2", expected = {}, expect_error = true},
		{name = "multiple leading dots", input = "..42", expected = {}, expect_error = true},
		{name = "dots chaining", input = "42..0", expected = {}, expect_error = true},
		{name = "complex dots mixing", input = "..42.0", expected = {}, expect_error = true},
	}

	for tt in tests {
		lexer := Lexer{}
		init(&lexer)
		tokens, err := scan(&lexer, tt.input)
		defer delete(tokens)
		if tt.expect_error {
			if err == nil {
				print_tokens(tt.input, tokens)
				testing.expectf(t, false, "%s: expected error but got none", tt.name)
				testing.fail_now(t)
			}
			continue
		}

		if err != nil {
			print_tokens(tt.input, tokens)
			testing.expectf(t, false, "unexpected error in %s: %v", tt.name, err)
			testing.fail_now(t)
		}

		if len(tokens) != len(tt.expected) {
			print_tokens(tt.input, tokens)
			testing.expectf(
				t,
				false,
				"%s: expected %d tokens, got %d",
				tt.name,
				len(tt.expected),
				len(tokens),
			)
			testing.fail_now(t)
		}

		for expected_kind, i in tt.expected {
			if tokens[i].kind != expected_kind {
				print_tokens(tt.input, tokens)
				testing.expectf(
					t,
					false,
					"%s: token %d: expected kind %v, got %v",
					tt.name,
					i,
					expected_kind,
					tokens[i].kind,
				)
				testing.fail_now(t)
			}
		}
	}
}

@(test)
test_lexer_identifiers :: proc(t: ^testing.T) {
	tests := []Test {
		{name = "simple identifier", input = "foo", expected = []syntax.Token_Kind{.Ident, .EOF}},
		{
			name = "single letter identifier",
			input = "x",
			expected = []syntax.Token_Kind{.Ident, .EOF},
		},
		{
			name = "identifier with underscore",
			input = "camel_case",
			expected = []syntax.Token_Kind{.Ident, .EOF},
		},
		{
			name = "identifier with multiple underscores",
			input = "snake_case_name",
			expected = []syntax.Token_Kind{.Ident, .EOF},
		},
		{
			name = "identifier ending with underscore",
			input = "name_",
			expected = []syntax.Token_Kind{.Ident, .EOF},
		},
		{
			name = "identifier with consecutive underscores",
			input = "double__underscore",
			expected = []syntax.Token_Kind{.Ident, .EOF},
		},
		{
			name = "long identifier",
			input = "veryLongIdentifierNameThatGoesOnAndOn",
			expected = []syntax.Token_Kind{.Ident, .EOF},
		},
		{
			name = "uppercase identifier",
			input = "CONSTANT",
			expected = []syntax.Token_Kind{.Ident, .EOF},
		},
		{
			name = "mixed case identifier",
			input = "MixedCase",
			expected = []syntax.Token_Kind{.Ident, .EOF},
		},
		{
			name = "identifier followed by token",
			input = "name(",
			expected = []syntax.Token_Kind{.Ident, .Left_Paren, .EOF},
		},
		{
			name = "identifier followed by operator",
			input = "x=",
			expected = []syntax.Token_Kind{.Ident, .Equal, .EOF},
		},
		{
			name = "multiple identifiers",
			input = "foo bar",
			expected = []syntax.Token_Kind{.Ident, .Ident, .EOF},
		},
		{
			name = "identifier with newline",
			input = "name\n",
			expected = []syntax.Token_Kind{.Ident, .New_Line, .EOF},
		},
		{
			name = "identifier between braces",
			input = "{foo}",
			expected = []syntax.Token_Kind{.Left_Brace, .Ident, .Right_Brace, .EOF},
		},
	}

	for tt in tests {
		lexer := Lexer{}
		init(&lexer)
		tokens, err := scan(&lexer, tt.input)
		defer delete(tokens)
		if err != nil {
			print_tokens(tt.input, tokens)
			testing.expectf(t, false, "unexpected error in %s: %v", tt.name, err)
			testing.fail_now(t)
		}

		if len(tokens) != len(tt.expected) {
			print_tokens(tt.input, tokens)
			testing.expectf(
				t,
				false,
				"%s: expected %d tokens, got %d",
				tt.name,
				len(tt.expected),
				len(tokens),
			)
			testing.fail_now(t)
		}

		for expected_kind, i in tt.expected {
			if tokens[i].kind != expected_kind {
				print_tokens(tt.input, tokens)
				testing.expectf(
					t,
					false,
					"%s: token %d: expected kind %v, got %v",
					tt.name,
					i,
					expected_kind,
					tokens[i].kind,
				)
				testing.fail_now(t)
			}
		}
	}
}

@(test)
test_lexer_identifier_lexemes :: proc(t: ^testing.T) {
	tests := []Test {
		{
			name = "simple identifier lexeme",
			input = "tokenKind",
			expected_string = "tokenKind",
			expect_error = false,
		},
		{
			name = "identifier with underscore lexeme",
			input = "window_height",
			expected_string = "window_height",
			expect_error = false,
		},
		{
			name = "uppercase identifier lexeme",
			input = "SIZE",
			expected_string = "SIZE",
			expect_error = false,
		},
		{
			name = "underscore at the end",
			input = "x_",
			expected_string = "x_",
			expect_error = false,
		},
		{
			name = "identifier starts with underscore",
			input = "_x",
			expected_string = "_x",
			expect_error = false,
		},
		{
			name = "leading and ending with underscores",
			input = "__init__",
			expected_string = "__init__",
			expect_error = false,
		},
		{
			name = "identifiers with trailing numbers",
			input = "x123",
			expected_string = "x123",
			expect_error = false,
		},
		{
			name = "identifiers with numbers in the middle",
			input = "x34x",
			expected_string = "x34x",
			expect_error = false,
		},
		{
			name = "random characters in identifiers",
			input = "x::",
			expected_string = "x",
			expect_error = false,
		},
		{
			name = "identifiers with leading number",
			input = "1x",
			expected_string = "",
			expect_error = true,
		},
		{
			name = "identifiers with leading numbers",
			input = "123x",
			expected_string = "",
			expect_error = true,
		},
	}

	for tt in tests {
		lexer := Lexer{}
		init(&lexer)
		tokens, err := scan(&lexer, tt.input)
		defer delete(tokens)
		if tt.expect_error {
			if err == nil {
				print_tokens(tt.input, tokens)
				testing.expectf(t, false, "%s: expected error but got none", tt.name)
				testing.fail_now(t)
			}
			continue
		}

		if err != nil {
			print_tokens(tt.input, tokens)
			testing.expectf(t, false, "unexpected error in %s: %v", tt.name, err)
			testing.fail_now(t)
		}

		tok := tokens[0]
		if tok.kind != .Ident {
			print_tokens(tt.input, tokens)
			testing.expectf(t, false, "%s: expected Ident, got %v", tt.name, tok.kind)
			testing.fail_now(t)
		}

		lexeme := tt.input[tok.lexeme_start:tok.lexeme_end]
		if lexeme != tt.expected_string {
			print_tokens(tt.input, tokens)
			testing.expectf(
				t,
				false,
				"%s: expected lexeme %q, got %q",
				tt.name,
				tt.expected_string,
				lexeme,
			)
			testing.fail_now(t)
		}
	}
}

@(test)
test_lexer_keywords :: proc(t: ^testing.T) {
	tests := []Test {
		{
			name = "fn keyword",
			input = "fn",
			expected = []syntax.Token_Kind{.Keyword, .EOF},
			keyword_kind = .Fn,
		},
		{
			name = "fn keyword followed by identifier",
			input = "fn name",
			expected = []syntax.Token_Kind{.Keyword, .Ident, .EOF},
			keyword_kind = .Fn,
		},
		{
			name = "fn keyword in assignment",
			input = "x = fn()",
			expected = []syntax.Token_Kind {
				.Ident,
				.Equal,
				.Keyword,
				.Left_Paren,
				.Right_Paren,
				.EOF,
			},
			keyword_kind = .Fn,
		},
	}

	for tt in tests {
		lexer := Lexer{}
		init(&lexer)
		tokens, err := scan(&lexer, tt.input)
		defer delete(tokens)
		if err != nil {
			print_tokens(tt.input, tokens)
			testing.expectf(t, false, "unexpected error in %s: %v", tt.name, err)
			testing.fail_now(t)
		}

		if len(tokens) != len(tt.expected) {
			print_tokens(tt.input, tokens)
			testing.expectf(
				t,
				false,
				"%s: expected %d tokens, got %d",
				tt.name,
				len(tt.expected),
				len(tokens),
			)
			testing.fail_now(t)
		}

		for expected_kind, i in tt.expected {
			if tokens[i].kind != expected_kind {
				print_tokens(tt.input, tokens)
				testing.expectf(
					t,
					false,
					"%s: token %d: expected kind %v, got %v",
					tt.name,
					i,
					expected_kind,
					tokens[i].kind,
				)
				testing.fail_now(t)
			}
		}

		// Verify the first token is the keyword with correct keyword kind
		if tokens[0].kind == .Keyword {
			if tokens[0].keyword != tt.keyword_kind {
				print_tokens(tt.input, tokens)
				testing.expectf(
					t,
					false,
					"%s: expected keyword kind %v, got %v",
					tt.name,
					tt.keyword_kind,
					tokens[0].keyword,
				)
				testing.fail_now(t)
			}
		}
	}
}

@(test)
test_lexer_identifier_no_literal_kind :: proc(t: ^testing.T) {
	input := "myVariable"

	lexer := Lexer{}
	init(&lexer)
	tokens, err := scan(&lexer, input)
	defer delete(tokens)
	if err != nil {
		print_tokens(input, tokens)
		testing.expectf(t, false, "unexpected error: %v", err)
		testing.fail_now(t)
	}

	if len(tokens) != 2 {
		print_tokens(input, tokens)
		testing.expectf(t, false, "expected 2 tokens, got %d", len(tokens))
		testing.fail_now(t)
	}

	if tokens[1].kind != .EOF {
		print_tokens(input, tokens)
		testing.expectf(t, false, "expected EOF token at end of input")
		testing.fail_now(t)
	}

	tok := tokens[0]
	if tok.literal_kind != nil {
		print_tokens(input, tokens)
		testing.expectf(
			t,
			false,
			"expected identifier to have None literal kind, got %v",
			tok.literal_kind,
		)
		testing.fail_now(t)
	}
}

@(test)
test_lexer_keyword_no_literal_kind :: proc(t: ^testing.T) {
	input := "fn"

	lexer := Lexer{}
	init(&lexer)
	tokens, err := scan(&lexer, input)
	defer delete(tokens)
	if err != nil {
		print_tokens(input, tokens)
		testing.expectf(t, false, "unexpected error: %v", err)
		testing.fail_now(t)
	}

	if len(tokens) != 2 {
		print_tokens(input, tokens)
		testing.expectf(t, false, "expected 2 tokens, got %d", len(tokens))
		testing.fail_now(t)
	}

	if tokens[1].kind != .EOF {
		print_tokens(input, tokens)
		testing.expectf(t, false, "expected EOF token at end of input")
		testing.fail_now(t)
	}

	tok := tokens[0]
	if tok.literal_kind != nil {
		print_tokens(input, tokens)
		testing.expectf(
			t,
			false,
			"expected keyword to have None literal kind, got %v",
			tok.literal_kind,
		)
		testing.fail_now(t)
	}

	if tok.keyword != .Fn {
		print_tokens(input, tokens)
		testing.expectf(t, false, "expected keyword to be Fn, got %v", tok.keyword)
		testing.fail_now(t)
	}
}

@(test)
test_lexer_literal_kind :: proc(t: ^testing.T) {
	tests := []Test {
		{name = "left paren has no literal", input = "(", token_index = 0, has_literal = false},
		{name = "comment has no literal", input = "// test", token_index = 0, has_literal = false},
	}

	for tt in tests {
		lexer := Lexer{}
		init(&lexer)
		tokens, err := scan(&lexer, tt.input)
		defer delete(tokens)
		if err != nil {
			print_tokens(tt.input, tokens)
			testing.expectf(t, false, "unexpected error: %v", err)
			testing.fail_now(t)
		}

		if tt.token_index >= len(tokens) {
			print_tokens(tt.input, tokens)
			testing.expectf(
				t,
				false,
				"token index %d out of range (only %d tokens)",
				tt.token_index,
				len(tokens),
			)
			testing.fail_now(t)
		}

		tok := tokens[tt.token_index]
		has_literal := tok.literal_kind != nil

		if has_literal != tt.has_literal {
			print_tokens(tt.input, tokens)
			testing.expectf(
				t,
				false,
				"expected has_literal=%v, got has_literal=%v",
				tt.has_literal,
				has_literal,
			)
			testing.fail_now(t)
		}
	}
}

@(private = "file")
Test :: struct {
	name:            string,
	input:           string,
	expected:        []syntax.Token_Kind,
	expected_string: string,
	expect_error:    bool,
	keyword_kind:    syntax.Keyword,
	token_index:     int,
	has_literal:     bool,
}

