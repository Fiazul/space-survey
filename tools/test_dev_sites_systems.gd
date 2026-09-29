extends Node
# The Ctrl+P panel's STAR SYSTEMS rows: Sol pad -> Proxima through the dev
# travel bypass (no ASTRYX_DEV_TRAVEL) -> back to Sol on Earth. Sol site rows
# vanish outside Sol.
# Run: godot --headless tools/test_dev_sites_systems.tscn

const MAIN := preload("res://scripts/core/main.gd")
var failures := 0


func check(label: String, ok: bool) -> void:
	print("  %s %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		failures += 1


func _press(text: String) -> bool:
	for c in main_panel()._list.get_children():
		if c is Button and not c.is_queued_for_deletion() and c.text.strip_edges().begins_with(text):
			c.pressed.emit()
			return true
	return false


func _labels() -> Array:
	var out := []
	for c in main_panel()._list.get_children():
		if c is Label and not c.is_queued_for_deletion():
			out.append(c.text)
	return out


var main: Node
func main_panel() -> DevSitesPanel:
	return main.dev_sites


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	ProfileDir.isolate("test_dev_sites_systems")
	OS.unset_environment("ASTRYX_DEV_TRAVEL")
	OS.set_environment("ASTRYX_START", "pad")
	for f in ["profile.cfg", "codex.json"]:
		if FileAccess.file_exists(ProfileDir.path(f)):
			DirAccess.remove_absolute(ProfileDir.path(f))
	main = MAIN.new()
	add_child(main)
	main.set_process(false)
	await get_tree().process_frame
	check("boot_sol_earth", main.current_system == SystemDB.SOL and main.ship.anchor_name == "Earth")
	check("proxima_unvisited", not GameState.visited.has(SystemDB.PROXIMA))

	main_panel().toggle()
	check("panel_has_star_systems", _labels().has("STAR SYSTEMS"))
	check("panel_has_sol_sites", _labels().has("Earth"))
	check("proxima_pressed", _press(SystemDB.display_name(SystemDB.PROXIMA)))
	check("panel_closed", not main_panel()._open and not get_tree().paused)
	check("on_proxima", main.current_system == SystemDB.PROXIMA and Ephemeris.system_id == SystemDB.PROXIMA)
	check("generated_system", Ephemeris.current() is GeneratedEphemeris)
	var anchor: String = main.ship.anchor_name
	check("anchor_generated_body", anchor == Ephemeris.spawn_body() and anchor != "Earth"
		and Ephemeris.is_anchorable(anchor))
	print("  anchor=%s off_km=%.1f" % [anchor, main.ship.anchor_off.length()])
	check("newton_on", main.ship._newton_g().length() > 0.0)

	main_panel().toggle()
	check("sol_sites_hidden", not _labels().has("Earth") and _labels().has("STAR SYSTEMS"))
	check("sol_pressed", _press("Sol"))
	check("back_on_sol", main.current_system == SystemDB.SOL and Ephemeris.system_id == SystemDB.SOL)
	check("anchor_earth", main.ship.anchor_name == "Earth")
	main_panel().toggle()
	check("sol_sites_back", _labels().has("Earth"))
	main_panel().toggle()

	print("dev_sites_systems: ", "OK" if failures == 0 else "FAIL %d" % failures)
	get_tree().quit(0 if failures == 0 else 1)
