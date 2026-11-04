package widgets

import "../buffer"
import "../layout"
import "../pen"
import "core:strings"

// One node of a tree, in a flat list in depth-first order: a node's
// children are the items right after it with a greater depth.
//
// `open` makes the node a branch that can be expanded and collapsed; it
// points at a flag you own (usually in your own node type), which the tree
// flips. Leaves leave it nil. A branch may have no children yet, so you can
// load them when it is opened.
Tree_Item :: struct {
	text:  string,
	depth: int, // 0 for the top level
	open:  ^bool,
}

Tree_State :: struct {
	selected:  int,  // index into the items (always a visible one)
	offset:    int,  // first visible row
	activated: bool, // Enter was pressed on the selection this frame
}

Tree_Options :: struct {
	indent:    int,  // cells per level (0 means the default, 2)
	markup:    bool, // item texts are markup instead of plain text
	scrollbar: bool, // when the rows don't fit
	guides:    bool, // lines from each branch to its children: │ ├ └
}

// An expandable tree. The children of a closed branch are skipped. While
// focused: ↑ ↓ (k j), PgUp PgDn, Home End move; → (l) opens a branch, or
// goes to its first child when open; ← (h) closes it, or goes to the
// parent; Space toggles; Enter activates. `guides` draws lines from each
// branch down to its children. Clicking a row selects it (and
// focuses), clicking a branch's arrow toggles it, the wheel scrolls.
// Returns true when the selection changed.
//
//	items := []hnoss.Tree_Item{
//	    {"src", 0, &src_open},
//	    {"main.odin", 1, nil},
//	    {"README.md", 0, nil},
//	}
//	hnoss.tree(ui, area, items, &state)
tree :: proc(ui: ^Ui, area: Rect, items: []Tree_Item, state: ^Tree_State, opts := Tree_Options{}) -> (changed: bool) {
	state.activated = false
	if area.width <= 0 || area.height <= 0 {
		return false
	}
	indent := opts.indent if opts.indent > 0 else 2
	old := state.selected

	// `rows` maps a visible row to its item and is rebuilt whenever a
	// branch is toggled, so later events in the same frame see the change.
	rows := make([dynamic]int, 0, len(items), context.temp_allocator)
	tree_rows(items, &rows)

	body := area
	bar: Rect
	if opts.scrollbar && len(rows) > area.height {
		bar = layout.cut_right(&body, 1)
	}
	h := body.height
	page := max(h - 1, 1)

	row := tree_settle(items, rows[:], state, h, follow = false)
	toggle :: proc(items: []Tree_Item, rows: ^[dynamic]int, it: Tree_Item) {
		it.open^ = !it.open^
		tree_rows(items, rows)
	}

	kit: Key_Iter
	for k, i in next_key(ui, state, &kit) {
		n := len(rows)
		if n == 0 { break }
		it := items[rows[row]]
		used := true
		code := k.code
		if code == .Char && k.mods == {} {
			switch k.char {
			case 'k': code = .Up
			case 'j': code = .Down
			case 'h': code = .Left
			case 'l': code = .Right
			}
		}
		space := k.code == .Char && k.char == ' ' && k.mods == {}
		#partial switch code {
		case .Up:        row -= 1
		case .Down:      row += 1
		case .Page_Up:   row -= page
		case .Page_Down: row += page
		case .Home:      row = 0
		case .End:       row = n - 1
		case .Enter:     state.activated = true
		case .Char:
			if space && it.open != nil { toggle(items, &rows, it) } else { used = false }
		case .Right:
			switch {
			case it.open == nil:
				used = false
			case !it.open^:
				toggle(items, &rows, it)
			case row + 1 < len(rows) && items[rows[row + 1]].depth > it.depth:
				row += 1
			}
		case .Left:
			if it.open != nil && it.open^ {
				toggle(items, &rows, it)
			} else if p := tree_parent(items, rows[row]); p >= 0 {
				row = tree_row_of(rows[:], p)
			} else {
				used = false
			}
		case:
			used = false
		}
		if used {
			consume(ui, i)
			state.selected = rows[clamp(row, 0, len(rows) - 1)]
			row = tree_settle(items, rows[:], state, h)
		}
	}

	mit: Key_Iter
	for m, i in next_mouse(ui, nil, area, &mit) {
		#partial switch m.kind {
		case .Press:
			ui.mem.focus = state
			if m.button == .Left && m.y >= body.y && m.x < body.x + body.width {
				if r := state.offset + m.y - body.y; r < len(rows) {
					it := items[rows[r]]
					state.selected = rows[r]
					arrow := body.x + it.depth * indent
					if it.open != nil && m.x >= arrow && m.x < arrow + 2 {
						toggle(items, &rows, it)
					}
					row = tree_settle(items, rows[:], state, h)
				}
			}
			consume(ui, i)
		case .Scroll:
			#partial switch m.button {
			case .Wheel_Up:   state.offset -= 3
			case .Wheel_Down: state.offset += 3
			}
			state.offset = clamp(state.offset, 0, max(len(rows) - h, 0))
			consume(ui, i)
		}
	}

	// Drawn bottom up: `more[d]` is whether a later row at depth d comes
	// before a shallower one, i.e. the last row's depth-d ancestor (or the
	// row itself) has a sibling below. Every row after the view counts too.
	row_style := ui.theme.selected if focused(ui, state) else ui.theme.selected_unfocused
	more := make([dynamic]bool, 0, 16, context.temp_allocator)
	end := min(state.offset + h, len(rows))
	for r := (len(rows) - 1 if opts.guides else end - 1); r >= state.offset; r -= 1 {
		it := items[rows[r]]
		d := max(it.depth, 0)
		if opts.guides {
			resize(&more, min(len(more), d + 1))
			for len(more) < d + 1 { append(&more, false) }
		}
		defer if opts.guides { more[d] = true }
		if r >= end { continue }

		line := Rect{body.x, body.y + r - state.offset, body.width, 1}
		if r == row {
			buffer.fill(ui.buf, line, row_style)
		}
		sb := strings.builder_make(context.temp_allocator)
		if opts.guides && d > 0 {
			for k in 1 ..< d {
				strings.write_string(&sb, "│" if more[k] else " ")
				for _ in 1 ..< indent { strings.write_byte(&sb, ' ') }
			}
			strings.write_string(&sb, "├" if more[d] else "└")
			for _ in 1 ..< indent { strings.write_string(&sb, "─") }
		} else {
			for _ in 0 ..< d * indent { strings.write_byte(&sb, ' ') }
		}
		switch {
		case it.open != nil:         strings.write_string(&sb, "▾ " if it.open^ else "▸ ")
		case opts.guides && d > 0:   strings.write_string(&sb, "─ ")
		case:                        strings.write_string(&sb, "  ")
		}
		p := pen.begin(ui.buf, layout.cut_left(&line, d * indent + 2), .Clip, base = ui.theme.muted if r != row else {})
		pen.write(&p, strings.to_string(sb))
		pen.finish(&p)
		p = pen.begin(ui.buf, line, .Ellipsis, base = ui.theme.text)
		if opts.markup { pen.markup(&p, it.text) } else { pen.write(&p, it.text) }
		pen.finish(&p)
	}

	if bar.width > 0 {
		scrollbar(ui, bar, len(rows), h, &state.offset)
	}
	return state.selected != old
}

// The visible items, in order: every item not under a closed branch.
@(private)
tree_rows :: proc(items: []Tree_Item, rows: ^[dynamic]int) {
	clear(rows)
	hide := -1 // items deeper than this are under a closed branch
	for it, i in items {
		if hide >= 0 {
			if it.depth > hide { continue }
			hide = -1
		}
		append(rows, i)
		if it.open != nil && !it.open^ { hide = it.depth }
	}
}

// Puts the state back in range and returns the selection's row: an item
// that is out of range or hidden under a closed branch gives way to its
// nearest visible ancestor. With `follow`, or when the selection had to
// move, the view scrolls to keep it on screen (not otherwise, so the wheel
// can scroll it away).
@(private)
tree_settle :: proc(items: []Tree_Item, rows: []int, state: ^Tree_State, h: int, follow := true) -> (row: int) {
	if len(rows) == 0 {
		state.selected, state.offset = 0, 0
		return 0
	}
	want := state.selected
	state.selected = clamp(state.selected, 0, len(items) - 1)
	row = tree_row_of(rows, state.selected)
	for p := state.selected; row < 0; {
		p = tree_parent(items, p)
		row = tree_row_of(rows, p) if p >= 0 else 0
	}
	state.selected = rows[row]
	if follow || state.selected != want {
		if row < state.offset { state.offset = row }
		if row >= state.offset + h { state.offset = row - h + 1 }
	}
	state.offset = clamp(state.offset, 0, max(len(rows) - h, 0))
	return
}

// The row showing item `i`, or -1 when it is hidden. Rows are sorted.
@(private)
tree_row_of :: proc(rows: []int, i: int) -> int {
	lo, hi := 0, len(rows)
	for lo < hi {
		mid := (lo + hi) / 2
		if rows[mid] < i { lo = mid + 1 } else { hi = mid }
	}
	return lo if lo < len(rows) && rows[lo] == i else -1
}

// The index of item `i`'s parent, or -1 at the top level.
@(private)
tree_parent :: proc(items: []Tree_Item, i: int) -> int {
	for j := i - 1; j >= 0; j -= 1 {
		if items[j].depth < items[i].depth { return j }
	}
	return -1
}
