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

Early work. See the roadmap below.

| Phase | Scope | State |
|---|---|---|
| 0 | Scaffold | done |
| 1 | Backend + restore safety | in progress |
| 2 | Buffer + diff renderer | |
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
```

## Building

```sh
./build.sh            # check + test + build examples into bin/
./build.sh check
./build.sh test
./build.sh run empty
```

## License

MIT
