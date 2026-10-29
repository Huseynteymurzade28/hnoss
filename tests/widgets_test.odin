package tests

import "core:testing"
import "../buffer"
import "../input"
import "../widgets"

// A tiny harness: a buffer, persistent widget memory and a cursor, so a
// test can run "frames" with hand-made events.
@(private = "file")
Harness :: struct {
	buf:    buffer.Buffer,
	mem:    widgets.Memory,
	cursor: widgets.Cursor,
}

@(private = "file")
harness :: proc(w, h: int) -> ^Harness {
	hs := new(Harness, context.temp_allocator)
	buffer.init(&hs.buf, {0, 0, w, h}, context.temp_allocator)
	return hs
}

@(private = "file")
frame :: proc(hs: ^Harness, events: ..input.Event) -> ^widgets.Ui {
	buffer.reset(&hs.buf)
	hs.cursor = {}
	evs := make([]input.Event, len(events), context.temp_allocator)
	copy(evs, events)
	return widgets.begin(&hs.buf, evs, &hs.mem, &hs.cursor)
}

@(private = "file")
key :: proc(code: input.Key_Code, mods: input.Key_Modifiers = {}) -> input.Event {
	return input.Key{code = code, mods = mods}
}

@(private = "file")
ch :: proc(r: rune, mods: input.Key_Modifiers = {}) -> input.Event {
	return input.Key{code = .Char, char = r, mods = mods}
}

@(private = "file")
click :: proc(x, y: int, kind := input.Mouse_Kind.Press) -> input.Event {
	return input.Mouse{kind = kind, button = .Left if kind != .Release else .Left, x = x, y = y}
}

@(private = "file")
wheel :: proc(x, y: int, down: bool) -> input.Event {
	return input.Mouse{kind = .Scroll, button = .Wheel_Down if down else .Wheel_Up, x = x, y = y}
}

@(private = "file")
expect_rows :: proc(t: ^testing.T, got: []string, want: ..string, loc := #caller_location) {
	for i in 0 ..< max(len(got), len(want)) {
		g := got[i] if i < len(got) else "<none>"
		w := want[i] if i < len(want) else ""
		testing.expectf(t, g == w, "row %d = %q, want %q", i, g, w, loc = loc)
	}
}

@(test)
widget_box_borders_and_title :: proc(t: ^testing.T) {
	hs := harness(12, 4)
	ui := frame(hs)
	inner := widgets.box(ui, ui.area, "Hi")
	testing.expect_value(t, inner, widgets.Rect{1, 1, 10, 2})
	expect_rows(t, screen_rows(&hs.buf), "╭ Hi ──────╮", "│          │", "│          │", "╰──────────╯")

	ui = frame(hs)
	widgets.box(ui, ui.area, "a very long title", {border = .Double, align = .Right})
	expect_rows(t, screen_rows(&hs.buf)[:1], "╔ a very … ╗")
}

@(test)
widget_paragraph_scrolls_with_focus_and_wheel :: proc(t: ^testing.T) {
	hs := harness(10, 2)
	st: widgets.Scroll_State
	text := "one\ntwo\nthree\nfour\nfive"

	// Not focused: keys are ignored and left for the app.
	ui := frame(hs, key(.Down))
	widgets.paragraph(ui, ui.area, text, &st)
	testing.expect_value(t, st.offset, 0)
	testing.expect_value(t, len(widgets.unhandled(ui)), 1)

	widgets.focus(ui, &st)
	ui = frame(hs, key(.Down), key(.Down))
	total := widgets.paragraph(ui, ui.area, text, &st)
	testing.expect_value(t, total, 5)
	testing.expect_value(t, len(widgets.unhandled(ui)), 0)
	expect_rows(t, screen_rows(&hs.buf), "three", "four")

	ui = frame(hs, key(.End))
	widgets.paragraph(ui, ui.area, text, &st)
	expect_rows(t, screen_rows(&hs.buf), "four", "five")

	ui = frame(hs, wheel(1, 1, false))
	widgets.paragraph(ui, ui.area, text, &st)
	testing.expect_value(t, st.offset, 0) // clamped at the top
}

@(test)
widget_paragraph_scrollbar :: proc(t: ^testing.T) {
	hs := harness(6, 4)
	st: widgets.Scroll_State
	ui := frame(hs)
	widgets.paragraph(ui, ui.area, "1\n2\n3\n4\n5\n6\n7\n8", &st, {scrollbar = true})
	rows := screen_rows(&hs.buf)
	expect_rows(t, rows, "1    ┃", "2    ┃", "3    │", "4    │")
}

@(test)
widget_scrollbar_click_and_drag :: proc(t: ^testing.T) {
	hs := harness(1, 10)
	offset := 0
	// 100 lines, 10 visible: thumb is 1 cell, travel 9, max offset 90.
	ui := frame(hs, click(0, 9))
	changed := widgets.scrollbar(ui, ui.area, 100, 10, &offset)
	testing.expect(t, changed)
	testing.expect_value(t, offset, 90)
	testing.expect_value(t, hs.mem.active, rawptr(&offset))

	// Dragging keeps working outside the bar's column.
	ui = frame(hs, input.Mouse{kind = .Drag, button = .Left, x = 7, y = 0})
	widgets.scrollbar(ui, ui.area, 100, 10, &offset)
	testing.expect_value(t, offset, 0)

	ui = frame(hs, input.Mouse{kind = .Release, button = .Left, x = 7, y = 3})
	widgets.scrollbar(ui, ui.area, 100, 10, &offset)
	testing.expect_value(t, hs.mem.active, nil)
	testing.expect_value(t, len(widgets.unhandled(ui)), 0)
}

@(test)
widget_focus_order_cycles_with_tab :: proc(t: ^testing.T) {
	hs := harness(4, 1)
	a, b, c: widgets.Scroll_State
	ui := frame(hs)
	widgets.focus_order(ui, {&a, &b, &c})
	testing.expect(t, widgets.focused(ui, &a))

	ui = frame(hs, key(.Tab), key(.Tab))
	widgets.focus_order(ui, {&a, &b, &c})
	testing.expect(t, widgets.focused(ui, &c))

	ui = frame(hs, key(.Back_Tab), ch('x'))
	widgets.focus_order(ui, {&a, &b, &c})
	testing.expect(t, widgets.focused(ui, &b))
	rest := widgets.unhandled(ui)
	testing.expect_value(t, len(rest), 1)
	testing.expect_value(t, rest[0], ch('x'))
}
