package lexer

import "../syntax"
import "core:fmt"
import "core:mem"
import "core:strings"
import "core:unicode"

Lexer :: struct {
	allocator:         mem.Allocator,
	current:           int,
	line:              int,
	column:            int,
	last_lexeme_start: int,
}

init :: proc(l: ^Lexer, allocator := context.allocator) {
	l.current = 0
	l.line = 0
	l.column = 0
	l.last_lexeme_start = 0
	l.allocator = allocator
}

scan :: proc(l: ^Lexer, source: string) -> ([dynamic]syntax.Token, Maybe(Lexer_Error)) {
	tokens := make([dynamic]syntax.Token, 0, len(source) / 4, allocator = l.allocator)
	l.line += 1

	err: Maybe(Lexer_Error) = nil
	for l.current < len(source) {
		b := source[l.current]

		l.column += 1
		l.last_lexeme_start = l.current

		switch b {
		case '\n':
			new_token := make_token(l, l.current, .New_Line, nil, nil)
			append(&tokens, new_token)
			l.line += 1
			l.column = 0

		case ' ', '\r', '\t':
		case '(':
			new_token := make_token(l, l.current, .Left_Paren, nil, nil)
			append(&tokens, new_token)

		case ')':
			new_token := make_token(l, l.current, .Right_Paren, nil, nil)
			append(&tokens, new_token)

		case '{':
			new_token := make_token(l, l.current, .Left_Brace, nil, nil)
			append(&tokens, new_token)

		case '}':
			new_token := make_token(l, l.current, .Right_Brace, nil, nil)
			append(&tokens, new_token)

		case ',':
			new_token := make_token(l, l.current, .Comma, nil, nil)
			append(&tokens, new_token)

		case '-':
			new_token := make_token(l, l.current, .Minus, nil, nil)
			append(&tokens, new_token)

		case '+':
			new_token := make_token(l, l.current, .Plus, nil, nil)
			append(&tokens, new_token)

		case '*':
			new_token := make_token(l, l.current, .Star, nil, nil)
			append(&tokens, new_token)

		case '!':
			next, ok := peek_next(l, source)
			if ok && next == '=' {
				new_token := make_token(l, l.current, .Bang_Equal, nil, nil)
				append(&tokens, new_token)

				l.current += 1
				l.column += 1
			} else {
				new_token := make_token(l, l.current, .Bang, nil, nil)
				append(&tokens, new_token)
			}

		case ':':
			next, ok := peek_next(l, source)
			if ok && next == '=' {
				new_token := make_token(l, l.current, .Colon_Equal, nil, nil)
				append(&tokens, new_token)

				l.current += 1
				l.column += 1
			} else if ok && next == ':' {
				new_token := make_token(l, l.current, .Colon_Colon, nil, nil)
				append(&tokens, new_token)

				l.current += 1
				l.column += 1
			} else {
				new_token := make_token(l, l.current, .Colon, nil, nil)
				append(&tokens, new_token)
			}

		case '/':
			next, ok := peek_next(l, source)
			if ok && next == '/' {
				// Keep advancing until a newline or end of input
				skips := 0
				for {
					l.current += 1
					skips += 1

					next, ok := peek_next(l, source)
					if !ok || next == '\n' {
						break
					}
				}

				new_token := make_token(l, l.current, .Comment, nil, nil)
				append(&tokens, new_token)
				l.column += skips
			} else {
				new_token := make_token(l, l.current, .Slash, nil, nil)
				append(&tokens, new_token)
			}

		case '=':
			next, ok := peek_next(l, source)
			if ok && next == '=' {
				new_token := make_token(l, l.current, .Equal_Equal, nil, nil)
				append(&tokens, new_token)
				l.current += 1
				l.column += 1
			} else {
				new_token := make_token(l, l.current, .Equal, nil, nil)
				append(&tokens, new_token)
			}

		case '<':
			next, ok := peek_next(l, source)
			if ok && next == '=' {
				new_token := make_token(l, l.current, .Less_Equal, nil, nil)
				append(&tokens, new_token)
				l.current += 1
				l.column += 1
			} else {
				new_token := make_token(l, l.current, .Less, nil, nil)
				append(&tokens, new_token)
			}

		case '>':
			next, ok := peek_next(l, source)
			if ok && next == '=' {
				new_token := make_token(l, l.current, .Greater_Equal, nil, nil)
				append(&tokens, new_token)
				l.current += 1
				l.column += 1
			} else {
				new_token := make_token(l, l.current, .Greater, nil, nil)
				append(&tokens, new_token)
			}

		case '"':
			// @TODO: do escapes and shit
			next, ok := peek_next(l, source)
			if !ok || next == '\n' {
				err = make_error(l, .Unterminated_String_Literal)
				break
			}

			skips := 0
			l.current += 1 // Move to first char in the string
			if source[l.current] != '"' { 	// String is not empty
				for {
					next, ok := peek_next(l, source)
					if !ok || next == '\n' {
						err = make_error(l, .Unterminated_String_Literal)
						break
					}

					if ok && next == '"' {
						// Move off it
						l.current += 1
						skips += 1
						break
					}

					l.current += 1
					skips += 1
				}
				if err != nil {
					break
				}
			}

			new_token := make_token(l, l.current, .Literal, .String, nil)
			append(&tokens, new_token)
			l.column += skips

		// numbers/words
		case:
			if unicode.is_digit(rune(b)) || b == '.' { 	// Number literal
				// Check if this is a dot, a beginning of a floating point number, or an illegal
				// identifier name that starts with a number
				next, ok := peek_next(l, source)
				if b == '.' &&
				   (!ok || (ok && (!unicode.is_digit(rune(next)) && next != '.'))) {
					new_token := make_token(l, l.current, .Dot, nil, nil)
					append(&tokens, new_token)
				} else if ok && unicode.is_letter(rune(next)) {
					err = make_error(l, .Ident_Starts_With_Number)
					break
				} else {
					dot_found := false // Make sure only one dot is scanned for each number
					if b == '.' {
						dot_found = true
					}

					skips := 0
					if ok && (unicode.is_digit(rune(next)) || next == '.') {
						for {
							next, ok := peek_next(l, source)
							if ok && unicode.is_letter(rune(next)) {
								err = make_error(l, .Ident_Starts_With_Number)
								break
							}

							if !ok || (!unicode.is_digit(rune(next)) && next != '.') {
								break
							}

							if ok && next == '.' {
								if dot_found {
									err = make_error(l, .Number_Literal_Dots_Count)
									break
								} else {
									dot_found = true
								}
							}

							l.current += 1
							skips += 1
						}
					}
					if err != nil {
						break
					}

					new_token := make_token(l, l.current, .Literal, .Number, nil)
					append(&tokens, new_token)
					l.column += skips
				}
			} else if unicode.is_letter(rune(b)) || b == '_' { 	// Identifier or an internal keyword
				skips := 0

				next, ok := peek_next(l, source)
				if ok &&
				   (
					   unicode.is_letter(rune(next)) ||
					   next == '_' ||
					   unicode.is_digit(rune(next))
					)
			   {
					for {
						next, ok := peek_next(l, source)
						if !ok ||
						   (!unicode.is_letter(rune(next)) &&
								   next != '_' &&
								   !unicode.is_digit(rune(next))) {
							break
						}

						l.current += 1
						skips += 1
					}
				}

				// Decide if it's a reserved keyword or an identifier name or special literal

				token_kind: syntax.Token_Kind = .Ident

				lexeme := string(source[l.last_lexeme_start:l.current + 1])

				keyword := syntax.keyword_from_string(lexeme)
				if keyword != nil {
					token_kind = .Keyword
				}
				
				literal_kind: Maybe(syntax.Literal_Kind) = nil
				if lexeme == "false" {
					token_kind = .Literal
					literal_kind = .Bool
				} else if lexeme == "true" {
					token_kind = .Literal
					literal_kind = .Bool
				}

				new_token := make_token(l, l.current, token_kind, literal_kind, keyword)
				append(&tokens, new_token)
				l.column += skips
			} else {
				err = make_error(l, .Unrecognized_Token)
				break
			}
		}

		l.current += 1
	}

	append(&tokens, syntax.Token{
		line         = l.line,
		column       = l.column,
		lexeme_start = len(source),
		lexeme_end   = len(source),
		kind         = .EOF,
	})

	return tokens, err
}

/// make_token constructs a token with the current state of the l instance
make_token :: proc(
	l: ^Lexer,
	current: int,
	kind: syntax.Token_Kind,
	literal_kind: Maybe(syntax.Literal_Kind),
	keyword: Maybe(syntax.Keyword),
) -> syntax.Token {
	return syntax.Token {
		kind = kind,
		lexeme_start = l.last_lexeme_start,
		lexeme_end = current + 1,
		line = l.line,
		column = l.column,
		literal_kind = literal_kind,
		keyword = keyword,
	}
}

// shows you the next byte without advancing the cursor
peek_next :: proc(l: ^Lexer, source: string) -> (byte, bool) {
	if l.current >= len(source) - 1 {
		return 0, false
	}

	return source[l.current + 1], true
}

Lexer_Error :: struct {
	kind:         Lexer_Error_Kind,
	lexeme_start: int,
	lexeme_end:   int,
}

Lexer_Error_Kind :: enum {
	Unterminated_String_Literal,
	Ident_Starts_With_Number,
	Number_Literal_Dots_Count,
	Unrecognized_Token,
}

@(private)
make_error :: proc(l: ^Lexer, kind: Lexer_Error_Kind) -> Lexer_Error {
	return Lexer_Error {
		kind         = kind,
		lexeme_start = l.last_lexeme_start,
		lexeme_end   = l.current + 1,
	}
}

@(private)
error_text :: proc(kind: Lexer_Error_Kind) -> (string, string) {
	switch kind {
	case .Unterminated_String_Literal:
		return "unterminated string literal", "string is missing a closing quote"
		
	case .Ident_Starts_With_Number:
		return "identifier cannot start with a digit", "rename to start with a letter or underscore"
		
	case .Number_Literal_Dots_Count:
		return "number literal has more than one decimal point", "use a single '.' for the decimal"
		
	case .Unrecognized_Token:
		return "token is not recognized", ""
	}

	return "", ""
}

format_error :: proc(err: Lexer_Error, source: string, allocator := context.allocator) -> string {
	start := clamp(err.lexeme_start, 0, len(source))
	end   := clamp(err.lexeme_end,   start, len(source))

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
	headline, hint := error_text(err.kind)

	b: strings.Builder
	strings.builder_init(&b, allocator)

	fmt.sbprintf(&b, "error: %s\n", headline)
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
	write_repeat(&b, ' ', column - 1)
	write_repeat(&b, '^', caret_count)
	if hint != "" {
		strings.write_byte(&b, ' ')
		strings.write_string(&b, hint)
	}
	strings.write_byte(&b, '\n')

	return strings.to_string(b) // @allocation
}

@(private)
write_repeat :: proc(b: ^strings.Builder, c: byte, n: int) {
	for _ in 0..<n do strings.write_byte(b, c)
}
