// A self-running demo that pushes hnoss hard on one screen: a gradient logo,
// a truecolor plasma, a shaded 3D torus on a braille canvas, live graphs,
// a table, gauges, and focus moving between widgets that are driven by
// scripted key presses. It plays an 18-second script on a loop.
//   q / Ctrl+C  quit
package main

import "core:fmt"
import "core:math"
import "core:os"
import "core:time"
import hnoss "../.."
import "../../backend"
import "../../buffer"

TEAL :: hnoss.Rgb{0x22, 0x84, 0x8c}
TEAL_LIGHT :: hnoss.Rgb{0x5f, 0xc4, 0xc9}
RED :: hnoss.Rgb{0xc4, 0x4e, 0x36}
RED_LIGHT :: hnoss.Rgb{0xf0, 0x8a, 0x6a}
GOLD :: hnoss.Rgb{0xe8, 0xc0, 0x60}
VIOLET :: hnoss.Rgb{0x9a, 0x7c, 0xe8}
BG :: hnoss.Rgb{0x0b, 0x11, 0x14}
PANEL :: hnoss.Rgb{0x23, 0x3a, 0x40}
TEXT :: hnoss.Rgb{0xdc, 0xe8, 0xea}
DIM :: hnoss.Rgb{0x6d, 0x86, 0x8c}

@(rodata) RAINBOW := [?]hnoss.Rgb{TEAL_LIGHT, TEAL, VIOLET, RED, RED_LIGHT, GOLD, TEAL_LIGHT}
@(rodata) HEAT := [?]hnoss.Rgb{TEAL, TEAL_LIGHT, GOLD, RED_LIGHT, RED}
@(rodata) DEPTH := [?]hnoss.Rgb{{0x1c, 0x3a, 0x44}, TEAL, TEAL_LIGHT, GOLD, {0xff, 0xf4, 0xd8}}

SCRIPT_SECONDS :: 18.0
SAMPLE_RATE :: 30.0 // graph samples per second, independent of the frame rate
FRAME_TIME :: time.Second / 60

theme :: proc() -> hnoss.Theme {
	t := hnoss.DEFAULT_THEME
	t.text = {fg = TEXT}
	t.muted = {fg = DIM}
	t.accent = {fg = TEAL_LIGHT}
	t.border = {fg = PANEL}
	t.border_focused = {fg = GOLD}
	t.title = {fg = TEXT, add = {.Bold}}
	t.selected = {fg = BG, bg = TEAL_LIGHT, add = {.Bold}}
	t.selected_unfocused = {bg = PANEL}
	t.header = {fg = RED_LIGHT, add = {.Bold}}
	t.gauge_filled = {fg = TEAL}
	t.gauge_empty = {bg = hnoss.Rgb{0x16, 0x24, 0x28}}
	t.tab = {fg = DIM}
	t.tab_selected = {fg = GOLD, add = {.Bold}}
	t.input = {fg = TEXT}
	t.scrollbar_track = {fg = PANEL}
	t.scrollbar_thumb = {fg = TEAL_LIGHT}
	return t
}

// What the script does and when, in seconds from the start of a loop.
Step :: struct {
	at:    f64,
	focus: int, // 0 none, 1 services, 2 regions, 3 command line
	ev:    hnoss.Event,
}

@(rodata) SCRIPT := [?]Step{
	{at = 1.6, focus = 1},
	{at = 2.2, focus = 1, ev = hnoss.Key{code = .Down}},
	{at = 2.7, focus = 1, ev = hnoss.Key{code = .Down}},
	{at = 3.2, focus = 1, ev = hnoss.Key{code = .Down}},
	{at = 3.7, focus = 1, ev = hnoss.Key{code = .Down}},
	{at = 4.4, focus = 1, ev = hnoss.Key{code = .Up}},
	{at = 5.2, focus = 2},
	{at = 5.8, focus = 2, ev = hnoss.Key{code = .Down}},
	{at = 6.3, focus = 2, ev = hnoss.Key{code = .Down}},
	{at = 6.8, focus = 2, ev = hnoss.Key{code = .Down}},
	{at = 7.3, focus = 2, ev = hnoss.Key{code = .Down}},
	{at = 8.0, focus = 2, ev = hnoss.Key{code = .End}},
	{at = 8.8, focus = 3},
}

// Typed like a person: uneven gaps, a pause between words and one typo
// fixed with Backspace ('\b').
TYPED :: "deploy api --regoin\b\b\bion=bakı --canary 10% "
PASTED :: "→ 世界 · Bakı ✓"
TYPE_FROM :: 9.2

State :: struct {
	tab:      int,
	services: hnoss.List_State,
	regions:  hnoss.Table_State,
	command:  hnoss.Input_State,
	series:   [3][dynamic]f64,
	latency:  [dynamic]f64,
	samples:  int,
	fps:      f64,
	draw_ms:  f64,
	bytes:    int, // written by the previous end_frame
}

main :: proc() {
	context.assertion_failure_proc = backend.assertion_failure_proc

	term, err := hnoss.init()
	if err != .None {
		fmt.eprintfln("hnoss: init failed: %v", err)
		os.exit(1)
	}
	defer hnoss.deinit(&term)

	st: State
	defer {
		hnoss.input_destroy(&st.command)
		for s in st.series { delete(s) }
		delete(st.latency)
	}
	st.fps = 60

	start := time.tick_now()
	last := start
	prev_t := -1.0
	events: [dynamic]hnoss.Event
	defer delete(events)
	loop: for {
		frame_start := time.tick_now()
		dt := time.duration_seconds(time.tick_diff(last, frame_start))
		last = frame_start
		if dt > 0 { st.fps = st.fps * 0.9 + (1 / dt) * 0.1 }

		total := time.duration_seconds(time.tick_since(start))
		t := math.mod(total, SCRIPT_SECONDS)
		if t < prev_t { restart(&st) }
		focus := scripted_events(&events, prev_t, t)
		prev_t = t
		simulate(&st, total + 30) // start with the graphs already full

		f := hnoss.begin_frame(&term)
		ui := hnoss.ui(f, events[:], theme())
		switch focus {
		case 0: hnoss.focus(ui, nil)
		case 1: hnoss.focus(ui, &st.services)
		case 2: hnoss.focus(ui, &st.regions)
		case 3: hnoss.focus(ui, &st.command)
		}
		draw(ui, f, &st, t, total)
		st.draw_ms = st.draw_ms * 0.9 + time.duration_milliseconds(time.tick_since(frame_start)) * 0.1
		if hnoss.end_frame(&term) != .None { break }
		st.bytes = term.last_bytes

		clear(&events)
		remaining := FRAME_TIME - time.tick_since(frame_start)
		for ev in hnoss.poll_events(&term, max(int(remaining / time.Millisecond), 0)) {
			if hnoss.is_char(ev, 'q') || hnoss.is_char(ev, 'c', {.Ctrl}) { break loop }
		}
		free_all(context.temp_allocator)
		if term.error != .None { break }
	}
}

restart :: proc(st: ^State) {
	st.services = {}
	st.regions = {}
	hnoss.input_set(&st.command, "")
	st.tab = 0
}

// Appends the script's events whose time falls in (prev, t] and returns who
// has focus at t.
scripted_events :: proc(events: ^[dynamic]hnoss.Event, prev, t: f64) -> (focus: int) {
	for s in SCRIPT {
		if s.at <= t { focus = s.focus }
		if s.at > prev && s.at <= t && s.ev != nil { append(events, s.ev) }
	}
	at := TYPE_FROM
	last: rune
	seed := u32(7)
	for r in TYPED {
		seed = seed * 1103515245 + 12345 // the same "random" rhythm every loop
		jitter := f64((seed >> 16) % 1000) / 1000
		gap := 0.07 + 0.09 * jitter
		switch {
		case r == '\b' && last != '\b': gap = 0.45 // notices the typo
		case r == '\b':                  gap = 0.09
		case last == '\b':               gap = 0.3
		case last == ' ':                 gap += 0.18 // between words
		case r == '-' || r == '=':        gap += 0.08
		}
		at += gap
		last = r
		if at > prev && at <= t {
			if r == '\b' {
				append(events, hnoss.Key{code = .Backspace})
			} else {
				append(events, hnoss.Key{code = .Char, char = r})
			}
		}
	}
	paste_at := at + 0.6
	if paste_at > prev && paste_at <= t { append(events, hnoss.Paste{text = PASTED}) }
	return
}

simulate :: proc(st: ^State, total: f64) {
	for f64(st.samples) < total * SAMPLE_RATE {
		x := f64(st.samples) / SAMPLE_RATE
		st.samples += 1
		push(&st.series[0], 520 + 260 * math.sin(x * 0.9) + 140 * math.sin(x * 2.3 + 1) + 70 * math.sin(x * 5.1))
		push(&st.series[1], 60 + 30 * math.sin(x * 1.3) + 20 * math.cos(x * 3.7) + 10 * math.sin(x * 9))
		spike := 40 * math.max(0, math.sin(x * 0.7)) * math.max(0, math.sin(x * 4.1))
		push(&st.series[2], 4 + spike + 3 * math.sin(x * 11))
		push(&st.latency, 24 + 9 * math.sin(x * 1.7) + 5 * math.cos(x * 4.2))
	}
	st.tab = int((total - 30) / 4) % 3
	push :: proc(d: ^[dynamic]f64, v: f64) {
		append(d, max(v, 0))
		if len(d) > 800 { remove_range(d, 0, 400) }
	}
}

draw :: proc(ui: ^hnoss.Ui, f: ^hnoss.Frame, st: ^State, t, total: f64) {
	buffer.fill(f.buffer, f.area, {fg = TEXT, bg = BG})
	area := hnoss.inset(f.area, 1)

	// Header: the logo, a tagline and live render stats.
	head := hnoss.cut_top(&area, 4)
	lw := logo(ui, head.x, head.y, total)
	info := hnoss.Rect{head.x + lw + 3, head.y, head.width - lw - 3, 4}
	hnoss.label(ui, hnoss.cut_top(&info, 1), "[b]immediate-mode TUI[/] [#6d868c]for[/] [b #5fc4c9]Odin[/]  [#6d868c]·  pure Odin, no C, no ncurses[/]", wrap = .Clip)
	hnoss.label(ui, hnoss.cut_top(&info, 1), "[#6d868c]truecolor · braille · unicode 16 · markup · layout · focus · diffed redraws[/]", wrap = .Clip)
	hnoss.cut_top(&info, 1)
	hnoss.label(ui, info, fmt.tprintf(
		"[#e8c060]●[/] [b]%.0f[/] [#6d868c]fps[/]   [#e8c060]●[/] [b]%.2f[/] [#6d868c]ms/frame[/]   [#e8c060]●[/] [b]%d×%d[/] [#6d868c]cells[/]   [#e8c060]●[/] [b]%.1f[/] [#6d868c]KiB written[/]",
		st.fps, st.draw_ms, f.area.width, f.area.height, f64(st.bytes) / 1024,
	), wrap = .Clip)
	hnoss.cut_top(&area, 1)

	footer := hnoss.cut_bottom(&area, 3)
	rows := hnoss.split(area, .Vertical, {hnoss.fill(5), hnoss.fill(4)}, gap = 0)

	// Row 1: plasma, torus, services.
	top := hnoss.split(rows[0], .Horizontal, {hnoss.fill(3), hnoss.fill(3), hnoss.fill(3)}, gap = 1)
	pl := hnoss.box(ui, top[0], "[b]Plasma[/] [#6d868c]truecolor ▀ half-blocks[/]")
	plasma(ui, pl, total)
	tr := hnoss.box(ui, top[1], "[b]Torus[/] [#6d868c]braille canvas, 2×4 dots/cell[/]")
	torus(ui, tr, total)
	services(ui, top[2], st, t)

	// Row 2: graph with tabs, regions table.
	mid := hnoss.split(rows[1], .Horizontal, {hnoss.fill(5), hnoss.fill(4)}, gap = 1)
	charts(ui, mid[0], st)
	regions(ui, mid[1], st)

	// Footer: the command line and gauges.
	cmd := hnoss.split(footer, .Horizontal, {hnoss.fill(5), hnoss.fill(4)}, gap = 1)
	cl := hnoss.box(ui, cmd[0], "[b]Command[/] [#6d868c]typed + pasted, grapheme-aware[/]", {focused = hnoss.focused(ui, &st.command)})
	hnoss.label(ui, hnoss.cut_left(&cl, 2), "[#f08a6a]❯[/]")
	hnoss.input(ui, cl, &st.command, {placeholder = "waiting for input…"})
	gauges(ui, cmd[1], total)

	// Intro: reveal the screen with a sweep from the left.
	if t < 1.2 {
		edge := int(ease(t / 1.2) * f64(f.area.width + 8))
		for x in max(edge - 8, 0) ..< f.area.width {
			for y in 0 ..< f.area.height {
				if x >= edge {
					buffer.set_symbol(f.buffer, x, y, " ", 1, {bg = BG})
				} else if (x + y) % 2 == 0 {
					buffer.set_symbol(f.buffer, x, y, "░", 1, {fg = hnoss.gradient(RAINBOW[:], f64(y) / f64(f.area.height)), bg = BG})
				}
			}
		}
	}
}

ease :: proc(v: f64) -> f64 {
	x := clamp(v, 0, 1)
	return 1 - (1 - x) * (1 - x) * (1 - x)
}

// The word "hnoss" in a 7×8 pixel font, drawn with half-blocks under a
// moving gradient. Returns its width in cells.
@(rodata) GLYPHS := [?][8]string{
	{"##     ", "##     ", "## ### ", "###  ##", "##   ##", "##   ##", "##   ##", "       "},
	{"       ", "       ", "## ### ", "###  ##", "##   ##", "##   ##", "##   ##", "       "},
	{"       ", "       ", " ##### ", "##   ##", "##   ##", "##   ##", " ##### ", "       "},
	{"       ", "       ", " ######", "##     ", " ##### ", "     ##", "###### ", "       "},
	{"       ", "       ", " ######", "##     ", " ##### ", "     ##", "###### ", "       "},
}

logo :: proc(ui: ^hnoss.Ui, x, y: int, t: f64) -> int {
	W :: 7
	GAP :: 1
	width := len(GLYPHS) * (W + GAP) - GAP
	pixel :: proc(gx, py: int) -> bool {
		if py < 0 || py >= 8 { return false }
		g := gx / (W + GAP)
		col := gx % (W + GAP)
		if g < 0 || g >= len(GLYPHS) || col >= W { return false }
		return GLYPHS[g][py][col] == '#'
	}
	{
		for row in 0 ..< 4 {
			for gx in 0 ..< width {
				up, down := pixel(gx, row * 2), pixel(gx, row * 2 + 1)
				sym: string
				switch {
				case up && down: sym = "█"
				case up:         sym = "▀"
				case down:       sym = "▄"
				case:            continue
				}
				c := hnoss.gradient(RAINBOW[:], math.mod(f64(gx) / f64(width) * 0.6 + f64(row) * 0.04 - t * 0.25 + 10, 1))
				buffer.set_symbol(ui.buf, x + gx, y + row, sym, 1, {fg = c, bg = BG})
			}
		}
	}
	return width + 1
}

plasma :: proc(ui: ^hnoss.Ui, r: hnoss.Rect, t: f64) {
	for y in 0 ..< r.height {
		for x in 0 ..< r.width {
			buffer.set_symbol(ui.buf, r.x + x, r.y + y, "▀", 1, {fg = plasma_at(x, y * 2, t), bg = plasma_at(x, y * 2 + 1, t)})
		}
	}
	plasma_at :: proc(x, y: int, t: f64) -> hnoss.Color {
		fx, fy := f64(x) * 0.12, f64(y) * 0.16
		v := math.sin(fx + t) + math.sin(fy - t * 1.3) + math.sin((fx + fy) * 0.6 + t * 0.7) + math.sin(math.sqrt(fx * fx + fy * fy) * 0.8 - t * 1.6)
		return hnoss.gradient(RAINBOW[:], math.mod((v + 4) / 8 + t * 0.08, 1))
	}
}

// A lit torus, z-buffered on a braille canvas; each cell takes the color of
// its brightest dot.
torus :: proc(ui: ^hnoss.Ui, r: hnoss.Rect, t: f64) {
	W, H := r.width * 2, r.height * 4
	if W <= 0 || H <= 0 { return }
	depth := make([]f64, W * H, context.temp_allocator)
	light := make([]f64, W * H, context.temp_allocator)
	for &d in depth { d = -1e9 }

	A, B := t * 0.9, t * 0.55
	sa, ca, sb, cb := math.sin(A), math.cos(A), math.sin(B), math.cos(B)
	R1, R2 :: 0.42, 1.0
	scale := min(f64(W) / 2.6, f64(H) / 2.6) // dots are about square: 2 wide, 4 tall per 1×2 cell
	for i in 0 ..< 90 {
		th := f64(i) / 90 * math.TAU
		ct, s := math.cos(th), math.sin(th)
		for j in 0 ..< 220 {
			ph := f64(j) / 220 * math.TAU
			cp, sp := math.cos(ph), math.sin(ph)
			cx, cy := R2 + R1 * ct, R1 * s
			// rotate around X by A, then Z by B
			px := cx * cp
			py := cy * ca - cx * sp * sa
			pz := cy * sa + cx * sp * ca
			x := px * cb - py * sb
			y := px * sb + py * cb
			nx0, ny0, nz0 := ct * cp, s * ca - ct * sp * sa, s * sa + ct * sp * ca
			nx := nx0 * cb - ny0 * sb
			ny := nx0 * sb + ny0 * cb
			lum := nx * -0.4 + ny * -0.6 + nz0 * 0.7
			sx := int(f64(W) / 2 + x * scale)
			sy := int(f64(H) / 2 - y * scale)
			if sx < 0 || sx >= W || sy < 0 || sy >= H { continue }
			k := sy * W + sx
			if pz > depth[k] { depth[k] = pz; light[k] = lum }
		}
	}
	BITS := [4][2]u8{{0x01, 0x08}, {0x02, 0x10}, {0x04, 0x20}, {0x40, 0x80}}
	for cy in 0 ..< r.height {
		for cx in 0 ..< r.width {
			bits: u8
			best := -2.0
			for dy in 0 ..< 4 {
				for dx in 0 ..< 2 {
					k := (cy * 4 + dy) * W + cx * 2 + dx
					if depth[k] > -1e9 && light[k] > -0.25 {
						bits |= BITS[dy][dx]
						best = max(best, light[k])
					}
				}
			}
			if bits == 0 { continue }
			buf: [4]u8
			n := encode_braille(&buf, 0x2800 + rune(bits))
			buffer.set_symbol(ui.buf, r.x + cx, r.y + cy, string(buf[:n]), 1, {fg = hnoss.gradient(DEPTH[:], clamp((best + 0.25) / 1.25, 0, 1))})
		}
	}
	encode_braille :: proc(buf: ^[4]u8, c: rune) -> int {
		buf[0] = 0xe0 | u8(c >> 12)
		buf[1] = 0x80 | u8((c >> 6) & 0x3f)
		buf[2] = 0x80 | u8(c & 0x3f)
		return 3
	}
}

services :: proc(ui: ^hnoss.Ui, r: hnoss.Rect, st: ^State, t: f64) {
	inner := hnoss.box(ui, r, "[b]Services[/] [#6d868c]↑↓ focus · markup[/]", {focused = hnoss.focused(ui, &st.services)})
	blink := "[#e8c060]◐[/]" if int(t * 4) % 2 == 0 else "[#e8c060]◑[/]"
	items := []string{
		"[#7fd88f]●[/] api-gateway     [#6d868c]v2.4.1[/]",
		"[#7fd88f]●[/] auth            [#6d868c]v1.9.0[/]",
		fmt.tprintf("%s worker-pool     [#6d868c]3/4 up[/]", blink),
		"[#7fd88f]●[/] search          [#6d868c]v3.0.2[/]",
		"[#f08a6a]●[/] billing         [#f08a6a]degraded[/]",
		"[#7fd88f]●[/] notifications   [#6d868c]v0.8.7[/]",
		"[#7fd88f]●[/] media-cdn       [#6d868c]v5.1.0[/]",
		"[#6d868c]○ legacy-reports  stopped[/]",
		"[#7fd88f]●[/] [i]şəki-edge[/]       [#6d868c]v1.0.0[/]",
	}
	hnoss.list(ui, inner, items, &st.services, {markup = true, scrollbar = true})
}

charts :: proc(ui: ^hnoss.Ui, r: hnoss.Rect, st: ^State) {
	NAMES := [3]string{"Requests/s", "Throughput MB/s", "Errors/min"}
	TOPS := [3]f64{1100, 130, 50}
	inner := hnoss.box(ui, r, "")
	bar := hnoss.cut_top(&inner, 1)
	hnoss.tabs(ui, bar, NAMES[:], &st.tab)
	data := st.series[st.tab][:]
	now := data[len(data) - 1]
	label := hnoss.cut_top(&inner, 1)
	hnoss.label(ui, label, fmt.tprintf("[#6d868c]now[/] [b #e8c060]%.0f[/]  [#6d868c]braille area chart, 2 samples per cell, gradient by height[/]", now), wrap = .Clip)
	hnoss.graph(ui, inner, data, {max_value = TOPS[st.tab], gradient = HEAT[:]})
}

regions :: proc(ui: ^hnoss.Ui, r: hnoss.Rect, st: ^State) {
	inner := hnoss.box(ui, r, "[b]Regions[/] [#6d868c]table · wide graphemes[/]", {focused = hnoss.focused(ui, &st.regions)})
	lat := st.latency[len(st.latency) - 1]
	rows := [][]string{
		{"Bakı", fmt.tprintf("%.0f ms", lat * 0.6), "38%", "healthy"},
		{"Frankfurt", fmt.tprintf("%.0f ms", lat), "61%", "healthy"},
		{"İstanbul", fmt.tprintf("%.0f ms", lat * 0.8), "47%", "healthy"},
		{"東京 Tokyo", fmt.tprintf("%.0f ms", lat * 3.1), "72%", "busy"},
		{"Virginia", fmt.tprintf("%.0f ms", lat * 2.4), "55%", "healthy"},
		{"São Paulo", fmt.tprintf("%.0f ms", lat * 4.0), "18%", "draining"},
		{"Şəki", fmt.tprintf("%.0f ms", lat * 2.9), "64%", "healthy"},
	}
	cols := []hnoss.Column{
		{title = "REGION", width = hnoss.fill(2)},
		{title = "P50", width = 7, align = .Right},
		{title = "LOAD", width = 5, align = .Right},
		{title = "STATUS", width = hnoss.fill(1)},
	}
	spark := hnoss.cut_bottom(&inner, 2)
	hnoss.table(ui, inner, cols, rows, &st.regions)
	hnoss.sparkline(ui, spark, st.latency[:], max_value = 45, st = hnoss.Style{fg = RED_LIGHT})
}

gauges :: proc(ui: ^hnoss.Ui, r: hnoss.Rect, t: f64) {
	g := hnoss.split(r, .Horizontal, {hnoss.fill(), hnoss.fill(), hnoss.fill()}, gap = 1)
	values := [3]f64{0.5 + 0.35 * math.sin(t * 1.1), 0.62 + 0.12 * math.sin(t * 0.4 + 1), 0.3 + 0.25 * math.sin(t * 2.3) * math.sin(t * 0.5)}
	names := [3]string{"CPU", "Memory", "GPU"}
	for i in 0 ..< 3 {
		inner := hnoss.box(ui, g[i], fmt.tprintf("[b]%s[/]", names[i]))
		hnoss.gauge(ui, inner, clamp(values[i], 0, 1))
	}
}
