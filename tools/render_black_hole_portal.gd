class_name RenderBlackHolePortal
extends Node3D

var output := "/tmp/astryx-humano"

func _ready() -> void:
	ProfileDir.isolate("render_black_hole_portal")
	get_window().mode = Window.MODE_WINDOWED
	get_window().size = Vector2i(1280,720)
	var cfg := ConfigFile.new()
	cfg.set_value("player","system",SystemDB.SAGITTARIUS_A)
	cfg.save(GameState.profile_path())
	DirAccess.make_dir_recursive_absolute(output)
	var main = load("res://scenes/Main.tscn").instantiate()
	add_child(main)
	main.set_process(false)
	main.dev_sites.go_core({"au":2.0,"polar":false})
	main.ship.relocate(Vector3(.585*Ephemeris.KM_PER_AU,0,0))
	main.ship.velocity = Vector3(20000000.0,0,0)
	FlightMode.dev_no_death = true
	main._process(.1)
	await capture("00_forced_capture")
	main.dev_sites.go_core({"au":2.0,"polar":false})
	var horizon := Ephemeris.body_radius_km("Sagittarius A*")
	main.ship.relocate(Vector3(horizon*.98,0,0))
	main.ship.velocity = Vector3(-100000,0,0)
	main.ship._update_camera(0.0)
	FlightMode.dev_no_death = false
	main._update_black_hole_horizon(0.0)
	var portal = main.black_hole_portal
	portal.set_process(false)
	portal.advance(1.0)
	await capture("01_entry")
	portal.advance(2.0)
	await capture("02_cubic_mist")
	portal.advance(2.2)
	await capture("03_loading")
	portal.advance(1.0)
	await capture("04_dinosaur_arcade")
	portal.runner.set_process(false)
	var jump := InputEventKey.new()
	jump.keycode = KEY_SPACE
	jump.pressed = true
	Input.parse_input_event(jump)
	await get_tree().process_frame
	if not portal.runner.running:
		push_error("Space did not reach the arcade")
		get_tree().quit(1)
		return
	portal.runner.advance(.18)
	await capture("05_human_jumping")
	get_window().size = Vector2i(640,360)
	await capture("06_small_screen")
	get_window().size = Vector2i(390,844)
	await capture("06_portrait")
	get_window().size = Vector2i(1280,720)
	portal.return_to_ship()
	main._process(0.0)
	await capture("07_return_2au")
	main.queue_free()
	await get_tree().process_frame
	print("black_hole_portal_render: OK ",output)
	get_tree().quit()

func capture(label: String) -> void:
	for frame in 4: await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(output.path_join(label+".png"))
