extends SceneTree
const G = preload("res://scripts/world/planet_generator.gd")
var failures := 0
class FlatWorld extends TerrainSampler:
	func height_m(_dir: Vector3, _detail: float = 0.0) -> float:
		return 0.0
	func max_height_km() -> float:
		return 500.0

class SlopedWorld extends FlatWorld:
	func normal_at(position: Vector3, _radius: float) -> Vector3:
		return (position.normalized() + Vector3.UP).normalized()

func _initialize() -> void:
	var earth := G.terrain_sampler(G.recipe_for({"name": "Earth"}))
	if not earth.has_method("resolve_motion"):
		check("solid contact resolver exists", false)
	else:
		for name in ["Earth", "Moon", "Mars", "Europa"]:
			var s := G.terrain_sampler(G.recipe_for({"name": name}))
			var radius: float = {"Earth": 6371.0, "Moon": 1737.4, "Mars": 3389.5, "Europa": 1560.8}[name]
			var dir := Vector3(0.3, 0.4, 0.8).normalized()
			var ground := s.ground_radius_km(dir, radius)
			var hit: Dictionary = s.resolve_motion(dir * (ground + 0.2), dir * (ground - 0.3), -dir * 10.0, radius, 0.04)
			check(name + " stops at surface", hit.hit and s.alt_above_ground_km(hit.position, radius) >= 0.039)
			check(name + " gentle outward bounce", hit.velocity.dot(hit.normal) > 0.0 and hit.velocity.dot(hit.normal) <= 0.0051)
			var buried: Dictionary = s.resolve_motion(dir * (ground - 0.5), dir * (ground - 0.5), Vector3.ZERO, radius, 0.04)
			check(name + " recovers buried spawn", s.alt_above_ground_km(buried.position, radius) >= 0.039)
			var resting: Dictionary = s.resolve_motion(hit.position, hit.position - dir * 0.002, -dir * 0.001, radius, 0.04)
			check(name + " low speed contact settles", absf(resting.velocity.dot(resting.normal)) < 0.0001)
		var sea := direction(0.0, -150.0)
		var resting_pos := sea * (6371.0 + 0.042)
		var original := resting_pos
		var resting_velocity := Vector3.ZERO
		for _frame in 180:
			resting_velocity -= sea * 0.00981 / 60.0
			var step: Dictionary = earth.resolve_motion(resting_pos, resting_pos + resting_velocity / 60.0, resting_velocity, 6371.0, 0.04)
			resting_pos = step.position
			resting_velocity = step.velocity
		check("resting contact does not sink or pogo", resting_pos.distance_to(original) < 0.001 and resting_velocity.length() < 0.0001)
		var flat := FlatWorld.new({})
		flat.surface = {"solid": true}
		var start := Vector3.RIGHT * 6471.0
		var finish := start.rotated(Vector3.UP, 0.2)
		var limited: Dictionary = flat.resolve_motion(start, finish, Vector3.FORWARD * 10000.0, 6371.0, 0.04)
		check("extreme travel stops at last verified point", limited.budget_limited and limited.position.distance_to(start) <= 103.0 and limited.velocity == Vector3.ZERO)
		var slope := SlopedWorld.new({})
		slope.surface = {"solid": true}
		var impact: Dictionary = slope.resolve_motion(Vector3.RIGHT * 6371.2,
			Vector3.RIGHT * 6370.9, Vector3.LEFT * 10.0, 6371.0, 0.04)
		check("slope impact cannot launch ship away at kilometres per second", impact.velocity.length() < 0.03)
		var post_velocity: Vector3 = impact.velocity
		post_velocity += Vector3.LEFT * 0.02943 * 2.0
		check("groundward thrust reverses rebound without S", post_velocity.x < 0.0)
		var gas := G.terrain_sampler(G.recipe_for({"name": "Jupiter"}))
		var cloud_pass: Dictionary = gas.resolve_motion(Vector3.RIGHT * 72000.0, Vector3.RIGHT * 71000.0, Vector3.LEFT, 71492.0, 0.04)
		check("gas giant has no solid floor", not cloud_pass.hit and cloud_pass.position == Vector3.RIGHT * 71000.0)
		# Cross Everest from clear air to clear air; endpoint projection alone misses it.
		var a := direction(27.9881, 86.70) * (6371.0 + 8.0)
		var b := direction(27.9881, 87.15) * (6371.0 + 8.0)
		var ridge: Dictionary = earth.resolve_motion(a, b, (b-a).normalized() * 50.0, 6371.0, 0.04)
		check("Everest sweep catches intervening summit", ridge.hit and ridge.position.distance_to(b) > 1.0)
		var escaping: Dictionary = earth.resolve_motion(ridge.position, ridge.position + ridge.normal, ridge.normal, 6371.0, 0.04)
		check("outward takeoff remains possible", escaping.position.distance_to(ridge.position) > 0.9)
	print("surface_contact: ", "OK" if failures == 0 else "FAIL %d" % failures)
	quit(0 if failures == 0 else 1)

func direction(lat: float, lon: float) -> Vector3:
	var a := deg_to_rad(lat)
	var b := deg_to_rad(lon)
	return Vector3(cos(a)*cos(b), sin(a), cos(a)*sin(b))

func check(label: String, ok: bool) -> void:
	if not ok:
		failures += 1
		push_error(label)
