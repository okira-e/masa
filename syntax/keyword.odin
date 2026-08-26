package syntax

Keyword :: enum u8 {
	If,
	Fn,
	Async,
	Await,
	Else,
	And,
	Or,
	Return,
}

Keyword_Entry :: struct {
	name: string,
	kw:   Keyword,
}

keywords := []Keyword_Entry {
	{"if",     .If},
	{"fn",     .Fn},
	{"async",  .Async},
	{"await",  .Await},
	{"else",   .Else},
	{"and",    .And},
	{"or",     .Or},
	{"return", .Return},
}

keyword_from_string :: proc(s: string) -> Maybe(Keyword) {
	for entry in keywords {
		if entry.name == s {
			return entry.kw
		}
	}

	return nil
}

