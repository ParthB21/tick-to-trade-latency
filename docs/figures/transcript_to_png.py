"""
Renders saved test transcripts (ModelSim `vsim -c` output and the Python checkers)
as terminal-style PNGs for the report. Lines are copied verbatim from the logs;
only the lines between the markers given below are kept (crop to what matters).

Usage:  python transcript_to_png.py <logdir> <outdir>
The logs are the full stdout of each run (see FIGURES.md for the exact commands).
"""
import os
import sys
from PIL import Image, ImageDraw, ImageFont

BG, FG, CMD, OK, BAD = (24, 24, 24), (225, 225, 225), (120, 190, 255), (110, 220, 110), (255, 110, 110)
FONT_SIZE, PAD, MIN_W = 30, 28, 1600


def font():
    for name in ("consola.ttf", "DejaVuSansMono.ttf", "cour.ttf"):
        try:
            return ImageFont.truetype(name, FONT_SIZE)
        except OSError:
            pass
    return ImageFont.load_default()


def clip(path, start=None, stop=None, grep=None):
    """Lines of a log from the first one containing `start` to the first containing `stop` (inclusive)."""
    with open(path, encoding="utf-8-sig") as f:
        lines = [l.rstrip() for l in f]
    if grep:
        return [l for l in lines if any(g in l for g in grep)]
    i = next(k for k, l in enumerate(lines) if start in l) if start else 0
    j = next(k for k, l in enumerate(lines) if k >= i and stop in l) if stop else len(lines) - 1
    return [l for l in lines[i:j + 1] if l.strip() not in ("", "#")]


def render(blocks, out):
    """blocks: list of (command, [lines])."""
    fnt = font()
    rows = []
    for cmd, lines in blocks:
        rows.append(("$ " + cmd, CMD))
        for l in lines:
            col = OK if ("PASS" in l and "FAIL" not in l.replace("0 failed", "")) else (BAD if "FAIL" in l else FG)
            rows.append((l, col))
        rows.append(("", FG))
    rows = rows[:-1]
    lh = int(FONT_SIZE * 1.3)
    w = max(MIN_W, max(int(fnt.getlength(t)) for t, _ in rows) + 2 * PAD)
    img = Image.new("RGB", (w, len(rows) * lh + 2 * PAD), BG)
    d = ImageDraw.Draw(img)
    for k, (t, c) in enumerate(rows):
        d.text((PAD, PAD + k * lh), t, fill=c, font=fnt)
    img.save(out)
    print("wrote", out, img.size)


if __name__ == "__main__":
    L, O = sys.argv[1], sys.argv[2]
    lg = lambda n: os.path.join(L, n + ".log")
    VS = "vsim -c work.{} -do \"run -all; quit -f\""
    figs = {
        "fig03_order_book_tests.png": [
            (VS.format("order_book_tb"), clip(lg("order_book"), "reset + RAM clear", "checks passed"))],
        "fig06_matching_tests.png": [
            (VS.format("matching_engine_tb"), clip(lg("matching"), "named cases (t", "ALL PASS"))],
        "fig10_arbiter_tests.png": [
            (VS.format("order_arbiter_tb"), clip(lg("arbiter"), "case 1 starts", "checks passed"))],
        "fig13_order_entry_tests.png": [
            (VS.format("order_entry_tb"), clip(lg("entry"), "part 1 starts", "checks passed"))],
        "fig14_system_hs1.png": [
            ("python ../python/system_model.py ../mem/market_data.hex kb_script.txt sys_expected.txt "
             "--hs 1 --kb-hex vectors/sys_kb.hex", clip(lg("sysmodel_hs1"), "system model", "system model")),
            (VS.format("hft_system_tb"), clip(lg("system_hs1"), "reset done", "messages logged")),
            ("python ../python/sys_compare.py sys_expected.txt sys_out.txt", clip(lg("cmp_hs1"), "messages", "PASS"))],
        "fig19_pnl_tests.png": [
            ("python ../python/gen_vectors.py", clip(lg("gen_vectors"), "strategy", "pnl tracker")),
            (VS.format("pnl_tracker_tb"), clip(lg("pnl"), grep=["PASS", "FAIL", "MISMATCH"]))],
        "fig21_strategy_tests.png": [
            ("python ../python/gen_vectors.py", clip(lg("gen_vectors"), "strategy", "pnl tracker")),
            (VS.format("strategy_tb"), clip(lg("strategy"), grep=["PASS", "FAIL", "MISMATCH"]))],
        "fig16_risk_gate_tests.png": [
            ("python ../python/gen_vectors.py", clip(lg("gen_vectors"), "strategy", "pnl tracker")),
            (VS.format("risk_gate_tb"), clip(lg("risk"), grep=["PASS", "FAIL", "MISMATCH"]))],
        "fig23_book_cursor_tests.png": [
            (VS.format("book_cursor_tb"), clip(lg("cursor"), grep=["PASS", "FAIL"]))],
        "fig24_e2e.png": [
            (VS.format("hft_top_tb"), clip(lg("hft_top"), "replay done", "PASS")),
            ("python ../python/e2e.py ../mem/market_data.hex out", clip(lg("e2e"), "orders:", "PASS"))],
        "fig25_system_skew.png": [
            ("python ../python/system_model.py ../mem/market_data.hex kb_script.txt sys_expected_skew.txt "
             "--hs 1 --skew-k 2", clip(lg("sysmodel_skew"), "system model", "system model")),
            ("vsim -c -gSKEW=1 -gOUT_FILE=sys_out_skew.txt work.hft_system_tb -do \"run -all; quit -f\"",
             clip(lg("system_skew"), "reset done", "messages logged")),
            ("python ../python/sys_compare.py sys_expected_skew.txt sys_out_skew.txt",
             clip(lg("cmp_skew"), "messages", "PASS"))],
    }
    for name, blocks in figs.items():
        render(blocks, os.path.join(O, name))
