#!/usr/bin/env python3
"""Generates Sprites.js (pixel art for Podbay) and a preview PNG.

    tools/sprites.py            write Sprites.js
    tools/sprites.py --preview  also write tools/preview.png (needs magick)

Sprites are rows of characters; each character is a palette role that the
QML side maps to theme colours:

    .  transparent        o  outline           w  body (foreground)
    h  highlight          s  shade             m  mesh / cushion / grill
    k  deep dark          a  accent (LEDs, crown)
"""
import json
import math
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))


class Grid:
    def __init__(self, w, h):
        self.w, self.h = w, h
        self.px = [["."] * w for _ in range(h)]

    def set(self, x, y, c):
        if 0 <= x < self.w and 0 <= y < self.h:
            self.px[y][x] = c

    def get(self, x, y):
        return self.px[y][x] if 0 <= x < self.w and 0 <= y < self.h else "."

    def shape(self, inside, fill, outline="o"):
        """Fill every pixel where inside(x, y); pixels on the edge get outline."""
        mask = [[inside(x, y) for x in range(self.w)] for y in range(self.h)]
        for y in range(self.h):
            for x in range(self.w):
                if not mask[y][x]:
                    continue
                edge = any(not (0 <= x + dx < self.w and 0 <= y + dy < self.h and mask[y + dy][x + dx])
                           for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)))
                c = outline if (edge and outline) else (fill(x, y) if callable(fill) else fill)
                if c:
                    self.set(x, y, c)
        return mask

    def rows(self):
        return ["".join(r) for r in self.px]


def rrect(x0, y0, x1, y1, r):
    def inside(x, y):
        if not (x0 <= x <= x1 and y0 <= y <= y1):
            return False
        cx = min(max(x, x0 + r), x1 - r)
        cy = min(max(y, y0 + r), y1 - r)
        return (x - cx) ** 2 + (y - cy) ** 2 <= r * r + 0.5
    return inside


def ellipse(cx, cy, rx, ry):
    return lambda x, y: ((x - cx) / rx) ** 2 + ((y - cy) / ry) ** 2 <= 1.0


# ---- AirPods Max (34 x 31) ------------------------------------------------

def airpods_max():
    g = Grid(34, 31)
    # Headband canopy: an arch of mesh under a steel frame.
    outer = ellipse(16.5, 12.0, 13.4, 11.8)
    inner = ellipse(16.5, 12.0, 9.6, 7.4)
    frame = ellipse(16.5, 12.0, 12.2, 10.6)
    g.shape(lambda x, y: y <= 11 and outer(x, y) and not inner(x, y),
            lambda x, y: "s" if not frame(x, y) else "m" if (x + y) % 2 else "k")
    # Telescoping arms.
    for x0 in (4, 28):
        g.shape(lambda x, y, x0=x0: x0 <= x <= x0 + 1 and 9 <= y <= 14,
                lambda x, y, x0=x0: "h" if x == x0 else "s", outline=None)
    # Ear cups: aluminium shell, cushion on the inner side.
    def cup(x0, x1, cushion_left):
        g.shape(rrect(x0, 14, x1, 30, 4),
                lambda x, y: ("m" if (x <= x0 + 2 if cushion_left else x >= x1 - 2)
                              else "h" if (x == x1 - 3 if cushion_left else x == x0 + 1) and y < 27
                              else "s" if y >= 27 else "w"))
    cup(1, 12, False)
    cup(21, 32, True)
    # Digital Crown and noise-control button on the right cup.
    g.set(29, 13, "a"); g.set(30, 13, "a"); g.set(29, 12, "o"); g.set(30, 12, "o")
    g.set(24, 13, "s"); g.set(25, 13, "s")
    return g.rows()


# ---- AirPods Pro: one bud (12 x 18), the case (26 x 20) ---------------------

def bud(mirror=False):
    g = Grid(13, 18)
    head = ellipse(7.0, 5.0, 5.2, 4.6)
    tip = ellipse(1.8, 5.0, 2.0, 2.3)
    stem = rrect(7, 7, 10, 17, 1)
    g.shape(lambda x, y: tip(x, y) and not head(x, y), "s")
    g.shape(lambda x, y: head(x, y) or stem(x, y),
            lambda x, y: "h" if (x == 4 and 3 <= y <= 6) or (x == 8 and y >= 9) else "s" if (x >= 9 and y >= 11) else "w")
    # Sensor and stem grill.
    g.set(7, 2, "k"); g.set(8, 2, "k")
    g.set(8, 15, "m"); g.set(9, 15, "m")
    rows = g.rows()
    return [r[::-1] for r in rows] if mirror else rows


def case(lid):
    """lid: 0 closed, 1 ajar, 2 open."""
    g = Grid(26, 22)
    body = rrect(1, 8, 24, 21, 6)
    g.shape(body, lambda x, y: "s" if y >= 19 else "h" if (x == 3 and y <= 16) else "w")
    if lid == 0:
        lid_shape = rrect(1, 4, 24, 12, 5)
        g.shape(lambda x, y: lid_shape(x, y) and y <= 9,
                lambda x, y: "h" if y == 5 else "w")
        for x in range(2, 24):
            g.set(x, 9, "o")
    else:
        # Body top is open: show the bud wells.
        for x in range(4, 22):
            g.set(x, 8, "o")
        for cx in (8, 17):
            g.shape(ellipse(cx, 9.5, 3.0, 1.6), "k", outline=None)
        if lid == 1:
            lid_shape = rrect(1, 1, 24, 7, 3)
            g.shape(lid_shape, lambda x, y: "h" if y == 2 else "w")
        else:
            lid_shape = rrect(3, 0, 22, 6, 3)
            g.shape(lid_shape, lambda x, y: "m" if y >= 4 else "s")
    g.set(12, 15, "a"); g.set(13, 15, "a")  # status light
    return g.rows()


# ---- Bar icons (13 x 13) --------------------------------------------------

def icon_max():
    g = Grid(13, 13)
    outer = ellipse(6, 6.5, 5.6, 5.8)
    inner = ellipse(6, 6.5, 3.6, 3.8)
    g.shape(lambda x, y: y <= 6 and outer(x, y) and not inner(x, y), "w", outline=None)
    for x0 in (0, 9):
        g.shape(rrect(x0, 6, x0 + 3, 12, 1), "w", outline=None)
    return g.rows()


def icon_pro():
    g = Grid(13, 13)
    for cx, sx in ((3.0, 4), (9.0, 7)):
        g.shape(lambda x, y, cx=cx, sx=sx: ellipse(cx, 2.8, 2.6, 2.4)(x, y) or (sx <= x <= sx + 1 and 3 <= y <= 11),
                "w", outline=None)
    return g.rows()


def build():
    sprites = {
        "max": airpods_max(),
        "budL": bud(),
        "budR": bud(mirror=True),
        "case0": case(0),
        "case1": case(1),
        "case2": case(2),
        "iconMax": icon_max(),
        "iconPro": icon_pro(),
    }
    for name, rows in sprites.items():
        assert len({len(r) for r in rows}) == 1, name
    return sprites


def write_js(sprites):
    out = os.path.join(HERE, "..", "Sprites.js")
    with open(out, "w") as f:
        f.write(".pragma library\n\n// Generated by tools/sprites.py; edit that, not this.\n")
        f.write("// Palette roles: . o w h s m k a (see tools/sprites.py)\n\n")
        for name, rows in sprites.items():
            f.write("var %s = %s\n\n" % (name, json.dumps(rows, indent=2)))
    return out


def preview(sprites, scale=8):
    pal = {".": (28, 28, 30), "o": (88, 88, 92), "w": (245, 245, 247), "h": (255, 255, 255),
           "s": (190, 190, 196), "m": (120, 120, 126), "k": (40, 40, 44), "a": (255, 159, 10)}
    names = ["max", "budL", "budR", "case0", "case1", "case2", "iconMax", "iconPro"]
    gap = 4
    W = sum(len(sprites[n][0]) + gap for n in names)
    H = max(len(sprites[n]) for n in names)
    img = [[pal["."]] * W for _ in range(H)]
    x0 = 0
    for n in names:
        for y, row in enumerate(sprites[n]):
            for x, c in enumerate(row):
                img[y][x0 + x] = pal[c]
        x0 += len(sprites[n][0]) + gap
    ppm = os.path.join(HERE, "preview.ppm")
    with open(ppm, "wb") as f:
        f.write(b"P6 %d %d 255\n" % (W, H))
        f.write(bytes(v for row in img for px in row for v in px))
    png = os.path.join(HERE, "preview.png")
    subprocess.run(["magick", ppm, "-scale", "%d%%" % (scale * 100), png], check=True)
    os.remove(ppm)
    return png


if __name__ == "__main__":
    s = build()
    print(write_js(s))
    if "--preview" in sys.argv:
        print(preview(s))
