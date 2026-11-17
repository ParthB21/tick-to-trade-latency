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

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "sim", "vectors")
N_RANDOM = 200


def write_lines(path, words, digits):
    with open(path, "w") as f:
        for w in words:
            f.write(f"{w:0{digits}X}\n")


# ---------------- strategy ----------------
# in : {bid_valid, ask_valid, best_bid[5:0], best_ask[5:0], half_spread[1:0], size[7:0]}  24 bits
# exp: {ok, bid_px[5:0], ask_px[5:0], size[7:0]}                                         21 bits

STRATEGY_EDGES = [
    # (best_bid, bid_valid, best_ask, ask_valid, half_spread, size)
    (30, 1, 33, 0, 1, 2),      # no asks
    (30, 0, 33, 1, 1, 2),      # no bids
    (0, 0, 0, 0, 0, 1),        # empty book
    (33, 1, 30, 1, 1, 2),      # crossed
    (31, 1, 31, 1, 1, 2),      # locked (bid == ask) counts as crossed
    (31, 1, 32, 1, 0, 2),      # 1-tick spread, mid2 odd, hs 0 -> quote the touch
    (30, 1, 32, 1, 0, 2),      # mid2 even, hs 0 -> bid == ask == mid
    (30, 1, 33, 1, 3, 2),      # widest half-spread
    (0, 1, 1, 1, 3, 4),        # bid clamps at 0
    (1, 1, 2, 1, 3, 4),        # bid would be -2 -> 0
    (62, 1, 63, 1, 3, 8),      # ask clamps at 63
    (0, 1, 63, 1, 0, 255),     # widest book, max size
]


def strategy_vectors(rng):
    cases = list(STRATEGY_EDGES)
    for _ in range(N_RANDOM):
        cases.append((rng.randrange(64), rng.randrange(2), rng.randrange(64),
                      rng.randrange(2), rng.randrange(4), rng.randrange(256)))
    ins, exps = [], []
    for bb, bv, ba, av, hs, size in cases:
        ok, bid, ask, sz = strategy(bb, bv, ba, av, hs, size)
        ins.append((bv << 23) | (av << 22) | (bb << 16) | (ba << 10) | (hs << 8) | size)
        exps.append((int(ok) << 20) | (bid << 14) | (ask << 8) | sz)
    return ins, exps


# ---------------- risk gate ----------------
# One vector = one clock edge. Sequences matter (kill latch, sticky flags).
# in : {resetn_low, kill_sw, quote_valid, quote_ok, bid_px[5:0], ask_px[5:0], size[7:0],
#       best_bid[5:0], bid_valid, best_ask[5:0], ask_valid, position[9:0], max_pos[8:0], max_size[7:0]}  65 bits
# exp: {order_valid, bid_live, bid_px[5:0], ask_live, ask_px[5:0], size[7:0], killed, reject[5:0]}       30 bits

MAX_SIZE = 8
POS_MASK = 0x3FF                          # 10-bit two's complement


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


if __name__ == "__main__":
    rng = random.Random(int(sys.argv[1]) if len(sys.argv) > 1 else 241)
    os.makedirs(OUT, exist_ok=True)
    ins, exps = strategy_vectors(rng)
    write_lines(os.path.join(OUT, "strategy_in.hex"), ins, 6)
    write_lines(os.path.join(OUT, "strategy_exp.hex"), exps, 6)
    print(f"strategy: {len(ins)} vectors")
    ins, exps = risk_vectors(rng)
    write_lines(os.path.join(OUT, "risk_in.hex"), ins, 17)
    write_lines(os.path.join(OUT, "risk_exp.hex"), exps, 8)
    print(f"risk gate: {len(ins)} vectors")
