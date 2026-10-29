package tests

import "core:strings"
import "../buffer"

// The buffer's rows as text, trailing spaces trimmed (temp allocator).
screen_rows :: proc(b: ^buffer.Buffer) -> []string {
	out := make([]string, b.area.height, context.temp_allocator)
	for y in 0 ..< b.area.height {
		sb := strings.builder_make(context.temp_allocator)
		for x := 0; x < b.area.width; {
			c := buffer.get(b, b.area.x + x, b.area.y + y)
			strings.write_string(&sb, buffer.cell_symbol(c))
			x += max(int(c.width), 1)
		}
		out[y] = strings.trim_right(strings.to_string(sb), " ")
	}
	return out
}
