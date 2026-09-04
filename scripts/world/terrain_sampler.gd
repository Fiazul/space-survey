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

# Procedural detail added on top of the DEM. Amplitude scales with the DEM's
# local slope: a 7.42 km texel cannot express a ridge, so flat sea floor stays
# flat while mountains get rugged. This is what makes 50 m triangles worth
# building instead of just interpolating between texels.
const DETAIL_FREQ := 900.0         # cycles across the body; ~44 km wavelength on Earth
const DETAIL_MAX_M := 420.0        # amplitude at full slope
const NOISE_WORLD_SLOPE := 0.35    # a noise world is already rugged at every scale

var _himg: Image                   # height map, or null -> noise
var _simg: Image                   # water mask, or null
var _aimg: Image                   # albedo, for the map half of surface_color
var _seed := 0.0                   # the SAME seed the cook material got
var _land := 1.0                   # recipe land_amount, the water cut with no mask
var _has_map := false


func _init(recipe: Dictionary) -> void:
	_himg = _img_of(str(recipe.get("height", "")))
	_simg = _img_of(str(recipe.get("specular", "")))
	_aimg = _img_of(str(recipe.get("albedo", "")))
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
		return 0.0                 # ocean floor is not modelled; sea level is the floor
	return base + _detail_m(dir, base)


# The map/noise value with NO procedural detail on top. Exists so the detail pass
# is separately testable: without this seam an assertion about "detail varies the
# ground" passes on bilinear interpolation of the DEM alone, which is what it did
# on the first draft of tools/test_earth_terrain.gd.
func base_height_m(dir: Vector3) -> float:
	var base: float
	if _has_map:
		base = (_bilinear(_himg, _dir_uv(dir)) - DEM_SEA_LEVEL) * DEM_SCALE_M
	else:
		base = PlanetGenerator.crust_height(dir, _seed) * NOISE_RELIEF_KM * 1000.0
	return maxf(base, 0.0) if not DEM_HAS_BATHYMETRY else base


# Ruggedness between DEM samples, scaled by how steep the DEM already is here.
func _detail_m(dir: Vector3, base_m: float) -> float:
	# Water flatness has THREE independent guards, and mutation testing showed the
	# load-bearing one is not either of the explicit checks: over open ocean the DEM
	# is flat, so slope01() is exactly 0 and the amplitude below vanishes on its own.
	# Removing this line AND height_m's `base <= 0.0` early return still leaves the
	# Pacific flat; only forcing slope01() to a constant wrinkles it. Keep all three
	# anyway - the early returns are cheap and they are what will matter the day
	# DEM_HAS_BATHYMETRY becomes true and `base` can legitimately go negative.
	if base_m < 1.0:
		return 0.0                 # keep water flat
	var slope := slope01(dir)
	var n: float = PlanetGenerator.fbm3(dir * DETAIL_FREQ + Vector3(_seed, _seed, _seed))
	return (n - 0.5) * 2.0 * DETAIL_MAX_M * slope


# 0..1 steepness from the DEM's own neighbourhood. Public because surface_color()
# needs it too — do NOT reimplement slope anywhere else.
func slope01(dir: Vector3) -> float:
	if not _has_map:
		return NOISE_WORLD_SLOPE
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
# be an UPPER BOUND and not an average — enter the band below the terrain and you
# arrive inside a mountain.
func max_height_km() -> float:
	if _has_map:
		return (DEM_MAX_VALUE * DEM_SCALE_M + DETAIL_MAX_M) / 1000.0
	return NOISE_RELIEF_KM * FBM_CEILING


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


func report() -> Dictionary:
	return {
		"height_source": "map" if _has_map else "noise",
		"water_source": "mask" if _simg != null else ("height" if _has_map else "noise"),
		"max_height_km": max_height_km(),
		"scale_m": DEM_SCALE_M,
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
# it also keeps every 8-bit step (~36 m at this scale) as a visible terrace.
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
