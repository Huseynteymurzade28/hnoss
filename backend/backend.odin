package backend

import "base:runtime"

Option :: enum u8 {
	// Switch to the alternate screen (xterm `?1049`), so the user's shell
	// scrollback is left untouched and comes back on exit.
	Alt_Screen,
	Hide_Cursor,
	// Restore the terminal and re-raise on SIGINT/SIGTERM/SIGHUP/SIGQUIT and
	// on fatal signals (SIGSEGV, SIGBUS, SIGFPE, SIGILL, SIGTRAP, SIGABRT).
	// Any handlers you installed before `init` are put back by `deinit`.
	Signal_Handlers,
}
Options :: bit_set[Option; u8]

DEFAULT_OPTIONS :: Options{.Alt_Screen, .Hide_Cursor, .Signal_Handlers}

Error :: enum u8 {
	None,
	Already_Active, // only one Backend may own the terminal at a time
	Not_A_Terminal, // no controlling terminal, or /dev/tty is not a tty
	Termios_Failed,
	Signal_Failed,
	Pipe_Failed,
	Size_Failed,
	Write_Failed,
	Read_Failed,
	Hangup, // the terminal went away (e.g. the emulator window was closed)
	Out_Of_Memory,
}

Size :: struct {
	cols, rows: int,
}

Read_Result :: struct {
	n:       int,  // bytes written into the caller's buffer
	resized: bool, // the terminal size changed since the previous read
}

// Escape sequences. References:
//   https://invisible-island.net/xterm/ctlseqs/ctlseqs.html
//   https://vt100.net/docs/vt510-rm/
ENTER_ALT_SCREEN :: "\x1b[?1049h" // save cursor, switch to alt buffer, clear it
LEAVE_ALT_SCREEN :: "\x1b[?1049l" // back to the main buffer, restore cursor
HIDE_CURSOR      :: "\x1b[?25l"
SHOW_CURSOR      :: "\x1b[?25h"
RESET_SGR        :: "\x1b[0m"
CLEAR_SCREEN     :: "\x1b[2J"
CURSOR_HOME      :: "\x1b[H"
// CAN (0x18) aborts any escape sequence the terminal is in the middle of
// parsing. The restore hook can fire while a frame is half written, so it
// sends CAN first to make sure the sequences after it are read cleanly.
CANCEL_SEQUENCE  :: "\x18"

// Install with `context.assertion_failure_proc = backend.assertion_failure_proc`.
// It restores the terminal *before* the panic message is printed, so the
// message ends up on the main screen instead of vanishing with the alt screen.
assertion_failure_proc :: proc(prefix, message: string, loc: runtime.Source_Code_Location) -> ! {
	restore_terminal()
	runtime.default_assertion_failure_proc(prefix, message, loc)
}

// Safety net for a `main` that returns without calling `deinit`.
// (`os.exit` skips @(fini) procs; use `deinit` before it.)
@(fini, private = "file")
restore_at_exit :: proc "contextless" () {
	restore_terminal()
}
