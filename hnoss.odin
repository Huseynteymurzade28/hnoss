/*
Package hnoss is an immediate-mode, widget-rich TUI library written in pure Odin.

The root package is the user-facing entry point: it owns the Terminal and
re-exports the commonly used types from the sub-packages.

	term, err := hnoss.init()
	defer hnoss.deinit(&term)
	for running {
		f := hnoss.begin_frame(&term)
		buffer.set_string(f.buffer, 0, 0, "hello")
		hnoss.end_frame(&term)
	}
*/
package hnoss

VERSION :: "0.0.1"
