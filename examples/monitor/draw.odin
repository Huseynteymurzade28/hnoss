package main

import "core:fmt"
import "core:strings"
import "core:time"
import "core:time/timezone"
import hnoss "../.."
import "../../buffer"
import "../../text"

// Draws the whole screen; returns false when the app should quit.
draw :: proc(ui: ^hnoss.Ui, f: ^hnoss.Frame, app: ^App) -> bool {
	pal := &app.themes[app.theme]
	buffer.fill(f.buffer, f.area, {fg = pal.text, bg = pal.bg})

	area := f.area
	if area.width < 60 || area.height < 20 {
		hnoss.label(ui, hnoss.center(area, 40, 2), "[b]hnoss monitor[/]\nneeds at least 60x20", align = .Center)
		return handle_keys(ui, app)
	}

	header(ui, hnoss.cut_top(&area, 1), app, pal)
	footer(ui, hnoss.cut_bottom(&area, 1), app, pal)

	rows := hnoss.split(area, .Vertical, {hnoss.percent(44), hnoss.fill()})
	top := hnoss.split(rows[0], .Horizontal, {hnoss.fill(3), hnoss.fill(2)})
	bottom := hnoss.split(rows[1], .Horizontal, {hnoss.percent(36), hnoss.fill()})
	left := hnoss.split(bottom[0], .Vertical, {hnoss.fill(), 7})

	cpu_panel(ui, top[0], &app.sys, pal)
	mem_panel(ui, top[1], &app.sys, pal)
	net_panel(ui, left[0], &app.sys, pal)
	info_panel(ui, left[1], &app.sys, pal)
	proc_panel(ui, bottom[1], app, pal)
	return handle_keys(ui, app)
}

header :: proc(ui: ^hnoss.Ui, r: hnoss.Rect, app: ^App, pal: ^Palette) {
	s := &app.sys
	x := gradient_text(ui, r.x + 1, r.y, "◆ hnoss", pal.logo, {add = {.Bold}})
	hnoss.label(ui, {x, r.y, 12, 1}, fmt.tprintf(" [#%06x]monitor[/]", rgb_u32(pal.dim)))

	clock := "--:--:--"
	if dt, ok := time.time_to_datetime(time.now()); ok {
		local := timezone.datetime_to_tz(dt, app.tz)
		clock = fmt.tprintf("%02d:%02d:%02d", local.hour, local.minute, local.second)
	}
	info := fmt.tprintf("[#%06x]%s · linux %s · up %s ·[/] [b]%s[/] ",
		rgb_u32(pal.dim), s.host, s.kernel, human_uptime(s.uptime), clock)
	hnoss.label(ui, r, info, align = .Right, wrap = .Clip)
}

footer :: proc(ui: ^hnoss.Ui, r: hnoss.Rect, app: ^App, pal: ^Palette) {
	k := fmt.tprintf("#%06x", rgb_u32(pal.ui.accent.fg.(hnoss.Rgb) or_else pal.text))
	d := fmt.tprintf("#%06x", rgb_u32(pal.dim))
	state := "[b]paused[/]" if app.paused else fmt.tprintf("every %v", app.interval)
	hnoss.label(ui, {r.x + 1, r.y, r.width - 2, 1}, fmt.tprintf(
		"[%s]t[/][%s] theme[/] [b]%s[/]  [%s]c m p n[/][%s] sort  r reverse  [/][%s]/[/][%s] filter  [/][%s]+ -[/][%s] speed  space pause  [/][%s]q[/][%s] quit   %s[/]",
		k, d, app.themes[app.theme].name, k, d, k, d, k, d, k, d, state), wrap = .Clip)
}

cpu_panel :: proc(ui: ^hnoss.Ui, r: hnoss.Rect, s: ^System, pal: ^Palette) {
	title := fmt.tprintf("[b]CPU[/] [#%06x]%s[/]", rgb_u32(pal.dim), s.cpu_model)
	inner := hnoss.box(ui, r, title)
	if inner.width < 10 || inner.height < 2 { return }

	// Per-core meters on the right, in as many columns as needed.
	n := len(s.cores)
	cols := max((n + inner.height - 1) / max(inner.height, 1), 1)
	col_w := 18
	if inner.width > cols * col_w + 20 {
		cores := hnoss.cut_right(&inner, cols * col_w)
		per_col := (n + cols - 1) / cols
		for v, i in s.cores {
			c := hnoss.Rect{cores.x + (i / per_col) * col_w + 1, cores.y + i % per_col, col_w - 1, 1}
			label := hnoss.cut_left(&c, 4)
			hnoss.label(ui, label, fmt.tprintf("[#%06x]C%d[/]", rgb_u32(pal.dim), i))
			pct := hnoss.cut_right(&c, 5)
			hnoss.label(ui, pct, fmt.tprintf("%.0f%%", v), align = .Right)
			meter(ui, c, v / 100, pal.cpu, pal.track)
		}
		hnoss.cut_right(&inner, 1)
	}

	hnoss.graph(ui, inner, s.cpu_hist[:], {max_value = 100, gradient = pal.cpu})
	big := fmt.tprintf("[b]%.1f%%[/]", s.cpu)
	hnoss.label(ui, {inner.x + 1, inner.y, 12, 1}, big)
	hnoss.label(ui, {inner.x + 1, inner.y + 1, inner.width - 2, 1},
		fmt.tprintf("[#%06x]load %.2f %.2f %.2f[/]", rgb_u32(pal.dim), s.load[0], s.load[1], s.load[2]), wrap = .Clip)
}

mem_panel :: proc(ui: ^hnoss.Ui, r: hnoss.Rect, s: ^System, pal: ^Palette) {
	inner := hnoss.box(ui, r, "[b]Memory[/]")
	if inner.width < 16 || inner.height < 3 { return }

	used := s.mem_total - s.mem_avail
	swap_used := s.swap_total - s.swap_free
	lines := [?]struct { name: string, ratio: f64, value: string }{
		{"RAM", ratio(used, s.mem_total), fmt.tprintf("%s / %s", human_kb(used), human_kb(s.mem_total))},
		{"Cache", ratio(s.mem_cached, s.mem_total), human_kb(s.mem_cached)},
		{"Swap", ratio(swap_used, s.swap_total), fmt.tprintf("%s / %s", human_kb(swap_used), human_kb(s.swap_total))},
	}
	for l in lines {
		row := hnoss.cut_top(&inner, 1)
		name := hnoss.cut_left(&row, 6)
		hnoss.label(ui, name, fmt.tprintf("[#%06x]%s[/]", rgb_u32(pal.dim), l.name))
		val := hnoss.cut_right(&row, min(19, row.width / 2))
		hnoss.label(ui, val, l.value, align = .Right, wrap = .Clip)
		hnoss.cut_right(&row, 1)
		meter(ui, row, l.ratio, pal.mem, pal.track)
	}
	hnoss.cut_top(&inner, 1)
	hnoss.graph(ui, inner, s.mem_hist[:], {max_value = 100, gradient = pal.mem})
}

net_panel :: proc(ui: ^hnoss.Ui, r: hnoss.Rect, s: ^System, pal: ^Palette) {
	inner := hnoss.box(ui, r, "[b]Network[/]")
	if inner.height < 2 { return }
	halves := hnoss.split(inner, .Vertical, {hnoss.fill(), hnoss.fill()})

	// One scale for both directions so they can be compared.
	shown := min(len(s.rx_hist), inner.width * 2)
	peak := 1024.0
	for v in s.rx_hist[len(s.rx_hist) - shown:] { peak = max(peak, v) }
	for v in s.tx_hist[len(s.tx_hist) - shown:] { peak = max(peak, v) }

	hnoss.graph(ui, halves[0], s.rx_hist[:], {max_value = peak, gradient = pal.rx})
	hnoss.graph(ui, halves[1], s.tx_hist[:], {max_value = peak, gradient = pal.tx, downward = true})
	hnoss.label(ui, {inner.x + 1, inner.y, inner.width - 2, 1},
		fmt.tprintf("[b]▼ %s[/]  [#%06x]peak %s[/]", human_rate(s.rx_rate), rgb_u32(pal.dim), human_rate(peak)), wrap = .Clip)
	hnoss.label(ui, {inner.x + 1, inner.y + inner.height - 1, inner.width - 2, 1},
		fmt.tprintf("[b]▲ %s[/]", human_rate(s.tx_rate)), wrap = .Clip)
}

info_panel :: proc(ui: ^hnoss.Ui, r: hnoss.Rect, s: ^System, pal: ^Palette) {
	inner := hnoss.box(ui, r, "[b]System[/]")
	if inner.width < 20 { return }
	row :: proc(ui: ^hnoss.Ui, inner: ^hnoss.Rect, pal: ^Palette, name: string) -> hnoss.Rect {
		line := hnoss.cut_top(inner, 1)
		hnoss.label(ui, hnoss.cut_left(&line, 9), fmt.tprintf("[#%06x]%s[/]", rgb_u32(pal.dim), name))
		return line
	}
	if s.temp >= 0 {
		line := row(ui, &inner, pal, "Temp")
		hnoss.label(ui, hnoss.cut_right(&line, 7), fmt.tprintf("%.0f°C", s.temp), align = .Right)
		hnoss.cut_right(&line, 1)
		meter(ui, line, (s.temp - 20) / 80, pal.cpu, pal.track)
	}
	if s.battery >= 0 {
		line := row(ui, &inner, pal, "Battery")
		hnoss.label(ui, hnoss.cut_right(&line, 7), fmt.tprintf("%s%d%%", "⚡" if s.charging else "", s.battery), align = .Right)
		hnoss.cut_right(&line, 1)
		meter(ui, line, f64(s.battery) / 100, pal.rx, pal.track)
	}
	hnoss.label(ui, row(ui, &inner, pal, "Tasks"),
		fmt.tprintf("%d procs · %d threads · %d running", len(s.procs), s.threads, s.running), wrap = .Ellipsis)
	hnoss.label(ui, row(ui, &inner, pal, "Cores"), fmt.tprintf("%d", s.ncores))
	hnoss.label(ui, row(ui, &inner, pal, "Uptime"), human_uptime(s.uptime))
}

proc_panel :: proc(ui: ^hnoss.Ui, r: hnoss.Rect, app: ^App, pal: ^Palette) {
	s := &app.sys
	if hnoss.focused(ui, nil) || ui.mem.focus == nil {
		hnoss.focus(ui, &app.table)
	}

	// Filter, sort, then format the visible data.
	needle := strings.to_lower(hnoss.input_text(&app.search), context.temp_allocator)
	shown := make([dynamic]Proc, 0, len(s.procs), context.temp_allocator)
	max_rss: u64 = 1
	for p in s.procs {
		max_rss = max(max_rss, p.rss_kb)
		if needle != "" &&
		   !strings.contains(strings.to_lower(p.name, context.temp_allocator), needle) &&
		   !strings.contains(p.user, needle) &&
		   !strings.contains(fmt.tprint(p.pid), needle) {
			continue
		}
		append(&shown, p)
	}
	sort_procs(shown[:], app.sort, app.reverse)

	arrow := "↑" if app.reverse else "↓"
	sort_name := [Sort_Key]string{.Cpu = "cpu", .Mem = "mem", .Pid = "pid", .Name = "name"}
	title := fmt.tprintf("[b]Processes[/] [#%06x]%d · sort %s %s[/]", rgb_u32(pal.dim), len(shown), sort_name[app.sort], arrow)
	inner := hnoss.box(ui, r, title, {focused = true})
	if inner.height < 3 { return }

	search := hnoss.cut_top(&inner, 1)
	// "/" focuses the filter *before* the field runs, so the keys typed
	// right after it in the same read land in the field too.
	if !hnoss.focused(ui, &app.search) {
		for ev, i in ui.events {
			if !ui.handled[i] && hnoss.is_char(ev, '/') {
				ui.handled[i] = true
				hnoss.focus(ui, &app.search)
				break
			}
		}
	}
	searching := hnoss.focused(ui, &app.search)
	hnoss.label(ui, hnoss.cut_left(&search, 2), "[b]/[/]" if searching else fmt.tprintf("[#%06x]/[/]", rgb_u32(pal.dim)))
	placeholder := "type to filter by name, user or pid" if searching else "press / to filter"
	hnoss.input(ui, search, &app.search, {placeholder = placeholder})

	cols := []hnoss.Column{
		{title = "PID", width = 7, align = .Right},
		{title = "USER", width = 9},
		{title = "NAME", width = hnoss.fill()},
		{title = "THR", width = 4, align = .Right},
		{title = "CPU%", width = 6, align = .Right},
		{title = "MEM", width = 7, align = .Right},
	}
	rows := make([][]string, len(shown), context.temp_allocator)
	for p, i in shown {
		row := make([]string, 6, context.temp_allocator)
		row[0] = fmt.tprint(p.pid)
		row[1] = p.user
		row[2] = p.name
		row[3] = fmt.tprint(p.threads)
		row[4] = fmt.tprintf("%.1f", p.cpu)
		row[5] = human_kb(p.rss_kb, short = true)
		rows[i] = row
	}

	// Once you pick a process, it stays selected while the list re-sorts
	// under it. Until then the selection simply stays on the top row.
	if app.selected_pid != 0 {
		for p, i in shown {
			if p.pid == app.selected_pid { app.table.selected = i }
		}
	}
	if hnoss.table(ui, inner, cols, rows, &app.table, {scrollbar = true}) && app.table.selected < len(shown) {
		app.selected_pid = shown[app.table.selected].pid
	}

	// Color the CPU% and MEM cells by value. Same column split as the table.
	body := inner
	if len(rows) > inner.height - 1 { hnoss.cut_right(&body, 1) }
	sizes := make([]hnoss.Size, len(cols), context.temp_allocator)
	for c, i in cols { sizes[i] = c.width }
	xs := hnoss.split_slice(body, .Horizontal, sizes, 1)
	for i in app.table.offset ..< min(app.table.offset + body.height - 1, len(shown)) {
		if i == app.table.selected { continue }
		y := body.y + 1 + i - app.table.offset
		p := shown[i]
		buffer.set_style(ui.buf, {xs[4].x, y, xs[4].width, 1}, {fg = hnoss.gradient(pal.cpu, p.cpu / 100), add = {.Bold} if p.cpu >= 1 else {}})
		buffer.set_style(ui.buf, {xs[5].x, y, xs[5].width, 1}, {fg = hnoss.gradient(pal.mem, f64(p.rss_kb) / f64(max_rss))})
		if p.state == 'R' {
			buffer.set_style(ui.buf, {xs[2].x, y, xs[2].width, 1}, {add = {.Bold}})
		}
	}
}

// A horizontal bar: filled cells take the gradient color of their own
// position (so the bar gets "hotter" towards the right), the leading
// edge is drawn in eighths, and the rest is a thin track.
meter :: proc(ui: ^hnoss.Ui, r: hnoss.Rect, value: f64, grad: []hnoss.Rgb, track: hnoss.Rgb) {
	if r.width <= 0 { return }
	eighths := int(clamp(value, 0, 1) * f64(r.width * 8) + 0.5)
	full, part := eighths / 8, eighths % 8
	for i in 0 ..< r.width {
		c := hnoss.gradient(grad, (f64(i) + 0.5) / f64(r.width))
		switch {
		case i < full:
			buffer.set_symbol(ui.buf, r.x + i, r.y, "█", 1, {fg = c})
		case i == full && part > 0:
			buffer.set_symbol(ui.buf, r.x + i, r.y, EIGHTHS[part], 1, {fg = c})
		case:
			buffer.set_symbol(ui.buf, r.x + i, r.y, "─", 1, {fg = track})
		}
	}
}

@(private = "file", rodata)
EIGHTHS := [8]string{" ", "▏", "▎", "▍", "▌", "▋", "▊", "▉"}

// Writes `s` with each grapheme colored along `grad`; returns the x after it.
gradient_text :: proc(ui: ^hnoss.Ui, x, y: int, s: string, grad: []hnoss.Rgb, mods: hnoss.Style = {}) -> int {
	n := max(text.width(s) - 1, 1)
	cx := x
	for rest := s; len(rest) > 0; {
		c, w, next := text.next_grapheme(rest)
		rest = next
		if w == 0 { continue }
		st := mods
		st.fg = hnoss.gradient(grad, f64(cx - x) / f64(n))
		buffer.set_symbol(ui.buf, cx, y, c, w, st)
		cx += w
	}
	return cx
}

ratio :: proc(a, b: u64) -> f64 {
	return f64(a) / f64(b) if b > 0 else 0
}

rgb_u32 :: proc(c: hnoss.Rgb) -> u32 {
	return u32(c.r) << 16 | u32(c.g) << 8 | u32(c.b)
}

human_kb :: proc(kb: u64, short := false) -> string {
	units := [?]string{"K", "M", "G", "T"} if short else [?]string{"KiB", "MiB", "GiB", "TiB"}
	v := f64(kb)
	u := 0
	for v >= 1024 && u < len(units) - 1 {
		v /= 1024
		u += 1
	}
	if v >= 100 || u == 0 {
		return fmt.tprintf("%.0f%s%s", v, "" if short else " ", units[u])
	}
	return fmt.tprintf("%.1f%s%s", v, "" if short else " ", units[u])
}

human_rate :: proc(bytes_per_s: f64) -> string {
	return fmt.tprintf("%s/s", human_kb(u64(bytes_per_s / 1024)))
}

human_uptime :: proc(seconds: f64) -> string {
	s := int(seconds)
	d, h, m := s / 86400, (s % 86400) / 3600, (s % 3600) / 60
	if d > 0 { return fmt.tprintf("%dd %dh", d, h) }
	if h > 0 { return fmt.tprintf("%dh %dm", h, m) }
	return fmt.tprintf("%dm", m)
}
