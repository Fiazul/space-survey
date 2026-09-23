class_name TestDocking
extends Node
var failures := 0
func check(label: String, ok: bool) -> void:
	print(("PASS " if ok else "FAIL ") + label)
	if not ok:
		failures += 1
func _ready() -> void:
	var main := preload("res://scripts/core/main.gd").new()
	add_child(main)
	main.set_process(false)
	main.ship.set_physics_process(false)
	main._land_beside_dock()
	main.props.dock_name = ""
	main._update_dock_ui()
	check("unnamed existing station permits docking", main._dock_in_range)
	var event := InputEventKey.new()
	event.pressed = true
	event.keycode = KEY_F
	main._input(event)
	check("F docks at orbital hangar", main.docked)
	event.keycode = KEY_2
	main._input(event)
	check("number key changes ship", main.ship.current_index() == 1)
	event.keycode = KEY_F
	main._input(event)
	check("F undocks", not main.docked)
	event.keycode = KEY_B
	main._input(event)
	check("B lowers gear", main.ship.systems.gear_target)
	main.ship.systems.step(2.0)
	event.keycode = KEY_R
	main._input(event)
	check("gear interlocks weapon deployment", not main.ship.systems.weapons_target)
	event.keycode = KEY_B
	main._input(event)
	main.ship.systems.step(2.0)
	event.keycode = KEY_R
	main._input(event)
	check("orbital hardpoints remain locked", not main.ship.systems.weapons_target)
	main.ship.anchor_off = Vector3.UP * 6372.0
	main.ship.nearest_name = "Earth"
	main._input(event)
	main.ship.systems.step(1.0)
	check("R deploys hardpoints", main.ship.systems.weapons_ready())
	var site := {"body": "Earth", "mode": "surface", "lat_deg": 23.81, "lon_deg": 90.41, "alt_km": .4}
	main.dev_sites.go(site)
	var body_basis: Basis = main.planets.surface_basis("Earth")
	var local_dir: Vector3 = body_basis.inverse() * main.ship.anchor_off.normalized()
	check("Dhaka teleport respects Earth rotation", local_dir.distance_to(DevSites.dir_for(23.81, 90.41)) < .000001)
	check("Dhaka ship upright relative to surface", main.ship.transform.basis.y.dot(main.ship.anchor_off.normalized()) > .999)
	main.props.has_dock = false
	main._update_dock_ui()
	check("missing station cannot dock", not main._dock_in_range)
	main.queue_free()
	await get_tree().process_frame
	get_tree().quit(1 if failures else 0)
