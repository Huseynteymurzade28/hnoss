#+build darwin
package tests

import "core:sys/posix"
import "core:testing"
import "../backend"

@(test)
make_raw_clears_line_discipline :: proc(t: ^testing.T) {
	cooked := posix.termios{
		c_iflag = {.ICRNL, .IXON, .BRKINT},
		c_oflag = {.OPOST},
		c_cflag = {.PARENB},
		c_lflag = {.ECHO, .ICANON, .ISIG, .IEXTEN},
	}
	cooked.c_cc[.VMIN] = 1
	cooked.c_cc[.VTIME] = 3

	raw := backend.make_raw(cooked)
	testing.expect_value(t, raw.c_iflag, posix.CInput_Flags{})
	testing.expect_value(t, raw.c_oflag, posix.COutput_Flags{})
	testing.expect_value(t, raw.c_lflag, posix.CLocal_Flags{})
	// Compare as raw bits: CS8 is a 2-bit value (0x300) on macOS.
	cflag := transmute(posix.tcflag_t)raw.c_cflag
	testing.expect_value(t, cflag & posix._CSIZE, posix.tcflag_t(posix.CS8))
	testing.expect(t, .PARENB not_in raw.c_cflag)
	testing.expect_value(t, raw.c_cc[.VMIN], 0)
	testing.expect_value(t, raw.c_cc[.VTIME], 0)
}

@(test)
make_raw_keeps_unrelated_flags :: proc(t: ^testing.T) {
	cooked := posix.termios{c_iflag = {.IXANY, .ICRNL}}
	raw := backend.make_raw(cooked)
	testing.expect_value(t, raw.c_iflag, posix.CInput_Flags{.IXANY})
}
