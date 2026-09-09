extends RefCounted
## Geological profiles are shared by geometry, collision and material binding.
## Landmarks below are seeded scenery, not claims about surveyed feature locations.

const WORLD_DEFAULTS := {
	"Earth": {"liquid_amount": 1.0, "crater_count": 0, "mountain_m": 0.0, "volcano_count": 3, "volcano_m": 240.0, "crater_density": 0.0, "hills_m": 0.0},
	"Moon": {"crater_count": 28, "crater_m": 700.0, "mountain_m": 0.0, "crater_density": 0.12, "crater_scale_km": 30.0, "hills_m": 100.0},
	"Mercury": {"crater_count": 32, "crater_m": 450.0, "crater_density": 0.15, "crater_scale_km": 30.0, "hills_m": 90.0},
	"Callisto": {"crater_count": 30, "crater_m": 500.0, "mountain_m": 0.0, "crater_density": 0.15, "crater_scale_km": 30.0, "hills_m": 90.0},
	"Mars": {"crater_count": 12, "crater_m": 260.0, "mountain_m": 600.0, "volcano_count": 5, "volcano_m": 2400.0, "crater_density": 0.08, "crater_scale_km": 20.0, "hills_m": 90.0},
	"Venus": {"crater_count": 3, "volcano_count": 12, "volcano_m": 1500.0, "mountain_m": 500.0, "crater_density": 0.03, "crater_scale_km": 25.0, "hills_m": 120.0},
	"Io": {"crater_count": 0, "volcano_count": 18, "volcano_m": 1800.0, "lava_amount": 1.0, "mountain_m": 240.0, "crater_density": 0.0, "hills_m": 0.0},
	"Europa": {"ice_surface": 1.0, "crater_count": 3, "crater_m": 100.0, "mountain_m": 80.0, "crater_density": 0.03, "crater_scale_km": 15.0, "hills_m": 70.0},
	"Enceladus": {"ice_surface": 1.0, "crater_count": 5, "crater_m": 100.0, "mountain_m": 100.0, "crater_density": 0.05, "crater_scale_km": 15.0, "hills_m": 70.0},
	"Titan": {"ice_surface": 0.15, "liquid_amount": 1.0, "mountain_m": 220.0, "crater_count": 2, "crater_density": 0.0, "hills_m": 150.0},
}

# Multi-scale crater fields are calibrated against a Moon-sized (~1737 km radius)
# reference circumference. This module never sees a body's true km radius (that
# arrives per-call as an argument elsewhere), so the km figures in crater_scale_km
# and HILLS_WAVELENGTH_KM are approximate on bodies of very different size, same
# spirit as the existing landmark angular widths.
const REF_CIRCUMFERENCE_KM := 10921.0
# MEASURED, not derived from REF_CIRCUMFERENCE_KM: cellular (Worley) noise's
# "frequency" does not set feature wavelength the way a periodic/fbm noise's
# does (REF_CIRCUMFERENCE_KM/freq, used above for ridge/hills, does NOT apply
# here). Counted actual cells in a 100x100 km patch at freq 100/200/364 ->
# 59/206/641 cells -> avg diameter 14.69/7.86/4.46 km -> diam_km*freq is a
# near-constant ~1550 across all three. Using the wrong constant here first
# put craters ~7x smaller than intended and spiked test_earth_terrain's grade
# to 87 deg (a 30 km-nominal crater was actually ~4.5 km wide, so its rim/wall
# fell entirely inside one 40 m ring-0 quad).
const CELLULAR_CAL_KM := 1550.0
# 30 / 5 / 0.8 / 0.15 km at crater_scale_km=30 - the 4th octave is what gives
# small craters underfoot at low altitude, the others read at 1-20 km.
const CRATER_OCTAVE_RATIOS := [1.0, 1.0 / 6.0, 1.0 / 37.5, 1.0 / 200.0]
const CRATER_SIZE_MIN_FRAC := 0.3  # smallest crater in a cell vs. the largest
# A cellular field gives one nearest-point read per direction: the Voronoi
# boundary IS the edge of "this cell's" data, so a crater whose radius reaches
# all the way to that boundary has nowhere left to put an ejecta apron before
# the read flips to an unrelated neighbour cell (measured: an 0.3..1.0 size
# range spiked test_earth_terrain's grade to 87 deg and broke the mesh/height
# agreement check outright). Capping the top of the range below 1.0 leaves
# real margin for the apron to decay before that flip.
const CRATER_SIZE_MAX_FRAC := 0.6
const CRATER_RIM_RATIO := 0.04     # rim height / diameter
const CRATER_WALL_ANGLE_DEG := 30.0
# `hash01 >= density` used to be a hard branch: a full crater on one side of
# the threshold, exactly zero on the other, with nothing between - measured a
# 22 m step over a 17 m horizontal sample, a near-vertical wall following
# whatever contour of the id-noise field happens to cross `density` (reported
# as a straight-edged seam at moon_7km, unrelated to any ring boundary). Fade
# across a band approaching the threshold instead, so the last cell before
# the cutoff tapers out rather than snapping.
const CRATER_DENSITY_FADE := 0.04
# --- Exposure ---
# A flat per-body albedo gain (see PLANET_GENERATOR.md "Exposure"). Never a
# name check: the default falls straight out of the recipe's own `color_a`
# luminance, a solid/dry body only (star/gas stay at 1.0 - nothing to expose).
# `SurfacePatch.bind_recipe` refines this default once a real TerrainSampler
# exists, by measuring the SAME land_color() the mesh vertices actually paint
# with - this cheap colour-only figure is what a sampler-less caller (the
# globe's own material build, `PlanetGenerator._cook_material`) would see.
const EXPOSURE_TARGET_LUM := 0.35
const EXPOSURE_GAIN_MAX := 3.5

static func _luminance(c: Color) -> float:
	var lin := c.srgb_to_linear()
	return lin.r * 0.299 + lin.g * 0.587 + lin.b * 0.114

const HILLS_WAVELENGTH_KM := 10.0  # base of the 2-20 km mid-scale relief band
# ridge_noise's own nominal wavelength (frequency=160 below), same
# REF_CIRCUMFERENCE_KM/freq relationship HILLS_WAVELENGTH_KM's own frequency
# uses - ~68.3 km, "70 km" in prose.
const MOUNTAIN_RIDGE_WAVELENGTH_KM := REF_CIRCUMFERENCE_KM / 160.0

# Below-DEM-texel band limit for the geology pass (craters/hills/mountains),
# distinct from _band_weight's mesh-resolution limit above: a mapped body's
# real topography already owns any wavelength AT OR ABOVE its DEM texel, so
# procedural geology at that scale would either duplicate or fight the real
# data. Weight is 1 well below the texel (legitimate fill-in detail the DEM
# cannot show) and fades to 0 approaching it - a smoothstep, not a hard cut,
# per the same reasoning _band_weight already documents. `texel_km <= 0.0`
# means the recipe carries no DEM-texel figure (no height map, or a mapped
# body like Earth that hasn't opted in) - full weight, i.e. no-op.
static func _below_texel_weight(cell_km: float, texel_km: float) -> float:
	if texel_km <= 0.0:
		return 1.0
	return 1.0 - smoothstep(0.5, 1.0, cell_km / texel_km)

# Band-limit weight, shared by every octave family below (crater octaves, hills).
# `detail_km` is the LOCAL sample spacing at the point being evaluated (a mesh
# vertex's neighbour distance, not the ring's own quad size - see
# SurfacePatch._compute_ring), 0.0 meaning "full detail, no band limit" for every
# caller that never measured one (contact kill, props, tests). A feature whose
# own cell/wavelength spans fewer than ~1.5 samples at this spacing cannot be
# resolved by the mesh at all; between 1.5 and 4 samples it fades in. Below the
# limit, two rings sampling the SAME continuous noise field at wildly different
# rates (a ring boundary is a 4x jump in quad size) each alias it to a
# DIFFERENT-looking result, which read as a straight texture-change band running
# along every ring boundary (reported at moon_7km). Cutting the octave instead of
# aliasing it removes the seam; the octave still runs at full strength once the
# mesh is fine enough to show it.
const DETAIL_LIMIT_SAMPLES_MIN := 1.5
const DETAIL_LIMIT_SAMPLES_MAX := 4.0


static func _band_weight(cell_km: float, detail_km: float) -> float:
	if detail_km <= 0.0:
		return 1.0
	return smoothstep(DETAIL_LIMIT_SAMPLES_MIN, DETAIL_LIMIT_SAMPLES_MAX, cell_km / detail_km)

# Real d/D: ~0.2 for simple (<15 km) craters, tapering to ~0.06 for complex
# (>=100 km) ones. Depth is nearly free against the band ceiling (it is BELOW
# the datum); this is what the ceiling math in max_offset_m does not have to
# pay for.
static func _crater_depth_ratio(d_km: float) -> float:
	if d_km <= 15.0:
		return 0.2
	if d_km >= 100.0:
		return 0.06
	return lerp(0.2, 0.06, (d_km - 15.0) / 85.0)

static func resolve(recipe: Dictionary) -> Dictionary:
	var kind := str(recipe.get("kind", "rocky"))
	var name := str(recipe.get("name", ""))
	var solid := kind != "star" and kind != "gas"
	var p := {
		"solid": solid, "seed": float(recipe.get("seed", 0.0)),
		"rock_amount": 1.0 if solid else 0.0,
		"liquid_amount": 0.0, "lava_amount": 0.0,
		"ice_surface": 1.0 if kind == "ice" and solid else 0.0,
		"mountain_m": 240.0 if solid else 0.0,
		"crater_count": 8 if solid else 0, "crater_m": 240.0,
		"crater_density": 0.15 if solid else 0.0, "crater_scale_km": 20.0,
		"hills_m": 150.0 if solid else 0.0,
		"volcano_count": 0, "volcano_m": 1200.0,
		"wave_scale": 1.0, "granulation": 1.0 if kind == "star" else 0.0,
		"storm_strength": 1.0 if not solid and kind != "star" else 0.0,
		"height_texel_km": 0.0,
	}
	if solid and kind != "ice" and float(recipe.get("water_shine", 0.0)) > 0.3:
		p.liquid_amount = 1.0
	for key in WORLD_DEFAULTS.get(name, {}):
		p[key] = WORLD_DEFAULTS[name][key]
	# Explicit recipe overrides let invented worlds use the same capabilities.
	var overrides: Dictionary = recipe.get("surface", {})
	for key in overrides:
		if p.has(key) and key not in ["solid", "seed"]:
			p[key] = overrides[key]
	# A mapped DEM already owns any large discrete crater (a random one could
	# land on top of Olympus Mons) - always suppressed, AFTER WORLD_DEFAULTS/
	# overrides so a named body's crater_count cannot re-enable it. Wavelength-
	# scale geology (mountains/hills/crater-field octaves) stays ON when the
	# recipe states its own DEM texel size (height_texel_km), band-limited
	# below it instead of zeroed outright - see _below_texel_weight. A mapped
	# body with no texel figure (Earth) keeps the old hard-zero behaviour.
	if not str(recipe.get("height", "")).is_empty():
		p.crater_count = 0
		var texel_km := float(recipe.get("height_texel_km", 0.0))
		if texel_km > 0.0:
			p.height_texel_km = texel_km
			p.mountain_m *= _below_texel_weight(MOUNTAIN_RIDGE_WAVELENGTH_KM, texel_km)
			p.hills_m *= _below_texel_weight(HILLS_WAVELENGTH_KM, texel_km)
		else:
			p.mountain_m = 0.0
			p.crater_density = 0.0
			p.hills_m = 0.0
	for key in ["rock_amount", "liquid_amount", "lava_amount", "ice_surface", "granulation", "storm_strength", "crater_density"]:
		p[key] = clampf(float(p[key]), 0.0, 1.0)
	for key in ["mountain_m", "crater_m", "hills_m", "volcano_m"]:
		p[key] = clampf(float(p[key]), 0.0, 10000.0)
	p.crater_scale_km = clampf(float(p.crater_scale_km), 0.1, 200.0)
	p.wave_scale = clampf(float(p.wave_scale), 0.1, 8.0)
	if not solid:
		for key in ["rock_amount", "liquid_amount", "lava_amount", "ice_surface", "mountain_m", "crater_density", "hills_m"]:
			p[key] = 0.0
		p.crater_count = 0
		p.volcano_count = 0
	var rng := RandomNumberGenerator.new()
	rng.seed = int(p.seed * 10000.0) + 713
	p.craters = _landmarks(rng, clampi(int(p.crater_count), 0, 48), 0.003, 0.009, 1.7)
	p.volcanoes = _landmarks(rng, clampi(int(p.volcano_count), 0, 32), 0.003, 0.008, 1.0)
	var ridge := FastNoiseLite.new()
	ridge.seed = int(p.seed * 101.0)
	ridge.frequency = 160.0
	ridge.fractal_octaves = 3
	p.ridge_noise = ridge
	p.crater_octaves = []
	if p.crater_density > 0.0 and p.crater_scale_km > 0.0:
		var cseed := int(p.seed * 131.0) + 47
		for i in CRATER_OCTAVE_RATIOS.size():
			var scale_km: float = float(p.crater_scale_km) * CRATER_OCTAVE_RATIOS[i]
			var freq := CELLULAR_CAL_KM / maxf(scale_km, 0.02)
			var dn := FastNoiseLite.new()
			dn.seed = cseed + i * 17
			dn.noise_type = FastNoiseLite.TYPE_CELLULAR
			dn.cellular_return_type = FastNoiseLite.RETURN_DISTANCE
			dn.cellular_distance_function = FastNoiseLite.DISTANCE_EUCLIDEAN
			dn.fractal_type = FastNoiseLite.FRACTAL_NONE
			dn.frequency = freq
			# SAME seed/frequency as dn: FastNoiseLite's cellular partition (the
			# Worley point layout) depends only on seed+frequency, so distance
			# and cell-value reads describe the SAME cells - the return type
			# just picks what to report about the nearest point. Verified live
			# (walking a path, the id changes only where distance has a local
			# max, i.e. only at a cell-boundary crossing).
			var idn := FastNoiseLite.new()
			idn.seed = dn.seed
			idn.noise_type = FastNoiseLite.TYPE_CELLULAR
			idn.cellular_return_type = FastNoiseLite.RETURN_CELL_VALUE
			idn.cellular_distance_function = FastNoiseLite.DISTANCE_EUCLIDEAN
			idn.fractal_type = FastNoiseLite.FRACTAL_NONE
			idn.frequency = freq
			p.crater_octaves.append({"dist_noise": dn, "id_noise": idn, "cell_km": scale_km})
	var hills := FastNoiseLite.new()
	hills.seed = int(p.seed * 271.0) + 5
	hills.frequency = REF_CIRCUMFERENCE_KM / HILLS_WAVELENGTH_KM
	hills.fractal_octaves = 3
	p.hills_noise = hills
	p["exposure"] = 1.0
	if solid:
		var fallback_col: Color = recipe.get("color_a", Color(0.45, 0.40, 0.35))
		p.exposure = clampf(EXPOSURE_TARGET_LUM / maxf(_luminance(fallback_col), 0.02),
			1.0, EXPOSURE_GAIN_MAX)
	if overrides.has("exposure"):
		p.exposure = clampf(float(overrides.exposure), 1.0, EXPOSURE_GAIN_MAX)
	elif recipe.has("exposure"):
		p.exposure = clampf(float(recipe.exposure), 1.0, EXPOSURE_GAIN_MAX)
	return p

# Chord distance r_max*width converts to an angle via 2*asin(chord/2); dot()
# is monotonically decreasing in angle over [0, pi], so this is an EXACT
# pre-filter (not an approximation) for `dir.distance_to(direction) < r_max*width`.
static func _dot_reach(width: float, r_max: float) -> float:
	return cos(2.0 * asin(clampf(r_max * width * 0.5, 0.0, 1.0)))

static func _landmarks(rng: RandomNumberGenerator, count: int, lo: float, hi: float, r_max: float) -> Array:
	var result := []
	for i in count:
		for attempt in 32:
			var y := rng.randf_range(-0.85, 0.85)
			var longitude := rng.randf_range(-PI, PI)
			var d := Vector3(sqrt(1.0 - y * y) * cos(longitude), y, sqrt(1.0 - y * y) * sin(longitude))
			var width := rng.randf_range(lo, hi)
			var clear := true
			for other in result:
				if d.distance_to(other.direction) < 1.7 * (width + float(other.width)):
					clear = false
					break
			if clear:
				result.append({"direction": d, "width": width, "dot_reach": _dot_reach(width, r_max)})
				break
	return result

static func crater_shape(r: float) -> float:
	# Bowl below datum; continuous raised rim and ejecta fading to zero outside.
	# Used by the seeded named landmarks (large, sparse) - kept as-is.
	var bowl := -pow(maxf(1.0 - r * r, 0.0), 2.0)
	var rim := 0.28 * exp(-pow((r - 1.0) / 0.16, 2.0))
	return bowl + rim

# Elite-style profile for the dense multi-scale crater fields: flat-ish floor,
# a genuinely steep inner wall (not a gaussian blend), a distinct rim crest,
# then a short ejecta apron. `wall_start` is where the wall begins (in units
# of crater radius, 0..1) - narrower for a proportionally deeper/taller crater
# so wall angle stays roughly constant across sizes, per `_crater_wall_start`.
# The apron only runs to r=1.4 (not the coordinator's originally-requested
# full diameter): with CRATER_SIZE_MAX_FRAC=0.6 the worst-case cell only has
# raw-boundary headroom to about r=1.67 before the Voronoi read flips to an
# unrelated neighbour, so ending the decay at 1.4 leaves a safety margin
# instead of a hard truncation cliff.
static func crater_shape2(r: float, depth_m: float, rim_m: float, wall_start: float) -> float:
	if r < wall_start:
		var t := r / maxf(wall_start, 0.001)
		return -depth_m * (1.0 - 0.15 * t * t)
	if r < 1.0:
		var t := (r - wall_start) / maxf(1.0 - wall_start, 0.001)
		var s := t * t * (3.0 - 2.0 * t)
		return lerp(-depth_m, rim_m, s)
	if r < 1.4:
		var t := (r - 1.0) / 0.4
		return rim_m * (1.0 - smoothstep(0.0, 1.0, t))
	return 0.0

static func _crater_wall_start(depth_ratio: float) -> float:
	var wall_frac := clampf((depth_ratio + CRATER_RIM_RATIO) / tan(deg_to_rad(CRATER_WALL_ANGLE_DEG)), 0.15, 0.6)
	return 1.0 - wall_frac

# crater_density picks WHICH cells host a crater (an empty cell contributes 0,
# not a shallow dent everywhere) and per-crater diameter varies
# CRATER_SIZE_MIN_FRAC..CRATER_SIZE_MAX_FRAC of the cell size, both read off
# the SAME cellular id so a cell that barely passes the density gate also
# gets a small crater, not a full-size one. `edge_fade` is a second, universal
# safety net independent of size_t: it forces the WHOLE contribution to 0 in
# the last 8% of the raw cellular read, so even a size_t right at the cap
# still meets its inactive/mismatched neighbour at height 0, not mid-rim.
static func crater_octave_offset_m(dir: Vector3, oct: Dictionary, density: float, detail_km: float = 0.0, texel_km: float = 0.0) -> float:
	var band: float = _band_weight(float(oct.cell_km), detail_km) \
		* _below_texel_weight(float(oct.cell_km), texel_km)
	if band <= 0.0:
		return 0.0
	var idn: FastNoiseLite = oct.id_noise
	var hash01 := (idn.get_noise_3dv(dir) + 1.0) * 0.5
	var density_fade: float = 1.0 - smoothstep(density - CRATER_DENSITY_FADE, density, hash01)
	if density_fade <= 0.0:
		return 0.0
	var size_t: float = lerp(CRATER_SIZE_MIN_FRAC, CRATER_SIZE_MAX_FRAC,
		clampf(hash01 / maxf(density, 0.0001), 0.0, 1.0))
	var d_km: float = float(oct.cell_km) * size_t
	var depth_ratio := _crater_depth_ratio(d_km)
	var depth_m := depth_ratio * d_km * 1000.0
	var rim_m := CRATER_RIM_RATIO * d_km * 1000.0
	var wall_start := _crater_wall_start(depth_ratio)
	var dn: FastNoiseLite = oct.dist_noise
	var raw_r := (dn.get_noise_3dv(dir) + 1.0) / 0.38
	var r := raw_r / maxf(size_t, 0.001)
	var edge_fade: float = 1.0 - smoothstep(0.92, 1.0, raw_r)
	return crater_shape2(r, depth_m, rim_m, wall_start) * edge_fade * density_fade * band

static func height_offset_m(dir: Vector3, p: Dictionary, detail_km: float = 0.0) -> float:
	if not p.solid:
		return 0.0
	var h := 0.0
	if p.mountain_m > 0.0:
		var ridge: FastNoiseLite = p.ridge_noise
		h += (0.55 - absf(ridge.get_noise_3dv(dir))) * float(p.mountain_m)
	if p.hills_m > 0.0:
		var hn: FastNoiseLite = p.hills_noise
		h += hn.get_noise_3dv(dir) * float(p.hills_m) * _band_weight(HILLS_WAVELENGTH_KM, detail_km)
	for oct in p.crater_octaves:
		var v := crater_octave_offset_m(dir, oct, float(p.crater_density), detail_km, float(p.height_texel_km))
		if v != 0.0:
			h += v
	for crater in p.craters:
		if dir.dot(crater.direction) < float(crater.dot_reach):
			continue
		var r: float = dir.distance_to(crater.direction) / float(crater.width)
		if r < 1.7:
			h += crater_shape(r) * float(p.crater_m)
	for volcano in p.volcanoes:
		if dir.dot(volcano.direction) < float(volcano.dot_reach):
			continue
		var r: float = dir.distance_to(volcano.direction) / float(volcano.width)
		if r < 1.0:
			var cone := (1.0 - r) * (1.0 - smoothstep(0.8, 1.0, r))
			var caldera := 0.76 * exp(-pow(r / 0.16, 4.0))
			h += (cone - caldera) * float(p.volcano_m)
	return h

static func lava_mask(dir: Vector3, p: Dictionary) -> float:
	if p.lava_amount <= 0.0:
		return 0.0
	var lava := 0.0
	for volcano in p.volcanoes:
		var r: float = dir.distance_to(volcano.direction) / float(volcano.width)
		lava = maxf(lava, 1.0 - smoothstep(0.10, 1.0, r))
	return lava * float(p.lava_amount)

static func max_offset_m(p: Dictionary) -> float:
	# Each landmark family is disjoint. Different families may overlap, so sum
	# their individual upper bounds, not every peak on the entire planet.
	var crater := float(p.crater_m) * 0.28 if not p.craters.is_empty() else 0.0
	var volcano := float(p.volcano_m) if not p.volcanoes.is_empty() else 0.0
	# Depth is nearly free here (it is BELOW the datum); only the rim, at its
	# largest possible diameter (size_t=CRATER_SIZE_MAX_FRAC), costs ceiling
	# headroom.
	var octave_bound := 0.0
	if float(p.crater_density) > 0.0:
		for oct in p.crater_octaves:
			octave_bound += CRATER_RIM_RATIO * CRATER_SIZE_MAX_FRAC * float(oct.cell_km) * 1000.0
	return float(p.mountain_m) + float(p.hills_m) + octave_bound + crater + volcano
