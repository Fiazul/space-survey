class_name TestTravel
extends Node
## Travel without wormholes (docs/adr/0003): a star is reachable once visited
## (teleport) or with ASTRYX_DEV_TRAVEL=1; a save in a system that no longer
## exists boots on the Sol pad. Needs ASTRYX_PROFILE_DIR (isolated here).
## godot --headless tools/test_travel.tscn  -> "travel: OK"
const MAIN := preload("res://scripts/core/main.gd")
var failures := 0


func check(name: String, ok: bool) -> void:
	print("  %s %s" % ["PASS" if ok else "FAIL", name])
	if not ok:
		failures += 1


func _boot() -> Node:
	var main: Node = MAIN.new()
	add_child(main)
	main.set_process(false)
	await get_tree().process_frame
	return main


func _unvisited_star() -> String:
	for id in SystemDB.all():
		if id != SystemDB.SOL and id != SystemDB.PROXIMA and not GameState.visited.has(id):
			return id
	return ""


func _ready() -> void:
	ProfileDir.isolate("test_travel")
	OS.unset_environment("ASTRYX_DEV_TRAVEL")
	for f in ["profile.cfg", "codex.json"]:
		if FileAccess.file_exists(ProfileDir.path(f)):
			DirAccess.remove_absolute(ProfileDir.path(f))
	var main: Node = await _boot()

	check("sol_is_teleport_platform", SystemDB.is_teleport_platform(SystemDB.SOL))
	check("unvisited_not_platform", not SystemDB.is_teleport_platform(SystemDB.PROXIMA))
	check("has_station_follows_rule", SystemDB.has_station(SystemDB.PROXIMA) == SystemDB.is_teleport_platform(SystemDB.PROXIMA))
	check("unvisited_star_state_locked", main.star_state(SystemDB.PROXIMA) == "locked")

	check("unvisited_refused", not main.travel_to(SystemDB.PROXIMA) and main.current_system == SystemDB.SOL)
	check("refusal_says_drive", str(main.hud.toast).contains("interstellar drive"))
	main.teleport_to_platform(SystemDB.PROXIMA)
	check("unvisited_teleport_refused", not main._tp_active)
	check("unknown_id_refused", not main.can_travel_to("interstellar"))

	GameState.visited[SystemDB.PROXIMA] = true
	check("visited_is_platform", SystemDB.is_teleport_platform(SystemDB.PROXIMA))
	check("visited_allowed", main.travel_to(SystemDB.PROXIMA) and main.current_system == SystemDB.PROXIMA
		and Ephemeris.system_id == SystemDB.PROXIMA)
	check("station_parks_beside_spawn", main.props.has_dock
		and absf(main.props.dock_rel(main.ship).length() - 20.0) < 0.5)
	check("sol_always_allowed", main.travel_to(SystemDB.SOL) and main.current_system == SystemDB.SOL)

	var far := _unvisited_star()
	check("dev_flag_off_refuses", far != "" and not main.can_travel_to(far))
	OS.set_environment("ASTRYX_DEV_TRAVEL", "1")
	check("dev_flag_allows", main.travel_to(far) and main.current_system == far)
	OS.unset_environment("ASTRYX_DEV_TRAVEL")
	check("dev_arrival_marks_visited", GameState.visited.has(far))
	main.travel_to(SystemDB.SOL)
	main.queue_free()
	await get_tree().process_frame

	# A save left in the old deep-space hub, with retired economy keys.
	var cfg := ConfigFile.new()
	cfg.load(GameState.profile_path())
	cfg.set_value("player", "system", "interstellar")
	cfg.set_value("player", "anchor", "Hub")
	cfg.set_value("player", "off", Vector3(0.0, 200.0, 600.0))
	cfg.set_value("player", "coins", 900)
	cfg.set_value("player", "nav_unlocked", ["tau_ceti"])
	cfg.save(GameState.profile_path())
	main = await _boot()
	check("lost_system_boots_sol", main.current_system == SystemDB.SOL and Ephemeris.system_id == SystemDB.SOL)
	check("lost_system_on_home_pad", main.ship.anchor_name == "Earth" and main.ship.landing_site_id == main.HOME_PAD_ID)
	check("old_keys_ignored", not "coins" in GameState and GameState.visited.has(SystemDB.PROXIMA))
	main.queue_free()
	await get_tree().process_frame
	print("travel: ", "OK" if failures == 0 else "FAIL %d" % failures)
	get_tree().quit(0 if failures == 0 else 1)
