package lexer

Token :: struct {
	kind:         Token_Kind,
	// lexeme is the actual text of the token. Can be the variable name for identifiers.
	lexeme_start: int,
	lexeme_end:   int,
	line:         int,
	column:       int,
	literal_kind: Maybe(Literal_Kind),
	keyword:      Maybe(Keyword),
}

Literal_Kind :: enum {
	Number,
	String,
	Boolean,
	Nil,
}

