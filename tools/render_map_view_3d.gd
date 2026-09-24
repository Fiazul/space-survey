extends Node
# Capture GLOBAL + LOCAL MapView3D frames (with Local/Global tabs + YOU) for visual review.
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

	# Full StarMap overlay so Local/Global tabs are visible in the shots.
	var sm := StarMap.new()
	sm.main = stub
	add_child(sm)
	await get_tree().process_frame
	# StarMap._build uses `main` during chip toggles; set chart.main too.
	if sm._chart != null:
		sm._chart.main = stub
	sm._tp_mode = false
	sm._open = true
	sm._view_system = stub.current_system
	sm._chart.view_system = stub.current_system
	sm._root.visible = true
	# Keep tree unpaused so pulse animates during settle.
	get_tree().paused = false

	# GLOBAL tab + YOU
	sm._chart.set_mode(MapView3D.Mode.GLOBAL)
	if sm._mode_global != null:
		sm._mode_global.set_pressed_no_signal(true)
	if sm._mode_local != null:
		sm._mode_local.set_pressed_no_signal(false)
	sm._chart.init_view()
	sm._chart.center_on(stub.current_system)
	sm._refresh()
	sm._on_mode_changed("global")
	await _settle()
	await _shot("01_global.png")

	# GLOBAL orbit angle — YOU still visible near Sol
	sm._chart._yaw = 1.15
	sm._chart._pitch = 0.58
	sm._chart._dist = 55.0
	sm._chart._apply_cam()
	await _settle()
	await _shot("02_global_orbit.png")

	# LOCAL tab + YOU at true_pos
	sm._chart.set_mode(MapView3D.Mode.LOCAL)
	if sm._mode_local != null:
		sm._mode_local.set_pressed_no_signal(true)
	if sm._mode_global != null:
		sm._mode_global.set_pressed_no_signal(false)
	sm._refresh()
	sm._on_mode_changed("local")
	await _settle()
	await _shot("03_local.png")

	sm._chart._yaw = 0.25
	sm._chart._pitch = 0.62
	sm._chart._dist = max(sm._chart._dist_min * 1.4, sm._chart._dist * 0.55)
	sm._chart._apply_cam()
	await _settle()
	await _shot("04_local_close.png")

	# Label / YOU close-ups
	sm._chart.set_mode(MapView3D.Mode.GLOBAL)
	if sm._mode_global != null:
		sm._mode_global.set_pressed_no_signal(true)
	if sm._mode_local != null:
		sm._mode_local.set_pressed_no_signal(false)
	sm._refresh()
	sm._on_mode_changed("global")
	sm._chart._yaw = 0.4
	sm._chart._pitch = 0.7
	sm._chart._dist = 32.0
	sm._chart._apply_cam()
	await _settle()
	await _shot("05_global_labels.png")

	sm._chart.set_mode(MapView3D.Mode.LOCAL)
	if sm._mode_local != null:
		sm._mode_local.set_pressed_no_signal(true)
	if sm._mode_global != null:
		sm._mode_global.set_pressed_no_signal(false)
	sm._refresh()
	sm._on_mode_changed("local")
	sm._chart._yaw = 1.0
	sm._chart._pitch = 0.5
	sm._chart._dist = 42.0
	sm._chart._apply_cam()
	await _settle()
	await _shot("06_local_labels.png")

	print("map shots -> ", OUT_DIR)
	await get_tree().process_frame
	get_tree().quit(0)


func _settle() -> void:
	# Enough frames for Label3D + YOU pulse to show mid-cycle.
	for i in 24:
		await get_tree().process_frame
	await get_tree().create_timer(0.35).timeout


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

	func notify_map_opened() -> void:
		pass

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

	func is_wormhole_known(sys: String) -> bool:
		return star_state(sys) != "locked" or sys == SystemDB.PROXIMA

	func is_teleport_unlocked(_sys: String) -> bool:
		return false

	func nav_cost(_sys: String) -> int:
		return 50

	func unlock_nav(_sys: String) -> bool:
		return false

	func navigate_to(_id: String) -> void:
		pass

	func _known_portals(id: String) -> Array:
		var out := []
		for p in SystemDB.portals(id):
			if is_edge_known(id, str(p.dest)):
				out.append(p)
		return out

	func planet_system(id: String):
		return planets

	func chart_lane(_a: String, _b: String) -> void:
		pass


class ShipStub extends Node3D:
	# Near Earth GEO-ish so YOU sits clearly off the Sol star in LOCAL.
	var true_pos := Vector3(42000.0, 1200.0, -8000.0)
	var frozen := false

	func _set_capture(_on: bool) -> void:
		pass


class PlanetsStub:
	func body_by_id(id: String):
		return null

	func rel_of(_name: String) -> Vector3:
		return Vector3(1.0, 0.0, 0.0)


class CodexStub:
	func is_scanned(_id: String) -> bool:
		return true

	func is_discovered(_id: String) -> bool:
		return true
