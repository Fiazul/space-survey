extends Node3D
func _ready() -> void:
	get_window().size = Vector2i(1200,850)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(.035,.05,.08)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(.75,.82,1)
	env.ambient_light_energy = .7
	var world := WorldEnvironment.new()
	world.environment = env
	add_child(world)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-50,-35,0)
	light.light_energy = 1.8
	add_child(light)
	var camera := Camera3D.new()
	camera.near = .001
	camera.far = 10
	camera.fov = 48
	add_child(camera)
	camera.current = true
	var site := {"id":"overview","name":"KENNEDY / LC-39A","operator":"NASA / SpaceX","parts":SurfaceFacility.parts()}
	var facility := SurfaceFacilities.build(site)
	add_child(facility)
	var ship := Ship.new()
	add_child(ship)
	ship._set_capture(false)
	ship.systems.gear_target = true
	ship.systems.step(2)
	var bottom := 0.0
	for foot in ship.systems.foot_points(): bottom = minf(bottom,foot.y)
	ship.position.y = -bottom
	camera.position = Vector3(.9,1.2,1.4)
	camera.look_at(Vector3.ZERO)
	DirAccess.make_dir_recursive_absolute("/tmp/ship-assistant")
	await _shot("landing-clearance")
	facility.visible = false
	ship.visible = false
	var stations := OrbitalStations.new()
	add_child(stations)
	for id in ["iss","tiangong"]:
		var state := stations.state_for(id)
		ship.anchor_off = state.position
		stations.update_for(ship,0)
		for node in stations._nodes.values(): node.get_node("Name").visible = false
		camera.position = Vector3(.10,.09,.15) if id == "iss" else Vector3(.07,.05,.09)
		camera.look_at(Vector3.ZERO)
		await _shot(id)
	ship.queue_free()
	stations.queue_free()
	await get_tree().process_frame
	get_tree().quit()
func _shot(label: String) -> void:
	for i in 5: await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("/tmp/ship-assistant/%s.png" % label)
