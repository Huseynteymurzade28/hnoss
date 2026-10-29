// Phase 5 example: cuts, split, grid and center. Every panel shows its own
// size; resize the terminal to watch everything re-divide.
//   g  toggle gaps   d  toggle dialog   q  quit
package main

import "core:fmt"
import "core:os"
import hnoss "../.."
import "../../backend"
import "../../buffer"
import "../../style"

main :: proc() {
	context.assertion_failure_proc = backend.assertion_failure_proc

	term, err := hnoss.init()
	if err != .None {
		fmt.eprintfln("hnoss: init failed: %v", err)
		os.exit(1)
	}
	defer hnoss.deinit(&term)

	gap := 1
	dialog := false
	loop: for {
		f := hnoss.begin_frame(&term)
		draw(f, gap, dialog)
		hnoss.end_frame(&term)
		free_all(context.temp_allocator)

		for ev in hnoss.poll_events(&term, -1) {
			switch {
			case hnoss.is_char(ev, 'q'), hnoss.is_char(ev, 'c', {.Ctrl}): break loop
			case hnoss.is_char(ev, 'g'): gap = 1 - gap
			case hnoss.is_char(ev, 'd'): dialog = !dialog
			}
		}
		if term.error != .None {
			break
		}
	}
}

draw :: proc(f: ^hnoss.Frame, gap: int, dialog: bool) {
	area := f.area

	// Cuts: peel the chrome off the edges.
	header := hnoss.cut_top(&area, 1)
	status := hnoss.cut_bottom(&area, 1)
	panel(f, header, "header · cut_top(&area, 1)", .Blue)
	panel(f, status, "status · cut_bottom(&area, 1)   g gaps · d dialog · q quit", .Bright_Black)

	area = hnoss.inset(area, gap)
	sidebar := hnoss.cut_left(&area, 26)
	hnoss.cut_left(&area, gap)
	panel(f, sidebar, "sidebar\ncut_left(&area, 26)", .Magenta)

	// Split: proportional rows, then columns inside the first row.
	rows := hnoss.split(area, .Vertical, {hnoss.percent(40), hnoss.fill(), 3}, gap = gap)
	cols := hnoss.split(rows[0], .Horizontal, {hnoss.fill(2), hnoss.fill(1)}, gap = gap)
	panel(f, cols[0], "fill(2)", .Green)
	panel(f, cols[1], "fill(1)", .Cyan)
	panel(f, rows[2], "3 cells", .Yellow)

	// Grid in the middle row.
	for row in 0 ..< 2 {
		for col in 0 ..< 4 {
			cell := hnoss.grid_cell(rows[1], 4, 2, col, row, gap = gap)
			colors := [?]style.Named_Color{.Red, .Bright_Red, .Bright_Blue, .Bright_Green}
			panel(f, cell, fmt.tprintf("grid %d,%d", col, row), colors[(row * 4 + col) % 4])
		}
	}

	if dialog {
		box := hnoss.center(f.area, 44, 7)
		panel(f, box, "center(f.area, 44, 7)\n\n[b]Salam![/] This box stays centered\nwhatever the terminal size.", .White)
	}
}

// A filled rectangle with a label and its own size in the corner.
panel :: proc(f: ^hnoss.Frame, r: hnoss.Rect, label: string, color: style.Named_Color) {
	if r.width <= 0 || r.height <= 0 {
		return
	}
	fg := style.Named_Color.Black
	if color == .Blue || color == .Bright_Black || color == .Magenta || color == .Red {
		fg = .White
	}
	buffer.fill(f.buffer, r, {fg = fg, bg = color})
	inner := hnoss.pad(r, 0, 1, 0, 1)
	hnoss.markup(f, inner, label, wrap = .Ellipsis)
	size := fmt.tprintf("%dx%d", r.width, r.height)
	if r.height > 1 {
		hnoss.markup(f, hnoss.Rect{inner.x, r.y + r.height - 1, inner.width, 1}, size, wrap = .Clip, align = .Right, base = {add = {.Dim}})
	}
}
