extends SceneTree
# Headless check on TouchControls.stick_to_cmd — pure, autoload-free, so it loads clean
# under --script (unlike ship.gd/main.gd, see CLAUDE.md "Commands").
# Run: godot --headless --script res://tools/test_touch_controls.gd

const TC := preload("res://scripts/flight/touch_controls.gd")
const HS := preload("res://scripts/ui/hud_scale.gd")


class ShipStub extends Node:
	var auto_cruise := false
	var dev_speed := true
	var touch_fire := false
	var touch_held := false
	var touch_thrust := 0.0
	var touch_yaw := 0.0
	var touch_brake := false
	var touch_pitch := 0.0
	var _cam_zoom := 1.0
	const ZOOM_MIN := 0.45
	const ZOOM_MAX := 8.0


func _initialize() -> void:
	var failed := 0
	failed += _check("flight_has_only_fire_thrust_menu", TC.visible_flight_buttons() == PackedStringArray(["FIRE", "THRUST", "MENU"]))
	failed += _check("menu_toggles_open", TC.toggled_menu(false) and not TC.toggled_menu(true))
	var menu_actions := TC.menu_action_names()
	for action in ["HOME", "MAP", "ARMS", "INTERACT", "GEAR", "CAP", "BOOST", "UP", "DOWN", "ZOOM−", "ZOOM+", "TELEPORT", "SYSTEMS", "DEV"]:
		failed += _check("menu_contains_%s" % action, menu_actions.has(action))

	var dead := TC.stick_to_cmd(Vector2(0.1, 0.1))
	failed += _check("dead_zone", dead.thrust == 0.0 and dead.yaw == 0.0 and not dead.brake)

	var zero := TC.stick_to_cmd(Vector2.ZERO)
	failed += _check("zero_vector", zero.thrust == 0.0 and zero.yaw == 0.0 and not zero.brake)

	var fwd := TC.stick_to_cmd(Vector2(0.0, -0.5))
	failed += _check("pure_forward_thrust", is_equal_approx(fwd.thrust, 0.5))
	failed += _check("pure_forward_yaw", fwd.yaw == 0.0)
	failed += _check("pure_forward_no_brake", not fwd.brake)

	var fwd_right := TC.stick_to_cmd(Vector2(1.0, -1.0))   # 45° forward-right
	failed += _check("fwd_right_thrust_positive", fwd_right.thrust > 0.0)
	failed += _check("fwd_right_yaw_positive_partial", fwd_right.yaw > 0.0 and fwd_right.yaw < 1.0)
	failed += _check("fwd_right_no_brake", not fwd_right.brake)
	# Exact 45° values: thrust = cos(45°), yaw = smoothstep((45-15)/75 = 0.4) ≈ 0.352.
	failed += _check("fwd_right_thrust_exact", is_equal_approx(fwd_right.thrust, cos(deg_to_rad(45.0))))
	failed += _check("fwd_right_yaw_exact", absf(fwd_right.yaw - 0.352) < 0.001)

	var exactly_150 := TC.stick_to_cmd(Vector2(sin(deg_to_rad(30.0)), cos(deg_to_rad(30.0))))   # 180-150=30
	failed += _check("exactly_150_brakes", exactly_150.brake)
	failed += _check("exactly_150_thrust_zero", is_equal_approx(exactly_150.thrust, 0.0))
	failed += _check("exactly_150_yaw_zero", exactly_150.yaw == 0.0)

	var right := TC.stick_to_cmd(Vector2(1.0, 0.0))   # 90° right
	failed += _check("right_thrust_zero", is_equal_approx(right.thrust, 0.0))
	failed += _check("right_yaw_full", is_equal_approx(right.yaw, 1.0))
	failed += _check("right_no_brake", not right.brake)

	var back_left := TC.stick_to_cmd(Vector2(-sin(deg_to_rad(60.0)), cos(deg_to_rad(60.0))))   # 120° back-left
	failed += _check("back_left_thrust_zero", is_equal_approx(back_left.thrust, 0.0))
	failed += _check("back_left_yaw_full_negative", is_equal_approx(back_left.yaw, -1.0))
	failed += _check("back_left_no_brake", not back_left.brake)

	var back := TC.stick_to_cmd(Vector2(sin(deg_to_rad(5.0)), cos(deg_to_rad(5.0))))   # 175° back
	failed += _check("back_brake", back.brake)
	failed += _check("back_thrust_zero", is_equal_approx(back.thrust, 0.0))
	failed += _check("back_yaw_zero", back.yaw == 0.0)

	var left := TC.stick_to_cmd(Vector2(-1.0, 0.0))   # 90° left, mirrors "right"
	failed += _check("symmetry_thrust", is_equal_approx(left.thrust, right.thrust))
	failed += _check("symmetry_yaw", is_equal_approx(left.yaw, -right.yaw))

	# pinch_zoom(start_zoom, start_dist, cur_dist, zmin, zmax)
	var apart := TC.pinch_zoom(2.0, 100.0, 200.0, 0.45, 8.0)   # fingers spread 2x -> zoom halves
	failed += _check("pinch_apart_halves", is_equal_approx(apart, 1.0))

	var together := TC.pinch_zoom(2.0, 100.0, 50.0, 0.45, 8.0)   # fingers close 2x -> zoom doubles
	failed += _check("pinch_together_doubles", is_equal_approx(together, 4.0))

	var unchanged := TC.pinch_zoom(2.0, 100.0, 100.0, 0.45, 8.0)   # same distance -> unchanged
	failed += _check("pinch_unchanged_dist", is_equal_approx(unchanged, 2.0))

	var clamp_min := TC.pinch_zoom(1.0, 100.0, 1000.0, 0.45, 8.0)   # would go far below zmin
	failed += _check("pinch_clamps_at_zmin", is_equal_approx(clamp_min, 0.45))

	var clamp_max := TC.pinch_zoom(1.0, 1000.0, 1.0, 0.45, 8.0)   # would go far above zmax
	failed += _check("pinch_clamps_at_zmax", is_equal_approx(clamp_max, 8.0))

	var zero_cur := TC.pinch_zoom(2.0, 100.0, 0.0, 0.45, 8.0)   # cur_dist ~0 — no div-by-zero
	failed += _check("pinch_zero_cur_dist_no_blowup", is_equal_approx(zero_cur, 2.0) and is_finite(zero_cur))

	var zero_start := TC.pinch_zoom(2.0, 0.0, 100.0, 0.45, 8.0)   # start_dist ~0 — degenerate pinch start
	failed += _check("pinch_zero_start_dist_no_blowup", is_equal_approx(zero_start, 2.0) and is_finite(zero_start))

	var zoom_in := TC.zoom_step(2.0, -1, log(2.0), 0.45, 8.0)   # one halving
	failed += _check("zoom_step_in", is_equal_approx(zoom_in, 1.0))

	var zoom_out := TC.zoom_step(2.0, 1, log(2.0), 0.45, 8.0)   # one doubling
	failed += _check("zoom_step_out", is_equal_approx(zoom_out, 4.0))

	var zoom_min := TC.zoom_step(0.5, -1, 0.12, 0.45, 8.0)
	failed += _check("zoom_step_clamps_at_zmin", is_equal_approx(zoom_min, 0.45))

	var zoom_max := TC.zoom_step(7.95, 1, 0.12, 0.45, 8.0)
	failed += _check("zoom_step_clamps_at_zmax", is_equal_approx(zoom_max, 8.0))

	failed += _check("scale_desktop_is_one", HS.compute_scale(96.0, Vector2(1920, 1080), false) == 1.0)
	failed += _check("scale_desktop_hidpi_is_one", HS.compute_scale(400.0, Vector2(3840, 2160), false) == 1.0)
	failed += _check("scale_phone_clamps_max", HS.compute_scale(420.0, Vector2(2400, 1080), true) == HS.MAX_SCALE)
	failed += _check("scale_tablet_floor", HS.compute_scale(150.0, Vector2(1280, 800), true) == HS.MIN_SCALE)
	var mid := HS.compute_scale(260.0, Vector2(2400, 1080), true)
	failed += _check("scale_midrange", mid > 1.0 and mid < HS.MAX_SCALE and absf(mid - 1.081) < 0.01)
	failed += _check("scale_portrait_same", is_equal_approx(mid, HS.compute_scale(260.0, Vector2(1080, 2400), true)))
	failed += _check("scale_bad_dpi", HS.compute_scale(0.0, Vector2(2400, 1080), true) == 1.0)
	failed += _check("fit_limits", is_equal_approx(HS.fit_scale(1.6, 570.0, 864.0), 864.0 / 570.0))
	failed += _check("fit_keeps_desired", HS.fit_scale(1.0, 570.0, 864.0) == 1.0)

	var none := HS.compute_insets(Rect2(), Vector2(2400, 1080), Vector2(1600, 720))
	failed += _check("insets_none", none.left == 0.0 and none.top == 0.0 and none.right == 0.0 and none.bottom == 0.0)
	var notch := HS.compute_insets(Rect2(90, 0, 2310, 1080), Vector2(2400, 1080), Vector2(1600, 720))
	failed += _check("insets_notch_left", is_equal_approx(notch.left, 60.0) and notch.right == 0.0 and notch.bottom == 0.0)

	var no_inset := {"left": 0.0, "top": 0.0, "right": 0.0, "bottom": 0.0}
	failed += _check("dock_identity_at_base", HS.dock_pos(Vector2(1170, 76), Vector2(88, 88), HS.BASE, no_inset) == Vector2(1170, 76))
	failed += _check("dock_right_edge", HS.dock_pos(Vector2(1170, 76), Vector2(88, 88), Vector2(1600, 720), no_inset) == Vector2(1490, 76))
	failed += _check("dock_bottom_edge", HS.dock_pos(Vector2(28, 535), Vector2(184, 52), Vector2(1280, 800), no_inset) == Vector2(28, 615))
	failed += _check("dock_inset_left", HS.dock_pos(Vector2(28, 55), Vector2(180, 40), Vector2(1600, 720), notch).x == 88.0)

	for sz in [Vector2(2400, 1080), Vector2(1920, 1080), Vector2(1280, 800), Vector2(1280, 720)]:
		for want in [1.0, 1.3, 1.6]:
			for inset in [no_inset, {"left": 60.0, "top": 0.0, "right": 0.0, "bottom": 0.0}]:
				var s := TC.overlay_scale(sz, want, inset)
				var rects := TC.button_rects(sz, s, inset)
				var all_inside := true
				var bottom_right := true
				var no_overlap := true
				var fire_dist := INF
				var fire_nearest := true
				for name in rects:
					var r: Rect2 = rects[name]
					all_inside = all_inside and r.position.x >= inset.left and r.position.y >= inset.top \
						and r.end.x <= sz.x - inset.right and r.end.y <= sz.y - inset.bottom
					bottom_right = bottom_right and (name == "MENU" or r.position.x >= sz.x * 0.70)
					for other in rects:
						if name != other:
							no_overlap = no_overlap and not r.intersects(rects[other])
					var d := r.get_center().distance_to(Vector2(sz.x - inset.right, sz.y - inset.bottom))
					if name == "FIRE":
						fire_dist = d
				for name in rects:
					if name != "FIRE":
						fire_nearest = fire_nearest and fire_dist < rects[name].get_center().distance_to(Vector2(sz.x - inset.right, sz.y - inset.bottom))
				var tag := "%s_%s_%s" % [sz, want, inset.left]
				failed += _check("layout_inside_%s" % tag, all_inside)
				failed += _check("layout_bottom_right_%s" % tag, bottom_right)
				failed += _check("layout_no_overlap_%s" % tag, no_overlap)
				failed += _check("layout_fire_corner_%s" % tag, fire_nearest)
				failed += _check("layout_no_zoom_%s" % tag, not rects.has("ZOOM+") and not rects.has("ZOOM−"))

	var stretch := Transform2D(Vector2(1.5, 0.0), Vector2(0.0, 1.5), Vector2.ZERO)
	failed += _check("event_to_canvas_unstretches_window_pixels", TC.event_to_canvas(Vector2(1770.0, 930.0), stretch) == Vector2(1180.0, 620.0))
	failed += await _live_input_checks()

	if failed == 0:
		print("touch_controls: OK")
		quit(0)
	else:
		print("touch_controls: FAIL %d" % failed)
		quit(1)


func _check(name: String, ok: bool) -> int:
	if not ok:
		print("touch_controls: FAIL %s" % name)
		return 1
	return 0


func _live_input_checks() -> int:
	var failed := 0
	var ship := ShipStub.new()
	root.add_child(ship)
	var controls := TC.new()
	controls.ship = ship
	controls._use_mouse = true
	root.add_child(controls)
	await process_frame
	controls._layout()
	controls._process(0.0)

	var menu: Dictionary = _button_named(controls, "MENU")
	_send_mouse(controls, menu.node.get_global_rect().get_center(), true)
	_send_mouse(controls, menu.node.get_global_rect().get_center(), false)
	controls._process(0.0)
	failed += _check("input_menu_opens", controls.is_menu_open())
	for action in TC.menu_action_names():
		failed += _check("input_menu_action_visible_%s" % action, _button_named(controls, action).node.visible)
	failed += _check("input_flight_buttons_hidden", not _button_named(controls, "FIRE").node.visible and not _button_named(controls, "THRUST").node.visible and not _button_named(controls, "MENU").node.visible)
	failed += _check("input_close_visible", _button_named(controls, "×").node.visible)

	_send_mouse(controls, Vector2(4.0, root.get_viewport().get_visible_rect().size.y - 4.0), true)
	controls._process(0.0)
	failed += _check("input_outside_closes_menu", not controls.is_menu_open())

	var fire: Dictionary = _button_named(controls, "FIRE")
	_send_mouse(controls, fire.node.get_global_rect().get_center(), true)
	failed += _check("input_fire_press_sets_touch_fire", ship.touch_fire)
	_send_mouse(controls, fire.node.get_global_rect().get_center(), false)
	failed += _check("input_fire_release_clears_touch_fire", not ship.touch_fire)

	controls.queue_free()
	ship.queue_free()
	await process_frame
	return failed


func _button_named(controls: CanvasLayer, text: String) -> Dictionary:
	for button in controls._buttons:
		if button.node.text == text:
			return button
	return {}


func _send_mouse(controls: CanvasLayer, position: Vector2, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.position = controls.get_viewport().get_final_transform() * position
	event.global_position = event.position
	event.pressed = pressed
	controls._input(event)
