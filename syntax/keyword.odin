package syntax

Keyword :: enum u8 {
	If,
	Else,
	And,
	Or,
}

Keyword_Entry :: struct {
	name: string,
	kw:   Keyword,
}

keywords := []Keyword_Entry {
	{"if", .If},
	{"else", .Else},
	{"and", .And},
	{"or", .Or},
}

keyword_from_string :: proc(s: string) -> Maybe(Keyword) {
	for entry in keywords {
		if entry.name == s {
			return entry.kw
		}
	}

	return nil
}
