// Phase 4 example: the pen and markup. Resize the terminal to watch the
// text reflow.
//   w      cycle wrap mode     a  cycle alignment
//   ↑ / ↓  scroll the article  q  quit
package main

import "core:fmt"
import "core:os"
import hnoss "../.."
import "../../backend"

ARTICLE :: `Terminals are grids of cells. Every glyph takes one cell, except the wide ones: 世界 takes four, a family 👨‍👩‍👧‍👦 takes two, a flag 🇹🇷 takes two, and é built from e plus a combining accent takes one.

hnoss measures text in grapheme clusters, so wrapping never splits a character in half and alignment is computed from what you actually see, not from bytes.

A word that is longer than the whole line, like Pneumonoultramicroscopicsilicovolcanoconiosis, still breaks — just in the middle, because there is nowhere else to break it.`

main :: proc() {
	context.assertion_failure_proc = backend.assertion_failure_proc

	term, err := hnoss.init()
	if err != .None {
		fmt.eprintfln("hnoss: init failed: %v", err)
		os.exit(1)
	}
	defer hnoss.deinit(&term)

	wrap := hnoss.Wrap.Word
	align := hnoss.Align.Left
	scroll := 0

	loop: for {
		f := hnoss.begin_frame(&term)
		draw(f, wrap, align, &scroll)
		hnoss.end_frame(&term)
		free_all(context.temp_allocator)

		for ev in hnoss.poll_events(&term, -1) {
			switch {
			case hnoss.is_char(ev, 'q'), hnoss.is_char(ev, 'c', {.Ctrl}):
				break loop
			case hnoss.is_char(ev, 'w'):
				wrap = hnoss.Wrap((int(wrap) + 1) % len(hnoss.Wrap))
			case hnoss.is_char(ev, 'a'):
				align = hnoss.Align((int(align) + 1) % len(hnoss.Align))
			case hnoss.is_key(ev, .Down):
				scroll += 1
			case hnoss.is_key(ev, .Up):
				scroll = max(scroll - 1, 0)
			}
		}
		if term.error != .None {
			break
		}
	}
}

draw :: proc(f: ^hnoss.Frame, wrap: hnoss.Wrap, align: hnoss.Align, scroll: ^int) {
	a := f.area
	if a.width < 20 || a.height < 8 {
		hnoss.markup(f, a, "[b red]terminal too small[/]", wrap = .Clip)
		return
	}

	// Title bar, centered.
	bar := hnoss.Rect{a.x, a.y, a.width, 1}
	hnoss.markup(f, bar, "[b black on cyan] hnoss · pen & markup [/]", align = .Center)

	// Status line at the bottom.
	status := hnoss.Rect{a.x, a.y + a.height - 1, a.width, 1}
	hnoss.markup(f, status, fmt.tprintf(
		"[dim]wrap[/] [b]%v[/]  [dim]align[/] [b]%v[/]  [dim]scroll[/] [b]%d[/]   [dim]w a ↑↓ q[/]",
		wrap, align, scroll^), wrap = .Ellipsis)

	// Left: the article, through a pen with the chosen wrap/align/scroll.
	body := hnoss.Rect{a.x + 2, a.y + 2, a.width * 3 / 5 - 3, a.height - 4}
	lines, _ := hnoss.measure(ARTICLE, body.width, wrap)
	scroll^ = min(scroll^, max(lines - body.height, 0))
	p := hnoss.pen(f, body, wrap, align, scroll = scroll^)
	hnoss.write(&p, ARTICLE)
	hnoss.finish(&p)

	// Right: a markup showcase, always word-wrapped.
	side := hnoss.Rect{body.x + body.width + 3, body.y, a.width - body.width - 7, body.height}
	if side.width < 10 {
		return
	}
	hnoss.markup(f, side, `[b u]Markup[/]

[b]bold[/] [d]dim[/] [i]italic[/] [u]underline[/] [r]reverse[/] [s]strike[/]

[red]red[/] [green]green[/] [yellow]yellow[/] [blue]blue[/] [magenta]magenta[/] [cyan]cyan[/]
[bright_red]bright[/] [@208]@208[/] [#ff66cc]#ff66cc[/]

[black on yellow] WARN [/] disk at [b]91%[/]
[white on red] FAIL [/] [i]build #42[/]
[black on green]  OK  [/] tests [b green]45/45[/]

[dim]Brackets that aren't tags stay as text: [1/3] [x][/]`)
}
