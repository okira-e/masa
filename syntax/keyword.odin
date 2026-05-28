package syntax

Keyword :: enum u8 {
	If,
	Else,
	And,
	Or,
	Bool,
	Number,
	Any,
	String,
}

Keyword_Entry :: struct {
	name: string,
	kw:   Keyword,
}

keywords := []Keyword_Entry {
	{"if",     .If},
	{"else",   .Else},
	{"and",    .And},
	{"or",     .Or},
	{"bool",   .Bool},
	{"number", .Number},
	{"any",    .Any},
	{"string", .String},
}

keyword_from_string :: proc(s: string) -> Maybe(Keyword) {
	for entry in keywords {
		if entry.name == s {
			return entry.kw
		}
	}

	return nil
}

is_keyword_type :: proc(keyword: Keyword) -> bool {
	#partial switch keyword {
	case .Bool, .Number, .String, .Any:
		return true
	}

	return false
}
