extends RefCounted
## Geological profiles are shared by geometry, collision and material binding.
## Landmarks below are seeded scenery, not claims about surveyed feature locations.

const WORLD_DEFAULTS := {
	"Earth": {"liquid_amount": 1.0, "crater_count": 0, "mountain_m": 0.0, "volcano_count": 3, "volcano_m": 240.0},
	"Moon": {"crater_count": 28, "crater_m": 700.0, "crater_field_m": 65.0, "mountain_m": 0.0},
	"Mercury": {"crater_count": 32, "crater_m": 450.0, "crater_field_m": 75.0},
	"Mars": {"crater_count": 12, "crater_m": 260.0, "mountain_m": 600.0, "volcano_count": 5, "volcano_m": 2400.0},
	"Venus": {"crater_count": 3, "volcano_count": 12, "volcano_m": 1500.0, "mountain_m": 500.0},
	"Io": {"crater_count": 0, "volcano_count": 18, "volcano_m": 1800.0, "lava_amount": 1.0, "mountain_m": 240.0},
	"Europa": {"ice_surface": 1.0, "crater_count": 3, "crater_m": 100.0, "mountain_m": 80.0},
	"Enceladus": {"ice_surface": 1.0, "crater_count": 5, "crater_m": 100.0, "mountain_m": 100.0},
	"Titan": {"ice_surface": 0.15, "liquid_amount": 1.0, "mountain_m": 220.0, "crater_count": 2},
}

static func resolve(recipe: Dictionary) -> Dictionary:
	var kind := str(recipe.get("kind", "rocky"))
	var name := str(recipe.get("name", ""))
	var solid := kind != "star" and kind != "gas" and name not in ["Uranus", "Neptune"]
	var p := {
		"solid": solid, "seed": float(recipe.get("seed", 0.0)),
		"rock_amount": 1.0 if solid else 0.0,
		"liquid_amount": 0.0, "lava_amount": 0.0,
		"ice_surface": 1.0 if kind == "ice" and solid else 0.0,
		"mountain_m": 240.0 if solid else 0.0,
		"crater_count": 8 if solid else 0, "crater_m": 240.0,
		"crater_field_m": 0.0,
		"volcano_count": 0, "volcano_m": 1200.0,
		"wave_scale": 1.0, "granulation": 1.0 if kind == "star" else 0.0,
		"storm_strength": 1.0 if not solid and kind != "star" else 0.0,
	}
	# A mapped DEM already owns the mountains. Never pile generic mountains on it.
	if not str(recipe.get("height", "")).is_empty():
		p.mountain_m = 0.0
		p.crater_count = 0
	if solid and kind != "ice" and float(recipe.get("water_shine", 0.0)) > 0.3:
		p.liquid_amount = 1.0
	for key in WORLD_DEFAULTS.get(name, {}):
		p[key] = WORLD_DEFAULTS[name][key]
	# Explicit recipe overrides let invented worlds use the same capabilities.
	var overrides: Dictionary = recipe.get("surface", {})
	for key in overrides:
		if p.has(key) and key not in ["solid", "seed"]:
			p[key] = overrides[key]
	for key in ["rock_amount", "liquid_amount", "lava_amount", "ice_surface", "granulation", "storm_strength"]:
		p[key] = clampf(float(p[key]), 0.0, 1.0)
	for key in ["mountain_m", "crater_m", "crater_field_m", "volcano_m"]:
		p[key] = clampf(float(p[key]), 0.0, 10000.0)
	p.wave_scale = clampf(float(p.wave_scale), 0.1, 8.0)
	if not solid:
		for key in ["rock_amount", "liquid_amount", "lava_amount", "ice_surface", "mountain_m", "crater_field_m"]:
			p[key] = 0.0
		p.crater_count = 0
		p.volcano_count = 0
	var rng := RandomNumberGenerator.new()
	rng.seed = int(p.seed * 10000.0) + 713
	p.craters = _landmarks(rng, clampi(int(p.crater_count), 0, 48), 0.003, 0.009)
	p.volcanoes = _landmarks(rng, clampi(int(p.volcano_count), 0, 32), 0.003, 0.008)
	var ridge := FastNoiseLite.new()
	ridge.seed = int(p.seed * 101.0)
	ridge.frequency = 160.0
	ridge.fractal_octaves = 3
	p.ridge_noise = ridge
	var cellular := FastNoiseLite.new()
	cellular.seed = ridge.seed + 91
	cellular.noise_type = FastNoiseLite.TYPE_CELLULAR
	cellular.cellular_return_type = FastNoiseLite.RETURN_DISTANCE
	cellular.cellular_distance_function = FastNoiseLite.DISTANCE_EUCLIDEAN
	cellular.fractal_type = FastNoiseLite.FRACTAL_NONE
	cellular.frequency = 240.0
	p.crater_noise = cellular
	return p

static func _landmarks(rng: RandomNumberGenerator, count: int, lo: float, hi: float) -> Array:
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
				result.append({"direction": d, "width": width})
				break
	return result

static func crater_shape(r: float) -> float:
	# Bowl below datum; continuous raised rim and ejecta fading to zero outside.
	var bowl := -pow(maxf(1.0 - r * r, 0.0), 2.0)
	var rim := 0.28 * exp(-pow((r - 1.0) / 0.16, 2.0))
	return bowl + rim

static func height_offset_m(dir: Vector3, p: Dictionary) -> float:
	if not p.solid:
		return 0.0
	var h := 0.0
	if p.mountain_m > 0.0:
		var ridge: FastNoiseLite = p.ridge_noise
		h += (0.55 - absf(ridge.get_noise_3dv(dir))) * float(p.mountain_m)
	if p.crater_field_m > 0.0:
		var cellular: FastNoiseLite = p.crater_noise
		h += crater_shape((cellular.get_noise_3dv(dir) + 1.0) / 0.38) * float(p.crater_field_m)
	for crater in p.craters:
		var r: float = dir.distance_to(crater.direction) / float(crater.width)
		if r < 1.7:
			h += crater_shape(r) * float(p.crater_m)
	for volcano in p.volcanoes:
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
	return float(p.mountain_m) + float(p.crater_field_m) + crater + volcano
