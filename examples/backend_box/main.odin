// Phase 1 example: raw backend only, no buffer/diff yet.
// Draws a box that fills the terminal and redraws on resize.
//   q / Ctrl+C  quit
//   p           panic (to check the terminal comes back clean)
package main

import "core:fmt"
import "core:os"
import "core:strings"
import "../../backend"

main :: proc() {
	context.assertion_failure_proc = backend.assertion_failure_proc

	b: backend.Backend
	if err := backend.init(&b); err != .None {
		fmt.eprintfln("hnoss: init failed: %v (errno %v)", err, b.errno)
		os.exit(1)
	}
	defer backend.deinit(&b)

	draw(&b)
	buf: [256]u8
	loop: for {
		res, err := backend.read(&b, buf[:], -1)
		if err != .None {
			break
		}
		if res.resized {
			draw(&b)
		}
		for c in buf[:res.n] {
			switch c {
			case 'q', 0x03: // 0x03 = Ctrl+C (ISIG is off in raw mode)
				break loop
			case 'p':
				panic("panic requested with 'p'")
			}
		}
	}
}

draw :: proc(b: ^backend.Backend) {
	defer free_all(context.temp_allocator)

	sz, err := backend.size(b)
	if err != .None || sz.cols < 2 || sz.rows < 2 {
		return
	}

	sb := strings.builder_make(context.temp_allocator)
	strings.write_string(&sb, backend.CLEAR_SCREEN)
	strings.write_string(&sb, backend.CURSOR_HOME)

	horiz := strings.repeat("─", sz.cols - 2, context.temp_allocator)
	fmt.sbprintf(&sb, "\x1b[1;1H┌%s┐", horiz)
	for row in 2 ..< sz.rows {
		fmt.sbprintf(&sb, "\x1b[%d;1H│\x1b[%d;%dH│", row, row, sz.cols)
	}
	fmt.sbprintf(&sb, "\x1b[%d;1H└%s┘", sz.rows, horiz)

	msg := fmt.tprintf("hnoss  %dx%d  q quit, p panic", sz.cols, sz.rows)
	if len(msg) <= sz.cols - 2 && sz.rows > 2 {
		fmt.sbprintf(&sb, "\x1b[%d;%dH%s", sz.rows / 2 + 1, (sz.cols - len(msg)) / 2 + 1, msg)
	}

	backend.write(b, strings.to_string(sb))
	backend.flush(b)
}
