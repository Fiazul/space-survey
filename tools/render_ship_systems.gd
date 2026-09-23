extends Node3D
## Repeatable visual inspection of fitted procedural rigs on every playable hull.
func _ready() -> void:
	get_window().size = Vector2i(1100, 800)
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(.04, .055, .08)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(.8, .87, 1)
	environment.ambient_light_energy = .65
	var world := WorldEnvironment.new()
	world.environment = environment
	add_child(world)
	for angle in [Vector3(-35, -30, 0), Vector3(45, 135, 0)]:
		var light := DirectionalLight3D.new()
		light.rotation_degrees = angle
		light.light_energy = 1.8
		add_child(light)
	var ship := Ship.new()
	add_child(ship)
	var plasma := PlasmaProjectiles.new()
	add_child(plasma)
	var camera := Camera3D.new()
	camera.near = .0005
	camera.far = 10
	camera.fov = 48
	add_child(camera)
	camera.current = true
	DirAccess.make_dir_recursive_absolute("/tmp/ship-systems")
	for index in ship.ship_count():
		ship.swap_ship(index)
		ship.reset_mesh_pose()
		var length: float = ship._hull_km
		camera.position = Vector3(1, -.65, -1.3) * length
		camera.look_at(Vector3(0, -length*.08, 0))
		for state in ["stowed", "landing", "weapons"]:
			ship.systems.gear_target = state == "landing"
			ship.systems.weapons_target = state == "weapons"
			ship.systems.step(3)
			for frame in 5:
				await get_tree().process_frame
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png("/tmp/ship-systems/%d-%s.png" % [index, state])
			if state == "weapons":
				for slot in ship.systems.mounts.size():
					plasma.emit(ship.muzzle_local(slot), Vector3.ZERO, ship.weapon_direction(), 1, Vector3.ZERO)
				for frame in 3:
					await get_tree().process_frame
				await RenderingServer.frame_post_draw
				get_viewport().get_texture().get_image().save_png("/tmp/ship-systems/%d-plasma-muzzle.png" % index)
				plasma.advance(.025, Vector3.ZERO, [])
				for frame in 3:
					await get_tree().process_frame
				await RenderingServer.frame_post_draw
				get_viewport().get_texture().get_image().save_png("/tmp/ship-systems/%d-plasma-flight.png" % index)
				plasma.clear()
	print("ship mechanism captures: /tmp/ship-systems")
	get_tree().quit()
