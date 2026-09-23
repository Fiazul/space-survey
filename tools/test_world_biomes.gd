class_name TestWorldBiomes
extends SceneTree
const G = preload("res://scripts/world/planet_generator.gd")
const B = preload("res://scripts/world/surface_biome.gd")
const F = preload("res://scripts/world/surface_forest.gd")
const R = preload("res://scripts/world/surface_recipe.gd")
var failures := 0

func check(label: String, ok: bool) -> void:
	if not ok:
		failures += 1
		push_error(label)

func _initialize() -> void:
	var profile := R.resolve({"kind": "rocky", "surface": {
		"vegetation_density": 0.8, "snow_line_m": 5000.0, "snow_polar_drop_m": 5200.0}})
	check("invented world enables forest", B.vegetation(profile, Vector3.RIGHT, 0.1, Color.GREEN) > 0.5)
	check("high mountains exclude forest", B.vegetation(profile, Vector3.RIGHT, 6.0, Color.GREEN) == 0.0)
	check("polar snow line lower", B.snow_line_m(profile, Vector3.UP) < B.snow_line_m(profile, Vector3.RIGHT))
	check("gas cannot grow forest", R.resolve({"kind": "gas", "surface": {"vegetation_density": 1.0}}).vegetation_density == 0.0)
	check("liquid does not imply biosphere", G.surface_kit({"kind": "rocky", "air_amount": 1.0, "water_shine": 1.0}) != "tree")
	check("Titan has no Earth trees", G.surface_kit(G.recipe_for({"name": "Titan"})) != "tree")
	check("frozen preset chooses ice geometry", G.surface_kit({"kind": "rocky", "surface": {"preset": "frozen_crust"}}) == "ice")
	check("high altitude bounds geometry", B.forest_budget(10.0) == 0)
	var custom := G.recipe_for({"name": "Test biosphere", "kind": "rocky", "air_amount": 0.8,
		"surface": {"preset": "temperate_forest", "tree_height_m": 18.0}})
	check("invented recipe supports preset", G.surface_kit(custom) == "tree")
	check("explicit value overrides preset", R.resolve(custom).tree_height_m == 18.0)
	var elements: Dictionary = preload("res://scripts/crafting/crafting_catalog.gd").elements()
	for name in ["Earth", "Moon", "Mars", "Europa", "Titan", "Jupiter", "Test biosphere"]:
		var world: Dictionary = G.recipe_for({"name": name})
		for source in ["crust", "ocean", "atmosphere", "salvage"]:
			for material in world.materials.get(source, []):
				check("resource resolves " + name + "/" + material, elements.has(material))
	var earth := G.terrain_sampler(G.recipe_for({"name": "Earth"}))
	var coast_lat := deg_to_rad(20.5)
	var coast_lon := deg_to_rad(-17.0)
	var coast := Vector3(cos(coast_lat) * cos(coast_lon), sin(coast_lat), cos(coast_lat) * sin(coast_lon))
	check("warm bright coast is not sea ice", earth.ice01(coast) == 0.0)
	var lat := deg_to_rad(-3.0)
	var lon := deg_to_rad(-60.0)
	var dir := Vector3(cos(lat) * cos(lon), sin(lat), cos(lat) * sin(lon))
	var cache := {}
	var start := Time.get_ticks_usec()
	var first := F.scatter(earth, dir * 6371.0, 6371.0, 4096, false, cache)
	var cold_us := Time.get_ticks_usec() - start
	check("dense canopy exceeds old whole-world budget", first.xforms.size() > 400)
	check("forest respects budget", first.xforms.size() <= 4096)
	start = Time.get_ticks_usec()
	var repeat := F.scatter(earth, dir * 6371.0, 6371.0, 4096, false, cache)
	var warm_us := Time.get_ticks_usec() - start
	check("stable cell placement", first.xforms == repeat.xforms)
	var moved := F.scatter(earth, (dir * 6371.0 + Vector3(0.01, 0.0, 0.0)).normalized() * 6371.0, 6371.0, 4096)
	var seats := {}
	for t in first.xforms:
		seats[t.origin] = true
	var shared := 0
	for t in moved.xforms:
		if seats.has(t.origin):
			shared += 1
	check("moving camera preserves tree seats", shared > first.xforms.size() * 0.8)
	print("world_biomes: ", "OK" if failures == 0 else "FAIL %d" % failures, " trees=", first.xforms.size(), " retained=", shared, " cold_ms=", cold_us / 1000.0, " cached_ms=", warm_us / 1000.0)
	quit(0 if failures == 0 else 1)
