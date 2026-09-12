extends SceneTree
# Headless check on TouchControls.stick_to_cmd — pure, autoload-free, so it loads clean
# under --script (unlike ship.gd/main.gd, see CLAUDE.md "Commands").
# Run: godot --headless --script res://tools/test_touch_controls.gd

const TC := preload("res://scripts/flight/touch_controls.gd")


func _initialize() -> void:
	var failed := 0

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
