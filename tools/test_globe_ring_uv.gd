extends SceneTree
# Contract: planet_cook.gdshader's vertex()-derived map UV (equirectangular,
# from direction) must equal TerrainSampler._dir_uv() / CloudLayer._dir_uv()
# EXACTLY — same longitude origin/sign, same latitude convention — or the
# globe samples albedo/height/spec/night/cloud at a different real-world spot
# than the ring/cloud-deck do for the SAME direction.
# Run: godot --headless --script res://tools/test_globe_ring_uv.gd
const G := preload("res://scripts/world/planet_generator.gd")
var failures := 0


# Mirrors the shader's vertex():
#   float lon = atan(v_mdl.z, v_mdl.x);
#   float lat = asin(clamp(v_mdl.y, -1.0, 1.0));
#   v_map_uv = vec2(lon / TAU + 0.5, 0.5 - lat / PI);
func shader_uv(dir: Vector3) -> Vector2:
	var lon := atan2(dir.z, dir.x)
	var lat := asin(clampf(dir.y, -1.0, 1.0))
	return Vector2(lon / TAU + 0.5, 0.5 - lat / PI)


func _initialize() -> void:
	var sampler: TerrainSampler = G.terrain_sampler(G.recipe_for({"name": "Earth"}))
	var dirs := [
		Vector3.UP, Vector3.DOWN,                          # poles
		Vector3.RIGHT, Vector3.LEFT,                        # +/- X (lon 0, 180)
		Vector3.FORWARD, Vector3.BACK,                      # +/- Z (lon +/-90)
		Vector3(1, 0, 0.0001).normalized(),                 # just off +X
		Vector3(-1, 0, -0.0001).normalized(),               # antimeridian, just off -X
		Vector3(0.5, 0.5, 0.5).normalized(),
		Vector3(-0.3, 0.7, -0.6).normalized(),
		Vector3(0.6, -0.4, 0.3).normalized(),
		Vector3(-0.8, -0.2, 0.55).normalized(),
	]
	check("checked_12_directions", dirs.size() == 12)
	for dir in dirs:
		var a := sampler._dir_uv(dir)
		var b := shader_uv(dir)
		check("uv_matches_at_%s" % str(dir), a.is_equal_approx(b))

	if failures == 0:
		print("globe_ring_uv: OK")
		quit(0)
	else:
		print("globe_ring_uv: FAIL %d" % failures)
		quit(1)


func check(label: String, ok: bool) -> void:
	if not ok:
		failures += 1
		push_error("globe_ring_uv: " + label)
