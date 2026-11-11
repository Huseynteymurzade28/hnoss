package widgets

import "core:fmt"
import "core:mem"
import "core:strings"
import "../buffer"
import "../input"
import "../layout"
import "../pen"

DEFAULT_LOG_LINES :: 10_000

// Lines of a log_view: a ring buffer that only grows at the end; once
// `max_lines` are kept, each new line drops the oldest. The lines are
// copies, made with the allocator of the first log_append
// (context.allocator); free them with log_destroy.
//
// The zero value is ready to use and follows the tail.
Log_State :: struct {
	max_lines: int, // set before the first append; 0 = DEFAULT_LOG_LINES

	lines:     [dynamic]string,
	head:      int, // index in `lines` of the oldest line once it is full
	appended:  int, // lines appended since the start (or log_clear); also the next line's number
	allocator: mem.Allocator,

	// Where the view is while it is not following the tail: the number of
	// the top line (as in `appended`, so it holds still while old lines
	// drop off) and how many of its wrapped rows are scrolled past.
	paused:    bool, // scrolled away from the tail: new lines don't move the view
	top:       int,
	top_row:   int,
	unseen:    int, // lines appended while paused
	bar:       int, // the scrollbar's offset (its identity while dragged)
}

Log_Options :: struct {
	wrap:      pen.Wrap, // .Word by default; .Clip or .Ellipsis cut long lines off instead
	markup:    bool,     // lines carry [markup]; off by default, as log text often has brackets
	scrollbar: bool,     // in the rightmost column, when the lines don't fit
}

// Appends `text` to the log, one line per "\n" (a trailing one doesn't
// start an empty line).
log_append :: proc(state: ^Log_State, text: string) {
	if state.allocator.procedure == nil {
		state.allocator = context.allocator
	}
	if state.max_lines <= 0 {
		state.max_lines = DEFAULT_LOG_LINES
	}
	if state.lines == nil {
		state.lines = make([dynamic]string, 0, min(state.max_lines, 256), state.allocator)
	}
	rest := strings.trim_suffix(text, "\n")
	for {
		nl := strings.index_byte(rest, '\n')
		line := rest if nl < 0 else rest[:nl]
		push_line(state, strings.trim_suffix(line, "\r"))
		if nl < 0 { break }
		rest = rest[nl + 1:]
	}
}

// log_append with fmt.tprintf formatting.
log_appendf :: proc(state: ^Log_State, format: string, args: ..any) {
	log_append(state, fmt.tprintf(format, ..args))
}

// Number of lines kept (at most max_lines).
log_len :: proc(state: ^Log_State) -> int {
	return len(state.lines)
}

// Line `i` of the kept ones, 0 being the oldest.
log_line :: proc(state: ^Log_State, i: int) -> string {
	return state.lines[(state.head + i) % len(state.lines)]
}

// Drops every line and goes back to following the tail.
log_clear :: proc(state: ^Log_State) {
	for l in state.lines {
		delete(l, state.allocator)
	}
	clear(&state.lines)
	state.head = 0
	state.appended = 0
	state.paused = false
	state.unseen = 0
}

log_destroy :: proc(state: ^Log_State) {
	log_clear(state)
	delete(state.lines)
	state.lines = nil
}

// A view of streaming lines (logs, build output, chat) that follows the
// tail: new lines appear at the bottom. Scrolling up (↑ k PgUp Home, the
// wheel, the scrollbar) holds the view still while lines keep coming, and
// shows how many arrived since; End or G, scrolling back to the bottom, or
// a click on that "new lines" note follows the tail again. ↓ j PgDn scroll
// down. Keys work while focused; clicking it takes focus.
log_view :: proc(ui: ^Ui, area: Rect, state: ^Log_State, opts := Log_Options{}) {
	if area.width <= 0 || area.height <= 0 {
		return
	}
	body := area
	bar: Rect
	if opts.scrollbar && !fits(state, body.width, body.height, opts) {
		bar = layout.cut_right(&body, 1)
	}
	v := Log_Cursor{state, body.width, opts}
	H := body.height
	clamp_top(state)

	page := max(H - 1, 1)
	it: Key_Iter
	for k, i in next_key(ui, state, &it) {
		used := true
		switch {
		case k.code == .Up || is_plain(k, 'k'):        log_scroll(&v, H, -1)
		case k.code == .Down || is_plain(k, 'j'):      log_scroll(&v, H, 1)
		case k.code == .Page_Up:                       log_scroll(&v, H, -page)
		case k.code == .Page_Down:                     log_scroll(&v, H, page)
		case k.code == .Home || is_plain(k, 'g'):      log_seek(&v, H, state.appended - len(state.lines))
		case k.code == .End || k.code == .Char && k.char == 'G' && k.mods <= {.Shift}:
			follow(state)
		case:
			used = false
		}
		if used { consume(ui, i) }
	}

	note := new_lines_note(state, body)
	mit: Key_Iter
	for m, i in next_mouse(ui, nil, body, &mit) {
		#partial switch m.kind {
		case .Scroll:
			#partial switch m.button {
			case .Wheel_Up:   log_scroll(&v, H, -3)
			case .Wheel_Down: log_scroll(&v, H, 3)
			case:             continue
			}
			consume(ui, i)
		case .Press:
			ui.mem.focus = state
			if m.button == .Left && layout.rect_contains(note, m.x, m.y) {
				follow(state)
				consume(ui, i)
			}
		}
	}

	top, top_row := state.top, state.top_row
	if !state.paused {
		top, top_row = bottom_anchor(&v, H)
	}
	if bar.width > 0 {
		first := state.appended - len(state.lines)
		// In lines, not rows: wrapped rows of lines out of view aren't known.
		state.bar = top - first
		if scrollbar(ui, bar, len(state.lines), lines_shown(&v, top, top_row, H), &state.bar) {
			log_seek(&v, H, first + state.bar)
			top, top_row = state.top, state.top_row
			if !state.paused {
				top, top_row = bottom_anchor(&v, H)
			}
		}
	}

	p := pen.begin(ui.buf, body, opts.wrap, scroll = top_row)
	for n := top; n < state.appended && !pen.overflowed(&p); n += 1 {
		write_log_line(&p, line_at(state, n), opts, ui.theme.text)
		pen.newline(&p)
	}
	pen.finish(&p)

	note = new_lines_note(state, body)
	if note.width > 0 {
		buffer.fill(ui.buf, note, ui.theme.selected)
		buffer.set_string(ui.buf, note.x, note.y, note_label(state, body.width), ui.theme.selected, note.width)
	}
}

// What scrolling needs to measure lines: rows depend on the width.
@(private = "file")
Log_Cursor :: struct {
	state: ^Log_State,
	width: int,
	opts:  Log_Options,
}

@(private = "file")
push_line :: proc(state: ^Log_State, line: string) {
	owned := strings.clone(line, state.allocator)
	if len(state.lines) < state.max_lines {
		append(&state.lines, owned)
	} else {
		delete(state.lines[state.head], state.allocator)
		state.lines[state.head] = owned
		state.head = (state.head + 1) % len(state.lines)
	}
	state.appended += 1
	if state.paused {
		state.unseen += 1
	}
}

@(private = "file")
line_at :: proc(state: ^Log_State, n: int) -> string {
	return log_line(state, n - (state.appended - len(state.lines)))
}

@(private = "file")
write_log_line :: proc(p: ^pen.Pen, line: string, opts: Log_Options, st: Style) {
	if opts.markup {
		pen.markup(p, line, st)
	} else {
		pen.write(p, line, st)
	}
}

// Rows line `n` takes; an empty line still takes one.
@(private = "file")
rows_of :: proc(v: ^Log_Cursor, n: int) -> int {
	if v.opts.wrap == .Clip || v.opts.wrap == .Ellipsis {
		return 1
	}
	p := pen.begin(nil, {0, 0, v.width, 0}, v.opts.wrap)
	write_log_line(&p, line_at(v.state, n), v.opts, {})
	return max(pen.finish(&p), 1)
}

@(private = "file")
follow :: proc(state: ^Log_State) {
	state.paused = false
	state.unseen = 0
}

// The top line drops off the ring while paused: start from the oldest.
@(private = "file")
clamp_top :: proc(state: ^Log_State) {
	first := state.appended - len(state.lines)
	if state.paused && state.top < first {
		state.top, state.top_row = first, 0
	}
}

// Top line and row that put the newest line's last row at the bottom.
@(private = "file")
bottom_anchor :: proc(v: ^Log_Cursor, height: int) -> (top, top_row: int) {
	first := v.state.appended - len(v.state.lines)
	sum := 0
	for n := v.state.appended - 1; n >= first; n -= 1 {
		r := rows_of(v, n)
		if sum + r >= height {
			return n, sum + r - height
		}
		sum += r
	}
	return first, 0
}

// Every line fits in `height` rows (so there is nothing to scroll).
@(private = "file")
fits :: proc(state: ^Log_State, width, height: int, opts: Log_Options) -> bool {
	v := Log_Cursor{state, width, opts}
	top, top_row := bottom_anchor(&v, height)
	return top == state.appended - len(state.lines) && top_row == 0
}

// How many lines, from `top` on, are at least partly in view.
@(private = "file")
lines_shown :: proc(v: ^Log_Cursor, top, top_row, height: int) -> int {
	sum := -top_row
	n := top
	for ; n < v.state.appended && sum < height; n += 1 {
		sum += rows_of(v, n)
	}
	return n - top
}

// From (top, top_row) the rest of the log takes more than `height` rows.
@(private = "file")
reaches_past :: proc(v: ^Log_Cursor, top, top_row, height: int) -> bool {
	sum := -top_row
	for n := top; n < v.state.appended; n += 1 {
		sum += rows_of(v, n)
		if sum > height {
			return true
		}
	}
	return false
}

// Scrolls by `delta` rows (negative = up). Leaving the tail pauses;
// reaching it again follows.
@(private = "file")
log_scroll :: proc(v: ^Log_Cursor, height, delta: int) {
	s := v.state
	if len(s.lines) == 0 {
		return
	}
	if !s.paused {
		if delta >= 0 {
			return
		}
		s.top, s.top_row = bottom_anchor(v, height)
	}
	first, last := s.appended - len(s.lines), s.appended - 1
	for n := -delta; n > 0; {
		if s.top_row > 0 {
			d := min(n, s.top_row)
			s.top_row -= d
			n -= d
			continue
		}
		if s.top <= first { break }
		s.top -= 1
		s.top_row = rows_of(v, s.top) - 1
		n -= 1
	}
	for n := delta; n > 0; {
		r := rows_of(v, s.top)
		if s.top_row + 1 < r {
			d := min(n, r - 1 - s.top_row)
			s.top_row += d
			n -= d
			continue
		}
		if s.top >= last { break }
		s.top += 1
		s.top_row = 0
		n -= 1
	}
	settle(v, height)
}

// Puts line `n` at the top.
@(private = "file")
log_seek :: proc(v: ^Log_Cursor, height, n: int) {
	s := v.state
	if len(s.lines) == 0 {
		return
	}
	s.top = clamp(n, s.appended - len(s.lines), s.appended - 1)
	s.top_row = 0
	settle(v, height)
}

// Paused if the view is above the tail, following if it reached it.
@(private = "file")
settle :: proc(v: ^Log_Cursor, height: int) {
	if reaches_past(v, v.state.top, v.state.top_row, height) {
		v.state.paused = true
	} else {
		follow(v.state)
	}
}

// Where the "N new lines" note goes: the bottom row, on the right.
@(private = "file")
new_lines_note :: proc(state: ^Log_State, body: Rect) -> Rect {
	if !state.paused || state.unseen == 0 || body.height < 2 {
		return {}
	}
	w := min(strings.rune_count(note_label(state, body.width)), body.width) // 1 cell per rune
	return {body.x + body.width - w, body.y + body.height - 1, w, 1}
}

// " ↓ 3 new lines ", or just " ↓ 3 " where that doesn't fit.
@(private = "file")
note_label :: proc(state: ^Log_State, width: int) -> string {
	long := fmt.tprintf(" ↓ %d new line%s ", state.unseen, "" if state.unseen == 1 else "s")
	if strings.rune_count(long) <= width {
		return long
	}
	return fmt.tprintf(" ↓ %d ", state.unseen)
}

@(private = "file")
is_plain :: proc(k: input.Key, r: rune) -> bool {
	return k.code == .Char && k.char == r && k.mods == {}
}
