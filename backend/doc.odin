/*
Package backend is the platform layer: raw mode, alternate screen, cursor
visibility, terminal size, output writes and input bytes.

Every platform provides the same small set of procedures in its own
`*_<os>.odin` files; the right one is picked at compile time, there is no
vtable. The contract:

	init         :: proc(b: ^Backend, opts := Options{}, allocator := context.allocator) -> Error
	deinit       :: proc(b: ^Backend)
	size         :: proc(b: ^Backend) -> (Size, Error)
	write        :: proc(b: ^Backend, s: string)            // buffered
	flush        :: proc(b: ^Backend) -> Error              // one write(2) per call (modulo partial writes)
	read         :: proc(b: ^Backend, buf: []u8, timeout_ms: int) -> (Read_Result, Error)
	restore_terminal         :: proc "contextless" ()      // idempotent, async-signal-safe
	assertion_failure_proc   :: runtime.Assertion_Failure_Proc

Restore safety: `init` registers the terminal in a single global restore
hook (the only global state in hnoss). It is run by `deinit`, by an
`@(fini)` procedure when `main` returns, by signal handlers for
SIGINT/SIGTERM/SIGHUP/SIGQUIT and fatal signals, and by
`assertion_failure_proc` if you install it:

	context.assertion_failure_proc = backend.assertion_failure_proc

Installing it matters: Odin prints panic messages to stderr *before*
trapping, and that text would land on the alternate screen and vanish.
The custom proc restores the terminal first, so the message stays visible.
Bounds-check failures bypass assertion_failure_proc; the terminal is still
restored (via SIGILL), but their message is lost with the alt screen.
*/
package backend
