class_name TestStellarCoronaClipping
extends Node3D

func _ready() -> void:
	get_window().size = Vector2i(960, 540)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color.BLACK
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = .7
	var world := WorldEnvironment.new()
	world.environment = env
	add_child(world)
	var camera := Camera3D.new()
	camera.fov = 70
	camera.near = .001
	camera.position.z = 1.6
	camera.rotation_degrees = Vector3(-20, 20, 25)
	add_child(camera)
	camera.make_current()
	var look := PlanetGenerator.paint({"name":"Sun", "star":true}, 1.0)
	add_child(look.sphere)
	look.sphere.visible = true
	var output := OS.get_environment("CORONA_SHOT_DIR")
	if output.is_empty(): output = "/tmp/corona-clipping"
	DirAccess.make_dir_recursive_absolute(output)
	var shots: Array[Image] = []
	for far_plane in [1000.0, Ephemeris.CAM_RENDER_FAR_KM / Ephemeris.SUN_RADIUS_KM]:
		camera.far = far_plane
		for i in 4: await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var capture := get_viewport().get_texture().get_image()
		capture.save_png(output.path_join("reference.png" if shots.is_empty() else "game_range.png"))
		shots.append(capture)
	var changed := 0
	var total := 0
	for y in range(shots[0].get_height()):
		for x in range(shots[0].get_width()):
			var a := shots[0].get_pixel(x, y)
			var b := shots[1].get_pixel(x, y)
			if a.r < .85 and absf(a.r-b.r) > .02: changed += 1
			total += 1
	var fraction := float(changed)/total
	print("stellar_corona_clipping: changed fraction %.5f" % fraction)
	var failed := fraction > .001
	if failed: push_error("Game camera range cuts off the stellar corona")
	var sample := Vector2i(shots[1].get_width()*.38, shots[1].get_height()*.55)
	var blocker := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3.ONE*.06
	blocker.mesh = box
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(0, 0, .8)
	blocker.material_override = material
	add_child(blocker)
	var screen_sample := Vector2(sample) / Vector2(shots[1].get_size()) * get_viewport().get_visible_rect().size
	blocker.position = camera.project_position(screen_sample, .2)
	for i in 4: await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var blocked := get_viewport().get_texture().get_image()
	blocked.save_png(output.path_join("foreground_occlusion.png"))
	var pixel := blocked.get_pixelv(sample)
	var occluded := shots[1].get_pixelv(sample).r > .2 and pixel.r < .02 and pixel.b > .3
	print("stellar_corona_clipping: foreground occlusion ", occluded)
	if not occluded:
		failed = true
		push_error("Foreground geometry must block the corona")
	blocker.queue_free()
	# Skimming the photosphere with the star centre near the screen edge: the old
	# tangent-plane billboard crossed the near plane and the glow ended in a straight line.
	var game_far := Ephemeris.CAM_RENDER_FAR_KM / Ephemeris.SUN_RADIUS_KM
	camera.near = .05 / Ephemeris.SUN_RADIUS_KM
	camera.far = game_far
	camera.position = Vector3(0, 0, 1.32)
	camera.rotation_degrees = Vector3(0, -72, 0)
	# Bright exposure: in game the glow reads far out, where the tangent plane sits beyond the far plane.
	env.tonemap_exposure = 4.0
	var grazing_shots: Array[Image] = []
	for planes in [[.05 / Ephemeris.SUN_RADIUS_KM, game_far], [.001, 50.0]]:
		camera.near = planes[0]
		camera.far = planes[1]
		for i in 4: await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var capture := get_viewport().get_texture().get_image()
		capture.save_png(output.path_join("grazing_game_range.png" if grazing_shots.is_empty() else "grazing_reference.png"))
		grazing_shots.append(capture)
	changed = 0
	var glow_pixels := 0
	for y in range(grazing_shots[0].get_height()):
		for x in range(grazing_shots[0].get_width()):
			var a := grazing_shots[1].get_pixel(x, y)
			var b := grazing_shots[0].get_pixel(x, y)
			if a.r > .02: glow_pixels += 1
			if a.r < .85 and absf(a.r-b.r) > .01: changed += 1
	print("stellar_corona_clipping: grazing glow pixels %d, changed by game far plane %d" % [glow_pixels, changed])
	if glow_pixels < 2000 or changed > 50:
		failed = true
		push_error("Grazing view: game camera range cuts the corona")
	print("stellar_corona_clipping: ", "FAIL" if failed else "OK")
	get_tree().quit(1 if failed else 0)
