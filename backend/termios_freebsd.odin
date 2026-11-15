#+build freebsd
package backend

// core:sys/posix covers termios on FreeBSD (with the right layout: tcflag_t
// is 32-bit here), but not ioctl or struct winsize, so those live here.

import "base:intrinsics"
import "core:c"
import "core:sys/freebsd"
import "core:sys/posix"

// The terminal ABI pieces from <sys/ttycom.h>, as raw ioctls like the Linux
// backend: no libc import.
//
// The size encoded in TIOCGETA/TIOCSETA is sizeof(struct termios) == 44,
// which the assert below pins down. tcgetattr(3) and tcsetattr(3) are only
// wrappers around these two requests.
TIOCGETA   :: 0x402c7413 // _IOR('t', 19, struct termios)
TIOCSETA   :: 0x802c7414 // _IOW('t', 20, struct termios)
TIOCGWINSZ :: 0x40087468 // _IOR('t', 104, struct winsize)

#assert(size_of(posix.termios) == 44)

// core:sys/freebsd has an ioctl wrapper, but it drops the request argument
// (it calls ioctl(fd, arg)), so the syscall is made directly. FreeBSD's
// syscall ABI is stable, unlike macOS (see termios_darwin.odin).
@(private)
ioctl :: proc "contextless" (fd: posix.FD, request: c.ulong, arg: rawptr) -> posix.Errno {
	res, ok := intrinsics.syscall_bsd(freebsd.SYS_ioctl, uintptr(fd), uintptr(request), uintptr(arg))
	return ok ? .NONE : cast(posix.Errno)res
}

// Not POSIX, so posix.Signal has no member for it. sys/signal.h
SIGWINCH :: posix.Signal(28)

Winsize :: struct {
	row, col:       u16,
	xpixel, ypixel: u16,
}
#assert(size_of(Winsize) == 8)

// On FreeBSD CS8 is both bits of CSIZE (0x300). posix.CControl_Flag_Bits.CS8
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
