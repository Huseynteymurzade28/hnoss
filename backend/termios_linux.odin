#+build linux
package backend

// core:sys/linux has the ioctl syscall but no termios definitions, so the
// kernel ABI pieces live here.

// The *kernel* `struct termios`, which TCGETS/TCSETS read and write. It is not
// glibc's `struct termios` (that one has NCCS = 32 and extra speed fields).
// Layout from include/uapi/asm-generic/termbits.h; valid on x86, x86_64, arm,
// arm64 and riscv64. (powerpc, mips, sparc and alpha differ.)
NCCS :: 19

Termios :: struct {
	iflag: u32,
	oflag: u32,
	cflag: u32,
	lflag: u32,
	line:  u8,
	cc:    [NCCS]u8,
}
#assert(size_of(Termios) == 36)

// include/uapi/asm-generic/ioctls.h
TCGETS     :: 0x5401
TCSETS     :: 0x5402 // apply now
TIOCGWINSZ :: 0x5413

Winsize :: struct {
	row, col:       u16,
	xpixel, ypixel: u16,
}

// c_iflag
IGNBRK :: 0o000001
BRKINT :: 0o000002
PARMRK :: 0o000010
ISTRIP :: 0o000040
INLCR  :: 0o000100
IGNCR  :: 0o000200
ICRNL  :: 0o000400
IXON   :: 0o002000
// c_oflag
OPOST  :: 0o000001
// c_cflag
CSIZE  :: 0o000060
CS8    :: 0o000060
PARENB :: 0o000400
// c_lflag
ISIG   :: 0o000001
ICANON :: 0o000002
ECHO   :: 0o000010
ECHONL :: 0o000100
IEXTEN :: 0o100000
// c_cc indices
VTIME  :: 5
VMIN   :: 6

// What glibc's cfmakeraw(3) does, except VMIN = 0: we only call read(2)
// after poll(2) says input is ready, and a zero VMIN means a read can
// never block even if that turns out to be wrong.
//
// ISIG is cleared, so Ctrl+C / Ctrl+Z / Ctrl+\ arrive as bytes (0x03, 0x1a,
// 0x1c) instead of signals; deciding what they mean is up to the app.
make_raw :: proc "contextless" (t: Termios) -> Termios {
	r := t
	r.iflag &~= IGNBRK | BRKINT | PARMRK | ISTRIP | INLCR | IGNCR | ICRNL | IXON
	r.oflag &~= OPOST
	r.lflag &~= ECHO | ECHONL | ICANON | ISIG | IEXTEN
	r.cflag &~= CSIZE | PARENB
	r.cflag |= CS8
	r.cc[VMIN] = 0
	r.cc[VTIME] = 0
	return r
}
