extends Node
# Capture GLOBAL + LOCAL MapView3D frames for visual review.
# Run: xvfb-run -a /home/box/godot/Godot_v4.7.2-stable_linux.x86_64 --path . res://tools/render_map_view_3d.tscn
# Plain --headless captures nothing.

const OUT_DIR := "/workspace/space-survey-map-shots"

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	get_viewport().transparent_bg = false
	get_viewport().size = Vector2i(1280, 720)

	var stub := MapStub.new()
	add_child(stub)

	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.size = Vector2(1280, 720)
	add_child(root)

	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.02, 0.03, 0.06)
	root.add_child(bg)

	var title := Label.new()
	title.position = Vector2(24, 16)
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color(0.55, 0.9, 1.0))
	root.add_child(title)

	var view := MapView3D.new()
	view.main = stub
	view.position = Vector2(40, 56)
	view.size = Vector2(1200, 620)
	root.add_child(view)
	await get_tree().process_frame
	await get_tree().process_frame

	# GLOBAL
	title.text = "GLOBAL map (Elite-style 3D)"
	view.set_mode(MapView3D.Mode.GLOBAL)
	view.init_view()
	await _settle()
	await _shot("01_global.png")

	# GLOBAL another angle
	view._yaw = 1.2
	view._pitch = 0.55
	view._dist = 70.0
	view._apply_cam()
	await _settle()
	await _shot("02_global_orbit.png")

	# LOCAL
	title.text = "LOCAL map (Sol system)"
	view.set_mode(MapView3D.Mode.LOCAL)
	await _settle()
	await _shot("03_local.png")

	view._yaw = 0.2
	view._pitch = 0.65
	view._dist = max(view._dist_min * 1.4, view._dist * 0.55)
	view._apply_cam()
	await _settle()
	await _shot("04_local_close.png")

	# Extra label-focused angles (stems / clickable names)
	title.text = "GLOBAL labels (leaders)"
	view.set_mode(MapView3D.Mode.GLOBAL)
	view._yaw = 0.35
	view._pitch = 0.72
	view._dist = 36.0
	view._apply_cam()
	await _settle()
	await _shot("05_global_labels.png")

	title.text = "LOCAL labels (leaders / Sol)"
	view.set_mode(MapView3D.Mode.LOCAL)
	view._yaw = 1.05
	view._pitch = 0.48
	view._dist = 48.0
	view._apply_cam()
	await _settle()
	await _shot("06_local_labels.png")

	print("map shots -> ", OUT_DIR)
	await get_tree().process_frame
	get_tree().quit(0)


func _settle() -> void:
	# Labels/leaders are built in rebuild(); a few extra frames let Label3D settle.
	for i in 18:
		await get_tree().process_frame
	await get_tree().create_timer(0.2).timeout


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	if img == null:
		push_error("null image for " + name)
		return
	var path := OUT_DIR.path_join(name)
	var err := img.save_png(path)
	print("saved ", path, " err=", err, " ", img.get_width(), "x", img.get_height())


class MapStub extends Node:
	var current_system := SystemDB.SOL
	var ship: ShipStub
	var audio = null
	var planets = PlanetsStub.new()
	var codex = CodexStub.new()

	func _ready() -> void:
		ship = ShipStub.new()
		add_child(ship)

	func star_state(id: String) -> String:
		if id == current_system:
			return "here"
		if id == SystemDB.PROXIMA:
			return "discovered"
		if id == SystemDB.TRAPPIST:
			return "nav"
		return "locked"

	func is_edge_known(a: String, b: String) -> bool:
		return a == SystemDB.SOL or b == SystemDB.SOL \
			or a == SystemDB.PROXIMA or b == SystemDB.PROXIMA

	func _known_portals(id: String) -> Array:
		var out := []
		for p in SystemDB.portals(id):
			if is_edge_known(id, str(p.dest)):
				out.append(p)
		return out

	func planet_system(id: String):
		return planets

	func navigate_to(_id: String) -> void:
		pass

	func chart_lane(_a: String, _b: String) -> void:
		pass


class ShipStub extends Node3D:
	var true_pos := Vector3(12000.0, 800.0, -4000.0)


class PlanetsStub:
	func body_by_id(id: String):
		return null


class CodexStub:
	func is_scanned(_id: String) -> bool:
		return true
