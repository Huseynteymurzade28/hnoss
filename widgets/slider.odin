package widgets

import "core:fmt"
import "core:math"
import "core:strconv"
import "../buffer"
import "../input"
import "../layout"
import "../text"

Slider_Options :: struct {
	step:       f64,    // what one key press moves; 0: a hundredth of the range
	show_value: bool,   // the value after the track
	format:     string, // fmt format for it, e.g. "%.0f%%"; "": as many decimals as `step` has
}

// A horizontal slider on the first row of `area`: "━━━━●────── 40".
// While focused, ← → (h l) move it by a step, PgUp PgDn (Shift+← →) by ten
// and Home End to the ends; ↑ ↓ are left for the app. Pressing the track
// focuses it and jumps there, dragging moves it and the wheel steps it.
// The value is kept on a step from `min_value` and inside the range.
// `value` is the widget's identity for focus. Returns true when it changed.
//
//	hnoss.slider(ui, row, &volume, 0, 100, {step = 5, show_value = true})
slider :: proc(ui: ^Ui, area: Rect, value: ^f64, min_value, max_value: f64, opts := Slider_Options{}) -> (changed: bool) {
	if area.width <= 0 || area.height <= 0 || !(max_value > min_value) {
		return false
	}
	old := value^
	step := opts.step if opts.step > 0 else (max_value - min_value) / 100
	decimals := step_decimals(step)
	format := opts.format if opts.format != "" else fmt.tprintf("%%.%df", decimals)

	// The label gets the room of the widest end, so the track keeps its length.
	track := Rect{area.x, area.y, area.width, 1}
	label_w := 0
	if opts.show_value {
		label_w = max(text.width(fmt.tprintf(format, min_value)), text.width(fmt.tprintf(format, max_value)))
		if track.width - label_w - 1 < 2 {
			label_w = 0 // no room: the track matters more
		} else {
			track.width -= label_w + 1
		}
	}

	it: Key_Iter
	for k, i in next_key(ui, value, &it) {
		shift := .Shift in k.mods
		used := true
		#partial switch k.code {
		case .Left:      value^ -= step * (10 if shift else 1)
		case .Right:     value^ += step * (10 if shift else 1)
		case .Page_Down: value^ -= step * 10
		case .Page_Up:   value^ += step * 10
		case .Home:      value^ = min_value
		case .End:       value^ = max_value
		case .Char:
			switch {
			case k.char == 'h' && k.mods == {}: value^ -= step
			case k.char == 'l' && k.mods == {}: value^ += step
			case: used = false
			}
		case:
			used = false
		}
		if used {
			value^ = clamp(value^, min_value, max_value) // so ← after → at the end moves back
			consume(ui, i)
		}
	}

	// Value whose knob would sit in column x.
	value_at :: proc(track: Rect, x: int, lo, hi: f64) -> f64 {
		if track.width <= 1 { return lo }
		r := clamp(f64(x - track.x) / f64(track.width - 1), 0, 1)
		return lo + r * (hi - lo)
	}
	mit: Key_Iter
	for m, i in next_mouse(ui, value, track, &mit) {
		#partial switch m.kind {
		case .Press:
			if m.button != .Left { continue }
			ui.mem.focus = value
			ui.mem.active = value
			value^ = value_at(track, m.x, min_value, max_value)
		case .Drag:
			if ui.mem.active != value { continue }
			value^ = value_at(track, m.x, min_value, max_value)
		case .Release:
			if ui.mem.active != value { continue }
			ui.mem.active = nil
		case .Scroll:
			#partial switch m.button {
			case .Wheel_Up, .Wheel_Right:  value^ += step
			case .Wheel_Down, .Wheel_Left: value^ -= step
			}
		case:
			continue
		}
		consume(ui, i)
	}

	// Snap to a step (the max is reachable even when the range isn't a
	// whole number of steps), rounded to the step's decimals so 3 × 0.3
	// is 0.9.
	v := clamp(value^, min_value, max_value)
	if v != max_value {
		v = min_value + math.round((v - min_value) / step) * step
		scale := math.pow(10, f64(decimals))
		v = clamp(math.round(v * scale) / scale, min_value, max_value)
	}
	value^ = v

	ratio := (v - min_value) / (max_value - min_value)
	knob := int(math.round(ratio * f64(track.width - 1)))
	knob_style := ui.theme.selected if focused(ui, value) else ui.theme.accent
	for col in 0 ..< track.width {
		sym, st := "─", ui.theme.muted
		switch {
		case col < knob:  sym, st = "━", ui.theme.accent
		case col == knob: sym, st = "●", knob_style
		}
		buffer.set_symbol(ui.buf, track.x + col, track.y, sym, 1, st)
	}
	if label_w > 0 {
		lbl := fmt.tprintf(format, v)
		x := area.x + area.width - label_w
		buffer.set_string(ui.buf, x + max(label_w - text.width(lbl), 0), area.y, lbl, ui.theme.text, label_w)
	}
	return value^ != old
}

Number_Options :: struct {
	min, max: Maybe(f64), // nil: no limit
	step:     f64,        // what ↑ ↓ and the wheel add; 0: 1
	decimals: int,        // digits after the point; 0: whole numbers only
}

// State of a number_input. Set `value` freely while the field isn't
// focused; while it is, the text being typed is in the fields below.
Number_State :: struct {
	value:     f64,
	submitted: bool, // Enter was pressed this frame

	// The text while focused (internal).
	editing:   bool,
	buf:       [NUMBER_MAX_LEN]u8,
	len:       int,
	cursor:    int,
	scroll:    int,
}

@(private)
NUMBER_MAX_LEN :: 32

// A one-line number field with "− +" at its right end. While focused,
// ↑ ↓ (PgUp PgDn: ten times as much) step it, and typing edits it like an
// input, but only keys that keep it a number are taken (digits, one point
// when `decimals` > 0, a leading minus when it can go below zero). The
// text becomes the value, clamped and rounded, on Enter (which sets
// state.submitted), a step, or losing focus; Esc puts back the value.
// Clicking focuses it; clicking "−" or "+" or the wheel steps it.
// Returns true when `state.value` changed.
//
//	hnoss.number_input(ui, row, &qty, {min = 1, max = 99})
number_input :: proc(ui: ^Ui, area: Rect, state: ^Number_State, opts := Number_Options{}) -> (changed: bool) {
	state.submitted = false
	if area.width <= 0 || area.height <= 0 {
		return false
	}
	old := state.value
	step := opts.step if opts.step > 0 else 1
	state.value = number_clamp(state.value, opts)
	has_focus := focused(ui, state)
	if has_focus && !state.editing {
		number_load(state, opts)
	} else if !has_focus && state.editing {
		number_commit(state, opts)
		state.editing = false
	}

	W := area.width
	buttons := W >= 8 // "− +" take the last three cells
	field := Rect{area.x, area.y, W - 4 if buttons else W, 1}

	if has_focus {
		for ev, i in ui.events {
			if ui.handled[i] { continue }
			#partial switch e in ev {
			case input.Key:
				if number_key(state, e, opts, step) { consume(ui, i) }
			case input.Paste:
				tmp := number_text(state)
				insert(&tmp, single_line(e.text))
				number_keep(state, &tmp, opts)
				consume(ui, i)
			}
		}
	}

	it: Key_Iter
	for m, i in next_mouse(ui, nil, Rect{area.x, area.y, W, 1}, &it) {
		#partial switch m.kind {
		case .Press:
			if m.button != .Left { continue }
			ui.mem.focus = state
			if !state.editing { number_load(state, opts) }
			switch {
			case buttons && m.x == area.x + W - 3: number_step(state, opts, -step)
			case buttons && m.x == area.x + W - 1: number_step(state, opts, step)
			case layout.rect_contains(field, m.x, m.y):
				state.cursor = min(m.x - field.x + state.scroll, state.len)
			}
		case .Scroll:
			#partial switch m.button {
			case .Wheel_Up:   number_step(state, opts, step)
			case .Wheel_Down: number_step(state, opts, -step)
			case: continue
			}
		case:
			continue
		}
		consume(ui, i)
	}

	// Draw. Numbers are ASCII, so a byte is a cell.
	s := string(state.buf[:state.len]) if state.editing else number_format(state.value, opts)
	state.cursor = clamp(state.cursor, 0, state.len)
	if state.editing {
		if state.cursor - state.scroll >= field.width { state.scroll = state.cursor - field.width + 1 }
		if state.cursor < state.scroll { state.scroll = state.cursor }
	} else {
		state.scroll = 0
	}
	state.scroll = clamp(state.scroll, 0, max(len(s), 0))
	buffer.fill(ui.buf, Rect{area.x, area.y, W, 1}, ui.theme.input)
	buffer.set_string(ui.buf, field.x, field.y, s[state.scroll:], ui.theme.input, field.width)
	if buttons {
		buffer.set_symbol(ui.buf, area.x + W - 3, area.y, "−", 1, ui.theme.muted)
		buffer.set_symbol(ui.buf, area.x + W - 1, area.y, "+", 1, ui.theme.muted)
	}
	if x := field.x + state.cursor - state.scroll; has_focus && layout.rect_contains(ui.buf.clip, x, area.y) {
		ui.cursor^ = {x, area.y, true, .Bar, false}
	}
	return state.value != old
}

// One key for a focused number_input; true if it was used.
@(private)
number_key :: proc(state: ^Number_State, k: input.Key, opts: Number_Options, step: f64) -> bool {
	#partial switch k.code {
	case .Up:        number_step(state, opts, step)
	case .Down:      number_step(state, opts, -step)
	case .Page_Up:   number_step(state, opts, step * 10)
	case .Page_Down: number_step(state, opts, -step * 10)
	case .Enter:
		number_commit(state, opts)
		number_load(state, opts)
		state.submitted = true
	case .Esc:
		if string(state.buf[:state.len]) == number_format(state.value, opts) {
			return false // nothing to undo: let the app (or a modal) have it
		}
		number_load(state, opts)
	case .Tab, .Back_Tab:
		return false
	case:
		tmp := number_text(state)
		used, _ := edit_key(&tmp, k)
		number_keep(state, &tmp, opts)
		return used
	}
	return true
}

// The text as a (temp) Input_State, to edit with the input's keys; then
// number_keep takes the result back if it is still (the start of) a
// number this field accepts.
@(private)
number_text :: proc(state: ^Number_State) -> Input_State {
	tmp := Input_State{cursor = state.cursor}
	tmp.text = make([dynamic]u8, 0, NUMBER_MAX_LEN, context.temp_allocator)
	append(&tmp.text, string(state.buf[:state.len]))
	return tmp
}

@(private)
number_keep :: proc(state: ^Number_State, tmp: ^Input_State, opts: Number_Options) {
	s := string(tmp.text[:])
	if len(s) > NUMBER_MAX_LEN || !number_prefix(s, opts) {
		return
	}
	state.len = copy(state.buf[:], s)
	state.cursor = clamp(tmp.cursor, 0, state.len)
}

// Accepts what can still be typed into a number: "", "-", "12.", "-0.5".
@(private)
number_prefix :: proc(s: string, opts: Number_Options) -> bool {
	i := 0
	if i < len(s) && s[i] == '-' {
		lo, has_lo := opts.min.?
		if has_lo && lo >= 0 { return false }
		i += 1
	}
	for i < len(s) && s[i] >= '0' && s[i] <= '9' { i += 1 }
	if i < len(s) && s[i] == '.' {
		if opts.decimals <= 0 { return false }
		i += 1
		start := i
		for i < len(s) && s[i] >= '0' && s[i] <= '9' { i += 1 }
		if i - start > opts.decimals { return false }
	}
	return i == len(s)
}

// The typed text becomes the value; text that isn't a number yet ("", "-")
// leaves it as it was.
@(private)
number_commit :: proc(state: ^Number_State, opts: Number_Options) {
	if v, ok := strconv.parse_f64(string(state.buf[:state.len])); ok {
		state.value = number_clamp(v, opts)
	}
}

@(private)
number_step :: proc(state: ^Number_State, opts: Number_Options, by: f64) {
	if state.editing { number_commit(state, opts) }
	state.value = number_clamp(state.value + by, opts)
	if state.editing { number_load(state, opts) }
}

// Puts the value in the text, with the caret at the end.
@(private)
number_load :: proc(state: ^Number_State, opts: Number_Options) {
	state.len = copy(state.buf[:], number_format(state.value, opts))
	state.cursor = state.len
	state.editing = true
}

@(private)
number_clamp :: proc(v: f64, opts: Number_Options) -> f64 {
	scale := math.pow(10, f64(max(opts.decimals, 0)))
	r := math.round(v * scale) / scale
	if lo, ok := opts.min.?; ok { r = max(r, lo) }
	if hi, ok := opts.max.?; ok { r = min(r, hi) }
	return r
}

@(private)
number_format :: proc(v: f64, opts: Number_Options) -> string {
	v := v
	if v == 0 { v = 0 } // no "-0"
	return fmt.tprintf("%.*f", max(opts.decimals, 0), v)
}

// How many decimals `step` has (up to 6): 1 → 0, 0.25 → 2.
@(private)
step_decimals :: proc(step: f64) -> int {
	d := 0
	for d < 6 {
		x := step * math.pow(10, f64(d))
		if abs(x - math.round(x)) < 1e-9 { break }
		d += 1
	}
	return d
}
