extends SceneTree
# Headless check on the Ctrl+D NODEATH dev toggle.
# Run: godot --headless --path . --script res://tools/test_dev_no_death.gd
#
# FlightMode is autoload-free (static vars/funcs only), so it loads clean under
# --script, unlike ship.gd/main.gd which touch autoloads (see CLAUDE.md
# "Commands"). Behaviour that only exists inside main.gd's per-frame death
# checks (_update_skin_kill/_update_core_hazard) is asserted as a SOURCE check
# below, the same pattern test_skin_kill.gd uses for the swept-contact test.

const FM := preload("res://scripts/flight/flight_mode.gd")


func _initialize() -> void:
	var failed := 0

	failed += _check("default_false", FM.dev_no_death == false)
	failed += _check("kill_allowed_when_flag_clear", FM.kill_allowed())

	FM.dev_no_death = true
	failed += _check("kill_blocked_when_flag_set", not FM.kill_allowed())
	FM.dev_no_death = false
	failed += _check("kill_allowed_again_after_clearing", FM.kill_allowed())

	# ship.gd: Ctrl+D toggles the flag, gated on dev_speed the same way \ gates
	# FASTAIR, and clears it again the moment DEV mode itself is turned off (a
	# flag is meaningless if it can outlive dev mode).
	var ship_src := FileAccess.get_file_as_string("res://scripts/flight/ship.gd")
	failed += _check("ctrl_d_gated_on_dev_speed",
		ship_src.find("KEY_D and event.ctrl_pressed and dev_speed") >= 0)
	failed += _check("toggle_func_exists",
		ship_src.find("func _debug_toggle_dev_no_death() -> void:") >= 0)
	failed += _check("dev_off_clears_no_death",
		ship_src.find("_FM.dev_no_death = false") >= 0)

	# main.gd: both death paths must consult the same gate before they can kill.
	var main_src := FileAccess.get_file_as_string("res://scripts/core/main.gd")
	var skin_kill_at := main_src.find("func _update_skin_kill(")
	var core_hazard_at := main_src.find("func _update_core_hazard(")
	failed += _check("skin_kill_and_core_hazard_found", skin_kill_at >= 0 and core_hazard_at >= 0)
	failed += _check("skin_kill_checks_kill_allowed",
		main_src.find("FlightMode.kill_allowed()", skin_kill_at) >= 0 \
		and main_src.find("FlightMode.kill_allowed()", skin_kill_at) < main_src.find("func _skin_begin("))
	failed += _check("core_hazard_checks_kill_allowed",
		main_src.find("FlightMode.kill_allowed()", core_hazard_at) >= 0 \
		and main_src.find("FlightMode.kill_allowed()", core_hazard_at) < main_src.find("func _core_kill("))
	failed += _check("skin_begin_also_clears_no_death",
		main_src.find("FlightMode.dev_no_death = false") >= 0)

	if failed == 0:
		print("dev_no_death: OK")
		quit(0)
	else:
		print("dev_no_death: FAIL %d" % failed)
		quit(1)


func _check(name: String, ok: bool) -> int:
	if not ok:
		print("dev_no_death: FAIL %s" % name)
		return 1
	return 0
