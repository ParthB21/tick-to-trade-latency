"""
Turns a frame buffer dumped by tb/dashboard_tb.v ($writememh of the VGA stub,
320 x 240 pixels, one 3-bit RGB value per line: bit 2 red, bit 1 green, bit 0 blue)
into a PNG scaled to 1280 x 720 with nearest-neighbour, which is how the 16:9
monitor stretches the 4:3 VGA output.

Usage (from sim/, after `do run_dashboard.do`):
    python ../docs/figures/frame_to_png.py out/dash_0.hex ../docs/figures/fig22_vga_frame.png
"""
import sys
from PIL import Image

W, H = 320, 240
OUT_W, OUT_H = 1280, 720


def read_frame(path):
    pix = []
    with open(path) as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("//"):
                continue
            pix.append(int(line, 16) if "x" not in line.lower() else 0)
    if len(pix) != W * H:
        raise SystemExit(f"{path}: {len(pix)} pixels, expected {W * H}")
    return pix


def to_image(pix):
    img = Image.new("RGB", (W, H))
    img.putdata([(255 * ((p >> 2) & 1), 255 * ((p >> 1) & 1), 255 * (p & 1)) for p in pix])
    return img.resize((OUT_W, OUT_H), Image.NEAREST)


if __name__ == "__main__":
    src = sys.argv[1] if len(sys.argv) > 1 else "out/dash_0.hex"
    dst = sys.argv[2] if len(sys.argv) > 2 else "fig22_vga_frame.png"
    to_image(read_frame(src)).save(dst)
    print(f"{src} -> {dst} ({OUT_W} x {OUT_H})")
