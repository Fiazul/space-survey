extends Node3D
## Same Amazon coordinates, altitude and camera heading at local noon and midnight.
## Uses the production globe/terrain/cloud/sky path; never reads/writes the profile.
class EarthWorld extends PlanetSystem:
	func _ready() -> void:
		_dot_tex = _make_dot_texture()
		_build_sun_sky()
		_surface = SurfacePatch.new()
		add_child(_surface)
		_cloud_layer = CloudLayer.new()
		add_child(_cloud_layer)
		_build_air_shell()
		var spec: Dictionary = Ephemeris.PLANETS.filter(func(p): return p.name == "Earth")[0].duplicate(true)
		spec.physical = true
		load_system([spec])

func _ready() -> void:
	get_window().mode = Window.MODE_WINDOWED
	get_window().size = Vector2i(1100,700)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color.BLACK
	add_child(env)
	var camera := Camera3D.new()
	camera.near = .05
	camera.far = Ephemeris.CAM_RENDER_FAR_KM
	camera.fov = 65
	add_child(camera)
	camera.current = true
	var world := EarthWorld.new()
	add_child(world)
	var local := DevSites.dir_for(-3,-60)
	var sampler := world.terrain_sampler_for("Earth")
	var radius := sampler.ground_radius_km(local,6371)+.3
	var utc := float(Time.get_unix_time_from_datetime_string("2026-09-23T00:00:00"))
	DirAccess.make_dir_recursive_absolute("/tmp/day-night")
	var captures: Array[Image] = []
	Ephemeris.rotation_clock.unix_s = utc+16*3600
	for phase in ["day","night"]:
		if phase == "night":
			Ephemeris.rotation_clock.advance(Ephemeris.rotation_clock.cycle_minutes*30.0)
		var body_basis := world.surface_basis("Earth")
		var off := body_basis*local*radius
		var up := body_basis*local
		var forward: Vector3 = body_basis*DevSites.surface_frame(local).north
		camera.look_at_from_position(Vector3.ZERO,forward*.75-up*.25,up)
		world.refresh(off,0,"Earth")
		for frame in 600:
			await get_tree().process_frame
			world.refresh(off,0,"Earth")
			if frame > 15 and world._surface.has_ground() and not world._surface._rebuild_busy():
				break
		await RenderingServer.frame_post_draw
		assert(world._surface.has_ground() and not world._surface._rebuild_busy(), "Terrain did not finish streaming")
		var capture := get_viewport().get_texture().get_image()
		captures.append(capture)
		capture.save_png("/tmp/day-night/amazon-%s.png" % phase)
		print("Amazon ",phase," ",Ephemeris.solar_state("Earth",local))
	# Sample the same ground pixels, excluding the sky. This catches both a blank
	# camera render and sunlight leaking through the planet onto trees at night.
	var brightness: Array[float] = []
	for capture in captures:
		var total := 0.0
		var count := 0
		for y in range(capture.get_height()/2,capture.get_height(),8):
			for x in range(0,capture.get_width(),8):
				total += capture.get_pixel(x,y).get_luminance()
				count += 1
		brightness.append(total/count)
	var ok := brightness[0] > .03 and brightness[0] > brightness[1]*1.5
	print("day_night_render: ","OK" if ok else "FAIL", " ground brightness ",brightness)
	world.queue_free()
	await get_tree().process_frame
	get_tree().quit(0 if ok else 1)
