"""
End-to-end reference model: ROM -> order book (Parth's model) -> strategy -> risk gate
-> matching engine (Parth) -> P&L tracker, then the dashboard frame. Checks the
hft_top_tb outputs against it. Same per-message timing as python/system_model.py:
the strategy snapshots the position before this message's fill, the risk gate sees
the position after it.

  out/orders.txt : one line per order the risk gate sent, first line = config
  out/frame.hex  : VGA frame buffer after the replay
Writes out/expected.png and out/sim.png so you can look at both.

Usage (from sim/):  python ../python/e2e.py ../mem/market_data.hex out
"""
import os
import sys
from msgfmt import END, read_hex, unpack
from ref_model import OrderBook
from strategy import strategy
from risk import RiskState, risk_step
from pnl import PnlState, pnl_step, BUY
from matching import MatchingEngine
from dashboard import read_frame, render, write_png, WIDTH, HEIGHT

MAX_REPORT = 10
NO_FILL = (0, BUY, 0, 0)


def read_config(line):
    return {k: int(v) for k, v in (item.split("=") for item in line.split()[1:])}


def expected_orders(hex_path, cfg):
    book, st, pnl, me, rows = OrderBook(), RiskState(), PnlState(), MatchingEngine(), []
    for i, word in enumerate(read_hex(hex_path)):
        if unpack(word)[0] == END:
            break
        trade = book.apply(word)
        bb, ba = book.best_bid(), book.best_ask()
        # the hardware priority encoder outputs 0 for an empty side
        top = (max(bb, 0), bb >= 0, max(ba, 0), ba >= 0)
        pos_before = pnl.position                    # strategy snapshot (book done cycle)
        fill = me.on_trade(*trade) if trade else None
        pnl = pnl_step(pnl, (1, fill.side, fill.px, fill.qty) if fill else NO_FILL, top)
        ok, bid, ask, size = strategy(top[0], top[1], top[2], top[3], cfg["half_spread"], cfg["size"],
                                      pos_before, cfg["skew_k"])
        st = risk_step(st, False, (1, ok, bid, ask, size), top, pnl.position, cfg["max_pos"], cfg["max_size"])
        me.on_order(st.bid_live, st.bid_px, st.ask_live, st.ask_px, st.size)
        rows.append((i, int(st.bid_live), st.bid_px, int(st.ask_live), st.ask_px, st.size))
    return rows, book, st, pnl


def compare_orders(exp, got):
    errors = 0
    for e, g in zip(exp, got):
        if e != g:
            errors += 1
            if errors <= MAX_REPORT:
                print(f"ORDER MISMATCH msg {e[0]}: expected bid {e[1]}@{e[2]} ask {e[3]}@{e[4]} size {e[5]}, "
                      f"hardware bid {g[1]}@{g[2]} ask {g[3]}@{g[4]} size {g[5]}")
    if len(exp) != len(got):
        errors += 1
        print(f"ORDER COUNT MISMATCH: expected {len(exp)}, hardware sent {len(got)}")
    return errors


def compare_frames(exp, got):
    diffs = [(x, y) for y in range(HEIGHT) for x in range(WIDTH) if exp[y][x] != got[y][x]]
    for x, y in diffs[:MAX_REPORT]:
        print(f"PIXEL MISMATCH ({x},{y}): expected {exp[y][x]:03b}, hardware {got[y][x]:03b}")
    return len(diffs)


if __name__ == "__main__":
    hex_path, out = sys.argv[1], sys.argv[2]
    with open(os.path.join(out, "orders.txt")) as f:
        lines = [line for line in f if line.strip()]
    cfg = read_config(lines[0])
    got = [tuple(map(int, line.split())) for line in lines[1:]]

    exp, book, st, pnl = expected_orders(hex_path, cfg)
    order_errors = compare_orders(exp, got)

    settled_pnl = pnl.cash + pnl.position * pnl.mark   # the register has settled long before the frame dump
    exp_frame = render(book.qty, st.bid_live, st.bid_px, st.ask_live, st.ask_px, pnl.position, settled_pnl)
    sim_frame = read_frame(os.path.join(out, "frame.hex"))
    write_png(exp_frame, os.path.join(out, "expected.png"))
    write_png(sim_frame, os.path.join(out, "sim.png"))
    pixel_errors = compare_frames(exp_frame, sim_frame)

    live = sum(1 for r in exp if r[1] and r[3])
    print(f"orders: {len(exp)} expected, {len(got)} from hardware, {order_errors} mismatches "
          f"({live} with both sides live)")
    print(f"frame : {WIDTH * HEIGHT} pixels, {pixel_errors} mismatches")
    if order_errors or pixel_errors:
        print("FAIL e2e")
        sys.exit(1)
    print("PASS e2e: hardware matches the chained Python model")
