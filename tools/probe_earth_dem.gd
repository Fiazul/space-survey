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
	{"name": "Everest", "lat": 27.9881, "lon": 86.9250, "m": 8848.0},
	{"name": "Aconcagua", "lat": -32.6532, "lon": -70.0109, "m": 6961.0},
	{"name": "Denali", "lat": 63.0695, "lon": -151.0074, "m": 6190.0},
	{"name": "Kilimanjaro", "lat": -3.0674, "lon": 37.3556, "m": 5895.0},
	{"name": "Dead Sea", "lat": 31.5590, "lon": 35.4732, "m": -430.0},
	{"name": "Sahara (flat)", "lat": 23.4162, "lon": 25.6628, "m": 400.0},
	{"name": "Amazon (low)", "lat": -3.4653, "lon": -62.2159, "m": 50.0},
	{"name": "mid-Pacific", "lat": 0.0, "lon": -150.0, "m": 0.0},
	{"name": "mid-Atlantic", "lat": 0.0, "lon": -25.0, "m": 0.0},
	{"name": "Mariana Trench", "lat": 11.3493, "lon": 142.1996, "m": -10994.0},
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
	print("probe_earth_dem: global max %.4f" % hi)

	# What the scale would be under each candidate sea-level reading, so the choice
	# is made from numbers instead of a guess.
	var pac := _bilinear(img, _uv_of(0.0, -150.0))
	var atl := _bilinear(img, _uv_of(0.0, -25.0))
	var sea: float = (pac + atl) * 0.5
	print("probe_earth_dem: mid-ocean mean %.4f -> DEM_SCALE_M would be %.1f m per unit"
		% [sea, 8848.0 / maxf(everest_v - sea, 0.0001)])
	print("probe_earth_dem: cross-check with that scale:")
	for p in PLACES:
		var v := _bilinear(img, _uv_of(float(p.lat), float(p.lon)))
		var got: float = (v - sea) * (8848.0 / maxf(everest_v - sea, 0.0001))
		var real := float(p.m)
		var err := "  n/a" if absf(real) < 1.0 else "%+6.0f%%" % ((got - real) / absf(real) * 100.0)
		print("   %-16s real %8.1f m   computed %8.1f m   %s" % [str(p.name), real, got, err])
	print("probe_earth_dem: done — see the plan's Task 1 Step 3 for how to read this")
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
