class_name BlackHoleBackground
extends Node
# Two bounded core batches in an isolated viewport; includes transparent gas,
# excludes the ship/UI, and only updates while a resolved black hole is visible.
var viewport: SubViewport
var camera: Camera3D
var core: GalacticCore
var _last_observer := Vector3(INF,INF,INF)

func _ready() -> void:
	viewport = SubViewport.new()
	viewport.size = Vector2i(1024,512)
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(viewport)
	var world := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color.BLACK
	world.environment = environment
	viewport.add_child(world)
	camera = Camera3D.new()
	camera.fov = 110.0
	camera.near = 100.0
	camera.far = 1100000.0
	viewport.add_child(camera)
	camera.make_current()
	core = GalacticCore.new()
	viewport.add_child(core)
	core._star_material.set_shader_parameter("include_physical_points", true)
	core._star_material.set_shader_parameter("panorama", true)
	core._gas_material.set_shader_parameter("panorama", true)

func refresh(source_camera: Camera3D, ship_off: Vector3, anchor: String, material: ShaderMaterial) -> void:
	if source_camera == null: return
	core.refresh(ship_off, anchor)
	if _last_observer.distance_to(core._last_observer) > 1e-8:
		_last_observer = core._last_observer
		viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	material.set_shader_parameter("background_texture", viewport.get_texture())
	material.set_shader_parameter("use_core_background", true)

func suspend() -> void:
	if viewport != null: viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
