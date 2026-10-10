class_name GalacticCoreDistribution
extends RefCounted
# Pure, cached physical samples shared by the view and ephemeris.
const SEED := 2600174540
const LAYERS := [[14000, 12000.0, .60, .55], [7000, 450.0, .68, .18], [9000, 12.0, .80, .85]]
static var _sample_cache := {}

static func galactic_basis() -> Basis:
	var ra := deg_to_rad(192.85948)
	var dec := deg_to_rad(27.12825)
	var pole := Vector3(cos(dec)*cos(ra), sin(dec), cos(dec)*sin(ra))
	var center := Vector3(-.05487556, -.48383502, -.87343709)
	var across := pole.cross(center).normalized()
	return Basis(center, pole, across)

static func samples() -> Dictionary:
	if not _sample_cache.is_empty(): return _sample_cache
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	var positions := PackedVector3Array()
	var colors := PackedColorArray()
	var attributes := PackedVector2Array()
	var temperatures := PackedFloat32Array()
	var frame := galactic_basis()
	for layer in LAYERS:
		for i in int(layer[0]):
			var radius: float = float(layer[1]) * pow(rng.randf_range(.00001, 1.0), float(layer[2]))
			var y := rng.randf_range(-1.0, 1.0)
			var phi := rng.randf() * TAU
			var planar := sqrt(1.0-y*y)
			positions.append(frame * Vector3(cos(phi)*planar, y*float(layer[3]), sin(phi)*planar) * radius)
			var hot := rng.randf() < (.13 if float(layer[1]) < 20.0 else .025)
			var temperature := rng.randf_range(12000.0, 30000.0) if hot else rng.randf_range(3400.0, 6500.0)
			temperature = round(temperature/250.0)*250.0
			colors.append(StarRecipe.color_at(temperature))
			var luminosity := pow(10.0, rng.randf_range(-.5, 3.2))
			var radius_solar := sqrt(luminosity)/pow(temperature/5772.0, 2.0)
			attributes.append(Vector2(luminosity, radius_solar*695700.0 / 9.4607304725808e12))
			temperatures.append(temperature)
	var inner_indices: Array = range(21000, positions.size())
	inner_indices.sort_custom(func(a, b): return positions[a].length_squared() < positions[b].length_squared())
	inner_indices.resize(12)
	_sample_cache = {"positions": positions, "colors": colors, "attributes": attributes,
		"temperatures": temperatures, "physical_indices": inner_indices}
	return _sample_cache
