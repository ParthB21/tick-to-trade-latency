"""
Shared message format for the Tick-to-Trade project.
Every market message is ONE 32-bit word in the ROM:

  [31:30] type      00 = ADD, 01 = CANCEL, 10 = TRADE, 11 = END (stop the feed)
  [29]    side      0 = BID (buy), 1 = ASK (sell)
  [28:23] price     0..63  (price level / tick)
  [22:13] order ID  0..1023
  [12:0]  quantity  0..8191

CANCEL and TRADE only need the order ID (+ qty for TRADE); the order book looks
up the order's side and price in its own order table. We still fill in side and
price so the CSV is easy to read.
"""

ADD, CANCEL, TRADE, END = 0, 1, 2, 3
BID, ASK = 0, 1
TYPE_NAMES = {ADD: "ADD", CANCEL: "CANCEL", TRADE: "TRADE", END: "END"}

N_LEVELS = 64
N_IDS = 1024
MAX_QTY = 8191


def pack(mtype, side, price, oid, qty):
    assert 0 <= mtype < 4 and side in (0, 1)
    assert 0 <= price < N_LEVELS and 0 <= oid < N_IDS and 0 <= qty <= MAX_QTY
    return (mtype << 30) | (side << 29) | (price << 23) | (oid << 13) | qty


def unpack(word):
    return ((word >> 30) & 0x3, (word >> 29) & 0x1, (word >> 23) & 0x3F,
            (word >> 13) & 0x3FF, word & 0x1FFF)


END_WORD = 0xFFFFFFFF


def write_hex(words, path, depth=None):
    """For $readmemh in Verilog (works in ModelSim and Quartus).
    Pads with END words up to depth so the whole ROM is defined."""
    words = list(words) + [END_WORD] * max(0, (depth or 0) - len(words))
    with open(path, "w") as f:
        for w in words:
            f.write(f"{w:08X}\n")


def write_mif(words, path, depth):
    """For a Quartus IP-catalog ROM, if you prefer that over $readmemh."""
    with open(path, "w") as f:
        f.write(f"WIDTH=32;\nDEPTH={depth};\nADDRESS_RADIX=UNS;\nDATA_RADIX=HEX;\n\n")
        f.write("CONTENT BEGIN\n")
        for i in range(depth):
            w = words[i] if i < len(words) else END_WORD
            f.write(f"    {i} : {w:08X};\n")
        f.write("END;\n")


def read_hex(path):
    with open(path) as f:
        return [int(line.strip(), 16) for line in f if line.strip()]
