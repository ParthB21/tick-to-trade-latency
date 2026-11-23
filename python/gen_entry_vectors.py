"""
Test vectors for the keyboard path (ps2_rx -> kb_decoder -> order_entry), answered
by python/order_entry.py. The book top is held at best bid 30 / best ask 33.

  ../sim/vectors/kb_bytes.hex : one PS/2 byte per line, bit 8 = 1 means "send this
                                frame with a bad parity bit" (the receiver must drop it)
  ../sim/vectors/kb_exp.hex   : the messages order entry must send, in order, then FFFFFFFF
  ../sim/vectors/kb_meta.hex  : number of rejected entries ("Err")
Usage:  python gen_entry_vectors.py
"""
import os
from order_entry import OrderEntry, type_text, text_to_scan_bytes, CHAR_CODES

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "sim", "vectors")
TOP = (30, True, 33, True)

# (typed text, what it tests). "\n" = Enter, ! = Esc, < = Backspace, ~ = keypad Enter, ^ = up arrow
LINES = [
    ("B12 50\n",    "ADD bid 50 @12 -> id 1"),
    ("S40 7\n",     "ADD ask 7 @40 -> id 2"),
    ("B33 1\n",     "Err: bid 33 >= best ask 33 (crosses)"),
    ("S30 1\n",     "Err: ask 30 <= best bid 30 (crosses)"),
    ("S31 1\n",     "ADD ask 1 @31 -> id 3"),
    ("B64 1\n",     "Err: price 64 > 63"),
    ("B1 0\n",      "Err: qty 0"),
    ("B1 8192\n",   "Err: qty 8192 > 8191"),
    ("B1 8191\n",   "ADD bid 8191 @1 -> id 4 (max qty)"),
    ("X2\n",        "CANCEL id 2"),
    ("X0\n",        "Err: id 0"),
    ("X1024\n",     "Err: id 1024"),
    ("T3 25\n",     "TRADE id 3 qty 25"),
    ("T1024 1\n",   "Err: trade id 1024"),
    ("B2<7 9\n",    "Backspace: price 2 -> 7, ADD bid 9 @7 -> id 5"),
    ("B5!\n",       "Esc clears; the Enter after it does nothing"),
    ("B5\n",        "Enter with no qty yet: ignored (still typing)"),
    ("S50 1\n",     "a new letter restarts: ADD ask 1 @50 -> id 6"),
    ("B12345 6\n",  "5th digit ignored: price 1234 -> Err"),
    ("A45 3\n",     "A = ask: ADD ask 3 @45 -> id 7"),
    ("C7\n",        "C = cancel: CANCEL id 7"),
    ("B2^0 4~",     "up arrow ignored, keypad Enter: ADD bid 4 @20 -> id 8"),
    ("1 2\n",       "digits with no command: ignored"),
    ("X 5\n",       "Space while typing a cancel id: ignored -> CANCEL id 5"),
]
BAD_FRAME = "B"            # sent with bad parity after the lines: must be dropped
AFTER_BAD = "12 5\n"       # so these keys arrive with no command: nothing is sent


def main():
    entry = OrderEntry()
    msgs, data = [], []
    for text, _ in LINES:
        msgs += type_text(entry, text, TOP)
        data += text_to_scan_bytes(text)
    data.append(0x100 | CHAR_CODES[BAD_FRAME])                 # make code with bad parity
    data += [0xF0, CHAR_CODES[BAD_FRAME]]                      # its release (good frames)
    data += text_to_scan_bytes(AFTER_BAD)
    msgs += type_text(OrderEntry(), "", TOP)                   # nothing: no command is active
    os.makedirs(OUT, exist_ok=True)
    with open(os.path.join(OUT, "kb_bytes.hex"), "w") as f:
        f.writelines(f"{b:03X}\n" for b in data)
        f.write("FFF\n")
    with open(os.path.join(OUT, "kb_exp.hex"), "w") as f:
        f.writelines(f"{w:08X}\n" for w in msgs)
        f.write("FFFFFFFF\n")
    with open(os.path.join(OUT, "kb_meta.hex"), "w") as f:
        f.write(f"{entry.errors:08X}\n")
    print(f"order entry: {len(LINES)} lines, {len(data)} PS/2 bytes, {len(msgs)} messages, "
          f"{entry.errors} rejected -> {OUT}")
    for w in msgs:
        print(f"  {w:08X}")


if __name__ == "__main__":
    main()
