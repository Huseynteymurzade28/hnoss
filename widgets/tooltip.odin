package widgets

import "core:math"
import "core:time"
import "../buffer"
import "../input"
import "../layout"
import "../pen"

// How long the pointer rests on a widget before its tooltip opens.
TOOLTIP_DELAY :: 500 * time.Millisecond

@(private)
TOOLTIP_MAX_WIDTH :: 40

// The tooltip the pointer is waiting for or looking at, kept in Memory.
Tooltip_State :: struct {
	id:     rawptr,        // the widget under the pointer that has one
	since:  time.Tick,     // when the pointer came to rest on it
	delay:  time.Duration,
	shown:  bool,
	closed: bool,          // dismissed by a key or a click, until the pointer leaves
}

// What `end` draws for the open tooltip.
@(private)
Tooltip :: struct {
	anchor: Rect,
	text:   string,
}

// A short markup text that opens next to `area` once the pointer has
// rested there for `delay`, over every other widget. It goes under the
// area, or above it when there is no room below, and shifts left to stay
// on the screen; long text wraps in at most 40 cells. Moving the pointer
// away closes it, and so does any key, click or wheel (until the pointer
// has left and come back). Call it right after the widget it explains,
// with that widget's state and area:
//
//	if hnoss.button(ui, row, "Save", &save) { ... }
//	hnoss.tooltip(ui, &save, row, "Write the file ([b]Ctrl+S[/])")
//
// `id` only tells tooltips apart; anything with a stable address does for
// a widget without state. For a tall widget pass the row the text is about,
// not the whole area. Like hover it needs .Mouse_Capture, and shows nothing
// under a modal, an open select or a toast, or while a widget is dragged.
//
// It opens without any input, so wait for input with
// hnoss.timeout(&term, ms) instead of a fixed timeout.
tooltip :: proc(ui: ^Ui, id: rawptr, area: Rect, text: string, delay := TOOLTIP_DELAY) {
	if id == nil || text == "" || !pointer_on(ui, id, area) {
		return
	}
	t := &ui.mem.tooltip
	ui.tooltip_seen = true
	if t.id != id {
		t^ = {id = id, since = ui.now}
	}
	t.delay = delay
	switch {
	case ui.pointer_acted:
		t.closed, t.shown = true, false
	case ui.pointer_moved && !t.shown:
		t.since = ui.now // not resting yet
	}
	if !t.closed && time.tick_diff(t.since, ui.now) >= delay {
		t.shown = true
	}
	if t.shown {
		ui.tooltip = Tooltip{layout.rect_intersection(area, ui.buf.clip), text}
	}
}

// Milliseconds the app can wait for input before a tooltip is due to
// open, at most `wait_ms` (-1: no limit). `wait_ms` when none is pending.
tooltip_timeout :: proc(mem: ^Memory, now: time.Tick, wait_ms: int) -> int {
	t := mem.tooltip
	if t.id == nil || t.shown || t.closed {
		return wait_ms
	}
	left := t.delay - time.tick_diff(t.since, now)
	need := max(int(math.ceil(time.duration_milliseconds(left))), 0) + 1
	return need if wait_ms < 0 else min(need, wait_ms)
}

// How long to wait for input so that everything that happens by itself
// (toasts sliding and expiring, a tooltip opening) still gets its frame.
timeout :: proc(mem: ^Memory, now: time.Tick, wait_ms: int) -> int {
	return tooltip_timeout(mem, now, toast_timeout(mem, now, wait_ms))
}

// What this frame's events mean to a tooltip: the pointer moved (it is not
// resting), or something was pressed, clicked or scrolled (it closes).
@(private)
tooltip_events :: proc(ui: ^Ui, events: []input.Event) {
	for ev in events {
		#partial switch e in ev {
		case input.Key:
			ui.pointer_acted = true
		case input.Mouse:
			if e.kind == .Move { ui.pointer_moved = true } else { ui.pointer_acted = true }
		}
	}
}

// Draws the open tooltip; called by `end`, which also forgets the one of
// a widget the pointer is no longer on.
@(private)
draw_tooltip :: proc(ui: ^Ui) {
	if !ui.tooltip_seen {
		ui.mem.tooltip = {}
	}
	tip, ok := ui.tooltip.?
	if !ok {
		return
	}
	ui.tooltip = nil
	max_w := min(TOOLTIP_MAX_WIDTH, ui.area.width)
	if max_w < 3 {
		return
	}
	// A cell of padding on each side of the text; as wide as its longest line
	// once wrapped.
	m := pen.begin(nil, {0, 0, max_w - 2, 0}, .Word)
	pen.markup(&m, tip.text)
	lines := max(pen.finish(&m), 1)
	r := place_popup(ui.area, tip.anchor, clamp(m.max_width, 1, max_w - 2) + 2, lines)

	clip := buffer.set_clip(ui.buf, ui.buf.area) // not cut by a scroll view
	defer buffer.set_clip(ui.buf, clip)
	blank(ui.buf, r)
	buffer.fill(ui.buf, r, ui.theme.tooltip)
	p := pen.begin(ui.buf, {r.x + 1, r.y, r.width - 2, r.height}, .Word, base = ui.theme.tooltip)
	pen.markup(&p, tip.text)
	pen.finish(&p)
}
