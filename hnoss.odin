/*
Package hnoss is an immediate-mode, widget-rich TUI library written in pure Odin.

The root package is the user-facing entry point: it owns the Terminal and
re-exports the commonly used types from the sub-packages.

Status: the Terminal / Frame / draw API arrives in Phase 2. Until then use
`hnoss/backend` directly (see examples/backend_box).
*/
package hnoss

VERSION :: "0.0.1"
