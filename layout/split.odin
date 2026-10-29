package layout

Direction :: enum u8 {
	Vertical,   // pieces stacked top to bottom (rows)
	Horizontal, // pieces side by side, left to right (columns)
}

// How big one piece of a split is. A plain number is a size in cells:
//
//	split(area, .Vertical, {1, fill(), 3})          // 1-row header, 3-row footer, body gets the rest
//	split(area, .Horizontal, {percent(30), fill(2), fill(1)}, gap = 1)
Size :: union {
	int,     // exactly this many cells
	Percent, // a share of the space (after gaps)
	Fill,    // a weighted share of whatever is left over
}

Percent :: struct {
	value: int, // 0..100
}

Fill :: struct {
	weight: int,
}

percent :: proc(p: int) -> Size { return Percent{p} }
fill :: proc(weight := 1) -> Size { return Fill{weight} }

// Divides `r` into len(sizes) pieces along `dir`, with `gap` cells between
// pieces. No allocation: the result is a fixed-size array.
//
// Rules, in order:
//  1. Cells and percents get their size, first come first served: if the
//     space runs out, later pieces shrink (down to zero).
//  2. What is left is shared by the fills in proportion to their weights,
//     rounded so the pieces add up exactly. With no fills, the leftover
//     space stays unused at the end.
split :: proc(r: Rect, dir: Direction, sizes: [$N]Size, gap := 0) -> (out: [N]Rect) {
	total := r.height if dir == .Vertical else r.width
	avail := max(total - max(gap, 0) * (N - 1), 0)

	lengths: [N]int
	remaining := avail
	fill_weight := 0
	for s, i in sizes {
		want := 0
		switch v in s {
		case int:     want = max(v, 0)
		case Percent: want = avail * clamp(v.value, 0, 100) / 100
		case Fill:    fill_weight += max(v.weight, 0); continue
		}
		lengths[i] = min(want, remaining)
		remaining -= lengths[i]
	}

	if fill_weight > 0 {
		// Largest-remainder rounding: floor every share, then hand the
		// leftover cells to the largest fractional parts (earlier first).
		frac: [N]int
		given := 0
		for s, i in sizes {
			if v, ok := s.(Fill); ok {
				w := max(v.weight, 0)
				lengths[i] = remaining * w / fill_weight
				frac[i] = remaining * w % fill_weight
				given += lengths[i]
			}
		}
		for _ in 0 ..< remaining - given {
			best := -1
			for s, i in sizes {
				if _, ok := s.(Fill); ok && (best < 0 || frac[i] > frac[best]) {
					best = i
				}
			}
			lengths[best] += 1
			frac[best] = -1
		}
	}

	pos := r.y if dir == .Vertical else r.x
	for length, i in lengths {
		if dir == .Vertical {
			out[i] = {r.x, pos, r.width, length}
		} else {
			out[i] = {pos, r.y, length, r.height}
		}
		pos += length + max(gap, 0)
	}
	return
}
