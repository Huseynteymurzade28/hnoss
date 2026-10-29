// Phase 3 example: prints every input event as it arrives.
// Mouse capture is on, so clicks, drags, motion and the wheel show up too;
// paste something to see a bracketed Paste event.
//   Ctrl+C  quit   (q is just another key here)
package main

import "core:fmt"
import "core:os"
import "core:strings"
import hnoss "../.."
import "../../backend"
import "../../buffer"
import "../../input"
import "../../style"

MAX_LOG :: 1000

main :: proc() {
	context.assertion_failure_proc = backend.assertion_failure_proc

	term, err := hnoss.init(hnoss.DEFAULT_OPTIONS + {.Mouse_Capture})
	if err != .None {
		fmt.eprintfln("hnoss: init failed: %v", err)
		os.exit(1)
	}
	defer hnoss.deinit(&term)

	log: [dynamic]string
	defer {
		for line in log { delete(line) }
		delete(log)
	}
	mouse_x, mouse_y := -1, -1

	loop: for {
		f := hnoss.begin_frame(&term)
		draw(f, log[:], mouse_x, mouse_y)
		hnoss.end_frame(&term)
		free_all(context.temp_allocator)

		for ev in hnoss.poll_events(&term, -1) {
			if hnoss.is_char(ev, 'c', {.Ctrl}) {
				break loop
			}
			if m, ok := ev.(input.Mouse); ok {
				mouse_x, mouse_y = m.x, m.y
			}
			if len(log) == MAX_LOG {
				delete(log[0])
				ordered_remove(&log, 0)
			}
			append(&log, describe(ev))
		}
		if term.error != .None {
			break
		}
	}
}

draw :: proc(f: ^hnoss.Frame, log: []string, mouse_x, mouse_y: int) {
	header := style.Style{fg = style.Named_Color.Black, bg = style.Named_Color.Cyan, add = {.Bold}}
	buffer.set_style(f.buffer, {0, 0, f.area.width, 1}, header)
	buffer.set_string(f.buffer, 1, 0, "hnoss event inspector  —  press keys, click, scroll, paste  —  Ctrl+C quits", header)

	rows := f.area.height - 1
	first := max(len(log) - rows, 0)
	for line, i in log[first:] {
		num := fmt.tprint(first + i + 1)
		buffer.set_string(f.buffer, 5 - len(num), i + 1, num, {fg = style.Named_Color.Bright_Black})
		buffer.set_string(f.buffer, 7, i + 1, line, max_width = f.area.width - 8)
	}

	if mouse_x >= 0 {
		buffer.set_symbol(f.buffer, mouse_x, mouse_y, "┼", 1, {fg = style.Named_Color.Yellow, add = {.Bold}})
	}
}

// One log line per event, allocated with context.allocator.
describe :: proc(ev: hnoss.Event) -> string {
	switch e in ev {
	case input.Key:
		name := fmt.tprintf("'%c'", e.char) if e.code == .Char else fmt.tprint(e.code)
		return fmt.aprintf("Key     %s%s", mods_prefix(e.mods), name)
	case input.Mouse:
		btn := "" if e.button == .None else fmt.tprintf(" %v", e.button)
		return fmt.aprintf("Mouse   %s%v%s at (%d, %d)", mods_prefix(e.mods), e.kind, btn, e.x, e.y)
	case input.Paste:
		preview := e.text[:min(len(e.text), 60)]
		return fmt.aprintf("Paste   %d bytes: %q%s", len(e.text), preview, "…" if len(e.text) > 60 else "")
	case input.Resize:
		return fmt.aprintf("Resize  %dx%d", e.cols, e.rows)
	}
	return strings.clone("?")
}

mods_prefix :: proc(m: input.Key_Modifiers) -> string {
	sb := strings.builder_make(context.temp_allocator)
	if .Ctrl in m { strings.write_string(&sb, "Ctrl+") }
	if .Alt in m { strings.write_string(&sb, "Alt+") }
	if .Shift in m { strings.write_string(&sb, "Shift+") }
	if .Super in m { strings.write_string(&sb, "Super+") }
	return strings.to_string(sb)
}
