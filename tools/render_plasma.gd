extends Node3D
## Sustained fire at the actual chase-camera scale. Deterministic 60 fps frames.
func _ready() -> void:
	get_window().mode = Window.MODE_WINDOWED
	get_window().size = Vector2i(1280, 720)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(.25, .36, .49)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(.7, .8, 1)
	env.ambient_light_energy = .5
	env.glow_enabled = true
	env.glow_normalized = true
	env.glow_intensity = .45
	env.glow_bloom = 0.0
	env.glow_strength = .85
	env.glow_hdr_threshold = 1.0
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	env.set_glow_level(1, .8)
	env.set_glow_level(2, .4)
	env.set_glow_level(3, .15)
	env.set_glow_level(5, 0.0)
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = .7
	var world := WorldEnvironment.new()
	world.environment = env
	add_child(world)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, -25, 0)
	sun.light_energy = 1.5
	add_child(sun)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(30, 30)
	ground.mesh = plane
	ground.position.y = -.25
	var ground_material := StandardMaterial3D.new()
	ground_material.albedo_color = Color(.13, .18, .10)
	ground.material_override = ground_material
	add_child(ground)
	var ship := Ship.new()
	add_child(ship)
	ship._set_capture(false)
	ship.newton = true
	ship.anchor_off = Vector3.UP*6372
	ship.systems.weapons_target = true
	ship.systems.step(1)
	var camera := Camera3D.new()
	camera.near = .001
	camera.far = 40
	add_child(camera)
	ship.camera = camera
	ship._update_camera(1)
	var combat := Combat.new()
	add_child(combat)
	var target := {"alive": true, "pos": ship.anchor_off+Vector3(.035,0,-1), "vel": Vector3(.3,0,0), "name": "Preview drone", "size": .01}
	combat._aliens = [target]
	var target_mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(.01,.006,.012)
	target_mesh.mesh = box
	add_child(target_mesh)
	var layer := CanvasLayer.new()
	add_child(layer)
	var reticle := preload("res://scripts/ui/crosshair.gd").new()
	reticle.size = Vector2(80,80)
	layer.add_child(reticle)
	var plasma := PlasmaProjectiles.new()
	add_child(plasma)
	DirAccess.make_dir_recursive_absolute("/tmp/plasma-chase")
	for frame in 90:
		combat.update_aim(ship)
		target_mesh.position = target.pos-ship.anchor_off
		reticle.set_solution(combat.aim_solution, camera)
		reticle.set_target(1,0)
		plasma.advance(1.0/60.0, Vector3.ZERO, [])
		if frame % 6 == 0:
			var slot := (frame/6) % ship.systems.mounts.size()
			plasma.emit(ship.muzzle_local(slot), Vector3.ZERO, ship.barrel_direction(slot), 1, Vector3.ZERO, ship.systems.muzzle_node(slot))
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("/tmp/plasma-chase/%03d.png" % frame)
	print("plasma chase sequence: /tmp/plasma-chase")
	combat._aliens.clear()
	get_tree().quit()
