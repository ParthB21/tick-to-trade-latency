"""
Reference model of dashboard.v (Pierce): renders the 320x240 frame the VGA
adapter should hold for a given book, our quotes, position and P&L, and
reads/writes frames.

Colours are the adapter's 3-bit {R, G, B} codes.
"""
import struct
import zlib
from msgfmt import N_LEVELS, BID, ASK
from font import FONT

WIDTH, HEIGHT = 320, 240
ROW_H = 3                       # rows per level; the last one is a black gap
CENTRE = 160
QTY_SHIFT = 5
BAR_MAX = 159
MARK_W = 8
BID_MARK_X, ASK_MARK_X = 8, 304
BLACK, GREEN, RED, YELLOW, WHITE = 0b000, 0b010, 0b100, 0b110, 0b111

# text panel (M2): 6 lines of 5x7 glyphs at 1x, 8-pixel cells, line k at row 192 + 8k
TEXT_X, TEXT_Y, CELL_W, LINE_H = 4, 192, 8, 8
PNL_SHOWN, FILLS_SHOWN = 99999, 9999
CYAN = 0b011
SEG_CHAR = {**{d: str(d) for d in range(10)}, 10: "-", 16: "B", 17: "S", 18: "C", 19: "T",
            20: "E", 21: "R", 22: "D", 23: "P", 24: "Q", 25: "F"}
IDLE_KEYS = [10] * 6                       # order entry with nothing typed: "------"
RISK_WORDS = [(5, "KILL"), (10, "SIDE"), (15, "SIZE"), (20, "LONG"), (25, "SHORT"), (31, "CROSS")]


def default_panel():
    return dict(best_bid=0, bid_valid=False, best_ask=0, ask_valid=False, msg_count=0, size=0,
                skew=False, fill_count=0, fill_side=0, fill_px=0, fill_qty=0, keys=IDLE_KEYS, reject=0)


def bar_len(qty):
    if qty == 0:
        return 0
    return max(1, min(qty >> QTY_SHIFT, BAR_MAX))


def put(line, slot, text):
    for i, ch in enumerate(text):
        line[slot + i] = ch


def text_lines(bid_live, bid_px, ask_live, ask_px, position, pnl, p):
    """6 lines of 39 characters plus a colour per character, same layout as dashboard.v."""
    sign = lambda v: "-" if v < 0 else "+"
    two = lambda ok, v: f"{v:02d}" if ok else "--"
    lines = [[" "] * 39 for _ in range(6)]
    l0 = lines[0]
    put(l0, 0, "BOOK"); put(l0, 5, "BID"); put(l0, 9, two(p["bid_valid"], p["best_bid"]))
    put(l0, 12, "ASK"); put(l0, 16, two(p["ask_valid"], p["best_ask"]))
    put(l0, 19, "SPREAD")
    put(l0, 26, two(p["bid_valid"] and p["ask_valid"], (p["best_ask"] - p["best_bid"]) % 64))
    put(l0, 29, "MSGS"); put(l0, 34, f"{p['msg_count']:04d}")
    l1 = lines[1]
    put(l1, 0, "BOT"); put(l1, 5, "BID"); put(l1, 9, two(bid_live, bid_px))
    put(l1, 12, "ASK"); put(l1, 16, two(ask_live, ask_px))
    put(l1, 19, "SIZE"); put(l1, 24, str(min(p["size"], 9)))
    put(l1, 26, "SKEW"); put(l1, 31, "ON" if p["skew"] else "OFF")
    l2 = lines[2]
    put(l2, 0, f"POS {sign(position)}{abs(position):03d}")
    put(l2, 11, f"PNL {sign(pnl)}{min(abs(pnl), PNL_SHOWN):05d}")
    l3 = lines[3]
    put(l3, 0, f"FILLS {min(p['fill_count'], FILLS_SHOWN):04d}")
    if p["fill_count"]:
        put(l3, 12, "LAST"); put(l3, 17, "SELL" if p["fill_side"] else "BUY")
        put(l3, 22, f"{p['fill_qty']:03d}"); put(l3, 26, "AT"); put(l3, 29, f"{p['fill_px']:02d}")
    l4 = lines[4]
    put(l4, 0, "KEYS")
    for slot, code in zip((6, 8, 10, 11, 12, 13), p["keys"]):
        l4[slot] = SEG_CHAR.get(code, " ")
    l5 = lines[5]
    put(l5, 0, "RISK")
    if p["reject"] == 0:
        put(l5, 5, "OK")
    for bit, (slot, word) in enumerate(RISK_WORDS):
        if p["reject"] >> bit & 1:
            put(l5, slot, word)
    pnl_col = RED if pnl < 0 else GREEN
    colours = [
        [WHITE] * 39,
        [YELLOW] * 39,
        [WHITE if i < 11 else pnl_col for i in range(39)],
        [CYAN] * 39,
        [RED if p["keys"][0] == 20 else WHITE] * 39,
        [GREEN if p["reject"] == 0 else RED] * 39,
    ]
    return ["".join(l) for l in lines], colours


def draw_panel(frame, lines, colours):
    for k, (text, cols) in enumerate(zip(lines, colours)):
        top = TEXT_Y + k * LINE_H
        for i, ch in enumerate(text):
            if ch == " ":
                continue
            left = TEXT_X + i * CELL_W
            for r, bits in enumerate(FONT[ch]):
                for c, bit in enumerate(bits):
                    if bit == "1":
                        frame[top + r][left + c] = cols[i]


def render(qty, bid_live, bid_px, ask_live, ask_px, position, pnl, panel=None):
    """qty[side][level] -> frame[y][x]. panel = default_panel()-style dict for the text panel."""
    p = default_panel()
    p.update(panel or {})
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
    draw_panel(frame, *text_lines(bid_live, bid_px, ask_live, ask_px, position, pnl, p))
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
