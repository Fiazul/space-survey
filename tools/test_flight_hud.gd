class_name TestFlightHud
extends Node
var failures := 0

func check(label: String, ok: bool) -> void:
	print(("PASS " if ok else "FAIL ") + label)
	if not ok:
		failures += 1

func _ready() -> void:
	var hud := HUD.new()
	add_child(hud)
	check("systems starts closed", not hud.is_systems_open())
	check("return home tucked inside menu", hud.teleport_button.get_parent() == hud._btn_bar)
	hud.toggle_systems()
	check("systems opens", hud.is_systems_open())
	check("menu blocks flight touches", hud.blocks_flight_touch(Vector2(640, 360)))
	hud.map_button.pressed.emit()
	check("opening chart closes systems", not hud.is_systems_open())
	check("closed menu leaves flight clear", not hud.blocks_flight_touch(Vector2(640, 360)))
	check("systems button blocks steering", hud.blocks_flight_touch(hud._systems_button.position + Vector2(10, 10)))
	hud.toggle_systems()
	hud.toggle_systems()
	check("keyboard toggle closes menu", not hud.is_systems_open())
	hud.queue_free()
	await get_tree().process_frame
	get_tree().quit(1 if failures else 0)
