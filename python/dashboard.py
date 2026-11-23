"""
Reference model of dashboard.v (Pierce): renders the 320x240 frame the VGA
adapter should hold for a given book, our quotes, position and P&L, and
reads/writes frames.

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
BLACK, GREEN, RED, YELLOW, WHITE = 0b000, 0b010, 0b100, 0b110, 0b111

# text: 5x7 glyphs drawn 2x, one per 16-pixel cell
TEXT_X, POS_Y, PNL_Y = 8, 196, 218
CELL_W, SCALE, GLYPH_W, GLYPH_H = 16, 2, 5, 7
PNL_SHOWN = 99999
FONT = {
    "0": ("01110", "10001", "10011", "10101", "11001", "10001", "01110"),
    "1": ("00100", "01100", "00100", "00100", "00100", "00100", "01110"),
    "2": ("01110", "10001", "00001", "00010", "00100", "01000", "11111"),
    "3": ("11111", "00010", "00100", "00010", "00001", "10001", "01110"),
    "4": ("00010", "00110", "01010", "10010", "11111", "00010", "00010"),
    "5": ("11111", "10000", "11110", "00001", "00001", "10001", "01110"),
    "6": ("00110", "01000", "10000", "11110", "10001", "10001", "01110"),
    "7": ("11111", "00001", "00010", "00100", "01000", "01000", "01000"),
    "8": ("01110", "10001", "10001", "01110", "10001", "10001", "01110"),
    "9": ("01110", "10001", "10001", "01111", "00001", "00010", "01100"),
    "+": ("00000", "00100", "00100", "11111", "00100", "00100", "00000"),
    "-": ("00000", "00000", "00000", "11111", "00000", "00000", "00000"),
    "P": ("11110", "10001", "10001", "11110", "10000", "10000", "10000"),
    "O": ("01110", "10001", "10001", "10001", "10001", "10001", "01110"),
    "S": ("01111", "10000", "10000", "01110", "00001", "00001", "11110"),
    "N": ("10001", "11001", "10101", "10011", "10001", "10001", "10001"),
    "L": ("10000", "10000", "10000", "10000", "10000", "10000", "11111"),
}


def bar_len(qty):
    if qty == 0:
        return 0
    return max(1, min(qty >> QTY_SHIFT, BAR_MAX))


def text_lines(position, pnl):
    """[(top row, string, colour)] for the two text lines."""
    sign = lambda v: "-" if v < 0 else "+"
    pos_text = f"POS {sign(position)}{abs(position):03d}"
    pnl_text = f"PNL {sign(pnl)}{min(abs(pnl), PNL_SHOWN):05d}"
    return [(POS_Y, pos_text, WHITE), (PNL_Y, pnl_text, RED if pnl < 0 else GREEN)]


def draw_text(frame, top, text, colour):
    for i, ch in enumerate(text):
        if ch == " ":
            continue
        left = TEXT_X + i * CELL_W
        for r, bits in enumerate(FONT[ch]):
            for c, bit in enumerate(bits):
                if bit == "1":
                    for y in range(top + r * SCALE, top + (r + 1) * SCALE):
                        frame[y][left + c * SCALE:left + (c + 1) * SCALE] = [colour] * SCALE


def render(qty, bid_live, bid_px, ask_live, ask_px, position, pnl):
    """qty[side][level] -> frame[y][x]."""
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
    for top, text, colour in text_lines(position, pnl):
        draw_text(frame, top, text, colour)
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
