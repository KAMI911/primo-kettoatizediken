"""Turn the raw 8 KB video dump ($E000-$FFFF) from the RENDER_TEST build into a PNG.
usage: render.py mono|color dump.bin out.png   (stdlib only)"""
import sys, zlib, struct

def png(path, w, h, rows):
    raw = b"".join(b"\0" + bytes(r) for r in rows)
    def chunk(t, d): return struct.pack(">I", len(d)) + t + d + struct.pack(">I", zlib.crc32(t + d))
    open(path, "wb").write(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))
                           + chunk(b"IDAT", zlib.compress(raw)) + chunk(b"IEND", b""))

def main(mode, src, out):
    d = open(src, "rb").read()
    if len(d) != 0x2000: sys.exit("dump is %d bytes, expected 8192" % len(d))
    if mode == "mono":
        base, lines = 0x800, 192
        px = lambda x, y: (d[base + y * 32 + x // 8] >> (7 - x % 8)) & 1
        col = lambda x, y, p: (255, 255, 255) if p else (0, 0, 0)
    else:
        base, lines = 0x700, 200
        pal = [(~d[0x20 + i]) & 0xFF for i in range(32)]            # stored inverted, RRRGGGBB
        def rgb(c): return ((c >> 5) * 255 // 7, ((c >> 2) & 7) * 255 // 7, (c & 3) * 255 // 3)
        def nib(x, y):
            b = d[0x80 + (y // 4) * 32 + x // 8]
            return (b >> 4) if (x // 4) % 2 == 0 else (b & 15)
        px = lambda x, y: (d[base + y * 32 + x // 8] >> (7 - x % 8)) & 1
        col = lambda x, y, p: rgb(pal[(p << 4) | nib(x, y)])
    S = 3
    rows = []
    for y in range(lines):
        line = []
        for x in range(256):
            line += list(col(x, y, px(x, y))) * S
        rows += [line] * S
    png(out, 256 * S, lines * S, rows)

if __name__ == "__main__": main(*sys.argv[1:4])
