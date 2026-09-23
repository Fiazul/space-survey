extends SceneTree
# Headless: a turn must carry Sol velocity with the hull.
# Run: godot --headless --path . --script res://tools/test_turn_carry.gd

const S := preload("res://scripts/flight/turn_carry.gd")


func _initialize() -> void:
	var failed := 0
	var old_b := Basis.IDENTITY
	var vel := Vector3(0.0, 0.0, -10.0)   # forward along the nose
	var new_b := old_b.rotated(Vector3.UP, PI)
	var out: Vector3 = S.apply(vel, old_b, new_b)
	failed += _check("flip_goes_with_nose", out.z > 8.0)
	failed += _check("speed_kept", is_equal_approx(out.length(), 10.0))

	var inward := Vector3(0.0, 0.0, -1.0)
	var still_in := vel.dot(inward) > 0.0
	var now_out := out.dot(inward) < 0.0
	failed += _check("was_in", still_in)
	failed += _check("now_out", now_out)

	var same: Vector3 = S.apply(vel, old_b, old_b)
	failed += _check("no_turn_no_change", same.distance_to(vel) < 0.0001)
	var falling := -vel
	failed += _check("backwards_fall_does_not_reverse", S.apply(falling,old_b,new_b).is_equal_approx(falling))
	var drift := Vector3.RIGHT*5
	failed += _check("side_slip_is_not_rotated", S.apply(drift,old_b,new_b).is_equal_approx(drift))
	# Manual steering is incremental, so test the entire turn, not only a 180° snap.
	var basis := old_b
	for i in 180:
		var turned := basis.rotated(Vector3.UP,deg_to_rad(1))
		falling = S.apply(falling,basis,turned)
		failed += _check("turn_cannot_flip_fall_outwards_%d" % i, falling.z > 0)
		basis = turned

	if failed == 0:
		print("turn_carry: OK")
		quit(0)
	else:
		print("turn_carry: FAIL %d" % failed)
		quit(1)


func _check(name: String, ok: bool) -> int:
	if not ok:
		print("turn_carry: FAIL %s" % name)
		return 1
	return 0
