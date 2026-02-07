package lexer

import "../syntax"
import "core:mem"
import "core:unicode"

Lexer :: struct {
	alloc:             mem.Allocator,
	current:           int,
	line:              int,
	column:            int,
	last_lexeme_start: int,
}

init :: proc(lexer: ^Lexer, alloc: mem.Allocator = context.allocator) {
	lexer.current = 0
	lexer.line = 0
	lexer.column = 0
	lexer.last_lexeme_start = 0
	lexer.alloc = alloc
}

scan :: proc(lexer: ^Lexer, source: string) -> ([dynamic]syntax.Token, Maybe(Lexer_Error)) {
	tokens := make([dynamic]syntax.Token, 0, len(source) / 4, lexer.alloc)
	lexer.line += 1

	err: Maybe(Lexer_Error) = nil
	for lexer.current < len(source) {
		b := source[lexer.current]

		lexer.column += 1
		lexer.last_lexeme_start = lexer.current

		switch b {
		case '\n':
			{
				new_token := make_token(lexer, lexer.current, .New_Line, nil, nil)
				append(&tokens, new_token)
				lexer.line += 1
				lexer.column = 0
			}
		case ' ', '\r', '\t':
			{
			}
		case '(':
			{
				new_token := make_token(lexer, lexer.current, .Left_Paren, nil, nil)
				append(&tokens, new_token)
			}
		case ')':
			{
				new_token := make_token(lexer, lexer.current, .Right_Paren, nil, nil)
				append(&tokens, new_token)
			}
		case '{':
			{
				new_token := make_token(lexer, lexer.current, .Left_Brace, nil, nil)
				append(&tokens, new_token)
			}
		case '}':
			{
				new_token := make_token(lexer, lexer.current, .Right_Brace, nil, nil)
				append(&tokens, new_token)
			}
		case ',':
			{
				new_token := make_token(lexer, lexer.current, .Comma, nil, nil)
				append(&tokens, new_token)
			}
		case '-':
			{
				new_token := make_token(lexer, lexer.current, .Minus, nil, nil)
				append(&tokens, new_token)
			}
		case '+':
			{
				new_token := make_token(lexer, lexer.current, .Plus, nil, nil)
				append(&tokens, new_token)
			}
		case '*':
			{
				new_token := make_token(lexer, lexer.current, .Star, nil, nil)
				append(&tokens, new_token)
			}
		case '!':
			{
				next, ok := peek_next(lexer, source)
				if ok && next == '=' {
					new_token := make_token(lexer, lexer.current, .Bang_Equal, nil, nil)
					append(&tokens, new_token)

					lexer.current += 1
					lexer.column += 1
				} else {
					new_token := make_token(lexer, lexer.current, .Bang, nil, nil)
					append(&tokens, new_token)
				}
			}
		case ':':
			{
				next, ok := peek_next(lexer, source)
				if ok && next == '=' {
					new_token := make_token(lexer, lexer.current, .Colon_Equal, nil, nil)
					append(&tokens, new_token)

					lexer.current += 1
					lexer.column += 1
				} else if ok && next == ':' {
					new_token := make_token(lexer, lexer.current, .Colon_Colon, nil, nil)
					append(&tokens, new_token)

					lexer.current += 1
					lexer.column += 1
				} else {
					new_token := make_token(lexer, lexer.current, .Colon, nil, nil)
					append(&tokens, new_token)
				}
			}
		case '/':
			{
				next, ok := peek_next(lexer, source)
				if ok && next == '/' {
					// Keep advancing until a newline or end of input
					skips := 0
					for {
						lexer.current += 1
						skips += 1

						next, ok := peek_next(lexer, source)
						if !ok || next == '\n' {
							break
						}
					}

					new_token := make_token(lexer, lexer.current, .Comment, nil, nil)
					append(&tokens, new_token)
					lexer.column += skips
				} else {
					new_token := make_token(lexer, lexer.current, .Slash, nil, nil)
					append(&tokens, new_token)
				}
			}
		case '=':
			{
				next, ok := peek_next(lexer, source)
				if ok && next == '=' {
					new_token := make_token(lexer, lexer.current, .Equal_Equal, nil, nil)
					append(&tokens, new_token)
					lexer.current += 1
					lexer.column += 1
				} else {
					new_token := make_token(lexer, lexer.current, .Equal, nil, nil)
					append(&tokens, new_token)
				}
			}
		case '<':
			{
				next, ok := peek_next(lexer, source)
				if ok && next == '=' {
					new_token := make_token(lexer, lexer.current, .Less_Equal, nil, nil)
					append(&tokens, new_token)
					lexer.current += 1
					lexer.column += 1
				} else {
					new_token := make_token(lexer, lexer.current, .Less, nil, nil)
					append(&tokens, new_token)
				}
			}
		case '>':
			{
				next, ok := peek_next(lexer, source)
				if ok && next == '=' {
					new_token := make_token(lexer, lexer.current, .Greater_Equal, nil, nil)
					append(&tokens, new_token)
					lexer.current += 1
					lexer.column += 1
				} else {
					new_token := make_token(lexer, lexer.current, .Greater, nil, nil)
					append(&tokens, new_token)
				}
			}

		case '"':
			{
				// @TODO: do escapes and shit
				next, ok := peek_next(lexer, source)
				if !ok || next == '\n' {
					err = .Unterminated_String_Literal
					break
				}

				skips := 0
				lexer.current += 1 // Move to first char in the string
				if source[lexer.current] != '"' { 	// String is not empty
					for {
						next, ok := peek_next(lexer, source)
						if !ok || next == '\n' {
							err = .Unterminated_String_Literal
							break
						}

						if ok && next == '"' {
							// Move off it
							lexer.current += 1
							skips += 1
							break
						}

						lexer.current += 1
						skips += 1
					}
					if err != nil {
						break
					}
				}

				new_token := make_token(lexer, lexer.current, .Literal, .String, nil)
				append(&tokens, new_token)
				lexer.column += skips
			}
		// numbers/words
		case:
			{
				if unicode.is_digit(rune(b)) || b == '.' { 	// Number literal
					// Check if this is a dot, a beginning of a floating point number, or an illegal
					// identifier name that starts with a number
					next, ok := peek_next(lexer, source)
					if b == '.' &&
					   (!ok || (ok && (!unicode.is_digit(rune(next)) && next != '.'))) {
						new_token := make_token(lexer, lexer.current, .Dot, nil, nil)
						append(&tokens, new_token)
					} else if ok && unicode.is_letter(rune(next)) {
						err = .Ident_Starts_With_Number
						break
					} else {
						dot_found := false // Make sure only one dot is scanned for each number
						if b == '.' {
							dot_found = true
						}

						skips := 0
						if ok && (unicode.is_digit(rune(next)) || next == '.') {
							for {
								next, ok := peek_next(lexer, source)
								if ok && unicode.is_letter(rune(next)) {
									err = .Ident_Starts_With_Number
									break
								}

								if !ok || (!unicode.is_digit(rune(next)) && next != '.') {
									break
								}

								if ok && next == '.' {
									if dot_found {
										err = .Number_Literal_Dots_Count
										break
									} else {
										dot_found = true
									}
								}

								lexer.current += 1
								skips += 1
							}
						}
						if err != nil {
							break
						}

						new_token := make_token(lexer, lexer.current, .Literal, .Number, nil)
						append(&tokens, new_token)
						lexer.column += skips
					}
				} else if unicode.is_letter(rune(b)) || b == '_' { 	// Identifier or an internal keyword
					skips := 0

					next, ok := peek_next(lexer, source)
					if ok &&
					   (unicode.is_letter(rune(next)) ||
							   next == '_' ||
							   unicode.is_digit(rune(next))) {
						for {
							next, ok := peek_next(lexer, source)
							if !ok ||
							   (!unicode.is_letter(rune(next)) &&
									   next != '_' &&
									   !unicode.is_digit(rune(next))) {
								break
							}

							lexer.current += 1
							skips += 1
						}
					}

					// Decide if it's a reserved keyword or an identifier name

					token_kind: syntax.Token_Kind = .Ident

					lexeme := string(source[lexer.last_lexeme_start:lexer.current + 1])
					keyword := syntax.keyword_from_string(lexeme)
					if keyword != nil {
						token_kind = .Keyword
					}

					new_token := make_token(lexer, lexer.current, token_kind, nil, keyword)
					append(&tokens, new_token)
					lexer.column += skips
				}
			}
		}

		lexer.current += 1
	}

	// append(&tokens, syntax.Token{line = lexer.line, kind = .EOF}) // Don't think this is needed yet

	return tokens, err
}

/// make_token constructs a token with the current state of the lexer instance
make_token :: proc(
	lexer: ^Lexer,
	current: int,
	kind: syntax.Token_Kind,
	literal_kind: Maybe(syntax.Literal_Kind),
	keyword: Maybe(syntax.Keyword),
) -> syntax.Token {
	return syntax.Token {
		kind = kind,
		lexeme_start = lexer.last_lexeme_start,
		lexeme_end = current + 1,
		line = lexer.line,
		column = lexer.column,
		literal_kind = literal_kind,
		keyword = keyword,
	}
}

// shows you the next byte without advancing the cursor
peek_next :: proc(lexer: ^Lexer, source: string) -> (byte, bool) {
	if lexer.current >= len(source) - 1 {
		return 0, false
	}

	return source[lexer.current + 1], true
}

Lexer_Error :: enum {
	Unterminated_String_Literal,
	Ident_Starts_With_Number,
	Number_Literal_Dots_Count,
}

lexer_error_to_string :: proc(err: Lexer_Error) -> string {
	switch err {
	case .Unterminated_String_Literal:
		return "unterminated string literal"
	case .Ident_Starts_With_Number:
		return "identifier names cannot start with a number"
	case .Number_Literal_Dots_Count:
		return "invalid number literal with multiple dots"
	}

	return ""
}
