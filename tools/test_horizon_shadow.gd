extends SceneTree
# Contract check for G.1's per-vertex horizon shadow and the exposure gain that
# sits next to it in shaders/planet_color.gdshaderinc (PLANET_GENERATOR.md
# "Exposure"). Run: godot --headless --script res://tools/test_horizon_shadow.gd
#
# The shadow half uses a SYNTHETIC sampler (a single fixed-height ridge, not a
# real Moon crater): _horizon_shadow marches an arbitrary ring vertex's own
# _sampler, so a hand-built height function that puts one obstruction at a
# known distance and height gives an exact, reproducible expected angle -
# rather than reverse-engineering where SurfaceRecipe's cellular crater field
# happens to seed one on the real DEM. It calls the PRODUCTION
# SurfacePatch._horizon_shadow() directly, not a re-implementation.

const G := preload("res://scripts/world/planet_generator.gd")
const SR := preload("res://scripts/world/surface_recipe.gd")
const SP := preload("res://scripts/world/surface_patch.gd")

const MOON_R := 1737.4      # km, Ephemeris.PLANETS - matches test_surface_band.gd

# --- Synthetic geometry: one flat step ridge, standing in for a crater wall ---
# A ~50 m obstruction sitting at a fixed 150 m east of the world's own "up"
# anchor. Everything before it (off_e < RIDGE_X) is flat ground at height 0;
# everything at or past it sits flat at RIDGE_H (a simplification of a crater's
# far wall/rim - the algorithm only cares about the tallest thing between a
# vertex and the sun, not the whole bowl profile).
const RIDGE_X := 0.15   # km
const RIDGE_H := 0.05   # km

class FakeSampler extends TerrainSampler:
	func ground_radius_km(dir: Vector3, body_radius_km: float, detail_km: float = 0.0) -> float:
		var off_e: float = dir.dot(Vector3(1, 0, 0)) * body_radius_km
		if off_e >= RIDGE_X:
			return body_radius_km + RIDGE_H
		return body_radius_km


func _initialize() -> void:
	var failed := 0
	failed += _shadow_low_sun_blocked()
	failed += _shadow_high_sun_clear()
	failed += _shadow_ring_boundary_continuity()
	failed += _exposure_bounds()
	failed += _exposure_gas_star_excluded()
	failed += _exposure_override()
	if failed == 0:
		print("horizon_shadow: OK")
		quit(0)
	else:
		print("horizon_shadow: FAIL %d" % failed)
		quit(1)


func _make_patch() -> SP:
	var patch := SP.new()
	patch._ready()
	var recipe := G.recipe_for({"name": "Moon"})
	var fake := FakeSampler.new(recipe)
	patch._sampler = fake
	patch._radius = MOON_R
	return patch


# 10 deg sun: a point at the base of the ridge's near (anti-sun) side must be
# shadowed; a point already ON the ridge (its sun-facing top) must be lit; flat
# ground far from the ridge must be untouched.
func _shadow_low_sun_blocked() -> int:
	var failed := 0
	var patch := _make_patch()
	var up := Vector3(0, 1, 0)
	var east := Vector3(1, 0, 0)
	var north := Vector3(0, 0, 1)
	var hit := up * MOON_R
	var elev := deg_to_rad(10.0)
	var sun_dir := (up * sin(elev) + east * cos(elev)).normalized()

	# Anti-sun wall: sits before the ridge, obstructed by it when marching east.
	var s_wall := patch._horizon_shadow(hit, up, east, north, MOON_R, 0.0, 0.0,
		0.0, sun_dir, 0.0, 0.02)
	failed += _check("low_sun_anti_sun_wall_is_shadowed", s_wall < 0.3)

	# Sun-facing wall: already on top of the ridge, nothing taller ahead.
	var s_lit := patch._horizon_shadow(hit, up, east, north, MOON_R, 0.3, 0.0,
		RIDGE_H, sun_dir, 0.0, 0.02)
	failed += _check("low_sun_sun_facing_wall_is_lit", s_lit > 0.9)

	# Flat ground far away: the ridge is out of the march's reach entirely.
	var s_flat := patch._horizon_shadow(hit, up, east, north, MOON_R, -5.0, 0.0,
		0.0, sun_dir, 0.0, 0.02)
	failed += _check("low_sun_flat_ground_is_lit", s_flat > 0.99)

	patch.free()
	return failed


# 60 deg sun: the SAME anti-sun-wall vertex must no longer read as shadowed -
# the ridge's horizon angle (~17 deg) is real but well under a 60 deg sun.
func _shadow_high_sun_clear() -> int:
	var failed := 0
	var patch := _make_patch()
	var up := Vector3(0, 1, 0)
	var east := Vector3(1, 0, 0)
	var north := Vector3(0, 0, 1)
	var hit := up * MOON_R
	var elev := deg_to_rad(60.0)
	var sun_dir := (up * sin(elev) + east * cos(elev)).normalized()

	var s_wall := patch._horizon_shadow(hit, up, east, north, MOON_R, 0.0, 0.0,
		0.0, sun_dir, 0.0, 0.02)
	failed += _check("high_sun_no_false_shadow", s_wall >= 0.9)

	patch.free()
	return failed


# Same class of bug _analytic_normal already fixes for normals: ring i and
# ring i+1 sample the same world position at different quad sizes, so if the
# shadow march's first step were the CALLING ring's own quad (rather than a
# value fixed for the whole rebuild), the two rings would read different
# shadow at their shared rim. _compute_ring passes `normal_step` (fixed per
# rebuild) as the march's step0, not `quad` - assert that choice actually
# lands identical UV2.y (the shadow channel) at real, committed shared-rim
# vertices on a live Moon patch, same probing style as
# test_surface_band.gd's _ring_boundary_height_agreement.
func _shadow_ring_boundary_continuity() -> int:
	var failed := 0
	var moon := G.recipe_for({"name": "Moon"})
	var patch := SP.new()
	patch._ready()
	var dir := Vector3(0.42, 0.31, 0.85).normalized()
	var pos: Vector3 = dir * (MOON_R + 1.0)
	var sampler: TerrainSampler = G.terrain_sampler(moon)
	patch.bind_body(moon, sampler)
	patch.set_view(Vector3(0.72, 0.16, 0.4), 1.0, 0.0)
	patch.update_for(pos, "Moon", true, MOON_R, 1.0, 0.03, 35.0, moon, sampler)
	patch.force_ready()

	var base: float = float(patch.report().base_quad_km)
	var hit: Vector3 = pos.normalized() * MOON_R
	var up := hit.normalized()
	var east := up.cross(Vector3.UP)
	if east.length_squared() < 0.0001:
		east = up.cross(Vector3.RIGHT)
	east = east.normalized()
	var north := east.cross(up).normalized()

	var checked := 0
	for ring in [0, 1]:
		var half_i: float = SP.ring_reach_km(ring, base) * 0.5
		var quad_next: float = SP.ring_quad_km(ring + 1, base)
		var steps: int = SP.RING_SEGS / int(SP.RING_STEP)
		for k in [0, 2, 4, steps]:
			var off_e: float = -half_i + quad_next * float(k)
			var off_n: float = half_i
			var d: Vector3 = (hit + east * off_e + north * off_n).normalized()
			var expect_p: Vector3 = d * sampler.ground_radius_km(d, MOON_R, SP._detail_km_at(off_e, off_n))
			var a := _closest_shadow(patch, ring, expect_p)
			var b := _closest_shadow(patch, ring + 1, expect_p)
			checked += 1
			failed += _check("shadow_boundary_%d_%d_k%d_ring%d_vertex_found" % [ring, ring + 1, k, ring],
				a.d < 0.01)
			failed += _check("shadow_boundary_%d_%d_k%d_ring%d_vertex_found" % [ring, ring + 1, k, ring + 1],
				b.d < 0.01)
			failed += _check("shadow_boundary_%d_%d_k%d_shadow_agrees" % [ring, ring + 1, k],
				absf(a.shadow - b.shadow) < 1.0e-4)
	failed += _check("checked_at_least_6_shared_rim_points", checked >= 6)
	patch.free()
	return failed


func _closest_shadow(patch: SP, ring: int, target: Vector3) -> Dictionary:
	var best_d := INF
	var best_shadow := 1.0
	for kind in ["land", "skirt"]:
		var mi: MeshInstance3D = patch.mesh_for(kind, ring)
		if mi == null or mi.mesh == null or mi.mesh.get_surface_count() == 0:
			continue
		var arrays: Array = mi.mesh.surface_get_arrays(0)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var uv2: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV2]
		for i in verts.size():
			var d := verts[i].distance_to(target)
			if d < best_d:
				best_d = d
				best_shadow = uv2[i].y
	return {"d": best_d, "shadow": best_shadow}


# --- Exposure ---
# The measured live behaviour (probed with the real Sol recipes and the real
# land_color() every ring vertex paints with) does NOT match a naive "Moon is
# 12% albedo" guess: moon_2k.jpg's own mean linear luminance is ~0.32, and
# SurfacePatch's real land_color() sampling reads ~0.32 too, giving a MODEST
# gain (~1.0-1.1), not the 2.5-3x a dark-regolith assumption would predict.
# This file asserts the general contract (bounded, solid-only, star/gas
# excluded, override honoured) against the REAL measured range rather than
# hard-coding an assumed number that live probing contradicts - see the
# worker report for the measured table.
func _exposure_bounds() -> int:
	var failed := 0
	for name in ["Earth", "Moon", "Mars", "Mercury", "Venus"]:
		var recipe := G.recipe_for({"name": name})
		var resolved := SR.resolve(recipe)
		var e: float = float(resolved.exposure)
		failed += _check(name + "_exposure_at_least_1", e >= 1.0 - 1.0e-6)
		failed += _check(name + "_exposure_capped", e <= SR.EXPOSURE_GAIN_MAX + 1.0e-6)
	return failed


func _exposure_gas_star_excluded() -> int:
	var failed := 0
	for name in ["Sun", "Jupiter", "Saturn"]:
		var recipe := G.recipe_for({"name": name})
		var resolved := SR.resolve(recipe)
		failed += _check(name + "_exposure_is_neutral", is_equal_approx(float(resolved.exposure), 1.0))
	return failed


func _exposure_override() -> int:
	var failed := 0
	var custom := G.recipe_for({"name": "Moon"})
	custom["surface"] = {"exposure": 2.7}
	var resolved := SR.resolve(custom)
	failed += _check("surface_override_honoured", is_equal_approx(float(resolved.exposure), 2.7))

	var custom2 := G.recipe_for({"name": "Mars"})
	custom2["exposure"] = 1.6
	var resolved2 := SR.resolve(custom2)
	failed += _check("top_level_override_honoured", is_equal_approx(float(resolved2.exposure), 1.6))
	return failed


func _check(name: String, ok: bool) -> int:
	if not ok:
		print("horizon_shadow: FAIL %s" % name)
		return 1
	return 0
