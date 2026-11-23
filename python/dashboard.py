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

# text, drawn for a 16:9 monitor that stretches the picture 4/3 wider (dashboard.v):
# 5-pixel glyphs in 6-pixel cells, 9 rows tall (font rows 2 and 4 twice), 10-row line pitch.
# Panel: 4 lines of 52 cells, line k at row 194 + 10k.
TEXT_X, TEXT_Y, CELL_W, LINE_H, N_CELLS = 4, 194, 6, 10, 52
FONT_ROWS = (0, 1, 2, 2, 3, 4, 4, 5, 6)            # drawn row -> font row
PNL_SHOWN, FILLS_SHOWN = 99999, 9999
CYAN = 0b011
SEG_CHAR = {**{d: str(d) for d in range(10)}, 10: "-", 16: "B", 17: "S", 18: "C", 19: "T",
            20: "E", 21: "R", 22: "D", 23: "P", 24: "Q", 25: "F"}
IDLE_KEYS = [10] * 6                       # order entry with nothing typed: "------"
RISK_WORDS = [(20, "KILL"), (25, "SIDE"), (30, "SIZE"), (35, "LONG"), (40, "SHORT"), (46, "CROSS")]

# arrow-key cursor (book_cursor.v): the bar(s) on its level are drawn white, and a
# top-right readout box with one line "BID pp QTY qqqq" / "ASK pp QTY qqqq" / "--- pp QTY 0000".
# From reset until the first arrow key the cursor is off: no white bar, readout "--- -- QTY 0000".
CURSOR_START = 32
READ_X, READ_Y, BOX_X, BOX_LAST_Y = 230, 1, 226, 10


def default_panel():
    return dict(best_bid=0, bid_valid=False, best_ask=0, ask_valid=False, msg_count=0, size=0,
                skew=False, fill_count=0, fill_side=0, fill_px=0, fill_qty=0, keys=IDLE_KEYS, reject=0,
                cursor=CURSOR_START, cursor_active=False)


def bar_len(qty):
    if qty == 0:
        return 0
    return max(1, min(qty >> QTY_SHIFT, BAR_MAX))


def put(line, slot, text):
    for i, ch in enumerate(text):
        line[slot + i] = ch


def text_lines(bid_live, bid_px, ask_live, ask_px, position, pnl, p):
    """4 lines of 52 characters plus a colour per character, same layout as dashboard.v."""
    sign = lambda v: "-" if v < 0 else "+"
    two = lambda ok, v: f"{v:02d}" if ok else "--"
    lines = [[" "] * N_CELLS for _ in range(4)]
    l0 = lines[0]
    put(l0, 0, "BOOK"); put(l0, 5, "BID"); put(l0, 9, two(p["bid_valid"], p["best_bid"]))
    put(l0, 12, "ASK"); put(l0, 16, two(p["ask_valid"], p["best_ask"]))
    put(l0, 19, "SPREAD")
    put(l0, 26, two(p["bid_valid"] and p["ask_valid"], (p["best_ask"] - p["best_bid"]) % 64))
    put(l0, 29, "MSGS"); put(l0, 34, f"{p['msg_count']:04d}")
    l1 = lines[1]
    put(l1, 0, "BOT"); put(l1, 5, "BID"); put(l1, 9, two(bid_live, bid_px))
    put(l1, 12, "ASK"); put(l1, 16, two(ask_live, ask_px))
    put(l1, 19, "SPREAD"); put(l1, 26, two(bid_live and ask_live, (ask_px - bid_px) % 64))
    put(l1, 29, "SIZE"); put(l1, 34, str(min(p["size"], 9)))
    put(l1, 36, "SKEW"); put(l1, 41, "ON" if p["skew"] else "OFF")
    l2 = lines[2]
    put(l2, 0, f"POS {sign(position)}{abs(position):03d}")
    put(l2, 9, f"PNL {sign(pnl)}{min(abs(pnl), PNL_SHOWN):05d}")
    put(l2, 20, f"FILLS {min(p['fill_count'], FILLS_SHOWN):04d}")
    if p["fill_count"]:
        put(l2, 31, "LAST"); put(l2, 36, "SELL" if p["fill_side"] else "BUY")
        put(l2, 41, f"{p['fill_qty']:03d}"); put(l2, 45, "AT"); put(l2, 48, f"{p['fill_px']:02d}")
    l3 = lines[3]
    put(l3, 0, "KEYS")
    for slot, code in zip((5, 7, 9, 10, 11, 12), p["keys"]):
        l3[slot] = SEG_CHAR.get(code, " ")
    put(l3, 15, "RISK")
    if p["reject"] == 0:
        put(l3, 20, "OK")
    for bit, (slot, word) in enumerate(RISK_WORDS):
        if p["reject"] >> bit & 1:
            put(l3, slot, word)
    pnl_col = RED if pnl < 0 else GREEN
    keys_col = RED if p["keys"][0] == 20 else WHITE
    risk_col = GREEN if p["reject"] == 0 else RED
    colours = [
        [WHITE] * N_CELLS,
        [YELLOW] * N_CELLS,
        [WHITE if i < 9 else pnl_col if i < 20 else CYAN for i in range(N_CELLS)],
        [keys_col if i < 15 else risk_col for i in range(N_CELLS)],
    ]
    return ["".join(l) for l in lines], colours


def draw_text(frame, left, top, text, cols):
    """One line of 6-pixel cells with 9-row glyphs (the 16:9 stretch correction)."""
    for i, ch in enumerate(text):
        if ch == " ":
            continue
        x0 = left + i * CELL_W
        for r, font_row in enumerate(FONT_ROWS):
            for c, bit in enumerate(FONT[ch][font_row]):
                if bit == "1":
                    frame[top + r][x0 + c] = cols[i]


def cursor_readout(qty, level, active):
    """Text and colour of the top-right box for the cursor level."""
    if not active:
        return "--- -- QTY 0000", WHITE
    bid_q, ask_q = qty[BID][level], qty[ASK][level]
    if bid_q:
        return f"BID {level:02d} QTY {bid_q:04d}", GREEN
    if ask_q:
        return f"ASK {level:02d} QTY {ask_q:04d}", RED
    return f"--- {level:02d} QTY 0000", WHITE


def render(qty, bid_live, bid_px, ask_live, ask_px, position, pnl, panel=None):
    """qty[side][level] -> frame[y][x]. panel = default_panel()-style dict for the text panel
    and the cursor."""
    p = default_panel()
    p.update(panel or {})
    frame = [[BLACK] * WIDTH for _ in range(HEIGHT)]
    for level in range(N_LEVELS):
        bid_l, ask_l = bar_len(qty[BID][level]), bar_len(qty[ASK][level])
        top = (N_LEVELS - 1 - level) * ROW_H
        for y in range(top, top + ROW_H - 1):
            row = frame[y]
            on_cursor = p["cursor_active"] and level == p["cursor"]
            for x in range(CENTRE - bid_l, CENTRE):
                row[x] = WHITE if on_cursor else GREEN
            for x in range(CENTRE, CENTRE + ask_l):
                row[x] = WHITE if on_cursor else RED
            if bid_live and level == bid_px:
                row[BID_MARK_X:BID_MARK_X + MARK_W] = [YELLOW] * MARK_W
            if ask_live and level == ask_px:
                row[ASK_MARK_X:ASK_MARK_X + MARK_W] = [YELLOW] * MARK_W
    for y in range(BOX_LAST_Y + 1):
        frame[y][BOX_X:WIDTH] = [BLACK] * (WIDTH - BOX_X)
    text, colour = cursor_readout(qty, p["cursor"], p["cursor_active"])
    draw_text(frame, READ_X, READ_Y, text, [colour] * len(text))
    lines, colours = text_lines(bid_live, bid_px, ask_live, ask_px, position, pnl, p)
    for k, (line, cols) in enumerate(zip(lines, colours)):
        draw_text(frame, TEXT_X, TEXT_Y + k * LINE_H, line, cols)
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
