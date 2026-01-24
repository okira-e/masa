package lexer

import "core:testing"
import "../syntax"

@(test)
test_lexer_smoke :: proc(t: ^testing.T) {
	tests := []struct {
		name:     string,
		input:    string,
		expected: []syntax.Token_Kind,
	} {
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
	tests := []struct {
		name:     string,
		input:    string,
		expected: []syntax.Token_Kind,
	} {
		{name = "left parenthesis", input = "(", expected = []syntax.Token_Kind{.Left_Paren}},
		{name = "slash", input = "/", expected = []syntax.Token_Kind{.Slash}},
		{name = "newline", input = "\n", expected = []syntax.Token_Kind{.New_Line}},
		{name = "comment", input = "// hello", expected = []syntax.Token_Kind{.Comment}},
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
	tests := []struct {
		name:     string,
		input:    string,
		expected: []syntax.Token_Kind,
	} {
		{
			name = "parentheses pair",
			input = "()",
			expected = []syntax.Token_Kind{.Left_Paren, .Right_Paren},
		},
		{
			name = "mixed brackets",
			input = "({)}",
			expected = []syntax.Token_Kind{.Left_Paren, .Left_Brace, .Right_Paren, .Right_Brace},
		},
		{name = "slash and brace", input = "/}", expected = []syntax.Token_Kind{.Slash, .Right_Brace}},
		{
			name = "comment and newline",
			input = "// comment\n",
			expected = []syntax.Token_Kind{.Comment, .New_Line},
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
	tests := []struct {
		name:     string,
		input:    string,
		expected: []syntax.Token_Kind,
	} {
		{
			name = "spaces between tokens",
			input = "( )",
			expected = []syntax.Token_Kind{.Left_Paren, .Right_Paren},
		},
		{
			name = "tabs between tokens",
			input = "{\t}",
			expected = []syntax.Token_Kind{.Left_Brace, .Right_Brace},
		},
		{
			name = "carriage return ignored",
			input = "(\r)",
			expected = []syntax.Token_Kind{.Left_Paren, .Right_Paren},
		},
		{
			name = "multiple spaces",
			input = "(   )",
			expected = []syntax.Token_Kind{.Left_Paren, .Right_Paren},
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
	tests := []struct {
		name:     string,
		input:    string,
		expected: []syntax.Token_Kind,
	} {
		{name = "simple comment", input = "// Hi there hello", expected = []syntax.Token_Kind{.Comment}},
		{
			name = "comment with newline",
			input = "// comment\n",
			expected = []syntax.Token_Kind{.Comment, .New_Line},
		},
		{
			name = "multiple comments",
			input = "// first\n// second",
			expected = []syntax.Token_Kind{.Comment, .New_Line, .Comment},
		},
		{
			name = "comment after token",
			input = "{ // comment",
			expected = []syntax.Token_Kind{.Left_Brace, .Comment},
		},
		{name = "empty comment", input = "//", expected = []syntax.Token_Kind{.Comment}},
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

	for tok, i in tokens {
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

	if len(tokens) != 0 {
		print_tokens(input, tokens)
		testing.expectf(t, false, "expected 0 tokens for empty input, got %d", len(tokens))
		testing.fail_now(t)
	}
}

@(test)
test_lexer_declaration_and_assignment :: proc(t: ^testing.T) {
	tests := []struct {
		name:     string,
		input:    string,
		expected: []syntax.Token_Kind,
	} {
		{name = "assignment equal", input = "=", expected = []syntax.Token_Kind{.Equal}},
		{name = "equal equal comparison", input = "==", expected = []syntax.Token_Kind{.Equal_Equal}},
		{name = "declarative assignment", input = ":=", expected = []syntax.Token_Kind{.Colon_Equal}},
		{
			name = "comptime declarative assignment",
			input = "::",
			expected = []syntax.Token_Kind{.Colon_Colon},
		},
		{
			name = "variable runtime declarative assignment",
			input = "x := 5",
			expected = []syntax.Token_Kind{.Ident, .Colon_Equal, .Literal},
		},
		{
			name = "variable comptime declarative assignment",
			input = "main :: fn",
			expected = []syntax.Token_Kind{.Ident, .Colon_Colon, .Keyword},
		},
		{
			name = "variable assignment",
			input = "x = 10",
			expected = []syntax.Token_Kind{.Ident, .Equal, .Literal},
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
	tests := []struct {
		name:     string,
		input:    string,
		expected: []syntax.Token_Kind,
	} {
		{name = "bang equal", input = "!=", expected = []syntax.Token_Kind{.Bang_Equal}},
		{name = "bang alone", input = "!", expected = []syntax.Token_Kind{.Bang}},
		{name = "bang not followed by equal", input = "!x", expected = []syntax.Token_Kind{.Bang}},
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
	tests := []struct {
		name:         string,
		input:        string,
		expect_error: bool,
		expected:     []syntax.Token_Kind,
	} {
		{
			name = "empty string",
			input = `""`,
			expect_error = false,
			expected = []syntax.Token_Kind{.Literal},
		},
		{
			name = "simple string",
			input = `"hello"`,
			expect_error = false,
			expected = []syntax.Token_Kind{.Literal},
		},
		{
			name = "string with spaces",
			input = `"hello world"`,
			expect_error = false,
			expected = []syntax.Token_Kind{.Literal},
		},
		{
			name = "string with special characters",
			input = `"!@#$%^&*()"`,
			expect_error = false,
			expected = []syntax.Token_Kind{.Literal},
		},
		{
			name = "string with numbers",
			input = `"123456"`,
			expect_error = false,
			expected = []syntax.Token_Kind{.Literal},
		},
		{
			name = "string with mixed content",
			input = `"Hello123!@#"`,
			expect_error = false,
			expected = []syntax.Token_Kind{.Literal},
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
			expected = []syntax.Token_Kind{.Literal, .Literal},
		},
		{
			name = "string followed by tokens",
			input = `"hello"()`,
			expect_error = false,
			expected = []syntax.Token_Kind{.Literal, .Left_Paren, .Right_Paren},
		},
		{
			name = "tokens followed by string",
			input = `()"world"`,
			expect_error = false,
			expected = []syntax.Token_Kind{.Left_Paren, .Right_Paren, .Literal},
		},
		{
			name = "string with tabs",
			input = "\"hello\tworld\"",
			expect_error = false,
			expected = []syntax.Token_Kind{.Literal},
		},
		{
			name = "string with only spaces",
			input = `"   "`,
			expect_error = false,
			expected = []syntax.Token_Kind{.Literal},
		},
		{
			name = "string at start of input",
			input = `"start" {}`,
			expect_error = false,
			expected = []syntax.Token_Kind{.Literal, .Left_Brace, .Right_Brace},
		},
		{
			name = "string at end of input",
			input = `{} "end"`,
			expect_error = false,
			expected = []syntax.Token_Kind{.Left_Brace, .Right_Brace, .Literal},
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
	tests := []struct {
		name:     string,
		input:    string,
		expected: string,
	} {
		{name = "simple string lexeme", input = `"hello"`, expected = `"hello"`},
		{name = "string with spaces lexeme", input = `"hello world"`, expected = `"hello world"`},
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

		if len(tokens) != 1 {
			print_tokens(tt.input, tokens)
			testing.expectf(t, false, "%s: expected 1 token, got %d", tt.name, len(tokens))
			testing.fail_now(t)
		}

		tok := tokens[0]
		if tok.kind != .Literal {
			print_tokens(tt.input, tokens)
			testing.expectf(t, false, "%s: expected Literal, got %v", tt.name, tok.kind)
			testing.fail_now(t)
		}

		lexeme := tt.input[tok.lexeme_start:tok.lexeme_end]
		if lexeme != tt.expected {
			print_tokens(tt.input, tokens)
			testing.expectf(
				t,
				false,
				"%s: expected lexeme %q, got %q",
				tt.name,
				tt.expected,
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

	if len(tokens) != 1 {
		print_tokens(input, tokens)
		testing.expectf(t, false, "expected 1 token, got %d", len(tokens))
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
	tests := []struct {
		name:         string,
		input:        string,
		expected:     []syntax.Token_Kind,
		expect_error: bool,
	} {
		{name = "empty dot", input = ".", expected = []syntax.Token_Kind{.Dot}, expect_error = false},
		{
			name = "leading dot to an identifier",
			input = ".x",
			expected = []syntax.Token_Kind{.Dot, .Ident},
			expect_error = false,
		},
		{
			name = "trailing dot",
			input = "x.",
			expected = []syntax.Token_Kind{.Ident, .Dot},
			expect_error = false,
		},
		{
			name = "simple number",
			input = "42",
			expected = []syntax.Token_Kind{.Literal},
			expect_error = false,
		},
		{
			name = "simple decimal",
			input = "42.0",
			expected = []syntax.Token_Kind{.Literal},
			expect_error = false,
		},
		{
			name = "leading dot to a number",
			input = ".42",
			expected = []syntax.Token_Kind{.Literal},
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
	tests := []struct {
		name:     string,
		input:    string,
		expected: []syntax.Token_Kind,
	} {
		{name = "simple identifier", input = "foo", expected = []syntax.Token_Kind{.Ident}},
		{name = "single letter identifier", input = "x", expected = []syntax.Token_Kind{.Ident}},
		{
			name = "identifier with underscore",
			input = "camel_case",
			expected = []syntax.Token_Kind{.Ident},
		},
		{
			name = "identifier with multiple underscores",
			input = "snake_case_name",
			expected = []syntax.Token_Kind{.Ident},
		},
		{
			name = "identifier ending with underscore",
			input = "name_",
			expected = []syntax.Token_Kind{.Ident},
		},
		{
			name = "identifier with consecutive underscores",
			input = "double__underscore",
			expected = []syntax.Token_Kind{.Ident},
		},
		{
			name = "long identifier",
			input = "veryLongIdentifierNameThatGoesOnAndOn",
			expected = []syntax.Token_Kind{.Ident},
		},
		{name = "uppercase identifier", input = "CONSTANT", expected = []syntax.Token_Kind{.Ident}},
		{name = "mixed case identifier", input = "MixedCase", expected = []syntax.Token_Kind{.Ident}},
		{
			name = "identifier followed by token",
			input = "name(",
			expected = []syntax.Token_Kind{.Ident, .Left_Paren},
		},
		{
			name = "identifier followed by operator",
			input = "x=",
			expected = []syntax.Token_Kind{.Ident, .Equal},
		},
		{
			name = "multiple identifiers",
			input = "foo bar",
			expected = []syntax.Token_Kind{.Ident, .Ident},
		},
		{
			name = "identifier with newline",
			input = "name\n",
			expected = []syntax.Token_Kind{.Ident, .New_Line},
		},
		{
			name = "identifier between braces",
			input = "{foo}",
			expected = []syntax.Token_Kind{.Left_Brace, .Ident, .Right_Brace},
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
	tests := []struct {
		name:         string,
		input:        string,
		expected:     string,
		expect_error: bool,
	} {
		{
			name = "simple identifier lexeme",
			input = "tokenKind",
			expected = "tokenKind",
			expect_error = false,
		},
		{
			name = "identifier with underscore lexeme",
			input = "window_height",
			expected = "window_height",
			expect_error = false,
		},
		{
			name = "uppercase identifier lexeme",
			input = "SIZE",
			expected = "SIZE",
			expect_error = false,
		},
		{name = "underscore at the end", input = "x_", expected = "x_", expect_error = false},
		{
			name = "identifier starts with underscore",
			input = "_x",
			expected = "_x",
			expect_error = false,
		},
		{
			name = "leading and ending with underscores",
			input = "__init__",
			expected = "__init__",
			expect_error = false,
		},
		{
			name = "identifiers with trailing numbers",
			input = "x123",
			expected = "x123",
			expect_error = false,
		},
		{
			name = "identifiers with numbers in the middle",
			input = "x34x",
			expected = "x34x",
			expect_error = false,
		},
		{
			name = "random characters in identifiers",
			input = "x::",
			expected = "x",
			expect_error = false,
		},
		{
			name = "identifiers with leading number",
			input = "1x",
			expected = "",
			expect_error = true,
		},
		{
			name = "identifiers with leading numbers",
			input = "123x",
			expected = "",
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
		if lexeme != tt.expected {
			print_tokens(tt.input, tokens)
			testing.expectf(
				t,
				false,
				"%s: expected lexeme %q, got %q",
				tt.name,
				tt.expected,
				lexeme,
			)
			testing.fail_now(t)
		}
	}
}

@(test)
test_lexer_keywords :: proc(t: ^testing.T) {
	tests := []struct {
		name:         string,
		input:        string,
		expected:     []syntax.Token_Kind,
		keyword_kind: syntax.Keyword,
	} {
		{name = "fn keyword", input = "fn", expected = []syntax.Token_Kind{.Keyword}, keyword_kind = .Fn},
		{
			name = "fn keyword followed by identifier",
			input = "fn name",
			expected = []syntax.Token_Kind{.Keyword, .Ident},
			keyword_kind = .Fn,
		},
		{
			name = "fn keyword in assignment",
			input = "x = fn()",
			expected = []syntax.Token_Kind{.Ident, .Equal, .Keyword, .Left_Paren, .Right_Paren},
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

	if len(tokens) != 1 {
		print_tokens(input, tokens)
		testing.expectf(t, false, "expected 1 token, got %d", len(tokens))
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

	if len(tokens) != 1 {
		print_tokens(input, tokens)
		testing.expectf(t, false, "expected 1 token, got %d", len(tokens))
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
	tests := []struct {
		name:        string,
		input:       string,
		token_index: int,
		has_literal: bool,
	} {
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
