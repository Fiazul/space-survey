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
	for unlock in 12: GameState.visited["test_system_%d" % unlock] = true # every tier swappable
	var module_set := OS.get_environment("MODULE_SET")
	if module_set in ["mk1", "mk2"]:
		GameState.weapon_set = module_set
		GameState.pad_set = module_set
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
	var shot_dir := OS.get_environment("SHOT_DIR")
	if shot_dir.is_empty(): shot_dir = "/tmp/ship-systems"
	DirAccess.make_dir_recursive_absolute(shot_dir)
	for index in ship.ship_count():
		ship.swap_ship(index)
		ship.reset_mesh_pose()
		var length: float = ship._hull_km
		camera.position = Vector3(1, -.65, -1.3) * length
		camera.look_at(Vector3(0, -length*.08, 0))
		for state in ["stowed", "landing", "hover", "weapons"]:
			var selected := OS.get_environment("SYSTEM_SHOTS")
			if not selected.is_empty() and not state in selected.split(","): continue
			ship.systems.gear_target = state == "landing" or state == "hover"
			ship.systems.weapons_target = state == "weapons"
			ship.systems.step(3)
			ship.systems.support.command(Vector3.UP*.012 if state == "hover" else Vector3.ZERO,.1)
			for frame in 5:
				await get_tree().process_frame
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png("%s/%d-%s.png" % [shot_dir, index, state])
			if state == "weapons":
				for slot in ship.systems.mounts.size():
					plasma.emit(ship.muzzle_local(slot), Vector3.ZERO, ship.weapon_direction(), 1, Vector3.ZERO)
				for frame in 3:
					await get_tree().process_frame
				await RenderingServer.frame_post_draw
				get_viewport().get_texture().get_image().save_png("%s/%d-plasma-muzzle.png" % [shot_dir, index])
				plasma.advance(.025, Vector3.ZERO, [])
				for frame in 3:
					await get_tree().process_frame
				await RenderingServer.frame_post_draw
				get_viewport().get_texture().get_image().save_png("%s/%d-plasma-flight.png" % [shot_dir, index])
				plasma.clear()
	print("ship mechanism captures: ", shot_dir)
	get_tree().quit()
