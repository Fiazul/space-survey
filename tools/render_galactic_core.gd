class_name RenderGalacticCore
extends Node3D

func _ready() -> void:
	ProfileDir.isolate("render_galactic_core")
	get_window().mode = Window.MODE_WINDOWED
	get_window().size = Vector2i(1280,720)
	var config := ConfigFile.new()
	config.set_value("player", "system", "sagittarius_a")
	config.save(GameState.profile_path())
	var main: Node = load("res://scenes/Main.tscn").instantiate()
	add_child(main)
	main.set_process(false)
	for i in 3: await get_tree().process_frame
	var output := OS.get_environment("CORE_SHOT_DIR")
	if output.is_empty(): output = "/tmp/astryx-core"
	DirAccess.make_dir_recursive_absolute(output)
	main.onboarding.set_process(false)
	var failures := 0
	var views := DevSitesPanel.core_views()
	var names := ["edge_7_9au", "close_2au", "polar_7_9au", "wide_79au", "overview_500ly"]
	for i in views.size():
		main.dev_sites.go_core(views[i])
		main._process(0.0)
		main.ship._set_capture(false)
		for frame in 5: await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var capture := get_viewport().get_texture().get_image()
		capture.save_png(output.path_join(names[i]+".png"))
		var plasma_pixels := 0
		for y in capture.get_height()/2:
			for x in range(200, capture.get_width()-200):
				var pixel := capture.get_pixel(x,y)
				if pixel.r > .35 and pixel.g > .12 and pixel.r > pixel.b*1.5: plasma_pixels += 1
		if i < 4 and plasma_pixels < (6 if i == 3 else 250):
			push_error("Black hole plasma missing in " + names[i])
			failures += 1
		print("galactic core plasma pixels: ", plasma_pixels)
		print("galactic core capture: ", names[i])
		if i == 1:
			# Hold the observer fixed: changing pixels must come from the physical
			# differential rotation, rather than camera or ship movement.
			Ephemeris.rotation_clock.advance(60.0)
			main._process(0.0)
			for frame in 5: await get_tree().process_frame
			await RenderingServer.frame_post_draw
			var rotated := get_viewport().get_texture().get_image()
			rotated.save_png(output.path_join("close_2au_rotated.png"))
			var changed := 0
			for y in range(80,360):
				for x in range(200,1080):
					var a := capture.get_pixel(x,y)
					var b := rotated.get_pixel(x,y)
					if absf(a.r-b.r)+absf(a.g-b.g)+absf(a.b-b.b) > .05: changed += 1
			if changed < 500:
				push_error("Accretion flow does not visibly rotate")
				failures += 1
			print("galactic core rotating plasma pixels: ", changed)
			await capture_angled_views(main,output)
	var background: BlackHoleBackground = main.planets.black_hole_background
	if background != null:
		var capture: Image = background.viewport.get_texture().get_image()
		capture.save_png(output.path_join("lens_background.png"))
		var stars := 0
		for y in capture.get_height():
			for x in capture.get_width():
				var pixel := capture.get_pixel(x,y)
				if maxf(pixel.r,maxf(pixel.g,pixel.b)) > .02: stars += 1
		if stars < 200:
			push_error("Lens background is empty")
			failures += 1
	main.dev_sites.go_system("sol")
	main.ship.face_toward(SystemDB.coord("sagittarius_a"))
	main._process(0.0)
	for i in 5: await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(output.path_join("from_sol.png"))
	print("galactic_core_render: ", "OK" if failures == 0 else "FAIL")
	get_tree().quit(1 if failures else 0)

func capture_angled_views(main: Node, output: String) -> void:
	main.ship.dev_speed = true
	main.ship.swap_ship(1)
	for view in [{"name":"close_2au_left","au":2.0,"yaw":-55.0,"roll":0.0},
		{"name":"close_2au_right_rolled","au":2.0,"yaw":55.0,"roll":33.0},
		{"name":"inside_flow_outward","au":.572,"yaw":160.0,"roll":0.0}]:
		main.dev_sites.go_core({"au":view.au,"polar":false})
		main._process(0.0)
		main.ship._update_authored_propulsion(1.0,1.0)
		main.ship._look_yaw = deg_to_rad(view.yaw)
		main.ship._look_yaw_s = main.ship._look_yaw
		main.ship._update_camera(0.0)
		main.ship.camera.rotate_object_local(Vector3.FORWARD,deg_to_rad(view.roll))
		for frame in 5: await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(output.path_join(str(view.name)+".png"))
