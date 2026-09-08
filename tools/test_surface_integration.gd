extends Node3D
const G := preload("res://scripts/world/planet_generator.gd")
const SP := preload("res://scripts/world/surface_patch.gd")
const PS := preload("res://scripts/world/planet_system.gd")
const ShipScript := preload("res://scripts/flight/ship.gd")
const MainScript := preload("res://scripts/core/main.gd")
const HudScript := preload("res://scripts/ui/hud.gd")
var failures := 0

func _ready() -> void:
	for radius in [6371.0, 1737.4]:
		for alt in [7.0, 20.0]:
			var half_width := SP.ring_reach_km(3, SP.base_quad_km(alt, radius)) * 0.5
			check("terrain_reaches_horizon_%s_%s" % [radius, alt], half_width >= SP.horizon_km(alt, radius))
			var recipe := G.recipe_for({"name": "Earth" if radius > 2000.0 else "Moon"})
			check("bird_eye_band_open_%s_%s" % [radius, alt], G.band_ceiling_km(G.terrain_sampler(recipe)) > alt)
	var planets := PS.new()
	add_child(planets)
	var moon := Ephemeris.scene_pos("Moon")
	var local := Vector3.RIGHT * (1737.4 + 1.0)
	planets.refresh(moon + local, 0.0)
	var patch: Node3D = planets.get("_surface")
	check("moon_ground_centered_on_moon", patch.position.distance_to(planets.rel_of("Moon")) < 0.1)
	var moved := moon + local.rotated(Vector3.UP, 0.002)
	planets.refresh(moved, 0.5)
	var anchors: Array = patch.get("_ring_anchor")
	for anchor in anchors:
		check("moving_rings_share_one_origin", (anchor as Vector3).distance_to(anchors[0]) < 0.001)
	check("terrain_rotates_with_body", patch.basis.is_equal_approx(planets.surface_basis("Moon")))
	check("moon_clearance_is_local", planets.ground_altitude_km("Moon") < 3.0)
	var ship := ShipScript.new()
	add_child(ship)
	ship.terrain = G.terrain_sampler(G.recipe_for({"name": "Earth"}))
	var dir := Vector3(0.3, 0.4, 0.5).normalized()
	var touched := 0
	for i in 20:
		var n := dir.rotated(Vector3.UP, i * 0.19)
		ship.true_pos = n * (ship.terrain.ground_radius_km(n, 6371.0) - 0.01)
		ship.call("_newton_ground")
		if ship.surface_impact:
			touched += 1
		ship.surface_impact = false
	check("clamped_contact_always_lethal", touched == 20)
	# Exercise the real death entry point, not just the sampler or source text.
	var main := MainScript.new()
	var hud := HudScript.new()
	var flash := ColorRect.new()
	hud.set("_flash", flash)
	main.ship = ship
	main.planets = planets
	main.hud = hud
	ship.newton = true
	ship.nearest_name = "Earth"
	ship.true_pos = Vector3.RIGHT * 6371.0
	planets.refresh(ship.true_pos, 0.0)
	ship.surface_impact = true
	main.call("_update_skin_kill", 0.016)
	check("earth_impact_starts_death", bool(main.get("_skin_dying")) and ship.locked)
	check("impact_consumed_once", not ship.surface_impact)
	main.set("_skin_dying", false)
	ship.locked = false
	ship.nearest_name = "Moon"
	var ms := planets.terrain_sampler_for("Moon")
	var moon_local := Vector3.RIGHT * (ms.ground_radius_km(Vector3.RIGHT, 1737.4) - 0.1)
	ship.true_pos = moon + planets.surface_basis("Moon") * moon_local
	planets.refresh(ship.true_pos, 0.0)
	main.call("_update_skin_kill", 0.016)
	check("moon_contact_starts_death", bool(main.get("_skin_dying")) and ship.locked)
	check("death_discards_pre_respawn_sweep", str(main.get("_prev_body")).is_empty())
	main.free()
	flash.free()
	hud.free()
	ship.queue_free()
	planets.queue_free()
	await get_tree().process_frame
	print("surface_integration: ", "OK" if failures == 0 else "FAIL %d" % failures)
	get_tree().quit(0 if failures == 0 else 1)

func check(label: String, ok: bool) -> void:
	if not ok:
		failures += 1
		push_error("surface_integration: " + label)
