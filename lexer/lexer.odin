package lexer

import "core:fmt"
import "core:unicode"

Lexer :: struct {
	current:           int,
	line:              int,
	column:            int,
	last_lexeme_start: int,
}

init :: proc(lxr: ^Lexer) {
	lxr.current = 0
	lxr.line = 0
	lxr.column = 0
	lxr.last_lexeme_start = 0
}

scan :: proc(lxr: ^Lexer, source: string) -> ([dynamic]Token, Maybe(Lexer_Error)) {
	tokens := [dynamic]Token{}
	lxr.line += 1

	err: Maybe(Lexer_Error) = nil
	for lxr.current < len(source) {
		b := source[lxr.current]

		lxr.column += 1
		lxr.last_lexeme_start = lxr.current

		switch b {
		case '\n':
			{
				new_token := make_token(lxr, lxr.current, .New_Line, nil, nil)
				append(&tokens, new_token)
				lxr.line += 1
				lxr.column = 0
			}
		case ' ', '\r', '\t':
			{
			}
		case '(':
			{
				new_token := make_token(lxr, lxr.current, .Left_Paren, nil, nil)
				append(&tokens, new_token)
			}
		case ')':
			{
				new_token := make_token(lxr, lxr.current, .Right_Paren, nil, nil)
				append(&tokens, new_token)
			}
		case '{':
			{
				new_token := make_token(lxr, lxr.current, .Left_Brace, nil, nil)
				append(&tokens, new_token)
			}
		case '}':
			{
				new_token := make_token(lxr, lxr.current, .Right_Brace, nil, nil)
				append(&tokens, new_token)
			}
		case ',':
			{
				new_token := make_token(lxr, lxr.current, .Comma, nil, nil)
				append(&tokens, new_token)
			}
		case '-':
			{
				new_token := make_token(lxr, lxr.current, .Minus, nil, nil)
				append(&tokens, new_token)
			}
		case '+':
			{
				new_token := make_token(lxr, lxr.current, .Plus, nil, nil)
				append(&tokens, new_token)
			}
		case '*':
			{
				new_token := make_token(lxr, lxr.current, .Star, nil, nil)
				append(&tokens, new_token)
			}
		case '!':
			{
				next, ok := peek(lxr, source)
				if ok && next == '=' {
					new_token := make_token(lxr, lxr.current, .Bang_Equal, nil, nil)
					append(&tokens, new_token)

					lxr.current += 1
					lxr.column += 1
				} else {
					new_token := make_token(lxr, lxr.current, .Bang, nil, nil)
					append(&tokens, new_token)
				}
			}
		case ':':
			{
				next, ok := peek(lxr, source)
				if ok && next == '=' {
					new_token := make_token(lxr, lxr.current, .Colon_Equal, nil, nil)
					append(&tokens, new_token)

					lxr.current += 1
					lxr.column += 1
				} else if ok && next == ':' {
					new_token := make_token(lxr, lxr.current, .Colon_Colon, nil, nil)
					append(&tokens, new_token)

					lxr.current += 1
					lxr.column += 1
				} else {
					new_token := make_token(lxr, lxr.current, .Colon, nil, nil)
					append(&tokens, new_token)
				}
			}
		case '/':
			{
				next, ok := peek(lxr, source)
				if ok && next == '/' {
					// Keep advancing until a newline or end of input
					skips := 0
					for {
						lxr.current += 1
						skips += 1

						next, ok := peek(lxr, source)
						if !ok || next == '\n' {
							break
						}
					}

					new_token := make_token(lxr, lxr.current, .Comment, nil, nil)
					append(&tokens, new_token)
					lxr.column += skips
				} else {
					new_token := make_token(lxr, lxr.current, .Slash, nil, nil)
					append(&tokens, new_token)
				}
			}
		case '=':
			{
				next, ok := peek(lxr, source)
				if ok && next == '=' {
					new_token := make_token(lxr, lxr.current, .Equal_Equal, nil, nil)
					append(&tokens, new_token)
					lxr.current += 1
					lxr.column += 1
				} else {
					new_token := make_token(lxr, lxr.current, .Equal, nil, nil)
					append(&tokens, new_token)
				}
			}
		case '<':
			{
				next, ok := peek(lxr, source)
				if ok && next == '=' {
					new_token := make_token(lxr, lxr.current, .Less_Equal, nil, nil)
					append(&tokens, new_token)
					lxr.current += 1
					lxr.column += 1
				} else {
					new_token := make_token(lxr, lxr.current, .Less, nil, nil)
					append(&tokens, new_token)
				}
			}
		case '>':
			{
				next, ok := peek(lxr, source)
				if ok && next == '=' {
					new_token := make_token(lxr, lxr.current, .Greater_Equal, nil, nil)
					append(&tokens, new_token)
					lxr.current += 1
					lxr.column += 1
				} else {
					new_token := make_token(lxr, lxr.current, .Greater, nil, nil)
					append(&tokens, new_token)
				}
			}

		case '"':
			{
				// @TODO: do escapes and shit
				next, ok := peek(lxr, source)
				if !ok || next == '\n' {
					err = .Unterminated_String_Literal
					break
				}

				skips := 0
				lxr.current += 1 // Move to first char in the string
				if source[lxr.current] != '"' { 	// String is not empty
					for {
						next, ok := peek(lxr, source)
						if !ok || next == '\n' {
							err = .Unterminated_String_Literal
							break
						}

						if ok && next == '"' {
							// Move off it
							lxr.current += 1
							skips += 1
							break
						}

						lxr.current += 1
						skips += 1
					}
					if err != nil {
						break
					}
				}

				new_token := make_token(lxr, lxr.current, .Literal, .String, nil)
				append(&tokens, new_token)
				lxr.column += skips
			}
		// numbers/words
		case:
			{
				if unicode.is_digit(rune(b)) || b == '.' { 	// Number literal
					// Check if this is a dot, a beginning of a floating point number, or an illegal
					// identifier name that starts with a number
					next, ok := peek(lxr, source)
					if b == '.' &&
					   (!ok || (ok && (!unicode.is_digit(rune(next)) && next != '.'))) {
						new_token := make_token(lxr, lxr.current, .Dot, nil, nil)
						append(&tokens, new_token)
					} else if ok && unicode.is_letter(rune(next)) {
						err = .Ident_Starts_With_Number
						break
					} else {
						dotFound := false // Make sure only one dot is scanned for each number
						if b == '.' {
							dotFound = true
						}

						skips := 0
						if ok && (unicode.is_digit(rune(next)) || next == '.') {
							for {
								next, ok := peek(lxr, source)
								if ok && unicode.is_letter(rune(next)) {
									err = .Ident_Starts_With_Number
									break
								}

								if !ok || (!unicode.is_digit(rune(next)) && next != '.') {
									break
								}

								if ok && next == '.' {
									if dotFound {
										err = .Number_Literal_Dots_Count
										break
									} else {
										dotFound = true
									}
								}

								lxr.current += 1
								skips += 1
							}
						}
						if err != nil {
							break
						}

						new_token := make_token(lxr, lxr.current, .Literal, .Number, nil)
						append(&tokens, new_token)
						lxr.column += skips
					}
				} else if unicode.is_letter(rune(b)) || b == '_' { 	// Identifier or an internal keyword
					skips := 0

					next, ok := peek(lxr, source)
					if ok &&
					   (unicode.is_letter(rune(next)) ||
							   next == '_' ||
							   unicode.is_digit(rune(next))) {
						for {
							next, ok := peek(lxr, source)
							if !ok ||
							   (!unicode.is_letter(rune(next)) &&
									   next != '_' &&
									   !unicode.is_digit(rune(next))) {
								break
							}

							lxr.current += 1
							skips += 1
						}
					}

					// Decide if it's a reserved keyword or an identifier name

					token_kind: Token_Kind = .Ident

					lexeme := string(source[lxr.last_lexeme_start:lxr.current + 1])
					keyword := keyword_from_string(lexeme)
					if keyword != nil {
						token_kind = .Keyword
					}

					new_token := make_token(lxr, lxr.current, token_kind, nil, keyword)
					append(&tokens, new_token)
					lxr.column += skips
				}
			}
		}

		lxr.current += 1
	}

	return tokens, err
}

/// make_token constructs a token with the current state of the lexer instance
make_token :: proc(
	lxr: ^Lexer,
	current: int,
	kind: Token_Kind,
	literal_kind: Maybe(Literal_Kind),
	keyword: Maybe(Keyword),
) -> Token {
	return Token {
		kind = kind,
		lexeme_start = lxr.last_lexeme_start,
		lexeme_end = current + 1,
		line = lxr.line,
		column = lxr.column,
		literal_kind = literal_kind,
		keyword = keyword,
	}
}

// peek shows you the next byte without advancing the cursor
peek :: proc(lxr: ^Lexer, source: string) -> (byte, bool) {
	if lxr.current >= len(source) - 1 {
		return 0, false
	}

	return source[lxr.current + 1], true
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

	return fmt.aprintf("unknown lexer error: %v", err)
}
