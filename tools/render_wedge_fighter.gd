extends Node3D

var _camera: Camera3D

func _ready() -> void:
	get_window().size = Vector2i(1440, 960)
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.018, 0.026, 0.045)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.65, 0.75, 0.95)
	environment.ambient_light_energy = 0.45
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var world := WorldEnvironment.new()
	world.environment = environment
	add_child(world)
	for setting in [[Vector3(-45, -35, 0), Color(0.87, 0.94, 1.0), 2.1],
		[Vector3(-20, 140, 0), Color(0.30, 0.65, 1.0), 1.2],
		[Vector3(25, 20, 0), Color(1.0, 0.65, 0.35), 0.65]]:
		var light := DirectionalLight3D.new()
		light.rotation_degrees = setting[0]
		light.light_color = setting[1]
		light.light_energy = setting[2]
		add_child(light)
	var underside_key := DirectionalLight3D.new()
	underside_key.rotation_degrees = Vector3(45, -35, 0)
	underside_key.light_color = Color(0.82, 0.92, 1.0)
	underside_key.light_energy = 1.8
	underside_key.visible = false
	add_child(underside_key)
	var model := load("res://assets/wedge_fighter/wedge_fighter.glb").instantiate() as Node3D
	add_child(model)
	if OS.get_environment("RAW") != "1" and ResourceLoader.exists("res://scripts/flight/wedge_fighter.gd"):
		var design = load("res://scripts/flight/wedge_fighter.gd")
		var driven: Array = design.style(model)
		for material in driven:
			material.set_shader_parameter("power", 0.62)
			material.set_shader_parameter("temperature", 0.9)
	_camera = Camera3D.new()
	_camera.fov = 42
	add_child(_camera)
	var output := OS.get_environment("SHOT_DIR")
	if output == "":
		output = "/tmp/wedge_fighter"
	DirAccess.make_dir_recursive_absolute(output)
	for shot in [["front", Vector3(8, 7, 11)], ["rear", Vector3(-8, 5.5, -12)], ["top", Vector3(0, 18, 0.01)], ["underside", Vector3(8, -7, 11)], ["bottom", Vector3(0, -18, 0.01)]]:
		underside_key.visible = shot[1].y < 0.0
		_camera.position = shot[1]
		_camera.look_at(Vector3(0, 0, -0.5), Vector3.UP)
		for frame in 8:
			await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png(output + "/" + shot[0] + ".png")
		print("wedge render: ", output, "/", shot[0], ".png")
	get_tree().quit()
