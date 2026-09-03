extends SceneTree
# Run: godot --headless --path . --script res://tools/test_streak_scale.gd
#
# The motion-streak field is authored in raw units (a box 45 deep made of 2.4-long
# streaks). Against an 80 m hull that works out to a field ~560 hull lengths deep built
# from debris 30 hull lengths long, all of it far away — and debris that size sliding
# past tells the eye the ship is a speck. Ship._fit_streaks rescales the whole emitter
# so the field is measured in HULL LENGTHS instead; this locks that conversion down.
#
# Pure arithmetic on the constants, so it runs headless in a fraction of a second.

const S := preload("res://scripts/flight/ship.gd")


func _initialize() -> void:
	var failed := 0

	var factor := S.HULL_KM * S.STREAK_FIELD_HULLS / S.STREAK_BOX_Z
	var hulls := func(raw: float) -> float: return raw * factor / S.HULL_KM
	var depth: float = hulls.call(45.0)      # emission_box_extents.z
	var width: float = hulls.call(16.0)      # emission_box_extents.x
	var streak: float = hulls.call(2.4)      # the streak BoxMesh's long axis
	var flow: float = hulls.call(240.0)      # initial_velocity_max, hull lengths/sec
	print("streaks: field %.1f deep x %.1f wide (hulls), streak %.2f hulls, flow %.0f hulls/s"
		% [depth, width, streak, flow])

	failed += _check("field_is_hull_scaled", is_equal_approx(depth, S.STREAK_FIELD_HULLS))
	failed += _check("debris_smaller_than_ship", streak < 1.0)
	failed += _check("debris_passes_close", width < 8.0)
	failed += _check("flow_still_reads_as_speed", flow > 20.0)

	if failed == 0:
		print("streak_scale: OK")
	else:
		print("streak_scale: %d FAILED" % failed)
	quit(1 if failed > 0 else 0)


func _check(name: String, ok: bool) -> int:
	print("  %s %s" % ["PASS" if ok else "FAIL", name])
	return 0 if ok else 1
