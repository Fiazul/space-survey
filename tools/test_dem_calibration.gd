extends Node
# Acceptance gate for the Mars/Moon DEM ingest (docs/research/2026-09-09-dem-ingest.md):
# the packed RG16 PNGs survive Godot's res:// import unchanged, TerrainSampler's
# per-recipe calibration reproduces the documented sampled elevations, and the
# CPU decode agrees with the GPU decode it mirrors (planet_cook.gdshader's
# decode_height()). Scene-based (not --script) because it loads res:// textures.
# Run: godot --headless tools/test_dem_calibration.tscn

const G := preload("res://scripts/world/planet_generator.gd")
const TS := preload("res://scripts/world/terrain_sampler.gd")

var failures := 0


func _ready() -> void:
	_import_lossless()
	_calibration()
	_mirror_check()
	print("dem_calibration: ", "OK" if failures == 0 else "FAIL %d" % failures)
	get_tree().quit(0 if failures == 0 else 1)


# --- 1. Import lossless check ------------------------------------------------
# Ground truth read directly off the PNG bytes with PIL (Image.open(path).
# getpixel()), independent of Godot entirely. If Godot's res:// import path
# (CompressedTexture2D -> get_image()) quantised or VRAM-compressed the file,
# these exact byte pairs would not survive.
func _import_lossless() -> void:
	_check_bytes("res://assets/planets/mars_height_2k.png", [
		[Vector2i(0, 0), 53, 10],
		[Vector2i(1024, 512), 57, 58],
		[Vector2i(907, 290), 30, 218],
		[Vector2i(100, 987), 96, 125],
		[Vector2i(1500, 50), 32, 105],
	])
	_check_bytes("res://assets/planets/moon_height_2k.png", [
		[Vector2i(0, 0), 116, 7],
		[Vector2i(1024, 512), 106, 35],
		[Vector2i(907, 290), 83, 139],
		[Vector2i(100, 987), 78, 213],
		[Vector2i(1500, 50), 116, 172],
	])
	# 2026-09-09 4k/8k re-wiring: same check, the higher-resolution files these
	# recipes now actually point at. Bytes read independently with PIL
	# (Image.open(path).convert("RGB").getpixel()), not derived from Godot.
	_check_bytes("res://assets/planets/mars_height_4k.png", [
		[Vector2i(0, 0), 54, 99],
		[Vector2i(2048, 1024), 57, 195],
		[Vector2i(1814, 580), 32, 92],
		[Vector2i(200, 1974), 97, 74],
		[Vector2i(3000, 100), 34, 5],
	])
	_check_bytes("res://assets/planets/moon_height_4k.png", [
		[Vector2i(0, 0), 116, 151],
		[Vector2i(2048, 1024), 107, 231],
		[Vector2i(1814, 580), 85, 245],
		[Vector2i(200, 1974), 83, 215],
		[Vector2i(3000, 100), 117, 139],
	])
	_check_bytes("res://assets/planets/earth_height_8k.png", [
		[Vector2i(0, 0), 93, 29],
		[Vector2i(4096, 2048), 82, 143],
		[Vector2i(3628, 1160), 88, 0],
		[Vector2i(400, 3948), 154, 75],
		[Vector2i(6000, 200), 148, 17],
	])


func _check_bytes(path: String, points: Array) -> void:
	var tex := load(path) as Texture2D
	check(path + ":loads", tex != null)
	if tex == null:
		return
	var img := tex.get_image()
	check(path + ":not_null_image", img != null)
	if img == null:
		return
	if img.is_compressed():
		img.decompress()
	check(path + ":not_vram_compressed_after_decompress", not img.is_compressed())
	img.convert(Image.FORMAT_RGB8)
	for entry in points:
		var p: Vector2i = entry[0]
		var exp_r: int = entry[1]
		var exp_g: int = entry[2]
		var c := img.get_pixel(p.x, p.y)
		var r := int(round(c.r * 255.0))
		var g := int(round(c.g * 255.0))
		check("%s:(%d,%d)_R" % [path, p.x, p.y], r == exp_r)
		check("%s:(%d,%d)_G" % [path, p.x, p.y], g == exp_g)


# --- 2. Per-recipe calibration -----------------------------------------------
# 2026-09-09 4k/8k re-wiring: RECIPES now point Mars/Moon at the 16 ppd (4k)
# maps and Earth at the 8k rg16 ETOPO map - numbers below are the 4k/8k
# landmark samples from docs/research/2026-09-09-dem-ingest.md's "later" table
# and assets/planets/SOURCES.txt, not the earlier 2k/4ppd ones.
func _calibration() -> void:
	var mars := G.terrain_sampler(G.recipe_for({"name": "Mars"}))
	var olympus := _dir_of(18.65, 226.2)
	var hellas := _dir_of(-42.4, 70.5)
	var olympus_m: float = mars.height_m(olympus)
	var hellas_m: float = mars.height_m(hellas)
	# Olympus Mons: named-point sample isn't the dataset's own argmax pixel at
	# either resolution (docs/research/2026-09-09-dem-ingest.md, "later" section)
	# - 19963.5 m at 4k, not 21171 m (the file's true global max).
	check("mars_olympus_mons_sampled", absf(olympus_m - 19963.5) < 800.0)
	check("mars_hellas_floor_sampled", absf(hellas_m - (-6072.0)) < 800.0)
	check("mars_hellas_is_negative", hellas_m < 0.0)

	var moon := G.terrain_sampler(G.recipe_for({"name": "Moon"}))
	var selene_summit := _dir_of(5.4, 201.4)
	var summit_m: float = moon.height_m(selene_summit)
	check("moon_selenean_summit_sampled", absf(summit_m - 10622.0) < 500.0)

	# Earth: signed rg16 (real bathymetry), water-mask-gated clamp in
	# TerrainSampler.height_m() - see scripts/world/terrain_sampler.gd's
	# height_m(). Everest is the array's OWN global max at 8k (7198.3 m), not
	# the real ~8849 m summit: 4.89 km/px area-averages the peak down, this is
	# the map's own calibration anchor, not a bug (PLANET_GENERATOR.md).
	var earth := G.terrain_sampler(G.recipe_for({"name": "Earth"}))
	var everest := _dir_of(27.99, 86.93)
	var everest_m: float = earth.height_m(everest)
	check("earth_everest_sampled", absf(everest_m - 7198.3) < 300.0)

	# Dead Sea: masked LAND below sea level. The water mask must say "not
	# water" here, so height_m() must NOT clamp it to 0 - the whole point of
	# this test is proving the clamp is water-mask-gated, not a blanket
	# max(ground, 0.0) that would flatten every below-datum point on Earth.
	var dead_sea := _dir_of(31.5, 35.5)
	var dead_sea_m: float = earth.height_m(dead_sea)
	check("earth_dead_sea_is_land", not earth.is_water(dead_sea))
	check("earth_dead_sea_sampled", absf(dead_sea_m - (-427.0)) < 100.0)

	# Mid-Pacific and Mariana: both masked OCEAN, both must clamp to the
	# liquid datum (0 m) even though Mariana's real decoded depth is deeply
	# negative (bathymetry carried, just hidden under the water plate).
	var mid_pacific := _dir_of(0.0, -150.0)
	var mariana := _dir_of(11.35, 142.2)
	check("earth_mid_pacific_is_water", earth.is_water(mid_pacific))
	check("earth_mariana_is_water", earth.is_water(mariana))
	check("earth_mid_pacific_clamped", earth.height_m(mid_pacific) == 0.0)
	check("earth_mariana_clamped", earth.height_m(mariana) == 0.0)
	# Prove the clamp is real, not a no-op: the RAW decoded depth underneath
	# the clamp is genuinely negative (bathymetry is carried, not discarded).
	check("earth_mariana_raw_depth_is_negative", earth.base_height_m(mariana) < -1000.0)


# --- 3. CPU/GPU decode mirror check ------------------------------------------
# Reimplements the bilinear+decode INDEPENDENTLY of TerrainSampler's own
# _bilinear_bytes/_texel (fresh Image.get_pixel reads, not the cached byte
# arrays), and compares against TerrainSampler.raw_sample01() - the same 0..1
# value planet_cook.gdshader's sample_height()/decode_height() compute on the
# GPU. Touch one, touch both: if either decode's math drifts, this fails.
func _mirror_check() -> void:
	_mirror_one("Earth", true)   # rg16 since the 2026-09-09 8k re-wiring
	_mirror_one("Mars", true)
	_mirror_one("Moon", true)


func _mirror_one(name: String, rg16: bool) -> void:
	var recipe := G.recipe_for({"name": name})
	var sampler := G.terrain_sampler(recipe)
	var tex := load(str(recipe.height)) as Texture2D
	check(name + "_mirror:loads", tex != null)
	if tex == null:
		return
	var img := tex.get_image()
	if img.is_compressed():
		img.decompress()
	img.convert(Image.FORMAT_RGB8)
	for pt in [Vector2(10.0, 40.0), Vector2(-33.0, 150.0), Vector2(60.0, -70.0)]:
		var dir := _dir_of(pt.x, pt.y)
		var lon := atan2(dir.z, dir.x)
		var lat := asin(clampf(dir.y, -1.0, 1.0))
		var uv := Vector2(lon / TAU + 0.5, 0.5 - lat / PI)
		var independent := _independent_decode(img, rg16, uv)
		var mirrored: float = sampler.raw_sample01(dir)
		check("%s_mirror_%s" % [name, pt], absf(independent - mirrored) < 0.0005)


func _independent_decode(img: Image, rg16: bool, uv: Vector2) -> float:
	var w := img.get_width()
	var h := img.get_height()
	var fx := fposmod(uv.x, 1.0) * float(w) - 0.5
	var fy := clampf(uv.y, 0.0, 1.0) * float(h) - 0.5
	var x0 := int(floor(fx))
	var y0 := int(floor(fy))
	var tx := fx - float(x0)
	var ty := fy - float(y0)
	var xa := posmod(x0, w)
	var xb := posmod(x0 + 1, w)
	var ya := clampi(y0, 0, h - 1)
	var yb := clampi(y0 + 1, 0, h - 1)
	var s00 := _decode_pixel(img, xa, ya, rg16)
	var s10 := _decode_pixel(img, xb, ya, rg16)
	var s01 := _decode_pixel(img, xa, yb, rg16)
	var s11 := _decode_pixel(img, xb, yb, rg16)
	return lerpf(lerpf(s00, s10, tx), lerpf(s01, s11, tx), ty)


func _decode_pixel(img: Image, x: int, y: int, rg16: bool) -> float:
	var c := img.get_pixel(x, y)
	if rg16:
		# Same formula as planet_cook.gdshader's decode_height(): texel.r/.g are
		# already 0..1 (R/255, G/255); 65535/255 == 257 exactly.
		return (c.r * 256.0 + c.g) / 257.0
	return c.r


func _dir_of(lat_deg: float, lon_deg: float) -> Vector3:
	var lat := deg_to_rad(lat_deg)
	var lon := deg_to_rad(lon_deg)
	return Vector3(cos(lat) * cos(lon), sin(lat), cos(lat) * sin(lon)).normalized()


func check(label: String, ok: bool) -> void:
	if not ok:
		failures += 1
		push_error("dem_calibration: " + label)
