package syntax

Keyword :: enum u8 {
	If,
	For,
	Fn,
	Async,
	Await,
	Else,
	And,
	Or,
	Return,
	In,
}

Keyword_Entry :: struct {
	name: string,
	kw:   Keyword,
}

keywords := []Keyword_Entry {
	{"if",     .If},
	{"for",    .For},
	{"fn",     .Fn},
	{"async",  .Async},
	{"await",  .Await},
	{"else",   .Else},
	{"and",    .And},
	{"or",     .Or},
	{"return", .Return},
	{"in",     .In},
}

keyword_from_string :: proc(s: string) -> Maybe(Keyword) {
	for entry in keywords {
		if entry.name == s {
			return entry.kw
		}
	}

	return nil
}
