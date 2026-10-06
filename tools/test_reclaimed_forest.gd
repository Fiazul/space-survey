extends SceneTree
var failures := 0

func _initialize() -> void:
	var sampler := PlanetGenerator.terrain_sampler(PlanetGenerator.recipe_for({"name": "Earth"}))
	check("Earth recipe retains requested tree height", sampler.surface.tree_height_m == 110.0)
	var dir := DevSites.dir_for(-3, -60)
	var forest := SurfaceForest.scatter(sampler, dir * 6371, 6371, 4096)
	var giant := 0
	var total_height := 0.0
	var seated := true
	var seat_error := 0.0
	for xf in forest.xforms:
		var height: float = xf.basis.y.length() * .03
		total_height += height
		if height > .24:
			giant += 1
		var ground := sampler.ground_radius_km(xf.origin.normalized(), 6371)
		seat_error = maxf(seat_error, absf(xf.origin.length() - ground + .002))
		seated = seated and absf(xf.origin.length() - ground + .002) < .002 and xf.origin.length() < ground + .0005
	check("large forest trees", total_height / maxf(forest.xforms.size(), 1) > .08)
	check("rare trees larger than Sovereign", giant > 0 and giant < forest.xforms.size() * .08)
	check("tree trunks seated on shared terrain height", seated)
	check("population remains bounded", forest.xforms.size() <= 4096)
	var region: Dictionary = sampler.settlements[0]
	var street: Vector3 = (region.dir * 6371 + region.basis.x * .015 + region.basis.z * .06).normalized()
	check("abandoned avenues admit forest", not SurfaceSettlement.vegetation_occupied(sampler, street, 6371))
	var protected := 0
	for z in range(1, 6):
		for x in range(1, 6):
			var item := SurfaceSettlement.cell(sampler, region, x, z, 6371)
			if not item.is_empty():
				var center: Vector3 = item.transform.origin.normalized()
				check("building foundations exclude trunks", SurfaceSettlement.vegetation_occupied(sampler, center, 6371))
				protected += 1
	check("tested occupied foundations", protected > 0)
	print("reclaimed_forest: ", "OK" if failures == 0 else "FAIL %d" % failures, " trees=", forest.xforms.size(), " giants=", giant, " seat_error_m=", seat_error * 1000)
	quit(0 if failures == 0 else 1)

func check(label: String, condition: bool) -> void:
	if not condition:
		failures += 1
		printerr("FAIL: ", label)
