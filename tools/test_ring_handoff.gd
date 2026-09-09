extends SceneTree
# Ground/globe hand-off contract: SurfacePatch.has_ground() must stay false
# until ring 0 has committed real geometry for the CURRENT body, and
# planet_system keys the globe's hide on `visible and has_ground()` rather
# than band membership alone. Before this slice `visible` went true the same
# frame the tile entered the band, independent of whether anything had been
# rebuilt yet — a cold tile (or one abandoned by a body switch) showed
# nothing while the globe was already hidden underneath it, which is the
# Moon-disappears-on-approach bug.
# Run: godot --headless --script res://tools/test_ring_handoff.gd

const G := preload("res://scripts/world/planet_generator.gd")
const SP := preload("res://scripts/world/surface_patch.gd")
const E := preload("res://scripts/autoload/ephemeris.gd")

const MOON_R := 1737.4
const MARS_R := 3389.5
const AIRLESS_KILL := E.CONTACT_KILL_FLOOR_KM


func _initialize() -> void:
	var failed := 0
	failed += _cold_tile_has_no_ground()
	failed += _body_switch_clears_ground()
	if failed == 0:
		print("ring_handoff: OK")
		quit(0)
	else:
		print("ring_handoff: FAIL %d" % failed)
		quit(1)


func _ceiling_of(recipe: Dictionary) -> float:
	return PlanetGenerator.band_ceiling_km(G.terrain_sampler(recipe))


func _cold_tile_has_no_ground() -> int:
	var failed := 0
	var moon := G.recipe_for({"name": "Moon"})
	var patch := SP.new()
	patch._ready()

	var dir := Vector3(0.42, 0.31, 0.85).normalized()
	var pos: Vector3 = dir * (MOON_R + 1.0)
	var sampler: TerrainSampler = G.terrain_sampler(moon)
	patch.bind_body(moon, sampler)
	var ceiling := _ceiling_of(moon)

	# One update_for call only DISPATCHES the background rebuild; nothing has
	# landed yet, so a cold tile must not claim ground even though it is
	# inside the band.
	patch.update_for(pos, "Moon", true, MOON_R, 1.0, AIRLESS_KILL, ceiling, moon, sampler)
	failed += _check("cold_tile_has_no_ground", not patch.has_ground())
	failed += _check("cold_tile_not_visible", not bool(patch.report().visible))

	patch.force_ready()
	failed += _check("committed_tile_has_ground", patch.has_ground())
	failed += _check("committed_tile_visible", bool(patch.report().visible))
	return failed


func _body_switch_clears_ground() -> int:
	var failed := 0
	var moon := G.recipe_for({"name": "Moon"})
	var mars := G.recipe_for({"name": "Mars"})
	var patch := SP.new()
	patch._ready()

	var moon_dir := Vector3(0.42, 0.31, 0.85).normalized()
	var moon_pos: Vector3 = moon_dir * (MOON_R + 1.0)
	var moon_sampler: TerrainSampler = G.terrain_sampler(moon)
	var moon_ceiling := _ceiling_of(moon)
	patch.bind_body(moon, moon_sampler)
	patch.update_for(moon_pos, "Moon", true, MOON_R, 1.0, AIRLESS_KILL, moon_ceiling, moon, moon_sampler)
	patch.force_ready()
	failed += _check("moon_committed_before_switch", patch.has_ground())

	var mars_dir := Vector3(0.11, 0.87, 0.48).normalized()
	var mars_pos: Vector3 = mars_dir * (MARS_R + 1.0)
	var mars_sampler: TerrainSampler = G.terrain_sampler(mars)
	var mars_ceiling := _ceiling_of(mars)
	patch.update_for(mars_pos, "Mars", true, MARS_R, 1.0, AIRLESS_KILL, mars_ceiling, mars, mars_sampler)
	failed += _check("switched_body_has_no_ground_before_commit", not patch.has_ground())
	failed += _check("switched_body_not_visible_before_commit", not bool(patch.report().visible))

	patch.force_ready()
	failed += _check("switched_body_has_ground_after_commit", patch.has_ground())
	failed += _check("switched_body_bound_to_mars", str(patch.report().body) == "Mars")
	return failed


func _check(name: String, ok: bool) -> int:
	if not ok:
		print("ring_handoff: FAIL %s" % name)
		return 1
	return 0
