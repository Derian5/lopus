"""Ground decals for the battlefield: blood splats and scorch marks.
Writes graphics/effects/vfx/ground_decals.png: a 4x3 grid of 128 px cells.
Rows 0-1: eight blood splats; row 2: four scorch marks. Run: python tools/vfx/gen_decals.py"""
import os
import numpy as np
from PIL import Image

CELL = 128
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', 'graphics', 'effects', 'vfx', 'ground_decals.png')


def smooth(t):
    t = np.clip(t, 0, 1)
    return t * t * (3 - 2 * t)


def blob_field(rng, cx, cy, radius, lobes=6, rough=0.22, size=CELL):
    yy, xx = np.mgrid[0:size, 0:size].astype(np.float32)
    dx, dy = xx - cx, yy - cy
    ang = np.arctan2(dy, dx)
    r = np.sqrt(dx * dx + dy * dy)
    edge = np.ones_like(ang)
    for k in range(2, 2 + lobes):
        edge += rng.uniform(-rough, rough) / (k * 0.5) * np.cos(k * ang + rng.uniform(0, 6.28))
    return radius * edge - r  # > 0 inside


def value_noise(rng, cells, amp, size=CELL):
    small = rng.normal(0, 1, (cells, cells)).astype(np.float32)
    img = Image.fromarray(((small - small.min()) / (np.ptp(small) + 1e-6) * 255).astype(np.uint8))
    big = np.asarray(img.resize((size, size), Image.BICUBIC)).astype(np.float32) / 255.0
    return (big - 0.5) * 2 * amp


def streak(rng, cx, cy, angle, length, width, size=CELL):
    """An elongated drop flung outward (ellipse along the throw)."""
    yy, xx = np.mgrid[0:size, 0:size].astype(np.float32)
    dx, dy = xx - cx, yy - cy
    u = dx * np.cos(angle) + dy * np.sin(angle)
    v = -dx * np.sin(angle) + dy * np.cos(angle)
    return width - np.sqrt((u / (length / width)) ** 2 + v * v)


def splat(rng):
    c = CELL / 2
    big = rng.uniform(17, 26)
    field = blob_field(rng, c, c, big, rough=0.3)
    # secondary lobes stuck to the main pool
    for _ in range(rng.integers(2, 5)):
        a = rng.uniform(0, 6.28)
        d = big * rng.uniform(0.6, 1.0)
        field = np.maximum(field, blob_field(rng, c + np.cos(a) * d, c + np.sin(a) * d, big * rng.uniform(0.35, 0.6), rough=0.2))
    # flung droplets, mostly to one side
    main = rng.uniform(0, 6.28)
    for _ in range(rng.integers(8, 16)):
        a = main + rng.normal(0, 0.8)
        d = big * rng.uniform(1.2, 2.3)
        x, y = c + np.cos(a) * d, c + np.sin(a) * d
        if 6 < x < CELL - 6 and 6 < y < CELL - 6:
            field = np.maximum(field, blob_field(rng, x, y, rng.uniform(1.2, 4.0), lobes=3, rough=0.15))
    for _ in range(rng.integers(3, 7)):
        a = main + rng.normal(0, 0.6)
        d = big * rng.uniform(1.0, 1.7)
        field = np.maximum(field, streak(rng, c + np.cos(a) * d, c + np.sin(a) * d, a, rng.uniform(7, 14), rng.uniform(1.4, 2.6)))
    field = field + value_noise(rng, 14, 2.2) + value_noise(rng, 40, 0.8)
    alpha = smooth((field + 1.2) / 2.4)
    depth = smooth(field / 9.0)  # 0 at the rim, 1 deep inside
    inner = np.array([98, 6, 10], np.float32)
    rim = np.array([46, 3, 5], np.float32)
    rgb = rim[None, None, :] * (1 - depth[..., None]) + inner[None, None, :] * depth[..., None]
    tone = value_noise(rng, 10, 0.18)[..., None]
    rgb = np.clip(rgb * (1 + tone) + rng.normal(0, 3, (CELL, CELL, 1)), 0, 255)
    a = alpha * (0.78 + 0.18 * depth)
    return np.dstack([rgb, a * 255]).astype(np.uint8)


def scorch(rng):
    c = CELL / 2
    field = blob_field(rng, c, c, rng.uniform(38, 48), lobes=8, rough=0.28)
    alpha = smooth((field + 14) / 34.0)
    yy, xx = np.mgrid[0:CELL, 0:CELL].astype(np.float32)
    grain = rng.normal(0, 1, (CELL, CELL))
    from_center = np.sqrt((xx - c) ** 2 + (yy - c) ** 2) / 50.0
    dark = np.clip(1.0 - from_center * 0.6, 0, 1)
    rgb = np.dstack([18 + 30 * (1 - dark) + grain * 4, 12 + 18 * (1 - dark) + grain * 3, 10 + 10 * (1 - dark) + grain * 2])
    a = alpha * (0.55 + 0.35 * dark) * (0.9 + 0.1 * grain.clip(-1, 1))
    return np.dstack([np.clip(rgb, 0, 255), np.clip(a, 0, 1) * 255]).astype(np.uint8)


def main():
    rng = np.random.default_rng(7)
    sheet = np.zeros((CELL * 3, CELL * 4, 4), np.uint8)
    for i in range(8):
        r, col = divmod(i, 4)
        sheet[r * CELL:(r + 1) * CELL, col * CELL:(col + 1) * CELL] = splat(rng)
    for i in range(4):
        sheet[2 * CELL:3 * CELL, i * CELL:(i + 1) * CELL] = scorch(rng)
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    Image.fromarray(sheet).save(OUT, optimize=True)
    print('wrote', os.path.normpath(OUT))


if __name__ == '__main__':
    main()
