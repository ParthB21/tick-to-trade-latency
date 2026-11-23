"""
Prints what the board's HEX displays should show at every step of a demo, from the
system model. Use it to check the board during the demo (and as a slide table).

  python demo_table.py ../mem/test_small.hex ../sim/kb_demo_small.txt [--hs 1] [--size 2]

Columns: what you do | market view | bot view | fills view | entry view
  market : best bid, best ask, ROM messages processed (last 2 digits)  (KEY[2] once from bot view)
  bot    : our bid, our ask ("--" = not live)                          (start-up view)
  fills  : b/S last fill side, its price, number of fills              (KEY[2] 5 times)
  entry  : after typing: letter + d + order ID, or Err                 (any key jumps here)
"""
import argparse
from msgfmt import END, read_hex, unpack
from system_model import System, read_script


def two(v, live=True):
    return f"{v:02d}" if live and v >= 0 else "--"


def views(s, kb_status=None):
    r = s.rows[-1] if s.rows else None
    n_rom = sum(1 for x in s.rows if x[1] == 0)
    if r:
        mkt = f"{two(r[3])} {two(r[4])} {n_rom % 100:02d}"
        bot = f"{two(r[6], r[5])} {two(r[8], r[7])}"
    else:
        mkt, bot = f"-- -- {n_rom % 100:02d}", "-- --"
    fills = [x for x in s.rows if x[9] >= 0]
    fv = "F-----" if not fills else f"{'S' if fills[-1][9] else 'b'} {fills[-1][10]:02d} {len(fills) % 1000:03d}"
    return mkt, bot, fv


def entry_view(e, mode_letter):
    if e.status == "ok":
        return f"{mode_letter} d {e.last_id:04d}"
    if e.status == "err":
        return "E r r"
    return "------"


LETTER = {"B": "b", "S": "S", "A": "S", "X": "C", "C": "C", "T": "t"}

if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("hex")
    ap.add_argument("script")
    ap.add_argument("--hs", type=int, default=1)
    ap.add_argument("--size", type=int, default=2)
    a = ap.parse_args()
    s = System(a.hs, a.size, 8, 8)
    pending = read_script(a.script)
    print(f"{'what you do':28s} | {'market':9s} | {'bot':6s} | {'fills':9s} | entry")
    print("-" * 75)

    def typed(n_done):
        while pending and pending[0][0] <= n_done:
            text = pending.pop(0)[1]
            before = len(s.rows)
            s.type_keys(text)
            m, b, f = views(s)
            note = "" if len(s.rows) > before else "  (nothing sent)"
            print(f"{'type ' + text.strip() + ' Enter':28s} | {m:9s} | {b:6s} | {f:9s} | "
                  f"{entry_view(s.entry, LETTER.get(text.strip()[0], '?'))}{note}")

    m, b, f = views(s)
    print(f"{'KEY[0] reset':28s} | {m:9s} | {b:6s} | {f:9s} | ------")
    typed(0)
    n = 0
    for word in read_hex(a.hex):
        if unpack(word)[0] == END:
            m, b, f = views(s)
            print(f"{'KEY[1] (END: LEDR[8] on)':28s} | {m:9s} | {b:6s} | {f:9s} |")
            break
        s.process(word, 0, n)
        n += 1
        m, b, f = views(s)
        print(f"{'KEY[1] -> ROM msg ' + str(n - 1):28s} | {m:9s} | {b:6s} | {f:9s} |")
        typed(n)
