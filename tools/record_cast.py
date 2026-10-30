#!/usr/bin/env python3
"""Runs a program in a pseudo-terminal for a while and saves its output as an
asciicast v2 recording, which agg turns into a GIF. docs/demo.gif is made with:

    ./build.sh examples
    python3 tools/record_cast.py bin/demo demo.cast 132 38 18.1
    agg --font-family "JetBrainsMono Nerd Font Mono,DejaVu Sans Mono,Noto Sans CJK JP" \
        --font-size 12 --line-height 1.2 --fps-cap 20 --idle-time-limit 1 --last-frame-duration 0 demo.cast docs/demo.gif
"""
import codecs, fcntl, json, os, pty, select, struct, sys, termios, time
prog, out, cols, rows, secs = sys.argv[1], sys.argv[2], int(sys.argv[3]), int(sys.argv[4]), float(sys.argv[5])
pid, fd = pty.fork()
if pid == 0:
    os.environ["TERM"] = "xterm-256color"; os.environ["COLORTERM"] = "truecolor"
    os.execv(prog, [prog])
fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack("HHHH", rows, cols, 0, 0))
start = time.time(); evs = []; dec = codecs.getincrementaldecoder("utf-8")("replace")
while time.time() - start < secs:
    r, _, _ = select.select([fd], [], [], 0.05)
    if r:
        try: data = os.read(fd, 1 << 16)
        except OSError: break
        evs.append([round(time.time() - start, 4), "o", dec.decode(data)])
os.write(fd, b"q")
end = time.time() + 3  # keep draining so the program is never blocked writing
while time.time() < end:
    r, _, _ = select.select([fd], [], [], 0.05)
    if r:
        try: os.read(fd, 1 << 16)
        except OSError: break
    if os.waitpid(pid, os.WNOHANG)[0]: break
else:
    os.kill(pid, 9); os.waitpid(pid, 0)
with open(out, "w") as f:
    f.write(json.dumps({"version": 2, "width": cols, "height": rows, "env": {"TERM": "xterm-256color"}}) + "\n")
    for e in evs: f.write(json.dumps(e, ensure_ascii=False) + "\n")
print(len(evs), "chunks")
