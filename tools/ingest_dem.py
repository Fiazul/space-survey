#!/usr/bin/env python3
"""Ingest raw global elevation grids into assets/planets/*_height_*.png at
16-bit precision.

Godot 4.6.3 flattens a single-channel 16-bit-per-pixel PNG to 8-bit on load
(measured: tools/probe_dem16.gd). The encoding used here instead packs the
16-bit sample across two 8-bit channels of a normal RGB8 PNG:

    value = R * 256 + G          (R = high byte, G = low byte, B unused)

RGB8 is Godot's native uncompressed format, so this round-trips exactly
(measured, same probe). `value` is a 0..65535 sample linearly mapping
[min_m, max_m] for that body -- see the printed calibration block and
assets/planets/SOURCES.txt for the actual numbers per body.

Sources (download to /tmp/planet_maps_raw/ first -- see
docs/research/2026-09-09-dem-ingest.md for exact URLs):
  mars_mola_4ppd.img / .lbl    MOLA MEGDR megt90n000cb  (1440x720,  MSB i16, m)
  mars_mola_16ppd.img / .lbl   MOLA MEGDR megt90n000eb  (5760x2880, MSB i16, m)
  moon_lola_4ppd.img / .lbl    LOLA GDR ldem_4          (1440x720,  LSB i16, x0.5m)
  moon_lola_16ppd.img / .lbl   LOLA GDR ldem_16         (5760x2880, LSB i16, x0.5m)
  etopo_2022_60s_surface.nc    ETOPO 2022 60 arc-sec "surface" grid (NOAA NCEI,
                               21600x10800, float, meters, signed w/ bathymetry)

CLI (per-body, run from repo root):
  python3 tools/ingest_dem.py mars --ppd 4  --size 2048x1024 --out mars_height_2k.png
  python3 tools/ingest_dem.py mars --ppd 16 --size 4096x2048 --out mars_height_4k.png
  python3 tools/ingest_dem.py moon --ppd 4  --size 2048x1024 --out moon_height_2k.png
  python3 tools/ingest_dem.py moon --ppd 16 --size 4096x2048 --out moon_height_4k.png
  python3 tools/ingest_dem.py earth --size 8192x4096 --out earth_height_8k.png

  No args -> legacy behavior: mars+moon at 4ppd/2048x1024 (matches the
  original 2026-09-09 run byte-for-byte).
"""
from __future__ import annotations

import argparse
import hashlib
from pathlib import Path

import numpy as np
from PIL import Image

RAW = Path("/tmp/planet_maps_raw")
DST = Path(__file__).resolve().parents[1] / "assets" / "planets"

# Named landmarks used to cross-check longitude alignment + calibration.
# (name, lat_deg, lon_deg_0_360_east, known_real_elevation_m_or_None)
MARS_LANDMARKS = [
    ("Olympus Mons summit", 18.65, 226.2, 21229.0),
    ("Hellas Planitia floor", -42.4, 70.5, -8200.0),
]
MOON_LANDMARKS = [
    ("Tycho floor", -43.3, 348.6, None),
    # Smith et al. 2010 cite 5.4N, 158.6 WEST (= 201.4E) for the Moon's
    # highest point; verified against this dataset's own argmax (5.4N,
    # 201.4E, +10504 m at 4ppd) -- see docs/research/2026-09-09-dem-ingest.md.
    ("Selenean summit (highest point, 5.4N 158.6W = 201.4E)", 5.4, 201.4, 10786.0),
]
# Earth landmarks: (name, lat, lon_-180_180_east, known real elevation m)
EARTH_LANDMARKS = [
    ("Everest", 27.99, 86.93, 8849.0),
    ("Denali", 63.07, -151.01, 6190.0),
    ("Kilimanjaro", -3.07, 37.35, 5895.0),
    ("Dead Sea shore", 31.5, 35.5, -430.0),
    ("Mariana Trench (Challenger Deep)", 11.35, 142.2, -10935.0),
]


def latlon_to_rowcol_centered(lat: float, lon_e_0_360: float, nrows: int, ncols: int) -> tuple[int, int]:
    """Column convention AFTER to_texture_convention()'s half-width roll:
    lon 0E sits at the horizontal CENTER of the image (matches
    mars_2k.jpg/moon_2k.jpg/earth_2k.jpg, checked empirically -- see
    docs/research/2026-09-09-dem-ingest.md)."""
    row = int((90.0 - lat) / (180.0 / nrows))
    row = min(max(row, 0), nrows - 1)
    col = (int(lon_e_0_360 / (360.0 / ncols)) + ncols // 2) % ncols
    return row, col


def latlon_to_rowcol_signed(lat: float, lon_e_signed: float, nrows: int, ncols: int) -> tuple[int, int]:
    """Same centered convention, but takes -180..180 signed longitude
    (convenience for Earth landmarks, which are conventionally quoted that
    way)."""
    lon_0_360 = lon_e_signed % 360.0
    return latlon_to_rowcol_centered(lat, lon_0_360, nrows, ncols)


def load_mars(ppd: int) -> np.ndarray:
    # MSB_INTEGER (big-endian) i16, meters relative to the areoid, already
    # the value -- no scaling factor in the label.
    name = "mars_mola_4ppd.img" if ppd == 4 else "mars_mola_16ppd.img"
    ncols, nrows = 1440 * (ppd // 4), 720 * (ppd // 4)
    raw = np.fromfile(RAW / name, dtype=">i2").reshape(nrows, ncols)
    return raw.astype(np.float64)


def load_moon(ppd: int) -> np.ndarray:
    # LSB_INTEGER (little-endian) i16. HEIGHT = DN * SCALING_FACTOR, relative
    # to a 1737.4 km reference sphere (OFFSET), per ldem_{4,16}.lbl.
    name = "moon_lola_4ppd.img" if ppd == 4 else "moon_lola_16ppd.img"
    ncols, nrows = 1440 * (ppd // 4), 720 * (ppd // 4)
    raw = np.fromfile(RAW / name, dtype="<i2").reshape(nrows, ncols)
    return raw.astype(np.float64) * 0.5


def load_earth() -> tuple[np.ndarray, bool]:
    """ETOPO 2022 60 arc-sec "surface" grid, meters, signed (bathymetry
    below 0 m, ice-sheet surface elevation over Greenland/Antarctica).
    Returns (array[lat, lon], needs_flip_to_north_at_row0)."""
    import netCDF4  # imported lazily -- only earth ingestion needs it

    ds = netCDF4.Dataset(RAW / "etopo_2022_60s_surface.nc")
    z = ds.variables["z"][:].astype(np.float64)
    lat = ds.variables["lat"][:]
    lon = ds.variables["lon"][:]
    ds.close()
    print(f"  etopo raw shape={z.shape} lat[0]={lat[0]} lat[-1]={lat[-1]} "
          f"lon[0]={lon[0]} lon[-1]={lon[-1]}")
    north_at_row0 = lat[0] > lat[-1]
    return z, north_at_row0


def to_texture_convention(m: np.ndarray, ncols_is_0_360_east: bool = True) -> np.ndarray:
    """Raw PDS raster convention is column 0 = lon 0E, increasing east.
    mars_2k.jpg/moon_2k.jpg (checked empirically against known maria/albedo
    features) instead put lon 0 at the HORIZONTAL CENTER of the image. Roll
    by half the width to match."""
    if not ncols_is_0_360_east:
        return m
    return np.roll(m, m.shape[1] // 2, axis=1)


def resample(m: np.ndarray, out_w: int, out_h: int) -> np.ndarray:
    im = Image.fromarray(m.astype(np.float32), mode="F")
    downsampling = out_w < im.width or out_h < im.height
    method = Image.Resampling.BOX if downsampling else Image.Resampling.BILINEAR
    im = im.resize((out_w, out_h), method)
    return np.array(im, dtype=np.float64)


def pack16(m: np.ndarray, min_m: float, max_m: float) -> np.ndarray:
    norm = (m - min_m) / (max_m - min_m)
    v = np.clip(np.round(norm * 65535.0), 0, 65535).astype(np.uint32)
    hi = (v >> 8).astype(np.uint8)
    lo = (v & 0xFF).astype(np.uint8)
    b = np.zeros_like(hi)
    return np.dstack([hi, lo, b])


def write_import(name: str) -> None:
    template = (DST / "mars_2k.jpg.import").read_text()
    rel = f"res://assets/planets/{name}"
    h = hashlib.md5(rel.encode()).hexdigest()
    uid = "uid://" + hashlib.sha1(rel.encode()).hexdigest()[:13]
    imp = template.replace("mars_2k.jpg", name).replace("uid://bkcxlofl3sg2e", uid)
    imp = imp.replace("7a2d695a775d11f168cf6ae656cf47da", h)
    (DST / (name + ".import")).write_text(imp)


def process_mars_moon(body: str, ppd: int, out_w: int, out_h: int, out_name: str) -> None:
    print(f"=== {body} (ppd={ppd}) -> {out_name} ({out_w}x{out_h}) ===")
    loader = load_mars if body == "mars" else load_moon
    landmarks = MARS_LANDMARKS if body == "mars" else MOON_LANDMARKS
    raw_m = loader(ppd)
    aligned = to_texture_convention(raw_m)
    resized = resample(aligned, out_w, out_h)

    min_m, max_m = float(resized.min()), float(resized.max())
    print(f"resized min_m={min_m:.1f} max_m={max_m:.1f} (raw {ppd}ppd min={raw_m.min():.1f} max={raw_m.max():.1f})")

    packed = pack16(resized, min_m, max_m)
    Image.fromarray(packed, mode="RGB").save(DST / out_name)
    write_import(out_name)
    print("wrote", DST / out_name, packed.shape)

    datum_raw = round((0.0 - min_m) / (max_m - min_m) * 65535.0)
    print(f"datum (0 m) -> raw16={datum_raw}")
    print(f"recipe fields: height_encoding=rg16 height_datum={-min_m/(max_m-min_m)!r} "
          f"height_m_per_unit={max_m-min_m!r} height_max=1.0 height_signed=true")

    for lname, lat, lon, real_m in landmarks:
        row, col = latlon_to_rowcol_centered(lat, lon, out_h, out_w)
        elev = resized[row, col]
        r255, g255 = packed[row, col, 0], packed[row, col, 1]
        raw16 = int(r255) * 256 + int(g255)
        decoded = raw16 / 65535.0 * (max_m - min_m) + min_m
        real_s = f"{real_m:.0f} m" if real_m is not None else "(no confident literature figure)"
        print(f"  {lname} @ lat={lat} lon={lon}E row,col=({row},{col}): "
              f"sampled={elev:.1f} m  R={r255} G={g255} raw16={raw16} decoded={decoded:.1f} m  "
              f"known={real_s}")


def process_earth(out_w: int, out_h: int, out_name: str) -> None:
    print(f"=== earth -> {out_name} ({out_w}x{out_h}) ===")
    raw_m, north_at_row0 = load_earth()
    if not north_at_row0:
        raw_m = np.flipud(raw_m)
        print("  flipped rows: source had south at row 0")
    # ETOPO netCDF lon runs -180..180 with column 0 = lon -180 (standard
    # equirectangular order, i.e. ALREADY "lon 0 at horizontal center" once
    # resampled -- verified below by landmark check, no roll applied).
    aligned = raw_m
    resized = resample(aligned, out_w, out_h)

    min_m, max_m = float(resized.min()), float(resized.max())
    print(f"resized min_m={min_m:.1f} max_m={max_m:.1f} (raw min={raw_m.min():.1f} max={raw_m.max():.1f})")

    packed = pack16(resized, min_m, max_m)
    Image.fromarray(packed, mode="RGB").save(DST / out_name)
    write_import(out_name)
    print("wrote", DST / out_name, packed.shape)

    datum_raw = round((0.0 - min_m) / (max_m - min_m) * 65535.0)
    print(f"datum (0 m) -> raw16={datum_raw}")
    print(f"recipe fields: height_encoding=rg16 height_datum={-min_m/(max_m-min_m)!r} "
          f"height_m_per_unit={max_m-min_m!r} height_max=1.0 height_signed=true")

    for lname, lat, lon, real_m in EARTH_LANDMARKS:
        row, col = latlon_to_rowcol_signed(lat, lon, out_h, out_w)
        elev = resized[row, col]
        r255, g255 = packed[row, col, 0], packed[row, col, 1]
        raw16 = int(r255) * 256 + int(g255)
        decoded = raw16 / 65535.0 * (max_m - min_m) + min_m
        print(f"  {lname} @ lat={lat} lon={lon}E row,col=({row},{col}): "
              f"sampled={elev:.1f} m  R={r255} G={g255} raw16={raw16} decoded={decoded:.1f} m  "
              f"known={real_m:.0f} m")


def parse_size(s: str) -> tuple[int, int]:
    w, h = s.lower().split("x")
    return int(w), int(h)


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("body", nargs="?", choices=["mars", "moon", "earth"], default=None)
    ap.add_argument("--ppd", type=int, choices=[4, 16], default=4, help="mars/moon only")
    ap.add_argument("--size", type=str, default=None, help="WxH, e.g. 2048x1024")
    ap.add_argument("--out", type=str, default=None, help="output filename under assets/planets/")
    args = ap.parse_args()

    DST.mkdir(parents=True, exist_ok=True)

    if args.body is None:
        # Legacy: reproduce the original 2026-09-09 run exactly.
        process_mars_moon("mars", 4, 2048, 1024, "mars_height_2k.png")
        process_mars_moon("moon", 4, 2048, 1024, "moon_height_2k.png")
        return

    if args.body == "earth":
        out_w, out_h = parse_size(args.size) if args.size else (8192, 4096)
        out_name = args.out or "earth_height_8k.png"
        process_earth(out_w, out_h, out_name)
        return

    out_w, out_h = parse_size(args.size) if args.size else (2048, 1024)
    default_name = f"{args.body}_height_{'2k' if args.ppd == 4 else '4k'}.png"
    out_name = args.out or default_name
    process_mars_moon(args.body, args.ppd, out_w, out_h, out_name)


if __name__ == "__main__":
    main()
