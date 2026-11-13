package widgets

import "core:math"
import "core:time"
import "core:unicode/utf8"
import "../buffer"
import "../input"
import "../layout"
import "../pen"

Toast_Kind :: enum u8 {
	Info,
	Success,
	Warning,
	Error,
}

// How many toasts are kept at once; a new one beyond it drops the oldest.
MAX_TOASTS :: 6

// The toasts on screen, kept in Memory (no allocation: the text is copied
// into a fixed buffer, cut at TOAST_MAX_LEN bytes).
Toasts :: struct {
	items: [MAX_TOASTS]Toast,
	count: int,
	tick:  time.Tick, // when they were last drawn, for the animation
}

TOAST_MAX_LEN :: 240

@(private)
Toast :: struct {
	buf:      [TOAST_MAX_LEN]u8,
	len:      int,
	kind:     Toast_Kind,
	born:     time.Tick,
	duration: time.Duration,
	y:        f64,  // rows below the top margin, easing toward its place
	placed:   bool, // drawn at least once (y means something)
	moving:   bool, // still easing: keep drawing frames
	area:     Rect, // where it was drawn, for clicks
}

// Shows a short markup message in the top-right corner, over everything
// else, for `duration` (0: 4 s, warnings 6 s, errors 8 s). Several stack,
// oldest on top; when one goes away the ones below slide up. Clicking one
// dismisses it (and the click goes no further). Call it on any frame, e.g.
// when a save finishes:
//
//	if saved { hnoss.toast(ui, "Saved [b]notes.txt[/]", .Success) }
//
// They expire and slide even when no input comes, so wait for input with
// hnoss.toast_timeout(&term, ms) instead of a fixed timeout while they show.
toast :: proc(ui: ^Ui, message: string, kind := Toast_Kind.Info, duration: time.Duration = 0) {
	ts := &ui.mem.toasts
	if ts.count == MAX_TOASTS {
		copy(ts.items[:], ts.items[1:])
		ts.count -= 1
	}
	t := &ts.items[ts.count]
	ts.count += 1
	t^ = {kind = kind, born = ui.now, duration = duration if duration > 0 else TOAST_DURATION[kind]}
	n := min(len(message), TOAST_MAX_LEN)
	for n < len(message) && n > 0 && !utf8.rune_start(message[n]) { n -= 1 } // don't cut a character
	t.len = copy(t.buf[:], message[:n])
}

// Milliseconds the app can wait for input before the toasts need another
// frame (to slide or to go away), at most `wait_ms` (-1: no limit). With
// no toasts it is `wait_ms`.
toast_timeout :: proc(mem: ^Memory, now: time.Tick, wait_ms: int) -> int {
	ts := &mem.toasts
	need := -1
	for &t in ts.items[:ts.count] {
		ms := 16 // a frame at 60 fps while sliding
		if !t.moving {
			left := t.duration - time.tick_diff(t.born, now)
			ms = max(int(math.ceil(time.duration_milliseconds(left))), 0) + 1
		}
		need = ms if need < 0 else min(need, ms)
	}
	switch {
	case need < 0:    return wait_ms
	case wait_ms < 0: return need
	}
	return min(need, wait_ms)
}

// A press on a toast drawn last frame dismisses it; every mouse event over
// one is marked handled, so the widgets under it never see it.
@(private)
toast_clicks :: proc(ui: ^Ui, events: []input.Event) {
	ts := &ui.mem.toasts
	for ev, i in events {
		m, ok := ev.(input.Mouse)
		if !ok { continue }
		for k in 0 ..< ts.count {
			if !layout.rect_contains(ts.items[k].area, m.x, m.y) { continue }
			if m.kind == .Press && m.button == .Left {
				copy(ts.items[k:], ts.items[k + 1:ts.count])
				ts.count -= 1
			}
			ui.handled[i] = true
			break
		}
	}
}

// Drops expired toasts and draws the rest; called by `end`.
@(private)
draw_toasts :: proc(ui: ^Ui) {
	ts := &ui.mem.toasts
	kept := 0
	for t in ts.items[:ts.count] {
		if time.tick_diff(t.born, ui.now) < t.duration {
			ts.items[kept] = t
			kept += 1
		}
	}
	ts.count = kept
	dt := clamp(time.duration_seconds(time.tick_diff(ts.tick, ui.now)), 0, 0.1)
	ts.tick = ui.now

	if ts.count == 0 {
		return
	}
	clip := buffer.set_clip(ui.buf, ui.buf.area) // not cut by a scroll view
	defer buffer.set_clip(ui.buf, clip)
	area := ui.area
	max_w := min(TOAST_MAX_WIDTH, area.width - 2)
	slot := 0
	for &t in ts.items[:ts.count] {
		t.area = {}
		if max_w < 8 { continue } // no room for a toast at all
		msg := string(t.buf[:t.len])
		// Border, icon and a space take 4 cells; up to 4 lines of text.
		text_w := clamp(markup_width(msg), 8, max_w - 4)
		lines := clamp(count_lines(msg, text_w, .Word), 1, 4)
		w, h := text_w + 4, lines + 2

		target := f64(slot)
		slot += h
		if !t.placed {
			t.y, t.placed = target, true
		} else {
			t.y += (target - t.y) * (1 - math.exp(-dt * 14))
			if abs(target - t.y) < 0.05 { t.y = target }
		}
		t.moving = t.y != target

		r := Rect{area.x + area.width - 1 - w, area.y + 1 + int(math.round(t.y)), w, h}
		if r.y + r.height > area.y + area.height {
			continue // no room below: waits its turn
		}
		t.area = r
		kind_style := ui.theme.info
		switch t.kind {
		case .Info:    kind_style = ui.theme.info
		case .Success: kind_style = ui.theme.success
		case .Warning: kind_style = ui.theme.warning
		case .Error:   kind_style = ui.theme.error
		}
		blank(ui.buf, r)
		inner := box(ui, r, "", {style = kind_style, fill = ui.theme.modal})
		buffer.set_symbol(ui.buf, inner.x, inner.y, TOAST_ICON[t.kind], 1, kind_style)
		p := pen.begin(ui.buf, {inner.x + 2, inner.y, inner.width - 2, inner.height}, .Word, base = ui.theme.text)
		pen.markup(&p, msg)
		pen.finish(&p)
	}
}

@(private)
TOAST_MAX_WIDTH :: 44

@(private, rodata)
TOAST_ICON := [Toast_Kind]string {
	.Info    = "•",
	.Success = "✓",
	.Warning = "!",
	.Error   = "✗",
}

@(private, rodata)
TOAST_DURATION := [Toast_Kind]time.Duration {
	.Info    = 4 * time.Second,
	.Success = 4 * time.Second,
	.Warning = 6 * time.Second,
	.Error   = 8 * time.Second,
}
