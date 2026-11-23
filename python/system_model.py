"""
System reference model (M2): every block's Python model, chained the same way
hft_top.v chains the hardware.

    ROM feed ----\\
                  arbiter -> order book -> strategy -> risk gate
    keyboard ----/               |            ^           | our quotes
      (order entry)              |            | position  v
                                 +--trade--> matching engine --fill--> P&L (Pierce)
                                              position -> strategy (skew) and risk gate (limits)

It replays the market data plus a scripted list of keyboard input and writes one
line per message the order book processed (ROM or keyboard):

    seq src idx best_bid best_ask bid_live bid_px ask_live ask_px fside fpx fqty position cash pnl

  seq      : 0, 1, 2 ... over all messages
  src      : 0 = ROM feed, 1 = keyboard
  idx      : ROM message index (ROM rows) or keyboard message number (keyboard rows)
  best_bid / best_ask : -1 = that side is empty
  bid_*/ask_* : our quotes after the risk gate (the order_valid that follows this message)
  fside fpx fqty : the fill this message caused (-1 -1 0 = no fill; fside 0 bought, 1 sold)
  position cash pnl : P&L tracker after the fill (pnl = cash + position * floor(mid))

Keyboard script (one command per line, Enter is added at the end of each line):
    <after_n> <keys>        typed after the n-th ROM message has been processed
    # comment
  keys: digits, B S A X C T, space;  ! = Esc, < = Backspace, ~ = keypad Enter

Timing inside one message, matching the hardware (book done = cycle d):
  d    book applies the message; strategy snapshots best bid/ask AND position (before this fill)
  d+1  matching engine: trade vs the quote resting before this message -> fill
  d+2  P&L has the new position; risk gate checks the quote with the NEW position
  d+3  order_valid: new quotes, matching engine reloads its remaining size

Usage:
  python system_model.py ../mem/market_data.hex ../sim/kb_script.txt ../sim/sys_expected.txt
         [--hs 1] [--size 2] [--max-pos 8] [--max-size 8] [--skew-k 0]
         [--kb-hex ../sim/vectors/sys_kb.hex]
  --skew-k   : 0 = SW[2] off, 2 = SW[2] on (hft_top's SKEW_K)
  --kb-hex   : also write the PS/2 bytes for the system testbench
"""
import argparse
from msgfmt import END, read_hex, unpack
from ref_model import OrderBook
from strategy import strategy
from risk import RiskState, risk_step
from matching import MatchingEngine
from pnl import PnlState, pnl_step, BUY
from order_entry import OrderEntry, char_to_key, text_to_scan_bytes

NO_FILL = (-1, -1, 0)


def read_script(path):
    """-> list of (after_n, text). Enter is appended to every line."""
    cmds = []
    if not path:
        return cmds
    with open(path) as f:
        for line in f:
            line = line.rstrip("\r\n")
            if not line.strip() or line.lstrip().startswith("#"):
                continue
            n, _, keys = line.strip().partition(" ")
            cmds.append((int(n), keys.strip() + "\n"))
    return sorted(cmds, key=lambda c: c[0])          # stable: keeps the file order within one n


class System:
    def __init__(self, hs, size, max_pos, max_size, skew_k=0):
        self.cfg = (hs, size, max_pos, max_size, skew_k)
        self.book, self.risk, self.me, self.pnl = OrderBook(), RiskState(), MatchingEngine(), PnlState()
        self.entry = OrderEntry()
        self.rows, self.seq, self.kb_count = [], 0, 0

    def top(self):
        bb, ba = self.book.best_bid(), self.book.best_ask()
        return bb, ba, (max(bb, 0), bb >= 0, max(ba, 0), ba >= 0)  # encoder gives 0 for an empty side

    def process(self, word, src, idx):
        hs, size, max_pos, max_size, skew_k = self.cfg
        trade = self.book.apply(word, src)
        bb, ba, top = self.top()
        pos_before = self.pnl.position                              # strategy snapshot at done
        fill = self.me.on_trade(*trade) if trade else None
        fill_in = (1, fill.side, fill.px, fill.qty) if fill else (0, BUY, 0, 0)
        self.pnl = pnl_step(self.pnl, fill_in, top)
        ok, bid, ask, sz = strategy(*top, hs, size, pos_before, skew_k)
        self.risk = risk_step(self.risk, False, (1, ok, bid, ask, sz), top,
                              self.pnl.position, max_pos, max_size)  # risk sees the new position
        r = self.risk
        self.me.on_order(r.bid_live, r.bid_px, r.ask_live, r.ask_px, r.size)
        f = (fill.side, fill.px, fill.qty) if fill else NO_FILL
        p = self.pnl
        self.rows.append((self.seq, src, idx, bb, ba, int(r.bid_live), r.bid_px, int(r.ask_live),
                          r.ask_px, *f, p.position, p.cash, p.cash + p.position * p.mark))
        self.seq += 1

    def type_keys(self, text):
        for ch in text:
            _, _, top = self.top()
            k = char_to_key(ch)
            word = self.entry.key(k, top) if k is not None else None
            if word is not None:
                self.process(word, 1, self.kb_count)
                self.kb_count += 1


def run(hex_path, script, **cfg):
    sysm = System(**cfg)
    cmds = read_script(script)
    pending = list(cmds)
    n = 0

    def flush(n_done):
        while pending and pending[0][0] <= n_done:
            sysm.type_keys(pending.pop(0)[1])

    flush(0)
    for word in read_hex(hex_path):
        if unpack(word)[0] == END:
            break
        sysm.process(word, 0, n)
        n += 1
        flush(n)
    flush(1 << 30)                                     # commands after the END
    return sysm, cmds


def write_kb_hex(cmds, path):
    """One word per PS/2 byte: [31:16] after_n, [7:0] byte. Ends with FFFFFFFF."""
    with open(path, "w") as f:
        for n, text in cmds:
            for b in text_to_scan_bytes(text):
                f.write(f"{(n << 16) | b:08X}\n")
        f.write("FFFFFFFF\n")


def write_rows(rows, path):
    with open(path, "w") as f:
        for r in rows:
            f.write(" ".join(str(v) for v in r) + "\n")


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("hex")
    ap.add_argument("script")
    ap.add_argument("out")
    ap.add_argument("--hs", type=int, default=1)
    ap.add_argument("--size", type=int, default=2)
    ap.add_argument("--max-pos", type=int, default=8)
    ap.add_argument("--max-size", type=int, default=8)
    ap.add_argument("--skew-k", type=int, default=0)
    ap.add_argument("--kb-hex")
    a = ap.parse_args()
    s, cmds = run(a.hex, a.script, hs=a.hs, size=a.size, max_pos=a.max_pos, max_size=a.max_size,
                  skew_k=a.skew_k)
    write_rows(s.rows, a.out)
    if a.kb_hex:
        write_kb_hex(cmds, a.kb_hex)
    fills = sum(1 for r in s.rows if r[9] >= 0)
    last = s.rows[-1] if s.rows else None
    print(f"system model: {len(s.rows)} messages ({s.kb_count} from the keyboard, "
          f"{s.entry.errors} keyboard entries rejected), {fills} fills, "
          f"final position {s.pnl.position}, cash {s.pnl.cash}, pnl {last[-1] if last else 0} -> {a.out}")
