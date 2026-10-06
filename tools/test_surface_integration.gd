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
	# One kilometre above the actual terrain, independent of the Moon's current
	# spin phase. A kilometre above mean radius can be >3 km above a basin.
	var moon_sampler := planets.terrain_sampler_for("Moon")
	var local_dir := planets.surface_basis("Moon").inverse() * Vector3.RIGHT
	var local := Vector3.RIGHT * (moon_sampler.ground_radius_km(local_dir, 1737.4) + 1.0)
	planets.refresh(moon + local, 0.0)
	var patch: Node3D = planets.get("_surface")
	check("moon_ground_centered_on_moon", patch.position.distance_to(planets.rel_of("Moon")) < 0.1)
	var moved_dir := Vector3.RIGHT.rotated(Vector3.UP, 0.002)
	var moved_local := planets.surface_basis("Moon").inverse() * moved_dir
	var moved := moon + moved_dir * (moon_sampler.ground_radius_km(moved_local, 1737.4) + 1.0)
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
	check("clamped_contact_detected", touched == 20)
	# Exercise the real non-lethal collision path, including non-anchor bodies.
	var main := MainScript.new()
	var hud := HudScript.new()
	var flash := ColorRect.new()
	hud.set("_flash", flash)
	main.ship = ship
	main.planets = planets
	main.hud = hud
	ship.nearest_name = "Earth"
	ship.true_pos = Vector3.RIGHT * 6371.0
	planets.refresh(ship.true_pos, 0.0)
	ship.surface_impact = true
	main.call("_update_skin_kill", 0.016)
	check("earth_impact_is_nonlethal", not bool(main.get("_skin_dying")) and not ship.locked)
	check("earth_hull_stays_outside", planets.ground_altitude_km("Earth") >= ship.surface_clearance_km() - 0.002)
	check("contact_does_not_disable_controls", not ship.locked)
	main.set("_skin_dying", false)
	ship.locked = false
	ship.nearest_name = "Moon"
	var ms := planets.terrain_sampler_for("Moon")
	var moon_local := Vector3.RIGHT * (ms.ground_radius_km(Vector3.RIGHT, 1737.4) - 0.1)
	ship.true_pos = moon + planets.surface_basis("Moon") * moon_local
	planets.refresh(ship.true_pos, 0.0)
	main.call("_update_skin_kill", 0.016)
	check("moon_contact_is_nonlethal", not bool(main.get("_skin_dying")) and not ship.locked)
	# Anchored at Earth, the offset near the Moon rounds to a 31 m float32 step.
	var moon_up := -planets.rel_of("Moon").normalized()
	var moon_tolerance := maxf(0.002, ulp_km(ship.anchor_off))
	check("non_anchor_moon_hull_stays_outside", planets.ground_altitude_km("Moon") >= ship.surface_clearance_km(moon_up) - moon_tolerance)
	check("contact_tracks_correct_body", str(main.get("_prev_body")) == "Moon")
	FlightMode.dev_no_death = true
	ship.true_pos = moon + planets.surface_basis("Moon") * moon_local
	planets.refresh(ship.true_pos, 0.0)
	main.call("_update_skin_kill", 0.016)
	check("nodeath_keeps_solidity", planets.ground_altitude_km("Moon") >= ship.surface_clearance_km(-planets.rel_of("Moon").normalized()) - moon_tolerance)
	FlightMode.dev_no_death = false
	# Real Newton substeps must support a ship at rest while gravity and the
	# Earth's co-rotation still run. This catches integration-only sinking.
	ship.nearest_name = "Earth"
	ship.set_anchor("Earth")
	ship.terrain = planets.terrain_sampler_for("Earth")
	ship.set_terrain_frame(planets.surface_basis("Earth"), planets.surface_angle("Earth"))
	var sea_dir := Vector3(-0.8660254, 0.0, -0.5).normalized()
	ship.anchor_off = ship.terrain_basis * sea_dir * (6371.0 + ship.surface_clearance_km() + 0.002)
	ship.velocity = Vector3.ZERO
	for _frame in 180:
		ship._newton_advance(1.0 / 60.0)
		# Measured through the double-precision frame: a float32 Basis*anchor_off
		# at Earth radius carries about a metre of its own rounding.
		var agl := ship.terrain.alt_above_ground_km(ship.terrain_local(ship.anchor_off, true), 6371.0)
		check("newton_rest_does_not_sink", agl >= ship.surface_clearance_km() - 0.001)
	check("newton_rest_stays_slow", ship.velocity.length() < 0.003)
	# A same-body teleport must not collide with the segment from its old site.
	ship.true_pos = Vector3.UP * 6500.0
	planets.refresh(ship.anchor_off, 0.0, ship.anchor_name)
	main.call("_update_skin_kill", 0.016)
	var teleport_target := Vector3.DOWN * 6500.0
	ship.true_pos = teleport_target
	planets.refresh(ship.anchor_off, 0.0, ship.anchor_name)
	main.call("_update_skin_kill", 0.016)
	check("teleport_does_not_sweep_through_planet", ship.anchor_off.distance_to(teleport_target) < 0.01)
	# The spin angle main hands the ship must build the same basis it renders
	# with. arcade_surface_angle_is_nan deleted 2026-09-29: no arcade spheres remain;
	# every generated world is an ephemeris spin, checked below on a HYG system.
	var earth_angle := planets.surface_angle("Earth")
	check("physical_surface_angle_matches_basis", is_finite(earth_angle) \
		and Basis(Vector3.UP, earth_angle).is_equal_approx(planets.surface_basis("Earth")))
	check("unknown_body_surface_angle_is_nan", is_nan(planets.surface_angle("NoSuchBody")))
	Ephemeris.switch_system("tau_ceti")
	planets.load_system(SystemDB.bodies("tau_ceti"))
	var world := Ephemeris.spawn_body()
	var world_angle := planets.surface_angle(world)
	check("generated_surface_angle_matches_basis", is_finite(world_angle) \
		and Basis(Vector3.UP, world_angle).is_equal_approx(planets.surface_basis(world)))
	Ephemeris.switch_system(SystemDB.SOL)
	planets.load_system(SystemDB.bodies(SystemDB.SOL))
	main.free()
	flash.free()
	hud.free()
	ship.queue_free()
	planets.queue_free()
	await get_tree().process_frame
	print("surface_integration: ", "OK" if failures == 0 else "FAIL %d" % failures)
	get_tree().quit(0 if failures == 0 else 1)

func ulp_km(offset: Vector3) -> float:
	return pow(2.0, floor(log(offset.length())/log(2.0)) - 23.0)

func check(label: String, ok: bool) -> void:
	if not ok:
		failures += 1
		push_error("surface_integration: " + label)
