package style

import "core:math"

// Linear interpolation between two colors, t in [0, 1].
lerp_rgb :: proc(a, b: Rgb, t: f64) -> Rgb {
	k := clamp(t, 0, 1)
	mix :: proc(x, y: u8, k: f64) -> u8 {
		return u8(math.round(f64(x) + (f64(y) - f64(x)) * k))
	}
	return {mix(a.r, b.r, k), mix(a.g, b.g, k), mix(a.b, b.b, k)}
}

// The color at position t (0..1) along evenly spaced `stops`.
// No stops gives nil (unspecified); one stop is a solid color.
gradient :: proc(stops: []Rgb, t: f64) -> Color {
	switch len(stops) {
	case 0: return nil
	case 1: return stops[0]
	}
	pos := clamp(t, 0, 1) * f64(len(stops) - 1)
	i := min(int(pos), len(stops) - 2)
	return lerp_rgb(stops[i], stops[i + 1], pos - f64(i))
}

// An Rgb from a 0xRRGGBB literal: hex(0xff8800).
hex :: proc(v: u32) -> Rgb {
	return {u8(v >> 16), u8(v >> 8), u8(v)}
}
