extends Node3D
# Real fitted starter hull and systems; reproduce individual auxiliary jet commands.
func _ready() -> void:
	get_window().size = Vector2i(1200, 800)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(.018, .025, .04)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(.7, .8, 1)
	env.ambient_light_energy = .45
	var world := WorldEnvironment.new()
	world.environment = env
	add_child(world)
	for angle in [Vector3(-35, -30, 0), Vector3(40, 130, 0)]:
		var light := DirectionalLight3D.new()
		light.rotation_degrees = angle
		light.light_energy = 1.4
		add_child(light)
	var ship := Ship.new()
	add_child(ship)
	ship._set_capture(false)
	ship.reset_mesh_pose()
	var camera := Camera3D.new()
	camera.near = .0005
	camera.far = 10
	camera.fov = 34
	camera.current = true
	add_child(camera)
	var out := "res://docs/reference/fleet-review/starter"
	DirAccess.make_dir_recursive_absolute(out)
	var length: float = ship._hull_km
	for view in ["front", "rear", "belly"]:
		camera.position = (Vector3(.85, .65, -1.1) if view == "front" else
			Vector3(.8, .45, 1.2) if view == "rear" else Vector3(.7, -.65, -.95)) * length
		camera.look_at(Vector3.ZERO)
		for state in ["idle", "strafe", "brake_idle", "hover"]:
			ModularHull.drive_rcs(ship._rcs_puffs, Vector3.RIGHT if state == "strafe" else Vector3.ZERO, state == "brake_idle", 1)
			ship.systems.support.command(Vector3.UP * .012 if state == "hover" else Vector3.ZERO, 1)
			ship.systems.gear_target = state == "hover"
			ship.systems.step(3)
			for frame in 4:
				await get_tree().process_frame
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png("%s/%s-%s.png" % [out, view, state])
	print("starter captures: ", out)
	get_tree().quit()
