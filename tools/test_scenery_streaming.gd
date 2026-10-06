extends SceneTree
var failures := 0

func _initialize() -> void:
	var recipe := PlanetGenerator.recipe_for({"name": "Earth"})
	var sampler := PlanetGenerator.terrain_sampler(recipe)
	var dir := DevSites.dir_for(-3, -60)
	var ship := dir * (sampler.ground_radius_km(dir, 6371) + .3)
	var patch := SurfacePatch.new()
	patch._ready()
	patch.update_for(ship, "Earth", 6371, .3, .02, 35, recipe, sampler, dir.cross(Vector3.UP).normalized() * 4.0)
	check("forest builds independently while terrain is pending", patch.get("_forest_pending") == true and patch.get("_thread_pending") == true)
	check("fast forest prefetch covers more than one kilometer", patch.get("_forest_result").center.distance_to(ship.normalized() * 6371) > 1.0)
	patch.force_ready()
	check("forest visible after first load", patch.report().props > 400)
	check("fast flight uses wider sparse forest coverage", patch.get("_forest_stride") > 1)
	patch.update_for(ship, "Earth", 6371, .3, .02, 35, recipe, sampler, Vector3.ZERO)
	check("stopping restores dense forest without lateral movement", patch.get("_forest_pending") and patch.get("_forest_stride") == 1)
	patch.force_ready()
	var existing: int = patch.report().props
	var moved := (ship + dir.cross(Vector3.UP).normalized() * .65).normalized() * ship.length()
	patch.update_for(moved, "Earth", 6371, .3, .02, 35, recipe, sampler, dir.cross(Vector3.UP).normalized() * .55)
	check("forest stays visible while replacement loads", patch.report().props == existing and patch.get("_forest_pending"))
	var ruins := SurfaceStructures.new()
	var london := DevSites.dir_for(51.51, -.12) * 6371
	var velocity := london.normalized().cross(Vector3.UP).normalized() * 4.0
	if ruins.get_method_list().any(func(method): return method.name == "update_for" and method.args.size() == 5):
		ruins.call("update_for", sampler, london, 6371.0, .3, velocity)
		check("ruins prefetch ahead of flight", (ruins.get("_result").get("prefetch", london) - london).dot(velocity) > .01)
		check("fast ruins prefetch extends beyond old draw radius", ruins.get("_result").prefetch.distance_to(london) > 2.8)
	else:
		check("ruins accept flight velocity", false)
	ruins.force_ready()
	check("city loaded", ruins.count > 0)
	var city_count := ruins.count
	ruins.update_for(sampler, london + velocity, 6371, .3, velocity)
	check("ruins stay visible while replacement loads", ruins.count == city_count and ruins.get("_pending"))
	ruins.force_ready()
	check("loading ruins does not erase forest", patch.report().props == existing)
	patch.force_ready()
	patch.free()
	ruins.free()
	print("scenery_streaming: ", "OK" if failures == 0 else "FAIL %d" % failures)
	quit(0 if failures == 0 else 1)

func check(label: String, condition: bool) -> void:
	if not condition:
		failures += 1
		printerr("FAIL: ", label)
