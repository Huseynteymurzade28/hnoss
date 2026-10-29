package main

import hnoss "../.."

// A monitor theme: the widget theme plus the gradients the charts use.
// Gradients run from "calm" (low values, bottom of a graph) to "hot".
Palette :: struct {
	name:  string,
	ui:    hnoss.Theme,
	bg:    hnoss.Color, // whole-screen background (nil: terminal default)
	text:  hnoss.Rgb,
	dim:   hnoss.Rgb,
	track: hnoss.Rgb, // empty part of meters
	logo:  []hnoss.Rgb,
	cpu:   []hnoss.Rgb,
	mem:   []hnoss.Rgb,
	rx:    []hnoss.Rgb,
	tx:    []hnoss.Rgb,
}

palettes :: proc() -> [4]Palette {
	return {
		make_palette("Odlar Yurdu", 0x140906, 0xf6e3d4, 0x9a6a55, 0x3a1d14, 0x6b3020, 0xff8c42,
			ODLAR_LOGO[:], ODLAR_CPU[:], ODLAR_MEM[:], ODLAR_RX[:], ODLAR_TX[:]),
		make_palette("Xəzər", 0x06141f, 0xdff3fb, 0x5f8aa0, 0x12303f, 0x1f5168, 0x4cc9f0,
			XEZER_LOGO[:], XEZER_CPU[:], XEZER_MEM[:], XEZER_RX[:], XEZER_TX[:]),
		make_palette("Aurora", 0x0c0f16, 0xe6e9ef, 0x6c7486, 0x1c2230, 0x2e3546, 0xa6e3a1,
			AURORA_LOGO[:], AURORA_CPU[:], AURORA_MEM[:], AURORA_RX[:], AURORA_TX[:]),
		make_palette("Mono", 0, 0xdddddd, 0x808080, 0x303030, 0x505050, 0xffffff,
			MONO_LOGO[:], MONO_CPU[:], MONO_CPU[:], MONO_CPU[:], MONO_CPU[:]),
	}
}

@(private = "file")
make_palette :: proc(name: string, bg, text, dim, track, frame, accent: u32, logo, cpu, mem, rx, tx: []hnoss.Rgb) -> Palette {
	A, T, D, F := hnoss.hex(accent), hnoss.hex(text), hnoss.hex(dim), hnoss.hex(frame)
	B: hnoss.Color = hnoss.hex(bg) if bg != 0 else nil
	ui := hnoss.DEFAULT_THEME
	ui.text = {fg = T}
	ui.muted = {fg = D}
	ui.accent = {fg = A}
	ui.border = {fg = F}
	ui.border_focused = {fg = A}
	ui.title = {fg = T, add = {.Bold}}
	ui.selected = {fg = B if B != nil else hnoss.Color(hnoss.hex(0x000000)), bg = A, add = {.Bold}}
	ui.selected_unfocused = {bg = F}
	ui.header = {fg = A, add = {.Bold}}
	ui.tab = {fg = D}
	ui.tab_selected = {fg = A, add = {.Bold}}
	ui.input = {fg = T}
	ui.scrollbar_track = {fg = F}
	ui.scrollbar_thumb = {fg = A}
	return {name = name, ui = ui, bg = B, text = T, dim = D, track = hnoss.hex(track),
		logo = logo, cpu = cpu, mem = mem, rx = rx, tx = tx}
}

// "Odlar Yurdu", the Land of Fire: embers to flame.
@(private = "file", rodata) ODLAR_LOGO := [?]hnoss.Rgb{{255, 209, 102}, {255, 140, 66}, {230, 57, 70}}
@(private = "file", rodata) ODLAR_CPU  := [?]hnoss.Rgb{{255, 209, 102}, {255, 140, 66}, {230, 57, 70}, {157, 2, 8}}
@(private = "file", rodata) ODLAR_MEM  := [?]hnoss.Rgb{{244, 162, 97}, {231, 111, 81}, {200, 50, 60}}
@(private = "file", rodata) ODLAR_RX   := [?]hnoss.Rgb{{255, 186, 8}, {244, 140, 6}}
@(private = "file", rodata) ODLAR_TX   := [?]hnoss.Rgb{{220, 47, 2}, {157, 2, 8}}

// "Xəzər", the Caspian: shallow teal to deep blue.
@(private = "file", rodata) XEZER_LOGO := [?]hnoss.Rgb{{128, 255, 219}, {76, 201, 240}, {67, 97, 238}}
@(private = "file", rodata) XEZER_CPU  := [?]hnoss.Rgb{{46, 196, 182}, {76, 201, 240}, {67, 97, 238}, {114, 9, 183}}
@(private = "file", rodata) XEZER_MEM  := [?]hnoss.Rgb{{128, 255, 219}, {72, 191, 227}, {83, 144, 217}}
@(private = "file", rodata) XEZER_RX   := [?]hnoss.Rgb{{100, 223, 223}, {83, 144, 217}}
@(private = "file", rodata) XEZER_TX   := [?]hnoss.Rgb{{116, 0, 184}, {105, 48, 195}}

@(private = "file", rodata) AURORA_LOGO := [?]hnoss.Rgb{{166, 227, 161}, {137, 220, 235}, {203, 166, 247}}
@(private = "file", rodata) AURORA_CPU  := [?]hnoss.Rgb{{80, 250, 123}, {241, 250, 140}, {255, 184, 108}, {255, 85, 85}}
@(private = "file", rodata) AURORA_MEM  := [?]hnoss.Rgb{{139, 233, 253}, {189, 147, 249}}
@(private = "file", rodata) AURORA_RX   := [?]hnoss.Rgb{{80, 250, 123}, {139, 233, 253}}
@(private = "file", rodata) AURORA_TX   := [?]hnoss.Rgb{{255, 121, 198}, {189, 147, 249}}

@(private = "file", rodata) MONO_LOGO := [?]hnoss.Rgb{{255, 255, 255}, {150, 150, 150}}
@(private = "file", rodata) MONO_CPU  := [?]hnoss.Rgb{{110, 110, 110}, {255, 255, 255}}
