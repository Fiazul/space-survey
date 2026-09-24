class_name TestMapView3D
extends Node
# Headless coverage for the Elite-style MapView3D (local + global) and StarMap host.
# Run: godot --headless --path . res://tools/test_map_view_3d.tscn

var failures := 0

func check(label: String, ok: bool) -> void:
	print(("PASS " if ok else "FAIL ") + label)
	if not ok:
		failures += 1


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var stub := MapStub.new()
	add_child(stub)

	var view := MapView3D.new()
	view.main = stub
	view.size = Vector2(700, 500)
	add_child(view)
	await get_tree().process_frame

	check("defaults to GLOBAL", view.mode == MapView3D.Mode.GLOBAL)
	view.init_view()
	await get_tree().process_frame
	check("global rebuild has pickables", view._pickables.size() >= 3)
	check("global span_ly positive", view.span_ly() > 0)
	check("lanes node exists", view._lanes != null)

	view.set_mode(MapView3D.Mode.LOCAL)
	await get_tree().process_frame
	check("mode is LOCAL", view.mode == MapView3D.Mode.LOCAL)
	check("local world has bodies/markers", view._world.get_child_count() >= 2)
	check("local pickables include system", view._pickables.size() >= 1)

	view.toggle_mode()
	await get_tree().process_frame
	check("toggle returns GLOBAL", view.mode == MapView3D.Mode.GLOBAL)

	view.filters["lanes"] = false
	view.rebuild()
	await get_tree().process_frame
	check("rebuild with lanes off keeps stars", view._pickables.size() >= 3)

	# StarMap hosts MapView3D (single map UI — no competing MapChart).
	var sm := StarMap.new()
	sm.main = stub
	add_child(sm)
	await get_tree().process_frame
	check("StarMap chart is MapView3D", sm._chart is MapView3D)
	check("mode chips exist", sm._mode_local != null and sm._mode_global != null)

	sm.toggle()
	await get_tree().process_frame
	check("open pauses tree", get_tree().paused)
	check("open starts GLOBAL", sm._chart.mode == MapView3D.Mode.GLOBAL)
	sm._chart.toggle_mode()
	await get_tree().process_frame
	check("toggle to LOCAL while open", sm._chart.mode == MapView3D.Mode.LOCAL)
	sm.toggle()
	await get_tree().process_frame
	check("close unpauses tree", not get_tree().paused)

	await get_tree().process_frame
	get_tree().quit(1 if failures else 0)


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

	func notify_map_opened() -> void:
		pass

	func is_wormhole_known(id: String) -> bool:
		var st := star_state(id)
		return st == "nav" or st == "discovered"

	func nav_cost(_id: String) -> int:
		return 100

	func unlock_nav(_id: String) -> bool:
		return false

	func navigate_to(_id: String) -> void:
		pass

	func is_teleport_unlocked(_id: String) -> bool:
		return false

	func teleport_to_platform(_id: String) -> void:
		pass

	func set_nav_target(_body: String) -> void:
		pass

	func start_autopilot(_body: String) -> void:
		pass

	func open_details_for(_body: String) -> void:
		pass


class ShipStub extends Node:
	var true_pos := Vector3(42000, 0, 0)
	var frozen := false
	func _set_capture(_on: bool) -> void:
		pass


class PlanetsStub:
	func rel_of(_name: String) -> Vector3:
		return Vector3(1000, 0, 0)


class CodexStub:
	func is_discovered(_name: String) -> bool:
		return true
