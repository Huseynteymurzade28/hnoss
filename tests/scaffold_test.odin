package tests

import "core:testing"
import hnoss ".."

@(test)
version_is_set :: proc(t: ^testing.T) {
	testing.expect(t, len(hnoss.VERSION) > 0)
}
