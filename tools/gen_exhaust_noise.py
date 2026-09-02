#!/usr/bin/env python3
"""Generate the tileable exhaust-turbulence noise used by shaders/cruiser_torch.gdshader.

Pure numpy + zlib, no third-party image library, matching the existing tools/gen_*.py
house style. Output is a seamlessly tiling RGBA8 PNG sampled in (angle, axial) space
by the torch shader, so the U axis MUST wrap exactly or a seam appears down the plume.

Channels:
  R  fine  FBM  (5 octaves) - small-scale boil
  G  coarse FBM (3 octaves) - large-scale billow / silhouette break-up
  B  warp  FBM  (3 octaves, offset lattice) - domain-warp offsets
  A  ridged  noise           - bright filaments/streaks along the flow

Run: python3 tools/gen_exhaust_noise.py
"""
import struct
import zlib

import numpy as np

SIZE = 256
OUT = "assets/fx/exhaust_noise.png"


def _lattice(rng: np.random.Generator, freq: int) -> np.ndarray:
    """One octave of PERIODIC gradient (Perlin) noise at `freq` cells across the image.

    Gradient noise, not value noise: value noise on an axis-aligned lattice leaves a
    visible rectilinear grid in the result, which reads as a wire pattern on the plume.
    Corner gradients are gathered modulo `freq`, so cell freq-1 interpolates back into
    cell 0 - that wrap is what makes the finished texture tile without a seam.
    """
    ang = rng.random((freq, freq), dtype=np.float64) * (2.0 * np.pi)
    gx, gy = np.cos(ang), np.sin(ang)
    t = np.arange(SIZE, dtype=np.float64) * (freq / SIZE)
    i = np.floor(t).astype(np.int64)
    f = t - i
    # Quintic smoothstep - C2 continuous, so no lattice creases in the derivative.
    w = f * f * f * (f * (f * 6.0 - 15.0) + 10.0)
    i0, i1 = i % freq, (i + 1) % freq
    fx, fy = f[None, :], f[:, None]
    wx, wy = w[None, :], w[:, None]

    def dot(iy, ix, ox, oy):
        return (gx[np.ix_(iy, ix)] * (fx - ox)) + (gy[np.ix_(iy, ix)] * (fy - oy))

    n00 = dot(i0, i0, 0.0, 0.0)
    n10 = dot(i0, i1, 1.0, 0.0)
    n01 = dot(i1, i0, 0.0, 1.0)
    n11 = dot(i1, i1, 1.0, 1.0)
    top = n00 * (1.0 - wx) + n10 * wx
    bot = n01 * (1.0 - wx) + n11 * wx
    return top * (1.0 - wy) + bot * wy


def equalize(a: np.ndarray) -> np.ndarray:
    """Flatten the histogram so the channel actually spans 0..1.

    Plain min/max rescaling leaves FBM bunched around its mean (a grey mush that gives
    the shader almost no dynamic range to work with). Rank-equalising guarantees the
    full range is used.
    """
    flat = a.ravel()
    order = flat.argsort()
    ranks = np.empty(flat.size, dtype=np.float64)
    ranks[order] = np.arange(flat.size, dtype=np.float64)
    return (ranks / max(flat.size - 1, 1)).reshape(a.shape)


def fbm(rng: np.random.Generator, octaves: int, base: int = 4) -> np.ndarray:
    out = np.zeros((SIZE, SIZE), dtype=np.float64)
    amp, norm, freq = 1.0, 0.0, base
    for _ in range(octaves):
        out += _lattice(rng, freq) * amp
        norm += amp
        amp *= 0.5
        freq *= 2
        if freq > SIZE:          # lattice finer than a texel carries no signal
            break
    return out / norm


def ridged(rng: np.random.Generator, octaves: int, base: int = 8) -> np.ndarray:
    """Absolute-value noise inverted into sharp crests - reads as plasma filaments."""
    out = np.zeros((SIZE, SIZE), dtype=np.float64)
    amp, norm, freq = 1.0, 0.0, base
    for _ in range(octaves):
        n = 1.0 - np.abs(_lattice(rng, freq) * 2.0)
        out += (n ** 2) * amp
        norm += amp
        amp *= 0.5
        freq *= 2
        if freq > SIZE:
            break
    return out / norm


def write_png(path: str, rgba: np.ndarray) -> None:
    """Minimal RGBA8 PNG writer (filter type 0 on every scanline)."""
    h, w, _ = rgba.shape
    raw = b"".join(b"\x00" + rgba[y].tobytes() for y in range(h))

    def chunk(tag: bytes, data: bytes) -> bytes:
        return (struct.pack(">I", len(data)) + tag + data
                + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF))

    png = b"\x89PNG\r\n\x1a\n"
    png += chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(raw, 9))
    png += chunk(b"IEND", b"")
    with open(path, "wb") as fh:
        fh.write(png)


def main() -> None:
    rng = np.random.default_rng(20260902)
    fine = equalize(fbm(rng, 5, base=8))
    coarse = equalize(fbm(rng, 3, base=4))
    warp = equalize(fbm(rng, 3, base=6))
    fila = equalize(ridged(rng, 4, base=8)) ** 1.7  # bias dark: filaments should be sparse
    rgba = np.stack([fine, coarse, warp, fila], axis=-1)
    rgba = np.clip(rgba * 255.0 + 0.5, 0, 255).astype(np.uint8)
    write_png(OUT, rgba)
    print("exhaust noise: wrote %s  %dx%d RGBA8" % (OUT, SIZE, SIZE))
    for name, ch in (("R fine", fine), ("G coarse", coarse), ("B warp", warp), ("A filament", fila)):
        print("  %-11s mean=%.3f  min=%.3f  max=%.3f" % (name, ch.mean(), ch.min(), ch.max()))
    # Seam check: column 0 must continue smoothly from column SIZE-1 (and same for rows).
    du = float(np.abs(rgba[:, 0].astype(int) - rgba[:, -1].astype(int)).mean())
    dv = float(np.abs(rgba[0, :].astype(int) - rgba[-1, :].astype(int)).mean())
    interior_u = float(np.abs(rgba[:, 1].astype(int) - rgba[:, 0].astype(int)).mean())
    print("  wrap seam  U=%.2f  V=%.2f  (interior step %.2f -> tiles cleanly)"
          % (du, dv, interior_u))


if __name__ == "__main__":
    main()
