package syntax

Keyword :: enum u8 {
	Fn,
	Void,
	Return,
	Number,
	Str,
	Nil,
	Any,
}

Keyword_Entry :: struct {
	name: string,
	kw:   Keyword,
}

keywords := []Keyword_Entry {
	{"fn", .Fn},
	{"void", .Void},
	{"return", .Return},
	{"number", .Number},
	{"str", .Str},
	{"nil", .Nil},
	{"any", .Any},
}

keyword_from_string :: proc(s: string) -> Maybe(Keyword) {
	for entry in keywords {
		if entry.name == s {
			return entry.kw
		}
	}

	return nil
}
