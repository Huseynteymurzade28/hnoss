#+build linux
package backend

import "base:intrinsics"
import "core:sys/linux"

Backend :: struct {
	fd:    linux.Fd, // /dev/tty, used for both input and output; -1 when closed
	opts:  Options,
	out:   [dynamic]u8,
	errno: linux.Errno, // OS error behind the last non-None Error, for diagnostics

	winch_installed: bool,
	job_installed:   bool, // SIGTSTP / SIGCONT have our handlers
	n_installed:     int, // how many of TERMINATING_SIGNALS have our handler
	old_winch:       linux.Sig_Action,
	old_tstp:        linux.Sig_Action,
	old_cont:        linux.Sig_Action,
	old_actions:     [len(TERMINATING_SIGNALS)]linux.Sig_Action,
}

// Signals that would kill the process with the terminal still in raw mode.
// The first four are sent from outside (kill, closing the window, ...); the
// rest are faults. Odin's panic/trap ends in SIGILL (ud2) or SIGTRAP.
@(private)
TERMINATING_SIGNALS :: [?]linux.Signal{
	.SIGINT, .SIGTERM, .SIGHUP, .SIGQUIT,
	.SIGSEGV, .SIGBUS, .SIGFPE, .SIGILL, .SIGTRAP, .SIGABRT,
}

// The one piece of global state in hnoss. Signal handlers cannot take
// arguments, so whatever they need has to live here.
@(private)
g_state: struct {
	owned:     bool, // a Backend is between init and deinit
	active:    bool, // atomic; true while the terminal is in raw mode
	resized:   bool, // atomic; set by the SIGWINCH handler
	suspended: bool, // atomic; the terminal was restored for a stop and should come back on continue
	resumed:   bool, // atomic; set on SIGCONT, the screen needs a full redraw
	fd:        linux.Fd,
	original:  Termios,
	raw:       Termios,
	// Self-pipe: the SIGWINCH handler writes a byte so a blocked poll(2)
	// wakes up. https://cr.yp.to/docs/selfpipe.html
	wake:     [2]linux.Fd,
	seq:       [128]u8, // escape sequence that undoes what init turned on
	seq_len:   int,
	enter:     [128]u8, // escape sequence that turns it on (again, after a stop)
	enter_len: int,
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
	fd, errno := linux.open("/dev/tty", {.RDWR, .NOCTTY, .CLOEXEC})
	if errno != .NONE {
		return fail(b, .Not_A_Terminal, errno)
	}
	b.fd = fd

	original: Termios
	if errno = ioctl(fd, TCGETS, &original); errno != .NONE {
		return fail(b, .Not_A_Terminal, errno)
	}

	if errno = linux.pipe2(&g_state.wake, {.NONBLOCK, .CLOEXEC}); errno != .NONE {
		g_state.wake = {-1, -1}
		return fail(b, .Pipe_Failed, errno)
	}

	g_state.fd = fd
	g_state.original = original
	g_state.raw = make_raw(original)
	build_sequences(opts)
	intrinsics.atomic_store(&g_state.resized, false)
	intrinsics.atomic_store(&g_state.suspended, false)
	intrinsics.atomic_store(&g_state.resumed, false)
	// Arm the hook before touching the terminal, so a failure from here
	// on still gets undone.
	intrinsics.atomic_store(&g_state.active, true)

	install_signal_handlers(b) or_return

	if errno = ioctl(fd, TCSETS, &g_state.raw); errno != .NONE {
		return fail(b, .Termios_Failed, errno)
	}

	write_bytes(b, g_state.enter[:g_state.enter_len])
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
		if p >= 0 { linux.close(p) }
	}
	g_state.wake = {-1, -1}
	g_state.owned = false
	if b.fd >= 0 { linux.close(b.fd) }
	delete(b.out)
	b^ = {fd = -1}
}

// Undo raw mode, show the cursor, leave the alt screen. Only async-signal-safe
// syscalls, no allocation, no context: it runs inside signal handlers.
// Idempotent; whoever flips `active` first does the work.
restore_terminal :: proc "contextless" () {
	if !intrinsics.atomic_exchange(&g_state.active, false) {
		return
	}
	write_all(g_state.fd, g_state.seq[:g_state.seq_len])
	ioctl(g_state.fd, TCSETS, &g_state.original)
}

// Puts back what restore_terminal undid for a stop (see stop_and_resume).
// Async-signal-safe like restore_terminal; does nothing unless suspended.
@(private = "file")
resume_terminal :: proc "contextless" () {
	if !intrinsics.atomic_exchange(&g_state.suspended, false) {
		return
	}
	// Armed first, as in init: a signal from here on restores again.
	intrinsics.atomic_store(&g_state.active, true)
	// From a background job this raises SIGTTOU and stops us again until
	// `fg`, which is what should happen.
	ioctl(g_state.fd, TCSETS, &g_state.raw)
	write_all(g_state.fd, g_state.enter[:g_state.enter_len])
	mark_resumed()
}

// Restores the terminal, stops the process like a Ctrl+Z in cooked mode
// would, and once it is continued (`fg`) puts raw mode and everything init
// turned on back. `pid` 0 stops the whole process group, as the kernel does
// for Ctrl+Z (e.g. `app | less`). Async-signal-safe.
@(private = "file")
stop_and_resume :: proc "contextless" (pid: linux.Pid) {
	if intrinsics.atomic_load(&g_state.active) {
		intrinsics.atomic_store(&g_state.suspended, true)
		restore_terminal()
	}
	// SIGTSTP with the default action stops us; our own handler (if
	// installed) is put back afterwards.
	dfl := linux.Sig_Action{special = .SIG_DFL}
	old: linux.Sig_Action
	linux.rt_sigaction(.SIGTSTP, &dfl, &old)
	linux.kill(pid, .SIGTSTP)
	// Continued. The SIGCONT handler, if installed, has already resumed.
	linux.rt_sigaction(.SIGTSTP, &old, nil)
	resume_terminal()
}

// Restores the terminal and stops the process (what Ctrl+Z does in a
// program that isn't in raw mode). Returns after the shell continues it,
// with the terminal back as init set it up; take_resumed then reports true
// so the caller can redraw everything.
suspend :: proc(b: ^Backend) -> Error {
	if b.fd < 0 {
		return .None
	}
	err := flush(b)
	stop_and_resume(0)
	return err
}

// True once after the process was stopped and continued: the screen was
// left (or changed by whatever ran meanwhile) and needs a full redraw.
take_resumed :: proc "contextless" () -> bool {
	return intrinsics.atomic_exchange(&g_state.resumed, false)
}

@(private = "file")
mark_resumed :: proc "contextless" () {
	intrinsics.atomic_store(&g_state.resumed, true)
	one := [1]u8{1}
	linux.write(g_state.wake[1], one[:]) // wake a blocked read
}

size :: proc(b: ^Backend) -> (Size, Error) {
	ws: Winsize
	if errno := ioctl(b.fd, TIOCGWINSZ, &ws); errno != .NONE {
		return {}, fail(b, .Size_Failed, errno)
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
	fds := [2]linux.Poll_Fd{
		{fd = b.fd, events = {.IN}},
		{fd = g_state.wake[0], events = {.IN}},
	}
	n, errno := linux.poll(fds[:], i32(timeout_ms))
	if errno == .EINTR {
		// A signal (most likely SIGWINCH) interrupted the wait.
		n = 0
	} else if errno != .NONE {
		return {}, fail(b, .Read_Failed, errno)
	}

	if n > 0 && .IN in fds[1].revents {
		drain: [64]u8
		for {
			k, e := linux.read(g_state.wake[0], drain[:])
			if k <= 0 || e != .NONE { break }
		}
	}
	res.resized = intrinsics.atomic_exchange(&g_state.resized, false)

	if n > 0 && fds[0].revents & {.IN, .HUP, .ERR} != {} {
		k, e := linux.read(b.fd, buf)
		switch {
		case e == .EINTR || e == .EAGAIN:
		case e != .NONE:
			return res, fail(b, .Read_Failed, e)
		case k == 0 && .HUP in fds[0].revents:
			return res, fail(b, .Hangup, .NONE)
		case:
			res.n = k
		}
	}
	return
}

@(private = "file")
fail :: proc "contextless" (b: ^Backend, err: Error, errno: linux.Errno) -> Error {
	b.errno = errno
	return err
}

// Fills g_state.enter (turn everything on) and g_state.seq (turn it off
// again, in reverse order).
@(private = "file")
build_sequences :: proc "contextless" (opts: Options) {
	g_state.enter_len = 0
	if .Alt_Screen in opts { push_enter(ENTER_ALT_SCREEN) }
	if .Hide_Cursor in opts { push_enter(HIDE_CURSOR) }
	if .Bracketed_Paste in opts { push_enter(ENABLE_BRACKETED_PASTE) }
	if .Mouse_Capture in opts { push_enter(ENABLE_MOUSE) }
	if .Kitty_Keyboard in opts { push_enter(ENABLE_KITTY_KEYBOARD) }
	if .Focus_Events in opts { push_enter(ENABLE_FOCUS_EVENTS) }
	push_enter(PUSH_TITLE)
	push_enter(CLEAR_SCREEN)
	push_enter(CURSOR_HOME)

	g_state.seq_len = 0
	push_seq(CANCEL_SEQUENCE)
	push_seq(RESET_SGR)
	if .Mouse_Capture in opts { push_seq(DISABLE_MOUSE) }
	if .Bracketed_Paste in opts { push_seq(DISABLE_BRACKETED_PASTE) }
	if .Focus_Events in opts { push_seq(DISABLE_FOCUS_EVENTS) }
	if .Hide_Cursor in opts { push_seq(SHOW_CURSOR) }
	if .Kitty_Keyboard in opts { push_seq(DISABLE_KITTY_KEYBOARD) }
	push_seq(RESET_CURSOR_SHAPE)
	push_seq(POP_TITLE)
	if .Alt_Screen in opts { push_seq(LEAVE_ALT_SCREEN) }
}

@(private = "file")
push_seq :: proc "contextless" (s: string) {
	n := copy(g_state.seq[g_state.seq_len:], s)
	g_state.seq_len += n
}

@(private = "file")
push_enter :: proc "contextless" (s: string) {
	n := copy(g_state.enter[g_state.enter_len:], s)
	g_state.enter_len += n
}

@(private = "file")
ioctl :: proc "contextless" (fd: linux.Fd, request: u32, arg: rawptr) -> linux.Errno {
	ret := int(linux.ioctl(fd, request, uintptr(arg)))
	return ret < 0 ? linux.Errno(-ret) : .NONE
}

@(private = "file")
write_all :: proc "contextless" (fd: linux.Fd, data: []u8) -> linux.Errno {
	rest := data
	for len(rest) > 0 {
		n, errno := linux.write(fd, rest)
		#partial switch errno {
		case .NONE:
			rest = rest[n:]
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
	winch := linux.Sig_Action{handler = winch_handler, flags = {.RESTART}}
	if errno := linux.rt_sigaction(.SIGWINCH, &winch, &b.old_winch); errno != .NONE {
		return fail(b, .Signal_Failed, errno)
	}
	b.winch_installed = true

	if .Signal_Handlers not_in b.opts {
		return .None
	}
	// NODEFER: the handler re-raises SIGTSTP to actually stop, which must
	// not stay blocked until the handler returns.
	tstp := linux.Sig_Action{handler = tstp_handler, flags = {.RESTART, .NODEFER}}
	cont := linux.Sig_Action{handler = cont_handler, flags = {.RESTART}}
	if errno := linux.rt_sigaction(.SIGCONT, &cont, &b.old_cont); errno != .NONE {
		return fail(b, .Signal_Failed, errno)
	}
	if errno := linux.rt_sigaction(.SIGTSTP, &tstp, &b.old_tstp); errno != .NONE {
		linux.rt_sigaction(.SIGCONT, &b.old_cont, nil)
		return fail(b, .Signal_Failed, errno)
	}
	b.job_installed = true

	for sig, i in TERMINATING_SIGNALS {
		// RESETHAND: the disposition goes back to SIG_DFL on entry, so the
		// re-raise in the handler kills the process the normal way.
		act := linux.Sig_Action{handler = terminating_handler, flags = {.RESETHAND}}
		if errno := linux.rt_sigaction(sig, &act, &b.old_actions[i]); errno != .NONE {
			return fail(b, .Signal_Failed, errno)
		}
		b.n_installed = i + 1
	}
	return .None
}

@(private = "file")
uninstall_signal_handlers :: proc(b: ^Backend) {
	if b.winch_installed {
		linux.rt_sigaction(.SIGWINCH, &b.old_winch, nil)
	}
	if b.job_installed {
		linux.rt_sigaction(.SIGTSTP, &b.old_tstp, nil)
		linux.rt_sigaction(.SIGCONT, &b.old_cont, nil)
	}
	sigs := TERMINATING_SIGNALS
	for i in 0 ..< b.n_installed {
		linux.rt_sigaction(sigs[i], &b.old_actions[i], nil)
	}
	b.winch_installed = false
	b.job_installed = false
	b.n_installed = 0
}

@(private = "file")
winch_handler :: proc "c" (sig: linux.Signal) {
	intrinsics.atomic_store(&g_state.resized, true)
	one := [1]u8{1}
	linux.write(g_state.wake[1], one[:]) // pipe full is fine: a wakeup is pending anyway
}

@(private = "file")
terminating_handler :: proc "c" (sig: linux.Signal) {
	restore_terminal()
	// Re-raise with the default disposition (see RESETHAND above) so the
	// exit status and core-dump behaviour are what they would have been.
	// For faults, returning re-executes the faulting instruction, which
	// then hits SIG_DFL as well.
	linux.kill(linux.getpid(), sig)
}

// `kill -TSTP` from outside (Ctrl+Z itself arrives as a key, see
// Option.Ctrl_Z_Suspends): restore, stop, and come back on continue.
@(private = "file")
tstp_handler :: proc "c" (sig: linux.Signal) {
	stop_and_resume(linux.getpid())
}

// Continued after any stop, ours or a SIGSTOP from outside: put the
// terminal back if we restored it, and have the next frame redraw all.
@(private = "file")
cont_handler :: proc "c" (sig: linux.Signal) {
	resume_terminal()
	mark_resumed()
}
