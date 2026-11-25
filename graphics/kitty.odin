package graphics

import "core:encoding/base64"
import "core:fmt"
import "core:strconv"
import "core:strings"

// The kitty graphics protocol, as far as Unicode placeholders need it: an
// image is sent once, given virtual placements, and shown wherever the
// screen has placeholder cells for one (see buffer.Image_Part).
// https://sw.kovidgoyal.net/kitty/graphics-protocol/
//
// Every command has q=2: the terminal answers nothing.

// The most base64 bytes in one command.
@(private)
CHUNK :: 4096

// Sends the pixels of image `id`: `channels` is 3 (RGB) or 4 (RGBA).
append_transmit :: proc(out: ^[dynamic]u8, id: u32, pixels: []u8, width, height, channels: int) {
	CHUNK_BYTES :: CHUNK / 4 * 3
	encoded: [CHUNK]u8
	for start := 0; start == 0 || start < len(pixels); start += CHUNK_BYTES {
		end := min(start + CHUNK_BYTES, len(pixels))
		more := 1 if end < len(pixels) else 0
		if start == 0 {
			fmt.sbprintf((^strings.Builder)(out), "\x1b_Ga=t,q=2,i=%d,f=%d,s=%d,v=%d,m=%d;", id, channels * 8, width, height, more)
		} else {
			fmt.sbprintf((^strings.Builder)(out), "\x1b_Gq=2,m=%d;", more)
		}
		n := encode_base64(encoded[:], pixels[start:end])
		append(out, ..encoded[:n])
		append(out, "\x1b\\")
	}
}

// Gives image `id` a placement of cols × rows cells for placeholders to
// refer to.
append_place :: proc(out: ^[dynamic]u8, id, placement: u32, cols, rows: int) {
	fmt.sbprintf((^strings.Builder)(out), "\x1b_Ga=p,U=1,q=2,i=%d,p=%d,c=%d,r=%d\x1b\\", id, placement, cols, rows)
}

append_unplace :: proc(out: ^[dynamic]u8, id, placement: u32) {
	fmt.sbprintf((^strings.Builder)(out), "\x1b_Ga=d,d=i,q=2,i=%d,p=%d\x1b\\", id, placement)
}

// Deletes image `id`, its placements and its pixels.
append_delete :: proc(out: ^[dynamic]u8, id: u32) {
	fmt.sbprintf((^strings.Builder)(out), "\x1b_Ga=d,d=I,q=2,i=%d\x1b\\", id)
}

// Whether the terminal with this XTVERSION reply ("kitty(0.39.1)") shows
// images in Unicode placeholders. Others that speak the protocol (Konsole,
// WezTerm) don't have those.
supports_placeholders :: proc(xtversion: string) -> bool {
	if strings.has_prefix(xtversion, "ghostty") { return true }
	if !strings.has_prefix(xtversion, "kitty(") { return false }
	v := strings.trim_suffix(xtversion[len("kitty("):], ")")
	major_s, _, rest := strings.partition(v, ".")
	minor_s, _, _ := strings.partition(rest, ".")
	major, _ := strconv.parse_int(major_s, 10)
	minor, _ := strconv.parse_int(minor_s, 10)
	return major > 0 || minor >= 28
}

@(private)
encode_base64 :: proc(dst, src: []u8) -> int {
	n := 0
	for i := 0; i < len(src); i += 3 {
		left := len(src) - i
		v := u32(src[i]) << 16
		if left > 1 { v |= u32(src[i + 1]) << 8 }
		if left > 2 { v |= u32(src[i + 2]) }
		dst[n] = base64.ENC_TABLE[v >> 18 & 63]
		dst[n + 1] = base64.ENC_TABLE[v >> 12 & 63]
		dst[n + 2] = base64.ENC_TABLE[v >> 6 & 63] if left > 1 else '='
		dst[n + 3] = base64.ENC_TABLE[v & 63] if left > 2 else '='
		n += 4
	}
	return n
}
