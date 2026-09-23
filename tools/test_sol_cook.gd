extends SceneTree
# Sol cook is live: Moon is a real ball from GEO, worlds have maps.
# Run: godot --headless --path . --script res://tools/test_sol_cook.gd

const G := preload("res://scripts/world/planet_generator.gd")
const E := preload("res://scripts/autoload/ephemeris.gd")


func _initialize() -> void:
	var failed := 0
	var worlds: Array = []
	worlds.append_array(E.PLANETS)
	worlds.append_array(E.PHYSICAL_MOONS)

	var names := {}
	for p in worlds:
		if p.get("craft", false):
			continue
		names[str(p.name)] = p

	failed += _check("has_moon", names.has("Moon"))
	failed += _check("has_earth", names.has("Earth"))
	failed += _check("has_sun", names.has("Sun"))
	failed += _check("has_io", names.has("Io"))
	failed += _check("has_phobos", names.has("Phobos"))
	failed += _check("moon_physical", bool(names["Moon"].get("physical", false)))
	failed += _check("io_parent", str(names["Io"].get("parent", "")) == "Jupiter")
	failed += _check("enough_worlds", names.size() >= 25)

	failed += _check("moon_map", G.has_map(G.recipe_for({ "name": "Moon" })))
	failed += _check("io_map", G.has_map(G.recipe_for({ "name": "Io" })))
	failed += _check("earth_map", G.has_map(G.recipe_for({ "name": "Earth" })))
	failed += _check("sun_stellar_recipe", G.recipe_for({ "name": "Sun" }).has("stellar"))

	var moon_eq := Vector3.ZERO
	var sun_eq := Vector3.ZERO
	for p in E.PLANETS:
		if str(p.name) == "Moon":
			moon_eq = p.eq
		elif str(p.name) == "Sun":
			sun_eq = p.eq
	var moon_p := Vector3(moon_eq.x, moon_eq.z, moon_eq.y) * E.AU_TO_UNITS
	var sun_p := Vector3(sun_eq.x, sun_eq.z, sun_eq.y) * E.AU_TO_UNITS
	var geo: Vector3 = sun_p.normalized() * E.GEO_RADIUS_KM
	var dist := (moon_p - geo).length()
	print("sol_cook: GEO→Moon %.0f km  far=%.0f" % [dist, E.CAM_FAR_SOL])
	failed += _check("moon_inside_far", dist < E.CAM_FAR_SOL * 0.85)
	var ang := rad_to_deg(2.0 * asin(clampf(E.MOON_RADIUS_KM / maxf(dist, 1.0), 0.0, 0.999)))
	print("sol_cook: Moon angular size %.2f deg from GEO" % ang)
	failed += _check("moon_disc_real", ang > 0.35 and ang < 0.8)

	var sun_dist := (sun_p - geo).length()
	print("sol_cook: GEO→Sun %.0f km" % sun_dist)
	failed += _check("sun_mesh_too_far", sun_dist > E.CAM_FAR_SOL)
	failed += _check("sun_bigger_than_far", E.SUN_RADIUS_KM > E.CAM_FAR_SOL)
	var sun_ang := rad_to_deg(2.0 * atan(E.SUN_RADIUS_KM / maxf(sun_dist, 1.0)))
	print("sol_cook: Sun angular size %.2f deg from GEO" % sun_ang)
	failed += _check("sun_half_degree", sun_ang > 0.45 and sun_ang < 0.65)
	var core_r: float = E.SKY_SHELL_KM * tan(deg_to_rad(E.SUN_ANG_RADIUS_DEG))
	var corona_r: float = core_r * 10.0
	print("sol_cook: Sun sky core %.0f km  corona %.0f km on shell" % [core_r, corona_r])
	failed += _check("sun_corona_bigger", corona_r > core_r * 4.0)

	var missing_maps: PackedStringArray = PackedStringArray()
	for nm in names.keys():
		var rec := G.recipe_for({ "name": nm })
		if rec.source == "invented":
			print("sol_cook: invented %s" % nm)
			failed += 1
		if nm != "Deimos" and rec.kind != "star" and not G.has_map(rec):
			missing_maps.append(nm)
	failed += _check("deimos_named", G.recipe_for({ "name": "Deimos" }).name == "Deimos")
	if not missing_maps.is_empty():
		print("sol_cook: missing maps %s" % ", ".join(missing_maps))
	failed += _check("sol_planet_maps_except_deimos", missing_maps.is_empty())

	if failed == 0:
		print("sol_cook: OK")
		quit(0)
	else:
		print("sol_cook: FAIL %d" % failed)
		quit(1)


func _check(name: String, ok: bool) -> int:
	if not ok:
		print("sol_cook: FAIL %s" % name)
		return 1
	return 0
