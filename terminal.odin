package hnoss

import "core:mem"
import "backend"
import "buffer"
import "layout"

Rect :: layout.Rect
Buffer :: buffer.Buffer
Error :: backend.Error

// Owns the terminal and two buffers: `front` is what is on screen, `back`
// is what the current frame draws into. end_frame diffs back against front,
// writes the difference in one go, then swaps them.
Terminal :: struct {
	backend:      backend.Backend,
	buffers:      [2]Buffer,
	current:      int, // index of the back buffer
	frame:        Frame,
	frame_count:  u64,
	needs_clear:  bool,
	last_bytes:   int, // bytes written by the last end_frame, for diagnostics
	allocator:    mem.Allocator,
}

// What a frame's draw code works with. Valid between begin_frame and end_frame.
Frame :: struct {
	area:   Rect, // the whole terminal
	buffer: ^Buffer,
	count:  u64, // frame number, starting at 0
}

init :: proc(opts := backend.DEFAULT_OPTIONS, allocator := context.allocator) -> (t: Terminal, err: Error) {
	t.allocator = allocator
	backend.init(&t.backend, opts, allocator) or_return
	defer if err != .None { backend.deinit(&t.backend) }

	sz := backend.size(&t.backend) or_return
	area := Rect{0, 0, sz.cols, sz.rows}
	for &b in t.buffers {
		if buffer.init(&b, area, allocator) != nil {
			return t, .Out_Of_Memory
		}
	}
	return t, .None
}

deinit :: proc(t: ^Terminal) {
	for &b in t.buffers {
		buffer.destroy(&b)
	}
	backend.deinit(&t.backend)
}

// Starts a frame. Picks up terminal resizes here, so a frame always matches
// the current size. The returned Frame starts blank.
begin_frame :: proc(t: ^Terminal) -> ^Frame {
	if sz, err := backend.size(&t.backend); err == .None {
		area := Rect{0, 0, sz.cols, sz.rows}
		if area != t.buffers[0].area {
			for &b in t.buffers {
				if buffer.resize(&b, area) != nil {
					panic("hnoss: out of memory resizing frame buffers")
				}
			}
			t.needs_clear = true
		}
	}
	back := &t.buffers[t.current]
	buffer.reset(back)
	t.frame = {area = back.area, buffer = back, count = t.frame_count}
	return &t.frame
}

// Diffs the frame against what is on screen and writes the changes with a
// single flush.
end_frame :: proc(t: ^Terminal) -> Error {
	back := &t.buffers[t.current]
	front := &t.buffers[1 - t.current]

	b := &t.backend
	start := len(b.out)
	backend.write(b, buffer.BEGIN_SYNC)
	if t.needs_clear {
		// After a clear the screen is blank, which is exactly an empty
		// buffer: diffing against one redraws everything that isn't blank.
		backend.write(b, backend.RESET_SGR)
		backend.write(b, backend.CLEAR_SCREEN)
		buffer.reset(front)
		t.needs_clear = false
	}
	buffer.diff(front, back, &b.out)
	backend.write(b, buffer.END_SYNC)
	t.last_bytes = len(b.out) - start

	t.current = 1 - t.current
	t.frame_count += 1
	return backend.flush(b)
}

// Forces the next frame to repaint the whole screen (e.g. after something
// else wrote to the terminal).
clear :: proc(t: ^Terminal) {
	t.needs_clear = true
}
