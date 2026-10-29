// A tour of hnoss on one screen: tabs, a markup list, a braille graph, a
// table, gauges, a sparkline and a text field, in a theme made from the
// logo's colors. Values are simulated.
//   Tab  move focus   ←→  tabs (when focused)   q  quit
package main

import "core:fmt"
import "core:math"
import "core:os"
import "core:time"
import hnoss "../.."
import "../../backend"
import "../../buffer"
import "../../text"

TEAL :: hnoss.Rgb{0x22, 0x84, 0x8c}
TEAL_LIGHT :: hnoss.Rgb{0x5f, 0xc4, 0xc9}
RED :: hnoss.Rgb{0xc4, 0x4e, 0x36}
RED_LIGHT :: hnoss.Rgb{0xf0, 0x8a, 0x6a}
BG :: hnoss.Rgb{0x0d, 0x15, 0x18}
PANEL :: hnoss.Rgb{0x23, 0x3a, 0x40}
TEXT :: hnoss.Rgb{0xdc, 0xe8, 0xea}
DIM :: hnoss.Rgb{0x6d, 0x86, 0x8c}

@(rodata) BRAND := [?]hnoss.Rgb{TEAL_LIGHT, TEAL, RED, RED_LIGHT}
@(rodata) GRAPH := [?]hnoss.Rgb{TEAL, TEAL_LIGHT, RED_LIGHT, RED}

theme :: proc() -> hnoss.Theme {
	t := hnoss.DEFAULT_THEME
	t.text = {fg = TEXT}
	t.muted = {fg = DIM}
	t.accent = {fg = TEAL_LIGHT}
	t.border = {fg = PANEL}
	t.border_focused = {fg = TEAL_LIGHT}
	t.title = {fg = TEXT, add = {.Bold}}
	t.selected = {fg = BG, bg = TEAL_LIGHT, add = {.Bold}}
	t.selected_unfocused = {bg = PANEL}
	t.header = {fg = RED_LIGHT, add = {.Bold}}
	t.gauge_filled = {fg = TEAL}
	t.gauge_empty = {bg = hnoss.Rgb{0x16, 0x24, 0x28}}
	t.tab = {fg = DIM}
	t.tab_selected = {fg = RED_LIGHT, add = {.Bold}}
	t.input = {fg = TEXT}
	t.scrollbar_track = {fg = PANEL}
	t.scrollbar_thumb = {fg = TEAL_LIGHT}
	return t
}

State :: struct {
	tab:      int,
	services: hnoss.List_State,
	regions:  hnoss.Table_State,
	search:   hnoss.Input_State,
	traffic:  [dynamic]f64,
	latency:  [dynamic]f64,
}

main :: proc() {
	context.assertion_failure_proc = backend.assertion_failure_proc

	term, err := hnoss.init(hnoss.DEFAULT_OPTIONS + {.Mouse_Capture})
	if err != .None {
		fmt.eprintfln("hnoss: init failed: %v", err)
		os.exit(1)
	}
	defer hnoss.deinit(&term)

	st: State
	defer hnoss.input_destroy(&st.search)
	defer delete(st.traffic)
	defer delete(st.latency)
	hnoss.input_set(&st.search, "region:baku")
	st.services.selected = 1

	start := time.tick_now()
	events: []hnoss.Event
	loop: for {
		t := time.duration_seconds(time.tick_since(start))
		simulate(&st, t)

		f := hnoss.begin_frame(&term)
		ui := hnoss.ui(f, events, theme())
		draw(ui, f, &st, t)
		for ev in hnoss.unhandled(ui) {
			if hnoss.is_char(ev, 'q') || hnoss.is_char(ev, 'c', {.Ctrl}) { break loop }
		}
		hnoss.end_frame(&term)
		free_all(context.temp_allocator)
		events = hnoss.poll_events(&term, 100)
		if term.error != .None { break }
	}
}

simulate :: proc(st: ^State, t: f64) {
	v := 520 + 260 * math.sin(t * 0.9) + 140 * math.sin(t * 2.3 + 1) + 70 * math.sin(t * 5.1)
	append(&st.traffic, max(v, 0))
	append(&st.latency, 24 + 9 * math.sin(t * 1.7) + 5 * math.cos(t * 4.2))
	if len(st.traffic) > 600 { remove_range(&st.traffic, 0, 300) }
	if len(st.latency) > 600 { remove_range(&st.latency, 0, 300) }
}

draw :: proc(ui: ^hnoss.Ui, f: ^hnoss.Frame, st: ^State, t: f64) {
	buffer.fill(f.buffer, f.area, {fg = TEXT, bg = BG})
	area := hnoss.inset(f.area, 1)
	hnoss.focus_order(ui, {&st.services, &st.regions, &st.search, &st.tab})

	// Brand + tabs.
	top := hnoss.cut_top(&area, 1)
	x := brand(ui, top.x, top.y, "◆ hnoss")
	hnoss.tabs(ui, {x + 2, top.y, top.width - x - 2, 1}, {"Dashboard", "Services", "Logs", "🇦🇿 Salam"}, &st.tab)
	hnoss.cut_top(&area, 1)
	footer := hnoss.cut_bottom(&area, 1)
	hnoss.label(ui, footer, "[#5fc4c9]Tab[/] [#6d868c]focus[/]  [#5fc4c9]↑↓ jk[/] [#6d868c]select[/]  [#5fc4c9]←→[/] [#6d868c]tabs[/]  [#5fc4c9]q[/] [#6d868c]quit   ·   box · list · graph · table · gauge · sparkline · input · tabs[/]", wrap = .Clip)

	cols := hnoss.split(area, .Horizontal, {hnoss.percent(34), hnoss.fill()}, gap = 1)

	// Left: services (markup list) and a deploy panel.
	left := hnoss.split(cols[0], .Vertical, {hnoss.fill(), 9})
	svc := hnoss.box(ui, left[0], "[b]Services[/] [#6d868c]8[/]", {focused = hnoss.focused(ui, &st.services)})
	hnoss.list(ui, svc, {
		"[#7fd88f]●[/] api-gateway        [#6d868c]v2.4.1[/]",
		"[#7fd88f]●[/] auth               [#6d868c]v1.9.0[/]",
		"[#e8c060]●[/] worker-pool        [#6d868c]3/4 up[/]",
		"[#7fd88f]●[/] search             [#6d868c]v3.0.2[/]",
		"[#f08a6a]●[/] billing            [#6d868c]degraded[/]",
		"[#7fd88f]●[/] notifications      [#6d868c]v0.8.7[/]",
		"[#7fd88f]●[/] media-cdn          [#6d868c]v5.1.0[/]",
		"[#6d868c]○ legacy-reports     stopped[/]",
	}, &st.services, {markup = true})

	dep := hnoss.box(ui, left[1], "[b]Deploy[/] [#6d868c]api-gateway → Bakı[/]", {focused = hnoss.focused(ui, &st.search)})
	field := hnoss.cut_top(&dep, 1)
	hnoss.label(ui, hnoss.cut_left(&field, 2), "[#c44e36]❯[/]")
	hnoss.input(ui, field, &st.search, {placeholder = "filter…"})
	hnoss.cut_top(&dep, 1)
	progress := math.mod(t / 12, 1.0)
	hnoss.label(ui, hnoss.cut_top(&dep, 1), fmt.tprintf("[#6d868c]rolling out[/] [b]%d[/][#6d868c]/12 pods[/]", int(progress * 12)))
	meter(ui, hnoss.cut_top(&dep, 1), progress)
	hnoss.cut_top(&dep, 1)
	hnoss.label(ui, dep, "[#7fd88f]✓[/] build  [#7fd88f]✓[/] tests 76/76  [#e8c060]◐[/] rollout", wrap = .Clip)

	// Right: traffic graph, regions table, gauges.
	right := hnoss.split(cols[1], .Vertical, {hnoss.fill(3), hnoss.fill(3), 5})
	last := st.traffic[len(st.traffic) - 1]
	gr := hnoss.box(ui, right[0], fmt.tprintf("[b]Requests[/] [#6d868c]per second[/]  [b #5fc4c9]%.0f[/]", last))
	hnoss.graph(ui, gr, st.traffic[:], {max_value = 1100, gradient = GRAPH[:]})

	reg := hnoss.box(ui, right[1], "[b]Regions[/]", {focused = hnoss.focused(ui, &st.regions)})
	lat := st.latency[len(st.latency) - 1]
	rows := [][]string{
		{"🇦🇿 Bakı", fmt.tprintf("%.0f ms", lat * 0.6), "38%", "healthy"},
		{"🇩🇪 Frankfurt", fmt.tprintf("%.0f ms", lat), "61%", "healthy"},
		{"🇹🇷 İstanbul", fmt.tprintf("%.0f ms", lat * 0.8), "47%", "healthy"},
		{"🇯🇵 Tokyo", fmt.tprintf("%.0f ms", lat * 3.1), "72%", "busy"},
		{"🇺🇸 Virginia", fmt.tprintf("%.0f ms", lat * 2.4), "55%", "healthy"},
		{"🇧🇷 São Paulo", fmt.tprintf("%.0f ms", lat * 4.0), "18%", "draining"},
	}
	cols_t := []hnoss.Column{
		{title = "REGION", width = hnoss.fill(2)},
		{title = "LATENCY", width = 9, align = .Right},
		{title = "LOAD", width = 6, align = .Right},
		{title = "STATUS", width = hnoss.fill(1)},
	}
	spark_area := hnoss.cut_right(&reg, min(28, reg.width / 3))
	hnoss.table(ui, reg, cols_t, rows, &st.regions)
	hnoss.label(ui, hnoss.cut_top(&spark_area, 1), fmt.tprintf("  [#6d868c]p50 latency[/] [b]%.1f ms[/]", lat))
	hnoss.sparkline(ui, hnoss.pad(spark_area, 0, 0, 0, 2), st.latency[:], max_value = 45, st = hnoss.Style{fg = RED_LIGHT})

	g := hnoss.split(right[2], .Horizontal, {hnoss.fill(), hnoss.fill(), hnoss.fill()}, gap = 1)
	values := [3]f64{0.42 + 0.2 * math.sin(t), 0.67 + 0.05 * math.sin(t * 0.3), 0.81}
	names := [3]string{"CPU", "Memory", "Disk"}
	for i in 0 ..< 3 {
		inner := hnoss.box(ui, g[i], fmt.tprintf("[b]%s[/]", names[i]))
		hnoss.gauge(ui, inner, values[i])
	}
}

// The logo's colors along a string.
brand :: proc(ui: ^hnoss.Ui, x, y: int, s: string) -> int {
	n := max(text.width(s) - 1, 1)
	cx := x
	for rest := s; len(rest) > 0; {
		c, w, next := text.next_grapheme(rest)
		rest = next
		buffer.set_symbol(ui.buf, cx, y, c, w, {fg = hnoss.gradient(BRAND[:], f64(cx - x) / f64(n)), add = {.Bold}})
		cx += w
	}
	return cx
}

// A slim gradient progress bar.
meter :: proc(ui: ^hnoss.Ui, r: hnoss.Rect, v: f64) {
	filled := int(clamp(v, 0, 1) * f64(r.width) + 0.5)
	for i in 0 ..< r.width {
		c := hnoss.gradient(BRAND[:], f64(i) / f64(max(r.width - 1, 1)))
		if i < filled {
			buffer.set_symbol(ui.buf, r.x + i, r.y, "━", 1, {fg = c})
		} else {
			buffer.set_symbol(ui.buf, r.x + i, r.y, "─", 1, {fg = PANEL})
		}
	}
}
