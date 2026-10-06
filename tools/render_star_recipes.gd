extends Node3D
## Same materials as gameplay, equal angular size to compare surface recipes.
func _ready() -> void:
	get_window().mode = Window.MODE_WINDOWED
	get_window().size = Vector2i(960,640)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(.003,.005,.012)
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = .7
	EnvironmentLook.apply(env)
	env.glow_enabled = true
	env.glow_intensity = .45
	env.glow_bloom = 0.0
	env.glow_hdr_threshold = 1.0
	var world := WorldEnvironment.new()
	world.environment = env
	add_child(world)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 9
	camera.position.z = 20
	add_child(camera)
	camera.make_current()
	var samples := [
		{"name":"Blue main sequence", "spectral":"O5V"},
		{"name":"Sirius", "spectral":"A1V"},
		{"name":"Sun", "spectral":"G2V"},
		{"name":"Proxima", "spectral":"M5.5V"},
		{"name":"Luhman 16", "spectral":"L8"},
		{"name":"Cool brown dwarf", "spectral":"T8"},
		{"name":"Red giant", "spectral":"K3III"},
		{"name":"Red supergiant", "spectral":"M2Iab"},
		{"name":"White dwarf", "spectral":"DQ6"},
		{"name":"Wolf–Rayet", "spectral":"WN5"},
		{"name":"Carbon star", "spectral":"C5"},
		{"name":"Pulsar", "stellar_type":"pulsar"},
	]
	var layer := CanvasLayer.new()
	add_child(layer)
	var spheres: Array[MeshInstance3D] = []
	for i in samples.size():
		var spec: Dictionary = samples[i].duplicate()
		spec["star"] = true
		var look := PlanetGenerator.paint(spec,.83)
		add_child(look.sphere)
		look.sphere.position = Vector3((i%4-1.5)*3.1, (1-i/4)*2.9,0)
		look.sphere.visible = true
		spheres.append(look.sphere)
		var label := Label.new()
		var s: Dictionary = look.recipe.stellar
		label.text = "%s · %s\n%.0f K / %.4f R☉" % [spec.name,s.spectral,s.temperature_k,s.radius_solar]
		label.add_theme_font_size_override("font_size",12)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.size = Vector2(320,50)
		label.position = camera.unproject_position(look.sphere.position+Vector3(0,-1.03,0))-Vector2(160,0)
		layer.add_child(label)
	for i in 4: await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var output := OS.get_environment("STAR_RECIPE_SHOT")
	if output.is_empty(): output = "/tmp/star-recipes.png"
	var capture := get_viewport().get_texture().get_image()
	var result := capture.save_png(output)
	if result != OK:
		push_error("Stellar capture failed: "+output)
		get_tree().quit(1)
		return
	print("stellar render: ", output)
	var failures := 0
	var means: Array[Color] = []
	for sphere in spheres:
		var center := camera.unproject_position(sphere.position)*Vector2(capture.get_size())/get_viewport().get_visible_rect().size
		var mean := Color(0,0,0,0)
		var count := 0
		for y in range(-24,25,3):
			for x in range(-24,25,3):
				mean += capture.get_pixel(int(center.x)+x,int(center.y)+y)
				count += 1
		means.append(mean/float(count))
	# Catch universal orange palettes and a washed-out solar disc using rendered pixels.
	if means[0].b <= means[0].r:
		push_error("Hot main sequence must retain its blue palette")
		failures += 1
	if means[2].g > .97 or absf(means[2].r-means[2].b) > .18 or means[2].b < .25:
		push_error("Sun must retain a warm-white, unclipped photosphere")
		failures += 1
	if means[3].r-means[3].g < .15 or means[3].g-means[3].b < .015:
		push_error("Proxima must have a red photosphere distinct from the Sun")
		failures += 1
	if means[5].r > means[2].r*.5:
		push_error("Cool brown dwarf must remain dim compared with the Sun")
		failures += 1
	print("stellar palette checks: ", "OK" if failures == 0 else "FAIL %d" % failures)
	if "--details" in OS.get_cmdline_user_args():
		layer.hide()
		camera.projection = Camera3D.PROJECTION_PERSPECTIVE
		camera.near = .001
		camera.far = 100
		camera.position.z = 1.5
		for sphere in spheres: sphere.visible = false
		for index in [2,3,7,9]:
			var sphere := spheres[index]
			var original := sphere.position
			sphere.position = Vector3.ZERO
			sphere.visible = true
			for i in 4: await get_tree().process_frame
			await RenderingServer.frame_post_draw
			var path := output.get_basename()+"-detail-%d.png" % index
			var saved := get_viewport().get_texture().get_image().save_png(path)
			if saved != OK:
				push_error("Stellar detail capture failed: "+path)
				failures += 1
			print("stellar detail: ", path)
			sphere.visible = false
			sphere.position = original
	get_tree().quit(1 if failures else 0)
