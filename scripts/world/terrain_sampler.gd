class_name TerrainSampler
extends RefCounted
const SurfaceRecipe := preload("res://scripts/world/surface_recipe.gd")
var surface: Dictionary
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

# --- Per-recipe DEM calibration ---
# The five constants above are EARTH's numbers, kept as the fallback default so
# Earth's own behaviour never moves. Mars/Moon carry real per-body calibration
# (docs/research/2026-09-09-dem-ingest.md, assets/planets/SOURCES.txt) on their
# own RECIPES entry instead of a second set of hardcoded constants here — see
# CLAUDE.md's "never hardcode if body_name == X" rule. All four fields describe
# the DECODED sample value space (0..1, same space _bilinear_bytes already
# returns), not raw digital numbers:
#   height_datum        sample value at 0 m
#   height_m_per_unit    metres per unit of sample value (the whole 0..1 span)
#   height_max           highest sample value the file can produce (upper bound
#                         for max_height_km(), not necessarily reached)
#   height_signed        true when a sample below datum is a real depth
#                         (Mars/Moon basins); false when negative is clamped to
#                         0 because the map does not model an ocean floor
#                         (Earth — DEM_HAS_BATHYMETRY's old name/meaning)
var _dem_datum := DEM_SEA_LEVEL
var _dem_m_per_unit := DEM_SCALE_M
var _dem_max := DEM_MAX_VALUE
var _dem_signed := DEM_HAS_BATHYMETRY
# RG16 byte-pack (R*256+G)/65535 vs plain R8 value/255 — see _load_gray/_texel.
var _h_stride := 1

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
# Octave 0's own wavelength, MEASURED (see the comment above DETAIL_FREQ: 11000
# gives 3643/1760/850/411 m across the four octaves; each further octave is
# /2.07 of the one before, matching ridged3()'s own q *= 2.07 per step). Used to
# band-limit each octave against the local mesh sample spacing - see
# SurfaceRecipe._band_weight for why an unlimited high-frequency octave reads as
# a different texture on either side of a ring boundary (reported at moon_7km).
const DETAIL_BASE_KM := 3.643
# MEASURED (tools/probe_amplitude.gd, see PLANET_GENERATOR.md): over a 3x3 km
# Moon patch, generic detail's mean |offset| is 19.3 m (range -30.8..+48.8 m) -
# the SAME order of magnitude as the geology pass's own craters (mean |offset|
# 21.2 m), even though detail's wavelength (411 m - 3.6 km) is several times a
# small crater's diameter (45-90 m, cell 0.15 km). Two independent noise fields
# of comparable amplitude sum into whichever one is least structured winning
# visually - reported as "rolling hills + primitive rocks, zero bowls" at
# moon_200m even with 1562 craters actually present in the height field over
# three 160x160 km patches (test_surface_recipes.gd's own crater-encounter
# count). Detail is generic roughness filler for wherever there is nothing more
# specific to show; a world whose geology pass already draws named craters
# should not have them buried under it, so detail is turned down (not off -
# still real roughness between craters) wherever craters exist at all.
const DETAIL_GEOLOGY_DAMPEN := 0.2

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
var _crust_color := Color(0.5, 0.5, 0.5)
var _ocean_color := Color(0.5, 0.5, 0.5)


func _init(recipe: Dictionary) -> void:
	surface = SurfaceRecipe.resolve(recipe)
	_h_stride = 2 if str(recipe.get("height_encoding", "r8")) == "rg16" else 1
	var hm := _load_gray(str(recipe.get("height", "")), _h_stride)
	_h_bytes = hm.bytes
	_h_w = hm.w
	_h_h = hm.h
	_dem_datum = float(recipe.get("height_datum", DEM_SEA_LEVEL))
	_dem_m_per_unit = float(recipe.get("height_m_per_unit", DEM_SCALE_M))
	_dem_max = float(recipe.get("height_max", DEM_MAX_VALUE))
	_dem_signed = bool(recipe.get("height_signed", DEM_HAS_BATHYMETRY))
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
	_crust_color = recipe.get("color_a", Color(0.5, 0.5, 0.5))
	_ocean_color = recipe.get("color_ocean", PlanetGenerator.DEFAULT_COLOR_OCEAN)
	_has_map = _h_w > 0


# Metres above sea level at a point on the crust. `dir` is an outward unit vector
# in MODEL space — the same vector the cook shader calls `n`.
func height_m(dir: Vector3, detail_km: float = 0.0) -> float:
	var base := base_height_m(dir)
	if _has_map and base <= 0.0 and not _dem_signed:
		return 0.0                 # ocean floor is not modelled; sea level is the floor
	var ground := base + _detail_m(dir, base, detail_km) + geology_height_m(dir, detail_km)
	if _has_map and _dem_signed and float(surface.liquid_amount) > 0.0 and is_water(dir):
		# Bathymetry-carrying map (Earth): the real seafloor depth is decoded
		# (base_height_m/slope01/etc. all see it), but the water plate sits at
		# the liquid datum (0 m) - clamp ONLY where the mask says ocean, so
		# masked land below sea level (Dead Sea) keeps its real negative depth.
		# Recipe-driven via liquid_amount + the existing water mask, never an
		# `if body_name == "Earth"` branch.
		ground = maxf(ground, 0.0)
	if not _has_map and float(surface.liquid_amount) > 0.0:
		# Procedural seas need a level datum too, not water painted up hillsides.
		var dry := 1.0 - water01(dir)
		return maxf(ground, 0.0) * smoothstep(0.05, 0.75, dry)
	return ground


# `detail_km` is the LOCAL sample spacing at this point (0.0 = full detail,
# every caller except SurfacePatch's mesh builder). See SurfaceRecipe._band_weight.
func geology_height_m(dir: Vector3, detail_km: float = 0.0) -> float:
	return SurfaceRecipe.height_offset_m(dir, surface, detail_km)


func lava01(dir: Vector3) -> float:
	return SurfaceRecipe.lava_mask(dir, surface)


# The map/noise value with NO procedural detail on top. Exists so the detail pass
# is separately testable: without this seam an assertion about "detail varies the
# ground" passes on bilinear interpolation of the DEM alone, which is what it did
# on the first draft of tools/test_earth_terrain.gd.
# TEST HOOK. The bilinear-decoded 0..1 sample with no elevation scale applied
# yet - exactly what planet_cook.gdshader's sample_height()/decode_height()
# compute on the GPU. tools/test_dem_calibration.gd's mirror check calls this
# to prove the CPU and GPU decodes agree; no other caller needs it (every real
# consumer wants metres, i.e. base_height_m()).
func raw_sample01(dir: Vector3) -> float:
	if not _has_map:
		return 0.0
	return _bilinear_bytes(_h_bytes, _h_w, _h_h, _dir_uv(dir), _h_stride)


func base_height_m(dir: Vector3) -> float:
	if _has_map:
		var mapped := (_bilinear_bytes(_h_bytes, _h_w, _h_h, _dir_uv(dir), _h_stride) - _dem_datum) \
			* _dem_m_per_unit
		return maxf(mapped, 0.0) if not _dem_signed else mapped
	# CENTRED on the datum, and deliberately NOT clamped: negative is a basin, not
	# an ocean. An airless world has no sea level, and clamping here would flatten
	# half the Moon into a plate sitting exactly on the sphere.
	return (PlanetGenerator.crust_height(dir, _seed) - FBM_MEAN) * NOISE_RELIEF_KM * 1000.0


# Ruggedness between DEM samples, scaled by how steep the DEM already is here.
func _detail_m(dir: Vector3, base_m: float, detail_km: float = 0.0) -> float:
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
	# Reimplements PlanetGenerator.ridged3's own loop (q *= 2.07, a *= 0.5 per
	# octave) rather than calling it, so each octave can be band-limited against
	# `detail_km` individually - ridged3() itself is shared with no other caller
	# that would need this. An octave whose wavelength (cell_km) cannot span the
	# local mesh sample spacing is dropped from BOTH the sum and its normalizer,
	# so the remaining octaves keep their existing relative weight instead of the
	# whole result dimming as octaves cut out (mirrors SurfaceRecipe's crater
	# octaves, which are additive and need no such renormalization).
	var q := dir * DETAIL_FREQ + Vector3(_seed, _seed, _seed)
	var a := 0.5
	var s := 0.0
	var norm := 0.0
	var cell_km := DETAIL_BASE_KM
	for _i in DETAIL_OCTAVES:
		var w := SurfaceRecipe._band_weight(cell_km, detail_km)
		if w > 0.0:
			var oct_n: float = PlanetGenerator._noise3(q)
			s += a * (1.0 - absf(2.0 * oct_n - 1.0)) * w
			norm += a * w
		q *= 2.07
		a *= 0.5
		cell_km /= 2.07
	var n := s / maxf(norm, 0.0001)
	# Ridged noise is 0..1 with its mass toward 1, so centre it before scaling or
	# it becomes a uniform lift rather than relief.
	var dampen: float = DETAIL_GEOLOGY_DAMPEN if float(surface.crater_density) > 0.0 else 1.0
	return (n - 0.5) * 2.0 * DETAIL_MAX_M * slope * dampen


# 0..1 steepness from the DEM's own neighbourhood. Public because surface_color()
# needs it too — do NOT reimplement slope anywhere else.
func slope01(dir: Vector3) -> float:
	if not _has_map:
		return NOISE_WORLD_SLOPE
	var uv := _dir_uv(dir)
	var e := 1.0 / float(_h_w)
	var dx := _bilinear_bytes(_h_bytes, _h_w, _h_h, uv + Vector2(e, 0.0), _h_stride) \
		- _bilinear_bytes(_h_bytes, _h_w, _h_h, uv - Vector2(e, 0.0), _h_stride)
	var dy := _bilinear_bytes(_h_bytes, _h_w, _h_h, uv + Vector2(0.0, e), _h_stride) \
		- _bilinear_bytes(_h_bytes, _h_w, _h_h, uv - Vector2(0.0, e), _h_stride)
	return clampf(sqrt(dx * dx + dy * dy) * 22.0, 0.0, 1.0)


# Distance from the body's centre to the ground at `dir`, in km.
func ground_radius_km(dir: Vector3, body_radius_km: float, detail_km: float = 0.0) -> float:
	return body_radius_km + height_m(dir, detail_km) / 1000.0


# Height of `pos` above the ground DIRECTLY BELOW IT, in km. Measuring from the
# sphere instead would report ~10.8 km while you sit 2 km over Everest's summit.
func alt_above_ground_km(pos: Vector3, body_radius_km: float) -> float:
	var d := pos.length()
	if d < 0.0001:
		return -body_radius_km
	return d - ground_radius_km(pos / d, body_radius_km)


# Sea level is sea level. A mask texel is 19.5 km across on Earth, so bilinear
# interpolation of it smears the coastline across whole mountain ranges - and the
# result was dark water quads lying on the Himalaya at 7626 m, in regular grid
# rows, which is what was reported as "cubes and boxes" on the ground.
const SEA_LEVEL_TOL_M := 40.0


# CONTINUOUS wetness, 0..1. The boolean below is for decisions (props, kill);
# this is for LOOK, and the difference matters: classifying whole quads as land
# or water and sending them to two different meshes drew every coastline at quad
# resolution - 1.5 km quads on ring 2, 6.1 km on ring 3 - as hard-edged angular
# polygons. Water is a material property of the surface, not separate geometry.
func water01(dir: Vector3) -> float:
	if float(surface.liquid_amount) <= 0.0:
		return 0.0
	if _land >= 1.0 and _s_w == 0:
		return 0.0
	if _s_w > 0:
		var mask := _bilinear_bytes(_s_bytes, _s_w, _s_h, _dir_uv(dir))
		# Elevation still has a veto: the mask is 19.5 km per texel, so its
		# interpolation reaches over mountains.
		var fade: float = 1.0 - smoothstep(SEA_LEVEL_TOL_M, SEA_LEVEL_TOL_M * 8.0,
			base_height_m(dir))
		var wet := clampf(smoothstep(0.35, 0.65, mask) * fade, 0.0, 1.0)
		return wet * (1.0 - ice01(dir))
	if _has_map:
		return 1.0 - smoothstep(0.0, SEA_LEVEL_TOL_M, height_m(dir))
	var edge := 1.0 - _land
	var h: float = PlanetGenerator.fbm3(dir * 2.1 + Vector3(_seed, _seed, _seed))
	return clampf(1.0 - smoothstep(edge - 0.05, edge + 0.05, h), 0.0, 1.0)


# NASA's water mask marks permanent/sea ice as water (spec=255) even though it
# reflects like snow, not ocean — measured on earth_spec_2k.png / earth_2k.jpg:
# open ocean albedo is (30,59,117), luma 0.223; Ross Ice Shelf and Arctic sea ice
# sample mask=water at luma 0.56-0.85. 0.45 sits with margin above the former and
# below the latter (tools/probe run against the real PNGs, not guessed). Mirrored
# in terrain_tile.gdshader as ICE_ALBEDO_LUM_MIN, converted for its linear-space
# texture sample.
const ICE_ALBEDO_LUM_MIN := 0.45


# 0..1: does the mask say water here while the albedo reads bright like ice? Only
# meaningful where a mask AND an albedo map both exist (noise/no-map worlds have no
# per-texel ice case, they classify water from geometry alone).
func ice01(dir: Vector3) -> float:
	if _s_w <= 0 or _a_w <= 0:
		return 0.0
	if _bilinear_bytes(_s_bytes, _s_w, _s_h, _dir_uv(dir)) <= 0.5:
		return 0.0
	var c := albedo_color(dir)
	var lum := c.r * 0.299 + c.g * 0.587 + c.b * 0.114
	return smoothstep(ICE_ALBEDO_LUM_MIN, ICE_ALBEDO_LUM_MIN + 0.15, lum)


func is_water(dir: Vector3) -> bool:
	if float(surface.liquid_amount) <= 0.0:
		return false
	if _land >= 1.0 and _s_w == 0:
		return false
	if _s_w > 0:
		if _bilinear_bytes(_s_bytes, _s_w, _s_h, _dir_uv(dir)) <= 0.5:
			return false
		if ice01(dir) > 0.5:
			return false
		# The mask says water; the ELEVATION has to agree. Ocean cannot be 7 km up.
		return base_height_m(dir) <= SEA_LEVEL_TOL_M
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
	var geology_bound := SurfaceRecipe.max_offset_m(surface) / 1000.0
	if _has_map:
		var top_m := (_dem_max - _dem_datum) * _dem_m_per_unit
		return (top_m + DETAIL_MAX_M) / 1000.0 + geology_bound
	# Centred, so the peak ABOVE the datum is only the half-range.
	return (FBM_CEILING - FBM_MEAN) * NOISE_RELIEF_KM + DETAIL_MAX_M / 1000.0 + geology_bound


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
	if alt_above_ground_km(to, body_radius_km) <= contact_km or alt_above_ground_km(from, body_radius_km) <= contact_km:
		return true
	var travel := from.distance_to(to)
	if travel < 0.0001:
		return false
	# One sample per ~50 m of travel (a ring-0 quad), capped so a teleport cannot
	# stall the frame. 64 samples covers ~3.2 km of travel; there is no speed cap to
	# guarantee that's enough (removed 2026-09-08, docs/ROADMAP.md "L.3") — at
	# AIR_TERMINAL_KMS (12 km/s) a single 60 fps frame covers ~200 km, well past this
	# sweep's 3.2 km reach, so a hull moving that fast between two clear samples can
	# still tunnel through terrain between them. Declared, accepted known limitation,
	# not something this function's algorithm fixes — see flight_mode.gd's own note on
	# the anti-tunnelling gap.
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


# Kilometres of ground per albedo texel on a body this size.
func km_per_texel(body_radius_km: float) -> float:
	return TAU * body_radius_km / maxf(float(_a_w), 1.0)


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
# The PALETTE alone - no map, no ocean. Both of those are sampled per fragment in
# shaders/terrain_tile.gdshader, because at ring 3's 10.24 km vertex spacing a
# map-derived colour becomes an angular polygon.
func land_color(dir: Vector3, _body_radius_km: float) -> Color:
	# Airless/rocky worlds must not inherit Earth's grass and snow palette.
	# Mapped geography also remains the broad tint when flying below one texel.
	if _a_w > 0:
		return albedo_color(dir)
	if _land >= 1.0:
		return _crust_color.darkened(slope01(dir) * 0.25)
	var h_m := height_m(dir)
	var span: float = maxf(max_height_km() * 1000.0, 1.0)
	var h01 := clampf(h_m / span, 0.0, 1.0)
	var slope := slope01(dir)
	var proc: Color = PALETTE_GRASS.lerp(PALETTE_DIRT, clampf(h01 * 2.2, 0.0, 1.0))
	proc = proc.lerp(PALETTE_ICE, smoothstep(0.45, 0.78, h01))
	return proc.lerp(PALETTE_ROCK, slope * 0.65)


# UNREACHABLE as of 2026-09-09 (grepped: no caller anywhere in scripts/ or
# tools/) — surface_patch._color_at() bakes vertex COLOR from land_color()
# ALONE and leaves the ocean blend entirely to terrain_tile.gdshader's own
# fragment-side `wet` mix (see that function's comment: baking ocean in here
# would quantise the shoreline to the vertex spacing). This function's
# ocean-ward lerp is still routed through the recipe's real _ocean_color
# rather than a hardcoded palette colour, for whichever future caller re-wires
# it — it does not affect the globe/ring colour parity bug, which is fixed in
# terrain_tile.gdshader's fragment() (ocean_base_color()) instead.
func surface_color(dir: Vector3, plate_km: float, body_radius_km: float) -> Color:
	var proc := land_color(dir, body_radius_km)
	var w := map_weight(plate_km, body_radius_km)
	if w > 0.0:
		proc = proc.lerp(albedo_color(dir), w)
	return proc.lerp(_ocean_color, water01(dir))


func report() -> Dictionary:
	return {
		"height_source": "map" if _has_map else "noise",
		"water_source": "mask" if _s_w > 0 else ("height" if _has_map else "noise"),
		"max_height_km": max_height_km(),
		"scale_m": _dem_m_per_unit,
		"seed": _seed,
	}


# Load a map as `stride` bytes per texel. stride=1: FORMAT_R8, the red channel
# - the only one water masks and Earth's height map use - contiguous and
# indexable without a stride. stride=2: an RG16 byte-pack (value = R*256+G,
# measured in tools/probe_dem16.gd - Godot flattens a real 16-bit grayscale PNG
# to 8-bit on load, so Mars/Moon's height maps are stored as ordinary RGB8 with
# R=high byte, G=low byte, B unused instead). Interleaved R,G per texel so
# _texel() can decode without a second array lookup.
func _load_gray(path: String, stride: int = 1) -> Dictionary:
	var img := _img_of(path)
	if img == null:
		return { "bytes": PackedByteArray(), "w": 0, "h": 0 }
	if stride == 2:
		img.convert(Image.FORMAT_RGB8)
		var src := img.get_data()
		var w := img.get_width()
		var h := img.get_height()
		var out := PackedByteArray()
		out.resize(w * h * 2)
		for i in w * h:
			out[i * 2] = src[i * 3]
			out[i * 2 + 1] = src[i * 3 + 1]
		return { "bytes": out, "w": w, "h": h }
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
func _bilinear_bytes(bytes: PackedByteArray, w: int, h: int, uv: Vector2, stride: int = 1) -> float:
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
	var s00 := _texel(bytes, (ra + xa) * stride, stride)
	var s10 := _texel(bytes, (ra + xb) * stride, stride)
	var s01 := _texel(bytes, (rb + xa) * stride, stride)
	var s11 := _texel(bytes, (rb + xb) * stride, stride)
	return lerpf(lerpf(s00, s10, tx), lerpf(s01, s11, tx), ty)


# Decode one texel to 0..1, DECODED before the bilinear lerp above runs (linear
# interpolation of the decoded value is identical to interpolating raw bytes
# then decoding, since both are affine - but decoding first is what stride=2's
# two-byte value needs, since a byte-wise lerp of R and G separately would not
# reconstruct R*256+G at all). Mirrors planet_cook.gdshader's height_rg16
# uniform branch in sample_height() - touch one, touch both.
func _texel(bytes: PackedByteArray, i: int, stride: int) -> float:
	if stride == 2:
		return float(int(bytes[i]) * 256 + int(bytes[i + 1])) / 65535.0
	return float(bytes[i]) / 255.0
