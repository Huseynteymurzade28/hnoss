package widgets

import "core:math"
import "../buffer"
import "../input"
import "../layout"
import "../style"

// State of a split_pane: how the space is shared, kept across frames and
// window resizes. `ratio` is the first pane's share of the room left
// after the divider, 0..1; a zero state starts as an even split.
Split_State :: struct {
	ratio:   f64,
	started: bool, // internal: the zero ratio has been replaced by the initial one
}

Split_Options :: struct {
	min_first, min_second: int, // the fewest cells each pane keeps
	max_first, max_second: int, // the most cells each pane gets; 0: no limit
	step:                  int, // cells one key moves the divider; 0: 1
	// The divider's ends join the lines just outside `area` (the border of
	// the box it is in, another split's divider) with ┬ ┴ ├ ┤ and their
	// double and heavy kin. Cells that aren't a straight line, such as a
	// title or a corner, are left alone. Draw the box first.
	join:                  bool,
}

// Two panes side by side (.Horizontal) or stacked (.Vertical) with a
// one-cell divider between them, which the mouse drags and a double click
// puts back in the middle. The divider takes keyboard focus like any
// widget (put `state` in focus_order): then ← → (or ↑ ↓ when stacked) move
// it by a step, Shift by ten steps, and Home End to its ends. Pressing it
// does not take the focus, so the widget you were using keeps it.
// When the area cannot fit both minimums, the first pane's wins.
// Returns the two panes, without the divider; call it before drawing them
// so it sees a press on the divider first.
//
//	files, preview := hnoss.split_pane(ui, area, .Horizontal, &split, {min_first = 12, min_second = 20})
split_pane :: proc(ui: ^Ui, area: Rect, dir: layout.Direction, state: ^Split_State, opts := Split_Options{}) -> (first, second: Rect) {
	if !state.started {
		if state.ratio == 0 { state.ratio = 0.5 }
		state.started = true
	}
	state.ratio = clamp(state.ratio, 0, 1) if !math.is_nan(state.ratio) else 0.5
	horizontal := dir == .Horizontal
	start := area.x if horizontal else area.y
	total := area.width if horizontal else area.height
	cross := area.height if horizontal else area.width
	if total < 1 || cross < 1 {
		return area, {area.x, area.y, 0, 0}
	}
	room := total - 1 // the divider takes one cell

	// Where the divider may go: the first pane's length, between lo and hi.
	lo := max(opts.min_first, 0)
	if opts.max_second > 0 { lo = max(lo, room - opts.max_second) }
	hi := room - max(opts.min_second, 0)
	if opts.max_first > 0 { hi = min(hi, opts.max_first) }
	place :: proc(n, lo, hi, room: int) -> int {
		return clamp(max(min(n, hi), lo), 0, room)
	}
	length := place(int(math.round(state.ratio * f64(room))), lo, hi, room)
	move_to :: proc(state: ^Split_State, n, lo, hi, room: int) -> int {
		at := place(n, lo, hi, room)
		state.ratio = f64(at) / f64(room) if room > 0 else 0.5
		return at
	}

	step := opts.step if opts.step > 0 else 1
	back, forth := input.Key_Code.Left, input.Key_Code.Right
	if !horizontal { back, forth = .Up, .Down }
	it: Key_Iter
	for k, i in next_key(ui, state, &it) {
		by := step * (10 if .Shift in k.mods else 1)
		switch {
		case k.code == back:  length = move_to(state, length - by, lo, hi, room)
		case k.code == forth: length = move_to(state, length + by, lo, hi, room)
		case k.code == .Home: length = move_to(state, lo, lo, hi, room)
		case k.code == .End:  length = move_to(state, hi, lo, hi, room)
		case:                 continue
		}
		consume(ui, i)
	}

	divider := Rect{start + length, area.y, 1, area.height} if horizontal else Rect{area.x, start + length, area.width, 1}
	mit: Key_Iter
	for m, i in next_mouse(ui, state, divider, &mit) {
		at := (m.x if horizontal else m.y) - start
		#partial switch m.kind {
		case .Press:
			if m.button != .Left { continue }
			if m.clicks == 2 {
				length = move_to(state, room / 2, lo, hi, room)
			}
			ui.mem.active = state
		case .Drag:
			if ui.mem.active != state { continue }
			length = move_to(state, at, lo, hi, room)
		case .Release:
			if ui.mem.active != state { continue }
			ui.mem.active = nil
		case:
			continue
		}
		consume(ui, i)
	}

	if horizontal {
		first = {area.x, area.y, length, area.height}
		divider = {area.x + length, area.y, 1, area.height}
		second = {divider.x + 1, area.y, room - length, area.height}
	} else {
		first = {area.x, area.y, area.width, length}
		divider = {area.x, area.y + length, area.width, 1}
		second = {area.x, divider.y + 1, area.width, room - length}
	}

	_, _, hot := hover(ui, state, divider)
	sym, st := "│" if horizontal else "─", ui.theme.border
	switch {
	case ui.mem.active == state || focused(ui, state):
		sym, st = "┃" if horizontal else "━", ui.theme.border_focused
	case hot:
		st = style.patch(st, ui.theme.hover)
	}
	for i in 0 ..< cross {
		if horizontal {
			buffer.set_symbol(ui.buf, divider.x, divider.y + i, sym, 1, st)
		} else {
			buffer.set_symbol(ui.buf, divider.x + i, divider.y, sym, 1, st)
		}
	}
	if opts.join {
		heavy := sym != "│" && sym != "─"
		ends := [2][2]int{{divider.x, area.y - 1}, {divider.x, area.y + area.height}}
		if !horizontal { ends = {{area.x - 1, divider.y}, {area.x + area.width, divider.y}} }
		for e, i in ends {
			if !layout.rect_contains(ui.buf.area, e.x, e.y) { continue }
			c := buffer.get(ui.buf, e.x, e.y)
			if j := split_junction(buffer.cell_symbol(c), i == 1, horizontal, heavy); j != "" {
				buffer.set_symbol(ui.buf, e.x, e.y, j, 1, style.patch(Style{fg = c.fg, bg = c.bg}, st))
			}
		}
	}
	return
}

// The junction where a divider ends on the line `on` (a box's border or
// another divider): `last` is its bottom (or right) end. "" when `on` is
// not a straight line across the divider's end (a title, a corner).
@(private)
split_junction :: proc(on: string, last, horizontal, heavy: bool) -> string {
	J :: struct { line: string, light, heavy: [2]string }
	across := [?]J{ // the divider is vertical; it ends on these horizontal lines
		{"─", {"┬", "┴"}, {"┰", "┸"}},
		{"═", {"╤", "╧"}, {"╤", "╧"}},
		{"━", {"┯", "┷"}, {"┳", "┻"}},
	}
	along := [?]J{ // the divider is horizontal; it ends on these vertical lines
		{"│", {"├", "┤"}, {"┝", "┥"}},
		{"║", {"╟", "╢"}, {"╟", "╢"}},
		{"┃", {"┠", "┨"}, {"┣", "┫"}},
	}
	for j in (across[:] if horizontal else along[:]) {
		if on == j.line {
			return j.heavy[int(last)] if heavy else j.light[int(last)]
		}
	}
	return ""
}
