extends SceneTree
# Run: godot --headless --path . --script res://tools/test_flight_mode.gd

const M := preload("res://scripts/flight/flight_mode.gd")
const E := preload("res://scripts/autoload/ephemeris.gd")


func _initialize() -> void:
	var failed := 0
	var earth_ez: float = M.exclusion_from_center(E.EARTH_RADIUS_KM, E.EARTH_ATMO_TOP_KM, false)
	var moon_ez: float = M.exclusion_from_center(E.MOON_RADIUS_KM, 0.0, false)
	var sun_ez: float = M.exclusion_from_center(E.SUN_RADIUS_KM, 0.0, true)
	print("flight_mode: EZ Earth %.0f  Moon %.0f  Sun %.0f" % [earth_ez, moon_ez, sun_ez])

	failed += _check("earth_ez_is_air", is_equal_approx(earth_ez, E.EARTH_RADIUS_KM + E.EARTH_ATMO_TOP_KM))
	failed += _check("moon_ez_10km", is_equal_approx(moon_ez, E.MOON_RADIUS_KM + 10.0))
	failed += _check("sun_ez_chromosphere", is_equal_approx(sun_ez, E.SUN_RADIUS_KM + 2500.0))

	failed += _check("geo_local", M.of("SPACE", 1.0, true) == M.LOCAL)
	failed += _check("geo_cruise", M.of("SPACE", 50.0, true) == M.CRUISE)
	failed += _check("ez_blocks_cruise_mode", M.of("SPACE", 50.0, false) == M.LOCAL)
	failed += _check("air_kills_cruise", M.of("AIR", 50.0, true) == M.AIR)

	failed += _check("geo_can_cruise", M.can_cruise("SPACE", E.GEO_RADIUS_KM, earth_ez))
	failed += _check("no_cruise_air_zone", not M.can_cruise("AIR", E.EARTH_RADIUS_KM + 50.0, earth_ez))
	var moon_close := E.MOON_RADIUS_KM + 1.0
	failed += _check("moon_close_no_cruise", not M.can_cruise("SPACE", moon_close, moon_ez))
	failed += _check("moon_far_cruise", M.can_cruise("SPACE", moon_ez + 1000.0, moon_ez))
	failed += _check("sun_inside_ez", not M.can_cruise("SPACE", E.SUN_RADIUS_KM + 100.0, sun_ez))
	failed += _check("sun_outside_ez", M.can_cruise("SPACE", E.SUN_RADIUS_KM + 20000.0, sun_ez))

	failed += _check("drop_earth_air", M.must_drop("AIR", 50.0, E.EARTH_RADIUS_KM + 50.0, earth_ez))
	failed += _check("drop_moon_ez", M.must_drop("SPACE", 50.0, moon_close, moon_ez))
	failed += _check("no_drop_geo_cruise", not M.must_drop("SPACE", 50.0, E.GEO_RADIUS_KM, earth_ez))
	failed += _check("no_drop_local_air", not M.must_drop("AIR", 1.0, E.EARTH_RADIUS_KM + 50.0, earth_ez))

	var eph: Node = E.new()
	failed += _check("geo_zone_space", eph.flight_zone("Earth", E.GEO_RADIUS_KM) == "SPACE")
	failed += _check("fifty_km_air", eph.flight_zone("Earth", E.EARTH_RADIUS_KM + 50.0) == "AIR")
	failed += _check("moon_1km_space", eph.flight_zone("Moon", E.MOON_RADIUS_KM + 1.0) == "SPACE")
	eph.free()

	# F9 from GEO is so fast one step skips the air and pins on the 29 km kill.
	# Crossing EZ from outside must hard-break: sit on the shell, dump speed.
	var geo := Vector3(E.GEO_RADIUS_KM, 0.0, 0.0)
	var inward := Vector3(-1.0, 0.0, 0.0)
	var f9_v := inward * 3.27e7
	var punch: Dictionary = M.break_at_exclusion(geo, f9_v, 0.25, Vector3.ZERO, earth_ez, 0.0)
	failed += _check("f9_drops", bool(punch.dropped))
	failed += _check("f9_stops_on_shell", absf(punch.pos.length() - earth_ez) < 1.0)
	failed += _check("f9_speed_dumped", punch.vel.length() < 0.001)

	# The SHIPPED path dumps to the band cap for the shell's altitude, not to zero.
	# A dead stop on every approach read as hitting a wall, and it got worse once
	# the band became somewhere to fly: the Moon's shell sits at 10 km with a
	# 5.27 km band ceiling below it, so you stopped dead and then re-accelerated
	# into a capped band. Heading is kept, magnitude is clamped.
	var cap10: float = M.band_speed_cap_units(10.0)
	var soft: Dictionary = M.break_at_exclusion(geo, f9_v, 0.25, Vector3.ZERO, earth_ez, cap10)
	failed += _check("shell_still_drops", bool(soft.dropped))
	failed += _check("shell_keeps_you_moving", soft.vel.length() > 0.0)
	failed += _check("shell_clamps_to_the_cap", soft.vel.length() <= cap10 + 1.0e-6)
	failed += _check("shell_keeps_your_heading",
		soft.vel.normalized().dot(f9_v.normalized()) > 0.999)
	# ...and it must never speed anyone UP. A ship already slower than the cap
	# keeps its own speed.
	#
	# The first version of this started from GEO with a crawl speed, so it never
	# reached the shell in the time given, `dropped` came back false, and the
	# `not dropped or ...` guard passed it for free - the mutation that makes the
	# shell accelerate a slow ship survived. Start 1 km outside the shell instead,
	# and ASSERT it dropped so the case can never go vacuous again.
	var crawl_speed: float = cap10 * 0.25
	var just_out: Vector3 = inward * -(earth_ez + 1.0)
	var crawl: Vector3 = inward * crawl_speed
	var slow: Dictionary = M.break_at_exclusion(just_out, crawl, 20.0, Vector3.ZERO, earth_ez, cap10)
	failed += _check("the_slow_case_actually_drops", bool(slow.dropped))
	failed += _check("shell_never_accelerates_you",
		slow.vel.length() <= crawl_speed + 1.0e-6)
	failed += _check("f9_not_on_kill", punch.pos.length() > E.EARTH_MIN_R_KM + 1.0)
	var far_side: Dictionary = M.break_at_exclusion(geo, inward * 1.0e8, 1.0, Vector3.ZERO, earth_ez, 0.0)
	failed += _check("punch_not_far_side", far_side.pos.x > 0.0)
	var coast: Dictionary = M.break_at_exclusion(geo, inward * 0.001, 0.25, Vector3.ZERO, earth_ez, 0.0)
	failed += _check("slow_fall_no_drop", not bool(coast.dropped))
	var in_air := Vector3(E.EARTH_RADIUS_KM + 50.0, 0.0, 0.0)
	var already: Dictionary = M.break_at_exclusion(in_air, inward * 10.0, 0.05, Vector3.ZERO, earth_ez, 0.0)
	failed += _check("already_inside_no_snap", not bool(already.dropped))
	var out: Dictionary = M.break_at_exclusion(geo, -inward * 10.0, 0.25, Vector3.ZERO, earth_ez, 0.0)
	failed += _check("outbound_no_drop", not bool(out.dropped))

	var ship_src := FileAccess.get_file_as_string("res://scripts/flight/ship.gd")
	failed += _check("ship_clips_ez", ship_src.find("break_at_exclusion") >= 0)
	# The ship must pass a real cap, not a zero. Source check because the shipped
	# call runs inside _newton_advance and is not reachable from a pure test.
	failed += _check("ship_dumps_to_the_band_cap",
		ship_src.find("band_speed_cap_units(shell_alt)") >= 0)

	var hud_src := FileAccess.get_file_as_string("res://scripts/ui/hud.gd")
	failed += _check("hud_mode_line", hud_src.find("Mode    ") >= 0)
	failed += _check("hud_drop_tag", hud_src.find("DROP") >= 0)

	if failed == 0:
		print("flight_mode: OK")
		quit(0)
	else:
		print("flight_mode: FAIL %d" % failed)
		quit(1)


func _check(name: String, ok: bool) -> int:
	if not ok:
		print("flight_mode: FAIL %s" % name)
		return 1
	return 0
