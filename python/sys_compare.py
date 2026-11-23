"""
Compare the system testbench log (tb/hft_system_tb.v) with the system model
(python/system_model.py), line by line, column by column.

Columns: seq src idx best_bid best_ask bid_live bid_px ask_live ask_px fside fpx fqty position cash pnl
"na" in the hardware log (no P&L tracker in hft_top yet) skips that column.

Usage:  python sys_compare.py ../sim/sys_expected.txt ../sim/sys_out.txt
"""
import sys

COLS = "seq src idx best_bid best_ask bid_live bid_px ask_live ask_px fside fpx fqty position cash pnl".split()
MAX_REPORT = 10


def load(path):
    with open(path) as f:
        return [line.split() for line in f if line.strip()]


def main(exp_path, got_path):
    exp, got = load(exp_path), load(got_path)
    errors, skipped = 0, set()
    for e, g in zip(exp, got):
        bad = []
        for name, ev, gv in zip(COLS, e, g):
            if gv == "na":
                skipped.add(name)
            elif ev != gv:
                bad.append(f"{name} expected {ev} got {gv}")
        if bad:
            errors += 1
            if errors <= MAX_REPORT:
                print(f"MISMATCH seq {e[0]} (src {'kbd' if e[1] == '1' else 'rom'} #{e[2]}): " + ", ".join(bad))
    if len(exp) != len(got):
        errors += 1
        print(f"LENGTH MISMATCH: model {len(exp)} messages, hardware {len(got)}")

    n_kbd = sum(1 for e in exp if e[1] == "1")
    n_fill = sum(1 for e in exp if e[9] != "-1")
    print(f"{len(exp)} messages ({len(exp) - n_kbd} ROM + {n_kbd} keyboard), {n_fill} fills in the model")
    if skipped:
        print(f"not checked (hardware logs 'na'): {', '.join(sorted(skipped, key=COLS.index))}")
    if errors == 0:
        print("PASS: hft_top matches the chained Python system model on every message")
    else:
        print(f"FAIL: {errors} mismatching messages")
        sys.exit(1)


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
