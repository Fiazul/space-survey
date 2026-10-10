class_name GalacticCoreEphemeris
extends SystemEphemeris
const DISTRIBUTION := preload("res://scripts/world/galactic_core_distribution.gd")
# A local frame at Sgr A*: no float32 subtraction against its 26,673 ly Sol offset.

static func build(system_id: String, row: Dictionary) -> GalacticCoreEphemeris:
	var e := GalacticCoreEphemeris.new()
	e.id = system_id
	e.primary_star = str(row.name)
	e.spawn_body = e.primary_star
	var recipe := BlackHoleRecipe.resolve(row)
	e._catalog.append({"name": e.primary_star, "radius": recipe.stellar.radius_km,
		"mu": recipe.stellar.mass_solar * BlackHoleRecipe.GM_SUN,
		"mass": recipe.stellar.mass_solar * 333000.0, "black_hole": recipe.stellar,
		"color": Color.BLACK, "glow": 0.0, "star": true, "physical": true,
		"stellar_type": "black_hole", "stellar": row.stellar.duplicate(true)})
	e._pos64[e.primary_star] = PackedFloat64Array([0.0, 0.0, 0.0])
	e._cluster_stars()
	e._build_gravity_bodies()
	return e

func spawn_park_km() -> float:
	return 7.9 * KM_PER_AU

func _cluster_stars() -> void:
	var points := DISTRIBUTION.samples()
	const LY_KM := 9.4607304725808e12
	for index in points.physical_indices:
		var name := "Core star C-%05d" % index
		var offset: Vector3 = points.positions[index]
		var radius: float = points.attributes[index].y * LY_KM
		var temperature: float = points.temperatures[index]
		var mass := 17.0 if temperature > 10000.0 else (2.0 if radius > 2.0*695700.0 else 1.0)
		var metadata := {"temperature_k": temperature, "radius_solar": radius/695700.0, "mass_solar": mass}
		_catalog.append({"name": name, "radius": radius, "mu": mass*BlackHoleRecipe.GM_SUN,
			"mass": mass*333000.0, "spin": TAU/(30.0*86400.0), "color": points.colors[index],
			"glow": 1.0, "star": true, "physical": true,
			"spectral": "B2V" if temperature > 10000.0 else ("K3III" if radius > 2.0*695700.0 else "G2V"),
			"stellar": metadata})
		_pos64[name] = PackedFloat64Array([float(offset.x)*LY_KM, float(offset.y)*LY_KM, float(offset.z)*LY_KM])
