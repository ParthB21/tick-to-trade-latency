"""
Generates the market data the FPGA replays.

Writes into ../mem:
  market_data.hex  - main feed for $readmemh (Verilog ROM)
  market_data.mif  - same data for a Quartus IP-catalog ROM (optional)
  market_data.csv  - human-readable version for your milestone PDF
  test_small.hex   - short hand-checkable sequence (used for the board demo
                     and the first waveform screenshots)

The main feed is a synthetic market: a mid price that random-walks around
level 32, traders adding bids below it and asks above it, cancelling orders,
and trades eating the best orders. Swapping this for real NASDAQ ITCH data
later only changes this script, not the hardware.

Usage:  python gen_market.py [num_messages] [seed]
"""
import os
import random
import sys
from msgfmt import (ADD, CANCEL, TRADE, BID, ASK, TYPE_NAMES, N_IDS, END_WORD,
                    pack, unpack, write_hex, write_mif)

ROM_DEPTH = 1024          # must match DEPTH of the market ROM in the Verilog
SMALL_DEPTH = 16          # must match DEPTH of the small test ROM
HERE = os.path.dirname(os.path.abspath(__file__))
MEM = os.path.join(HERE, "..", "mem")


def small_test():
    """Short sequence you can check by hand. Expected book after each line
    is in the comment as (best bid, best ask)."""
    return [
        pack(ADD,    BID, 10, 1, 100),  # (10, --)  first bid
        pack(ADD,    BID, 12, 2, 50),   # (12, --)  better bid
        pack(ADD,    ASK, 15, 3, 70),   # (12, 15)  first ask
        pack(ADD,    ASK, 14, 4, 30),   # (12, 14)  better ask
        pack(ADD,    BID, 12, 5, 25),   # (12, 14)  second order at 12 (qty 75)
        pack(CANCEL, BID, 12, 2, 0),    # (12, 14)  12 still has 25 left
        pack(TRADE,  ASK, 14, 4, 10),   # (12, 14)  partial fill: 14 has 20 left
        pack(TRADE,  ASK, 14, 4, 20),   # (12, 15)  14 fully traded away
        pack(CANCEL, BID, 12, 5, 0),    # (10, 15)  last order at 12 gone
        pack(CANCEL, BID, 0, 99, 0),    # (10, 15)  unknown ID: ignored
        pack(ADD,    BID, 13, 6, 40),   # (13, 15)
        pack(CANCEL, BID, 13, 6, 0),    # (10, 15)
        pack(CANCEL, BID, 10, 1, 0),    # (--, 15)  no bids left
        END_WORD,
    ]


def synthetic_market(n, seed):
    rng = random.Random(seed)
    mid = 32.0
    live = {}                       # oid -> [side, price, qty]
    free_ids = list(range(N_IDS))
    rng.shuffle(free_ids)
    words = []

    while len(words) < n:
        mid = min(max(mid + rng.choice([-0.5, 0, 0, 0.5]), 12), 51)
        r = rng.random()
        bids = [o for o, v in live.items() if v[0] == BID]
        asks = [o for o, v in live.items() if v[0] == ASK]

        if (r < 0.55 or len(live) < 10) and free_ids:            # ADD
            side = rng.choice([BID, ASK])
            dist = 1 + int(rng.expovariate(0.4))                 # mostly near mid
            price = int(mid) - dist if side == BID else int(mid) + dist
            if bids and side == ASK:                              # never cross the book
                price = max(price, max(live[o][1] for o in bids) + 1)
            if asks and side == BID:
                price = min(price, min(live[o][1] for o in asks) - 1)
            price = min(max(price, 0), 63)
            qty = rng.choice([100, 100, 200, 300, 500]) + rng.randrange(0, 100)
            oid = free_ids.pop()
            live[oid] = [side, price, qty]
            words.append(pack(ADD, side, price, oid, qty))

        elif r < 0.80 and live:                                   # CANCEL
            oid = rng.choice(list(live))
            side, price, _ = live.pop(oid)
            free_ids.insert(0, oid)
            words.append(pack(CANCEL, side, price, oid, 0))

        elif bids and asks:                                       # TRADE at the best level
            side = rng.choice([BID, ASK])
            pool = bids if side == BID else asks
            best = (max if side == BID else min)(live[o][1] for o in pool)
            oid = rng.choice([o for o in pool if live[o][1] == best])
            q = live[oid][2]
            tq = q if rng.random() < 0.5 else rng.randint(1, q)
            words.append(pack(TRADE, side, best, oid, tq))
            if tq == q:
                del live[oid]
                free_ids.insert(0, oid)
            else:
                live[oid][2] -= tq

    words.append(END_WORD)
    return words


def write_csv(words, path):
    with open(path, "w") as f:
        f.write("index,hex,type,side,price,order_id,qty\n")
        for i, w in enumerate(words):
            t, s, p, o, q = unpack(w)
            f.write(f"{i},{w:08X},{TYPE_NAMES[t]},{'BID' if s == 0 else 'ASK'},{p},{o},{q}\n")


if __name__ == "__main__":
    n = int(sys.argv[1]) if len(sys.argv) > 1 else 1000
    seed = int(sys.argv[2]) if len(sys.argv) > 2 else 241
    assert n < ROM_DEPTH, "leave room for the END word"
    os.makedirs(MEM, exist_ok=True)

    main = synthetic_market(n, seed)
    write_hex(main, os.path.join(MEM, "market_data.hex"), ROM_DEPTH)
    write_mif(main, os.path.join(MEM, "market_data.mif"), ROM_DEPTH)
    write_csv(main, os.path.join(MEM, "market_data.csv"))

    small = small_test()
    write_hex(small, os.path.join(MEM, "test_small.hex"), SMALL_DEPTH)
    write_mif(small, os.path.join(MEM, "test_small.mif"), SMALL_DEPTH)
    write_csv(small, os.path.join(MEM, "test_small.csv"))
    print(f"wrote {len(main) - 1} market messages and {len(small) - 1} test messages to {MEM}")
