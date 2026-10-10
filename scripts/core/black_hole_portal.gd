class_name BlackHolePortal
extends CanvasLayer
# A fictional horizon interior, then a dinosaur's arcade. The space tree stays
# intact but suspended; its previous visibility, processing and audio restore.

const Runner := preload("res://scripts/ui/humano_runner.gd")
enum Stage { DESCENT, LOADING, PLAYING, CLOSED }
const DESCENT_S := 5.0
const LOADING_S := 1.0
const CUBE_COUNT := 28
const INK := Color("182637")
const CREAM := Color("f1dfb5")
const GREEN := Color("62ab80")
const PINK := Color("dc7f9b")

var stage := Stage.DESCENT
var elapsed := 0.0
var main: Node3D
var runner: Control
var return_direction := Vector3(1.0,.12,0.0).normalized()
var _states: Array[Dictionary] = []
var _audio_states: Array[Dictionary] = []
var _main_visible := true
var _mouse_mode: Input.MouseMode
var _ship_capture := false
var _root: Control
var _viewport: SubViewport
var _world: Node3D
var _camera: Camera3D
var _environment: Environment
var _fog: ColorRect
var _loading: VBoxContainer
var _headline: Label
var _hint: Label
var _jump_button: Button
var _cubes: MultiMeshInstance3D
var _cube_frames: Array[Transform3D] = []
var _cube_edges: Array[Transform3D] = []
var _dino: Node3D
var _hands: Array[Node3D] = []
var _tap := 0.0

func _ready() -> void:
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	_fog = ColorRect.new()
	_fog.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fog.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fog.color = Color(INK, 0.0)
	_root.add_child(_fog)
	var container := SubViewportContainer.new()
	container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	container.stretch = true
	container.stretch_shrink = 2
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(container)
	_viewport = SubViewport.new()
	_viewport.size = Vector2i(640,360)
	_viewport.own_world_3d = true
	_viewport.transparent_bg = true
	_viewport.handle_input_locally = false
	container.add_child(_viewport)
	_world = Node3D.new()
	_viewport.add_child(_world)
	_camera = Camera3D.new()
	_camera.position = Vector3(0,0,5)
	_camera.fov = 75.0
	_world.add_child(_camera)
	_camera.make_current()
	var world_environment := WorldEnvironment.new()
	_environment = Environment.new()
	_environment.background_mode = Environment.BG_COLOR
	_environment.background_color = INK
	_environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_environment.ambient_light_color = CREAM
	_environment.ambient_light_energy = .55
	_environment.fog_enabled = true
	_environment.fog_light_color = Color("70627f")
	_environment.fog_density = .015
	world_environment.environment = _environment
	_world.add_child(world_environment)
	_build_cubes()
	_build_controls()
	_root.resized.connect(_fit_room)

func begin(space: Node3D) -> void:
	main = space
	_main_visible = main.visible
	_mouse_mode = Input.get_mouse_mode()
	_ship_capture = main.ship._mouse_captured
	var direction: Vector3 = main.ship.to_body("Sagittarius A*")
	if direction.length_squared() > 1.0: return_direction = -direction.normalized()
	for node in main.find_children("*", "AudioStreamPlayer", true, false) + GameAudio.find_children("*", "AudioStreamPlayer", true, false):
		_audio_states.append({"node":node, "paused":node.stream_paused})
		node.stream_paused = true
	for node in [main] + main.find_children("*", "", true, false):
		if node == self or is_ancestor_of(node): continue
		var state := {"node":node, "mode":node.process_mode}
		if node is CanvasLayer or (node is Node3D and node.get_parent() == main and node != main.ship and not node is Light3D):
			state["visible"] = node.visible
			node.visible = false
		_states.append(state)
		node.process_mode = Node.PROCESS_MODE_DISABLED
	main.ship._set_capture(false)
	main._save_profile()

func _process(delta: float) -> void:
	advance(delta)

func advance(delta: float) -> void:
	if stage == Stage.CLOSED or main == null: return
	elapsed += maxf(delta,0.0)
	if stage == Stage.DESCENT:
		main.ship.relocate(main.ship.anchor_off + main.ship.velocity*minf(delta,.25))
		main.planets.refresh(main.ship.anchor_off,0.0,main.ship.anchor_name,main.ship.velocity)
		_update_cubes()
		_fog.color.a = smoothstep(0.0,DESCENT_S*.85,elapsed)
		_environment.fog_density = lerpf(.015,.09,clampf(elapsed/DESCENT_S,0.0,1.0))
		if elapsed >= DESCENT_S: _show_loading()
	if stage == Stage.LOADING:
		_hint.text = "Loading Humano" + ".".repeat(1 + int(elapsed*3.0)%3)
		if elapsed >= DESCENT_S + LOADING_S: _show_arcade()
	if stage == Stage.PLAYING:
		_tap = maxf(0.0,_tap-delta)
		for hand in _hands: hand.rotation.x = -.14 - .25*sin(_tap/.18*PI)
		_dino.rotation.y = sin(elapsed*.7)*.025

func _unhandled_input(event: InputEvent) -> void:
	if stage == Stage.CLOSED: return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			return_to_ship()
			get_viewport().set_input_as_handled()
		elif stage == Stage.PLAYING and event.keycode in [KEY_SPACE,KEY_UP]:
			_jump()
			get_viewport().set_input_as_handled()
	elif stage == Stage.PLAYING and event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_jump()
		get_viewport().set_input_as_handled()
	elif stage == Stage.PLAYING and event is InputEventScreenTouch and event.pressed:
		_jump()
		get_viewport().set_input_as_handled()

func _jump() -> void:
	if stage != Stage.PLAYING: return
	runner.jump()
	_tap = .18

func return_to_ship() -> void:
	if stage != Stage.CLOSED and is_instance_valid(main):
		main.return_from_black_hole_portal()

func close() -> void:
	if stage == Stage.CLOSED: return
	stage = Stage.CLOSED
	for state in _states:
		if not is_instance_valid(state.node): continue
		state.node.process_mode = state.mode
		if state.has("visible"): state.node.visible = state.visible
	_restore_audio()
	if is_instance_valid(main):
		main.visible = _main_visible
		main.ship._set_capture(_ship_capture)
	Input.set_mouse_mode(_mouse_mode)
	queue_free()

func _restore_audio() -> void:
	for state in _audio_states:
		if is_instance_valid(state.node): state.node.stream_paused = state.paused
	_audio_states.clear()

func _exit_tree() -> void:
	_restore_audio()

func _build_controls() -> void:
	var header := VBoxContainer.new()
	header.position = Vector2(28,24)
	_root.add_child(header)
	_headline = Label.new()
	_headline.text = "BEYOND THE HORIZON"
	_headline.add_theme_font_size_override("font_size",24)
	_headline.add_theme_color_override("font_color",CREAM)
	header.add_child(_headline)
	var subtitle := Label.new()
	subtitle.text = "Keep going."
	subtitle.add_theme_color_override("font_color",Color(CREAM,.7))
	header.add_child(subtitle)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(center)
	_loading = VBoxContainer.new()
	_loading.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(_loading)
	var title := Label.new()
	title.text = "SOMEWHERE ELSE"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size",32)
	title.add_theme_color_override("font_color",CREAM)
	_loading.add_child(title)
	_hint = Label.new()
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.add_theme_color_override("font_color",Color(CREAM,.7))
	_loading.add_child(_hint)
	_loading.hide()
	var bottom := HBoxContainer.new()
	bottom.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	bottom.offset_left = 24
	bottom.offset_right = -24
	bottom.offset_top = -24 - 52*HudScale.touch_scale()
	bottom.offset_bottom = -24
	bottom.add_theme_constant_override("separation",12)
	_root.add_child(bottom)
	var exit_button := _button("Return to ship · Esc")
	exit_button.pressed.connect(return_to_ship)
	bottom.add_child(exit_button)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom.add_child(spacer)
	_jump_button = _button("Jump · Space / ↑")
	_jump_button.pressed.connect(_jump)
	_jump_button.hide()
	bottom.add_child(_jump_button)

func _button(text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(190,52)
	button.custom_minimum_size *= HudScale.touch_scale()
	button.add_theme_color_override("font_color",CREAM)
	button.add_theme_font_size_override("font_size",int(16*HudScale.touch_scale()))
	for entry in ["normal","hover","pressed","focus"]:
		var style := StyleBoxFlat.new()
		style.bg_color = Color("283c50") if entry != "hover" else Color("3d5468")
		style.border_color = PINK if entry == "focus" else Color("526578")
		style.set_border_width_all(2 if entry == "focus" else 1)
		style.set_corner_radius_all(8)
		style.content_margin_left = 14
		style.content_margin_right = 14
		button.add_theme_stylebox_override(entry,style)
	return button

func _build_cubes() -> void:
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.use_colors = true
	var beam := BoxMesh.new()
	beam.size = Vector3(.025,.025,1.0)
	multi.mesh = beam
	multi.instance_count = CUBE_COUNT*12
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	beam.material = material
	for axis in 3:
		for a in [-1.0,1.0]:
			for b in [-1.0,1.0]:
				var center := Vector3.ZERO
				center[(axis+1)%3] = a*.5
				center[(axis+2)%3] = b*.5
				var basis := Basis.IDENTITY
				if axis == 0: basis = Basis(Vector3.UP,PI*.5)
				elif axis == 1: basis = Basis(Vector3.RIGHT,PI*.5)
				_cube_edges.append(Transform3D(basis,center))
	for i in CUBE_COUNT:
		var angle := float(i)*2.39996
		var radius := 2.8 + float(i%5)*1.1
		var size := 1.2 + float(i%4)*.6
		_cube_frames.append(Transform3D(Basis.IDENTITY.scaled(Vector3.ONE*size),Vector3(cos(angle)*radius,sin(angle)*radius,-float(i)*2.0)))
		for edge in 12: multi.set_instance_color(i*12+edge,CREAM.lerp(PINK,float(i%5)/5.0))
	_cubes = MultiMeshInstance3D.new()
	_cubes.multimesh = multi
	_world.add_child(_cubes)
	_update_cubes()

func _update_cubes() -> void:
	for i in CUBE_COUNT:
		var frame := _cube_frames[i]
		frame.origin.z = fposmod(frame.origin.z + elapsed*8.0,56.0) - 51.0
		frame.basis = frame.basis.rotated(Vector3(1,.7,.4).normalized(),elapsed*(.1 + float(i%3)*.07))
		for edge in 12: _cubes.multimesh.set_instance_transform(i*12+edge,frame*_cube_edges[edge])

func _show_loading() -> void:
	stage = Stage.LOADING
	main.visible = false
	_headline.get_parent().hide()
	_fog.color.a = 1.0
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_cubes.queue_free()
	_loading.show()
	_build_arcade()

func _show_arcade() -> void:
	stage = Stage.PLAYING
	_loading.hide()
	_headline.text = "THE OTHER SIDE"
	(_headline.get_parent().get_child(1) as Label).text = "You're the dinosaur. The human is your game."
	_headline.get_parent().show()
	_jump_button.show()
	_viewport.transparent_bg = false
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_fit_room()

func _fit_room() -> void:
	if stage == Stage.PLAYING:
		_camera.keep_aspect = Camera3D.KEEP_WIDTH if _root.size.x < _root.size.y else Camera3D.KEEP_HEIGHT

func _material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = .82
	return material

func _box(parent: Node3D, size: Vector3, position: Vector3, color: Color) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = _material(color)
	instance.position = position
	parent.add_child(instance)
	return instance

func _round(parent: Node3D, size: Vector3, position: Vector3, color: Color) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = .5
	mesh.height = 1.0
	mesh.radial_segments = 12
	mesh.rings = 6
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = _material(color)
	instance.scale = size
	instance.position = position
	parent.add_child(instance)
	return instance

func _build_arcade() -> void:
	_environment.fog_enabled = false
	_environment.background_color = INK
	_camera.position = Vector3(4.8,4.4,8.2)
	_camera.fov = 52
	_camera.look_at(Vector3(0,2.5,-.5))
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-48,-25,0)
	light.light_color = CREAM
	light.light_energy = 1.2
	_world.add_child(light)
	_box(_world,Vector3(22,.15,22),Vector3(0,-.15,0),Color("22384a"))
	_box(_world,Vector3(12,8,.25),Vector3(0,3.8,-3.5),Color("293747"))
	for side in [-1.0,1.0]:
		_box(_world,Vector3(.12,5,.08),Vector3(side*4.4,2.5,-3.3),PINK)
	_box(_world,Vector3(6.8,4.05,.6),Vector3(0,3.5,-1.6),CREAM)
	_box(_world,Vector3(6.3,3.55,.12),Vector3(0,3.5,-1.24),INK)
	_box(_world,Vector3(5.7,1.15,2.0),Vector3(0,.55,-.9),PINK)
	_box(_world,Vector3(5.7,.2,2.3),Vector3(0,1.23,-.7),Color("536575"))
	for i in 7:
		_box(_world,Vector3(.23,.07,.25),Vector3(-1.4+float(i)*.4,1.38,-.3),CREAM)
	var game_viewport := SubViewport.new()
	game_viewport.size = Vector2i(512,288)
	game_viewport.disable_3d = true
	game_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_viewport.add_child(game_viewport)
	runner = Runner.new()
	game_viewport.add_child(runner)
	var screen := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(6.0,3.375)
	screen.mesh = quad
	screen.position = Vector3(0,3.5,-1.16)
	var screen_material := StandardMaterial3D.new()
	screen_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	screen_material.albedo_texture = game_viewport.get_texture()
	screen_material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	screen.material_override = screen_material
	_world.add_child(screen)
	var title := Label3D.new()
	title.text = "H U M A N O"
	title.position = Vector3(0,5.78,-1.22)
	title.font_size = 54
	title.pixel_size = .009
	title.modulate = PINK
	_world.add_child(title)
	_build_dinosaur()

func _build_dinosaur() -> void:
	_dino = Node3D.new()
	_dino.position = Vector3(-1.9,0,1.55)
	_world.add_child(_dino)
	_round(_dino,Vector3(1.45,2.2,1.65),Vector3(0,1.5,.35),GREEN)
	_round(_dino,Vector3(1.05,1.6,.95),Vector3(0,1.5,-.32),CREAM)
	_round(_dino,Vector3(1.2,1.35,1.25),Vector3(0,2.85,-.2),GREEN)
	_box(_dino,Vector3(1.1,.65,1.3),Vector3(0,2.75,-.85),GREEN)
	_box(_dino,Vector3(1.05,.12,.8),Vector3(0,2.39,-1.03),Color("43795c"))
	for side in [-1.0,1.0]:
		_round(_dino,Vector3(.25,.35,.32),Vector3(side*.58,3.01,-.64),CREAM)
		_round(_dino,Vector3(.13,.2,.17),Vector3(side*.68,3.03,-.67),INK)
		_round(_dino,Vector3(.65,.85,.8),Vector3(side*.52,.53,.5),GREEN)
		_box(_dino,Vector3(.7,.28,1.0),Vector3(side*.55,.15,.15),GREEN)
		var arm := Node3D.new()
		arm.position = Vector3(side*.68,1.94,-.35)
		_dino.add_child(arm)
		_round(arm,Vector3(.28,.34,.95),Vector3(0,-.13,-.36),GREEN)
		_box(arm,Vector3(.35,.17,.35),Vector3(0,-.24,-.9),CREAM)
		_hands.append(arm)
	for i in 5:
		var scale := 1.0-float(i)*.15
		_round(_dino,Vector3(.85,.85,1.05)*scale,Vector3(0,.9-float(i)*.1,1.0+float(i)*.55),GREEN)
	for i in 4:
		var spine := _box(_dino,Vector3(.3,.3,.3),Vector3(0,2.5-float(i)*.34,.65+float(i)*.22),PINK)
		spine.rotation.z = PI*.25
