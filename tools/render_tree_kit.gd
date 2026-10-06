class_name RenderTreeKit
extends Node3D
var frames := 0

func _ready() -> void:
	get_window().mode = Window.MODE_WINDOWED
	get_window().size = Vector2i(500, 300)
	var kit := SurfaceTreeKit.new()
	for i in 2:
		var tree := MeshInstance3D.new()
		tree.mesh = kit.mesh(i)
		tree.position.x = -.022 if i == 0 else .022
		add_child(tree)
	if OS.get_environment("TREE_SIMPLE") == "1":
		var shader := Shader.new()
		shader.code = "shader_type spatial; render_mode unshaded, cull_disabled; uniform sampler2D albedo_map : source_color; uniform vec4 tint : source_color; void fragment(){vec4 tex=texture(albedo_map,UV)*tint; ALBEDO=tex.rgb; ALPHA=tex.a; ALPHA_SCISSOR_THRESHOLD=.45;}"
		for mat in kit.materials:
			mat.shader = shader
	kit.set_parameter("air_amount", 1.0)
	kit.set_parameter("exposure", 1.8)
	kit.set_parameter("sun_dir", Vector3(.6, .7, .3).normalized())
	var cam := Camera3D.new()
	cam.near = .0001
	cam.far = 1.0
	add_child(cam)
	cam.look_at_from_position(Vector3(.045, .025, .075), Vector3(0, .015, 0))
	var world := WorldEnvironment.new()
	world.environment = Environment.new()
	world.environment.background_mode = Environment.BG_COLOR
	world.environment.background_color = Color(.03, .045, .065)
	EnvironmentLook.apply(world.environment)
	add_child(world)

func _process(_dt: float) -> void:
	frames += 1
	print("tree_kit frame ", frames)
	if frames == 4:
		get_viewport().get_texture().get_image().save_png("/tmp/astryx-tree-kit.png")
		get_tree().quit()
