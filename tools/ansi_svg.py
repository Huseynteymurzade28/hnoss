#!/usr/bin/env python3
"""Runs an hnoss program in a pseudo-terminal and saves what it draws as an
SVG "screenshot" with exact colors and a fixed cell grid.

    python3 tools/ansi_svg.py bin/monitor out.svg --cols 140 --rows 40 --wait 30 [--keys t]

Understands the subset of ANSI that hnoss emits: cursor moves, clear,
SGR (bold, dim, italic, underline, reverse, 16/256/truecolor).
"""
import codecs, argparse, fcntl, html, os, pty, re, select, struct, termios, time, unicodedata

CELL_W, CELL_H, FONT = 9.0, 19.0, 15
DEFAULT_FG, DEFAULT_BG = (0xd8, 0xd8, 0xd8), (0x10, 0x10, 0x14)
BASE16 = [(0x1d, 0x1f, 0x21), (0xcc, 0x66, 0x66), (0xb5, 0xbd, 0x68), (0xf0, 0xc6, 0x74),
          (0x81, 0xa2, 0xbe), (0xb2, 0x94, 0xbb), (0x8a, 0xbe, 0xb7), (0xc5, 0xc8, 0xc6),
          (0x66, 0x66, 0x66), (0xd5, 0x4e, 0x53), (0xb9, 0xca, 0x4a), (0xe7, 0xc5, 0x47),
          (0x7a, 0xa6, 0xda), (0xc3, 0x97, 0xd8), (0x70, 0xc0, 0xb1), (0xea, 0xea, 0xea)]

def indexed(n):
    if n < 16: return BASE16[n]
    if n < 232:
        n -= 16; lv = [0, 95, 135, 175, 215, 255]
        return (lv[n // 36], lv[(n // 6) % 6], lv[n % 6])
    v = 8 + (n - 232) * 10
    return (v, v, v)

class Pen:
    def __init__(s): s.reset()
    def reset(s): s.fg = None; s.bg = None; s.bold = s.dim = s.italic = s.under = s.rev = False
    def copy(s):
        p = Pen(); p.__dict__.update(s.__dict__); return p

def sgr(pen, params):
    ps = [int(x) if x else 0 for x in params.split(";")] if params else [0]
    i = 0
    while i < len(ps):
        p = ps[i]
        if p == 0: pen.reset()
        elif p == 1: pen.bold = True
        elif p == 2: pen.dim = True
        elif p == 3: pen.italic = True
        elif p == 4: pen.under = True
        elif p == 7: pen.rev = True
        elif p == 22: pen.bold = pen.dim = False
        elif p == 23: pen.italic = False
        elif p == 24: pen.under = False
        elif p == 27: pen.rev = False
        elif 30 <= p <= 37: pen.fg = BASE16[p - 30]
        elif 90 <= p <= 97: pen.fg = BASE16[p - 90 + 8]
        elif p == 39: pen.fg = None
        elif 40 <= p <= 47: pen.bg = BASE16[p - 40]
        elif 100 <= p <= 107: pen.bg = BASE16[p - 100 + 8]
        elif p == 49: pen.bg = None
        elif p in (38, 48) and i + 1 < len(ps):
            if ps[i + 1] == 5 and i + 2 < len(ps):
                c = indexed(ps[i + 2]); i += 2
            elif ps[i + 1] == 2 and i + 4 < len(ps):
                c = tuple(ps[i + 2:i + 5]); i += 4
            else:
                c = None
            if p == 38: pen.fg = c
            else: pen.bg = c
        i += 1

def joins(ch):
    o = ord(ch)
    return unicodedata.category(ch) in ("Mn", "Me", "Cf") or 0x1f3fb <= o <= 0x1f3ff

class Screen:
    def __init__(s, rows, cols):
        s.rows, s.cols = rows, cols
        s.cells = [[(" ", Pen(), 1) for _ in range(cols)] for _ in range(rows)]
        s.x = s.y = 0; s.pen = Pen()
    def feed(s, data):
        if not hasattr(s, "dec"): s.dec = codecs.getincrementaldecoder("utf-8")("replace"); s.tail = ""
        t = s.tail + s.dec.decode(data); s.tail = ""
        cut = t.rfind("\x1b")
        if cut >= 0 and not re.match(r"\x1b\[[?<]?[0-9;]*[@-~]", t[cut:]) and len(t) - cut < 32:
            t, s.tail = t[:cut], t[cut:]  # an escape sequence split across reads
        i = 0
        while i < len(t):
            ch = t[i]
            if ch == "\x1b" and i + 1 < len(t) and t[i + 1] == "[":
                m = re.match(r"\x1b\[([?<]?)([0-9;]*)([@-~])", t[i:])
                if not m: i += 1; continue
                priv, args, f = m.groups(); i += m.end()
                if priv: continue
                if f == "H":
                    a = (args.split(";") + ["1", "1"])[:2]
                    s.y, s.x = int(a[0] or 1) - 1, int(a[1] or 1) - 1
                elif f == "J" and args == "2":
                    s.cells = [[(" ", s.pen.copy(), 1) for _ in range(s.cols)] for _ in range(s.rows)]
                elif f == "m":
                    sgr(s.pen, args)
                continue
            if ch in "\x18\x1b": i += 1; continue
            prev_g = s.cells[s.y][s.x - 1][0] if 0 <= s.y < s.rows and 0 < s.x <= s.cols else ""
            if 0 < s.x <= s.cols and s.cells[s.y][s.x - 1][2] == 0 and s.x >= 2:
                prev_g = s.cells[s.y][s.x - 2][0]  # we are right after a wide glyph's second cell
            if prev_g.endswith("\u200d"):
                # ZWJ sequence: this emoji is part of the previous glyph
                px = s.x - 2 if s.cells[s.y][s.x - 1][2] == 0 else s.x - 1
                g, p, w = s.cells[s.y][px]; s.cells[s.y][px] = (g + ch, p, w)
                i += 1; continue
            if joins(ch) or (0x1f1e6 <= ord(ch) <= 0x1f1ff and s.x >= 2 and 0 <= s.y < s.rows
                             and len(s.cells[s.y][s.x - 2][0]) == 1 and 0x1f1e6 <= ord(s.cells[s.y][s.x - 2][0]) <= 0x1f1ff):
                # combining mark / second flag letter: append to the previous glyph
                px = s.x - 2 if 0x1f1e6 <= ord(ch) <= 0x1f1ff else s.x - 1
                if not (0x1f1e6 <= ord(ch) <= 0x1f1ff) and px >= 1 and s.cells[s.y][px][2] == 0:
                    px -= 1  # mark after a wide glyph belongs to the glyph itself
                if 0 <= s.y < s.rows and 0 <= px < s.cols:
                    g, p, w = s.cells[s.y][px]; s.cells[s.y][px] = (g + ch, p, w)
                i += 1; continue
            w = 2 if unicodedata.east_asian_width(ch) in "WF" or 0x1f1e6 <= ord(ch) <= 0x1f1ff else 1
            if 0 <= s.y < s.rows and 0 <= s.x < s.cols:
                s.cells[s.y][s.x] = (ch, s.pen.copy(), w)
                if w == 2 and s.x + 1 < s.cols: s.cells[s.y][s.x + 1] = ("", s.pen.copy(), 0)
            s.x += w; i += 1

def colors(p):
    fg, bg = p.fg or DEFAULT_FG, p.bg or DEFAULT_BG
    if p.rev: fg, bg = bg, fg
    if p.dim: fg = tuple(int(c * 0.6 + b * 0.4) for c, b in zip(fg, bg))
    return fg, bg

def hexc(c): return "#%02x%02x%02x" % c

# Braille dots and block elements are drawn as shapes: fonts render them
# inconsistently (thin, gappy, misaligned), shapes are crisp everywhere.
BRAILLE_BITS = [(0, 0, 0x01), (0, 1, 0x02), (0, 2, 0x04), (1, 0, 0x08),
                (1, 1, 0x10), (1, 2, 0x20), (0, 3, 0x40), (1, 3, 0x80)]
EIGHTHS = "▏▎▍▌▋▊▉█"

def flag(code, x0, y0):
    """Small vector flags for regional-indicator pairs (fonts rarely have them)."""
    w, h = CELL_W * 2 - 2, CELL_H * 0.62
    x, y = x0 + 1, y0 + (CELL_H - h) / 2
    def stripes(cols, horizontal=True):
        n = len(cols); parts = []
        for i, c in enumerate(cols):
            if horizontal:
                parts.append(f'<rect x="{x:.1f}" y="{y + i * h / n:.1f}" width="{w:.1f}" height="{h / n + 0.2:.1f}" fill="{c}"/>')
            else:
                parts.append(f'<rect x="{x + i * w / n:.1f}" y="{y:.1f}" width="{w / n + 0.2:.1f}" height="{h:.1f}" fill="{c}"/>')
        return "".join(parts)
    def crescent(cx, cy, r, bg):
        return (f'<circle cx="{cx:.1f}" cy="{cy:.1f}" r="{r:.2f}" fill="#fff"/>'
                f'<circle cx="{cx + r * 0.28:.1f}" cy="{cy:.1f}" r="{r * 0.8:.2f}" fill="{bg}"/>'
                f'<circle cx="{cx + r * 1.05:.1f}" cy="{cy:.1f}" r="{r * 0.32:.2f}" fill="#fff"/>')
    body = {
        "AZ": lambda: stripes(["#00b5e2", "#ef3340", "#509e2f"]) + crescent(x + w * 0.45, y + h / 2, h * 0.17, "#ef3340"),
        "TR": lambda: stripes(["#e30a17"]) + crescent(x + w * 0.38, y + h / 2, h * 0.3, "#e30a17"),
        "DE": lambda: stripes(["#000000", "#dd0000", "#ffce00"]),
        "JP": lambda: stripes(["#ffffff"]) + f'<circle cx="{x + w / 2:.1f}" cy="{y + h / 2:.1f}" r="{h * 0.3:.2f}" fill="#bc002d"/>',
        "US": lambda: stripes(["#b22234", "#ffffff"] * 3 + ["#b22234"]) + f'<rect x="{x:.1f}" y="{y:.1f}" width="{w * 0.42:.1f}" height="{h * 4 / 7:.1f}" fill="#3c3b6e"/>',
        "BR": lambda: stripes(["#009c3b"]) + f'<polygon points="{x + w / 2:.1f},{y + 1:.1f} {x + w - 1.5:.1f},{y + h / 2:.1f} {x + w / 2:.1f},{y + h - 1:.1f} {x + 1.5:.1f},{y + h / 2:.1f}" fill="#ffdf00"/><circle cx="{x + w / 2:.1f}" cy="{y + h / 2:.1f}" r="{h * 0.24:.2f}" fill="#002776"/>',
        "FR": lambda: stripes(["#0055a4", "#ffffff", "#ef4135"], horizontal=False),
        "GB": lambda: stripes(["#012169"]) + f'<path d="M{x:.1f} {y:.1f}L{x + w:.1f} {y + h:.1f}M{x + w:.1f} {y:.1f}L{x:.1f} {y + h:.1f}" stroke="#fff" stroke-width="2"/><path d="M{x + w / 2:.1f} {y:.1f}V{y + h:.1f}M{x:.1f} {y + h / 2:.1f}H{x + w:.1f}" stroke="#c8102e" stroke-width="2.4"/>',
    }.get(code)
    if body is None: return None
    return f'<g>{body()}<rect x="{x:.1f}" y="{y:.1f}" width="{w:.1f}" height="{h:.1f}" fill="none" stroke="#00000055" stroke-width="0.6"/></g>'

def shapes(g, x0, y0, color):
    if len(g) == 2 and all(0x1f1e6 <= ord(c) <= 0x1f1ff for c in g):
        return flag("".join(chr(ord(c) - 0x1f1e6 + ord("A")) for c in g), x0, y0)
    if len(g) != 1: return None
    o = ord(g)
    if 0x2800 < o <= 0x28ff:
        bits, r = o - 0x2800, min(CELL_W / 4, CELL_H / 8) * 0.78
        dots = [f'<circle cx="{x0 + (c + 0.5) * CELL_W / 2:.1f}" cy="{y0 + (rw + 0.5) * CELL_H / 4:.1f}" r="{r:.2f}"/>'
                for c, rw, b in BRAILLE_BITS if bits & b]
        return f'<g fill="{color}">' + "".join(dots) + "</g>"
    if g in EIGHTHS:
        w = CELL_W * (EIGHTHS.index(g) + 1) / 8 + (0.6 if g == "█" else 0)
        return f'<rect x="{x0:.1f}" y="{y0:.1f}" width="{w:.1f}" height="{CELL_H + 0.6:.1f}" fill="{color}"/>'
    if g == "▀":
        return f'<rect x="{x0:.1f}" y="{y0:.1f}" width="{CELL_W + 0.6:.1f}" height="{CELL_H / 2 + 0.3:.1f}" fill="{color}"/>'
    if g in "▁▂▃▅▆▇":
        k = "▁▂▃▄▅▆▇".index(g) + 1
        hh = CELL_H * k / 8
        return f'<rect x="{x0:.1f}" y="{y0 + CELL_H - hh:.1f}" width="{CELL_W + 0.6:.1f}" height="{hh + 0.6:.1f}" fill="{color}"/>'
    if g == "▄":
        return f'<rect x="{x0:.1f}" y="{y0 + CELL_H / 2:.1f}" width="{CELL_W + 0.6:.1f}" height="{CELL_H / 2 + 0.6:.1f}" fill="{color}"/>'
    return None

def to_svg(scr):
    W, H = scr.cols * CELL_W, scr.rows * CELL_H
    out = [f'<svg xmlns="http://www.w3.org/2000/svg" width="{W:.0f}" height="{H:.0f}" viewBox="0 0 {W:.0f} {H:.0f}">',
           f'<rect width="100%" height="100%" fill="{hexc(DEFAULT_BG)}"/>',
           f'<g font-family="JetBrains Mono, DejaVu Sans Mono, Menlo, Consolas, monospace" font-size="{FONT}">']
    for y, row in enumerate(scr.cells):
        x = 0
        while x < scr.cols:  # background runs
            _, p, _ = row[x]; bg = colors(p)[1]; start = x
            while x < scr.cols and colors(row[x][1])[1] == bg: x += 1
            if bg != DEFAULT_BG:
                out.append(f'<rect x="{start * CELL_W:.1f}" y="{y * CELL_H:.1f}" width="{(x - start) * CELL_W + 0.6:.1f}" height="{CELL_H + 0.6:.1f}" fill="{hexc(bg)}"/>')
        for x, (g, p, w) in enumerate(row):  # glyphs, one positioned text per cell
            if g.strip() == "": continue
            fg = colors(p)[0]
            shape = shapes(g, x * CELL_W, y * CELL_H, hexc(fg))
            if shape is not None:
                out.append(shape); continue
            attrs = f'fill="{hexc(fg)}"'
            if p.bold: attrs += ' font-weight="bold"'
            if p.italic: attrs += ' font-style="italic"'
            if p.under: attrs += ' text-decoration="underline"'
            if w == 2 or g[0] in "█▀▄▌▐▏▎▍▋▊▉" or 0x2800 <= ord(g[0]) <= 0x28ff or g[0] in "─│╭╮╰╯┃━":
                attrs += f' textLength="{CELL_W * max(w, 1):.1f}" lengthAdjust="spacingAndGlyphs"'
            out.append(f'<text x="{x * CELL_W:.1f}" y="{y * CELL_H + CELL_H * 0.78:.1f}" {attrs}>{html.escape(g)}</text>')
    out.append("</g></svg>")
    return "\n".join(out)

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("binary"); ap.add_argument("out")
    ap.add_argument("--cols", type=int, default=140); ap.add_argument("--rows", type=int, default=40)
    ap.add_argument("--wait", type=float, default=3.0, help="seconds to let it run before capturing")
    ap.add_argument("--keys", default="", help="bytes to send just before capturing")
    a = ap.parse_args()
    pid, fd = pty.fork()
    if pid == 0:
        os.environ["COLORTERM"] = "truecolor"; os.execv(a.binary, [a.binary])
    fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack("HHHH", a.rows, a.cols, 0, 0))
    scr = Screen(a.rows, a.cols)
    def pump(dur):
        end = time.time() + dur
        while time.time() < end:
            r, _, _ = select.select([fd], [], [], 0.05)
            if r:
                try: scr.feed(os.read(fd, 1 << 20))
                except OSError: return
    pump(a.wait)
    if a.keys:
        # --keys accepts escapes: "jj\\r", "\\x1b[A"; each "|" is a pause between bursts
        for burst in a.keys.split("|"):
            os.write(fd, burst.encode("utf-8").decode("unicode_escape").encode("latin-1")); pump(0.4)
    with open(a.out, "w") as f: f.write(to_svg(scr))
    # Quit: q, then Ctrl+C (some programs take q as input), then SIGTERM.
    import signal
    for key in (b"q", b"\x03", None):
        if key: os.write(fd, key)
        else: os.kill(pid, signal.SIGTERM)
        pump(0.5)
        done, _ = os.waitpid(pid, os.WNOHANG)
        if done: break
    print(f"wrote {a.out}")

if __name__ == "__main__":
    main()
