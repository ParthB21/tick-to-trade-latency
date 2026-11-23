"""
Writes test vectors for Pierce's block testbenches into ../sim/vectors/.
Each block gets <block>_in.hex (one stimulus word per line) and
<block>_exp.hex (the reference model's answer for that line).

Usage:  python gen_vectors.py [seed]
"""
import os
import random
import sys
from strategy import strategy
from risk import RiskState, risk_step
from pnl import PnlState, pnl_step, BUY, SELL

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "sim", "vectors")
N_RANDOM = 200


def write_lines(path, words, digits):
    with open(path, "w") as f:
        for w in words:
            f.write(f"{w:0{digits}X}\n")


# ---------------- strategy ----------------
# in : {bid_valid, ask_valid, best_bid[5:0], best_ask[5:0], half_spread[1:0], size[7:0],
#       position[9:0], skew_k[2:0]}                                                     37 bits
# exp: {ok, bid_px[5:0], ask_px[5:0], size[7:0]}                                         21 bits

POS_MASK = 0x3FF                          # 10-bit two's complement

STRATEGY_EDGES = [
    # (best_bid, bid_valid, best_ask, ask_valid, half_spread, size, position, skew_k)
    (30, 1, 33, 0, 1, 2, 0, 0),       # no asks
    (30, 0, 33, 1, 1, 2, 0, 0),       # no bids
    (0, 0, 0, 0, 0, 1, 0, 0),         # empty book
    (33, 1, 30, 1, 1, 2, 0, 0),       # crossed
    (31, 1, 31, 1, 1, 2, 0, 0),       # locked (bid == ask) counts as crossed
    (31, 1, 32, 1, 0, 2, 0, 0),       # 1-tick spread, mid2 odd, hs 0 -> quote the touch
    (30, 1, 32, 1, 0, 2, 0, 0),       # mid2 even, hs 0 -> bid == ask == mid
    (30, 1, 33, 1, 3, 2, 0, 0),       # widest half-spread
    (0, 1, 1, 1, 3, 4, 0, 0),         # bid clamps at 0
    (1, 1, 2, 1, 3, 4, 0, 0),         # bid would be -2 -> 0
    (62, 1, 63, 1, 3, 8, 0, 0),       # ask clamps at 63
    (0, 1, 63, 1, 0, 255, 0, 0),      # widest book, max size
    (30, 1, 33, 1, 1, 2, 8, 0),       # long but skew off: no shift
    (30, 1, 33, 1, 1, 2, 8, 2),       # long 8, k 2 -> skew 2: both quotes down 2
    (30, 1, 33, 1, 1, 2, -8, 2),      # short 8 -> both quotes up 2
    (30, 1, 33, 1, 1, 2, 3, 2),       # 3*2/8 = 0.75 -> 0
    (30, 1, 33, 1, 1, 2, -3, 2),      # -0.75 rounds toward 0 too (no -1 bias)
    (30, 1, 33, 1, 1, 2, -1, 7),      # -7/8 -> 0
    (30, 1, 33, 1, 1, 2, 511, 7),     # max long: skew 447, bid clamps to 0, ask stops at best bid + 1 = 31
    (30, 1, 33, 1, 1, 2, -512, 7),    # max short: -(-512) magnitude, ask clamps to 63, bid stops at best ask - 1 = 32
    (2, 1, 5, 1, 0, 1, 16, 1),        # skew pushes the bid below 0 -> 0, ask (2) would cross -> best bid + 1 = 3
    (30, 1, 31, 1, 0, 2, 9, 2),       # long 9, 1-tick book: ask 29 would cross -> 31 (joins best ask)
    (30, 1, 31, 1, 1, 2, -8, 2),      # short 8, 1-tick book: bid 31 would cross -> 30 (joins best bid)
    (30, 1, 31, 1, 3, 2, 16, 2),      # long 16: skew 4 > half-spread 3, ask still 31, not rejected
    (30, 1, 33, 1, 1, 2, 12, 2),      # long 12: ask 32 + 1 - 3 = 30 would cross -> 31, inside the spread
]


def strategy_vectors(rng):
    cases = list(STRATEGY_EDGES)
    for _ in range(N_RANDOM):
        position = rng.randrange(-48, 49) if rng.random() < 0.8 else rng.randrange(-512, 512)
        cases.append((rng.randrange(64), rng.randrange(2), rng.randrange(64),
                      rng.randrange(2), rng.randrange(4), rng.randrange(256),
                      position, rng.randrange(8)))
    ins, exps = [], []
    for bb, bv, ba, av, hs, size, pos, k in cases:
        ok, bid, ask, sz = strategy(bb, bv, ba, av, hs, size, pos, k)
        ins.append((bv << 36) | (av << 35) | (bb << 29) | (ba << 23) | (hs << 21) | (size << 13)
                   | ((pos & POS_MASK) << 3) | k)
        exps.append((int(ok) << 20) | (bid << 14) | (ask << 8) | sz)
    return ins, exps


# ---------------- risk gate ----------------
# One vector = one clock edge. Sequences matter (kill latch, sticky flags).
# in : {resetn_low, kill_sw, quote_valid, quote_ok, bid_px[5:0], ask_px[5:0], size[7:0],
#       best_bid[5:0], bid_valid, best_ask[5:0], ask_valid, position[9:0], max_pos[8:0], max_size[7:0]}  65 bits
# exp: {order_valid, bid_live, bid_px[5:0], ask_live, ask_px[5:0], size[7:0], killed, reject[5:0]}       30 bits

MAX_SIZE = 8


def random_quote(rng):
    best_bid = rng.randrange(20, 40)
    best_ask = best_bid + rng.randrange(1, 5)
    bid_px = best_bid + rng.randrange(-3, 3)          # sometimes >= best_ask (crossing)
    ask_px = best_ask + rng.randrange(-2, 4)          # sometimes <= best_bid
    return dict(quote=(1, rng.random() > 0.1, bid_px, ask_px, rng.choice([1, 2, 4, 8, 8, 12])),
                top=(best_bid, rng.random() > 0.05, best_ask, rng.random() > 0.05),
                position=rng.randrange(-40, 41), max_pos=rng.choice([4, 8, 16, 32]))


def risk_vectors(rng):
    idle = dict(quote=(0, 0, 0, 0, 0), top=(30, 1, 32, 1), position=0, max_pos=8)
    steps = []                                        # (reset, kill_sw, fields)
    steps += [(0, 0, random_quote(rng)) for _ in range(150)]
    steps += [(0, 0, idle)] * 3                       # outputs must hold, order_valid low
    for pos in (511, -512, 500, -500):                # extreme positions: signed overflow check
        q = random_quote(rng)
        steps.append((0, 0, dict(q, position=pos, max_pos=32)))
    steps += [(0, 1, idle)]                           # kill rises with no quote
    steps += [(0, 1, random_quote(rng)) for _ in range(5)]   # killed: all rejected
    steps += [(0, 0, random_quote(rng)) for _ in range(5)]   # switch down: still killed
    steps += [(1, 0, idle)]                           # reset clears the latch and flags
    steps += [(0, 0, random_quote(rng)) for _ in range(20)]
    steps += [(0, 1, random_quote(rng))]              # kill and a quote in the same cycle
    steps += [(0, 0, random_quote(rng)) for _ in range(3)]
    steps += [(1, 0, idle)]
    steps += [(0, 0, random_quote(rng)) for _ in range(50)]

    st = RiskState()
    ins, exps = [], []
    for rst, kill, f in steps:
        valid, ok, bid_px, ask_px, size = f["quote"]
        bid_px, ask_px = max(0, min(63, bid_px)), max(0, min(63, ask_px))
        best_bid, bid_valid, best_ask, ask_valid = f["top"]
        st = RiskState() if rst else risk_step(st, kill, (valid, ok, bid_px, ask_px, size),
                                               f["top"], f["position"], f["max_pos"], MAX_SIZE)
        ins.append((rst << 64) | (kill << 63) | (valid << 62) | (int(ok) << 61) | (bid_px << 55)
                   | (ask_px << 49) | (size << 41) | (best_bid << 35) | (int(bid_valid) << 34)
                   | (best_ask << 28) | (int(ask_valid) << 27) | ((f["position"] & POS_MASK) << 17)
                   | (f["max_pos"] << 8) | MAX_SIZE)
        exps.append((st.order_valid << 29) | (st.bid_live << 28) | (st.bid_px << 22)
                    | (st.ask_live << 21) | (st.ask_px << 15) | (st.size << 7)
                    | (st.killed << 6) | st.reject)
    return ins, exps


# ---------------- P&L tracker ----------------
# One vector = one clock edge.
# in : {resetn_low, fill_valid, fill_side, fill_px[5:0], fill_qty[7:0],
#       best_bid[5:0], bid_valid, best_ask[5:0], ask_valid}                    31 bits
# exp: {position[9:0], pnl[23:0]}                                             34 bits

PNL_MASK = 0xFFFFFF                       # 24-bit two's complement
NO_FILL = (0, BUY, 0, 0)
EMPTY_BOOK = (0, 0, 0, 0)
POS_SOFT_LIMIT = 250                      # past this, fills lean back toward flat (250 + 255 < 512)


def random_top(rng):
    best_bid = rng.randrange(10, 50)
    return (best_bid, rng.random() > 0.1, best_bid + rng.randrange(1, 6), rng.random() > 0.1)


def random_fill(rng, position):
    side = rng.randrange(2)
    if abs(position) > POS_SOFT_LIMIT:
        side = SELL if position > 0 else BUY
    qty = rng.choice([1, 2, 4, 8]) if rng.random() < 0.7 else rng.randrange(1, 256)
    return (1, side, rng.randrange(64), qty)


def pnl_vectors(rng):
    steps = []                                        # (reset, fill or None = random, top or None = random)
    steps += [(0, NO_FILL, EMPTY_BOOK)] * 3           # mark stays 0 before the book has both sides
    steps += [(0, (1, BUY, 30, 4), EMPTY_BOOK)]       # fill before any mark: pnl = cash
    steps += [(0, NO_FILL, (30, 1, 33, 1))] * 2       # mark = floor(31.5) = 31
    steps += [(0, NO_FILL, (30, 1, 0, 0))] * 2        # one-sided book: mark holds
    steps += [(0, (1, SELL, 33, 4), (30, 1, 33, 1))]  # round trip: +3 ticks x 4 shares
    steps += [(0, None, None) for _ in range(300)]
    steps += [(1, NO_FILL, EMPTY_BOOK)]               # reset: the extremes below start flat
    steps += [(0, (1, BUY, 63, 255), (62, 1, 63, 1))] * 2           # max notional, long 510
    steps += [(0, NO_FILL, (62, 1, 63, 1))] * 2
    steps += [(0, (1, SELL, 0, 255), (0, 1, 1, 1))] * 4             # through flat to short 510
    steps += [(0, NO_FILL, (0, 1, 1, 1))] * 2
    steps += [(1, NO_FILL, EMPTY_BOOK)]               # reset clears everything
    steps += [(0, None, None) for _ in range(200)]

    st = PnlState()
    ins, exps = [], []
    for rst, fill, top in steps:
        fill = fill or (random_fill(rng, st.position) if rng.random() < 0.4 else NO_FILL)
        top = top or random_top(rng)
        st = PnlState() if rst else pnl_step(st, fill, top)
        valid, side, px, qty = fill
        best_bid, bid_valid, best_ask, ask_valid = top
        ins.append((rst << 30) | (valid << 29) | (side << 28) | (px << 22) | (qty << 14)
                   | (best_bid << 8) | (int(bid_valid) << 7) | (best_ask << 1) | int(ask_valid))
        exps.append(((st.position & POS_MASK) << 24) | (st.pnl & PNL_MASK))
    return ins, exps


if __name__ == "__main__":
    rng = random.Random(int(sys.argv[1]) if len(sys.argv) > 1 else 241)
    os.makedirs(OUT, exist_ok=True)
    ins, exps = strategy_vectors(rng)
    write_lines(os.path.join(OUT, "strategy_in.hex"), ins, 10)
    write_lines(os.path.join(OUT, "strategy_exp.hex"), exps, 6)
    print(f"strategy: {len(ins)} vectors")
    ins, exps = risk_vectors(rng)
    write_lines(os.path.join(OUT, "risk_in.hex"), ins, 17)
    write_lines(os.path.join(OUT, "risk_exp.hex"), exps, 8)
    print(f"risk gate: {len(ins)} vectors")
    ins, exps = pnl_vectors(rng)
    write_lines(os.path.join(OUT, "pnl_in.hex"), ins, 8)
    write_lines(os.path.join(OUT, "pnl_exp.hex"), exps, 9)
    print(f"pnl tracker: {len(ins)} vectors")
