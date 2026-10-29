# hnoss

> Named after Hnoss, daughter of Freyja. Her name means "treasure, precious beauty".

**hnoss** is an immediate-mode, widget-rich TUI library for [Odin](https://odin-lang.org),
inspired by [Ratatui](https://ratatui.rs).

## Goals

- **Pure Odin.** Only `core:` and `base:`. No ncurses, no termbox, no C.
- **Immediate mode.** Every frame you describe the whole UI; hnoss diffs it against
  the previous frame and writes the minimal ANSI to the terminal.
- **Ratatui-level ergonomics**: constraint layouts, styled text, and a real widget set
  (Block, Paragraph, List, Table, Gauge, Sparkline, Tabs, Scrollbar, TextInput).
- **Explicit allocators.** Per-frame scratch lives in `context.temp_allocator`.
- **No hidden global state**, apart from one terminal-restore hook.
- **The terminal is always restored** (raw mode, cursor, alt screen), even on panic or signal.
- Linux first; the platform code sits behind a small backend so macOS/Windows can follow.

## Status

Early work. See the roadmap below. What exists today:

```odin
term, err := hnoss.init()
defer hnoss.deinit(&term)
for running {
    f := hnoss.begin_frame(&term)          // picks up resizes
    buffer.set_string(f.buffer, 2, 1, "hello", {fg = style.Named_Color.Cyan, add = {.Bold}})
    hnoss.end_frame(&term)                 // diff vs last frame, one write
}
```

Rendering is double-buffered: each frame is diffed against the previous one and only
changed cells are written, with cursor moves and SGR codes emitted only when needed,
inside a synchronized-output block so the terminal never shows a torn frame.
A 200x60 frame where every cell changes color diffs in ~2 ms; an unchanged frame in ~0.07 ms.

| Phase | Scope | State |
|---|---|---|
| 0 | Scaffold | done |
| 1 | Backend + restore safety | done |
| 2 | Buffer + diff renderer | done |
| 3 | Input parser | |
| 4 | Style, text, unicode width | |
| 5 | Layout | |
| 6 | Widgets | |
| 7 | Demo app (system monitor) | |

## Layout

```
backend/   terminal I/O: raw mode, alt screen, size, write, input bytes
input/     byte stream -> Event (Key, Mouse, Resize, Paste)
buffer/    Cell, Buffer, double-buffer diff -> minimal ANSI
style/     Color, Modifier, Style
layout/    Rect, constraint solver, split
text/      Span, Line, Text, unicode width
widgets/   Block, Paragraph, List, Table, ...
examples/  one runnable example per feature
tests/     `odin test` suites
bench/     render pipeline benchmark
```

## Building

```sh
./build.sh            # check + test + build examples into bin/
./build.sh check
./build.sh test
./build.sh run plasma        # full-screen truecolor animation at 60 fps
./build.sh run backend_box   # q / Ctrl+C quits, p panics (terminal still comes back clean)
./build.sh bench             # time fill + diff for a 200x60 frame
```

## License

MIT
