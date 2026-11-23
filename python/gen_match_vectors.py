"""
Random test vectors for matching_engine.v, answered by python/matching.py.

One vector = one event, applied for one clock cycle:
  in  (44 bits): {kind[1:0], bid_live, bid_px[5:0], ask_live, ask_px[5:0], size[7:0],
                  trade_side, trade_price[5:0], trade_qty[12:0]}
                 kind 0 = order_valid pulse (load the quote fields)
                 kind 1 = trade_valid pulse (quote fields = the quote still resting)
  exp (32 bits): {fill_valid, fill_side, fill_px[5:0], fill_qty[7:0], bid_rem[7:0], ask_rem[7:0]}
                 checked the cycle after the event

Writes ../sim/vectors/match_in.hex and match_exp.hex.
Usage:  python gen_match_vectors.py [n] [seed]
"""
import os
import random
import sys
from matching import MatchingEngine

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "sim", "vectors")


def main(n=500, seed=241):
    rng = random.Random(seed)
    me = MatchingEngine()
    q = (0, 0, 0, 0, 0)                      # quote held by the risk gate's registers
    ins, exps = [], []
    for _ in range(n):
        if rng.random() < 0.35:
            mid = rng.randrange(4, 60)
            q = (int(rng.random() < 0.8), mid - rng.randrange(0, 3),
                 int(rng.random() < 0.8), mid + rng.randrange(0, 3), rng.choice([1, 2, 4, 8, 200]))
            me.on_order(*q)
            fill, kind, t = None, 0, (0, 0, 0)
        else:
            side = rng.randrange(2)
            px = (q[1] if side == 0 else q[3]) + rng.randrange(-2, 3)
            t = (side, max(0, min(63, px)), rng.choice([1, 2, 3, 5, 100, 8191]))
            fill, kind = me.on_trade(*t), 1
        f = (1, fill.side, fill.px, fill.qty) if fill else (0, 0, 0, 0)
        ins.append((kind << 42) | (q[0] << 41) | (q[1] << 35) | (q[2] << 34) | (q[3] << 28)
                   | (q[4] << 20) | (t[0] << 19) | (t[1] << 13) | t[2])
        exps.append((f[0] << 31) | (f[1] << 30) | (f[2] << 24) | (f[3] << 16)
                    | (me.bid_rem << 8) | me.ask_rem)
    os.makedirs(OUT, exist_ok=True)
    with open(os.path.join(OUT, "match_in.hex"), "w") as fh:
        fh.writelines(f"{w:011X}\n" for w in ins)
    with open(os.path.join(OUT, "match_exp.hex"), "w") as fh:
        fh.writelines(f"{w:08X}\n" for w in exps)
    print(f"matching engine: {n} vectors, {me.fills} fills -> {OUT}")


if __name__ == "__main__":
    main(int(sys.argv[1]) if len(sys.argv) > 1 else 500,
         int(sys.argv[2]) if len(sys.argv) > 2 else 241)
