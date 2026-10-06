extends Node3D

func _ready() -> void:
	get_window().mode = Window.MODE_WINDOWED
	get_window().size = Vector2i(800, 450)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(.003, .005, .012)
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = .7
	EnvironmentLook.apply(env)
	env.glow_enabled = true
	env.glow_normalized = true
	env.glow_intensity = .45
	env.glow_strength = .85
	env.glow_bloom = 0.0
	env.glow_hdr_threshold = 1.0
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	env.set_glow_level(1, .8)
	env.set_glow_level(2, .4)
	env.set_glow_level(3, .15)
	env.set_glow_level(5, 0.0)
	var world := WorldEnvironment.new()
	world.environment = env
	add_child(world)
	var camera := Camera3D.new()
	camera.fov = 70
	camera.near = .001
	camera.far = 1000
	add_child(camera)
	camera.make_current()
	var look := PlanetGenerator.paint({"name":"Sun", "star":true}, 1.0)
	add_child(look.sphere)
	look.sphere.visible = true
	var output := OS.get_environment("SUN_SHOT_DIR")
	if output.is_empty(): output = "/tmp/sun-approach"
	DirAccess.make_dir_recursive_absolute(output)
	var failures := 0
	var metrics: Dictionary = {}
	for shot in [
		{"name":"far", "distance":215.0, "yaw":0.0},
		{"name":"approach", "distance":4.0, "yaw":0.0},
		{"name":"close", "distance":1.5, "yaw":0.0},
		{"name":"limb", "distance":1.2, "yaw":50.0},
		{"name":"grazing", "distance":1.02, "yaw":75.0},
		{"name":"photosphere", "distance":1.001, "yaw":85.0},
		{"name":"polar_limb", "distance":1.001, "yaw":0.0, "pitch":90.0},
	]:
		camera.position = Vector3(0, 0, shot.distance)
		camera.rotation = Vector3(deg_to_rad(float(shot.get("pitch", 0.0))), deg_to_rad(shot.yaw), 0)
		for i in 8: await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var path := output.path_join(str(shot.name)+".png")
		var capture := get_viewport().get_texture().get_image()
		var result := capture.save_png(path)
		if result != OK:
			push_error("Sun capture failed: "+path)
			get_tree().quit(1)
			return
		print("sun approach: ", path)
		var peak := 0.0
		for y in range(capture.get_height()):
			for x in range(capture.get_width()):
				var pixel := capture.get_pixel(x, y)
				peak = maxf(peak, _luminance(pixel))
		if peak < .65:
			failures += 1
			push_error("Sun must remain luminous in %s view (peak %.3f)" % [shot.name, peak])
		metrics[shot.name] = {"peak": peak}
		# Resolved, centered discs only: far spans few pixels and grazing views expose
		# limb/corona rather than the photosphere interior.
		if shot.name in ["approach", "close"]:
			var surface := _surface_metrics(capture, camera)
			metrics[shot.name].merge(surface)
			print("sun surface %s: %s" % [shot.name, JSON.stringify(surface)])
			if int(surface.samples) < 100 or float(surface.range_90_10) < .025 or float(surface.local_detail) < .0015:
				failures += 1
				push_error("Sun photosphere lost resolved surface contrast in %s" % shot.name)
			if float(surface.clipped_fraction) > .02 or float(surface.mean) > .94:
				failures += 1
				push_error("Sun photosphere is clipped/washed out in %s" % shot.name)
			if absf(float(surface.warm_color)) > .18:
				failures += 1
				push_error("Sun photosphere must retain a warm-white visible color in %s" % shot.name)
	var report := FileAccess.open(output.path_join("metrics.json"), FileAccess.WRITE)
	if report == null:
		failures += 1
		push_error("Could not write Sun image metrics")
	else:
		report.store_string(JSON.stringify(metrics, "\t"))
	print("sun_approach: ", "OK" if failures == 0 else "FAIL %d" % failures)
	get_tree().quit(1 if failures else 0)

func _luminance(pixel: Color) -> float:
	return pixel.r*.2126 + pixel.g*.7152 + pixel.b*.0722

func _surface_metrics(capture: Image, camera: Camera3D) -> Dictionary:
	var values: Array[float] = []
	var sum := 0.0
	var detail := 0.0
	var clipped := 0
	var warm_color := 0.0
	var origin := camera.global_position
	var viewport_scale := camera.get_viewport().get_visible_rect().size / Vector2(capture.get_size())
	for y in range(3, capture.get_height()-3, 3):
		for x in range(3, capture.get_width()-3, 3):
			var ray := camera.project_ray_normal(Vector2(x+.5, y+.5) * viewport_scale)
			var along := origin.dot(ray)
			var discriminant := along*along-origin.length_squared()+1.0
			if discriminant <= 0.0: continue
			var distance := -along-sqrt(discriminant)
			if distance <= 0.0: continue
			var normal := (origin+ray*distance).normalized()
			if -normal.dot(ray) < .80: continue
			var pixel := capture.get_pixel(x, y)
			var value := _luminance(pixel)
			warm_color += pixel.r-pixel.b
			values.append(value)
			sum += value
			if pixel.g >= .99 or minf(pixel.r, minf(pixel.g, pixel.b)) >= .98:
				clipped += 1
			# A symmetric local residual rejects a smooth limb gradient: a shaded
			# but featureless disc cannot pass as granulation. Test exported pixels.
			var neighbors := (_luminance(capture.get_pixel(x-2,y)) + _luminance(capture.get_pixel(x+2,y))
				+ _luminance(capture.get_pixel(x,y-2)) + _luminance(capture.get_pixel(x,y+2)))*.25
			detail += absf(value-neighbors)
	if values.is_empty():
		return {"samples": 0, "range_90_10": 0.0, "local_detail": 0.0, "clipped_fraction": 0.0, "mean": 0.0, "warm_color": 0.0}
	values.sort()
	var count := values.size()
	return {"samples": count, "range_90_10": values[int((count-1)*.9)]-values[int((count-1)*.1)],
		"local_detail": detail/count, "clipped_fraction": float(clipped)/count, "mean": sum/count, "warm_color": warm_color/count}
