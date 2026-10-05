class_name RenderStarTeleport
extends Node3D

func _ready() -> void:
	ProfileDir.isolate("render_star_teleport")
	get_window().mode = Window.MODE_WINDOWED
	get_window().size = Vector2i(1280,720)
	var main: Node = load("res://scenes/Main.tscn").instantiate()
	add_child(main)
	for i in 30: await get_tree().process_frame
	main.set_process(false)
	var output := OS.get_environment("STAR_TELEPORT_SHOTS")
	if output.is_empty(): output = "/tmp/star-teleport"
	DirAccess.make_dir_recursive_absolute(output)
	var failures := 0
	for id in [SystemDB.SOL,SystemDB.PROXIMA,"wolf_359","sirius","luhman_16","gliese_440"]:
		var key := InputEventKey.new()
		key.keycode = KEY_P
		key.ctrl_pressed = true
		key.pressed = true
		Input.parse_input_event(key)
		await get_tree().process_frame
		if not main.dev_sites._open:
			push_error("Ctrl+P did not open the star picker")
			failures += 1
			break
		main.dev_sites._filter.text = id
		main.dev_sites._refresh()
		await get_tree().process_frame
		var picked := false
		for row in main.dev_sites._list.get_children():
			if row is Button:
				row.pressed.emit()
				picked = true
				break
		var star := Ephemeris.primary_star
		if not picked or main.current_system != id or main.ship.anchor_name != star or main.ship.nearest_name != star:
			push_error("Star picker arrival failed: "+id)
			failures += 1
			continue
		main._process(0.0)
		main.hud._lore.hide()
		main.ship._set_capture(false)
		for i in 8: await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var path := output.path_join(id+".png")
		var result := get_viewport().get_texture().get_image().save_png(path)
		if result != OK:
			push_error("Star teleport capture failed: "+path)
			failures += 1
		print("star teleport capture: %s -> %s, %.2f radii, %s" % [
			id,star,main.ship.anchor_off.length()/Ephemeris.body_radius_km(star),path])
	print("star_teleport_render: ","OK" if failures == 0 else "FAIL %d" % failures)
	get_tree().quit(1 if failures else 0)
