"""Drive an hnoss program in a pseudo-terminal and read back its screen.

A minimal screen model that understands what hnoss emits (cursor moves,
clear, SGR, UTF-8 text with wide chars); enough to check layout and text,
not colors.

    import sys; sys.path.insert(0, "tools")
    from pty_screen import App
    app = App("bin/w_list", rows=14, cols=64)
    app.send(b"jj\r")          # keys, raw bytes
    app.show("after jj Enter")
    app.quit()                  # sends q, checks exit code and termios
"""
import codecs, os, pty, sys, time, termios, struct, fcntl, select, re, unicodedata
class Screen:
    def __init__(s,r,c): s.resize(r,c)
    def resize(s,r,c): s.r,s.c=r,c; s.g=[[" "]*c for _ in range(r)]; s.x=s.y=0
    def feed(s,data):
        if not hasattr(s, "dec"): s.dec = codecs.getincrementaldecoder("utf-8")("replace"); s.tail = ""
        t = s.tail + s.dec.decode(data); s.tail = ""
        cut = t.rfind("\x1b")
        if cut >= 0 and not re.match(r"\x1b\[[?<]?[0-9;]*[@-~]", t[cut:]) and len(t) - cut < 32:
            t, s.tail = t[:cut], t[cut:]  # an escape sequence split across reads
        i = 0
        while i<len(t):
            ch=t[i]
            if ch=="\x1b" and i+1<len(t) and t[i+1]=="[":
                m=re.match(r"\x1b\[([?<]?)([0-9;]*)([@-~])",t[i:])
                if not m: i+=1; continue
                p,args,f=m.groups(); i+=m.end()
                if f=="H" and not p:
                    a=(args.split(";")+["1","1"])[:2]; s.y=int(a[0] or 1)-1; s.x=int(a[1] or 1)-1
                elif f=="J" and args=="2": s.g=[[" "]*s.c for _ in range(s.r)]
                continue
            if ch in "\x18\x1b": i+=1; continue
            if unicodedata.category(ch) in ("Mn","Me","Cf") or 0x1f3fb<=ord(ch)<=0x1f3ff or (0x1f1e6<=ord(ch)<=0x1f1ff and s.x>0 and 0x1f1e6<=ord(s.g[s.y][s.x-2][-1:] or 'a')<=0x1f1ff and len(s.g[s.y][s.x-2])==1):
                if s.x>0 and 0<=s.y<s.r: s.g[s.y][max(s.x-1,0)] += ch
                i+=1; continue
            w=2 if unicodedata.east_asian_width(ch) in "WF" or 0x1f1e6<=ord(ch)<=0x1f1ff else 1
            if 0<=s.y<s.r and 0<=s.x<s.c:
                s.g[s.y][s.x]=ch
                if w==2 and s.x+1<s.c: s.g[s.y][s.x+1]=""
            s.x+=w; i+=1
    def text(s): return "\n".join("".join(r).rstrip() for r in s.g)
class App:
    def __init__(a,binary,rows=20,cols=70):
        a.pid,a.fd=pty.fork()
        if a.pid==0: os.execv(binary,[binary])
        a.scr=Screen(rows,cols); fcntl.ioctl(a.fd, termios.TIOCSWINSZ, struct.pack("HHHH", rows, cols, 0, 0)); a.drain(0.5)
    def drain(a,dur=0.25):
        out=[]; end=time.time()+dur
        while time.time()<end:
            r,_,_=select.select([a.fd],[],[],0.02)
            if r:
                try: out.append(os.read(a.fd,1<<20))
                except OSError: break
        o=b"".join(out); a.scr.feed(o); return o
    def send(a,b,dur=0.25): os.write(a.fd,b); return a.drain(dur)
    def show(a,title): print(f"--- {title} ---\n"+a.scr.text())
    def quit(a,key=b"q"):
        os.write(a.fd,key); a.drain(0.4)
        _,st=os.waitpid(a.pid,0)
        ok=bool(termios.tcgetattr(a.fd)[3]&termios.ICANON)
        print(f"exit={os.WEXITSTATUS(st) if os.WIFEXITED(st) else 'signal'} restored={ok}")
