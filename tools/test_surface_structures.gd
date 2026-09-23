class_name TestSurfaceStructures
extends SceneTree
var failures := 0
class FlatLand extends TerrainSampler:
	func height_m(_dir: Vector3, _detail: float = 0.0) -> float:
		return 0.0
	func max_height_km() -> float:
		return 0.0
	func is_water(_dir: Vector3) -> bool:
		return false
	func ice01(_dir: Vector3) -> float:
		return 0.0

func _initialize() -> void:
	var recipe := {"kind": "rocky", "surface": {"settlements": [{"name": "Test", "lat_deg": 0.0, "lon_deg": 0.0, "radius_km": 2.0, "density": 1.0, "seed": 42}]}}
	var sampler := FlatLand.new(recipe)
	var examples := {}
	for x in range(1, 8):
		for z in range(1, 8):
			var item := SurfaceSettlement.cell(sampler, sampler.settlements[0], x, z, 6371.0)
			if not item.is_empty():
				examples[item.variant] = item
	check("all ruin archetypes present", examples.size() == 3)
	var tower: Dictionary = examples[0]
	var xf: Transform3D = tower.transform
	var start := xf * Vector3(-.15, .05, 0)
	var end := xf * Vector3(.15, .05, 0)
	var hit := sampler.resolve_motion(start, end, (end-start).normalized() * 8.0, 6371.0, .002)
	check("high speed wall sweep stops before building", hit.hit and (xf.affine_inverse() * hit.position).x < -.025)
	check("wall rebound stays small", hit.velocity.length() < .03)
	var taking_off := sampler.resolve_motion(hit.position, hit.position + hit.normal * .1, hit.normal, 6371.0, .002)
	check("outward thrust can leave wall", taking_off.position.distance_to(hit.position) > .09)
	var buried := sampler.resolve_motion(xf * Vector3(0, .03, 0), xf * Vector3(0, .03, 0), Vector3.ZERO, 6371.0, .002)
	check("embedded spawn separates", buried.hit and buried.position.distance_to(xf * Vector3(0, .03, 0)) > .01)
	var hall: Transform3D = examples[1].transform
	var entering := sampler.resolve_motion(hall * Vector3(.10, .015, 0), hall * Vector3(.022, .015, 0), -hall.basis.x, 6371.0, .001)
	check("missing warehouse wall is an actual opening", not entering.hit)
	var roof := sampler.resolve_motion(hall * Vector3(-.02, .09, 0), hall * Vector3(-.02, .015, 0), -hall.basis.y, 6371.0, .001)
	check("remaining roof stops descent", roof.hit and (hall.affine_inverse() * roof.position).y >= .027)
	var landing := sampler.resolve_motion(hall * Vector3(-.02, .09, 0), hall * Vector3(-.02, .015, 0), -hall.basis.y.normalized() * .001, 6371.0, .001)
	check("slow roof contact settles without bounce", landing.hit and landing.velocity.length() < .00001)
	var buffers := SurfaceStructures.scatter(sampler, Vector3.RIGHT * 6371.0, 6371.0)
	var total := 0
	for buffer in buffers:
		total += buffer.size() / 16
	check("draw budget bounded", total > 100 and total <= SurfaceSettlement.DRAW_BUDGET)
	check("stable layouts independent of camera", buffers == SurfaceStructures.scatter(sampler, Vector3.RIGHT * 6371.0, 6371.0))
	var earth := PlanetGenerator.terrain_sampler(PlanetGenerator.recipe_for({"name": "Earth"}))
	check("Earth abandoned districts configured", earth.settlements.size() == 16)
	check("ruins reference recipe salvage materials", "iron" in earth.settlements[0].materials)
	check("settlements can be explicitly disabled", SurfaceSettlement.resolve({"surface": {"settlement_preset": "earth_graveyard", "settlements": []}}).is_empty())
	check("Earth powered night lights disabled", PlanetGenerator.recipe_for({"name": "Earth"}).city_amount == 0.0)
	check("uninhabited recipes have no ruins", PlanetGenerator.terrain_sampler(PlanetGenerator.recipe_for({"name": "Europa"})).settlements.is_empty())
	var london := SurfaceStructures.scatter(earth, DevSites.dir_for(51.51, -.12) * 6371.0, 6371.0)
	var buildings := 0
	for buffer in london:
		buildings += buffer.size() / 16
	check("London terrain admits grounded buildings", buildings > 100)
	var dhaka_dir := DevSites.dir_for(23.81, 90.41)
	var dhaka := SurfaceStructures.scatter(earth, dhaka_dir * 6371.0, 6371.0)
	var dhaka_buildings := 0
	for buffer in dhaka:
		dhaka_buildings += buffer.size() / 16
	check("Dhaka terrain admits grounded buildings", dhaka_buildings > 100)
	check("Dhaka district excludes forest", SurfaceSettlement.occupied(earth.settlements, dhaka_dir, 6371.0))
	print("Dhaka buildings=", dhaka_buildings)
	print("surface_structures: ", "OK" if failures == 0 else "FAIL", " London buildings=", buildings)
	quit(0 if failures == 0 else 1)

func check(label: String, ok: bool) -> void:
	print("PASS " if ok else "FAIL ", label)
	if not ok:
		failures += 1
