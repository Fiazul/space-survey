class_name RenderStarTeleport
extends Node3D

func _ready() -> void:
	ProfileDir.isolate("render_star_teleport")
	get_window().mode = Window.MODE_WINDOWED
	get_window().size = Vector2i(800,450)
	if OS.get_environment("STAR_DOUBLE_SIDED") == "1":
		var shader: Shader = PlanetGenerator.COOK_SHADER
		shader.set_code(shader.code.replace("cull_back", "cull_disabled"))
	var main: Node = load("res://scenes/Main.tscn").instantiate()
	add_child(main)
	for i in 30: await get_tree().process_frame
	main.set_process(false)
	var output := OS.get_environment("STAR_TELEPORT_SHOTS")
	if output.is_empty(): output = "/tmp/star-teleport"
	DirAccess.make_dir_recursive_absolute(output)
	var failures := 0
	var systems := [SystemDB.SOL,SystemDB.PROXIMA,"wolf_359","sirius","luhman_16","gliese_440"]
	var requested := OS.get_environment("STAR_TELEPORT_SYSTEMS")
	if not requested.is_empty():
		systems = Array(requested.split(",", false))
	for id in systems:
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
		var primary_body: Dictionary = {}
		for body in main.planets._bodies:
			if body.name == star: primary_body = body
		var glare_reference: Image = null
		var point: Sprite3D = primary_body.dot
		if id in ["arcturus", "aldebaran"] and point.visible:
			push_error("Resolved giant has point glare: " + id)
			failures += 1
		if id in ["vela_pulsar", "crab_pulsar"]:
			if not point.visible:
				push_error("Unresolved neutron core has no point glare: " + id)
				failures += 1
			else:
				point.visible = false
				for i in 4: await get_tree().process_frame
				await RenderingServer.frame_post_draw
				glare_reference = get_viewport().get_texture().get_image()
				point.visible = true
				for i in 4: await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var path := output.path_join(id+".png")
		var capture := get_viewport().get_texture().get_image()
		if glare_reference != null:
			var metrics := _glare_metrics(capture, glare_reference, main.ship.camera, point)
			print("star point glare: ", id, " ", metrics)
			if capture.get_size() != Vector2i(800,450) or not metrics.in_frame \
					or metrics.changed < 2 or metrics.changed > 20 or metrics.outside != 0 or metrics.blue_white < 2:
				push_error("Unresolved core needs a localized blue-white point (2..20 pixels within 6px): " + id)
				failures += 1
		var result := capture.save_png(path)
		if result != OK:
			push_error("Star teleport capture failed: "+path)
			failures += 1
		if id in [SystemDB.SOL, "sirius"]:
			var disc: MeshInstance3D = main.planets._sun_sky
			for body in main.planets._bodies:
				if body.name == star and body.sphere.visible:
					disc = body.sphere
			var metrics := _disc_metrics(capture, main.ship.camera, disc)
			print("star disc integrity: ", id, " ", metrics)
			if metrics.samples < 50 or metrics.dark_fraction > .02:
				push_error("Far-side triangles corrupt the stellar photosphere: " + id)
				failures += 1
		print("star teleport capture: %s -> %s, %.2f radii, %s" % [
			id,star,main.ship.anchor_off.length()/Ephemeris.body_radius_km(star),path])
	print("star_teleport_render: ","OK" if failures == 0 else "FAIL %d" % failures)
	get_tree().quit(1 if failures else 0)

func _glare_metrics(capture: Image, reference: Image, camera: Camera3D, point: Sprite3D) -> Dictionary:
	var pixel_scale := Vector2(capture.get_size()) / get_viewport().get_visible_rect().size
	var center := camera.unproject_position(point.global_position) * pixel_scale
	var in_frame := not camera.is_position_behind(point.global_position) \
		and Rect2(Vector2.ZERO, Vector2(capture.get_size())).grow(-12.0).has_point(center)
	var changed := 0
	var outside := 0
	var blue_white := 0
	for y in range(maxi(0, int(center.y) - 12), mini(capture.get_height(), int(center.y) + 13)):
		for x in range(maxi(0, int(center.x) - 12), mini(capture.get_width(), int(center.x) + 13)):
			var delta := capture.get_pixel(x,y) - reference.get_pixel(x,y)
			if maxf(absf(delta.r), maxf(absf(delta.g), absf(delta.b))) <= .01: continue
			if (Vector2(x,y) + Vector2(.5,.5)).distance_to(center) > 6.0:
				outside += 1
				continue
			changed += 1
			if delta.r > .01 and delta.g > .01 and delta.b > .01 \
					and delta.b >= delta.r * .9 and delta.g >= delta.r * .9:
				blue_white += 1
	return {"center":center, "in_frame":in_frame, "changed":changed, "outside":outside, "blue_white":blue_white}

func _disc_metrics(capture: Image, camera: Camera3D, disc: MeshInstance3D) -> Dictionary:
	var pixel_scale := Vector2(capture.get_size()) / get_viewport().get_visible_rect().size
	var relative := disc.global_position - camera.global_position
	var radius: float = disc.mesh.radius * disc.global_basis.get_scale().x
	var center := camera.unproject_position(disc.global_position) * pixel_scale
	var edge_dir := relative.normalized().rotated(camera.global_basis.y, asin(radius / relative.length()))
	var edge := camera.unproject_position(camera.global_position + edge_dir * relative.length()) * pixel_scale
	var reach := center.distance_to(edge) * .6
	var values: Array[float] = []
	for y in range(maxi(0, int(center.y - reach)), mini(capture.get_height(), int(center.y + reach)), 2):
		for x in range(maxi(0, int(center.x - reach)), mini(capture.get_width(), int(center.x + reach)), 2):
			if Vector2(x, y).distance_to(center) > reach:
				continue
			var pixel := capture.get_pixel(x, y)
			values.append(pixel.r * .2126 + pixel.g * .7152 + pixel.b * .0722)
	if values.is_empty():
		return {"samples": 0, "dark_fraction": 1.0}
	values.sort()
	var bright := values[int(values.size() * .75)]
	var dark := values.filter(func(value): return value < bright * .8).size()
	return {"samples": values.size(), "dark_fraction": float(dark) / values.size()}
