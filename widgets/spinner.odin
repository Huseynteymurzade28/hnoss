package widgets

import "core:time"
import "../buffer"
import "../pen"
import "../style"
import "../text"

Spinner_Kind :: enum u8 {
	Dots, // ⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏
	Line, // - \ | /
	Arc,  // ◜ ◠ ◝ ◞ ◡ ◟
}

Spinner_Options :: struct {
	kind:     Spinner_Kind,
	interval: time.Duration, // time per frame; 0: the kind's own speed
	style:    Maybe(Style),  // the spinning symbol; default theme.accent
}

// A one-cell activity indicator on the first row of `area`, followed by
// an optional markup `label`. The frame shown comes from `elapsed`, so it
// spins at the same speed whatever the frame rate:
//
//	start := time.tick_now()
//	...
//	hnoss.spinner(ui, area, time.tick_since(start), "Loading [dim]packages[/]")
spinner :: proc(ui: ^Ui, area: Rect, elapsed: time.Duration, label := "", opts := Spinner_Options{}) {
	if area.width <= 0 || area.height <= 0 {
		return
	}
	frames := SPINNER_FRAMES[opts.kind]
	step := opts.interval if opts.interval > 0 else SPINNER_INTERVAL[opts.kind]
	sym := frames[int(max(elapsed, 0) / step) % len(frames)]
	w := max(text.width(sym), 1)
	st := style.patch(ui.theme.accent, opts.style.? or_else {})
	buffer.set_symbol(ui.buf, area.x, area.y, sym, w, st)

	if label == "" || area.width <= w + 1 {
		return
	}
	rest := Rect{area.x + w + 1, area.y, area.width - w - 1, 1}
	p := pen.begin(ui.buf, rest, .Ellipsis, .Left)
	pen.markup(&p, label, ui.theme.text)
	pen.finish(&p)
}

@(private, rodata)
SPINNER_FRAMES := [Spinner_Kind][]string {
	.Dots = {"⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"},
	.Line = {"-", "\\", "|", "/"},
	.Arc  = {"◜", "◠", "◝", "◞", "◡", "◟"},
}

@(private, rodata)
SPINNER_INTERVAL := [Spinner_Kind]time.Duration {
	.Dots = 80 * time.Millisecond,
	.Line = 130 * time.Millisecond,
	.Arc  = 100 * time.Millisecond,
}
