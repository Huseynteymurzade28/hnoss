#+build darwin
package backend

import "base:intrinsics"
import "core:c"
import "core:sys/posix"

Backend :: struct {
	fd:    posix.FD, // /dev/tty, used for both input and output; -1 when closed
	opts:  Options,
	out:   [dynamic]u8,
	errno: posix.Errno, // OS error behind the last non-None Error, for diagnostics

	winch_installed: bool,
	n_installed:     int, // how many of TERMINATING_SIGNALS have our handler
	old_winch:       posix.sigaction_t,
	old_actions:     [len(TERMINATING_SIGNALS)]posix.sigaction_t,
}

// Signals that would kill the process with the terminal still in raw mode.
// The first four are sent from outside (kill, closing the window, ...); the
// rest are faults. Odin's panic/trap ends in SIGILL or SIGTRAP.
@(private)
TERMINATING_SIGNALS :: [?]posix.Signal{
	.SIGINT, .SIGTERM, .SIGHUP, .SIGQUIT,
	.SIGSEGV, .SIGBUS, .SIGFPE, .SIGILL, .SIGTRAP, .SIGABRT,
}

// The one piece of global state in hnoss. Signal handlers cannot take
// arguments, so whatever they need has to live here.
@(private)
g_state: struct {
	owned:    bool, // a Backend is between init and deinit
	active:   bool, // atomic; true while the terminal is in raw mode
	resized:  bool, // atomic; set by the SIGWINCH handler
	fd:       posix.FD,
	original: posix.termios,
	// Self-pipe: the SIGWINCH handler writes a byte so a blocked poll(2)
	// wakes up. https://cr.yp.to/docs/selfpipe.html
	wake:     [2]posix.FD,
	seq:      [128]u8, // escape sequence that undoes what init turned on
	seq_len:  int,
}

init :: proc(b: ^Backend, opts := DEFAULT_OPTIONS, allocator := context.allocator) -> (err: Error) {
	if g_state.owned {
		return .Already_Active
	}
	g_state.owned = true
	g_state.wake = {-1, -1}
	b^ = {fd = -1, opts = opts, out = make([dynamic]u8, 0, 16 * 1024, allocator)}
	defer if err != .None { deinit(b) }

	// /dev/tty rather than stdin/stdout, so the UI still works with a
	// redirected stdout (`app > log.txt`).
	fd := posix.open("/dev/tty", {.RDWR, .NOCTTY, .CLOEXEC})
	if fd < 0 {
		return fail(b, .Not_A_Terminal, posix.errno())
	}
	b.fd = fd

	original: posix.termios
	if posix.tcgetattr(fd, &original) != .OK {
		return fail(b, .Not_A_Terminal, posix.errno())
	}

	// No pipe2 on macOS: set the flags afterwards. Nothing else runs yet,
	// so the window before CLOEXEC is set doesn't matter.
	if errno := make_wake_pipe(); errno != .NONE {
		return fail(b, .Pipe_Failed, errno)
	}
	// read uses select(2), whose fd_set only holds fds below FD_SETSIZE
	// (and FD_SET doesn't actually stop out-of-range writes).
	if fd >= posix.FD_SETSIZE || g_state.wake[0] >= posix.FD_SETSIZE {
		return fail(b, .Pipe_Failed, .EMFILE)
	}

	g_state.fd = fd
	g_state.original = original
	g_state.seq_len = 0
	push_seq(CANCEL_SEQUENCE)
	push_seq(RESET_SGR)
	if .Mouse_Capture in opts { push_seq(DISABLE_MOUSE) }
	if .Bracketed_Paste in opts { push_seq(DISABLE_BRACKETED_PASTE) }
	if .Focus_Events in opts { push_seq(DISABLE_FOCUS_EVENTS) }
	if .Hide_Cursor in opts { push_seq(SHOW_CURSOR) }
	if .Kitty_Keyboard in opts { push_seq(DISABLE_KITTY_KEYBOARD) }
	if .Alt_Screen in opts { push_seq(LEAVE_ALT_SCREEN) }
	intrinsics.atomic_store(&g_state.resized, false)
	// Arm the hook before touching the terminal, so a failure from here
	// on still gets undone.
	intrinsics.atomic_store(&g_state.active, true)

	install_signal_handlers(b) or_return

	raw := make_raw(original)
	if posix.tcsetattr(fd, .TCSANOW, &raw) != .OK {
		return fail(b, .Termios_Failed, posix.errno())
	}

	if .Alt_Screen in opts { write(b, ENTER_ALT_SCREEN) }
	if .Hide_Cursor in opts { write(b, HIDE_CURSOR) }
	if .Bracketed_Paste in opts { write(b, ENABLE_BRACKETED_PASTE) }
	if .Mouse_Capture in opts { write(b, ENABLE_MOUSE) }
	if .Kitty_Keyboard in opts { write(b, ENABLE_KITTY_KEYBOARD) }
	if .Focus_Events in opts { write(b, ENABLE_FOCUS_EVENTS) }
	write(b, CLEAR_SCREEN)
	write(b, CURSOR_HOME)
	return flush(b)
}

// Restores the terminal and releases everything init acquired. Safe to call
// more than once, and after a failed init.
deinit :: proc(b: ^Backend) {
	if b.out == nil {
		return
	}
	// Push out a half-built frame first; restore sequences go after it.
	if b.fd >= 0 { flush(b) }
	restore_terminal()
	uninstall_signal_handlers(b)

	for p in g_state.wake {
		if p >= 0 { posix.close(p) }
	}
	g_state.wake = {-1, -1}
	g_state.owned = false
	if b.fd >= 0 { posix.close(b.fd) }
	delete(b.out)
	b^ = {fd = -1}
}

// Undo raw mode, show the cursor, leave the alt screen. Only async-signal-safe
// calls, no allocation, no context: it runs inside signal handlers.
// Idempotent; whoever flips `active` first does the work.
restore_terminal :: proc "contextless" () {
	if !intrinsics.atomic_exchange(&g_state.active, false) {
		return
	}
	write_all(g_state.fd, g_state.seq[:g_state.seq_len])
	posix.tcsetattr(g_state.fd, .TCSANOW, &g_state.original)
}

size :: proc(b: ^Backend) -> (Size, Error) {
	ws: Winsize
	if ioctl(b.fd, TIOCGWINSZ, &ws) < 0 {
		return {}, fail(b, .Size_Failed, posix.errno())
	}
	// Some environments (serial consoles, odd ptys) report 0x0.
	if ws.col == 0 || ws.row == 0 {
		return {}, fail(b, .Size_Failed, .NONE)
	}
	return {int(ws.col), int(ws.row)}, .None
}

// Queues output; nothing reaches the terminal until `flush`.
write :: proc(b: ^Backend, s: string) {
	append(&b.out, s)
}

write_bytes :: proc(b: ^Backend, s: []u8) {
	append(&b.out, ..s)
}

flush :: proc(b: ^Backend) -> Error {
	if len(b.out) == 0 {
		return .None
	}
	errno := write_all(b.fd, b.out[:])
	clear(&b.out)
	if errno != .NONE {
		return fail(b, .Write_Failed, errno)
	}
	return .None
}

// Waits up to `timeout_ms` (-1 = forever, 0 = don't wait) for input or a
// resize, then reads whatever input is available into `buf`.
read :: proc(b: ^Backend, buf: []u8, timeout_ms: int) -> (res: Read_Result, err: Error) {
	// select(2), not poll(2): macOS poll doesn't support character devices
	// and reports POLLNVAL for /dev/tty straight away, which would spin.
	// init guarantees both fds are < FD_SETSIZE.
	rfds: posix.fd_set
	posix.FD_SET(b.fd, &rfds)
	posix.FD_SET(g_state.wake[0], &rfds)
	tv: posix.timeval
	tvp: ^posix.timeval // nil = wait forever
	if timeout_ms >= 0 {
		tv = {
			tv_sec  = posix.time_t(timeout_ms / 1000),
			tv_usec = posix.suseconds_t(timeout_ms % 1000 * 1000),
		}
		tvp = &tv
	}
	nfds := c.int(max(b.fd, g_state.wake[0])) + 1
	n := posix.select(nfds, &rfds, nil, nil, tvp)
	if n < 0 {
		if errno := posix.errno(); errno != .EINTR {
			return {}, fail(b, .Read_Failed, errno)
		}
		// A signal (most likely SIGWINCH) interrupted the wait.
		n = 0
	}

	if n > 0 && posix.FD_ISSET(g_state.wake[0], &rfds) {
		drain: [64]u8
		for posix.read(g_state.wake[0], raw_data(drain[:]), len(drain)) > 0 {}
	}
	res.resized = intrinsics.atomic_exchange(&g_state.resized, false)

	// select also reports a hung-up tty as readable; read then returns 0.
	if n > 0 && posix.FD_ISSET(b.fd, &rfds) {
		k := posix.read(b.fd, raw_data(buf), len(buf))
		switch {
		case k < 0:
			if e := posix.errno(); e != .EINTR && e != .EAGAIN {
				return res, fail(b, .Read_Failed, e)
			}
		case k == 0:
			return res, fail(b, .Hangup, .NONE)
		case:
			res.n = int(k)
		}
	}
	return
}

@(private = "file")
fail :: proc "contextless" (b: ^Backend, err: Error, errno: posix.Errno) -> Error {
	b.errno = errno
	return err
}

@(private = "file")
push_seq :: proc "contextless" (s: string) {
	n := copy(g_state.seq[g_state.seq_len:], s)
	g_state.seq_len += n
}

// Creates g_state.wake, non-blocking and close-on-exec on both ends.
@(private = "file")
make_wake_pipe :: proc "contextless" () -> posix.Errno {
	if posix.pipe(&g_state.wake) != .OK {
		g_state.wake = {-1, -1}
		return posix.errno()
	}
	for p in g_state.wake {
		fl := posix.fcntl(p, .GETFL)
		if fl < 0 ||
		   posix.fcntl(p, .SETFL, fl | posix.O_NONBLOCK) < 0 ||
		   posix.fcntl(p, .SETFD, c.int(posix.FD_CLOEXEC)) < 0 {
			return posix.errno() // deinit closes the pipe
		}
	}
	return .NONE
}

@(private = "file")
write_all :: proc "contextless" (fd: posix.FD, data: []u8) -> posix.Errno {
	rest := data
	for len(rest) > 0 {
		n := posix.write(fd, raw_data(rest), len(rest))
		if n >= 0 {
			rest = rest[n:]
			continue
		}
		#partial switch errno := posix.errno(); errno {
		case .EINTR, .EAGAIN:
			continue
		case:
			return errno
		}
	}
	return .NONE
}

@(private = "file")
install_signal_handlers :: proc(b: ^Backend) -> Error {
	winch := posix.sigaction_t{sa_handler = winch_handler, sa_flags = {.RESTART}}
	if posix.sigaction(SIGWINCH, &winch, &b.old_winch) != .OK {
		return fail(b, .Signal_Failed, posix.errno())
	}
	b.winch_installed = true

	if .Signal_Handlers not_in b.opts {
		return .None
	}
	for sig, i in TERMINATING_SIGNALS {
		// RESETHAND: the disposition goes back to SIG_DFL on entry, so the
		// re-raise in the handler kills the process the normal way.
		act := posix.sigaction_t{sa_handler = terminating_handler, sa_flags = {.RESETHAND}}
		if posix.sigaction(sig, &act, &b.old_actions[i]) != .OK {
			return fail(b, .Signal_Failed, posix.errno())
		}
		b.n_installed = i + 1
	}
	return .None
}

@(private = "file")
uninstall_signal_handlers :: proc(b: ^Backend) {
	if b.winch_installed {
		posix.sigaction(SIGWINCH, &b.old_winch, nil)
	}
	sigs := TERMINATING_SIGNALS
	for i in 0 ..< b.n_installed {
		posix.sigaction(sigs[i], &b.old_actions[i], nil)
	}
	b.winch_installed = false
	b.n_installed = 0
}

@(private = "file")
winch_handler :: proc "c" (sig: posix.Signal) {
	// libc's write can clobber errno, which the interrupted code may be
	// about to read.
	saved := posix.errno()
	intrinsics.atomic_store(&g_state.resized, true)
	one := [1]u8{1}
	posix.write(g_state.wake[1], raw_data(one[:]), 1) // pipe full is fine: a wakeup is pending anyway
	posix.errno(saved)
}

@(private = "file")
terminating_handler :: proc "c" (sig: posix.Signal) {
	restore_terminal()
	// macOS ignores SA_RESETHAND for SIGILL and SIGTRAP (Odin's panic/trap
	// ends in one of those), so reset the disposition by hand; otherwise the
	// re-raise below re-enters this handler forever.
	dfl := posix.sigaction_t{sa_handler = auto_cast posix.SIG_DFL}
	posix.sigaction(sig, &dfl, nil)
	// Re-raise with the default disposition so the
	// exit status and core-dump behaviour are what they would have been.
	// For faults, returning re-executes the faulting instruction, which
	// then hits SIG_DFL as well.
	posix.kill(posix.getpid(), sig)
}
