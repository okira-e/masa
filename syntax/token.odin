package syntax

Token :: struct {
	kind:         Token_Kind,
	// span is authoritative; line and column cache the token's start for display/debugging.
	span:         Span,
	line:         int,
	column:       int,
	literal_kind: Maybe(Literal_Kind),
	keyword:      Maybe(Keyword),
}

Token_Kind :: enum u8 {
	New_Line,
	Literal,
	Keyword,
	Ident,
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
	EOF,
}

Literal_Kind :: enum u8 {
	Number,
	String,
	Bool,
	Nil,
}

Type :: struct {
	variant: Type_Variant,
	span:    Span,
}

Type_Variant :: union {
	Token,
	Fn_Type,
}

Fn_Type:: struct {
	params:  [dynamic]Type,
	returns: [dynamic]Type,
	async:   bool,
	span:    Span,
}

type_eq :: proc(a: Type, b: Type) -> bool {
	switch av in a.variant {
	case Token:
		bv, ok := b.variant.(Token)
		return ok && av == bv

	case Fn_Type:
		bv, ok := b.variant.(Fn_Type)
		if !ok do return false

		if av.async != bv.async do return false

		if len(av.params) != len(bv.params) do return false

		for p, i in av.params {
			if !type_eq(p, bv.params[i]) do return false
		}

		if len(av.returns) != len(bv.returns) do return false

		for r, i in av.returns {
			if !type_eq(r, bv.returns[i]) do return false
		}

		return true
	}

	// Both hold no variant (zero value).
	return a.variant == nil && b.variant == nil
}
