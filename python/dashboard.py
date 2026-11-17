"""
Reference model of dashboard.v (Pierce): renders the 320x240 frame the VGA
adapter should hold for a given book and our quotes, and reads/writes frames.

Colours are the adapter's 3-bit {R, G, B} codes.
"""
import struct
import zlib
from msgfmt import N_LEVELS, BID, ASK

WIDTH, HEIGHT = 320, 240
ROW_H = 3                       # rows per level; the last one is a black gap
CENTRE = 160
QTY_SHIFT = 5
BAR_MAX = 159
MARK_W = 8
BID_MARK_X, ASK_MARK_X = 8, 304
BLACK, GREEN, RED, YELLOW = 0b000, 0b010, 0b100, 0b110


def bar_len(qty):
    if qty == 0:
        return 0
    return max(1, min(qty >> QTY_SHIFT, BAR_MAX))


def render(qty, bid_live, bid_px, ask_live, ask_px):
    """qty[side][level] -> frame[y][x]. Rows below the ladder stay background (black)."""
    frame = [[BLACK] * WIDTH for _ in range(HEIGHT)]
    for level in range(N_LEVELS):
        bid_l, ask_l = bar_len(qty[BID][level]), bar_len(qty[ASK][level])
        top = (N_LEVELS - 1 - level) * ROW_H
        for y in range(top, top + ROW_H - 1):
            row = frame[y]
            for x in range(CENTRE - bid_l, CENTRE):
                row[x] = GREEN
            for x in range(CENTRE, CENTRE + ask_l):
                row[x] = RED
            if bid_live and level == bid_px:
                row[BID_MARK_X:BID_MARK_X + MARK_W] = [YELLOW] * MARK_W
            if ask_live and level == ask_px:
                row[ASK_MARK_X:ASK_MARK_X + MARK_W] = [YELLOW] * MARK_W
    return frame


def read_frame(path):
    """Frame dumped by the testbench with $writememh: one pixel per line, index y*320+x."""
    with open(path) as f:
        pixels = [int(line, 16) for line in f if line.strip() and not line.startswith("//")]
    return [pixels[y * WIDTH:(y + 1) * WIDTH] for y in range(HEIGHT)]


def write_png(frame, path):
    def chunk(tag, data):
        return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data))
    raw = b"".join(b"\x00" + bytes(255 * ((c >> s) & 1) for c in row for s in (2, 1, 0))
                   for row in frame)
    png = (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", WIDTH, HEIGHT, 8, 2, 0, 0, 0))
           + chunk(b"IDAT", zlib.compress(raw)) + chunk(b"IEND", b""))
    with open(path, "wb") as f:
        f.write(png)
