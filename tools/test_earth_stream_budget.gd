extends SceneTree

const SP = preload("res://scripts/world/surface_patch.gd")
const G = preload("res://scripts/world/planet_generator.gd")
var failures := 0

func _initialize() -> void:
	var patch := SP.new()
	patch._ready()
	var recipe := G.recipe_for({"name": "Earth"})
	check("Earth includes physical material sources", recipe.get("materials", {}).has("atmosphere"))
	check("Earth port stays salvage-only", recipe.get("materials", {}).get("port_salvage_only", false))
	var isolated := G.recipe_for({"name": "Earth"})
	isolated.materials.crust.clear()
	check("material lists are isolated per recipe", not recipe.materials.crust.is_empty())
	var sampler := G.terrain_sampler(recipe)
	patch.bind_body(recipe, sampler)
	if patch.has_method("_vegetation_at"):
		check("polar ice has no trees", not patch._vegetation_at(Vector3.UP, 0.0))
		check("alpine snow has no trees", not patch._vegetation_at(Vector3.RIGHT, 6.0))
		var desert := Vector3(cos(deg_to_rad(23.0)), sin(deg_to_rad(23.0)), 0.0)
		check("desert has no forest props", not patch._vegetation_at(desert, 0.3))
	else:
		check("vegetation respects Earth biomes", false)
	var land_dir := Vector3(0.2, 0.7, 0.6).normalized()
	check("unresolved relief has no residual displacement", absf(sampler._detail_m(land_dir, 1000.0, 100.0)) < 0.001)
	var hit := Vector3.RIGHT * 6371.0
	var base := 0.01
	if patch.has_method("_flight_base"):
		patch._batch_times = [2000]
		var flight_base: float = patch._flight_base(base, hit, Vector3.FORWARD * 10.0)
		check("10 km/s remains inside detail while workers build", SP.ring_reach_km(0, flight_base) * 0.5 > 10.0 * 2.0)
		check("detail restores after stopping", is_equal_approx(patch._flight_base(base, hit, Vector3.ZERO), base))
	else:
		check("terrain accounts for distance flown during build", false)
	var predicted: Vector3 = patch._predicted_hit(hit, 6371.0, Vector3.FORWARD * 10.0, base)
	check("10 km/s prediction retains nearby ground", predicted.distance_to(hit) < SP.ring_reach_km(0, base) * 0.5)
	# A slow worker makes the exit-path stall reproducible independently of CPU speed.
	patch._thread_pending = true
	patch._thread_group_id = WorkerThreadPool.add_group_task(func(_i: int): OS.delay_msec(250), 1)
	var started := Time.get_ticks_msec()
	patch.update_for(Vector3.RIGHT * 7000.0, "Earth", true, 6371.0, 629.0, 0.0, 35.0, recipe, sampler)
	check("leaving atmosphere does not wait on worker", Time.get_ticks_msec() - started < 100)
	check("leaving atmosphere hides local patch", not patch.visible)
	patch._abandon_rebuild()
	patch.free()
	print("earth_stream_budget: ", "OK" if failures == 0 else "FAIL %d" % failures)
	quit(0 if failures == 0 else 1)

func check(label: String, ok: bool) -> void:
	if not ok:
		failures += 1
		push_error(label)
