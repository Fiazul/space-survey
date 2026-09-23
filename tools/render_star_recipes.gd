extends Node3D
## Same materials as gameplay, equal angular size to compare surface recipes.
func _ready() -> void:
	get_window().mode = Window.MODE_WINDOWED
	get_window().size = Vector2i(1440,960)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(.003,.005,.012)
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = .7
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
	for i in samples.size():
		var spec: Dictionary = samples[i].duplicate()
		spec["star"] = true
		var look := PlanetGenerator.paint(spec,.83)
		add_child(look.sphere)
		look.sphere.position = Vector3((i%4-1.5)*3.1, (1-i/4)*2.9,0)
		look.sphere.visible = true
		var label := Label.new()
		var s: Dictionary = look.recipe.stellar
		label.text = "%s · %s\n%.0f K / %.4f R☉" % [spec.name,s.spectral,s.temperature_k,s.radius_solar]
		label.add_theme_font_size_override("font_size",16)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.size = Vector2(320,50)
		label.position = camera.unproject_position(look.sphere.position+Vector3(0,-1.03,0))-Vector2(160,0)
		layer.add_child(label)
	for i in 4: await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("/tmp/star-recipes.png")
	print("stellar render: /tmp/star-recipes.png")
	get_tree().quit()
