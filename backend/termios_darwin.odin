#+build darwin
package backend

// core:sys/posix covers termios on macOS (with the right layout: tcflag_t is
// 64-bit here), but not ioctl or struct winsize, so those live here.

import "core:c"
import "core:sys/posix"

// Through libc rather than a raw syscall: on macOS only the libSystem
// interface is a stable ABI.
foreign import libc "system:System"

@(private)
foreign libc {
	ioctl :: proc(fd: posix.FD, request: c.ulong, #c_vararg args: ..any) -> c.int ---
}

// Not POSIX, so posix.Signal has no member for it. sys/signal.h
SIGWINCH :: posix.Signal(28)

// sys/ttycom.h: _IOR('t', 104, struct winsize)
TIOCGWINSZ :: 0x40087468

Winsize :: struct {
	row, col:       u16,
	xpixel, ypixel: u16,
}
#assert(size_of(Winsize) == 8)

// On macOS CS8 is both bits of CSIZE (0x300). posix.CControl_Flag_Bits.CS8
// is log2 of that, i.e. only bit 9, so going through the bit_set enum would
// set CS7|... wrong; use the full CSIZE mask instead.
#assert(posix.CS8 == posix._CSIZE)

// What cfmakeraw(3) does, except VMIN = 0: we only call read(2) after
// poll(2) says input is ready, and a zero VMIN means a read can never block
// even if that turns out to be wrong.
//
// ISIG is cleared, so Ctrl+C / Ctrl+Z / Ctrl+\ arrive as bytes (0x03, 0x1a,
// 0x1c) instead of signals; deciding what they mean is up to the app.
make_raw :: proc "contextless" (t: posix.termios) -> posix.termios {
	r := t
	r.c_iflag -= {.IGNBRK, .BRKINT, .PARMRK, .ISTRIP, .INLCR, .IGNCR, .ICRNL, .IXON}
	r.c_oflag -= {.OPOST}
	r.c_lflag -= {.ECHO, .ECHONL, .ICANON, .ISIG, .IEXTEN}
	r.c_cflag -= posix.CSIZE | {.PARENB}
	r.c_cflag |= posix.CSIZE // == CS8, see above
	r.c_cc[.VMIN] = 0
	r.c_cc[.VTIME] = 0
	return r
}
