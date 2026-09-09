# 2026-09-09 — Real DEM ingest for Mars + Moon (evidence-driven recipes)

Goal: get real global topography for Mars and the Moon into `assets/planets/`
at 16-bit precision, and prove that precision survives Godot's import. Data
files landed; code that consumes them (`TerrainSampler`, `SurfaceRecipe`,
`planet_cook.gdshader`) is NOT changed by this note — see "Where the recipe
code still needs to change" at the end.

## Sources

Both are PDS3-labelled global grids from the PDS Geosciences Node, public
domain (US government work), 4 pixels/degree, 1440x720, 16-bit integer,
simple cylindrical (equirectangular), `CENTER_LONGITUDE=180`,
`WESTERNMOST_LONGITUDE=0`, `EASTERNMOST_LONGITUDE=360`, positive-east.

- **Mars** — MGS MOLA MEGDR topography, `megt90n000cb.img`/`.lbl`:
  https://pds-geosciences.wustl.edu/mgs/mgs-m-mola-5-megdr-l3-v1/mgsl_300x/meg004/megt90n000cb.img
  MSB_INTEGER (big-endian) i16, unit = meter, no scaling factor (DN is the
  elevation directly), datum = areoid (Goddard Mars potential model
  GMM3/mgm1025). Body radius used for the projection: 3396.0 km sphere.
  Label states dataset min/max: -8068 m / +21134 m.
- **Moon** — LRO LOLA GDR shape map, `ldem_4.img`/`.lbl`:
  https://pds-geosciences.wustl.edu/lro/lro-l-lola-3-rdr-v1/lrolol_1xxx/data/lola_gdr/cylindrical/img/ldem_4.img
  LSB_INTEGER (little-endian) i16, `HEIGHT_m = DN * 0.5` (SCALING_FACTOR),
  relative to a 1737.4 km reference **sphere** (OFFSET) — a sphere, not a
  geoid, matching CLAUDE.md's expectation for the Moon. Label states dataset
  min/max: -17758*0.5 = -8879.0 m / +21008*0.5 = 10504.0 m.

Both chosen over the higher-resolution MOLA/LOLA products (128 ppd/463 m,
would be tens of GB) specifically because they're the smallest *global,
single-file* products at a usable pixel-per-degree count — 2 MB each as
downloaded. sha256 + full calibration numbers: `assets/planets/SOURCES.txt`.

## Longitude convention — two different conventions in this repo now

The raw PDS files use column 0 = lon 0E, increasing east (standard raster
convention for that data product). **Checked empirically**: Mars's global
argmax sample (21134 m, exactly the label's stated dataset max) sits at row
290/col 907 of the raw 1440x720 grid → lat 17.4N, lon 226.9E — within ~1
pixel of Olympus Mons's real coordinates (18.65N, 226.2E). That's strong,
direct confirmation the raw-file convention is "col 0 = lon 0E" with no
shift needed to read the PDS files themselves correctly.

But `assets/planets/mars_2k.jpg` and `moon_2k.jpg` (the existing albedo
textures this DEM has to align with) use a **different** convention: lon 0E
sits at the image's **horizontal center**, not its left edge. Checked by
luminance contrast at known dark/bright landmarks (`/tmp` throwaway script,
not checked in):

| region (known albedo) | expected | lum, no shift | lum, half-width shift |
|---|---|---|---|
| Syrtis Major (dark) | dark | 145.9 (wrong) | 58.9 (right) |
| Tharsis (bright/dusty) | bright | 52.5 (wrong) | 143.7 (right) |
| Oceanus Procellarum (dark mare) | dark | 203.7 (wrong) | 80.2 (right) |
| Descartes highlands (bright) | bright | 202.8 (wrong) | 174.2 (right) |
| Far-side highlands (bright) | bright | 100.5 (wrong) | 192.3 (right) |

Every one of 8 landmark checks across both bodies flips from wrong to right
under the half-width roll — this is the convention `mars_2k.jpg`/`moon_2k.jpg`
actually use, not an assumption. `tools/ingest_dem.py`'s
`to_texture_convention()` does `np.roll(dem, w // 2, axis=1)` before
resampling, so `mars_height_2k.png`/`moon_height_2k.png` line up
texel-for-texel with the existing albedo maps. **Any future DEM ingest for a
body sharing this repo's existing texture convention needs the same roll —
do not assume PDS/USGS column 0 is this repo's column 0.**

## 16-bit encoding — measured, not assumed

`tools/probe_dem16.gd` (`godot --headless --script tools/probe_dem16.gd`)
built a 4x4 test PNG with two adjacent 16-bit values (12345, 12347) that
share the same **high byte** (0x30) and would collapse to an identical
8-bit sample if Godot quantized on load. Result:

```
--- probe_dem16: Image.load() path ---
format=0 (Image.FORMAT_L8=0 ...)
pixel(0,0) -> r*65535= 12336.0002412647
pixel(1,0) -> r*65535= 12336.0002412647
12345 vs 12347 distinguishable after Godot load (16-bit survives if true): false
```

**Confirmed: Godot 4.6.3 flattens a single-channel 16-bit grayscale PNG to
`FORMAT_L8` (8-bit) on load**, both via `Image.load()` and
`Image.load_png_from_buffer()`. 12345 and 12347 both decode to 12336
(≈ 48 * 257, i.e. only the high byte survived).

Fallback tested in the same run: pack the 16-bit sample as
`R = value >> 8, G = value & 0xFF` in an ordinary RGB8 PNG (B unused). RGB8
is a native Godot format (no implicit bit-depth reduction), and the probe's
third section round-trips all 16 test values exactly:

```
--- probe_dem16: R=hi/G=lo byte-pack fallback (RGB8, no 16-bit format involved) ---
format=4 (expect FORMAT_RGB8=4)
(0, 0) R=48 G=57 decoded=12345 expected=12345 match=true
(1, 0) R=48 G=59 decoded=12347 expected=12347 match=true
... [16/16 match=true]
pack16_roundtrip: OK
```

**Format decision: `value = R*256 + G`**, RGB8 PNG, matches
`assets/planets/mars_height_2k.png` / `moon_height_2k.png`.

Both files' `.import` use `compress/mode=0` ("Lossless") and
`mipmaps/generate=false`, copied from the existing `mars_2k.jpg.import`
template (every file in `assets/planets/` already uses `compress/mode=0`,
even the `.jpg` sources — this project already treats "Lossless" as the
house style for these maps, not something new introduced here).

**Residual gap, not independently verified**: the probe above loads the PNG
by absolute filesystem path with plain `Image.load()`/`load_png_from_buffer()`
— it does not exercise the real `res://` import pipeline (`load(path) as
Texture2D` → `.get_image()` → `CompressedTexture2D`) that `TerrainSampler._img_of()`
actually uses. I could not test that path: it requires Godot to have already
generated a `.godot/imported/*.ctex` cache entry for the new file, which only
happens via a real editor import or `godot --headless --import` — both
outside this brief's constraint (`only godot --headless --script
tools/probe_dem16.gd`), and risky to run against a project directory whose
editor is open in another process. The claim that `compress/mode=0` doesn't
requantize an already-8-bit-per-channel RGB8 image rests on Godot's
documented meaning of "Lossless" (no quantization/compression artifacts by
definition), not on a fresh empirical run — flagging this so whoever wires
`TerrainSampler` to read these files runs that check once for real (e.g. add
a `test_*.gd` scene-based test that loads `mars_height_2k.png` through the
normal `load()` path and asserts a couple of known R/G values, the same way
`tools/test_earth_terrain.gd` pins `earth_height.jpg`'s calibration).

## Calibration table

Full numbers (min_m/max_m per body, decode formula, landmark samples vs.
known real elevations) are in `assets/planets/SOURCES.txt` under "Real
global topography". Summary:

| body | min_m | max_m | datum raw16 | landmark check |
|---|---|---|---|---|
| Mars | -7941.6 | 21083.6 | 17931 | Olympus Mons 19774 m sampled vs ~21229 m known; Hellas floor -6136.8 m sampled vs ~-8200 m known (4 ppd = ~14.8 km/px undersamples both peaks) |
| Moon | -8585.2 | 10356.6 | 29703 | Selenean summit (Moon's highest point) 10356.6 m sampled vs ~10786 m known; Tycho floor -2267.5 m sampled, no confident published absolute figure to check against, flagged as non-calibration-grade (crater is only ~11 px wide at native resolution) |

decode: `elevation_m = (R*256+G)/65535 * (max_m - min_m) + min_m`.

## Where the recipe/sampler code will need to change (not done here)

Three places, all inside files this brief was explicitly told not to touch:

1. `scripts/world/terrain_sampler.gd:25-32` — `DEM_SEA_LEVEL`,
   `DEM_PEAK_VALUE`, `DEM_PEAK_M`, `DEM_MAX_VALUE`, `DEM_HAS_BATHYMETRY` are
   one set of Earth-specific constants on the `TerrainSampler` class, not
   per-body data. Mars/Moon need their own min_m/max_m/datum (this doc's
   table) and `DEM_HAS_BATHYMETRY = true` semantics (there's no ocean to
   clamp to — the whole point of these two bodies is that basins are real,
   negative terrain, same as the airless-noise-world branch already handles).
2. `scripts/world/terrain_sampler.gd:487-492` (`_load_gray`) hardcodes
   `img.convert(Image.FORMAT_R8)` — for the new bodies this needs to read
   R **and** G (the value is `R*256+G`, not `R` alone), so `_load_gray`/
   `_bilinear_bytes` need a second byte-array path (or a format flag on
   `SurfaceRecipe`) for two-channel DEMs vs. Earth's existing single-channel
   one.
3. `shaders/planet_cook.gdshader:107-112` (`sample_height`) reads only
   `texture(height_tex, uv).r` — same fix needed on the GPU side, and per
   CLAUDE.md's "touch one, touch both" rule this has to move in lockstep
   with `PlanetGenerator.crust_height()`/`TerrainSampler.base_height_m()`.

## Reproduction

```
mkdir -p /tmp/planet_maps_raw
curl -o /tmp/planet_maps_raw/mars_mola_4ppd.img https://pds-geosciences.wustl.edu/mgs/mgs-m-mola-5-megdr-l3-v1/mgsl_300x/meg004/megt90n000cb.img
curl -o /tmp/planet_maps_raw/moon_lola_4ppd.img https://pds-geosciences.wustl.edu/lro/lro-l-lola-3-rdr-v1/lrolol_1xxx/data/lola_gdr/cylindrical/img/ldem_4.img
python3 tools/ingest_dem.py
godot --headless --script tools/probe_dem16.gd
```

## 2026-09-09 later: 8k Earth / 4k Mars+Moon

Data-only follow-up (see brief: task did not touch any `.gd`/`.gdshader` —
recipe wiring for these three new files is still someone else's job, same as
the section above). All three raw sources downloaded fresh this session,
sha256 + full numbers in `assets/planets/SOURCES.txt`; only the derived
recipe-field table is repeated here per the brief's instruction to append it.

**Format reader used**: `numpy.fromfile` for the Mars/Moon PDS3 `.img` grids
(unchanged from the section above, just a bigger `ppd`), `netCDF4` (pip
`--user` install, wheel bundles its own HDF5/netCDF libs, no system GDAL
needed) for the Earth ETOPO grid. `rasterio` was also pip-installed as a
fallback in case `netCDF4` couldn't read the file, but wasn't needed in the
end — `netCDF4.Dataset(...).variables["z"][:]` read the full 21600x10800
`float32` grid directly.

**Sources**:
- Mars 16 ppd — MOLA MEGDR `megt90n000eb.img`/`.lbl`, same PDS path as the
  4 ppd file (`.../meg016/` instead of `.../meg004/`), 5760x2880,
  MSB_INTEGER i16, meter, areoid datum. Label's own stated dataset min/max
  (`-8177`/`+21171` m) match this file's actual min/max exactly.
- Moon 16 ppd — LOLA GDR `ldem_16.img`/`.lbl`, same directory as `ldem_4`,
  5760x2880, LSB_INTEGER i16, `HEIGHT_m = DN * 0.5`, 1737.4 km reference
  sphere. Label states max/min `21580`/`-18150` raw DN (`10790`/`-9075` m)
  as the theoretical encoding range; the actual data's min/max are tighter
  (`-8981.5`/`+10685.5` m).
- Earth — ETOPO 2022 v1, 60 arc-second, "surface" product (ice-sheet top,
  not bedrock), NOAA NCEI THREDDS server, single global netCDF, 21600x10800,
  `float32` meters, EGM2008-referenced (≈ mean sea level = 0 m), public
  domain. 478.29 MB downloaded (matches the THREDDS catalog's listed
  "478.2 Mbytes" almost exactly). GEBCO 2024 was not needed — ETOPO's single
  60 arc-sec global file was small enough and simple enough (plain lat/lon
  grid, no tiling) to use directly.

**Longitude/orientation, checked not assumed**: read straight from the
netCDF's own `lat`/`lon` coordinate variables (not inferred from the PDS
label convention used for Mars/Moon) — `lat[0]=-89.99` (south) to
`lat[-1]=89.99` (north), so the raw array needed a row-flip (`np.flipud`)
before resampling; `lon[0]=-179.99` to `lon[-1]=179.99`, i.e. column 0 is
already lon -180 — the SAME "lon 0 at horizontal center" convention this
repo's albedo/height maps already use, so (unlike Mars/Moon) **no** longitude
roll was applied for Earth. Confirmed after the fact: the resampled array's
own global maximum sample sits at decoded (27.99N, 86.92E) — Everest's real
coordinate to within 0.01 degree, and Greenland (72N, -40W) samples bright/
high (ice-sheet surface, not a wrongly-oriented ocean read as land).

**Files + sizes**:

| file | dims | bytes | sha256 (first 16 hex) |
|---|---|---|---|
| `assets/planets/mars_height_4k.png` | 4096x2048 | 11,948,575 | `a20f0239a23a5cf1` |
| `assets/planets/moon_height_4k.png` | 4096x2048 | 14,215,904 | `574ca5f3a8dbcaf1` |
| `assets/planets/earth_height_8k.png` | 8192x4096 | 49,023,797 | `9513678f4f9d61c4` |

Total new bytes: 75,188,276 (~71.7 MiB) — under the ~120 MB budget; no file
exceeds ~50 MB (`earth_height_8k.png` is the largest at 49.0 MB, just under
the ~50 MB single-file guideline).

**Recipe field values** (same derivation as the Mars/Moon 2k table above:
`height_datum = -min_m/(max_m-min_m)`, `height_m_per_unit = max_m-min_m`,
`height_max = 1.0`, `height_signed = true`, `height_texel_km = (2*pi*R_km)/out_w`):

| body/map | min_m | max_m | height_datum | height_m_per_unit | height_max | height_signed | height_texel_km |
|---|---|---|---|---|---|---|---|
| Mars `mars_height_4k.png` | -8163.0 | 21171.0 | 0.27827776641439966 | 29334.0 | 1.0 | true | 5.20940 |
| Moon `moon_height_4k.png` | -8981.5 | 10622.0 | 0.45815798199301144 | 19603.5 | 1.0 | true | 2.66514 |
| Earth `earth_height_8k.png` | -10708.2 | 7198.3 | 0.5980075212736995 | 17906.5 | 1.0 | **true** (existing `Earth` recipe entry is `height_signed: false` — see below) | 4.88579 |

Compare to the existing 2k table (`min_m/max_m`, both bodies): Mars 2k
`-7941.6/21083.6` → 4k `-8163.0/21171.0` (max climbed to within 58 m of the
label's stated true dataset max 21171; min climbed to within 14 m of the
stated true min -8177). Moon 2k `-8585.2/10356.6` → 4k `-8981.5/10622.0`
(both extremes moved outward, closer to the fuller native range). This
matches the brief's expectation ("Olympus toward 21.2 km, Hellas toward
−8.2 km") for the file's overall min/max — the fixed single-point landmark
samples (Olympus Mons summit, Hellas floor) did NOT uniformly improve
alongside it: Olympus sampled 19963.5 m (up from 19774.0 m, better) but
Hellas sampled -6072.0 m (up from -6136.8 m, i.e. LESS deep than before).
Root cause, checked directly against the raw 16 ppd grid: the fixed
landmark coordinates (18.65N/226.2E, -42.4N/70.5E) are not exactly the
dataset's own extremum pixels at either resolution. The 16 ppd file's own
global argmax sits at (17.375N, 226.9375E) = 21171 m — within ~1.3 px of
Olympus's real summit, same as the 4 ppd file's argmax was within ~1 px —
but the global argmin sits at (-32.8125N, 62.1875E) = -8177 m, about 10
degrees of latitude from the named "Hellas floor" coordinate, i.e. a
different, shallower part of the same basin margin. This is the same
"named point isn't the extremum pixel" caveat the original 2 ppd table
already flagged for Hellas, not a resolution regression — the underlying
16 ppd data genuinely reaches closer to the real extreme, the point sample
at that one fixed coordinate just doesn't land on it. Full landmark tables
(all values, both resolutions) are in `assets/planets/SOURCES.txt`.

**Earth signedness note**: `planet_generator.gd`'s current `Earth` RECIPES
entry (`"height_encoding": "r8"`, `"height_signed": false`) is unchanged by
this task — this is a data-only brief, no `.gd` edits. `earth_height_8k.png`
is a ready drop-in replacement candidate, but wiring it in means someone
must decide: flip `Earth`'s recipe to `"height_encoding": "rg16"`,
`"height_signed": true` with the numbers in the table above, AND decide what
the sampler/shader do with negative (below-datum) samples now that they're
real bathymetry, not clamped noise. Recommendation (not enforced, no code
touched): keep the existing sea-level water plate rendering as-is (so the
visible ocean surface doesn't change) but let `TerrainSampler`'s underlying
height function report the real negative depth for anything under the water
plate — this only matters for e.g. contact/depth queries below the plate,
never for what's drawn, and costs nothing visually while making the
"crust height and displayed geometry agree" contract (PLANET_GENERATOR.md)
still hold for whichever future feature (submarine flight? depth readout?)
wants the real number. Clamping instead (discarding the bathymetry
entirely) is the simpler, lower-risk alternative if that future feature
never materializes — genuinely a judgment call for whoever does the wiring,
flagged here rather than decided.

**Reproduction (this later run)**:

```
mkdir -p /tmp/planet_maps_raw
curl -o /tmp/planet_maps_raw/mars_mola_16ppd.img https://pds-geosciences.wustl.edu/mgs/mgs-m-mola-5-megdr-l3-v1/mgsl_300x/meg016/megt90n000eb.img
curl -o /tmp/planet_maps_raw/moon_lola_16ppd.img https://pds-geosciences.wustl.edu/lro/lro-l-lola-3-rdr-v1/lrolol_1xxx/data/lola_gdr/cylindrical/img/ldem_16.img
curl -o /tmp/planet_maps_raw/etopo_2022_60s_surface.nc https://www.ngdc.noaa.gov/thredds/fileServer/global/ETOPO2022/60s/60s_surface_elev_netcdf/ETOPO_2022_v1_60s_N90W180_surface.nc
pip3 install --user netCDF4
python3 tools/ingest_dem.py mars --ppd 16 --size 4096x2048 --out mars_height_4k.png
python3 tools/ingest_dem.py moon --ppd 16 --size 4096x2048 --out moon_height_4k.png
python3 tools/ingest_dem.py earth --size 8192x4096 --out earth_height_8k.png
```

**Not verified in this pass** (same residual gap as the section above, now
also true for these three new files): the real `res://` import pipeline
(`load()` → `.get_image()` → `CompressedTexture2D`) was not exercised for
`mars_height_4k.png`/`moon_height_4k.png`/`earth_height_8k.png` — only
`Image.load()` via plain PIL/numpy (used to derive the calibration numbers
above), same constraint as before (no `godot --headless --import` run
against a project whose editor may be open in another process). Whoever
wires these into the recipes should extend `tools/test_dem_calibration.gd`'s
existing real-import check to cover the new files' known R/G byte pairs, not
assume the 2k files' passing result generalizes.
