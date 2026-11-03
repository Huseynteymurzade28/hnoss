package tests

import "core:testing"
import "../backend"

@(test)
restore_without_init_is_noop :: proc(t: ^testing.T) {
	backend.restore_terminal()
	backend.restore_terminal()
}

@(test)
deinit_zero_backend_is_noop :: proc(t: ^testing.T) {
	b: backend.Backend
	backend.deinit(&b)
	backend.deinit(&b)
}
