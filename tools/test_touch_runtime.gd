extends Node
# Native viewport dispatch on a stretched screen, including real ship actions.
var failures := 0
var controls: TouchControls

func check(label: String, ok: bool) -> void:
	if not ok:
		failures += 1
		push_error("touch_runtime: " + label)

func button(label: String) -> Button:
	for entry in controls._buttons:
		if entry.node.text == label:
			return entry.node
	return null

func touch(label: String, pressed: bool, finger := 0) -> void:
	touch_at(button(label).get_global_rect().get_center(), pressed, finger)

func touch_at(position: Vector2, pressed: bool, finger := 0) -> void:
	var event := InputEventScreenTouch.new()
	event.index = finger
	event.position = position
	event.pressed = pressed
	get_viewport().push_input(event, true)

func _ready() -> void:
	ProfileDir.isolate("test_touch_runtime")
	Input.emulate_mouse_from_touch = false
	get_window().content_scale_size = Vector2i(1280, 720)
	get_window().content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	var main: Node = preload("res://scripts/core/main.gd").new()
	add_child(main)
	main.set_process(false)
	controls = TouchControls.new()
	controls.ship = main.ship
	controls.main = main
	controls._use_mouse = false
	main.add_child(controls)
	await get_tree().process_frame
	controls._process(0.0)
	touch("MENU", true)
	touch("MENU", false)
	await get_tree().process_frame
	check("native tap opens menu on stretched screen", controls.is_menu_open())
	# Keep independent hold tests running even when the initial tap fails.
	controls.set_menu_open(true)
	controls._process(0.0)
	touch("UP", true)
	await get_tree().process_frame
	await get_tree().process_frame
	check("pitch remains held across menu frames", main.ship.touch_pitch == -1.0)
	touch("UP", false)
	check("pitch releases", main.ship.touch_pitch == 0.0)
	touch("BOOST", true)
	await get_tree().process_frame
	await get_tree().process_frame
	check("boost remains held across menu frames", Input.is_physical_key_pressed(KEY_SHIFT))
	touch("BOOST", false)
	await get_tree().process_frame
	check("boost releases", not Input.is_physical_key_pressed(KEY_SHIFT))
	main.ship.landed = false
	main.ship.landing_site = ""
	var gear_before: bool = main.ship.systems.gear_target
	touch("GEAR", true)
	touch("GEAR", false)
	await get_tree().process_frame
	check("gear tap reaches actual ship action", main.ship.systems.gear_target != gear_before)
	controls.set_menu_open(false)
	controls._process(0.0)
	var cruise_before: bool = main.ship.auto_cruise
	touch("THRUST", true)
	touch("THRUST", false)
	check("native thrust toggles cruise", main.ship.auto_cruise != cruise_before)
	touch("FIRE", true, 1)
	await get_tree().process_frame
	check("native fire remains held", main.ship.touch_fire)
	touch("FIRE", false, 1)
	check("native fire releases", not main.ship.touch_fire)
	var origin := get_viewport().get_visible_rect().size * Vector2(.2, .7)
	touch_at(origin, true, 2)
	var drag := InputEventScreenDrag.new()
	drag.index = 2
	drag.position = origin + Vector2(0, -TouchControls.RING_R * controls._scale * .5)
	drag.relative = drag.position - origin
	get_viewport().push_input(drag, true)
	touch("FIRE", true, 1)
	await get_tree().process_frame
	check("native stick and fire work simultaneously", main.ship.touch_thrust > .4 and main.ship.touch_fire)
	touch_at(drag.position, false, 2)
	check("releasing stick preserves other finger", main.ship.touch_thrust == 0.0 and main.ship.touch_fire)
	touch("FIRE", false, 1)
	controls.set_menu_open(true)
	controls._process(0.0)
	touch("UP", true)
	touch("BOOST", true, 1)
	await get_tree().process_frame
	controls.set_menu_open(false)
	await get_tree().process_frame
	check("closing menu clears all holds", main.ship.touch_pitch == 0.0 and not Input.is_physical_key_pressed(KEY_SHIFT))
	main.hud.toggle_systems()
	controls._process(0.0)
	check("systems panel hides flight controls", not button("FIRE").visible and not button("MENU").visible)
	main.hud.toggle_systems()
	controls._process(0.0)
	check("closing systems restores flight controls", button("FIRE").visible and button("MENU").visible)
	main.queue_free()
	await get_tree().process_frame
	print("touch_runtime: %s" % ("OK" if failures == 0 else "FAIL %d" % failures))
	get_tree().quit(0 if failures == 0 else 1)
