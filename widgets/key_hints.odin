package widgets

import "../buffer"
import "../text"

// One entry of a key-hint bar or help page: `key` is what to press
// ("q", "Ctrl+S", "↑↓"), `desc` what it does.
Key_Hint :: struct {
	key, desc: string,
}

// The one-line `q quit · / search · ? help` bar, on the first row of
// `area`. Keys are drawn in theme.key, descriptions and separators in
// theme.muted. When they don't all fit, hints are dropped from the end and
// a `…` marks that some are missing, so put the important ones first.
//
//	hnoss.key_hints(ui, footer, {{"q", "quit"}, {"/", "search"}, {"?", "help"}})
key_hints :: proc(ui: ^Ui, area: Rect, hints: []Key_Hint, separator := " · ") {
	if area.width <= 0 || area.height <= 0 || len(hints) == 0 {
		return
	}
	sep_w := text.width(separator)
	more := " …"
	more_w := text.width(more)

	// How many hints fit, leaving room for " …" unless they all fit.
	fits, used := 0, 0
	for h, i in hints {
		w := hint_width(h) + (sep_w if i > 0 else 0)
		room := area.width - (0 if i == len(hints) - 1 else more_w)
		if used + w > room {
			break
		}
		fits, used = i + 1, used + w
	}

	x := area.x
	for h, i in hints[:fits] {
		if i > 0 {
			x = buffer.set_string(ui.buf, x, area.y, separator, ui.theme.muted)
		}
		x = draw_hint(ui, x, area.y, h)
	}
	if fits < len(hints) {
		s := more if fits > 0 else "…"
		buffer.set_string(ui.buf, x, area.y, s, ui.theme.muted, area.x + area.width - x)
	}
}

// A full list of hints, one per row: keys in a right-aligned column, then
// their descriptions. Meant for a help modal opened with `?`:
//
//	if help {
//		inner := hnoss.modal(ui, hnoss.center(f.area, 40, len(hints) + 2), &help, "Keys")
//		hnoss.key_help(ui, inner, hints)
//	}
//
// A hint with an empty key is a section heading, drawn in theme.title.
// Rows past the bottom of `area` are cut off.
key_help :: proc(ui: ^Ui, area: Rect, hints: []Key_Hint) {
	key_w := 0
	for h in hints {
		key_w = max(key_w, text.width(h.key))
	}
	for h, i in hints {
		if i >= area.height { break }
		y := area.y + i
		if h.key == "" {
			buffer.set_string(ui.buf, area.x, y, h.desc, ui.theme.title, area.width)
			continue
		}
		pad := key_w - text.width(h.key)
		x := buffer.set_string(ui.buf, area.x + pad, y, h.key, ui.theme.key, area.width - pad)
		x += 2
		if x < area.x + area.width {
			buffer.set_string(ui.buf, x, y, h.desc, ui.theme.text, area.x + area.width - x)
		}
	}
}

@(private)
hint_width :: proc(h: Key_Hint) -> int {
	w := text.width(h.key)
	if h.desc != "" {
		w += 1 + text.width(h.desc)
	}
	return w
}

@(private)
draw_hint :: proc(ui: ^Ui, x, y: int, h: Key_Hint) -> (end: int) {
	end = buffer.set_string(ui.buf, x, y, h.key, ui.theme.key)
	if h.desc != "" {
		end = buffer.set_string(ui.buf, end + 1, y, h.desc, ui.theme.muted)
	}
	return
}
