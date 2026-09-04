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

# --- DEM encoding, MEASURED by tools/probe_earth_dem.gd ---
# These are FACTS ABOUT THE FILE, not tuning. If earth_height.jpg is ever
# re-fetched, re-run that probe: a pack with different encoding would silently
# flatten or invert the planet. tools/test_earth_terrain.gd pins them.
#
#   5400 x 2700, 7.42 km per texel at the equator
#   mid-Pacific and mid-Atlantic both sample exactly 0.0000  -> sea level is 0
#   Mariana Trench also samples 0.0000, identical to open ocean
#     -> ocean depth is NOT encoded; this is a land-only map clamped at the floor
#   Everest samples 0.9547 -> 8848 / 0.9547 = 9267.7 m per unit
#   Cross-check at that scale: Denali +1%, Aconcagua +2%, Kilimanjaro +7%
const DEM_SEA_LEVEL := 0.0
const DEM_PEAK_VALUE := 0.9547     # Everest's texel — the calibration anchor
const DEM_PEAK_M := 8848.0
# The highest sample ANYWHERE in the file, which is above Everest's own texel.
# max_height_km() uses this, not DEM_PEAK_VALUE: the band ceiling has to bound
# the terrain that exists, not the terrain we happened to name.
const DEM_MAX_VALUE := 0.9804
const DEM_HAS_BATHYMETRY := false

# Metres per unit of DEM sample above sea level.
const DEM_SCALE_M := DEM_PEAK_M / maxf(DEM_PEAK_VALUE - DEM_SEA_LEVEL, 0.0001)

# Elevation scale for a world with NO height map. Keeps the 3.2 lift constant
# surface_patch._vert already used, so airless relief does not change character.
const NOISE_RELIEF_KM := 3.2
# fbm3 sums 5 octaves of halving amplitude: 0.5+0.25+0.125+0.0625+0.03125.
const FBM_CEILING := 0.96875
# ...and its MEAN is that ceiling times 0.5, because the underlying value noise is
# uniform on 0..1. Subtracting it is what makes a noise world's terrain straddle
# the sphere instead of standing on a plinth above it.
#
# THE BUG THIS FIXES: crust_height() is all-positive, so
# `crust * NOISE_RELIEF_KM` put the ENTIRE lunar surface between 380 m and
# 2421 m above the sphere, averaging 1457 m. Altitude on the tape is measured
# from the sphere, so at "Alt 2 km" over the Moon the real ground was already at
# the hull and contact kill fired correctly - which in play read as being unable
# to descend below 2 km. Terrain oscillates about a datum.
const FBM_MEAN := FBM_CEILING * 0.5

# Procedural detail added on top of the DEM. Amplitude scales with the DEM's
# local slope: a 7.42 km texel cannot express a ridge, so flat sea floor stays
# flat while mountains get rugged. This is what makes 50 m triangles worth
# building instead of just interpolating between texels.
# DETAIL FREQUENCY, and it was wrong by 150x.
# 900 cycles across the body is a 44.5 km wavelength - COARSER than ring 0's
# entire width (4.3 km at 6 km altitude), so detail was a constant offset across
# the whole fine ring and contributed nothing. Worse, the DEM's 7.42 km texels
# already supply everything above ~15 km, so the band detail was covering was
# already covered.
#
# Detail's job is the range the DEM CANNOT express: from one texel down to
# roughly a ring-0 quad. 11000 gives a 3.6 km base, and four ridged octaves carry
# it to 3643 / 1760 / 850 / 411 m - ridge scale through to roughness.
const DETAIL_FREQ := 11000.0
const DETAIL_MAX_M := 160.0        # amplitude at full slope
# 160 is MEASURED, not guessed. Amplitude has to be set against the finest
# octave's wavelength or the terrain becomes spikes: at 420 m the Moon came out
# with a mean grade of 0.85 (40 degrees) and a worst of 3.89 (76), which is not
# terrain. Ridged noise roughly doubles the gradient of smooth noise, which is
# what the first pass failed to compensate for. Swept over 40 m steps:
#   420 m -> mean 40.5 deg, worst 76   spikes
#   160 m -> mean 18.0 deg, worst 56   a hillside with cliff faces
#   110 m -> mean 12.6 deg, worst 46   gentle
#    80 m -> mean  9.2 deg, worst 36   rolling
# A real mountainside is 0.3-0.7 grade (17-35 degrees), so 160 sits at the rugged
# end of believable. tools/test_earth_terrain.gd pins the band.
# Even flat plains are not billiard tables, so slope scales detail down but never
# to nothing - and it is CAPPED well below 1.0 at the top.
#
# Detail is ROUGHNESS ON TOP OF the DEM's shape, not a multiplier of it. Letting
# it scale to full amplitude wherever the DEM is steep piled 160 m of ridged noise
# onto the Himalaya's own grade (slope01 there is 1.00, against the Moon's flat
# 0.35) and produced 78-degree turns between adjacent vertex normals. Capping the
# top keeps roughness roughly consistent everywhere and leaves the large-scale
# steepness to the DEM, which is the thing that actually knows about it.
const DETAIL_SLOPE_FLOOR := 0.18
const DETAIL_SLOPE_CEIL := 0.55
# Three octaves, not five. Each octave is 8 hash() calls, and this fbm is the
# single dominant cost in a ring rebuild (4,225 heights x 40 sin() at five
# octaves). Octaves 4 and 5 together carry under 9% of the amplitude - at most
# 39 m here. crust_height() still uses the full five, because THAT one has to
# mirror planet_cook.gdshader exactly.
const DETAIL_OCTAVES := 4
const NOISE_WORLD_SLOPE := 0.35    # a noise world is already rugged at every scale

# Maps are cached as RAW SINGLE-CHANNEL BYTES, not as Images.
# Image.get_pixel() from GDScript costs an Object call per texel, and one
# height_m() makes ~20 of them (4 for the bilinear, 16 more for the slope). That
# measured 11.78 us per call, which at 16,384 calls per ring is 267 ms - 3.7 fps,
# exactly what was reported in play. Direct byte indexing runs the SAME bilinear
# maths with none of the dispatch. Earth's height map is 5400x2700 = 14.6 MB here.
var _h_bytes := PackedByteArray()
var _h_w := 0
var _h_h := 0
var _s_bytes := PackedByteArray()
var _s_w := 0
var _s_h := 0
var _aimg: Image                   # kept for callers that still want the Image
# Albedo as raw RGB bytes: _color_at reads it once per grid vertex, which is 4,225
# Image.get_pixel() calls per ring rebuild.
var _a_bytes := PackedByteArray()
var _a_w := 0
var _a_h := 0
var _seed := 0.0                   # the SAME seed the cook material got
var _land := 1.0                   # recipe land_amount, the water cut with no mask
var _has_map := false


func _init(recipe: Dictionary) -> void:
	var hm := _load_gray(str(recipe.get("height", "")))
	_h_bytes = hm.bytes
	_h_w = hm.w
	_h_h = hm.h
	var wm := _load_gray(str(recipe.get("specular", "")))
	_s_bytes = wm.bytes
	_s_w = wm.w
	_s_h = wm.h
	var am := _img_of(str(recipe.get("albedo", "")))
	if am != null:
		am.convert(Image.FORMAT_RGB8)
		_a_bytes = am.get_data()
		_a_w = am.get_width()
		_a_h = am.get_height()
	_aimg = am
	_seed = float(recipe.get("seed", 0.0))
	_land = float(recipe.get("land_amount", 1.0))
	_has_map = _h_w > 0


# Metres above sea level at a point on the crust. `dir` is an outward unit vector
# in MODEL space — the same vector the cook shader calls `n`.
func height_m(dir: Vector3) -> float:
	var base := base_height_m(dir)
	if _has_map and base <= 0.0 and not DEM_HAS_BATHYMETRY:
		return 0.0                 # ocean floor is not modelled; sea level is the floor
	return base + _detail_m(dir, base)


# The map/noise value with NO procedural detail on top. Exists so the detail pass
# is separately testable: without this seam an assertion about "detail varies the
# ground" passes on bilinear interpolation of the DEM alone, which is what it did
# on the first draft of tools/test_earth_terrain.gd.
func base_height_m(dir: Vector3) -> float:
	if _has_map:
		var mapped := (_bilinear_bytes(_h_bytes, _h_w, _h_h, _dir_uv(dir)) - DEM_SEA_LEVEL) \
			* DEM_SCALE_M
		return maxf(mapped, 0.0) if not DEM_HAS_BATHYMETRY else mapped
	# CENTRED on the datum, and deliberately NOT clamped: negative is a basin, not
	# an ocean. An airless world has no sea level, and clamping here would flatten
	# half the Moon into a plate sitting exactly on the sphere.
	return (PlanetGenerator.crust_height(dir, _seed) - FBM_MEAN) * NOISE_RELIEF_KM * 1000.0


# Ruggedness between DEM samples, scaled by how steep the DEM already is here.
func _detail_m(dir: Vector3, base_m: float) -> float:
	# Water flatness has THREE independent guards, and mutation testing showed the
	# load-bearing one is not either of the explicit checks: over open ocean the DEM
	# is flat, so slope01() is exactly 0 and the amplitude below vanishes on its own.
	# Removing this line AND height_m's `base <= 0.0` early return still leaves the
	# Pacific flat; only forcing slope01() to a constant wrinkles it. Keep all three
	# anyway - the early returns are cheap and they are what will matter the day
	# DEM_HAS_BATHYMETRY becomes true and `base` can legitimately go negative.
	# Flat where there is water. Gated on _has_map, because a noise world's basins
	# are legitimately below the datum and must still get their detail.
	if _has_map and base_m < 1.0:
		return 0.0                 # keep water flat
	# RIDGED, not smooth: ridged noise creases, which is what reads as a mountain
	# ridgeline instead of a dune, and it gets that structure without paying for
	# more octaves.
	var slope := lerpf(DETAIL_SLOPE_FLOOR, DETAIL_SLOPE_CEIL, slope01(dir))
	var n: float = PlanetGenerator.ridged3(
		dir * DETAIL_FREQ + Vector3(_seed, _seed, _seed), DETAIL_OCTAVES)
	# Ridged noise is 0..1 with its mass toward 1, so centre it before scaling or
	# it becomes a uniform lift rather than relief.
	return (n - 0.5) * 2.0 * DETAIL_MAX_M * slope


# 0..1 steepness from the DEM's own neighbourhood. Public because surface_color()
# needs it too — do NOT reimplement slope anywhere else.
func slope01(dir: Vector3) -> float:
	if not _has_map:
		return NOISE_WORLD_SLOPE
	var uv := _dir_uv(dir)
	var e := 1.0 / float(_h_w)
	var dx := _bilinear_bytes(_h_bytes, _h_w, _h_h, uv + Vector2(e, 0.0)) \
		- _bilinear_bytes(_h_bytes, _h_w, _h_h, uv - Vector2(e, 0.0))
	var dy := _bilinear_bytes(_h_bytes, _h_w, _h_h, uv + Vector2(0.0, e)) \
		- _bilinear_bytes(_h_bytes, _h_w, _h_h, uv - Vector2(0.0, e))
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
	if _s_w > 0:
		return _bilinear_bytes(_s_bytes, _s_w, _s_h, _dir_uv(dir)) > 0.5
	if _has_map:
		return height_m(dir) <= 0.5
	# No mask and no map: the cook shader's land_amount cut on fbm.
	var edge := 1.0 - _land
	var h: float = PlanetGenerator.fbm3(dir * 2.1 + Vector3(_seed, _seed, _seed))
	return (1.0 - smoothstep(edge - 0.05, edge + 0.05, h)) > 0.5


# Tallest terrain this world can produce, km. Drives the band ceiling, so it must
# be an UPPER BOUND and not an average — enter the band below the terrain and you
# arrive inside a mountain.
func max_height_km() -> float:
	if _has_map:
		return (DEM_MAX_VALUE * DEM_SCALE_M + DETAIL_MAX_M) / 1000.0
	# Centred, so the peak ABOVE the datum is only the half-range.
	return (FBM_CEILING - FBM_MEAN) * NOISE_RELIEF_KM + DETAIL_MAX_M / 1000.0


# Did the hull touch ground anywhere along this frame's movement? Samples the
# SEGMENT, not its endpoints.
#
# A point test is not enough, and the failure is not theoretical: fly east along
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


# Nearest-texel albedo colour. Nearest is fine here: at these altitudes the map
# spans under two texels across the whole ring, so interpolating it buys nothing -
# that blur is a data limit, and slice A5 is what addresses it.
func albedo_color(dir: Vector3) -> Color:
	if _a_w <= 0:
		return Color(0.45, 0.40, 0.35)
	var uv := _dir_uv(dir)
	var x := clampi(int(fposmod(uv.x, 1.0) * float(_a_w)), 0, _a_w - 1)
	var y := clampi(int(clampf(uv.y, 0.0, 0.999) * float(_a_h)), 0, _a_h - 1)
	var i := (y * _a_w + x) * 3
	return Color(float(_a_bytes[i]) / 255.0, float(_a_bytes[i + 1]) / 255.0,
		float(_a_bytes[i + 2]) / 255.0)


# --- Surface colour ---
# The albedo map runs out of information long before the geometry does. Measured:
# Earth's 2048px albedo is 19.5 km per texel, so ring 0 at 6 km altitude spans
# 0.22 of a texel - the whole visible ground is ONE FLAT COLOUR, and no triangle
# count changes that. planet_cook.gdshader already blends a procedural
# height/slope palette for the globe past detail > 0.02; the tile sampled the
# albedo and stopped, so it was blurrier than the globe at the same altitude.
const MAP_FADE_TEXELS := 4.0
const PALETTE_GRASS := Color(0.16, 0.30, 0.09)
const PALETTE_ROCK := Color(0.40, 0.36, 0.32)
const PALETTE_DIRT := Color(0.38, 0.28, 0.16)
const PALETTE_ICE := Color(0.86, 0.89, 0.93)
const PALETTE_OCEAN := Color(0.06, 0.22, 0.32)


# Kilometres of ground per albedo texel on a body this size.
func km_per_texel(body_radius_km: float) -> float:
	return TAU * body_radius_km / 2048.0


# How much the MAP should lead, 0..1, from how many texels it still spans across
# the plate. A measurable quantity, not a taste knob: above four texels the map
# still carries real information; below it the map is a broad tint and the
# procedural palette has to carry the detail.
func map_weight(plate_km: float, body_radius_km: float) -> float:
	if _a_w <= 0:
		return 0.0
	return clampf(plate_km / km_per_texel(body_radius_km) / MAP_FADE_TEXELS, 0.0, 1.0)


# Ground colour. The map keeps the evidence - Mare Imbrium dark, the Sahara pale -
# and the palette supplies the detail the map has no resolution for.
func surface_color(dir: Vector3, plate_km: float, body_radius_km: float) -> Color:
	if is_water(dir):
		return PALETTE_OCEAN
	var h_m := height_m(dir)
	var span: float = maxf(max_height_km() * 1000.0, 1.0)
	var h01 := clampf(h_m / span, 0.0, 1.0)
	var slope := slope01(dir)
	var proc: Color = PALETTE_GRASS.lerp(PALETTE_DIRT, clampf(h01 * 2.2, 0.0, 1.0))
	proc = proc.lerp(PALETTE_ICE, smoothstep(0.45, 0.78, h01))
	proc = proc.lerp(PALETTE_ROCK, slope * 0.65)
	var w := map_weight(plate_km, body_radius_km)
	if w <= 0.0:
		return proc
	return proc.lerp(albedo_color(dir), w)


func report() -> Dictionary:
	return {
		"height_source": "map" if _has_map else "noise",
		"water_source": "mask" if _s_w > 0 else ("height" if _has_map else "noise"),
		"max_height_km": max_height_km(),
		"scale_m": DEM_SCALE_M,
		"seed": _seed,
	}


# Load a map as one byte per texel. FORMAT_R8 so the red channel - the only one
# height and water masks use - is contiguous and indexable without a stride.
func _load_gray(path: String) -> Dictionary:
	var img := _img_of(path)
	if img == null:
		return { "bytes": PackedByteArray(), "w": 0, "h": 0 }
	img.convert(Image.FORMAT_R8)
	return { "bytes": img.get_data(), "w": img.get_width(), "h": img.get_height() }


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
# it also keeps every 8-bit step (~36 m at this scale) as a visible terrace.
# Indexes raw bytes rather than calling Image.get_pixel - identical arithmetic,
# without ~20 Object calls per height_m(). tools/test_earth_terrain.gd's
# mesh_matches_the_height_function is what proves the results did not move.
func _bilinear_bytes(bytes: PackedByteArray, w: int, h: int, uv: Vector2) -> float:
	if w <= 0 or h <= 0:
		return 0.0
	var fx := fposmod(uv.x, 1.0) * float(w) - 0.5
	var fy := clampf(uv.y, 0.0, 1.0) * float(h) - 0.5
	var x0 := int(floor(fx))
	var y0 := int(floor(fy))
	var tx := fx - float(x0)
	var ty := fy - float(y0)
	var xa := posmod(x0, w)
	var xb := posmod(x0 + 1, w)
	var ra := clampi(y0, 0, h - 1) * w
	var rb := clampi(y0 + 1, 0, h - 1) * w
	var s00 := float(bytes[ra + xa])
	var s10 := float(bytes[ra + xb])
	var s01 := float(bytes[rb + xa])
	var s11 := float(bytes[rb + xb])
	return lerpf(lerpf(s00, s10, tx), lerpf(s01, s11, tx), ty) / 255.0
