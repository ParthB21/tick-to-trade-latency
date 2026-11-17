"""
Compare the ModelSim output against the Python reference model, line by line.

Usage:  python compare.py ../sim/expected.txt ../sim/sim_out.txt
"""
import sys


def load(path):
    with open(path) as f:
        return [tuple(map(int, line.split())) for line in f if line.strip()]


exp, got = load(sys.argv[1]), load(sys.argv[2])
errors = 0
for e, g in zip(exp, got):
    if e != g:
        errors += 1
        if errors <= 10:
            print(f"MISMATCH at msg {e[0]}: expected bid={e[1]} ask={e[2]}, "
                  f"hardware bid={g[1]} ask={g[2]}")
if len(exp) != len(got):
    errors += 1
    print(f"LENGTH MISMATCH: expected {len(exp)} lines, hardware gave {len(got)}")

if errors == 0:
    print(f"PASS: all {len(exp)} messages match the Python reference model")
else:
    print(f"FAIL: {errors} mismatches")
    sys.exit(1)
