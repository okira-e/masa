package lexer

import "../syntax"
import "core:fmt"

print_tokens :: proc(source: string, tokens: [dynamic]syntax.Token) {
	for &token, i in tokens {
		print_token(source, &token, i)
	}
}

print_token :: proc(source: string, token: ^syntax.Token, i := 0) {
	fmt.printf("Tokens: \n")
	out := "---"

	#partial switch token.kind {
	case .Comment:
		lexeme := source[token.lexeme_start:token.lexeme_end]
		out = fmt.aprintf("Comment(%s)", lexeme)

	case .Keyword:
		lexeme := source[token.lexeme_start:token.lexeme_end]
		out = fmt.aprintf("Keyword(%s)", lexeme)

	case .Ident:
		lexeme := source[token.lexeme_start:token.lexeme_end]
		out = fmt.aprintf("Identifier(%s)", lexeme)

	case:
		{
			if token.literal_kind != nil {
				kind := token.literal_kind
				lex := source[token.lexeme_start:token.lexeme_end]

				switch kind {
				case .Bool:
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
		token.kind,
		token.lexeme_start,
		token.lexeme_end,
		token.line,
		token.column,
		out,
	)
}
