package lexer

import "core:fmt"

print_tokens :: proc(source: string, tokens: [dynamic]Token) {
	fmt.printf("Tokens: \n")
	for tok, i in tokens {
		out := "---"

		#partial switch tok.kind {
		case .Comment:
			lexeme := source[tok.lexeme_start:tok.lexeme_end]
			out = fmt.aprintf("Comment(%s)", lexeme)

		case .Keyword:
			lexeme := source[tok.lexeme_start:tok.lexeme_end]
			out = fmt.aprintf("Keyword(%s)", lexeme)

		case .Ident:
			lexeme := source[tok.lexeme_start:tok.lexeme_end]
			out = fmt.aprintf("Identifier(%s)", lexeme)

		case:
			{
				if tok.literal_kind != nil {
					kind := tok.literal_kind
					lex := source[tok.lexeme_start:tok.lexeme_end]

					switch kind {
					case .Boolean:
						out = fmt.aprintf("Boolean(%s)", lex)
					case .String:
						out = fmt.aprintf("String(%s)", lex)
					case .Number:
						out = fmt.aprintf("Number(%s)", lex)
					case .Nil:
						out = "nil"
					}
				}
			}
		}

		fmt.printf(
			"%4d  %-12s  [%d:%d]  line=%d col=%d  %s\n",
			i,
			tok.kind,
			tok.lexeme_start,
			tok.lexeme_end,
			tok.line,
			tok.column,
			out,
		)
	}
}
