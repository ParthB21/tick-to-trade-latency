"""Crop a captured ModelSim Wave window to the wave pane (drop title bar, menus, toolbars)."""
import sys
from PIL import Image

src, dst = sys.argv[1], sys.argv[2]
im = Image.open(src).convert("RGB")
w, h = im.size


def grey(p):
    return p[0] == p[1] == p[2] and 90 <= p[0] <= 200


# top of the wave pane: the right side is black and the signal-name pane (left) is grey
top = next(y for y in range(h - 30)
           if all(im.getpixel((int(w * 0.8), y + k)) == (0, 0, 0) for k in range(6))
           and grey(im.getpixel((int(w * 0.06), y + 25))))
out = im.crop((8, top, w - 8, h - 8))
out.save(dst)
print(dst, out.size)
