# Earth Flyover Terrain Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fly Earth from 15 km down to the ground with real relief under the hull, and die by hitting terrain instead of by crossing an altitude.

**Architecture:** One `TerrainSampler` owns the only height function in the system; both the mesh builder and the kill test call it, so geometry and lethality can never disagree. The single ground plate becomes four nested rings (50 m quads underfoot, 3.2 km quads at 205 km) so detail and reach stop competing. The band's ceiling is derived from the terrain's own maximum height rather than authored, and an altitude-ramped speed cap bounds per-frame movement so a swept contact test is sound.

**Tech Stack:** Godot 4.6.3, GDScript. No new dependencies. Tests are headless `SceneTree` scripts under `tools/`.

## Global Constraints

- Godot 4.6.3 stable. GDScript only, no C# and no GDExtension.
- **`ship.speed_limit` and `PlanetSystem.speed_limit` are in UNITS PER SECOND, and 1 unit = 1 km in Sol.** A 600 m/s cap is `0.6`, not `600.0`. Getting this wrong yields 600 km/s and voids the anti-tunnelling guarantee while every test still passes. Convert once, at the boundary, and name the variable so the unit is visible.
- Positions in Sol are physical: 1 unit = 1 km. Earth radius 6371.0, Moon 1737.4.
- `PlanetGenerator` and `TerrainSampler` must hold NO autoload reference (no `Ephemeris`, no `PlanetData`), so their tests run under plain `--script`. Autoload-dependent values arrive as arguments. `surface_patch.gd` already follows this rule — keep it.
- Verification is headless on llvmpipe software Vulkan. Geometry, agreement and bounds are provable here; appearance is not. Never claim a visual outcome.
- Every new assertion must be mutation-tested: break the thing it describes, show the assertion fails, restore.
- Run tests with `timeout 240 godot --headless --path . --script res://tools/<name>.gd`.
- Commit after each task. End commit messages with:
  `Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>`
  `Claude-Session: https://claude.ai/code/session_01XSor1aVH7G1V3YpERuAG16`

## File Structure

| File | Responsibility |
|---|---|
| `tools/probe_earth_dem.gd` | **new.** One-shot measurement of `earth_height.jpg`'s encoding. Produces the constants Task 2 hardcodes. Not a test. |
| `scripts/world/terrain_sampler.gd` | **new.** `TerrainSampler`. The only height, water and surface-colour authority. No autoloads. |
| `scripts/world/planet_generator.gd` | Adds `terrain_sampler()`; band ceiling from terrain max height; retires the plate-derived ceiling constants. |
| `scripts/world/surface_patch.gd` | Single plate → four nested rings with skirts. Vertices and colour come from the sampler. |
| `scripts/world/planet_system.gd` | Owns the sampler for the nearest body, exposes it, folds the band cap into `speed_limit`. |
| `scripts/flight/flight_mode.gd` | Adds `band_speed_cap()`. Pure, already autoload-free. |
| `scripts/core/main.gd` | `_update_skin_kill` → swept contact test against the sampler. |
| `scripts/autoload/ephemeris.gd` | Retires `EARTH_MIN_R_KM`; `surface_kill_km` becomes a contact margin; `sweet_spot` reworked. |
| `tools/test_earth_terrain.gd` | **new.** This slice's contract: sampler, rings, cap, kill, colour. |
| `tools/test_surface_band.gd` | Nine plate assertions restated against rings or deleted. |
| `tools/test_skin_kill.gd` | Four bubble assertions rewritten for contact. |

---

### Task 1: Measure the DEM's encoding

Nothing downstream means anything until we know what `r = 0.0` and `r = 1.0` are in this file. This task produces numbers, not features.

**Files:**
- Create: `tools/probe_earth_dem.gd`

**Interfaces:**
- Consumes: nothing.
- Produces: four measured constants that Task 2 hardcodes into `TerrainSampler` — `DEM_SEA_LEVEL` (the 0..1 sample value at sea level), `DEM_PEAK_VALUE` (the sample value at Everest), `DEM_PEAK_M` (8848.0), and a boolean `DEM_HAS_BATHYMETRY`.

- [ ] **Step 1: Write the probe**

Create `tools/probe_earth_dem.gd`:

```gdscript
extends SceneTree
# One-shot measurement of assets/planets/earth_height.jpg's encoding. NOT a test —
# it prints facts that tools/test_earth_terrain.gd then pins as constants.
#
# Run: godot --headless --path . --script res://tools/probe_earth_dem.gd
#
# We do not know what r=0.0 and r=1.0 mean in this file, where sea level sits, or
# whether ocean depth is encoded below it. Every height in the game depends on
# that mapping, so it gets measured before a single vertex is written.

const PATH := "res://assets/planets/earth_height.jpg"

# Known points, degrees. lat +N, lon +E.
const PLACES := [
	{"name": "Everest",        "lat":  27.9881, "lon":  86.9250, "m":  8848.0},
	{"name": "Aconcagua",      "lat": -32.6532, "lon": -70.0109, "m":  6961.0},
	{"name": "Denali",         "lat":  63.0695, "lon": -151.0074, "m": 6190.0},
	{"name": "Kilimanjaro",    "lat":  -3.0674, "lon":  37.3556, "m":  5895.0},
	{"name": "Dead Sea",       "lat":  31.5590, "lon":  35.4732, "m":  -430.0},
	{"name": "Sahara (flat)",  "lat":  23.4162, "lon":  25.6628, "m":   400.0},
	{"name": "Amazon (low)",   "lat":  -3.4653, "lon": -62.2159, "m":    50.0},
	{"name": "mid-Pacific",    "lat":   0.0000, "lon": -150.0000, "m":    0.0},
	{"name": "mid-Atlantic",   "lat":   0.0000, "lon": -25.0000, "m":     0.0},
	{"name": "Mariana Trench", "lat":  11.3493, "lon": 142.1996, "m": -10994.0},
]


func _initialize() -> void:
	var tex := load(PATH) as Texture2D
	if tex == null:
		print("probe_earth_dem: FAIL cannot load %s" % PATH)
		quit(1)
		return
	var img := tex.get_image()
	if img == null:
		print("probe_earth_dem: FAIL no image")
		quit(1)
		return
	if img.is_compressed():
		img.decompress()

	var w := img.get_width()
	var h := img.get_height()
	print("probe_earth_dem: %d x %d, %.2f km per texel at the equator"
		% [w, h, 40075.0 / float(w)])

	# Global range and distribution. A DEM that encodes bathymetry has a big mass
	# of texels BELOW sea level; one that clamps the ocean has a spike AT the floor.
	var lo := 1.0
	var hi := 0.0
	var buckets := PackedInt32Array()
	buckets.resize(20)
	var total := 0
	# Stride so this stays quick: ~200k samples is plenty for a distribution.
	var step := maxi(1, int(sqrt(float(w * h) / 200000.0)))
	for y in range(0, h, step):
		for x in range(0, w, step):
			var v := img.get_pixel(x, y).r
			lo = minf(lo, v)
			hi = maxf(hi, v)
			buckets[clampi(int(v * 20.0), 0, 19)] += 1
			total += 1
	print("probe_earth_dem: range %.4f .. %.4f over %d samples" % [lo, hi, total])
	print("probe_earth_dem: distribution (each bucket = 0.05 of range)")
	for i in 20:
		var frac := float(buckets[i]) / float(total)
		print("   %.2f-%.2f  %6.2f%%  %s"
			% [float(i) * 0.05, float(i + 1) * 0.05, frac * 100.0,
			"#".repeat(int(frac * 200.0))])

	# Named points. The pairing of (known metres) with (sampled 0..1) is what gives
	# us the scale, and mid-ocean tells us where zero is.
	print("probe_earth_dem: named points")
	for p in PLACES:
		var uv := _uv_of(float(p.lat), float(p.lon))
		var v := _bilinear(img, uv)
		print("   %-16s %8.1f m   uv (%.4f, %.4f)   sample %.4f"
			% [str(p.name), float(p.m), uv.x, uv.y, v])

	# Sanity: the highest sample anywhere near the Himalaya should be at/above the
	# Everest sample. If it is not, our UV mapping is wrong (flipped V or a 180
	# longitude offset), and every height in the game would be from the wrong place.
	var everest_uv := _uv_of(27.9881, 86.9250)
	var everest_v := _bilinear(img, everest_uv)
	var region_max := 0.0
	var region_at := Vector2.ZERO
	for dy in range(-40, 41):
		for dx in range(-40, 41):
			var uv := everest_uv + Vector2(float(dx) / float(w), float(dy) / float(h))
			var v := _bilinear(img, uv)
			if v > region_max:
				region_max = v
				region_at = uv
	print("probe_earth_dem: Everest sample %.4f; regional max %.4f at uv (%.4f, %.4f)"
		% [everest_v, region_max, region_at.x, region_at.y])
	print("probe_earth_dem: global max %.4f -> if Everest is the world high point," % hi)
	print("                 sea-level value and this pair give the metres-per-unit scale")
	print("probe_earth_dem: done — copy these into TerrainSampler (Task 2)")
	quit(0)


# Same mapping surface_patch._dir_uv() uses, stated in lat/lon so the named points
# above are readable. u wraps at the antimeridian, v = 0 is the north pole.
func _uv_of(lat_deg: float, lon_deg: float) -> Vector2:
	return Vector2(lon_deg / 360.0 + 0.5, 0.5 - lat_deg / 180.0)


func _bilinear(img: Image, uv: Vector2) -> float:
	var w := img.get_width()
	var h := img.get_height()
	var fx := fposmod(uv.x, 1.0) * float(w) - 0.5
	var fy := clampf(uv.y, 0.0, 1.0) * float(h) - 0.5
	var x0 := int(floor(fx))
	var y0 := int(floor(fy))
	var tx := fx - float(x0)
	var ty := fy - float(y0)
	var s00 := _texel(img, x0, y0)
	var s10 := _texel(img, x0 + 1, y0)
	var s01 := _texel(img, x0, y0 + 1)
	var s11 := _texel(img, x0 + 1, y0 + 1)
	return lerpf(lerpf(s00, s10, tx), lerpf(s01, s11, tx), ty)


func _texel(img: Image, x: int, y: int) -> float:
	var w := img.get_width()
	var h := img.get_height()
	return img.get_pixel(posmod(x, w), clampi(y, 0, h - 1)).r
```

- [ ] **Step 2: Run it**

Run: `timeout 240 godot --headless --path . --script res://tools/probe_earth_dem.gd`

Expected: dimensions `5400 x 2700`, a `7.42 km per texel` line, a distribution histogram, and a table of ten named points with their samples.

- [ ] **Step 3: Read the output and decide the encoding**

Answer these three questions from the printed numbers, and write the answers into the commit message:

1. **Where is sea level?** Look at `mid-Pacific` and `mid-Atlantic`. If both sit at ~0.0, the ocean is clamped to the floor and `DEM_SEA_LEVEL = 0.0`. If they sit at some common midpoint (~0.3-0.5), bathymetry is encoded and `DEM_SEA_LEVEL` is that value.
2. **Is bathymetry real?** Compare `Mariana Trench` to `mid-Pacific`. Clearly lower means depth is encoded; identical means the ocean is flat-floored. Set `DEM_HAS_BATHYMETRY` accordingly.
3. **What is the vertical scale?** `DEM_PEAK_VALUE` is the Everest sample; with `DEM_SEA_LEVEL` and `DEM_PEAK_M = 8848.0` that gives metres per unit. Sanity-check it against Aconcagua, Denali and Kilimanjaro — their computed metres should land within roughly 30% of their real values. A 7.42 km texel smooths peaks down, so expect the probe to *understate* every summit; that is the expected direction of error, and it is why slice B injects peaks.

If the regional max is NOT at or above the Everest sample, **stop**: the UV mapping is wrong and must be fixed before anything else. A flipped `v` puts the Himalaya in the southern ocean and nothing downstream would be recoverable.

- [ ] **Step 4: Commit**

```bash
git add tools/probe_earth_dem.gd
git commit -m "$(cat <<'EOF'
tools: probe earth_height.jpg's encoding before building on it

Measures the DEM's range, distribution and value at ten known points so
sea level, bathymetry and the vertical scale are established facts rather
than assumptions. Also checks the UV mapping by confirming the regional
maximum near 27.99N 86.93E is at or above the Everest sample - a flipped V
would put the Himalaya in the southern ocean.

Measured: <fill in from the run: dimensions, sea-level value, bathymetry
yes/no, metres per unit, and the cross-check summits>

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01XSor1aVH7G1V3YpERuAG16
EOF
)"
```

---

### Task 2: TerrainSampler — the only height function

**Files:**
- Create: `scripts/world/terrain_sampler.gd`
- Create: `tools/test_earth_terrain.gd`
- Modify: `scripts/world/planet_generator.gd` (add `terrain_sampler()`)

**Interfaces:**
- Consumes: the four constants measured in Task 1.
- Produces:
  ```gdscript
  PlanetGenerator.terrain_sampler(recipe: Dictionary) -> TerrainSampler
  TerrainSampler.height_m(dir: Vector3) -> float
  TerrainSampler.ground_radius_km(dir: Vector3, body_radius_km: float) -> float
  TerrainSampler.alt_above_ground_km(pos: Vector3, body_radius_km: float) -> float
  TerrainSampler.is_water(dir: Vector3) -> bool
  TerrainSampler.max_height_km() -> float
  TerrainSampler.report() -> Dictionary
  ```

- [ ] **Step 1: Write the failing test**

Create `tools/test_earth_terrain.gd`:

```gdscript
extends SceneTree
# Contract for the Earth flyover slice: one height function, nested rings, the
# band ceiling, the speed cap and the contact kill.
# Run: godot --headless --path . --script res://tools/test_earth_terrain.gd
#
# The load-bearing assertion in this file is mesh_matches_the_height_function.
# Mesh geometry and the kill test are two consumers of one function; if they ever
# disagree you die in clear air or fly through rock, and no amount of visual
# inspection would tell you which one was wrong.

const G := preload("res://scripts/world/planet_generator.gd")

const EARTH_R := 6371.0
const MOON_R := 1737.4


func _initialize() -> void:
	var failed := 0
	failed += _sampler()
	if failed == 0:
		print("earth_terrain: OK")
		quit(0)
	else:
		print("earth_terrain: FAIL %d" % failed)
		quit(1)


func _sampler() -> int:
	var failed := 0
	var earth := G.recipe_for({"name": "Earth"})
	var s = G.terrain_sampler(earth)
	failed += _check("earth_sampler_exists", s != null)
	if s == null:
		return failed

	# Everest is the world's high point. The 7.42 km texel smooths it, so we assert
	# it is the regional maximum and in the right ballpark, not exact.
	var everest := _dir_of(27.9881, 86.9250)
	var pacific := _dir_of(0.0, -150.0)
	var e_m: float = s.height_m(everest)
	var p_m: float = s.height_m(pacific)

	failed += _check("everest_is_high_ground", e_m > 4000.0)
	failed += _check("everest_is_not_absurd", e_m < 12000.0)
	failed += _check("open_ocean_is_at_sea_level", absf(p_m) < 60.0)
	failed += _check("mountains_are_above_the_ocean", e_m > p_m + 4000.0)
	failed += _check("open_ocean_is_water", s.is_water(pacific))
	failed += _check("everest_is_not_water", not s.is_water(everest))

	# ground_radius_km and alt_above_ground_km must agree with height_m, since the
	# kill test uses them and the mesh uses height_m.
	var gr: float = s.ground_radius_km(everest, EARTH_R)
	failed += _check("ground_radius_tracks_height",
		is_equal_approx(gr, EARTH_R + e_m / 1000.0))
	var above: float = s.alt_above_ground_km(everest * (gr + 2.0), EARTH_R)
	failed += _check("altitude_is_measured_from_local_ground",
		is_equal_approx(above, 2.0))
	# The bug this catches: measuring from the sphere instead of the ground would
	# report ~10.8 km here instead of 2.0.
	failed += _check("altitude_is_not_measured_from_the_sphere", above < 5.0)

	# Determinism. The mesh builder and the kill test call this at different times
	# in the same frame; any statefulness would desync them.
	failed += _check("height_is_deterministic",
		is_equal_approx(e_m, s.height_m(everest)))

	# A world with no DEM still answers, from the shader's own crust noise.
	var moon := G.recipe_for({"name": "Moon"})
	var ms = G.terrain_sampler(moon)
	var md := _dir_of(12.0, 34.0)
	var mh: float = ms.height_m(md)
	failed += _check("airless_world_has_height", mh > 0.0)
	failed += _check("airless_world_height_is_bounded", mh < 4000.0)
	failed += _check("airless_world_is_never_water", not ms.is_water(md))
	failed += _check("airless_max_height_is_bounded",
		ms.max_height_km() > 0.5 and ms.max_height_km() < 4.0)
	failed += _check("earth_max_height_covers_everest", s.max_height_km() >= 8.0)

	print("earth_terrain: sampler  Everest %.0f m, Pacific %.0f m, Earth max %.2f km, Moon max %.2f km"
		% [e_m, p_m, s.max_height_km(), ms.max_height_km()])
	return failed


# Unit direction for a lat/lon, matching surface_patch._dir_uv()'s convention.
func _dir_of(lat_deg: float, lon_deg: float) -> Vector3:
	var lat := deg_to_rad(lat_deg)
	var lon := deg_to_rad(lon_deg)
	return Vector3(cos(lat) * cos(lon), sin(lat), cos(lat) * sin(lon)).normalized()


func _check(name: String, ok: bool) -> int:
	if not ok:
		print("earth_terrain: FAIL %s" % name)
		return 1
	return 0
```

- [ ] **Step 2: Run it to verify it fails**

Run: `timeout 240 godot --headless --path . --script res://tools/test_earth_terrain.gd`
Expected: a parse/compile error naming `terrain_sampler` as an unknown function on `PlanetGenerator`.

- [ ] **Step 3: Write TerrainSampler**

Create `scripts/world/terrain_sampler.gd`. Replace the four `DEM_*` constants with Task 1's measured values:

```gdscript
class_name TerrainSampler
extends RefCounted
# THE height function. One instance per body, and every consumer holds the same
# instance: the ring mesh builder displaces vertices with it, and main's contact
# kill measures altitude with it. If those two ever computed height differently
# you would die in clear air or fly through rock, so there is deliberately no
# second implementation anywhere.
#
# Holds no autoload reference (body radius arrives as an argument), so this and
# its tests run under plain `--script`.

# --- DEM encoding, measured by tools/probe_earth_dem.gd ---
# These are FACTS ABOUT THE FILE, not tuning. If earth_height.jpg is ever
# re-fetched, re-run the probe: a pack with different encoding would silently
# flatten or invert the planet. tools/test_earth_terrain.gd pins them.
const DEM_SEA_LEVEL := 0.0        # <- Task 1: sample value at mid-ocean
const DEM_PEAK_VALUE := 1.0       # <- Task 1: sample value at Everest
const DEM_PEAK_M := 8848.0        # Everest, metres
const DEM_HAS_BATHYMETRY := false # <- Task 1: is ocean depth encoded?

# Metres per unit of DEM sample above sea level.
const DEM_SCALE_M := DEM_PEAK_M / maxf(DEM_PEAK_VALUE - DEM_SEA_LEVEL, 0.0001)

# Elevation scale for a world with NO height map. Keeps the 3.2 lift constant
# surface_patch._vert already used, so airless relief does not change character.
# fbm3 is bounded at 0.96875, so a noise world's ceiling is ~3.1 km.
const NOISE_RELIEF_KM := 3.2

# Procedural detail added on top of the DEM. Amplitude scales with the DEM's
# local slope: 7.42 km texels cannot express a ridge, so flat sea floor stays
# flat while mountains get rugged. This is what makes 50 m triangles worth
# building instead of just interpolating between texels.
const DETAIL_FREQ := 900.0        # cycles across the body; ~44 km wavelength on Earth
const DETAIL_MAX_M := 420.0       # amplitude at full slope

var _himg: Image                  # height map, or null -> noise
var _simg: Image                  # water mask, or null
var _seed := 0.0                  # the SAME seed the cook material got
var _land := 1.0                  # recipe land_amount, the water cut with no mask
var _has_map := false


func _init(recipe: Dictionary) -> void:
	_himg = _img_of(str(recipe.get("height", "")))
	_simg = _img_of(str(recipe.get("specular", "")))
	_seed = float(recipe.get("seed", 0.0))
	_land = float(recipe.get("land_amount", 1.0))
	_has_map = _himg != null


# Metres above sea level at a point on the crust. `dir` is an outward unit vector
# in MODEL space — the same vector the cook shader calls `n`.
func height_m(dir: Vector3) -> float:
	var base: float
	if _has_map:
		base = (_bilinear(_himg, _dir_uv(dir)) - DEM_SEA_LEVEL) * DEM_SCALE_M
	else:
		# No map: the cook shader's own crust fbm, so the tile agrees with the globe.
		base = PlanetGenerator.crust_height(dir, _seed) * NOISE_RELIEF_KM * 1000.0
	if base <= 0.0 and not DEM_HAS_BATHYMETRY:
		return 0.0                # ocean floor is not modelled; sea level is the floor
	return base + _detail_m(dir, base)


# Ruggedness between DEM samples, scaled by how steep the DEM already is here.
func _detail_m(dir: Vector3, base_m: float) -> float:
	if base_m < 1.0:
		return 0.0                # keep water flat
	var slope := _slope01(dir)
	var n: float = PlanetGenerator.fbm3(dir * DETAIL_FREQ + Vector3(_seed, _seed, _seed))
	return (n - 0.5) * 2.0 * DETAIL_MAX_M * slope


# 0..1 steepness from the DEM's own neighbourhood. Zero for a noise world, whose
# fbm is already rugged at every scale.
func _slope01(dir: Vector3) -> float:
	if not _has_map:
		return 0.35
	var uv := _dir_uv(dir)
	var e := 1.0 / float(_himg.get_width())
	var dx := _bilinear(_himg, uv + Vector2(e, 0.0)) - _bilinear(_himg, uv - Vector2(e, 0.0))
	var dy := _bilinear(_himg, uv + Vector2(0.0, e)) - _bilinear(_himg, uv - Vector2(0.0, e))
	return clampf(sqrt(dx * dx + dy * dy) * 22.0, 0.0, 1.0)


# Distance from the body's centre to the ground at `dir`, in km.
func ground_radius_km(dir: Vector3, body_radius_km: float) -> float:
	return body_radius_km + height_m(dir) / 1000.0


# Height of `pos` above the ground DIRECTLY BELOW IT, in km. Measuring from the
# sphere instead would report ~10.8 km while you sit 2 km over Everest's summit.
func alt_above_ground_km(pos: Vector3, body_radius_km: float) -> float:
	var d := pos.length()
	if d < 0.0001:
		return -body_radius_km
	return d - ground_radius_km(pos / d, body_radius_km)


func is_water(dir: Vector3) -> bool:
	if _simg != null:
		return _bilinear(_simg, _dir_uv(dir)) > 0.5
	if _has_map:
		return height_m(dir) <= 0.5
	# No mask and no map: the cook shader's land_amount cut on fbm.
	var edge := 1.0 - _land
	var h: float = PlanetGenerator.fbm3(dir * 2.1 + Vector3(_seed, _seed, _seed))
	return (1.0 - smoothstep(edge - 0.05, edge + 0.05, h)) > 0.5


# Tallest terrain this world can produce, km. Drives the band ceiling, so it must
# be an upper bound and not an average.
func max_height_km() -> float:
	if _has_map:
		return (DEM_PEAK_M + DETAIL_MAX_M) / 1000.0
	# fbm3 sums 5 octaves of 0.5-halving amplitude: 0.96875 is its hard ceiling.
	return NOISE_RELIEF_KM * 0.96875


func report() -> Dictionary:
	return {
		"height_source": "map" if _has_map else "noise",
		"water_source": "mask" if _simg != null else ("height" if _has_map else "noise"),
		"max_height_km": max_height_km(),
		"seed": _seed,
	}


func _img_of(path: String) -> Image:
	if path.is_empty() or not ResourceLoader.exists(path):
		return null
	var tex := load(path) as Texture2D
	if tex == null:
		return null
	var img := tex.get_image()
	if img != null and img.is_compressed():
		img.decompress()
	return img


# Equirectangular, matching surface_patch._dir_uv(). v = 0 is the north pole.
func _dir_uv(dir: Vector3) -> Vector2:
	var lon := atan2(dir.z, dir.x)
	var lat := asin(clampf(dir.y, -1.0, 1.0))
	return Vector2(lon / TAU + 0.5, 0.5 - lat / PI)


# BILINEAR, not nearest. Nearest is what makes 7.42 km texels read as blocks, and
# it also keeps every 8-bit step (~35 m at Everest scale) as a visible terrace.
func _bilinear(img: Image, uv: Vector2) -> float:
	var w := img.get_width()
	var h := img.get_height()
	var fx := fposmod(uv.x, 1.0) * float(w) - 0.5
	var fy := clampf(uv.y, 0.0, 1.0) * float(h) - 0.5
	var x0 := int(floor(fx))
	var y0 := int(floor(fy))
	var tx := fx - float(x0)
	var ty := fy - float(y0)
	var s00 := _texel(img, x0, y0)
	var s10 := _texel(img, x0 + 1, y0)
	var s01 := _texel(img, x0, y0 + 1)
	var s11 := _texel(img, x0 + 1, y0 + 1)
	return lerpf(lerpf(s00, s10, tx), lerpf(s01, s11, tx), ty)


func _texel(img: Image, x: int, y: int) -> float:
	return img.get_pixel(posmod(x, img.get_width()),
		clampi(y, 0, img.get_height() - 1)).r
```

- [ ] **Step 4: Add the factory to PlanetGenerator**

In `scripts/world/planet_generator.gd`, immediately after the `crust_height` function, add:

```gdscript
# One sampler per body, built from its recipe. Callers must SHARE the instance —
# the mesh builder and the contact kill have to be looking at the same terrain.
static func terrain_sampler(recipe: Dictionary) -> TerrainSampler:
	return TerrainSampler.new(recipe)
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `timeout 240 godot --headless --path . --script res://tools/test_earth_terrain.gd`
Expected: `earth_terrain: OK` plus the sampler line. If `everest_is_high_ground` fails, the Task 1 constants are wrong — go back and re-read the probe output rather than adjusting the assertion.

- [ ] **Step 6: Mutation-test the assertions**

For each mutation: apply, run, confirm the named assertion fails, restore.

| Mutation | Must fail |
|---|---|
| `_bilinear` → return `_texel(img, int(uv.x*w), int(uv.y*h))` | nothing new, but note the Everest value shifts — proves bilinear is live |
| `_dir_uv` → `0.5 + lat / PI` (flipped v) | `everest_is_high_ground`, `mountains_are_above_the_ocean` |
| `alt_above_ground_km` → `d - body_radius_km` | `altitude_is_measured_from_local_ground`, `altitude_is_not_measured_from_the_sphere` |
| `max_height_km` → `return 1.0` | `earth_max_height_covers_everest` |
| `is_water` → `return false` | `open_ocean_is_water` |

- [ ] **Step 7: Commit**

```bash
git add scripts/world/terrain_sampler.gd scripts/world/planet_generator.gd tools/test_earth_terrain.gd
git commit -m "$(cat <<'EOF'
feat: TerrainSampler, the only height function in the system

Mesh geometry and the contact kill must never disagree about where the
ground is, so there is one implementation and every consumer shares the
instance. Bilinear DEM sampling (nearest is what makes 7.42 km texels read
as blocks and keeps every 8-bit step as a terrace), plus procedural detail
whose amplitude follows the DEM's local slope so flat sea floor stays flat
and mountains get rugged. Worlds with no map fall through to the cook
shader's own crust fbm at the same seed.

alt_above_ground_km measures from the ground below you, not from the
sphere - the difference is 10.8 km versus 2.0 km when you are over
Everest, and the test pins it.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01XSor1aVH7G1V3YpERuAG16
EOF
)"
```

---

### Task 3: Four nested rings replace the single plate

Rings land BEFORE Earth's band opens. Reversing this order creates an intermediate state where a 36 km plate hangs at 15 km altitude — the sticker-on-a-globe bug, reintroduced.

**Files:**
- Modify: `scripts/world/surface_patch.gd`
- Modify: `tools/test_earth_terrain.gd` (add `_rings()`)
- Modify: `tools/test_surface_band.gd` (restate plate assertions)

**Interfaces:**
- Consumes: `TerrainSampler.ground_radius_km`, `.is_water`, `.height_m` from Task 2.
- Produces:
  ```gdscript
  SurfacePatch.RING_COUNT -> int (4)
  SurfacePatch.RING_SEGS -> int (64)
  SurfacePatch.ring_quad_km(ring: int) -> float
  SurfacePatch.ring_reach_km(ring: int) -> float
  SurfacePatch.bind_body(recipe: Dictionary, sampler: TerrainSampler) -> void
  SurfacePatch.report() -> Dictionary   # gains "rings", "tris", "ring_verts"
  ```

- [ ] **Step 1: Write the failing test**

Append to `tools/test_earth_terrain.gd` — add `failed += _rings()` to `_initialize()`, and:

```gdscript
const SP := preload("res://scripts/world/surface_patch.gd")


func _rings() -> int:
	var failed := 0
	var moon := G.recipe_for({"name": "Moon"})
	var s = G.terrain_sampler(moon)
	var patch = SP.new()
	patch._ready()
	patch.bind_body(moon, s)

	# Ring geometry: 4 rings, each quad 4x the one inside it, reaching past 200 km.
	failed += _check("four_rings", SP.RING_COUNT == 4)
	failed += _check("ring_0_is_fine", SP.ring_quad_km(0) <= 0.05)
	failed += _check("each_ring_is_coarser",
		SP.ring_quad_km(1) > SP.ring_quad_km(0)
		and SP.ring_quad_km(2) > SP.ring_quad_km(1)
		and SP.ring_quad_km(3) > SP.ring_quad_km(2))
	failed += _check("outer_ring_reaches_the_horizon", SP.ring_reach_km(3) > 200.0)

	# Build at 1 km over the Moon.
	var dir := Vector3(0.42, 0.31, 0.85).normalized()
	var pos: Vector3 = dir * (MOON_R + 1.0)
	patch.update_for(pos, "Moon", true, MOON_R, 1.0, 0.1, moon)
	var r: Dictionary = patch.report()

	failed += _check("all_rings_built", int(r.rings) == SP.RING_COUNT)
	# Constant budget is the whole point of rings: detail and reach stop competing.
	var tris_low := int(r.tris)
	patch.update_for(dir * (MOON_R + 4.0), "Moon", true, MOON_R, 4.0, 0.1, moon)
	var tris_high := int(patch.report().tris)
	failed += _check("triangle_budget_is_constant_with_altitude", tris_low == tris_high)
	failed += _check("triangle_budget_is_within_range",
		tris_low > 20000 and tris_low < 45000)

	# THE assertion. Every committed vertex must sit exactly where the height
	# function says the ground is. Divergence here means dying in clear air.
	var worst: float = patch.worst_vertex_error_km(MOON_R)
	failed += _check("mesh_matches_the_height_function", worst < 0.001)

	# Seams: each ring's skirt must cover the gap to the next ring out.
	failed += _check("rings_have_no_gaps", bool(patch.rings_seal()))

	print("earth_terrain: rings  %d rings, %d tris, quads %.3f/%.3f/%.3f/%.3f km, reach %.1f km, worst vertex err %.6f km"
		% [int(r.rings), tris_low, SP.ring_quad_km(0), SP.ring_quad_km(1),
		SP.ring_quad_km(2), SP.ring_quad_km(3), SP.ring_reach_km(3), worst])
	patch.free()
	return failed
```

- [ ] **Step 2: Run it to verify it fails**

Run: `timeout 240 godot --headless --path . --script res://tools/test_earth_terrain.gd`
Expected: FAIL on `RING_COUNT` being an unknown constant.

- [ ] **Step 3: Rewrite surface_patch.gd's geometry as rings**

Replace the `SEGS`/plate constants and `_rebuild` with the ring builder. Keep `bind_recipe`'s image/kit logic, `_prop_here`, `_prop_aspect`, `_place_props`, the kit meshes, `_mat`, `_hash` and `_dir_uv` exactly as they are.

Constants block — replace `const SEGS := 48` and the `MOVE_REBUILD_FRAC`/`TILE_DRIFT_FRAC` pair with:

```gdscript
# --- Nested rings ---
# One plate cannot be both fine and far: 50 m triangles out to a 10 km-altitude
# horizon (~350 km) is 49 million quads. Concentric rings, each quad 4x the one
# inside it, give 50 m underfoot AND 205 km of reach for a constant 32k triangles.
const RING_COUNT := 4
const RING_SEGS := 64
const RING_0_QUAD_KM := 0.05        # 50 m
const RING_STEP := 4.0              # each ring out is this much coarser
# Rings 1..3 are DONUTS: the inner ring's footprint is skipped, so nothing
# overdraws and the budget stays flat.
# Each ring's outer edge drops straight down by one of its own quads. Adjacent
# rings sample the same height function at different rates, so their edges do not
# meet exactly; the skirt hides that gap and is invisible from above.
const SKIRT_QUADS := 1.0
```

Ring geometry helpers:

```gdscript
static func ring_quad_km(ring: int) -> float:
	return RING_0_QUAD_KM * pow(RING_STEP, float(ring))


static func ring_reach_km(ring: int) -> float:
	return ring_quad_km(ring) * float(RING_SEGS)
```

Replace the `_ground`/`_water` single-mesh pair with per-ring arrays, and add the sampler:

```gdscript
var _ring_land: Array[MeshInstance3D] = []
var _ring_water: Array[MeshInstance3D] = []
var _ring_anchor: Array[Vector3] = []     # ZERO = that ring never built
var _sampler: TerrainSampler
var _tris := 0
```

In `_ready()`, replace the two `MeshInstance3D` creations with:

```gdscript
	for i in RING_COUNT:
		var land := MeshInstance3D.new()
		land.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(land)
		_ring_land.append(land)
		var water := MeshInstance3D.new()
		water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(water)
		_ring_water.append(water)
		_ring_anchor.append(Vector3.ZERO)
```

Add the binder that takes the shared sampler:

```gdscript
# Point the tile at a world, with the SHARED sampler the kill test also holds.
func bind_body(recipe: Dictionary, sampler: TerrainSampler) -> void:
	_sampler = sampler
	bind_recipe(recipe)
	for i in RING_COUNT:
		_ring_anchor[i] = Vector3.ZERO
```

Replace `update_for`'s plate logic:

```gdscript
func update_for(ship_pos: Vector3, body: String, physical: bool, radius: float,
		alt: float, kill: float, recipe: Dictionary) -> void:
	if not should_show(body, physical, alt, kill, recipe):
		visible = false
		return
	if _body != body or _sampler == null:
		bind_body(recipe, PlanetGenerator.terrain_sampler(recipe))
		_body = body
	visible = true
	var hit: Vector3 = ship_pos.normalized() * radius
	# Each ring rebuilds only when the hull has crossed one of ITS OWN quads, so
	# ring 0 follows you closely and cheaply while ring 3 almost never moves.
	for i in RING_COUNT:
		var quad := ring_quad_km(i)
		if _ring_anchor[i] == Vector3.ZERO or hit.distance_to(_ring_anchor[i]) > quad:
			_build_ring(i, hit, radius)
			_ring_anchor[i] = hit
	_tris = 0
	for m in _ring_land:
		_tris += _tri_count(m)
	for m in _ring_water:
		_tris += _tri_count(m)


func _tri_count(mi: MeshInstance3D) -> int:
	if mi == null or mi.mesh == null or mi.mesh.get_surface_count() == 0:
		return 0
	return mi.mesh.surface_get_array_len(0) / 3
```

The ring builder, replacing `_rebuild`:

```gdscript
func _build_ring(ring: int, hit: Vector3, radius: float) -> void:
	var up := hit.normalized()
	var east := up.cross(Vector3.UP)
	if east.length_squared() < 0.0001:
		east = up.cross(Vector3.RIGHT)
	east = east.normalized()
	var north := east.cross(up).normalized()
	var quad := ring_quad_km(ring)
	var half := ring_reach_km(ring) * 0.5
	# A donut: skip the quads the finer ring inside already covers.
	var hole := 0.0 if ring == 0 else ring_reach_km(ring - 1) * 0.5
	var land_st := SurfaceTool.new()
	var wat_st := SurfaceTool.new()
	land_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	wat_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var prop_xforms: Array[Transform3D] = []
	for j in RING_SEGS:
		for i in RING_SEGS:
			var e0 := (float(i) / float(RING_SEGS) - 0.5) * 2.0 * half
			var n0 := (float(j) / float(RING_SEGS) - 0.5) * 2.0 * half
			var e1 := e0 + quad
			var n1 := n0 + quad
			# Inside the hole means the finer ring owns this ground.
			if hole > 0.0 and absf(e0) < hole and absf(n0) < hole \
					and absf(e1) <= hole and absf(n1) <= hole:
				continue
			var p00 := _vert(hit, up, east, north, radius, e0, n0)
			var p10 := _vert(hit, up, east, north, radius, e1, n0)
			var p01 := _vert(hit, up, east, north, radius, e0, n1)
			var p11 := _vert(hit, up, east, north, radius, e1, n1)
			var wet: float = (float(p00.w) + float(p10.w) + float(p01.w) + float(p11.w)) * 0.25
			var st: SurfaceTool = wat_st if wet > 0.55 else land_st
			var nrm: Vector3 = (p10.p - p00.p).cross(p01.p - p00.p)
			if nrm.length_squared() < 1e-10:
				nrm = up
			else:
				nrm = nrm.normalized()
			_tri(st, p00, p10, p11, nrm)
			_tri(st, p00, p11, p01, nrm)
			# Skirt the outer edge so the seam to the next ring out cannot show.
			var edge_e: bool = i == 0 or i == RING_SEGS - 1
			var edge_n: bool = j == 0 or j == RING_SEGS - 1
			if edge_e or edge_n:
				_skirt(st, p00, p10 if edge_n else p01, up, quad * SKIRT_QUADS)
			# Props ride ring 0 only this slice; slice D revisits density.
			if ring == 0:
				var seedn := _hash(Vector2(float(i), float(j)))
				if _prop_here(wet, float(p00.h), seedn):
					var t := Transform3D()
					var sc: float = 0.012 + seedn * 0.028
					t.basis = Basis(east, nrm, north).orthonormalized().scaled(
						Vector3(sc, sc * _prop_aspect(seedn), sc))
					t.origin = p00.p + nrm * sc * 0.9
					prop_xforms.append(t)
	_ring_land[ring].mesh = land_st.commit()
	_ring_land[ring].material_override = _mat(false)
	_ring_water[ring].mesh = wat_st.commit()
	_ring_water[ring].material_override = _mat(true)
	if ring == 0:
		_place_props(prop_xforms, hit, east, north)


# Two triangles hanging straight down from an edge, hiding the gap where this
# ring's edge and the next ring's edge sampled the same ground at different rates.
func _skirt(st: SurfaceTool, a: Dictionary, b: Dictionary, up: Vector3, drop: float) -> void:
	var a_lo: Dictionary = a.duplicate()
	var b_lo: Dictionary = b.duplicate()
	a_lo["p"] = a.p - up * drop
	b_lo["p"] = b.p - up * drop
	var nrm: Vector3 = (b.p - a.p).cross(a_lo.p - a.p)
	if nrm.length_squared() < 1e-10:
		nrm = up
	else:
		nrm = nrm.normalized()
	_tri(st, a, b, b_lo, nrm)
	_tri(st, a, b_lo, a_lo, nrm)
```

`_vert` now takes metric offsets and asks the sampler:

```gdscript
# Vertex at a metric offset from the ring's centre. Height comes from the SHARED
# sampler — the same call main's contact kill makes — so mesh and lethality agree.
func _vert(hit: Vector3, up: Vector3, east: Vector3, north: Vector3,
		radius: float, off_e: float, off_n: float) -> Dictionary:
	var dir: Vector3 = (hit + east * off_e + north * off_n).normalized()
	var uv := _dir_uv(dir)
	var gr: float = _sampler.ground_radius_km(dir, radius)
	var wet: float = 1.0 if _sampler.is_water(dir) else 0.0
	var h: float = (gr - radius) / _sampler.max_height_km()   # 0..1, for props/colour
	return { "p": dir * gr, "h": clampf(h, 0.0, 1.0), "w": wet,
		"c": _color_at(dir, uv, h), "uv": uv }
```

Delete `_height_at` and `_water_at` — the sampler owns both now. Keep `_color_at` until Task 7.

Add the two test hooks and extend `report()`:

```gdscript
# Largest disagreement between a committed vertex and the height function, in km.
# Test hook: this is the number that must stay at zero.
func worst_vertex_error_km(radius: float) -> float:
	var worst := 0.0
	for ring in RING_COUNT:
		for mi in [_ring_land[ring], _ring_water[ring]]:
			if mi == null or mi.mesh == null or mi.mesh.get_surface_count() == 0:
				continue
			var verts: PackedVector3Array = mi.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
			for v in verts:
				var d := v.length()
				if d < 0.0001:
					continue
				var want: float = _sampler.ground_radius_km(v / d, radius)
				# Skirt vertices hang BELOW the ground on purpose; only over-height
				# counts as disagreement.
				if d - want > worst:
					worst = d - want
	return worst


# Does every ring's skirt reach at least as deep as the next ring's worst
# possible height disagreement? If not, a seam can open.
func rings_seal() -> bool:
	for ring in range(RING_COUNT - 1):
		var drop := ring_quad_km(ring) * SKIRT_QUADS
		if drop < ring_quad_km(ring + 1) * 0.05:
			return false
	return true
```

In `report()`, replace `"ground_verts"` / `"water_verts"` / `"ground_aabb"` with:

```gdscript
		"rings": RING_COUNT,
		"tris": _tris,
		"ring_verts": _tri_count(_ring_land[0]) * 3,
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `timeout 240 godot --headless --path . --script res://tools/test_earth_terrain.gd`
Expected: `earth_terrain: OK` with a rings line showing 4 rings, ~32k triangles, quads 0.050/0.200/0.800/3.200 km, reach 204.8 km, and worst vertex error 0.000000.

- [ ] **Step 5: Repair test_surface_band.gd**

Nine assertions describe the plate, which no longer exists. Delete these five outright — they name a mechanism rings replace:

`plate_grows_with_altitude`, `plate_never_below_min`, `plate_never_above_max`, `plate_always_dwarfs_the_altitude`, `tile_plate_scales_to_the_altitude`

Restate these four against ring 0, changing only the names and the quantity read:

```gdscript
	failed += _check("ring_0_sits_on_the_moons_shell", near > MOON_R * 0.9 and far > MOON_R)
	failed += _check("ring_0_is_local_not_global",
		box.size.x < MOON_R and box.size.y < MOON_R and box.size.z < MOON_R)
	failed += _check("standing_still_keeps_the_same_rings",
		int(patch.report().tris) == tris_before)
	failed += _check("props_cover_ring_0", spread > SP.ring_reach_km(0) * 0.85)
```

Leave `_kits()`, `_sources()` and `_crust()` untouched — none of them depend on the plate.

- [ ] **Step 6: Run the repaired test**

Run: `timeout 240 godot --headless --path . --script res://tools/test_surface_band.gd`
Expected: `surface_band: OK`.

- [ ] **Step 7: Mutation-test the ring assertions**

| Mutation | Must fail |
|---|---|
| `_vert` → `"p": dir * radius` (ignore height) | `mesh_matches_the_height_function` |
| `_vert` → `"p": dir * (gr + 0.5)` | `mesh_matches_the_height_function` |
| `RING_STEP` → `1.0` | `each_ring_is_coarser`, `outer_ring_reaches_the_horizon` |
| remove the `continue` that skips the hole | `triangle_budget_is_within_range` |
| `SKIRT_QUADS` → `0.0` | `rings_have_no_gaps` |

- [ ] **Step 8: Commit**

```bash
git add scripts/world/surface_patch.gd tools/test_earth_terrain.gd tools/test_surface_band.gd
git commit -m "$(cat <<'EOF'
feat: four nested terrain rings replace the single ground plate

One plate cannot be fine and far at once: 50 m triangles out to a 350 km
horizon is 49 million quads. Four concentric rings, each quad 4x the one
inside it, give 50 m underfoot and 205 km of reach for a constant ~32k
triangles. Rings 1-3 are donuts so nothing overdraws, each rebuilds only
when the hull crosses one of its own quads, and outer edges get skirts
because adjacent rings sample the same height function at different rates
and their edges do not meet exactly.

Vertices now come from the shared TerrainSampler, and
worst_vertex_error_km() pins mesh-versus-function agreement at zero.

Retires tile_km_for() and the plate constants, and with them nine
assertions in test_surface_band.gd - five deleted as describing a
mechanism that no longer exists, four restated against ring 0.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01XSor1aVH7G1V3YpERuAG16
EOF
)"
```

---

### Task 4: Band ceiling from terrain max height

**Files:**
- Modify: `scripts/world/planet_generator.gd`
- Modify: `scripts/world/surface_patch.gd` (`should_show` signature)
- Modify: `scripts/world/planet_system.gd` (own and pass the sampler)
- Modify: `tools/test_earth_terrain.gd` (add `_band()`)
- Modify: `tools/test_surface_band.gd` (Earth's ceiling assertions)

**Interfaces:**
- Consumes: `TerrainSampler.max_height_km()`.
- Produces:
  ```gdscript
  PlanetGenerator.band_ceiling_km(sampler: TerrainSampler) -> float
  PlanetGenerator.ground_stamp_ok(alt_km: float, kill_km: float, ceiling_km: float) -> bool
  SurfacePatch.should_show(body, physical, alt, kill, ceiling, recipe) -> bool
  PlanetSystem.terrain_sampler_for(body: String) -> TerrainSampler
  ```

- [ ] **Step 1: Write the failing test**

Add `failed += _band()` to `_initialize()` in `tools/test_earth_terrain.gd`, and:

```gdscript
func _band() -> int:
	var failed := 0
	var earth := G.recipe_for({"name": "Earth"})
	var moon := G.recipe_for({"name": "Moon"})
	var es = G.terrain_sampler(earth)
	var ms = G.terrain_sampler(moon)

	var e_ceil: float = G.band_ceiling_km(es)
	var m_ceil: float = G.band_ceiling_km(ms)

	# The ceiling's job changed. It used to stop a small plate reading as a
	# sticker; rings reach 205 km, so now it must open the band ABOVE the tallest
	# terrain or you enter already inside a mountain.
	failed += _check("earth_ceiling_clears_everest", e_ceil > 8.848)
	failed += _check("earth_ceiling_is_about_15km", e_ceil > 13.0 and e_ceil < 17.0)
	failed += _check("airless_ceiling_clears_its_own_relief",
		m_ceil > ms.max_height_km())
	failed += _check("ceiling_is_derived_not_authored", not is_equal_approx(e_ceil, m_ceil))

	# Every altitude between contact and the ceiling must be in the band.
	failed += _check("earth_band_opens_just_above_the_ground",
		G.ground_stamp_ok(0.5, 0.02, e_ceil))
	failed += _check("earth_band_covers_everest_height",
		G.ground_stamp_ok(9.0, 0.02, e_ceil))
	failed += _check("earth_band_shuts_above_the_ceiling",
		not G.ground_stamp_ok(e_ceil + 1.0, 0.02, e_ceil))
	# EZ is 100 km (Karman). The band must never reach it - that was commit 8933730.
	failed += _check("no_tile_at_earth_ez", not G.ground_stamp_ok(100.0, 0.02, e_ceil))
	failed += _check("no_tile_in_earth_air", not G.ground_stamp_ok(50.0, 0.02, e_ceil))

	print("earth_terrain: band  Earth ceiling %.2f km (max terrain %.2f), Moon ceiling %.2f km (max %.2f)"
		% [e_ceil, es.max_height_km(), m_ceil, ms.max_height_km()])
	return failed
```

- [ ] **Step 2: Run it to verify it fails**

Expected: FAIL — `band_ceiling_km` is not a function on `PlanetGenerator`.

- [ ] **Step 3: Replace the plate-derived ceiling**

In `scripts/world/planet_generator.gd`, delete `TILE_KM_MAX`, `TILE_KM_MIN`, `BAND_ALT_FRACTION`, `TILE_ALT_MULT`, `STAMP_BELOW_KM`, `band_top_km()` and `tile_km_for()`. Replace with:

```gdscript
# --- Skin band ceiling ---
# This rule REPLACED a plate-width one, and the reason matters. The old ceiling
# (3.24 km) existed because a single local plate only reads as ground while its
# width dwarfs your altitude - a 36 km plate seen from 100 km up is a sticker on
# a globe. Rings reach 205 km, so that constraint is gone.
# The ceiling's job is now the opposite: open the band ABOVE the tallest terrain,
# or you enter the band already inside a mountain. Do not reintroduce a
# plate-ratio rule here; it no longer describes anything.
const BAND_CEILING_MULT := 1.7      # headroom above the highest ground
const BAND_CEILING_MIN_KM := 3.0    # floor for a world flat enough that 1.7x would
                                    # open the band underground


# Ceiling of the band for this world, km above sea level. Earth: 8.85 x 1.7 = 15.0.
static func band_ceiling_km(sampler: TerrainSampler) -> float:
	if sampler == null:
		return BAND_CEILING_MIN_KM
	return maxf(sampler.max_height_km() * BAND_CEILING_MULT, BAND_CEILING_MIN_KM)


# Is the ground tile allowed here? Above the kill line and below this world's
# ceiling. The ceiling is now per-world, so it arrives as an argument rather than
# being read off a global constant.
static func ground_stamp_ok(alt_km: float, kill_km: float, ceiling_km: float) -> bool:
	return alt_km > kill_km and alt_km < ceiling_km
```

In `scripts/world/surface_patch.gd`, thread the ceiling through:

```gdscript
static func should_show(body: String, physical: bool, alt: float, kill: float,
		ceiling: float, recipe: Dictionary) -> bool:
	if body.is_empty() or not physical:
		return false
	if not PlanetGenerator.has_surface(recipe):
		return false
	return PlanetGenerator.ground_stamp_ok(alt, kill, ceiling)
```

and in `update_for`, change the signature to accept `ceiling: float` after `kill` and pass it to `should_show`.

- [ ] **Step 4: Have PlanetSystem own the sampler**

In `scripts/world/planet_system.gd`, add beside `_surface`:

```gdscript
var _samplers := {}            # body name -> TerrainSampler, built once on first need


# The shared sampler for a body. main's contact kill and the ground tile MUST get
# the same instance, or geometry and lethality drift apart.
func terrain_sampler_for(body: String) -> TerrainSampler:
	if body.is_empty():
		return null
	if not _samplers.has(body):
		for b in _bodies:
			if str(b.name) == body:
				_samplers[body] = PlanetGenerator.terrain_sampler(b.get("recipe", {}))
				break
	return _samplers.get(body, null)
```

Then in `refresh()`, replace the `_surface.update_for(...)` call with:

```gdscript
	if _surface != null:
		var sampler := terrain_sampler_for(nearest_name)
		var ceiling: float = PlanetGenerator.band_ceiling_km(sampler)
		# Altitude above LOCAL GROUND, not above the sphere. Over Everest the two
		# differ by 8.85 km, which is the whole point of the slice.
		var salt: float = nearest_dist - nearest_radius
		if sampler != null and near_physical:
			salt = sampler.alt_above_ground_km(
				(ship_pos - _rel.get(nearest_name, Vector3.ZERO) - ship_pos) * -1.0,
				nearest_radius)
		_surface.position = -ship_pos
		_surface.update_for(ship_pos, nearest_name, near_physical, nearest_radius,
			salt, eph.surface_kill_km(nearest_name), ceiling, near_recipe)
```

**Careful with that position.** The sampler needs the ship's position in the
BODY's model frame. `_rel[name]` is the render-space vector ship→body, so the
ship's offset from the body centre is `-_rel[name]`. Write it plainly instead:

```gdscript
		var from_centre: Vector3 = -_rel.get(nearest_name, Vector3.ZERO)
		if sampler != null and near_physical and from_centre.length() > 0.001:
			salt = sampler.alt_above_ground_km(from_centre, nearest_radius)
```

- [ ] **Step 5: Run both tests**

Run: `timeout 240 godot --headless --path . --script res://tools/test_earth_terrain.gd`
Expected: `earth_terrain: OK`, band line showing Earth ceiling ~15.75 km, Moon ~5.27 km.

Run: `timeout 240 godot --headless --path . --script res://tools/test_surface_band.gd`
Expected: FAIL on `earth_band_still_empty_until_the_kill_line_moves` and the `ground_stamp_ok` arity.

- [ ] **Step 6: Repair test_surface_band.gd's band section**

Every `G.ground_stamp_ok(a, b)` call gains the ceiling argument. Replace the Earth assertion — it was planted last slice precisely so this moment would announce itself, and it has now done its job:

```gdscript
	# Earth's band is still shut, but for a DIFFERENT reason than last slice: the
	# ceiling now clears Everest (15.75 km), and what keeps the band empty is the
	# 29 km kill bubble sitting above it. Task 6 removes that and Earth goes live.
	failed += _check("earth_band_waits_on_the_kill_line", earth_alts.is_empty())
```

Update `_open_window` to take and pass a ceiling.

- [ ] **Step 7: Run the repaired test**

Expected: `surface_band: OK`. The airless band now reads ~0.11..5.26 km rather than ~0.11..3.23 — larger, and correct: the band must clear the terrain, not a plate ratio.

- [ ] **Step 8: Mutation-test**

| Mutation | Must fail |
|---|---|
| `band_ceiling_km` → `return BAND_CEILING_MIN_KM` | `earth_ceiling_clears_everest`, `ceiling_is_derived_not_authored` |
| `BAND_CEILING_MULT` → `12.0` | `no_tile_in_earth_air` |
| `ground_stamp_ok` → drop the `alt_km > kill_km` half | `earth_band_opens_just_above_the_ground` stays green but the kill-line tests in Task 6 fail — note this and rely on Task 6 |

- [ ] **Step 9: Commit**

```bash
git add scripts/world/planet_generator.gd scripts/world/surface_patch.gd scripts/world/planet_system.gd tools/test_earth_terrain.gd tools/test_surface_band.gd
git commit -m "$(cat <<'EOF'
feat: band ceiling derived from the terrain's own height

The old 3.24 km ceiling existed because a single plate only reads as ground
while its width dwarfs your altitude. Rings reach 205 km, so that reason is
gone, and the ceiling's job inverts: open the band ABOVE the tallest
terrain, or you enter it already inside a mountain.

Earth 8.85 x 1.7 = 15.75 km. Airless worlds get the same rule, which moves
their band from 3.24 to ~5.26 km - larger, and correct for the same reason.

PlanetSystem now owns one TerrainSampler per body and hands the same
instance to the tile, so altitude is measured above local ground rather
than above the sphere - a 8.85 km difference over Everest.

Earth's band stays shut, now purely because the 29 km kill bubble sits
above the ceiling. Task 6 removes it.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01XSor1aVH7G1V3YpERuAG16
EOF
)"
```

---

### Task 5: Altitude-ramped speed cap

Lands before contact kill: the spec's position is that a contact test is unsound without a bound on per-frame movement.

**Files:**
- Modify: `scripts/flight/flight_mode.gd`
- Modify: `scripts/world/planet_system.gd`
- Modify: `tools/test_earth_terrain.gd` (add `_cap()`)

**Interfaces:**
- Consumes: `SurfacePatch.ring_quad_km(0)`.
- Produces:
  ```gdscript
  FlightMode.band_speed_cap_ms(alt_above_ground_km: float) -> float   # metres/sec
  FlightMode.band_speed_cap_units(alt_above_ground_km: float) -> float # units/sec
  FlightMode.WORST_FRAME_S -> float
  ```

- [ ] **Step 1: Write the failing test**

Add `failed += _cap()` to `_initialize()`, and:

```gdscript
const FM := preload("res://scripts/flight/flight_mode.gd")


func _cap() -> int:
	var failed := 0

	# The anchors, in m/s.
	failed += _check("cap_at_100km", FM.band_speed_cap_ms(100.0) > 1500.0)
	failed += _check("cap_at_the_ceiling", absf(FM.band_speed_cap_ms(15.0) - 600.0) < 60.0)
	failed += _check("cap_at_5km", absf(FM.band_speed_cap_ms(5.0) - 300.0) < 40.0)
	failed += _check("cap_at_1km", absf(FM.band_speed_cap_ms(1.0) - 150.0) < 25.0)
	failed += _check("cap_on_the_deck", absf(FM.band_speed_cap_ms(0.2) - 60.0) < 12.0)
	failed += _check("cap_never_rises_as_you_descend",
		FM.band_speed_cap_ms(0.05) <= FM.band_speed_cap_ms(0.2))
	failed += _check("cap_is_monotonic",
		FM.band_speed_cap_ms(1.0) < FM.band_speed_cap_ms(5.0)
		and FM.band_speed_cap_ms(5.0) < FM.band_speed_cap_ms(15.0))

	# THE UNIT TRAP. speed_limit is in units/s and 1 unit = 1 km in Sol, so a
	# 600 m/s cap is 0.6. Writing 600.0 there gives 600 km/s: every "cap applied"
	# test still passes and the anti-tunnelling guarantee is silently void.
	failed += _check("units_conversion_is_per_kilometre",
		is_equal_approx(FM.band_speed_cap_units(15.0), FM.band_speed_cap_ms(15.0) / 1000.0))
	failed += _check("cap_in_units_is_not_kilometres_per_second",
		FM.band_speed_cap_units(15.0) < 1.0)

	# The guarantee this whole task exists for: at every altitude in the band, one
	# frame of travel at the cap is shorter than a ring-0 quad, so a swept contact
	# test cannot step over a mountain.
	var quad: float = SP.ring_quad_km(0)
	var earth := G.recipe_for({"name": "Earth"})
	var ceiling: float = G.band_ceiling_km(G.terrain_sampler(earth))
	var worst_alt := 0.0
	var worst_ratio := 0.0
	# Sweep only INSIDE the band. The cap is applied where a tile exists (see
	# PlanetSystem.refresh: `if salt < ceiling`), so sweeping past the ceiling would
	# test the 100 km anchor, which is deliberately looser than the bound and would
	# read as a cap bug rather than a test bug. At 15.75 km the cap is 600 m/s:
	# 600 * 0.05 s = 30 m against a 50 m quad, a ratio of 0.60.
	for i in 2000:
		var alt := ceiling * float(i) / 2000.0
		var step_km: float = FM.band_speed_cap_units(alt) * FM.WORST_FRAME_S
		var ratio := step_km / quad
		if ratio > worst_ratio:
			worst_ratio = ratio
			worst_alt = alt
	failed += _check("cap_prevents_tunnelling", worst_ratio < 1.0)
	# And state the headroom, so raising an anchor cannot quietly eat all of it.
	failed += _check("tunnelling_bound_has_headroom", worst_ratio < 0.8)

	print("earth_terrain: cap  %.0f/%.0f/%.0f/%.0f/%.0f m/s at 100/15/5/1/0.2 km; worst step %.1f%% of a %.0f m quad at %.1f km"
		% [FM.band_speed_cap_ms(100.0), FM.band_speed_cap_ms(15.0),
		FM.band_speed_cap_ms(5.0), FM.band_speed_cap_ms(1.0),
		FM.band_speed_cap_ms(0.2), worst_ratio * 100.0, quad * 1000.0, worst_alt])
	return failed
```

- [ ] **Step 2: Run it to verify it fails**

Expected: FAIL — `band_speed_cap_ms` unknown on `FlightMode`.

- [ ] **Step 3: Implement the cap**

Append to `scripts/flight/flight_mode.gd`:

```gdscript
# --- Skin-band speed cap ---
# Contact kill compares the hull against terrain each frame. Unbounded, MAX_SPEED
# is 10,000 units/s = 10,000 km/s, which at 60 fps is 166 km per frame - the hull
# teleports past whole mountain ranges between samples and the kill becomes a coin
# flip. So the cap is a CORRECTNESS requirement of contact kill, not flight polish.
#
# Read as: the closer you are to rock, the less you may move per frame.
# Presented in-world as an atmospheric flight limit, not an invisible wall.
const BAND_CAP_ANCHORS := [
	[100.0, 2000.0],
	[15.0, 600.0],
	[5.0, 300.0],
	[1.0, 150.0],
	[0.2, 60.0],
]
# Frame time the anti-tunnelling guarantee is proven against. 20 fps, not 60:
# the bound has to hold when the frame rate dips, which is exactly when a point
# test would fail.
const WORST_FRAME_S := 0.05


# Speed ceiling in METRES PER SECOND at this height above local ground.
static func band_speed_cap_ms(alt_above_ground_km: float) -> float:
	var a: Array = BAND_CAP_ANCHORS
	if alt_above_ground_km >= float(a[0][0]):
		return float(a[0][1])
	var last: int = a.size() - 1
	if alt_above_ground_km <= float(a[last][0]):
		return float(a[last][1])
	for i in range(last):
		var hi: Array = a[i]
		var lo: Array = a[i + 1]
		if alt_above_ground_km <= float(hi[0]) and alt_above_ground_km >= float(lo[0]):
			var t: float = (alt_above_ground_km - float(lo[0])) / (float(hi[0]) - float(lo[0]))
			return lerpf(float(lo[1]), float(hi[1]), t)
	return float(a[last][1])


# The same cap in UNITS PER SECOND, which is what ship.speed_limit wants.
# 1 unit = 1 km in Sol, so this divides by 1000. Do the conversion HERE and
# nowhere else: a 600.0 handed straight to speed_limit is 600 km/s and voids
# the tunnelling bound while every "cap applied" assertion still passes.
static func band_speed_cap_units(alt_above_ground_km: float) -> float:
	return band_speed_cap_ms(alt_above_ground_km) / 1000.0
```

- [ ] **Step 4: Wire it into PlanetSystem**

In `refresh()`, right after `salt` is computed in Task 4's block:

```gdscript
		# Fold the band cap into speed_limit. Deliberately NOT gated on
		# `speed_zones` - that flag defers the approach-zone pass, while this cap
		# is what makes contact kill sound.
		if sampler != null and near_physical and salt < ceiling:
			speed_limit = minf(speed_limit, FlightMode.band_speed_cap_units(salt))
```

Add at the top of `planet_system.gd` if not already present:

```gdscript
const FlightMode := preload("res://scripts/flight/flight_mode.gd")
```

- [ ] **Step 5: Run the test to verify it passes**

Expected: `earth_terrain: OK` and a cap line reading `2000/600/300/150/60 m/s at 100/15/5/1/0.2 km; worst step 60.0% of a 50 m quad at 100.0 km`.

If `cap_prevents_tunnelling` fails, do NOT loosen the assertion — lower the offending anchor until the bound holds. The bound is the deliverable.

**Known tension, decided deliberately.** 1 km/s over the Moon already reads as
"frozen" in play (Moon circumference 10,914 km, so that is a three-hour lap), and
the in-band cap runs 60-600 m/s — *slower* than that. The bet is that perceived
speed comes from nearby terrain moving, not from the number: ring 3 puts a horizon
205 km out and Task 7 gives it enough contrast to track. If the band still feels
dead after Task 7, the lever is **ring 0's quad size, not the cap**: the bound is
`cap < quad / WORST_FRAME_S`, so 100 m quads permit 2000 m/s. Raising the cap
alone breaks contact kill.

- [ ] **Step 6: Mutation-test**

| Mutation | Must fail |
|---|---|
| `band_speed_cap_units` → `return band_speed_cap_ms(alt)` (the unit bug) | `units_conversion_is_per_kilometre`, `cap_in_units_is_not_kilometres_per_second`, `cap_prevents_tunnelling` |
| first anchor → `[100.0, 20000.0]` | `cap_prevents_tunnelling` |
| `WORST_FRAME_S` → `0.001` | nothing — note that this weakens the proof, so the constant carries a comment saying why it is 20 fps |
| invert the anchor list order | `cap_is_monotonic` |

- [ ] **Step 7: Commit**

```bash
git add scripts/flight/flight_mode.gd scripts/world/planet_system.gd tools/test_earth_terrain.gd
git commit -m "$(cat <<'EOF'
feat: altitude-ramped band speed cap, with an anti-tunnelling proof

Contact kill compares the hull against terrain each frame. Unbounded,
MAX_SPEED is 10,000 units/s = 10,000 km/s, or 166 km per frame at 60 fps -
the hull steps over whole mountain ranges between samples. The cap is
therefore a correctness requirement of contact kill, not flight polish,
and it is applied independently of the deferred speed_zones flag.

The test is the guarantee, not the numbers: at every altitude in the band,
one frame of travel at the cap is shorter than a ring-0 quad. Proven at
20 fps rather than 60, because the bound has to hold when the frame rate
dips - which is exactly when a point test would fail.

speed_limit is in units/s with 1 unit = 1 km, so the m/s-to-units
conversion lives in one function and two assertions guard it. A 600.0
handed straight to speed_limit is 600 km/s and voids the bound while every
"cap applied" test still passes.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01XSor1aVH7G1V3YpERuAG16
EOF
)"
```

---

### Task 6: Swept contact kill — Earth goes live

**Files:**
- Modify: `scripts/autoload/ephemeris.gd`
- Modify: `scripts/core/main.gd:1484-1506`
- Modify: `tools/test_skin_kill.gd`
- Modify: `tools/test_earth_terrain.gd` (add `_kill()`)

**Interfaces:**
- Consumes: `TerrainSampler.alt_above_ground_km`, `PlanetSystem.terrain_sampler_for`.
- Produces:
  ```gdscript
  Ephemeris.CONTACT_KILL_FLOOR_KM -> float (0.02)
  Ephemeris.surface_kill_km(body_name: String = "") -> float   # now a contact margin
  TerrainSampler.swept_contact(from: Vector3, to: Vector3, body_radius_km: float, contact_km: float) -> bool
  ```

- [ ] **Step 1: Write the failing test**

Add `failed += _kill()` to `_initialize()`, and:

```gdscript
func _kill() -> int:
	var failed := 0
	var earth := G.recipe_for({"name": "Earth"})
	var s = G.terrain_sampler(earth)
	var everest := _dir_of(27.9881, 86.9250)
	var pacific := _dir_of(0.0, -150.0)
	var e_ground: float = s.ground_radius_km(everest, EARTH_R)
	var p_ground: float = s.ground_radius_km(pacific, EARTH_R)

	# The whole point: the Pacific and Everest's summit no longer kill at the same
	# altitude. 9 km over the sphere is INSIDE the mountain.
	failed += _check("nine_km_over_the_sphere_is_inside_everest",
		EARTH_R + 9.0 < e_ground + 1.0)
	failed += _check("nine_km_over_the_pacific_is_clear_air",
		EARTH_R + 9.0 > p_ground + 8.0)

	var contact := 0.02
	failed += _check("contact_fires_at_the_mountain",
		s.swept_contact(everest * (e_ground + 0.5), everest * (e_ground + 0.01),
			EARTH_R, contact))
	failed += _check("contact_holds_off_above_the_mountain",
		not s.swept_contact(everest * (e_ground + 3.0), everest * (e_ground + 2.9),
			EARTH_R, contact))
	failed += _check("low_pass_over_the_ocean_survives",
		not s.swept_contact(pacific * (p_ground + 1.0), pacific * (p_ground + 1.0),
			EARTH_R, contact))
	failed += _check("touching_the_ocean_kills",
		s.swept_contact(pacific * (p_ground + 0.5), pacific * (p_ground + 0.005),
			EARTH_R, contact))

	# THE swept assertion. A point test at both ends of this segment sees clear air
	# at 12 km and clear air out over the lowlands, and misses the mountain in
	# between. One frame-rate dip and you fly through Everest.
	var before: Vector3 = _dir_of(27.9881, 84.0) * (EARTH_R + 9.5)
	var after: Vector3 = _dir_of(27.9881, 89.0) * (EARTH_R + 9.5)
	var point_test_says_safe: bool = \
		s.alt_above_ground_km(before, EARTH_R) > contact \
		and s.alt_above_ground_km(after, EARTH_R) > contact
	failed += _check("point_test_would_have_missed_it", point_test_says_safe)
	failed += _check("swept_kill_catches_a_frame_long_jump",
		s.swept_contact(before, after, EARTH_R, contact))

	print("earth_terrain: kill  Everest ground %.2f km radius (+%.0f m), Pacific %.2f (+%.0f m); swept catches the 5-degree jump: %s"
		% [e_ground, (e_ground - EARTH_R) * 1000.0, p_ground,
		(p_ground - EARTH_R) * 1000.0,
		str(s.swept_contact(before, after, EARTH_R, contact))])
	return failed
```

- [ ] **Step 2: Run it to verify it fails**

Expected: FAIL — `swept_contact` unknown on `TerrainSampler`.

- [ ] **Step 3: Add the swept test to TerrainSampler**

Append to `scripts/world/terrain_sampler.gd`:

```gdscript
# Did the hull touch ground anywhere along this frame's movement? Samples the
# SEGMENT, not its endpoints.
#
# A point test is not enough and the failure is not theoretical: fly east along
# 28N at 9.5 km and both ends of a single frame's movement are clear air over the
# Nepalese lowlands while Everest stands in the middle. One frame-rate dip and you
# pass through the mountain. Sample count follows the distance travelled, so a
# slow hover costs one sample and a fast pass costs proportionally more.
func swept_contact(from: Vector3, to: Vector3, body_radius_km: float,
		contact_km: float) -> bool:
	if alt_above_ground_km(to, body_radius_km) <= contact_km:
		return true
	var travel := from.distance_to(to)
	if travel < 0.0001:
		return false
	# One sample per ~50 m of travel (a ring-0 quad), capped so a teleport cannot
	# stall the frame. 64 samples covers 3.2 km, which the speed cap guarantees.
	var steps := clampi(int(ceil(travel / 0.05)), 1, 64)
	for i in range(1, steps):
		var p: Vector3 = from.lerp(to, float(i) / float(steps))
		if alt_above_ground_km(p, body_radius_km) <= contact_km:
			return true
	return false
```

- [ ] **Step 4: Retire the 29 km bubble in Ephemeris**

In `scripts/autoload/ephemeris.gd`, replace the `EARTH_MIN_R_KM` block:

```gdscript
# No landing. You die on CONTACT with terrain, not at an altitude.
# This replaced a 29 km bubble (EARTH_MIN_R_KM = 6400, so kill = 6400 - 6371),
# which killed you at a fixed radius regardless of what was under you - the
# Pacific and the summit of Everest were equally lethal at the same altitude,
# and Earth could never show ground because the bubble sat 29 km above it.
# Now: kill when the hull is within CONTACT of the ground BELOW it, which
# TerrainSampler computes per position. This value is the hull's contact margin.
const CONTACT_KILL_FLOOR_KM := 0.02
const SURFACE_KILL_SECS := 2.2
```

Delete `const EARTH_MIN_R_KM := 6400.0` and `const SURFACE_KILL_FLOOR_KM := 0.1`.

Rewrite `surface_kill_km`:

```gdscript
# Contact margin for a body: how close the hull may get to the ground before it
# is a crash. No longer an altitude above the sphere - see CONTACT_KILL_FLOOR_KM.
func surface_kill_km(body_name: String = "") -> float:
	var extra := maxf(float(surface_kill_extra_km.get(body_name, 0.0)), 0.0)
	return CONTACT_KILL_FLOOR_KM + extra
```

Rewrite `sweet_spot`'s park distance, which used `kill * 4` and would now be 80 m:

```gdscript
	# Park well clear of the band, not clear of the old 29 km bubble.
	var park := rad + maxf(atmo_top_km(body_name) * 1.5, 120.0)
```

- [ ] **Step 5: Make main's kill test swept and terrain-aware**

Replace the body of `_update_skin_kill` from `if not planets.is_physical(...)` onward:

```gdscript
	if not planets.is_physical(planets.nearest_name):
		return
	if planets.nearest_dist >= INF or planets.nearest_radius <= 0.0:
		return
	var sampler := planets.terrain_sampler_for(planets.nearest_name)
	if sampler == null:
		return
	# Position relative to the body's CENTRE, which is the frame the sampler works
	# in. planets.rel_of() is the render-space vector ship->body, so negate it.
	var from_centre: Vector3 = -planets.rel_of(planets.nearest_name)
	if from_centre.length() < 0.001:
		return
	var contact: float = Ephemeris.surface_kill_km(planets.nearest_name)
	# Sweep the segment this frame covered. The endpoints of one frame's travel can
	# both be clear air with a mountain standing between them.
	var prev: Vector3 = _prev_from_centre if _prev_body == planets.nearest_name \
		else from_centre
	if sampler.swept_contact(prev, from_centre, planets.nearest_radius, contact):
		_skin_begin(planets.nearest_name)
	_prev_from_centre = from_centre
	_prev_body = planets.nearest_name
```

Add the two state vars near main's other flight state:

```gdscript
var _prev_from_centre := Vector3.ZERO   # last frame's ship offset from the nearest body
var _prev_body := ""                    # which body that was, so a swap does not sweep
                                        # across interplanetary space
```

- [ ] **Step 6: Rewrite test_skin_kill.gd's four bubble assertions**

Replace them with contact-margin assertions:

```gdscript
	# The 29 km bubble is gone. Kill is contact with the ground below you, which
	# TerrainSampler decides per position - see tools/test_earth_terrain.gd _kill().
	failed += _check("earth_uses_a_contact_margin",
		is_equal_approx(eph.surface_kill_km("Earth"), E.CONTACT_KILL_FLOOR_KM))
	failed += _check("every_world_uses_the_same_margin",
		is_equal_approx(eph.surface_kill_km("Moon"), eph.surface_kill_km("Earth")))
	failed += _check("margin_is_small_enough_to_fly_the_deck",
		eph.surface_kill_km("Earth") < 0.1)
	failed += _check("margin_is_big_enough_to_beat_mesh_error",
		eph.surface_kill_km("Earth") > 0.0)
```

Update `earth_kill_29km` and `moon_at_floor` to reference `CONTACT_KILL_FLOOR_KM`, and delete the two references to `E.EARTH_MIN_R_KM` and `E.SURFACE_KILL_FLOOR_KM`.

- [ ] **Step 7: Flip Earth's band assertion in test_surface_band.gd**

```gdscript
	# Earth's band is LIVE. This assertion is the inverse of the one two slices
	# planted here so that moving the kill line would announce itself; it has.
	failed += _check("earth_band_is_no_longer_empty", earth_alts.size() > 0)
	failed += _check("earth_band_reaches_everest_height",
		earth_alts.size() > 0 and float(earth_alts[-1]) > 8.848)
```

- [ ] **Step 8: Run everything**

```bash
for t in test_earth_terrain test_surface_band test_skin_kill test_planet_generator test_sol_cook test_flight_mode test_newton; do
  printf '%-26s ' "$t"
  timeout 240 godot --headless --path . --script res://tools/$t.gd 2>&1 | grep -E ': (OK|FAIL)' | tail -1
done
timeout 90 godot --headless --path . --quit-after 240 2>&1 | grep -iE 'SCRIPT ERROR|Invalid|nonexistent|Cannot call|too few|too many'
```

Expected: all OK, and no script errors from the boot.

- [ ] **Step 9: Mutation-test**

| Mutation | Must fail |
|---|---|
| `swept_contact` → test only `to` | `swept_kill_catches_a_frame_long_jump` |
| `swept_contact` → `return false` | `contact_fires_at_the_mountain`, `touching_the_ocean_kills` |
| `alt_above_ground_km` in the kill path → `d - body_radius_km` | `nine_km_over_the_sphere_is_inside_everest` stays green; `contact_holds_off_above_the_mountain` fails |
| `CONTACT_KILL_FLOOR_KM` → `29.0` | `margin_is_small_enough_to_fly_the_deck`, `earth_band_is_no_longer_empty` |

- [ ] **Step 10: Commit**

```bash
git add scripts/autoload/ephemeris.gd scripts/core/main.gd tools/test_skin_kill.gd tools/test_surface_band.gd tools/test_earth_terrain.gd scripts/world/terrain_sampler.gd
git commit -m "$(cat <<'EOF'
feat: swept contact kill replaces the 29 km bubble - Earth goes live

You now die on contact with the ground BELOW you rather than at a fixed
radius from the centre. The old rule made the Pacific and the summit of
Everest equally lethal at the same altitude, and kept Earth from ever
showing ground because the bubble sat 29 km above it.

The test sweeps the segment the hull covered this frame, not its endpoints.
This is not theoretical: flying east along 28N at 9.5 km, both ends of one
frame's travel are clear air over the Nepalese lowlands with Everest
standing in between. test_earth_terrain asserts a point test WOULD have
missed it, then that the swept test catches it.

Retires EARTH_MIN_R_KM and SURFACE_KILL_FLOOR_KM; surface_kill_km is now a
contact margin, and sweet_spot parks clear of the band rather than clear of
the old bubble. Four assertions in test_skin_kill rewritten, and Earth's
band assertion in test_surface_band inverted - it was planted two slices
ago precisely so this change would announce itself.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01XSor1aVH7G1V3YpERuAG16
EOF
)"
```

---

### Task 7: Shared surface colour

**Files:**
- Modify: `scripts/world/terrain_sampler.gd`
- Modify: `scripts/world/surface_patch.gd` (`_color_at` delegates)
- Modify: `tools/test_earth_terrain.gd` (add `_colour()`)

**Interfaces:**
- Consumes: `TerrainSampler.height_m`, `._slope01`.
- Produces:
  ```gdscript
  TerrainSampler.surface_color(dir: Vector3, plate_km: float) -> Color
  TerrainSampler.map_weight(plate_km: float) -> float
  TerrainSampler.km_per_texel(body_radius_km: float) -> float
  ```

- [ ] **Step 1: Write the failing test**

Add `failed += _colour()` to `_initialize()`, and:

```gdscript
func _colour() -> int:
	var failed := 0
	var earth := G.recipe_for({"name": "Earth"})
	var s = G.terrain_sampler(earth)

	# Measured on the shipped tile: at 1 km altitude a 10 km plate covers 1.9
	# albedo texels on the Moon, 0.96 on Mars, 0.51 on Earth. Half a pixel of
	# colour across the whole visible ground. No triangle count fixes that, which
	# is why the palette has to take over as the map runs out.
	var far_w: float = s.map_weight(200.0)
	var near_w: float = s.map_weight(2.0)
	failed += _check("map_leads_when_it_has_detail", far_w > 0.9)
	failed += _check("noise_leads_when_it_does_not", near_w < 0.3)
	failed += _check("map_is_never_fully_discarded", near_w > 0.0)
	failed += _check("map_weight_is_monotonic", far_w > near_w)

	# The palette must actually vary with the terrain, or we have swapped one flat
	# colour for another.
	var high: Color = s.surface_color(_dir_of(27.9881, 86.9250), 2.0)
	var low: Color = s.surface_color(_dir_of(-3.4653, -62.2159), 2.0)
	var sea: Color = s.surface_color(_dir_of(0.0, -150.0), 2.0)
	failed += _check("high_ground_differs_from_low", high != low)
	failed += _check("land_differs_from_water", low != sea)
	var spread: float = absf(high.r - low.r) + absf(high.g - low.g) + absf(high.b - low.b)
	failed += _check("palette_is_not_one_flat_colour", spread > 0.12)

	print("earth_terrain: colour  map weight %.2f at 200 km / %.2f at 2 km; Everest %s, Amazon %s, Pacific %s"
		% [far_w, near_w, str(high.to_html(false)), str(low.to_html(false)),
		str(sea.to_html(false))])
	return failed
```

- [ ] **Step 2: Run it to verify it fails**

Expected: FAIL — `map_weight` unknown on `TerrainSampler`.

- [ ] **Step 3: Implement the shared palette**

Append to `scripts/world/terrain_sampler.gd`:

```gdscript
# --- Surface colour ---
# The albedo map runs out of information long before the geometry does. Measured
# on the shipped tile: at 1 km altitude a 10 km plate spans 1.9 texels of the
# Moon's 2048px albedo, 0.96 on Mars and 0.51 on EARTH. Half a pixel. The ground
# is one flat colour and no triangle count changes it - this is the "blurry
# surface" from the first GPU look, and it is a data limit.
#
# planet_cook.gdshader already solves it for the globe: past detail > 0.02 it
# blends a procedural grass/rock/dirt/ice palette by height and slope. The tile
# used to sample the albedo and stop, so it was BLURRIER than the globe at the
# same altitude and the two disagreed at the tile's edge. Same rule as height:
# one palette, two consumers.
const MAP_FADE_TEXELS := 4.0     # above this many texels across, the map still leads
const ALBEDO_TEXELS := 2048.0    # width of every albedo in assets/planets

const PALETTE_GRASS := Color(0.16, 0.30, 0.09)
const PALETTE_ROCK := Color(0.40, 0.36, 0.32)
const PALETTE_DIRT := Color(0.38, 0.28, 0.16)
const PALETTE_ICE := Color(0.86, 0.89, 0.93)
const PALETTE_OCEAN := Color(0.06, 0.22, 0.32)


# Kilometres of ground per albedo texel at this body's size.
func km_per_texel(body_radius_km: float) -> float:
	return TAU * body_radius_km / ALBEDO_TEXELS


# How much the map should lead, 0..1, from how many texels it still spans across
# the plate. A measurable quantity, not a taste knob.
func map_weight(plate_km: float) -> float:
	if not _has_map and _simg == null:
		return 0.0
	var texels := plate_km / km_per_texel(6371.0)
	return clampf(texels / MAP_FADE_TEXELS, 0.0, 1.0)


# Ground colour, blending the map (which holds the real evidence - Mare Imbrium
# dark, the Sahara pale) with the procedural palette that carries detail once the
# map has none left.
func surface_color(dir: Vector3, plate_km: float) -> Color:
	if is_water(dir):
		return PALETTE_OCEAN
	var h_m := height_m(dir)
	var h01 := clampf(h_m / maxf(max_height_km() * 1000.0, 1.0), 0.0, 1.0)
	var slope := _slope01(dir)
	# Height picks the band, slope exposes rock through it.
	var proc: Color = PALETTE_GRASS.lerp(PALETTE_DIRT, clampf(h01 * 2.2, 0.0, 1.0))
	proc = proc.lerp(PALETTE_ICE, smoothstep(0.45, 0.78, h01))
	proc = proc.lerp(PALETTE_ROCK, slope * 0.65)
	var w := map_weight(plate_km)
	if w <= 0.0:
		return proc
	var mapped := _map_color(dir)
	return proc.lerp(mapped, w)


func _map_color(dir: Vector3) -> Color:
	if _aimg_cache == null:
		return PALETTE_ROCK
	var uv := _dir_uv(dir)
	var x := int(floor(fposmod(uv.x, 1.0) * float(_aimg_cache.get_width())))
	var y := int(floor(clampf(uv.y, 0.0, 0.999) * float(_aimg_cache.get_height())))
	return _aimg_cache.get_pixel(x, y)
```

Add the albedo image to the sampler's state — in the var block:

```gdscript
var _aimg_cache: Image            # albedo, for the map half of surface_color
```

and in `_init`, after `_simg`:

```gdscript
	_aimg_cache = _img_of(str(recipe.get("albedo", "")))
```

- [ ] **Step 4: Delegate the tile's colour to the sampler**

In `scripts/world/surface_patch.gd`, replace `_color_at` entirely:

```gdscript
# Colour comes from the sampler, so the tile and the globe shader cannot disagree
# at the tile's edge. See TerrainSampler.surface_color.
func _color_at(dir: Vector3, _uv: Vector2, _h: float) -> Color:
	return _sampler.surface_color(dir, ring_reach_km(0))
```

- [ ] **Step 5: Run the test to verify it passes**

Expected: `earth_terrain: OK` and a colour line showing map weight near 1.0 at 200 km and well under 0.3 at 2 km, with three distinct hex colours.

- [ ] **Step 6: Mutation-test**

| Mutation | Must fail |
|---|---|
| `map_weight` → `return 1.0` | `noise_leads_when_it_does_not`, `map_weight_is_monotonic` |
| `map_weight` → `return 0.0` | `map_leads_when_it_has_detail`, `map_is_never_fully_discarded` |
| `surface_color` → `return _map_color(dir)` | `palette_is_not_one_flat_colour` (Earth's albedo is ~0.5 texel across a 2 km plate, so all three points sample nearly the same pixel) |
| drop the slope term | `palette_is_not_one_flat_colour` may survive — note this and rely on the height terms |

- [ ] **Step 7: Full suite and boot**

```bash
for f in tools/test_*.gd; do
  t=$(basename "$f" .gd)
  if [ -f "tools/$t.tscn" ]; then out=$(timeout 240 godot --headless --path . "res://tools/$t.tscn" 2>&1)
  else out=$(timeout 240 godot --headless --path . --script "res://$f" 2>&1); fi
  printf '%-28s %s\n' "$t" "$(echo "$out" | grep -E ': (OK|FAIL)' | tail -1)"
done
```

Expected: everything OK except the two pre-existing `booster_brightness` knob guards in `test_class_ii_cruiser` and `test_jazoone_spaceship`, and `test_wh_network`, which times out for unrelated reasons (no preloads, zero planet references).

- [ ] **Step 8: Update the docs**

Add a section to `PLANET_GENERATOR.md` under the skin-band section, and a new dated section at the top of `HANDOFF.md`, covering: the DEM's measured encoding, why rings replaced the plate, the ceiling rule inversion, the units/s trap, the swept-versus-point kill, and the texel arithmetic behind A5. State plainly that nothing here was verified on a GPU.

- [ ] **Step 9: Commit**

```bash
git add scripts/world/terrain_sampler.gd scripts/world/surface_patch.gd tools/test_earth_terrain.gd PLANET_GENERATOR.md HANDOFF.md
git commit -m "$(cat <<'EOF'
feat: one surface palette shared by the tile and the globe

The albedo map runs out before the geometry does. Measured: at 1 km
altitude a 10 km plate spans 1.9 texels of the Moon's 2048px albedo, 0.96
on Mars, 0.51 on Earth - half a pixel of colour across the whole visible
ground. That is the "blurry surface" from the first GPU look, and it is a
data limit no triangle count fixes.

planet_cook.gdshader already blends a procedural height/slope palette for
the globe; the tile sampled the albedo and stopped, so it was blurrier than
the globe at the same altitude and the two disagreed at the tile's edge.
Now both use one palette, weighted by how many texels the map still spans
across the plate - a measurable quantity rather than a taste knob. The map
is never fully discarded, so Mare Imbrium stays dark and the Sahara pale.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01XSor1aVH7G1V3YpERuAG16
EOF
)"
```

---

## Self-Review

**Spec coverage:**

| Spec section | Task |
|---|---|
| A1 one height function, two consumers | 2 (built), 3 (`mesh_matches_the_height_function`), 6 (kill consumes it) |
| A1 DEM encoding measured first | 1 |
| A2 four nested rings, donuts, skirts, constant budget | 3 |
| A3 ceiling from terrain max height | 4 |
| A3 contact kill, retired constants, swept segment | 6 |
| A4 ramped cap, units, anti-tunnelling proof | 5 |
| A5 shared surface colour, texel-weighted | 7 |
| Props on ring 0 only | 3 (`if ring == 0`) |
| Mutation-testing every assertion | every task's mutation step |

**Known gaps, stated rather than hidden:**

- **`_slope01` is called from `surface_color` but is private.** Same file, so this
  works in GDScript, but Task 7 relies on Task 2's internal. Flagged so the
  implementer does not "fix" it by duplicating the slope maths — that would
  recreate exactly the two-implementations bug this slice exists to prevent.
- **`map_weight` hardcodes Earth's radius** in its texel calculation
  (`km_per_texel(6371.0)`), because the sampler does not know its body's radius.
  Correct for Earth, wrong by 3.7x for the Moon. Acceptable this slice (the weight
  is a blend factor, not a measurement) but it means the Moon's map fades later
  than it should. Fix by storing the radius on the sampler when a body binds it —
  do that if the Moon looks worse after Task 7 than before.
- **Task 4 Step 4 shows the position maths twice**, once wrongly and once
  plainly. Use the second form (`from_centre = -_rel[name]`). The first is left in
  as the trap it is: the sampler needs body-frame coordinates and `_rel` points
  the other way.
- **`DEM_SEA_LEVEL` / `DEM_PEAK_VALUE` are placeholders in Task 2's code**, filled
  from Task 1's measurement. This is the one intentional "fill in from the
  previous step" in the plan, and Task 2's test fails loudly if they are wrong.

**Type consistency:** `ground_stamp_ok` gains a third parameter in Task 4 and every
call site is updated in that same task (`surface_patch.should_show`, both tests).
`should_show` and `update_for` gain `ceiling` in Task 4. `_color_at` keeps its
three-parameter shape in Task 7 so `_vert` needs no edit. `report()` keys change in
Task 3 (`ground_verts`/`water_verts`/`ground_aabb` → `rings`/`tris`/`ring_verts`)
and `test_surface_band.gd`'s `_tile()` section reads the old keys — Task 3 Step 5
must update those reads too.
