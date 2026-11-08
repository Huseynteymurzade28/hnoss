package widgets

import "core:fmt"
import "core:unicode"
import "core:unicode/utf8"
import "../buffer"
import "../input"
import "../layout"
import "../pen"
import "../text"

List_State :: struct {
	selected:  int,  // index of the selected item (into `items`, also while filtering)
	offset:    int,  // first visible row (of the matching items, while filtering)
	activated: bool, // Enter was pressed, or the selection double-clicked, this frame
	query_buf: [64]u8, // the filter typed so far (see list_query), UTF-8
	query_len: int,
}

List_Options :: struct {
	marker:    Maybe(string), // drawn before the selected item (default "› ")
	markup:    bool,          // items are markup instead of plain text
	scrollbar: bool,          // when the items don't fit
	filter:    bool,          // typing narrows the items (j and k then type, too)
}

// A scrollable, selectable list. While focused: ↑ ↓ (or k j), PgUp PgDn,
// Home End move, Enter or a double click activates. Clicking selects (and focuses), the wheel
// scrolls. Returns true when the selection changed.
//
// With `opts.filter`, printable keys and paste build a query instead (so j
// and k type), Backspace and Ctrl+U edit it and Esc clears it; Backspace
// and Esc on an empty query are left to the app. Only the items that
// contain the query, or its characters in order, ignoring case, are shown,
// with the matched characters in theme.match, and the query on the bottom
// row. `state.selected` stays an index into `items`: a selection the query
// hides moves to the next match. With no matches, Enter does nothing.
// Markup items are matched as written, tags included, and not highlighted.
list :: proc(ui: ^Ui, area: Rect, items: []string, state: ^List_State, opts := List_Options{}) -> (changed: bool) {
	state.activated = false
	if area.width <= 0 || area.height <= 0 {
		return false
	}
	old := state.selected
	body := area

	// The query keys go first, so a burst of typing and arrows in one frame
	// moves through the matches of the final query.
	query_changed := opts.filter && edit_query(ui, state)
	query := list_query(state)
	filtering := opts.filter && query != ""

	// While filtering, rows are positions in `shown`; the selection is
	// mapped to one for select_rows and back.
	shown: []int
	if filtering {
		shown = matching(items, query)
		state.selected = nearest_match(shown, state.selected)
		if body.height >= 2 {
			draw_query(ui, layout.cut_bottom(&body, 1), query, len(shown), len(items))
		}
	}
	n := len(shown) if filtering else len(items)
	bar: Rect
	if opts.scrollbar && n > body.height {
		bar = layout.cut_right(&body, 1)
	}
	if query_changed {
		// bring the selection into view once; afterwards the wheel may move away
		row := state.selected if !filtering else position_of(shown, state.selected)
		state.offset = clamp(state.offset, row - body.height + 1, row)
	}

	if filtering && len(shown) == 0 {
		// keys and clicks are still the list's, but there is nothing to select
		offset := state.offset
		select_rows(ui, state, body, 0, 0)
		state.selected, state.offset = old, offset
		buffer.set_string(ui.buf, body.x, body.y, "no matches", ui.theme.muted, body.width)
		return false
	}

	if filtering { state.selected = position_of(shown, state.selected) }
	select_rows(ui, state, body, 0, n)
	row_style := ui.theme.selected if focused(ui, state) else ui.theme.selected_unfocused
	marker := opts.marker.? or_else "› "
	if filtering {
		draw_rows(ui, body, items, state.selected, state.offset, row_style, marker, opts.markup, shown, query)
		state.selected = shown[state.selected]
	} else {
		draw_rows(ui, body, items, state.selected, state.offset, row_style, marker, opts.markup)
	}

	if bar.width > 0 {
		scrollbar(ui, bar, n, body.height, &state.offset)
	}
	return state.selected != old
}

// The filter typed into a list with `filter` set ("" when none).
list_query :: proc(state: ^List_State) -> string {
	return string(state.query_buf[:clamp(state.query_len, 0, len(state.query_buf))])
}

// Replaces a list's filter (cut to fit at a character boundary; "" clears it).
list_set_query :: proc(state: ^List_State, query: string) {
	state.query_len = 0
	query_append(state, query)
}

@(private)
query_append :: proc(state: ^List_State, s: string) {
	state.query_len = clamp(state.query_len, 0, len(state.query_buf))
	for r in s {
		if r < 0x20 || r == 0x7f { continue }
		b, n := utf8.encode_rune(r)
		if state.query_len + n > len(state.query_buf) { return }
		copy(state.query_buf[state.query_len:], b[:n])
		state.query_len += n
	}
}

// Takes the keys and paste that edit the query. Returns true when it changed.
@(private)
edit_query :: proc(ui: ^Ui, state: ^List_State) -> (changed: bool) {
	if !focused(ui, state) {
		return false
	}
	for ev, i in ui.events {
		if ui.handled[i] { continue }
		before := state.query_len
		used := true
		#partial switch e in ev {
		case input.Key:
			ctrl, alt := .Ctrl in e.mods, .Alt in e.mods
			#partial switch e.code {
			case .Char:
				switch {
				case !ctrl && !alt:
					b, n := utf8.encode_rune(e.char)
					query_append(state, string(b[:n]))
				case ctrl && e.char == 'u' && before > 0: state.query_len = 0
				case: used = false
				}
			case .Backspace:
				if before > 0 {
					_, n := utf8.decode_last_rune(list_query(state))
					state.query_len -= n
				} else {
					used = false
				}
			case .Esc:
				used = before > 0
				state.query_len = 0
			case:
				used = false
			}
		case input.Paste:
			query_append(state, single_line(e.text))
		case:
			used = false
		}
		if used {
			consume(ui, i)
			changed ||= state.query_len != before
		}
	}
	return
}

// "/ query          3/22" on one row.
@(private)
draw_query :: proc(ui: ^Ui, row: Rect, query: string, matches, total: int) {
	r := row
	count := fmt.tprintf("%d/%d", matches, total)
	right := layout.cut_right(&r, min(text.width(count) + 1, max(r.width - 3, 0)))
	p := pen.begin(ui.buf, r, .Ellipsis, base = ui.theme.text)
	pen.write(&p, "/ ", ui.theme.key)
	pen.write(&p, query)
	pen.finish(&p)
	p = pen.begin(ui.buf, right, .Clip, .Right, base = ui.theme.muted)
	pen.write(&p, count)
	pen.finish(&p)
}

// Indices of the items that match `query` (temp allocator).
@(private)
matching :: proc(items: []string, query: string) -> []int {
	out := make([dynamic]int, 0, 16, context.temp_allocator)
	for s, i in items {
		if fuzzy_match(s, query) { append(&out, i) }
	}
	return out[:]
}

// `selected` if it is in `shown`, else the first match after it, else the
// last match (or `selected` when nothing matches).
@(private)
nearest_match :: proc(shown: []int, selected: int) -> int {
	for idx in shown {
		if idx >= selected { return idx }
	}
	return shown[len(shown) - 1] if len(shown) > 0 else selected
}

@(private)
position_of :: proc(shown: []int, idx: int) -> int {
	for v, i in shown {
		if v == idx { return i }
	}
	return 0
}

// Case-insensitive match of `query` in `s`: as a substring if it is one,
// else its characters in order. Characters are compared by the first rune
// of each grapheme of `s`. On a match, `hits` (len(s) bytes, if given) is
// set true over the matched graphemes.
@(private)
fuzzy_match :: proc(s, query: string, hits: []bool = nil) -> bool {
	if query == "" {
		return true
	}
	for start := s; len(start) > 0; {
		if n, ok := match_prefix(start, query); ok {
			at := len(s) - len(start)
			if hits != nil {
				for i in at ..< at + n { hits[i] = true }
			}
			return true
		}
		_, _, rest := text.next_grapheme(start)
		start = rest
	}
	q := query
	for rest := s; len(rest) > 0 && len(q) > 0; {
		cluster, _, r := text.next_grapheme(rest)
		qr, qn := utf8.decode_rune_in_string(q)
		if same_char(cluster, qr) {
			q = q[qn:]
			if hits != nil {
				at := len(s) - len(rest)
				for i in at ..< at + len(cluster) { hits[i] = true }
			}
		}
		rest = r
	}
	if len(q) > 0 && hits != nil {
		for &h in hits { h = false }
	}
	return len(q) == 0
}

// Whether `s` starts with `query`; `n` is the bytes of `s` it covers.
@(private)
match_prefix :: proc(s, query: string) -> (n: int, ok: bool) {
	rest, q := s, query
	for len(q) > 0 {
		if len(rest) == 0 { return 0, false }
		cluster, _, r := text.next_grapheme(rest)
		qr, qn := utf8.decode_rune_in_string(q)
		if !same_char(cluster, qr) { return 0, false }
		rest, q = r, q[qn:]
	}
	return len(s) - len(rest), true
}

@(private)
same_char :: proc(cluster: string, r: rune) -> bool {
	c, _ := utf8.decode_rune_in_string(cluster)
	return unicode.to_lower(c) == unicode.to_lower(r)
}

// Draws the items from `offset` down `body`, the `selected` one filled
// with `row_style` and preceded by `marker`. With `shown`, row i is
// items[shown[i]] (rows, `selected` and `offset` count positions in
// `shown`) and the characters matching `query` are drawn in theme.match.
@(private)
draw_rows :: proc(ui: ^Ui, body: Rect, items: []string, selected, offset: int, row_style: Style, marker: string, markup: bool, shown: []int = nil, query := "") {
	mw := text.width(marker)
	n := len(shown) if shown != nil else len(items)
	for i in offset ..< min(offset + body.height, n) {
		y := body.y + i - offset
		if i == selected {
			row := Rect{body.x, y, body.width, 1}
			buffer.fill(ui.buf, row, row_style)
			p := pen.begin(ui.buf, row, .Clip)
			pen.write(&p, marker)
			pen.finish(&p)
		}
		s := items[shown[i]] if shown != nil else items[i]
		item := Rect{body.x + mw, y, body.width - mw, 1}
		p := pen.begin(ui.buf, item, .Ellipsis, base = ui.theme.text)
		switch {
		case markup:
			pen.markup(&p, s)
		case query != "":
			write_highlighted(&p, s, query, ui.theme.match)
		case:
			pen.write(&p, s)
		}
		pen.finish(&p)
	}
}

// Writes `s` with the graphemes that match `query` in `st`.
@(private)
write_highlighted :: proc(p: ^pen.Pen, s, query: string, st: Style) {
	hits := make([]bool, len(s), context.temp_allocator)
	fuzzy_match(s, query, hits)
	for start := 0; start < len(s); {
		end := start
		for end < len(s) && hits[end] == hits[start] { end += 1 }
		pen.write(p, s[start:end], st if hits[start] else {})
		start = end
	}
}

// Keyboard and mouse handling shared by list and table: `rows` is the
// area the items occupy (after any header), `header` rows above it are
// part of the widget but not selectable.
@(private)
select_rows :: proc(ui: ^Ui, state: ^List_State, rows: Rect, header, n: int) {
	h := rows.height
	page := max(h - 1, 1)
	last := max(n - 1, 0)
	top := max(n - h, 0)

	// Every event starts from a state in range (the first one too, after n
	// or the area changed), so a burst of events in one frame ends where the
	// same events one frame each would.
	state.selected = clamp(state.selected, 0, last)
	state.offset = clamp(state.offset, 0, top)

	it: Key_Iter
	for k, i in next_key(ui, state, &it) {
		used := true
		#partial switch k.code {
		case .Up:        state.selected -= 1
		case .Down:      state.selected += 1
		case .Page_Up:   state.selected -= page
		case .Page_Down: state.selected += page
		case .Home:      state.selected = 0
		case .End:       state.selected = n - 1
		case .Enter:     state.activated = n > 0
		case .Char:
			switch {
			case k.char == 'k' && k.mods == {}: state.selected -= 1
			case k.char == 'j' && k.mods == {}: state.selected += 1
			case: used = false
			}
		case:
			used = false
		}
		if used {
			consume(ui, i)
			state.selected = clamp(state.selected, 0, last)
			// keep the selection on screen
			if state.selected < state.offset { state.offset = state.selected }
			if state.selected >= state.offset + h { state.offset = state.selected - h + 1 }
			state.offset = clamp(state.offset, 0, top)
		}
	}

	whole := Rect{rows.x, rows.y - header, rows.width, rows.height + header}
	mit: Key_Iter
	for m, i in next_mouse(ui, nil, whole, &mit) {
		#partial switch m.kind {
		case .Press:
			ui.mem.focus = state
			if m.button == .Left && m.y >= rows.y {
				if idx := state.offset + m.y - rows.y; idx < n {
					state.selected = idx
					state.activated ||= m.clicks == 2
				}
			}
			consume(ui, i)
		case .Scroll:
			#partial switch m.button {
			case .Wheel_Up:   state.offset -= 3
			case .Wheel_Down: state.offset += 3
			}
			state.offset = clamp(state.offset, 0, top)
			consume(ui, i)
		}
	}
}
