#!/usr/bin/env python3
"""Generates the fog sprite set (programmer art for the pack artist
to replace):

  assets/sprites/ground/fog/tile_ground_fog.png
      The deck: ONE 128x64 tile whose fine grain is PERIODIC with
      the tile — the texture wraps, so every cell samples the same
      pattern at the same world-anchored phase and adjacent tiles
      continue each other seamlessly (the opaque skirt included: a
      skirt pixel is the periodic continuation of what it covers).
      This is what removes the per-tile borders that read as a
      grid. The grain stays fine (well under a cell) so the one-cell
      period never shows. The alpha mask is the water tile's own
      chamfer-dilated diamond, matching every other ground tile.

  assets/sprites/fog/wisp_fog_{a,b,c}.png
      Soft cloud sprites — radial falloff eaten by noise, feathered
      fully transparent edges — drawn two to three cells wide over
      fog cells at low density. Density and overlap are what read
      as "fog"; the deck underneath is near-uniform.
"""

import random

from PIL import Image, ImageFilter

# --- The deck: one periodic fine-grain cloud tile. -------------------
W, H = 128, 64
BASE = (217, 228, 222)
SHADE = (201, 216, 208)

rnd = random.Random(5)
grain = Image.new("L", (W, H))
for _ in range(320):
    grain.putpixel(
        (rnd.randrange(W), rnd.randrange(H)), rnd.randrange(110, 210)
    )
grain = grain.filter(ImageFilter.GaussianBlur(1.2))
# Wrap-blur: average the blurred grain with its shifted copies so the
# result is exactly periodic — edges continue into each other.
periodic = Image.new("L", (W, H))
for dx in (-W, 0, W):
    for dy in (-H, 0, H):
        if dx == 0 and dy == 0:
            continue
        periodic.paste(
            grain.crop((
                max(0, -dx), max(0, -dy),
                W - max(0, dx), H - max(0, dy),
            )),
            (max(0, dx), max(0, dy)),
        )
periodic = Image.blend(grain, periodic, 0.5).filter(
    ImageFilter.GaussianBlur(0.8)
)

water = Image.open("assets/sprites/ground/water/tile_ground_water.png")
alpha = water.getchannel("A")
deck = Image.new("RGBA", (W, H))
for y in range(H):
    for x in range(W):
        g = periodic.getpixel((x, y))
        t = (g - 128) / 127 * 0.10
        deck.putpixel(
            (x, y),
            (
                max(0, min(255, int(BASE[0] * (1 - t) + SHADE[0] * t))),
                max(0, min(255, int(BASE[1] * (1 - t) + SHADE[1] * t))),
                max(0, min(255, int(BASE[2] * (1 - t) + SHADE[2] * t))),
                alpha.getpixel((x, y)),
            ),
        )

import os

os.makedirs("assets/sprites/ground/fog", exist_ok=True)
deck.save("assets/sprites/ground/fog/tile_ground_fog.png")
print("assets/sprites/ground/fog/tile_ground_fog.png written")


# --- The wisps: soft, noise-eaten cloud sprites. ---------------------
def make_wisp(radius_world, seed):
    # Art is 2x world density (renderScale 0.5).
    size = radius_world * 2 * 2
    noise = Image.new("L", (size, size))
    r2 = random.Random(seed)
    for _ in range(size * size // 12):
        noise.putpixel(
            (r2.randrange(size), r2.randrange(size)), r2.randrange(256)
        )
    noise = (
        noise.resize((size // 2, size // 2), Image.BILINEAR)
        .resize((size, size), Image.BILINEAR)
        .filter(ImageFilter.GaussianBlur(radius_world * 0.22))
    )
    # The blur pulls the speckle toward its mean; stretch it back to
    # the full range so the wisp keeps its dense core and open holes.
    lo, hi = noise.getextrema()
    if hi > lo:
        noise = noise.point(lambda v: int((v - lo) * 255 / (hi - lo)))
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    half = size / 2 - 8
    for y in range(size):
        dy = (y - size / 2) / half
        for x in range(size):
            dx = (x - size / 2) / half
            fall = 1 - (dx * dx + dy * dy)
            if fall <= 0:
                continue
            n = noise.getpixel((x, y)) / 255
            # Thresholded noise: dense cores and open holes, so a
            # wisp reads as a torn cloud, and overlapping wisps do
            # not stack into a uniform haze.
            core = max(0.0, min(1.0, (n - 0.30) / 0.45))
            core = core * core * (3 - 2 * core)
            mask = fall * (0.22 + 0.68 * core)
            if mask < 0.05:
                continue
            f = y / (size - 1)
            img.putpixel(
                (x, y),
                (
                    int(238 * (1 - f) + 224 * f),
                    int(246 * (1 - f) + 235 * f),
                    int(242 * (1 - f) + 228 * f),
                    int(235 * min(1, mask)),
                ),
            )
    return img


os.makedirs("assets/sprites/fog", exist_ok=True)
for variant, (radius, seed) in (("a", (64, 1)), ("b", (88, 2)), ("c", (110, 3))):
    path = f"assets/sprites/fog/wisp_fog_{variant}.png"
    make_wisp(radius, seed).save(path)
    print(path, "written")
