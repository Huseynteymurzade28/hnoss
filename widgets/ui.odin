package widgets

import "../buffer"
import "../input"
import "../layout"
import "../style"

Rect :: layout.Rect
Style :: style.Style

// What one frame of widgets works with: where to draw, this frame's
// events, and the bits of state that outlive a frame (Memory).
//
// Widgets are procedures: calling one draws it, handles the input meant
// for it and reports what happened. Stateful widgets take a pointer to a
// state struct you own; that pointer is also the widget's identity for
// focus.
Ui :: struct {
	buf:     ^buffer.Buffer,
	area:    Rect, // the whole frame
	events:  []input.Event,
	handled: []bool, // parallel to events: consumed by a widget
	mem:     ^Memory,
	cursor:  ^Cursor,
	theme:   Theme,
	held:    []input.Event, // this frame's events, held back from the widgets under a modal

	// While a popup (a select's options) was open last frame, it gets the
	// whole frame's input: `popup` is its `open` flag, `popup_events` the
	// events, and nobody else sees any.
	popup:        ^bool,
	popup_events: []input.Event,
	overlay:      Maybe(Overlay), // drawn over everything by `end`
}

// A popup list to draw on top of the frame once every widget is drawn.
@(private)
Overlay :: struct {
	area:     Rect, // with its border
	items:    []string,
	selected: int,
	offset:   int,
	markup:   bool,
}

// State kept across frames, owned by the Terminal.
Memory :: struct {
	focus:  rawptr, // state pointer of the widget receiving keys
	active: rawptr, // widget being dragged with the mouse
	modal:  ^bool,  // `open` of the modal drawn last frame
	popup:  ^bool,  // `open` of the popup drawn last frame
}

// Where to show the terminal's own cursor after this frame (TextInput
// puts it at the caret). Reset to hidden every frame.
Cursor :: struct {
	x, y:    int,
	visible: bool,
	shape:   Cursor_Shape,
	blink:   bool,
}

// .Default leaves the shape the user configured in their terminal.
Cursor_Shape :: enum u8 {
	Default,
	Block,
	Underline,
	Bar,
}

begin :: proc(buf: ^buffer.Buffer, events: []input.Event, mem: ^Memory, cursor: ^Cursor, theme := DEFAULT_THEME) -> ^Ui {
	ui := new(Ui, context.temp_allocator)
	ui^ = {
		buf     = buf,
		area    = buf.area,
		events  = events,
		handled = make([]bool, len(events), context.temp_allocator),
		mem     = mem,
		cursor  = cursor,
		theme   = theme,
	}
	// An open popup takes every event, even from inside a modal. While a
	// modal is open, the widgets drawn before it see no events; `modal`
	// hands them back.
	if mem.popup != nil && mem.popup^ {
		ui.popup = mem.popup
		ui.popup_events = events
		ui.events = events[:0]
	} else if mem.modal != nil && mem.modal^ {
		ui.held = events
		ui.events = events[:0]
	}
	mem.modal = nil
	mem.popup = nil
	return ui
}

// Finishes this frame's widgets by drawing the overlay layer (an open
// select's options) over everything else. end_frame calls it for you.
end :: proc(ui: ^Ui) {
	o, ok := ui.overlay.?
	if !ok {
		return
	}
	ui.overlay = nil
	clip := buffer.set_clip(ui.buf, ui.buf.area) // not cut by a scroll view
	defer buffer.set_clip(ui.buf, clip)
	events := ui.events
	ui.events = nil // the scrollbar only draws
	defer ui.events = events

	blank(ui.buf, o.area)
	rows := box(ui, o.area, "", {focused = true, fill = ui.theme.modal})
	offset := o.offset
	if len(o.items) > rows.height {
		scrollbar(ui, layout.cut_right(&rows, 1), len(o.items), rows.height, &offset)
	}
	draw_rows(ui, rows, o.items, o.selected, o.offset, ui.theme.selected, "› ", o.markup)
}

// Gives keyboard focus to the widget whose state is `id` (nil: nobody).
focus :: proc(ui: ^Ui, id: rawptr) {
	ui.mem.focus = id
}

focused :: proc(ui: ^Ui, id: rawptr) -> bool {
	return id != nil && ui.mem.focus == id
}

// Tab / Shift+Tab move focus through `order` (wrapping around). If nothing
// in `order` has focus yet, the first widget gets it.
//
//	hnoss.focus_order(ui, {&list, &search})
focus_order :: proc(ui: ^Ui, order: []rawptr) {
	if len(order) == 0 {
		return
	}
	cur := -1
	for id, i in order {
		if id == ui.mem.focus { cur = i }
	}
	if cur < 0 {
		ui.mem.focus = order[0]
		cur = 0
	}
	for ev, i in ui.events {
		if ui.handled[i] { continue }
		k, ok := ev.(input.Key)
		if !ok { continue }
		switch {
		case k.code == .Tab && k.mods == {}:
			cur = (cur + 1) % len(order)
		case k.code == .Back_Tab:
			cur = (cur + len(order) - 1) % len(order)
		case:
			continue
		}
		ui.mem.focus = order[cur]
		ui.handled[i] = true
	}
}

// The events no widget consumed this frame, for the app's own shortcuts.
// Call it after drawing the widgets.
unhandled :: proc(ui: ^Ui) -> []input.Event {
	out := make([dynamic]input.Event, 0, len(ui.events), context.temp_allocator)
	for ev, i in ui.events {
		if !ui.handled[i] { append(&out, ev) }
	}
	return out[:]
}

// Iterates this frame's not-yet-consumed key events, but only when the
// widget `id` has focus. Mark one as used with `consume(ui, i)`.
//
//	for k, i in next_key(ui, id, &it) { ... consume(ui, i) }
Key_Iter :: struct {
	i: int,
}

next_key :: proc(ui: ^Ui, id: rawptr, it: ^Key_Iter) -> (k: input.Key, index: int, ok: bool) {
	if !focused(ui, id) {
		return
	}
	for it.i < len(ui.events) {
		i := it.i
		it.i += 1
		if ui.handled[i] { continue }
		if key, is_key := ui.events[i].(input.Key); is_key {
			return key, i, true
		}
	}
	return
}

// Like next_key for mouse events inside `area` and the buffer's clip (or
// anywhere, while `id` is the widget being dragged). Focus is not required.
next_mouse :: proc(ui: ^Ui, id: rawptr, area: Rect, it: ^Key_Iter) -> (m: input.Mouse, index: int, ok: bool) {
	for it.i < len(ui.events) {
		i := it.i
		it.i += 1
		if ui.handled[i] { continue }
		if mouse, is_mouse := ui.events[i].(input.Mouse); is_mouse {
			dragging := id != nil && ui.mem.active == id
			inside := layout.rect_contains(area, mouse.x, mouse.y) && layout.rect_contains(ui.buf.clip, mouse.x, mouse.y)
			if dragging || inside {
				return mouse, i, true
			}
		}
	}
	return
}

consume :: proc(ui: ^Ui, index: int) {
	ui.handled[index] = true
}
