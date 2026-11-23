"""
Checks dashboard_tb frames against the dashboard model (Pierce).
Reads out/dash_cases.txt (one case per line) and out/dash_<n>.hex, renders the
same fake book and inputs, and compares every pixel. Writes out/dash_<n>.png.

Usage (from sim/):  python ../python/check_dashboard.py out
"""
import os
import sys
from msgfmt import N_LEVELS, BID, ASK
from dashboard import read_frame, render, write_png, WIDTH, HEIGHT
from e2e import compare_frames


def fake_qty(side, level):
    """Same formula as the fake book in tb/dashboard_tb.v."""
    return 0 if (level + side) % 5 == 0 else (level * 97 + side * 1234) % 3000


if __name__ == "__main__":
    out = sys.argv[1]
    qty = {side: [fake_qty(side, level) for level in range(N_LEVELS)] for side in (BID, ASK)}
    with open(os.path.join(out, "dash_cases.txt")) as f:
        cases = [tuple(map(int, line.split())) for line in f if line.strip()]
    errors = 0
    for c in cases:
        n, bid_live, bid_px, ask_live, ask_px, position, pnl = c[:7]
        (best_bid, bid_valid, best_ask, ask_valid, msg_count, size, skew,
         fill_count, fill_side, fill_px, fill_qty, reject) = c[7:19]
        panel = dict(best_bid=best_bid, bid_valid=bool(bid_valid), best_ask=best_ask,
                     ask_valid=bool(ask_valid), msg_count=msg_count, size=size, skew=bool(skew),
                     fill_count=fill_count, fill_side=fill_side, fill_px=fill_px, fill_qty=fill_qty,
                     keys=list(c[19:25]), reject=reject, cursor=c[25])
        exp = render(qty, bid_live, bid_px, ask_live, ask_px, position, pnl, panel)
        got = read_frame(os.path.join(out, f"dash_{n}.hex"))
        write_png(got, os.path.join(out, f"dash_{n}.png"))
        diffs = compare_frames(exp, got)
        print(f"case {n}: position {position}, pnl {pnl}: {diffs} pixel mismatches")
        errors += diffs
    if not cases or errors:
        print("FAIL dashboard")
        sys.exit(1)
    print(f"PASS dashboard: {len(cases)} frames x {WIDTH * HEIGHT} pixels")
