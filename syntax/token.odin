package syntax

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

Token_Kind :: enum {
	New_Line,
	Left_Paren,
	Right_Paren,
	Left_Brace,
	Right_Brace,
	Comma,
	Dot,
	Minus,
	Plus,
	Star,
	Bang,
	Colon,
	Colon_Colon,
	Bang_Equal,
	Equal_Equal,
	Equal,
	Colon_Equal,
	Less_Equal,
	Less,
	Greater_Equal,
	Greater,
	Comment,
	Slash,
	Literal,
	Ident,
	Keyword,
	EOF,
}

Literal_Kind :: enum {
	Number,
	String,
	Bool,
	Nil,
}
