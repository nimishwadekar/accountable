#!/usr/bin/env python3
"""Previews the sprite-based wispy fog look over the real render
(fog_in_game.png) — what the game would show if the fog art set were:

  - one periodic fine-grain deck tile (seamless, no cell borders),
  - large soft wisp sprites at low alpha, hash-placed on fog cells,
  - creep wisps over charted cells near the boundary,
  - boundary fog cells: a terrain underlay (copied from the charted
    neighbour in this preview; a real terrain tile in the game) under
    a feathered fog edge overlay — the fog's alpha ramps from full
    (interior, seamless with the deck) to a thin haze at the boundary
    line, so terrain shows through the fringe and the hard edge is
    gone. In the game this overlay is the 12-shape edge/corner/
    quarter sprite set the shore system already uses, drawn as PNGs.

Everything here mirrors what sprite placement would draw; only the
pixels are composited in PIL for preview purposes.
"""

import json
import random

from PIL import Image, ImageChops, ImageDraw, ImageFilter

W, H = 3900, 2400
CAM_X, CAM_Y = W / 2, H / 2 - 128

authored = set()
for key in json.load(open("assets/content/terrain.json"))["parcels"]:
    x, y = (int(v) for v in key.split(","))
    authored.add((x, y))


def parcel_of(c, r):
    return (c // 8, r // 8)


def cell_center(c, r):
    return ((c - r) * 32 + CAM_X, (c + r) * 16 + CAM_Y)


cells = []
for c in range(-90, 100):
    for r in range(-90, 100):
        x, y = cell_center(c, r)
        if -80 <= x <= W + 80 and -80 <= y <= H + 80:
            cells.append((c, r))
fog = {(c, r) for (c, r) in cells if parcel_of(c, r) not in authored}
charted = {(c, r) for (c, r) in cells if (c, r) not in fog}

# Fog cells that touch charted terrain — cardinal or diagonal — (the
# edge-overlay cells), and rings of charted cells near the boundary
# (the creep wisps). Cardinal contact fades the whole facing side;
# diagonal-only contact fades a wedge at the shared vertex — the
# edge/corner/quarter semantics of the 12-shape set.
boundary_fog = {}
ring = {}
for (c, r) in cells:
    is_fog = (c, r) in fog
    charted_neighbours = []
    for dx in (-1, 0, 1):
        for dy in (-1, 0, 1):
            if dx == 0 and dy == 0:
                continue
            if (c + dx, r + dy) in charted:
                charted_neighbours.append((dx, dy))
    if is_fog:
        if charted_neighbours:
            boundary_fog[(c, r)] = charted_neighbours
    else:
        best = 3
        for dx in (-2, -1, 0, 1, 2):
            for dy in (-2, -1, 0, 1, 2):
                d = abs(dx) + abs(dy)
                if 0 < d <= 2 and (c + dx, r + dy) in fog:
                    best = min(best, d)
        if best <= 2:
            ring[(c, r)] = best


def cell_hash(c, r, salt=0):
    return (c * 73856093) ^ (r * 19349663) ^ (salt * 83492791)


def diamond_mask(cell_set):
    mask = Image.new("L", (W, H), 0)
    d = ImageDraw.Draw(mask)
    for (c, r) in cell_set:
        x, y = cell_center(c, r)
        d.polygon([(x, y - 16), (x + 32, y), (x, y + 16), (x - 32, y)], fill=255)
    return mask


# --- The deck: one periodic fine-grain cloud tile, world-anchored. --
TILE_W, TILE_H = 64, 32
rnd = random.Random(5)
base = (217, 228, 222)
grain = Image.new("L", (TILE_W, TILE_H))
for v in range(256):
    x, y = rnd.randrange(TILE_W), rnd.randrange(TILE_H)
    grain.putpixel((x, y), rnd.randrange(120, 200))
grain = grain.filter(ImageFilter.GaussianBlur(1.2))
wrapped = Image.new("L", (TILE_W, TILE_H))
wrapped.paste(grain, (0, 0))
for dx in (-TILE_W, 0, TILE_W):
    for dy in (-TILE_H, 0, TILE_H):
        if dx or dy:
            wrapped.paste(grain.crop((
                max(0, -dx), max(0, -dy),
                TILE_W - max(0, dx), TILE_H - max(0, dy),
            )), (max(0, dx), max(0, dy)))
wrapped = wrapped.filter(ImageFilter.GaussianBlur(0.8))

deck = Image.new("RGBA", (W, H), (0, 0, 0, 0))
deck_px = deck.load()
for y in range(H):
    ty = int(CAM_Y + y) % TILE_H
    for x in range(W):
        tx = int(CAM_X + x) % TILE_W
        g = wrapped.getpixel((tx, ty))
        t = (g - 128) / 127 * 0.10
        deck_px[x, y] = (
            max(0, min(255, int(base[0] * (1 - t) + 201 * t))),
            max(0, min(255, int(base[1] * (1 - t) + 216 * t))),
            max(0, min(255, int(base[2] * (1 - t) + 208 * t))),
            255,
        )

# --- Soft wisp blobs, the sprite layer. ----------------------------
def make_wisp(radius, seed):
    size = radius * 2
    noise = Image.new("L", (size, size))
    r2 = random.Random(seed)
    for v in range(size * size // 8):
        noise.putpixel(
            (r2.randrange(size), r2.randrange(size)), r2.randrange(256)
        )
    noise = noise.resize((size // 2, size // 2), Image.BILINEAR).resize(
        (size, size), Image.BILINEAR
    ).filter(ImageFilter.GaussianBlur(radius * 0.18))
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    for y in range(size):
        dy = (y - size / 2) / (size / 2 - 4)
        for x in range(size):
            dx = (x - size / 2) / (size / 2 - 4)
            fall = 1 - (dx * dx + dy * dy)
            if fall <= 0:
                continue
            n = noise.getpixel((x, y)) / 255
            mask = fall * (0.35 + 0.65 * n)
            if mask < 0.05:
                continue
            f = y / (size - 1)
            color = (
                int(238 * (1 - f) + 224 * f),
                int(246 * (1 - f) + 235 * f),
                int(242 * (1 - f) + 228 * f),
            )
            img.putpixel((x, y), (*color, int(255 * min(1, mask))))
    return img


WISPS = [make_wisp(r, s) for r, s in ((64, 1), (88, 2), (110, 3))]

out = Image.open("fog_in_game.png").convert("RGBA")

# --- The boundary fog layer: deck + fog wisps, feathered at the edge.
fog_layer = deck.copy()
for (c, r) in fog:
    h = cell_hash(c, r)
    if h % 5 < 2:
        wisp = WISPS[h % 3]
        x, y = cell_center(c, r)
        jitter = ((h >> 3) % 17 - 8, (h >> 6) % 9 - 4)
        fog_layer.paste(
            wisp,
            (int(x - wisp.width / 2 + jitter[0]), int(y - wisp.height / 2 + jitter[1])),
            wisp,
        )

# The edge overlay's alpha ramp: a fade measured PERPENDICULAR TO THE
# SHARED DIAMOND EDGE — exactly how the 12-shape edge sprites' art
# would bake it (art drawn in tile space fades from the edge
# inward). Screen-axis fades are wrong here: the diamond's edges are
# diagonal, and an axis-aligned ramp leaves the fog opaque along
# parts of the real edge — a repeating sawtooth of hard segments.
# Cardinal contact fades the whole facing half of the diamond;
# diagonal contact fades a wedge at the shared vertex.
edge_alpha = Image.new("L", (W, H), 255)
draw_alpha = ImageDraw.Draw(edge_alpha)

def edge_progress(lx, ly, dx, dy):
    """Progress from the cell's interior toward the shared edge with
    the neighbour at (dx, dy), for local offsets lx in [-32, 32] and
    ly in [-16, 16] from the cell centre."""
    if dx != 0:
        form = lx + 2 * ly
        progress = (form + 32) / 64 if dx > 0 else (32 - form) / 64
    else:
        form = lx - 2 * ly
        progress = (form + 32) / 64 if dy < 0 else (32 - form) / 64
    return max(0.0, min(1.0, progress))


# Torus-matched bite noise: value noise sampled in the diamond's
# (L, M) square coordinates — L and M are the two diagonal linear
# forms, and the cell maps to the square [-32, 32]^2 in them. The
# noise is periodic with period 64 in BOTH, which is exactly the
# cell lattice: neighbouring cells sample the same noise values at
# their shared edges for every facing, so the displaced fade contour
# is continuous across cells — no per-cell alpha steps (the faint
# repeating L shapes). Variants perturb the interior only, vanishing
# toward the tile's edges, which is how edge-matched sprite variants
# are drawn.
_R = random.Random(97)
_TORUS_N = 2
BASE_GRID = [[_R.random() for _ in range(_TORUS_N)] for _ in range(_TORUS_N)]
VARIANT_GRIDS = []
for v in range(4):
    r2 = random.Random(200 + v)
    VARIANT_GRIDS.append([[r2.random() - 0.5 for _ in range(3)] for _ in range(3)])


def torus_sample(grid, u, v, size):
    iu, iv = int(u) % size, int(v) % size
    fu, fv = u - int(u), v - int(v)
    ju, jv = (iu + 1) % size, (iv + 1) % size
    return (
        grid[iu][iv] * (1 - fu) * (1 - fv)
        + grid[ju][iv] * fu * (1 - fv)
        + grid[iu][jv] * (1 - fu) * fv
        + grid[ju][jv] * fu * fv
    )


def bite_value(lx, ly, variant):
    L = lx + 2 * ly
    M = lx - 2 * ly
    u = ((L % 64) + 64) % 64 / (64 / _TORUS_N)
    v = ((M % 64) + 64) % 64 / (64 / _TORUS_N)
    n = torus_sample(BASE_GRID, u, v, _TORUS_N)
    # The variant perturbation fades out toward the tile's edges
    # (|L| or |M| near 32) so every variant agrees with every other
    # where cells meet.
    w = min(1.0, max(0.0, (32 - abs(L)) / 14)) * min(
        1.0, max(0.0, (32 - abs(M)) / 14)
    )
    if w > 0:
        pu = ((L % 64) + 64) % 64 / (64 / 3)
        pv = ((M % 64) + 64) % 64 / (64 / 3)
        n += torus_sample(VARIANT_GRIDS[variant], pu, pv, 3) * 0.7 * w
    return min(1.0, max(0.0, n))


BITE = 0.85  # how far the noise displaces the fade, in ramp units

for (cell, neighbours) in boundary_fog.items():
    cx, cy = cell_center(*cell)
    variant = cell_hash(*cell, salt=13) % 4
    cardinal = [(dx, dy) for (dx, dy) in neighbours if dx == 0 or dy == 0]
    diagonal = [(dx, dy) for (dx, dy) in neighbours if dx != 0 and dy != 0]
    for px_x in range(64):
        for px_y in range(32):
            x, y = int(cx - 32 + px_x), int(cy - 16 + px_y)
            if not (0 <= x < W and 0 <= y < H):
                continue
            lx, ly = px_x - 32, px_y - 16
            fade = 0.0
            for (dx, dy) in cardinal:
                fade = max(fade, edge_progress(lx, ly, dx, dy))
            for (dx, dy) in diagonal:
                fade = max(
                    fade,
                    edge_progress(lx, ly, dx, 0)
                    * edge_progress(lx, ly, 0, dy),
                )
            if fade <= 0:
                continue
            n = bite_value(lx, ly, variant)
            window = min(1.0, fade / 0.25)
            displaced = fade + (n - 0.5) * BITE * window
            draw_alpha.point(
                (x, y),
                max(0, min(255, int(255 * (1 - 0.85 * displaced)))),
            )

# --- The underlay: terrain showing through the fringe. --------------
# In the game the boundary fog cell draws its charted neighbour's
# terrain tile under the edge overlay; here the neighbour's pixels
# are copied from the render itself, replacing the old fog there.
CELL_STENCIL = Image.new("L", (64, 32), 0)
ImageDraw.Draw(CELL_STENCIL).polygon(
    [(32, 0), (64, 16), (32, 32), (0, 16)], fill=255
)
for (cell, neighbours) in boundary_fog.items():
    dx, dy = neighbours[0]
    nx, ny = cell_center(cell[0] + dx, cell[1] + dy)
    cx, cy = cell_center(*cell)
    box = (int(nx - 32), int(ny - 16), int(nx + 32), int(ny + 16))
    if box[0] < 0 or box[1] < 0 or box[2] > W or box[3] > H:
        continue
    patch = out.crop(box)
    # Masked to the cell's own diamond: a rectangular paste would
    # spill over the neighbouring fog cells and show its box seams
    # through the thinned fringe (faint L shapes). The real game
    # draws the terrain tile, whose diamond art needs no masking.
    out.paste(patch, (int(cx - 32), int(cy - 16)), CELL_STENCIL)

# The fog layer — deck plus fog wisps — blended over the render by
# the edge alpha: full cloud in the interior, the feathered fringe
# letting the underlay through at the boundary.
fog_diamonds = diamond_mask(fog)
fog_mask = ImageChops.multiply(fog_diamonds, edge_alpha)
out.paste(fog_layer, (0, 0), fog_mask)

# --- Creep wisps over the charted side of the boundary. -------------
for (cell, ring_d) in ring.items():
    h = cell_hash(*cell, salt=7)
    if h % 10 >= (4 if ring_d == 1 else 7):
        continue
    wisp = WISPS[h % 3]
    x, y = cell_center(*cell)
    scaled = wisp.copy()
    factor = 0.55 if ring_d == 1 else 0.30
    scaled.putalpha(
        scaled.getchannel("A").point(lambda v, f=factor: int(v * f))
    )
    out.alpha_composite(
        scaled, (int(x - wisp.width / 2), int(y - wisp.height / 2))
    )

out.convert("RGB").save("fog_sprite_wispy_preview.png")
print("fog_sprite_wispy_preview.png written")
