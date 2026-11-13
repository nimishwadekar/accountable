#!/usr/bin/env python3
"""Water-side shore band previews — cross-fade on the water tile only.

Composites the game's real ground art (no invented pixels). The band
blends the land material over the water tile with an alpha ramp that
falls to zero at `reach` canvas pixels from the nearest land edge,
optionally broken up by value noise. The "current" sheet replicates
the shipped bank sprites (material cut by the baked masks, with the
game's waterBankRoles selection) for an honest side-by-side.
"""
import math
import os
import random

from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, '..', '..'))
ASSETS = os.path.join(ROOT, 'assets', 'sprites')

TW, TH = 128, 64
HW, HH = 64, 32
MARGIN = 28

grass = Image.open(os.path.join(ASSETS, 'ground/grass/tile_ground_grass.png')).convert('RGBA')
water = Image.open(os.path.join(ASSETS, 'ground/water/tile_ground_water.png')).convert('RGBA')


def load_mask(fam, sub):
    return Image.open(os.path.join(ASSETS, 'shores', 'masks', f'shore_{fam}_{sub}.png')).convert('RGB')


MASKS = {}
for sub in ('n', 'e', 's', 'w'):
    MASKS[('edge', sub)] = load_mask('edge', sub)
    MASKS[('corner', sub)] = load_mask('corner', sub)
for sub in ('ne', 'nw', 'se', 'sw'):
    MASKS[('quarter', sub)] = load_mask('quarter', sub)
MASK_LOADERS = {k: v.load() for k, v in MASKS.items()}

# --- scene -----------------------------------------------------------------

COLS, ROWS = 16, 12
water_cells = set()
for r in range(3, 7):
    for c in range(4, 10):
        water_cells.add((c, r))
water_cells.discard((9, 3))  # land protrusion -> diagonal-only contact at (8,4)
water_cells.discard((6, 5))  # island in the pond
water_cells |= {(6, 1), (6, 2)}    # 1-wide inlet
water_cells |= {(11, 2), (12, 2)}  # small 2x1 pond
water_cells.add((12, 7))           # lone 1x1 pond


def is_water(c, r):
    return (c, r) in water_cells


def origin(c, r):
    return ((c - r) * HW, (c + r) * HH)


xs = [origin(c, r)[0] for c in range(COLS) for r in range(ROWS)]
ys = [origin(c, r)[1] for c in range(COLS) for r in range(ROWS)]
sx0, sy0 = min(xs) - MARGIN, min(ys) - MARGIN
SCENE_W = max(xs) + TW - sx0 + MARGIN
SCENE_H = max(ys) + TH - sy0 + MARGIN

base = Image.new('RGBA', (SCENE_W, SCENE_H), (38, 44, 48, 255))
for s in range(COLS + ROWS - 1):
    for c in range(COLS):
        for r in range(ROWS):
            if c + r != s:
                continue
            tile = water if is_water(c, r) else grass
            ox, oy = origin(c, r)
            base.paste(tile, (ox - sx0, oy - sy0), tile)

# --- solid pixels + repaired grass colours (fringe dilation) ----------------

gpx = grass.load()
solid = [(x, y) for y in range(TH) for x in range(TW) if gpx[x, y][3] > 0]
repaired = [[None] * TW for _ in range(TH)]
for y in range(TH):
    for x in range(TW):
        if gpx[x, y][3] > 0:
            repaired[y][x] = gpx[x, y][:3]
need = [(x, y) for y in range(TH) for x in range(TW) if repaired[y][x] is None]
remaining = len(need)
while remaining:
    progress = False
    for (x, y) in need:
        if repaired[y][x] is not None:
            continue
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            nx, ny = x + dx, y + dy
            if 0 <= nx < TW and 0 <= ny < TH and repaired[ny][nx] is not None:
                repaired[y][x] = repaired[ny][nx]
                remaining -= 1
                progress = True
                break
    if not progress:
        break
for y in range(TH):
    for x in range(TW):
        if repaired[y][x] is None:
            repaired[y][x] = (154, 161, 80)

# --- value noise (two octaves), stored as stretched [0,1] --------------------


def noise_layer(cell, seed):
    rnd = random.Random(seed)
    gw, gh = SCENE_W // cell + 2, SCENE_H // cell + 2
    im = Image.new('L', (gw, gh))
    im.putdata([rnd.randint(0, 255) for _ in range(gw * gh)])
    return im.resize((SCENE_W, SCENE_H), Image.BICUBIC)


n1 = noise_layer(44, 7)
n2 = noise_layer(16, 13)


def noise_raw(x, y):
    n = 0.65 * n1.getpixel((x, y)) / 255 + 0.35 * n2.getpixel((x, y)) / 255
    return min(1.0, max(0.0, (n - 0.2) / 0.6))


def modulate(n, strength):
    """Noise only ever reduces the ramp, by up to `strength`."""
    return 1.0 - strength * (1.0 - n)


# --- band geometry: distance to nearest land diamond ------------------------


def seg_dist(px, py, ax, ay, bx, by):
    vx, vy = bx - ax, by - ay
    wx, wy = px - ax, py - ay
    t = (wx * vx + wy * vy) / (vx * vx + vy * vy)
    if t < 0:
        t = 0.0
    elif t > 1:
        t = 1.0
    dx, dy = px - (ax + t * vx), py - (ay + t * vy)
    return math.hypot(dx, dy)


REACH_MAX = 34.0
bands = {}
for (c, r) in sorted(water_cells):
    segs = []
    for dc in (-1, 0, 1):
        for dr in (-1, 0, 1):
            if (dc == 0 and dr == 0) or is_water(c + dc, r + dr):
                continue
            ox, oy = origin(c + dc, r + dr)
            cx, cy = ox + HW, oy + HH
            nv = (cx, cy - HH)
            ev = (cx + HW, cy)
            sv = (cx, cy + HH)
            wv = (cx - HW, cy)
            segs += [(nv, ev), (ev, sv), (sv, wv), (wv, nv)]
    if not segs:
        continue
    ox, oy = origin(c, r)
    pts = []
    for (lx, ly) in solid:
        gx, gy = ox + lx, oy + ly
        d = min(seg_dist(gx, gy, a[0], a[1], b[0], b[1]) for (a, b) in segs)
        if d < REACH_MAX:
            pts.append((lx, ly, d, noise_raw(gx - sx0, gy - sy0)))
    bands[(c, r)] = pts

# --- current-look bank roles (replicates waterBankRoles) --------------------


def bank_roles(c, r):
    def bs(dc, dr):
        return None if is_water(c + dc, r + dr) else 'grass'

    N, E, S, W_ = bs(0, -1), bs(1, 0), bs(0, 1), bs(-1, 0)
    if N and E and S and W_:
        return []
    roles = []
    n, e, s, w = N, E, S, W_
    if n and e:
        roles.append(('corner', 'w'))
        n = e = None
    elif e and s:
        roles.append(('corner', 'n'))
        e = s = None
    elif s and w:
        roles.append(('corner', 'e'))
        s = w = None
    elif w and n:
        roles.append(('corner', 's'))
        w = n = None
    if n:
        roles.append(('quarter', 'sw'))
    if e:
        roles.append(('quarter', 'nw'))
    if s:
        roles.append(('quarter', 'ne'))
    if w:
        roles.append(('quarter', 'se'))
    if N is None and W_ is None and bs(-1, -1):
        roles.append(('edge', 's'))
    if N is None and E is None and bs(1, -1):
        roles.append(('edge', 'w'))
    if E is None and S is None and bs(1, 1):
        roles.append(('edge', 'n'))
    if S is None and W_ is None and bs(-1, 1):
        roles.append(('edge', 'e'))
    return roles


# --- rendering --------------------------------------------------------------


def smoothstep(t):
    t = 0.0 if t < 0 else (1.0 if t > 1 else t)
    return t * t * (3 - 2 * t)


try:
    FONT = ImageFont.load_default(size=18)
except TypeError:
    FONT = ImageFont.load_default()


def finish(im, label, fname):
    bar = Image.new('RGBA', (im.width, 36), (24, 28, 31, 255))
    d = ImageDraw.Draw(bar)
    d.text((12, 8), label, fill=(235, 238, 220, 255), font=FONT)
    out = Image.new('RGBA', (im.width, im.height + bar.height), (24, 28, 31, 255))
    out.paste(bar, (0, 0))
    out.paste(im, (0, bar.height))
    out = out.resize((out.width * 2, out.height * 2), Image.NEAREST)
    path = os.path.join(HERE, fname)
    out.save(path)
    print('wrote', path)


def render_band(reach, strength, posterize, label, fname):
    im = base.copy()
    px = im.load()
    for (c, r), pts in bands.items():
        ox, oy = origin(c, r)
        for (lx, ly, d, n) in pts:
            t = 1.0 - d / reach
            if t <= 0:
                continue
            a = smoothstep(t)
            if strength > 0:
                a *= modulate(n, strength)
            if posterize:
                a = round(a * 3.0) / 3.0
            if a < 0.01:
                continue
            gr, gg, gb = repaired[ly][lx]
            gx, gy = ox + lx - sx0, oy + ly - sy0
            wr, wg, wb, _ = px[gx, gy]
            px[gx, gy] = (round(wr + (gr - wr) * a),
                          round(wg + (gg - wg) * a),
                          round(wb + (gb - wb) * a), 255)
    finish(im, label, fname)


def render_current(label, fname):
    im = base.copy()
    px = im.load()
    for (c, r) in sorted(water_cells):
        roles = bank_roles(c, r)
        if not roles:
            continue
        ox, oy = origin(c, r)
        for (fam, sub) in roles:
            mpx = MASK_LOADERS[(fam, sub)]
            for (lx, ly) in solid:
                lum = mpx[lx, ly][0]
                if lum == 0:
                    continue
                a = lum / 255
                gr, gg, gb = repaired[ly][lx]
                gx, gy = ox + lx - sx0, oy + ly - sy0
                wr, wg, wb, _ = px[gx, gy]
                px[gx, gy] = (round(wr + (gr - wr) * a),
                              round(wg + (gg - wg) * a),
                              round(wb + (gb - wb) * a), 255)
    finish(im, label, fname)


# --- coverage stats ---------------------------------------------------------


def coverage_current(cell):
    roles = bank_roles(*cell)
    cov = 0
    for (lx, ly) in solid:
        rem = 1.0
        for (fam, sub) in roles:
            rem *= 1 - MASK_LOADERS[(fam, sub)][lx, ly][0] / 255
        if 1 - rem > 0.5:
            cov += 1
    return cov / len(solid)


def band_alphas(cell, reach, strength):
    out = []
    for (lx, ly, d, n) in bands.get(cell, []):
        a = smoothstep(1 - d / reach)
        if strength > 0:
            a *= modulate(n, strength)
        out.append(a)
    return out


def coverage_band(cell, reach, strength, threshold):
    alphas = band_alphas(cell, reach, strength)
    if not alphas:
        return 0.0
    return sum(1 for a in alphas if a > threshold) / len(solid)


def waterline_alpha(cell, reach, strength):
    """Mean band alpha within 4px of the border (waterline strength)."""
    near = [(d, n) for (lx, ly, d, n) in bands.get(cell, []) if d < 4]
    if not near:
        return 0.0
    tot = 0.0
    for d, n in near:
        a = smoothstep(1 - d / reach)
        if strength > 0:
            a *= modulate(n, strength)
        tot += a
    return tot / len(near)


def main():
    render_current('CURRENT — baked bank sprites (opaque land art over water)', '0_current_banks.png')
    render_band(29, 0, False, 'A — water-side band, clean ramp, half tile', '1_band_clean_half.png')
    render_band(29, 0.55, False, 'B — water-side band, gentle noise, half tile', '2_band_noise_gentle.png')
    render_band(19, 0.55, False, 'C — water-side band, gentle noise, third tile', '3_band_noise_third.png')
    render_band(29, 0.55, True, 'D — water-side band, gentle noise, posterized, half tile', '4_band_noise_posterized.png')
    render_band(29, 0.8, False, 'E — water-side band, strong noise, half tile', '5_band_noise_strong.png')

    print()
    print('scene map ( . land   ~ water   # in-pond land):')
    for r in range(ROWS):
        print('  ' + ''.join(
            '~' if is_water(c, r) else ('#' if (c, r) in ((9, 3), (6, 5)) else '.')
            for c in range(COLS)))
    print()
    print(f'solid px per tile: {len(solid)} (mathematical diamond: 4096 — the art fringe overpaints, as shipped)')
    print('land-weight on the water tile (fraction of tile pixels above 50% land coverage):')
    print(f'{"cell":14s} {"case":16s} {"current":>8s} {"B half":>8s} {"C third":>9s}')
    for cell, case in (((4, 4), 'straight edge'),
                       ((4, 3), 'concave corner'),
                       ((6, 4), 'island-facing'),
                       ((8, 4), 'diagonal-only'),
                       ((12, 7), 'surrounded 1x1')):
        print(f'{str(cell):14s} {case:16s} {coverage_current(cell):8.2f} '
              f'{coverage_band(cell, 29, 0.55, 0.5):8.2f} {coverage_band(cell, 19, 0.55, 0.5):9.2f}')
    print()
    print('straight-edge cell, band detail:')
    print(f'  tint coverage (alpha>0.15): B {coverage_band((4,4), 29, 0.55, 0.15):.2f}'
          f'  C {coverage_band((4,4), 19, 0.55, 0.15):.2f}')
    print(f'  waterline mean alpha: A {waterline_alpha((4,4), 29, 0):.2f}'
          f'  B {waterline_alpha((4,4), 29, 0.55):.2f}'
          f'  E {waterline_alpha((4,4), 29, 0.8):.2f}')


if __name__ == '__main__':
    main()
