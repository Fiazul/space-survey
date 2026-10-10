class_name TestBlackHolePortal
extends Node

var failures := 0

func check(label: String, ok: bool) -> void:
	if not ok:
		failures += 1
		push_error("black_hole_portal: " + label)

func _ready() -> void:
	ProfileDir.isolate("test_black_hole_portal")
	var cfg := ConfigFile.new()
	cfg.set_value("player","system",SystemDB.SAGITTARIUS_A)
	cfg.save(GameState.profile_path())
	var main = load("res://scenes/Main.tscn").instantiate()
	add_child(main)
	main.set_process(false)
	check("root provides a portal return", main.has_method("return_from_black_hole_portal"))
	if not main.has_method("return_from_black_hole_portal"):
		main.free()
		get_tree().quit(1)
		return
	var ship: Ship = main.ship
	for child in main.get_children():
		if child is Node3D and child.scene_file_path == "res://assets/Astronaut.glb":
			check("scene-authored astronaut stays out of the core", not child.visible)
	var finn: Dictionary = main.props._items.filter(func(item): return item.name == "Finn")[0]
	check("saved core boot does not show the Sol astronaut", main.props.current_system == SystemDB.SAGITTARIUS_A and not finn.holder.visible)
	main.dev_sites.go_core({"au":2.0,"polar":false})
	finn.holder.visible = true
	main.props.update(ship,0.0)
	check("inactive Sol astronaut cannot leak into the core", not finn.holder.visible)
	ship._set_capture(true)
	var capture_mode := Input.get_mouse_mode()
	var canvas: CanvasLayer = main.hud._canvas
	var canvas_visible := canvas.visible
	var music_player: AudioStreamPlayer = main.music._music
	var music_paused := music_player.stream_paused if music_player != null else true
	main.combat.player_hp = 42.0
	var hull: int = ship.current_index()
	var velocity := Vector3(-2000.0, 0.0, 0.0)
	var horizon := Ephemeris.body_radius_km("Sagittarius A*")
	ship.relocate(Vector3(horizon*.98,0,0))
	ship.velocity = velocity
	FlightMode.dev_no_death = false
	main._update_black_hole_horizon(0.0)
	var portal = main.black_hole_portal
	check("horizon opens the portal", portal != null)
	if portal == null:
		get_tree().quit(1)
		return
	portal.set_process(false)
	check("entry preserves hull and momentum", not main._skin_dying and not ship.locked and ship.velocity == velocity and main.combat.player_hp == 42.0)
	check("flight inputs and HUD suspend", ship.process_mode == Node.PROCESS_MODE_DISABLED and not canvas.visible)
	check("only the ship stays visible during descent", ship.visible and not main.props.visible and not main.planets.visible)
	if music_player != null: check("space music pauses", music_player.stream_paused)
	main._update_black_hole_horizon(.1)
	check("entry cannot duplicate the portal", main.black_hole_portal == portal)
	var before := ship.anchor_off
	portal.advance(.2)
	check("ship continues through the interior", ship.anchor_off.x < before.x and ship.velocity == velocity)
	var held := ship.anchor_off
	main._process(.2)
	check("space frame loop is held", ship.anchor_off == held)
	main._save_profile()
	cfg.load(GameState.profile_path())
	var saved: Vector3 = cfg.get_value("player","off",Vector3.ZERO)
	check("portal saves a safe 2 AU orbit", absf(saved.length()/Ephemeris.KM_PER_AU-2.0) < .00001)
	portal.advance(5.0)
	check("cinematic reaches loading", portal.stage == portal.Stage.LOADING)
	portal.advance(1.2)
	check("loading reveals only the dinosaur game", portal.stage == portal.Stage.PLAYING and not main.visible and portal.runner != null)
	portal.runner.jump()
	portal.runner.advance(.1)
	check("the screen game is playable", portal.runner.player_y > 0.0)
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	Input.parse_input_event(escape)
	await get_tree().process_frame
	check("Escape returns at exactly 2 AU", main.black_hole_portal == null and absf(ship.anchor_off.length()/Ephemeris.KM_PER_AU-2.0) < .00001)
	check("safe return has circular velocity", ship.velocity.is_equal_approx(main._park_velocity()) and absf(ship.velocity.dot(ship.anchor_off.normalized())) < .1)
	check("return preserves the hull and restores controls", main.visible and ship.process_mode != Node.PROCESS_MODE_DISABLED and ship.current_index() == hull and main.combat.player_hp == 42.0 and canvas.visible == canvas_visible)
	check("return restores mouse steering capture", ship._mouse_captured and Input.get_mouse_mode() == capture_mode)
	if music_player != null: check("music pause state restores", music_player.stream_paused == music_paused)
	check("portal saves the return checkpoint", cfg.get_value("player","system","") == SystemDB.SAGITTARIUS_A)
	await get_tree().process_frame
	ship.horizon_crossed = true
	ship.relocate(Vector3(horizon*3.0,0,0))
	main._update_black_hole_horizon(0.0)
	check("swept crossings outside the endpoint still enter", main.black_hole_portal != null)
	if main.black_hole_portal != null:
		var buttons: Array = main.black_hole_portal.find_children("*","Button",true,false)
		buttons[0].pressed.emit()
		check("visible return button exits during descent", main.black_hole_portal == null)
	await get_tree().process_frame
	FlightMode.dev_no_death = true
	ship.relocate(Vector3(horizon*.98,0,0))
	main._update_black_hole_horizon(0.0)
	check("developer no-death cannot bypass the portal", main.black_hole_portal != null)
	if main.black_hole_portal != null: main.black_hole_portal.return_to_ship()
	FlightMode.dev_no_death = false
	check("picker provides a direct Humano entry", main.dev_sites.has_method("go_humano"))
	if main.dev_sites.has_method("go_humano"):
		check("picker starts the portal", main.dev_sites.go_humano())
		main.black_hole_portal.return_to_ship()
	ship.relocate(Vector3(horizon*.98,0,0))
	var drone: AudioStreamPlayer = GameAudio._hole_drone
	var drone_playing := drone.playing
	drone.play()
	drone.stream_paused = false
	main._update_black_hole_horizon(0.0)
	check("teardown fixture enters an active portal", main.black_hole_portal != null and drone.stream_paused)
	main.free()
	check("owner teardown restores persistent audio", not drone.stream_paused)
	if not drone_playing: drone.stop()
	print("black_hole_portal: ", "OK" if failures == 0 else "FAIL %d" % failures)
	get_tree().quit(1 if failures else 0)
