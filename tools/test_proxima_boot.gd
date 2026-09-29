class_name TestProximaBoot
extends Node
## Boots the real main, arrives in generated Proxima through main._arrive and
## drives 30 s of main._process at 1/60: Newton on, anchored to a generated
## world, falling under its gravity. Needs ASTRYX_PROFILE_DIR (isolated here).
## godot --headless tools/test_proxima_boot.tscn  -> "proxima_boot: OK"
const DT := 1.0 / 60.0
var failures := 0


func check(name: String, ok: bool) -> void:
	if not ok:
		failures += 1
		print("proxima_boot: FAIL ", name)


func _ready() -> void:
	ProfileDir.isolate("test_proxima_boot")
	var main: Node = preload("res://scripts/core/main.gd").new()
	add_child(main)
	main.set_process(false)
	await get_tree().process_frame
	main._arrive(SystemDB.PROXIMA)
	var ship: Ship = main.ship
	var worlds := []
	for p in Ephemeris.live_worlds():
		worlds.append(str(p.name))
	print("proxima_boot: anchor=%s system=%s worlds=%s" % [ship.anchor_name, main.current_system, worlds])
	check("anchor_generated", ship.anchor_name in worlds and not SolEphemeris.worlds().any(func(p): return p.name == ship.anchor_name))
	check("proxima_system", Ephemeris.system_id == SystemDB.PROXIMA and Ephemeris.primary_star == "Proxima Centauri")
	ship.velocity = Vector3.ZERO
	var anchor := ship.anchor_name
	var r0 := ship.anchor_distance_km()
	# Newton pull in the anchor's free-falling frame (world + star tidal residue),
	# radial part, as the ship integrates it.
	var g_sum := -(ship.call("_newton_g") as Vector3).dot(ship.anchor_off.normalized())
	for i in 1800:
		main._process(DT)
	var r1 := ship.anchor_distance_km()
	var radial := ship.velocity.dot(ship.anchor_off.normalized())
	var g := Ephemeris.gm(anchor) / (r0 * r0)
	print("proxima_boot: 30 s  r %.4f -> %.4f km  fell %.4f km (frame Newton predicts %.4f, world alone %.4f)  v_radial %.6f km/s  anchor=%s nearest=%s" % [
		r0, r1, r0 - r1, 0.5 * g_sum * 900.0, 0.5 * g * 900.0, radial, ship.anchor_name, main.planets.nearest_name])
	check("still_anchored_generated", ship.anchor_name == anchor)
	check("falls", r1 < r0 and radial < 0.0)
	check("fall_is_newton", absf((r0 - r1) / (0.5 * g_sum * 900.0) - 1.0) < 0.05)
	# The star's direct pull is cancelled by the frame; only its tidal residue is
	# left, so the fall is the world's GM/r² to well under 1 %.
	check("fall_is_world_gm_over_r2", absf((r0 - r1) / (0.5 * g * 900.0) - 1.0) < 0.01)
	main.queue_free()
	await get_tree().process_frame
	print("proxima_boot: ", "OK" if failures == 0 else "FAIL %d" % failures)
	get_tree().quit(0 if failures == 0 else 1)
