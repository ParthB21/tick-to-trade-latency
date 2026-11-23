"""
Python reference ("golden") model of the order book.

It replays the same ROM file the FPGA uses and, after every message, writes:
    msg_index best_bid best_ask
(best_bid = -1 if there are no bids, best_ask = -1 if there are no asks)

The Verilog testbench writes the same format, and compare.py checks they match.

Usage:  python ref_model.py ../mem/market_data.hex ../sim/expected.txt
"""
import sys
from msgfmt import ADD, CANCEL, TRADE, END, BID, N_LEVELS, read_hex, unpack


class OrderBook:
    def __init__(self):
        self.qty = [[0] * N_LEVELS, [0] * N_LEVELS]   # qty[side][price]
        self.orders = {}                               # oid -> [side, price, qty]

    def apply(self, word, src=0):
        """src = 0 ROM feed, 1 keyboard. The arbiter adds src as bit 10 of the
        order ID, so the two sources have separate ID spaces (M2)."""
        mtype, side, price, oid, qty = unpack(word)
        oid |= src << 10
        if mtype == ADD:
            # Hardware overwrites the table entry; a well-formed feed never
            # reuses a live ID, and the generator guarantees that.
            self.orders[oid] = [side, price, qty]
            self.qty[side][price] = min(self.qty[side][price] + qty, 8191)
        elif mtype in (CANCEL, TRADE):
            if oid not in self.orders:
                return None                            # unknown ID: ignored
            s, p, q = self.orders[oid]
            dec = q if mtype == CANCEL else min(qty, q)
            self.qty[s][p] = max(self.qty[s][p] - dec, 0)
            if q - dec == 0:
                del self.orders[oid]
            else:
                self.orders[oid][2] = q - dec
            if mtype == TRADE:
                return (s, p, dec)                     # trade event (for M2)
        return None

    def best_bid(self):
        for p in range(N_LEVELS - 1, -1, -1):
            if self.qty[BID][p] > 0:
                return p
        return -1

    def best_ask(self):
        for p in range(N_LEVELS):
            if self.qty[1][p] > 0:
                return p
        return -1


def run(hex_path):
    book, rows = OrderBook(), []
    for i, w in enumerate(read_hex(hex_path)):
        if unpack(w)[0] == END:
            break
        book.apply(w)
        rows.append((i, book.best_bid(), book.best_ask()))
    return rows, book


if __name__ == "__main__":
    rows, _ = run(sys.argv[1])
    with open(sys.argv[2], "w") as f:
        for r in rows:
            f.write(f"{r[0]} {r[1]} {r[2]}\n")
    print(f"reference model: {len(rows)} messages -> {sys.argv[2]}")
