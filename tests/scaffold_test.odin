package tests

import "core:testing"
import hnoss ".."

@(test)
version_is_set :: proc(t: ^testing.T) {
	testing.expect(t, len(hnoss.VERSION) > 0)
}

@(test)
cursor_shape_sequences :: proc(t: ^testing.T) {
	seq :: proc(shape: hnoss.Cursor_Shape, blink: bool) -> string {
		out := make([dynamic]u8, context.temp_allocator)
		hnoss.append_cursor_shape(&out, shape, blink)
		return string(out[:])
	}
	testing.expect_value(t, seq(.Default, false), "\x1b[0 q")
	testing.expect_value(t, seq(.Default, true), "\x1b[0 q")
	testing.expect_value(t, seq(.Block, true), "\x1b[1 q")
	testing.expect_value(t, seq(.Block, false), "\x1b[2 q")
	testing.expect_value(t, seq(.Underline, false), "\x1b[4 q")
	testing.expect_value(t, seq(.Bar, true), "\x1b[5 q")
	testing.expect_value(t, seq(.Bar, false), "\x1b[6 q")
}

@(test)
clipboard_is_osc_52_base64 :: proc(t: ^testing.T) {
	term: hnoss.Terminal
	defer delete(term.backend.out)
	hnoss.set_clipboard(&term, "Bakı")
	testing.expect_value(t, string(term.backend.out[:]), "\x1b]52;c;QmFrxLE=\x07")
}

@(test)
title_drops_control_characters :: proc(t: ^testing.T) {
	term: hnoss.Terminal
	defer delete(term.backend.out)
	hnoss.set_title(&term, "hnoss\x1b]0;evil\x07 — Şəki\u009b")
	testing.expect_value(t, string(term.backend.out[:]), "\x1b]2;hnoss]0;evil — Şəki\x07")
}
