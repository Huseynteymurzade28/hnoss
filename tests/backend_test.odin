package tests

import "core:testing"
import "../backend"

@(test)
make_raw_clears_line_discipline :: proc(t: ^testing.T) {
	cooked := backend.Termios{
		iflag = backend.ICRNL | backend.IXON | backend.BRKINT,
		oflag = backend.OPOST,
		cflag = backend.PARENB,
		lflag = backend.ECHO | backend.ICANON | backend.ISIG | backend.IEXTEN,
	}
	cooked.cc[backend.VMIN] = 1
	cooked.cc[backend.VTIME] = 3

	raw := backend.make_raw(cooked)
	testing.expect_value(t, raw.iflag, 0)
	testing.expect_value(t, raw.oflag, 0)
	testing.expect_value(t, raw.lflag, 0)
	testing.expect_value(t, raw.cflag & backend.CSIZE, u32(backend.CS8))
	testing.expect_value(t, raw.cflag & backend.PARENB, 0)
	testing.expect_value(t, raw.cc[backend.VMIN], 0)
	testing.expect_value(t, raw.cc[backend.VTIME], 0)
}

@(test)
make_raw_keeps_unrelated_flags :: proc(t: ^testing.T) {
	IUTF8 :: 0o040000
	cooked := backend.Termios{iflag = IUTF8 | backend.ICRNL}
	raw := backend.make_raw(cooked)
	testing.expect_value(t, raw.iflag, IUTF8)
}

@(test)
restore_without_init_is_noop :: proc(t: ^testing.T) {
	backend.restore_terminal()
	backend.restore_terminal()
}

@(test)
deinit_zero_backend_is_noop :: proc(t: ^testing.T) {
	b: backend.Backend
	backend.deinit(&b)
	backend.deinit(&b)
}
