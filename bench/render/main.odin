// Times the render pipeline without a terminal: filling a buffer, diffing
// a frame where every cell changes, and a frame where nothing does.
// Run: odin run bench/render -o:speed
package main

import "core:fmt"
import "core:time"
import "../../buffer"
import "../../style"

W :: 200
H :: 60
ITER :: 200

main :: proc() {
	a, b: buffer.Buffer
	buffer.init(&a, {0, 0, W, H})
	buffer.init(&b, {0, 0, W, H})
	defer buffer.destroy(&a)
	defer buffer.destroy(&b)
	out := make([dynamic]u8, 0, 1 << 20)
	defer delete(out)

	fill :: proc(buf: ^buffer.Buffer, seed: int) {
		for y in 0 ..< H {
			for x in 0 ..< W {
				v := u8((x * 7 + y * 13 + seed * 5) & 0xff)
				buffer.set_symbol(buf, x, y, "▀", 1, {fg = style.rgb(v, 255 - v, v / 2), bg = style.rgb(v / 3, v, 255 - v)})
			}
		}
	}

	sw: time.Stopwatch
	time.stopwatch_start(&sw)
	for i in 0 ..< ITER {
		fill(&b, i)
	}
	time.stopwatch_stop(&sw)
	report("fill (set_symbol, every cell)", sw)

	time.stopwatch_reset(&sw)
	bytes := 0
	for i in 0 ..< ITER {
		fill(&a, i)
		fill(&b, i + 1)
		clear(&out)
		time.stopwatch_start(&sw)
		buffer.diff(&a, &b, &out)
		time.stopwatch_stop(&sw)
		bytes = len(out)
	}
	report("diff, every cell changed", sw)
	fmt.printfln("    %d KiB per frame", bytes / 1024)

	time.stopwatch_reset(&sw)
	fill(&a, 0)
	fill(&b, 0)
	for _ in 0 ..< ITER {
		clear(&out)
		time.stopwatch_start(&sw)
		buffer.diff(&a, &b, &out)
		time.stopwatch_stop(&sw)
	}
	report("diff, nothing changed", sw)
}

report :: proc(name: string, sw: time.Stopwatch) {
	d := time.stopwatch_duration(sw)
	fmt.printfln("%-32s %7.3f ms/frame  (%dx%d)", name, time.duration_milliseconds(d) / ITER, W, H)
}
