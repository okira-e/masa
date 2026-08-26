package syntax

// A half-open byte range into the source: [start, end).
Span :: struct {
	start: int,
	end:   int,
}

// Returns a span that covers both inputs.
// first: [3--------8]
// last:       [6--------12]
// join:  [3-------------12]
span_join :: proc(first: Span, last: Span) -> Span {
	return Span {
		start = min(first.start, last.start),
		end   = max(first.end, last.end),
	}
}

span_is_valid :: proc(span: Span, source_len: int) -> bool {
	return span.start >= 0 && span.start <= span.end && span.end <= source_len
}
