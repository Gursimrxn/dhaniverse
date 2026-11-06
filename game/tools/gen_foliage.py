#!/usr/bin/env python3
"""Realistic foliage textures for the valley's trees, shrubs and conifers.

    python tools/gen_foliage.py            (from the game folder; numpy, scipy, Pillow)
    python tools/gen_foliage.py --preview  (also writes PNG previews to ./foliage_preview)

Writes into assets/vh/ in the format VHTex reads (raw RGBA8 rows, gzipped, mips appended) and registers
the files in assets/vh/textures.json:

  leafhq_<kind>          leaf-cluster atlas: albedo (sRGB) + coverage, coverage-preserving mips so the
                         alpha test keeps the crowns as full in the distance as close up
  leafhq_<kind>_normal   tangent-space normal of every leaf (rgb: x right, y up the card, z out) +
                         translucency in alpha (thin blade 1 .. midrib, petiole and twig ~0)
  barkhq_map / _normal   tileable furrowed bark with lichen; normal (rgb) + height (alpha)
  turf_map / _normal     tileable lawn seen from above, for the terrain's grass; normal (rgb) + height (alpha)

Atlas layout matches the cards (scripts/vh/vh_trees.gd): image row 0 is the card's anchor, where the twig
comes in at the top centre; the spray grows down the image, which is up the card.
Every leaf is drawn as a real shape - ovate and serrated, lobed, lanceolate, elliptic, or spruce shoots of
needles - with a midrib, curving secondary veins, a fine vein net, edge tint, the odd blemish or bite, its
own hue, fold and tilt (in the normal map), shade from the leaves in front of it and a soft cast shadow.
Everything is drawn at twice the size and filtered down.
"""
import gzip
import json
import math
import os
import sys

import numpy as np
from PIL import Image
from scipy import ndimage

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets", "vh")
ALPHA_REF = 0.42          # leaf.gdshaderinc alpha_test
SS = 2                    # supersampling


# --- small helpers -----------------------------------------------------------------------------------------
def srgb(c):
    return np.array(c, dtype=np.float32) / 255.0


def smoothstep(a, b, x):
    t = np.clip((x - a) / (b - a), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def fbm(shape, rng, octaves=5, base=8, periodic=False):
    """Value-noise fBm in 0..1 over an image of `shape`, `base` cells across at the coarsest octave
    (periodic: tiles seamlessly)."""
    h, w = shape
    out = np.zeros(shape, np.float32)
    amp, tot = 1.0, 0.0
    for o in range(octaves):
        n = base * (2 ** o)
        ny = max(2, int(round(n * h / w)))
        g = rng.random((ny, n)).astype(np.float32)
        up = ndimage.zoom(g, (h / ny, w / n), order=3, mode="grid-wrap" if periodic else "nearest", grid_mode=True)
        up = up[:h, :w]
        if up.shape != (h, w):
            up = np.pad(up, ((0, h - up.shape[0]), (0, w - up.shape[1])), mode="wrap" if periodic else "edge")
        out += up * amp
        tot += amp
        amp *= 0.5
    out /= tot
    lo, hi = np.percentile(out, 1), np.percentile(out, 99)
    return np.clip((out - lo) / (hi - lo + 1e-6), 0.0, 1.0)


def blur(a, s):
    return ndimage.gaussian_filter(a, s, mode="nearest")


# --- the canvas: colour, coverage, normal, translucency ------------------------------------------------------
class Canvas:
    def __init__(self, size, rng):
        self.n = size
        self.rgb = np.zeros((size, size, 3), np.float32)
        self.a = np.zeros((size, size), np.float32)
        self.nrm = np.zeros((size, size, 3), np.float32)
        self.nrm[..., 2] = 1.0
        self.tr = np.zeros((size, size), np.float32)
        self.rng = rng
        self.grain = fbm((size, size), rng, octaves=6, base=24)          # leaf surface mottling
        self.fine = fbm((size, size), rng, octaves=3, base=180)          # vein net / cell texture
        self.blot = fbm((size, size), rng, octaves=4, base=10)

    def box(self, pts, pad=4):
        pts = np.asarray(pts)
        x0 = int(max(0, math.floor(pts[:, 0].min()) - pad))
        x1 = int(min(self.n, math.ceil(pts[:, 0].max()) + pad))
        y0 = int(max(0, math.floor(pts[:, 1].min()) - pad))
        y1 = int(min(self.n, math.ceil(pts[:, 1].max()) + pad))
        if x1 <= x0 or y1 <= y0:
            return None
        ys, xs = np.mgrid[y0:y1, x0:x1].astype(np.float32) + 0.5
        return (slice(y0, y1), slice(x0, x1)), xs, ys

    def shadow(self, sl, cov, strength, off):
        """Darken what is already drawn under a soft, offset copy of the new shape."""
        if strength <= 0:
            return
        sh = blur(cov, 3.0 * SS)
        sh = ndimage.shift(sh, (off[1], off[0]), order=1, mode="constant")
        k = 1.0 - strength * sh * self.a[sl]
        self.rgb[sl] *= k[..., None]

    def put(self, sl, cov, rgb, nrm, tr):
        """Alpha-over a shape (coverage, colour, normal, translucency) onto the canvas."""
        c = cov[..., None]
        self.rgb[sl] = self.rgb[sl] * (1 - c) + rgb * c
        self.nrm[sl] = self.nrm[sl] * (1 - c) + nrm * c
        self.tr[sl] = self.tr[sl] * (1 - cov) + tr * cov
        self.a[sl] = self.a[sl] + cov * (1 - self.a[sl])


def stroke(cv, p0, p1, r0, r1, col, tr=0.05, bark=True):
    """A tapered twig from p0 to p1 (pixels), round in section (normal across it)."""
    p0, p1 = np.array(p0, np.float32), np.array(p1, np.float32)
    got = cv.box([p0 - r0, p0 + r0, p1 - r1, p1 + r1], pad=3)
    if got is None:
        return
    sl, xs, ys = got
    d = p1 - p0
    L = float(np.hypot(*d)) + 1e-6
    t = np.clip(((xs - p0[0]) * d[0] + (ys - p0[1]) * d[1]) / (L * L), 0.0, 1.0)
    cx = p0[0] + d[0] * t
    cy = p0[1] + d[1] * t
    r = r0 + (r1 - r0) * t
    dist = np.hypot(xs - cx, ys - cy)
    cov = np.clip((r - dist) / 1.2 + 0.5, 0.0, 1.0)
    if cov.max() <= 0:
        return
    side = ((xs - cx) * (-d[1]) + (ys - cy) * d[0]) / L / np.maximum(r, 0.5)   # -1..1 across
    side = np.clip(side, -1.0, 1.0)
    shade = 0.75 + 0.3 * (1.0 - side * side) - 0.12 * side
    rgb = np.asarray(col, np.float32)[None, None, :] * shade[..., None]
    if bark:
        rgb *= (0.85 + 0.3 * cv.grain[sl])[..., None]
    nrm = np.stack([side * (-d[1] / L), side * (d[0] / L), np.sqrt(np.maximum(1.0 - side * side, 0.05))], -1)
    cv.put(sl, cov, rgb, nrm, np.full(cov.shape, tr, np.float32))


# --- leaves ------------------------------------------------------------------------------------------------------
def leaf_outline(kind, t, rng_l):
    """Half-width of the blade (0..1 of its widest) at t along the midrib (0 base .. 1 tip)."""
    t = np.clip(t, 0.0, 1.0)
    if kind == "ovate":           # broadleaf / blossom: ovate, short acuminate tip, fine teeth
        w = np.maximum(np.sin(np.pi * np.power(t, 0.72)), 0.0) ** 0.85 * (1.0 - 0.18 * t)
        w *= 1.0 - 0.55 * smoothstep(0.78, 1.0, t) * (1.0 - smoothstep(0.92, 1.0, t))
        teeth = 1.0 + 0.045 * (2.0 * np.abs(np.mod(t * rng_l["teeth"], 1.0) - 0.5) - 0.5) * smoothstep(0.08, 0.2, t)
        return w * teeth
    if kind == "lobed":           # oak: 4-6 rounded lobes a side, deep sinuses, ear-like base
        base = np.maximum(np.sin(np.pi * np.power(t, 0.85)), 0.0) ** 0.7 * (0.75 + 0.35 * t) * (1.0 - 0.6 * smoothstep(0.85, 1.0, t))
        lobes = rng_l["lobes"]
        wave = np.abs(np.sin(np.pi * (lobes * t + rng_l["phase"])))
        return base * (0.52 + 0.48 * np.power(wave, 0.55)) + 0.06 * smoothstep(0.1, 0.0, t)
    if kind == "lance":           # willow: narrow, long taper
        return np.maximum(np.sin(np.pi * np.power(t, 0.55)), 0.0) ** 1.1 * (1.0 - 0.1 * t)
    if kind == "ellipse":         # shrub: elliptic, entire margin
        return np.sqrt(np.maximum(1.0 - (2.0 * t - 1.0) ** 2, 0.0)) ** 0.9
    return np.maximum(np.sin(np.pi * t), 0.0)


def draw_leaf(cv, anchor, ang, L, W, P, kind, col, z, params, rng):
    """One leaf: petiole from `anchor` along `ang`, blade length L, half-width W (pixels).
    col: base sRGB colour; z: 0 back .. 1 front (shade); params: fold, tilt, foreshortening."""
    ax, ay = anchor
    c, s = math.cos(ang), math.sin(ang)
    reach = P + L
    pts = [(ax + c * u - s * v, ay + s * u + c * v) for u in (0, reach) for v in (-W * 1.25, W * 1.25)]
    got = cv.box(pts, pad=3)
    if got is None:
        return
    sl, xs, ys = got
    dx, dy = xs - ax, ys - ay
    u = dx * c + dy * s
    v = -dx * s + dy * c
    t = (u - P) / L
    rl = {"teeth": rng.uniform(18, 26), "lobes": rng.uniform(4.0, 5.5), "phase": rng.uniform(-0.2, 0.2)}
    half = W * leaf_outline(kind, t, rl) * (1.0 + 0.04 * (cv.blot[sl] - 0.5))
    inside_t = (t >= 0.0) & (t <= 1.0)
    edge = half - np.abs(v)
    cov = np.clip(edge / (0.9 * SS) + 0.5, 0.0, 1.0) * inside_t
    # an insect bite out of the margin now and then
    if rng.random() < params.get("bites", 0.12):
        bt = rng.uniform(0.3, 0.8)
        bside = rng.choice([-1.0, 1.0])
        br = W * rng.uniform(0.25, 0.5)
        bx = P + bt * L
        by = bside * W * leaf_outline(kind, np.array(bt), rl) * 0.95
        cov *= np.clip((np.hypot(u - bx, v - by) - br) / SS + 0.5, 0.0, 1.0)
    pw = max(0.9 * SS, W * 0.06)
    pet = np.clip((pw * (1.0 - 0.3 * np.clip(u / max(P, 1), 0, 1)) - np.abs(v)) / SS + 0.5, 0.0, 1.0) * (u >= -1) * (u <= P + 0.15 * L)
    cov_all = np.maximum(cov, pet)
    if cov_all.max() <= 0.0:
        return
    # baked shade from the leaves in front of it, then this leaf's soft shadow on what lies behind
    cv.shadow(sl, cov_all, params.get("cast", 0.28), (2.0 * SS, 3.0 * SS))
    tt = np.clip(t, 0.0, 1.0)
    rel = np.clip(np.abs(v) / np.maximum(half, 1e-3), 0.0, 1.0)   # 0 midrib .. 1 margin
    base = np.asarray(col, np.float32)
    # colour: a touch yellower at the base, deeper towards the tip, mottled
    rgb = np.ones(cov.shape + (3,), np.float32) * base
    rgb *= (1.06 - 0.12 * tt)[..., None]
    rgb[..., 0] *= 1.0 + 0.06 * (1.0 - tt)
    rgb *= (0.9 + 0.2 * cv.grain[sl])[..., None]
    # midrib and curving secondary veins, fading to the margin and the tip
    mid_w = max(0.6 * SS, W * 0.055) * (1.0 - 0.75 * tt)
    mid = np.exp(-(v / mid_w) ** 2) * inside_t
    nv = params.get("veins", 8)
    vang = params.get("vein_angle", 0.55)
    a = (u - P) - np.abs(v) * vang * (1.0 + 0.6 * rel)
    sp = L / nv
    dl = np.abs(np.mod(a + 0.5 * sp, sp) - 0.5 * sp)
    vw = max(0.4 * SS, W * 0.018)
    sec = np.exp(-(dl / vw) ** 2) * smoothstep(0.98, 0.55, rel) * smoothstep(0.04, 0.12, tt) * (1.0 - smoothstep(0.85, 1.0, tt))
    net = smoothstep(0.55, 0.85, 1.0 - np.abs(2.0 * cv.fine[sl] - 1.0)) * 0.6
    vein_col = np.asarray(params.get("vein_col", base * 1.45 + 0.04), np.float32)
    lit = np.clip(mid * params.get("mid_k", 0.6) + sec * params.get("sec_k", 0.3), 0.0, 1.0)
    rgb = rgb * (1.0 - lit[..., None]) + vein_col * lit[..., None]
    rgb *= (1.0 - 0.07 * net)[..., None]
    # margin: a thin darker, warmer rim
    rim = smoothstep(1.4 * SS, 0.0, edge) * inside_t
    rgb = rgb * (1.0 - 0.25 * rim[..., None]) + np.array([0.42, 0.36, 0.12], np.float32) * (0.1 * rim[..., None])
    # blemishes: a few small brown or yellow spots on some leaves
    if rng.random() < params.get("spots", 0.2):
        for _ in range(rng.integers(1, 4)):
            st = rng.uniform(0.2, 0.85)
            sv = rng.uniform(-0.6, 0.6) * W
            sr = W * rng.uniform(0.07, 0.18)
            sd = np.hypot(u - (P + st * L), v - sv)
            sm = smoothstep(sr, sr * 0.4, sd) * inside_t
            sc = np.array([0.45, 0.33, 0.12] if rng.random() < 0.6 else [0.62, 0.58, 0.22], np.float32)
            rgb = rgb * (1.0 - 0.8 * sm[..., None]) + sc * (0.8 * sm[..., None])
    # shade: deeper leaves darker and a little bluer, front leaves lit
    shade = params.get("ao_min", 0.58) + (1.0 - params.get("ao_min", 0.58)) * z ** 0.8
    rgb *= shade
    rgb[..., 2] *= 1.0 + 0.08 * (1.0 - z)
    # petiole
    pet_only = pet * (1.0 - cov)
    pcol = np.asarray(params.get("petiole_col", base * 0.95 + np.array([0.06, 0.03, 0.0])), np.float32) * shade
    rgb = rgb * (1.0 - pet_only[..., None]) + pcol * pet_only[..., None]
    # normal: the blade folds up from the midrib, tilts as a whole, veins sit in shallow grooves
    fold = params["fold"]
    sgn = np.sign(v)
    across = sgn * math.sin(fold) * (0.4 + 0.6 * rel)
    along = params["tilt_along"] + 0.25 * (tt - 0.5) * params.get("curl", 0.4)
    groove = (sec * 0.25 + mid * 0.2) * np.sign(np.mod(a + 0.5 * sp, sp) - 0.5 * sp)
    lx = across * 1.0
    ly = along + groove * 0.3
    lz = np.ones_like(lx)
    # leaf frame -> image frame (u along the leaf, v across it)
    nx = lx * (-s) + ly * c
    ny = lx * c + ly * s
    nrm = np.stack([nx + params["tilt"][0], ny + params["tilt"][1], lz], -1)
    nrm /= np.linalg.norm(nrm, axis=-1, keepdims=True)
    # translucency: thin blade glows, veins and petiole less, margins most
    tr = np.where(cov >= pet, np.clip(0.8 + 0.2 * rel - 0.7 * mid - 0.25 * sec, 0.1, 1.0), 0.15)
    cv.put(sl, cov_all, rgb, nrm, tr)


def draw_flower(cv, centre, R, rng, z, petal_a, petal_b):
    """Five-petalled blossom (cherry): notched petals, pink heart, stamens."""
    cx, cy = centre
    rot = rng.uniform(0, 2 * math.pi)
    got = cv.box([(cx - R * 1.2, cy - R * 1.2), (cx + R * 1.2, cy + R * 1.2)], pad=3)
    if got is None:
        return
    sl, xs, ys = got
    dx, dy = xs - cx, ys - cy
    r = np.hypot(dx, dy)
    th = np.arctan2(dy, dx) - rot
    k = np.mod(th, 2 * math.pi / 5) - math.pi / 5            # angle from the nearest petal axis
    pr = R * (0.72 + 0.28 * np.cos(k * 5 / 2) ** 0.6)
    notch = 1.0 - 0.18 * np.exp(-(k / 0.09) ** 2)
    cov = np.clip((pr * notch - r) / SS + 0.5, 0.0, 1.0)
    cv.shadow(sl, cov, 0.3, (1.5 * SS, 2.5 * SS))
    rr = r / R
    col = np.asarray(petal_a, np.float32) * (1 - rr[..., None]) + np.asarray(petal_b, np.float32) * rr[..., None]
    heart = smoothstep(0.38, 0.1, rr)
    col = col * (1 - heart[..., None] * 0.6) + np.array([0.86, 0.45, 0.55], np.float32) * heart[..., None] * 0.6
    vein = 0.04 * np.cos(np.arctan2(dy, dx) * 26.0) * smoothstep(0.2, 0.9, rr)
    col *= (0.93 + vein + 0.1 * cv.grain[sl])[..., None]
    # stamens: little yellow dots on a ring
    st = np.zeros_like(r)
    for i in range(9):
        a = rot + i * 2 * math.pi / 9 + rng.uniform(-0.2, 0.2)
        sr = R * rng.uniform(0.25, 0.38)
        st = np.maximum(st, smoothstep(0.09 * R, 0.03 * R, np.hypot(dx - math.cos(a) * sr, dy - math.sin(a) * sr)))
    col = col * (1 - st[..., None]) + np.array([0.95, 0.82, 0.32], np.float32) * st[..., None]
    col *= 0.72 + 0.28 * z
    cup = np.clip(rr, 0, 1) * 0.5
    nrm = np.stack([dx / np.maximum(r, 1e-3) * cup, dy / np.maximum(r, 1e-3) * cup, np.ones_like(r)], -1)
    nrm /= np.linalg.norm(nrm, axis=-1, keepdims=True)
    cv.put(sl, cov, col, nrm, np.full(cov.shape, 0.9, np.float32))


def needle_shoot(cv, p0, ang, length, rng, z, pal, tip_col, density=1.0):
    """A spruce shoot: brown twig with needles all round it, seen from above (bottle brush)."""
    c, s = math.cos(ang), math.sin(ang)
    p0 = np.array(p0, np.float32)
    p1 = p0 + np.array([c, s], np.float32) * length
    stroke(cv, p0, p1, 1.4 * SS, 0.7 * SS, srgb((92, 68, 46)), tr=0.0)
    n = int(length / (1.2 * SS) * density)
    for i in range(n):
        t = (i + rng.random()) / n
        q = p0 + (p1 - p0) * t
        side = 1.0 if i % 2 == 0 else -1.0
        spread = rng.uniform(0.55, 1.15)                   # 0 = along the shoot, pi/2 = straight out
        a = ang + side * spread
        nl = length * rng.uniform(0.075, 0.11) * (0.75 + 0.35 * math.sin(math.pi * min(t * 1.2, 1.0)))
        nl *= rng.uniform(0.55, 1.0)                        # needles pointing up or down look shorter
        q1 = q + np.array([math.cos(a), math.sin(a)], np.float32) * nl
        young = smoothstep(0.75, 1.0, t) * rng.uniform(0.6, 1.0)
        col = np.asarray(pal[rng.integers(len(pal))], np.float32) * (0.82 + 0.3 * rng.random())
        col = col * (1 - young) + np.asarray(tip_col, np.float32) * young
        col *= 0.7 + 0.3 * z
        stroke(cv, q, q1, 1.1 * SS, 0.5 * SS, col, tr=0.55, bark=False)


# --- mips, edge padding, file output ------------------------------------------------------------------------------
def pad_colour(rgb, a, iters=10):
    """Push-pull: give transparent texels the colour of the nearest leaves, so filtering never bleeds black."""
    w = (a > 0.02).astype(np.float32)
    levels = [(rgb * w[..., None], w)]
    c, ww = rgb * w[..., None], w
    for _ in range(iters):
        if c.shape[0] < 4:
            break
        c = c.reshape(c.shape[0] // 2, 2, c.shape[1] // 2, 2, 3).sum((1, 3))
        ww = ww.reshape(ww.shape[0] // 2, 2, ww.shape[1] // 2, 2).sum((1, 3))
        levels.append((c, ww))
    fill = levels[-1][0] / np.maximum(levels[-1][1], 1e-6)[..., None]
    for c, ww in reversed(levels[:-1]):
        up = np.repeat(np.repeat(fill, 2, 0), 2, 1)[: c.shape[0], : c.shape[1]]
        here = c / np.maximum(ww, 1e-6)[..., None]
        k = np.clip(ww, 0, 1)[..., None]
        fill = here * k + up * (1 - k)
    return fill


def downsample(img):
    h, w = img.shape[:2]
    return img.reshape(h // 2, 2, w // 2, 2, *img.shape[2:]).mean((1, 3))


def coverage_scale(a, target):
    lo, hi = 0.0, 8.0
    for _ in range(24):
        m = (lo + hi) * 0.5
        if (np.clip(a * m, 0, 1) > ALPHA_REF).mean() < target:
            lo = m
        else:
            hi = m
    return (lo + hi) * 0.5


def mip_chain(rgba, alpha_test=True):
    """Mips down to 1x1; alpha rescaled per level so the share of texels passing the test stays put."""
    levels = [rgba]
    cov0 = (rgba[..., 3] > ALPHA_REF).mean()
    cur = rgba
    while cur.shape[0] > 1 or cur.shape[1] > 1:
        h, w = cur.shape[:2]
        if h == 1 or w == 1:
            nh, nw = max(1, h // 2), max(1, w // 2)
            img = Image.fromarray((np.clip(cur, 0, 1) * 255 + 0.5).astype(np.uint8), "RGBA").resize((nw, nh), Image.BOX)
            nxt = np.asarray(img).astype(np.float32) / 255
        else:
            nxt = downsample(cur)
        if alpha_test:
            nxt = nxt.copy()
            nxt[..., 3] = np.clip(nxt[..., 3] * coverage_scale(nxt[..., 3], cov0), 0, 1)
        levels.append(nxt)
        cur = nxt
    return levels


def save(name, rgba, alpha_test=True, mips=True, preview_dir=None, meta=None):
    levels = mip_chain(rgba, alpha_test) if mips else [rgba]
    raw = b"".join((np.clip(l, 0, 1) * 255 + 0.5).astype(np.uint8).tobytes() for l in levels)
    with gzip.open(os.path.join(OUT, name + ".rgba.gz"), "wb", compresslevel=9) as f:
        f.write(raw)
    h, w = rgba.shape[:2]
    if meta is not None:
        meta[name] = [w, h, len(levels)] if mips else [w, h]
    if preview_dir:
        img = (np.clip(rgba, 0, 1) * 255 + 0.5).astype(np.uint8)
        if alpha_test:
            bg = np.zeros_like(img[..., :3]) + np.array([96, 96, 96], np.uint8)
            al = rgba[..., 3:4]
            img = (img[..., :3] * al + bg * (1 - al)).astype(np.uint8)
            Image.fromarray(img, "RGB").save(os.path.join(preview_dir, name + ".png"))
        else:
            Image.fromarray(img[..., :3], "RGB").save(os.path.join(preview_dir, name + ".png"))
    print("  %-26s %dx%d  %d levels  %.0f KB" % (name, w, h, len(levels), os.path.getsize(os.path.join(OUT, name + ".rgba.gz")) / 1024))


def finish(cv, size, aspect=1.0):
    """Supersampled canvas -> final (h, w) albedo RGBA and normal RGBA (rgb normal, a translucency)."""
    rgb = pad_colour(cv.rgb, cv.a)
    nrm = cv.nrm / np.maximum(np.linalg.norm(cv.nrm, axis=-1, keepdims=True), 1e-6)
    nrm = pad_colour(nrm, cv.a)
    tr = pad_colour(cv.tr[..., None].repeat(3, -1), cv.a)[..., 0]
    out_h, out_w = size, int(size * aspect)

    def res(x):
        x = np.ascontiguousarray(x, np.float32)
        chans = [x] if x.ndim == 2 else [x[..., i] for i in range(x.shape[2])]
        r = [np.asarray(Image.fromarray(ch, "F").resize((out_w, out_h), Image.BOX)) for ch in chans]
        return r[0] if x.ndim == 2 else np.stack(r, -1)

    a = np.clip(res(cv.a), 0, 1)
    albedo = np.concatenate([np.clip(res(rgb), 0, 1), a[..., None]], -1)
    n = res(nrm)
    n /= np.maximum(np.linalg.norm(n, axis=-1, keepdims=True), 1e-6)
    normal = np.concatenate([n * 0.5 + 0.5, np.clip(res(tr), 0, 1)[..., None]], -1)
    return albedo, normal


# --- species -----------------------------------------------------------------------------------------------------
def branch_cluster(cv, rng, spec):
    """Twig with side twigs filling a teardrop crown on the card, leaves alternating along every twig."""
    N = cv.n
    root = np.array([N * 0.5, 0.0], np.float32)
    top = np.array([N * (0.5 + rng.uniform(-0.04, 0.04)), N * spec.get("reach", 0.8)], np.float32)
    twigs = [(root, top, 2.6 * SS, 1.2 * SS)]
    for i in range(spec["side_twigs"]):
        t = 0.1 + 0.8 * (i + rng.random() * 0.6) / spec["side_twigs"]
        b = root + (top - root) * t
        side = -1 if i % 2 else 1
        ang = math.pi / 2 + side * rng.uniform(0.55, 1.05)
        ln = N * rng.uniform(0.3, 0.42) * (1.0 - 0.4 * t) * spec.get("spread", 1.0)
        e = b + np.array([math.cos(ang), math.sin(ang)], np.float32) * ln
        twigs.append((b, e, 1.6 * SS, 0.8 * SS))
    for p0, p1, r0, r1 in twigs:
        stroke(cv, p0, p1, r0, r1, srgb(spec["twig"]), tr=0.0)
    leaves = []
    for p0, p1, r0, r1 in twigs:
        d = p1 - p0
        L = float(np.hypot(*d))
        ang0 = math.atan2(d[1], d[0])
        n = max(3, int(L / (spec["spacing"] * N)))
        for k in range(n):
            t = 0.12 + 0.88 * (k + rng.uniform(0.0, 0.5)) / n
            q = p0 + d * t
            side = 1 if k % 2 else -1
            a = ang0 + side * rng.uniform(0.45, 1.15)
            leaves.append((q, a))
        leaves.append((p1, ang0 + rng.uniform(-0.2, 0.2)))
    zs = rng.random(len(leaves))
    for idx in np.argsort(zs):
        q, a = leaves[idx]
        z = zs[idx]
        L = spec["leaf_len"] * N * rng.uniform(0.78, 1.18)
        fore = rng.uniform(0.55, 1.0)                     # leaves turned edge-on look narrower
        W = L * spec["leaf_w"] * fore
        P = L * spec.get("petiole", 0.18)
        col = srgb(spec["greens"][rng.integers(len(spec["greens"]))]) * rng.uniform(0.9, 1.1)
        if rng.random() < spec.get("yellow", 0.04):
            col = srgb((132, 136, 58)) * rng.uniform(0.9, 1.05)
        tilt = (rng.normal(0, 0.28), rng.normal(0, 0.28) - 0.12)
        under = rng.random() < spec.get("under", 0.16)
        if under:
            g = col.mean()
            col = (col * 0.8 + g * 0.2) * 1.12 + np.array([0.0, 0.006, 0.01], np.float32)
        params = dict(spec.get("params", {}))
        params.update(fold=rng.uniform(0.15, 0.4), tilt=tilt, tilt_along=rng.normal(0, 0.15) - 0.3 * (1.0 - fore))
        if under:
            params.update(sec_k=0.45, mid_k=0.75)
        draw_leaf(cv, q, a, L, W, P, spec["shape"], col, z, params, rng)
    return leaves


def gen_broad(rng, N):
    cv = Canvas(N, rng)
    branch_cluster(cv, rng, {
        "side_twigs": 9, "reach": 0.82, "spacing": 0.036, "leaf_len": 0.11, "leaf_w": 0.36, "petiole": 0.16,
        "shape": "ovate", "twig": (96, 76, 56), "yellow": 0.015,
        "greens": [(86, 124, 42), (104, 142, 48), (76, 112, 44), (118, 152, 56), (70, 104, 40), (96, 134, 50)],
        "params": {"veins": 8, "vein_angle": 0.62, "spots": 0.1, "bites": 0.1, "ao_min": 0.66, "cast": 0.2},
    })
    return cv


def gen_oak(rng, N):
    cv = Canvas(N, rng)
    branch_cluster(cv, rng, {
        "side_twigs": 9, "reach": 0.8, "spacing": 0.04, "leaf_len": 0.12, "leaf_w": 0.34, "petiole": 0.08,
        "shape": "lobed", "twig": (90, 72, 54), "yellow": 0.02,
        "greens": [(78, 110, 44), (70, 100, 42), (92, 122, 50), (62, 92, 40), (84, 116, 46)],
        "params": {"veins": 6, "vein_angle": 0.45, "spots": 0.14, "bites": 0.14, "ao_min": 0.62, "cast": 0.2},
    })
    return cv


def gen_shrub(rng, N):
    cv = Canvas(N, rng)
    branch_cluster(cv, rng, {
        "side_twigs": 12, "reach": 0.84, "spacing": 0.024, "leaf_len": 0.065, "leaf_w": 0.42, "petiole": 0.1,
        "shape": "ellipse", "twig": (84, 70, 52), "yellow": 0.01,
        "greens": [(58, 94, 40), (68, 106, 46), (52, 84, 38), (76, 114, 48)],
        "params": {"veins": 6, "vein_angle": 0.7, "spots": 0.05, "bites": 0.05, "ao_min": 0.62, "cast": 0.2},
    })
    return cv


def gen_blossom(rng, N):
    cv = Canvas(N, rng)
    leaves = branch_cluster(cv, rng, {
        "side_twigs": 8, "reach": 0.8, "spacing": 0.042, "leaf_len": 0.105, "leaf_w": 0.33, "petiole": 0.18,
        "shape": "ovate", "twig": (102, 72, 60), "yellow": 0.02,
        "greens": [(106, 142, 56), (120, 156, 64), (94, 130, 52), (112, 148, 60)],
        "params": {"veins": 9, "vein_angle": 0.6, "spots": 0.06, "bites": 0.06, "ao_min": 0.66, "cast": 0.2},
    })
    # flower clusters on short stalks along the twigs
    for i in range(26):
        q, a = leaves[rng.integers(len(leaves))]
        for j in range(rng.integers(2, 4)):
            off = np.array([rng.normal(0, 0.03), rng.normal(0, 0.03)], np.float32) * N
            c = q + off
            stroke(cv, q, c, 0.7 * SS, 0.5 * SS, srgb((120, 110, 60)), tr=0.3, bark=False)
            pink = rng.uniform(0.0, 1.0)
            pa = srgb((250, 238, 242)) * (1 - pink) + srgb((246, 206, 220)) * pink
            pb = srgb((246, 226, 234)) * (1 - pink) + srgb((236, 170, 196)) * pink
            draw_flower(cv, c, N * rng.uniform(0.022, 0.03), rng, rng.uniform(0.6, 1.0), pa, pb)
    return cv


def gen_willow(rng, N):
    cv = Canvas(N, rng)
    strands = 5
    for i in range(strands):
        x0 = N * (0.12 + 0.76 * (i + rng.uniform(0.2, 0.8)) / strands)
        pts = [np.array([x0, 0.0], np.float32)]
        for k in range(8):
            prev = pts[-1]
            pts.append(prev + np.array([rng.normal(0, 0.012) * N, N * 0.12], np.float32))
        for k in range(len(pts) - 1):
            stroke(cv, pts[k], pts[k + 1], (1.6 - 0.12 * k) * SS, (1.5 - 0.12 * k) * SS, srgb((112, 102, 62)), tr=0.1)
        zs = []
        for k in range(len(pts) - 1):
            for j in range(7):
                t = (j + rng.random()) / 7
                q = pts[k] + (pts[k + 1] - pts[k]) * t
                side = 1 if j % 2 else -1
                a = math.pi / 2 + side * rng.uniform(0.25, 0.7)
                zs.append((rng.random(), q, a))
        for z, q, a in sorted(zs, key=lambda e: e[0]):
            L = N * rng.uniform(0.075, 0.105)
            W = L * rng.uniform(0.09, 0.13)
            col = srgb([(118, 146, 70), (104, 134, 62), (132, 156, 80), (110, 140, 74)][rng.integers(4)]) * rng.uniform(0.9, 1.08)
            params = {"veins": 10, "vein_angle": 0.9, "spots": 0.06, "bites": 0.04, "ao_min": 0.6,
                      "fold": rng.uniform(0.2, 0.45), "tilt": (rng.normal(0, 0.3), rng.normal(0, 0.3)), "tilt_along": rng.normal(0, 0.2)}
            draw_leaf(cv, q, a, L, W, L * 0.05, "lance", col, z, params, rng)
    return cv


def gen_needle(rng, N):
    """Spruce branch tip seen from outside: a main shoot with paired side shoots and their own side shoots,
    every shoot a bottle brush of needles, the fresh growth at the tips a lighter green."""
    cv = Canvas(N, rng)
    pal = [srgb(c) for c in [(54, 88, 58), (64, 100, 64), (48, 80, 54), (72, 108, 68), (58, 94, 66)]]
    tip = srgb((116, 152, 78))
    root = np.array([N * 0.5, 0.0], np.float32)
    axis_len = N * 0.94
    shoots = []
    n_side = 12
    for i in range(n_side):
        t = 0.05 + 0.9 * (i + rng.uniform(0.0, 0.5)) / n_side
        b = root + np.array([rng.normal(0, 0.004) * N, axis_len * t], np.float32)
        for side in (-1, 1):
            ang = math.pi / 2 + side * rng.uniform(0.7, 1.0)
            ln = N * (0.42 * (1.0 - 0.7 * t) + 0.1) * rng.uniform(0.85, 1.1)
            shoots.append((rng.random(), b, ang, ln))
    shoots.append((0.5, root, math.pi / 2, axis_len))
    for z, b, ang, ln in sorted(shoots, key=lambda e: e[0]):
        needle_shoot(cv, b, ang, ln, rng, 0.6 + 0.4 * z, pal, tip)
        k_n = int(ln / (N * 0.05))
        for k in range(k_n):
            t = 0.15 + 0.75 * (k + rng.random()) / max(1, k_n)
            q = b + np.array([math.cos(ang), math.sin(ang)], np.float32) * ln * t
            a2 = ang + (1 if k % 2 else -1) * rng.uniform(0.55, 0.9)
            needle_shoot(cv, q, a2, ln * rng.uniform(0.28, 0.4) * (1.0 - 0.45 * t), rng, 0.55 + 0.45 * z * rng.uniform(0.7, 1.0), pal, tip, 0.95)
    return cv


def fbm_aniso(shape, rng, octaves, cells_x, cells_y):
    """Tileable value-noise fBm (0..1) with its own cell counts across (u) and along (v)."""
    h, w = shape
    out = np.zeros(shape, np.float32)
    amp, tot = 1.0, 0.0
    for o in range(octaves):
        nx, ny = cells_x * 2 ** o, cells_y * 2 ** o
        g = rng.random((ny, nx)).astype(np.float32)
        up = ndimage.zoom(g, (h / ny, w / nx), order=3, mode="grid-wrap", grid_mode=True)[:h, :w]
        out += up * amp
        tot += amp
        amp *= 0.5
    out /= tot
    lo, hi = np.percentile(out, 0.5), np.percentile(out, 99.5)
    return np.clip((out - lo) / (hi - lo + 1e-6), 0.0, 1.0)


def gen_bark(rng, w, h):
    """Tileable furrowed bark (u around the trunk, v along it): a meandering net of deep vertical furrows
    between corky ridges, broken across into plates, with grey-green lichen on the ridges."""
    sh = (h, w)
    n1 = fbm_aniso(sh, rng, 4, 9, 2)
    n2 = fbm_aniso(sh, rng, 4, 15, 3)
    f1 = 1.0 - np.abs(2.0 * n1 - 1.0)                     # 1 on the creases
    f2 = 1.0 - np.abs(2.0 * n2 - 1.0)
    furrow = smoothstep(0.58, 0.96, np.maximum(f1, 0.92 * f2)) ** 1.4
    seg = smoothstep(0.55, 0.72, fbm_aniso(sh, rng, 3, 8, 10))
    cracks = smoothstep(0.88, 0.985, 1.0 - np.abs(2.0 * fbm_aniso(sh, rng, 3, 2, 22) - 1.0)) * (1.0 - furrow) * seg
    cork = fbm_aniso(sh, rng, 5, 24, 12)
    fibres = fbm_aniso(sh, rng, 3, 90, 5)
    height = (1.0 - furrow) * (0.7 + 0.2 * cork + 0.1 * fibres) - 0.3 * cracks
    height = ndimage.gaussian_filter(height, 0.6, mode="wrap")
    height = (height - height.min()) / (np.ptp(height) + 1e-6)
    lichen = smoothstep(0.7, 0.84, fbm_aniso(sh, rng, 4, 8, 10)) * smoothstep(0.6, 0.85, height)
    lichen *= 0.6 + 0.4 * fbm_aniso(sh, rng, 2, 40, 40)
    deep, mid, high = srgb((62, 51, 43)), srgb((130, 112, 95)), srgb((188, 172, 154))
    k1 = smoothstep(0.0, 0.45, height)[..., None]
    k2 = smoothstep(0.45, 1.0, height)[..., None]
    rgb = deep * (1 - k1) + mid * k1
    rgb = rgb * (1 - k2) + high * k2
    rgb *= (0.84 + 0.22 * cork + 0.12 * fibres)[..., None]
    rgb = rgb * (1 - 0.7 * lichen[..., None]) + srgb((166, 178, 140)) * (0.7 * lichen[..., None])
    gy, gx = np.gradient(height * 9.0)
    n = np.stack([-gx, -gy, np.ones_like(gx)], -1)
    n /= np.linalg.norm(n, axis=-1, keepdims=True)
    albedo = np.concatenate([np.clip(rgb, 0, 1), np.ones(sh + (1,), np.float32)], -1)
    normal = np.concatenate([n * 0.5 + 0.5, height[..., None]], -1)
    return albedo, normal


def gen_turf(rng, n):
    """Tileable lawn seen from above (for the terrain's grass): a dark thatch of old blades and soil, then
    thousands of short blades in layers, the upper ones fresher and lighter, a few dried to straw.
    Albedo rgb + normal (rgb) with the blade height in alpha."""
    N = n * SS
    cv = Canvas(N, rng)
    thatch = fbm((N, N), rng, octaves=5, base=6, periodic=True)
    cv.rgb[:] = (srgb((52, 58, 30)) * (0.75 + 0.5 * thatch[..., None])).astype(np.float32)
    cv.a[:] = 1.0
    cv.tr[:] = 0.0
    greens = [srgb(c) for c in [(78, 112, 42), (92, 126, 48), (70, 102, 40), (104, 136, 54), (86, 118, 46), (112, 140, 58)]]
    patch = fbm((N, N), rng, octaves=3, base=4, periodic=True)
    layers = 4
    for layer in range(layers):
        z = (layer + 1) / layers
        count = int(9000 * (N / 1024) ** 2 * (1.25 - 0.2 * layer))
        for _ in range(count):
            p0 = rng.random(2) * N
            ang = rng.uniform(0, 2 * math.pi)
            ln = rng.uniform(5, 15) * SS * (0.7 + 0.5 * z)
            p1 = p0 + np.array([math.cos(ang), math.sin(ang)]) * ln
            col = greens[rng.integers(len(greens))] * rng.uniform(0.85, 1.12)
            pv = patch[int(p0[1]) % N, int(p0[0]) % N]
            col = col * (0.88 + 0.24 * pv)
            if rng.random() < 0.04 + 0.05 * pv:
                col = srgb((150, 140, 82)) * rng.uniform(0.85, 1.1)
            col = col * (0.62 + 0.38 * z)
            w0 = rng.uniform(0.9, 1.6) * SS
            for dx in (-N, 0, N):
                for dy in (-N, 0, N):
                    q0, q1 = p0 + (dx, dy), p1 + (dx, dy)
                    if max(q0[0], q1[0]) < -4 or min(q0[0], q1[0]) > N + 4 or max(q0[1], q1[1]) < -4 or min(q0[1], q1[1]) > N + 4:
                        continue
                    stroke(cv, q0, q1, w0, 0.35 * SS, col, tr=0.5, bark=False)
    rgb = cv.rgb
    nrm = cv.nrm / np.maximum(np.linalg.norm(cv.nrm, axis=-1, keepdims=True), 1e-6)
    lum = rgb.mean(-1)
    hgt = np.clip((lum - lum.min()) / (np.ptp(lum) + 1e-6), 0, 1)

    def res(x):
        x = np.ascontiguousarray(x, np.float32)
        chans = [x] if x.ndim == 2 else [x[..., i] for i in range(x.shape[2])]
        r = [np.asarray(Image.fromarray(ch, "F").resize((n, n), Image.BOX)) for ch in chans]
        return r[0] if x.ndim == 2 else np.stack(r, -1)

    albedo = np.concatenate([np.clip(res(rgb), 0, 1), np.ones((n, n, 1), np.float32)], -1)
    nn = res(nrm)
    nn /= np.maximum(np.linalg.norm(nn, axis=-1, keepdims=True), 1e-6)
    normal = np.concatenate([nn * 0.5 + 0.5, res(hgt)[..., None]], -1)
    return albedo, normal


SPECIES = {
    "broad": (gen_broad, 1024, 1.0, 11),
    "oak": (gen_oak, 1024, 1.0, 12),
    "shrub": (gen_shrub, 1024, 1.0, 13),
    "blossom": (gen_blossom, 1024, 1.0, 14),
    "willow": (gen_willow, 1024, 0.5, 15),
    "needle": (gen_needle, 1024, 1.0, 16),
}


def main():
    preview = None
    if "--preview" in sys.argv:
        preview = os.path.join(os.getcwd(), "foliage_preview")
        os.makedirs(preview, exist_ok=True)
    only = [a.split("=", 1)[1] for a in sys.argv if a.startswith("--only=")]
    only = only[0].split(",") if only else None
    meta_path = os.path.join(OUT, "textures.json")
    meta = json.load(open(meta_path))
    for kind, (fn, size, aspect, seed) in SPECIES.items():
        if only and kind not in only:
            continue
        print(kind)
        rng = np.random.default_rng(seed)
        cv = fn(rng, size * SS)
        albedo, normal = finish(cv, size, aspect)
        save("leafhq_" + kind, albedo, True, True, preview, meta)
        save("leafhq_" + kind + "_normal", normal, False, True, preview, meta)
    if not only or "turf" in only:
        print("turf")
        albedo, normal = gen_turf(np.random.default_rng(31), 512)
        save("turf_map", albedo, False, True, preview, meta)
        save("turf_normal", normal, False, True, preview, meta)
    if not only or "bark" in only:
        print("bark")
        albedo, normal = gen_bark(np.random.default_rng(21), 512, 1024)
        save("barkhq_map", albedo, False, True, preview, meta)
        save("barkhq_normal", normal, False, True, preview, meta)
    json.dump(meta, open(meta_path, "w"), separators=(",", ":"))


if __name__ == "__main__":
    main()
