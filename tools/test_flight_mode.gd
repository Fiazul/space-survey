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
	# Crossing EZ from outside must hard-snap: sit exactly on the shell. 2026-
	# 09-08: no velocity dump anymore ("a real game doesn't hard cap") - the
	# incoming velocity comes back unchanged, only position is corrected.
	var geo := Vector3(E.GEO_RADIUS_KM, 0.0, 0.0)
	var inward := Vector3(-1.0, 0.0, 0.0)
	var f9_v := inward * 3.27e7
	var punch: Dictionary = M.break_at_exclusion(geo, f9_v, 0.25, Vector3.ZERO, earth_ez)
	failed += _check("f9_drops", bool(punch.dropped))
	failed += _check("f9_stops_on_shell", absf(punch.pos.length() - earth_ez) < 1.0)
	failed += _check("f9_speed_kept_not_dumped",
		is_equal_approx(punch.vel.length(), f9_v.length()))
	# The shell must sit above the ground, not on it. Was EARTH_MIN_R_KM + 1;
	# that 6400 km bubble is retired, so this states the intent directly.
	failed += _check("f9_not_on_kill", punch.pos.length() > E.EARTH_RADIUS_KM + 1.0)
	var far_side: Dictionary = M.break_at_exclusion(geo, inward * 1.0e8, 1.0, Vector3.ZERO, earth_ez)
	failed += _check("punch_not_far_side", far_side.pos.x > 0.0)
	var coast: Dictionary = M.break_at_exclusion(geo, inward * 0.001, 0.25, Vector3.ZERO, earth_ez)
	failed += _check("slow_fall_no_drop", not bool(coast.dropped))
	var in_air := Vector3(E.EARTH_RADIUS_KM + 50.0, 0.0, 0.0)
	var already: Dictionary = M.break_at_exclusion(in_air, inward * 10.0, 0.05, Vector3.ZERO, earth_ez)
	failed += _check("already_inside_no_snap", not bool(already.dropped))
	var out: Dictionary = M.break_at_exclusion(geo, -inward * 10.0, 0.25, Vector3.ZERO, earth_ez)
	failed += _check("outbound_no_drop", not bool(out.dropped))

	# Direction-blind was the reported bug: climbing away must never snap like
	# diving in. Start just outside the shell heading straight out - if the
	# gate is missing or wrong, this would still drop like the inbound case.
	var just_outside: Vector3 = inward * -(earth_ez + 0.5)
	var climbing_out: Vector3 = -inward * 5.0
	var climb: Dictionary = M.break_at_exclusion(just_outside, climbing_out, 1.0,
		Vector3.ZERO, earth_ez)
	failed += _check("shell_outbound_not_dropped", not bool(climb.dropped))
	var diving_in: Vector3 = inward * 5.0
	var dive: Dictionary = M.break_at_exclusion(just_outside, diving_in, 1.0,
		Vector3.ZERO, earth_ez)
	failed += _check("shell_inbound_dropped", bool(dive.dropped))
	failed += _check("shell_inbound_keeps_velocity",
		is_equal_approx(dive.vel.length(), diving_in.length()))

	# air_load / mach: the one heating function every heat/plasma/audio FX keys
	# off. Vacuum is 0, it saturates towards 1, and it is monotonic in speed.
	failed += _check("air_load_vacuum_no_atmo", is_equal_approx(M.air_load(10.0, 5.0, 0.0), 0.0))
	failed += _check("air_load_vacuum_above_top", is_equal_approx(M.air_load(150.0, 5.0, 100.0), 0.0))
	failed += _check("air_load_zero_speed", is_equal_approx(M.air_load(10.0, 0.0, 100.0), 0.0))
	var low_load: float = M.air_load(10.0, 1.0, 100.0)
	# 2026-09-12: the curve's knee (air_load_q_ref) now tracks AIR_TERMINAL_KMS (boosted
	# equilibrium lands at AIR_LOAD_TARGET_FRAC by design, not 1.0 - see flight_mode.gd),
	# so the probe speed is a fixed MULTIPLE of AIR_TERMINAL_KMS (not a literal km/s
	# figure tuned to one specific target) to demonstrate the curve's asymptote past that
	# design point regardless of the current target value (2026-09-12: a literal 30 km/s
	# was tuned to the then-12 km/s target and silently stopped proving anything once
	# AIR_TERMINAL_KMS moved to 50).
	var high_load: float = M.air_load(10.0, 2.5 * M.AIR_TERMINAL_KMS, 100.0)
	failed += _check("air_load_monotonic_in_speed", high_load > low_load)
	failed += _check("air_load_saturates", high_load < 1.0 and high_load > M.AIR_LOAD_TARGET_FRAC)
	failed += _check("air_load_in_range", low_load >= 0.0 and low_load <= 1.0)
	failed += _check("mach_unity_at_speed_of_sound", is_equal_approx(M.mach(0.34), 1.0))
	failed += _check("mach_monotonic", M.mach(1.0) > M.mach(0.5))

	# Onset floor: nothing should be felt at 90-100 km even at real entry speed - the
	# density there is so low (rho ~1e-5..1e-6 of sea level) that the un-floored curve
	# still returned a nonzero-but-imperceptible value. The floor (AIR_LOAD_Q_FLOOR)
	# is picked so 2 km/s at ~70 km is the first felt buffet.
	failed += _check("air_load_silent_at_95km_2kms", is_equal_approx(M.air_load(95.0, 2.0, 100.0), 0.0))
	failed += _check("air_load_silent_at_90km_2kms", is_equal_approx(M.air_load(90.0, 2.0, 100.0), 0.0))
	failed += _check("air_load_silent_at_90km_orbital", M.air_load(90.0, 7.9, 100.0) < 0.001)
	failed += _check("air_load_onset_at_70km_2kms_is_zero_or_tiny",
		M.air_load(70.0, 2.0, 100.0) <= 0.001)
	failed += _check("air_load_felt_shortly_past_onset",
		M.air_load(65.0, 2.5, 100.0) > 0.0)

	var ship_src := FileAccess.get_file_as_string("res://scripts/flight/ship.gd")
	failed += _check("ship_clips_ez", ship_src.find("break_at_exclusion") >= 0)
	# 2026-09-08: no more band-cap dump call to check for - the shell snap no
	# longer takes a speed argument at all.
	failed += _check("ship_no_longer_dumps_a_band_cap",
		ship_src.find("band_speed_cap_units(shell_alt)") == -1)
	failed += _check("ship_has_dev_fast_air_drag",
		ship_src.find("_FM.dev_fast_air") >= 0 and ship_src.find("DEV_AIR_DRAG_MULT") >= 0)

	# 2026-09-09 entry handshake: ship.gd cannot be preloaded here (it touches the
	# Ephemeris autoload at parse time, unavailable under --script — see
	# test_chase_rig.gd's header comment), so wiring is a source check and the
	# formula itself is replicated below in pure math against ship.gd's own
	# constants (mirrored by name/value; touch one, touch both).
	failed += _check("ship_softens_entry_crossing",
		ship_src.find("ENTRY_SPEED_MAX_KMS") >= 0 and ship_src.find("hit.dropped") >= 0)
	failed += _check("ship_drag_is_a_per_substep_dv_clamp",
		ship_src.find("DRAG_MAX_DV_FRAC") >= 0 and ship_src.find("move_toward(Vector3.ZERO, dv)") >= 0)

	# Entry handshake: inbound crossing at 30 km/s must come back at ENTRY_SPEED_MAX_KMS,
	# not the raw incoming speed - ship.gd's _newton_advance scales hit.vel exactly this way.
	const ENTRY_SPEED_MAX_KMS := 3.0
	var v_in := Vector3(-30.0, 0.0, 0.0)
	var v_capped: Vector3 = v_in * (ENTRY_SPEED_MAX_KMS / v_in.length()) if v_in.length() > ENTRY_SPEED_MAX_KMS else v_in
	failed += _check("entry_crossing_softened_to_cap", is_equal_approx(v_capped.length(), ENTRY_SPEED_MAX_KMS))
	failed += _check("entry_crossing_keeps_heading", v_capped.normalized().dot(v_in.normalized()) > 0.999)

	# Drag clamp: a single substep must never remove more than 25% of speed - same
	# law _newton_atmo_drag uses (500 * NEWTON_BALLISTIC * rho * spd^2). NEWTON_BALLISTIC
	# is derived (2026-09-12) from FlightMode.air_ballistic/AIR_TERMINAL_KMS rather than
	# hand-picked (was a hardcoded 0.005 here and in ship.gd) — mirror the same call ship.gd
	# makes, using ship.gd's own NEWTON_THRUST/BOOST_MULT (mirrored below; touch one, touch both).
	const NEWTON_THRUST := 0.01962     # ship.gd:~342, 2 g in km/s^2
	const NEWTON_BOOST_MULT := 3.0     # ship.gd:~80, Shift multiplier
	var NEWTON_BALLISTIC: float = M.air_ballistic(NEWTON_THRUST, NEWTON_BOOST_MULT, E.RHO0)
	const DRAG_MAX_DV_FRAC := 0.25     # ship.gd, _newton_atmo_drag
	var spd40: float = 30.0
	var rho40: float = E.RHO0 * exp(-40.0 / E.EARTH_ATMO_H_KM)
	var acc40: float = 500.0 * NEWTON_BALLISTIC * rho40 * spd40 * spd40
	var dt_coarse := 0.05   # in_air substep from _newton_advance
	var dv40: float = minf(acc40 * dt_coarse, DRAG_MAX_DV_FRAC * spd40)
	failed += _check("drag_step_never_exceeds_quarter_speed", dv40 <= DRAG_MAX_DV_FRAC * spd40 + 1.0e-9)
	var rho0: float = E.RHO0 * exp(-0.0 / E.EARTH_ATMO_H_KM)
	var acc0: float = 500.0 * NEWTON_BALLISTIC * rho0 * spd40 * spd40
	var dv0: float = minf(acc0 * dt_coarse, DRAG_MAX_DV_FRAC * spd40)
	print("flight_mode: 30km/s @ 40km dv %.5f km/s; @ sea level dv %.5f km/s (clamp cap %.3f)"
		% [acc40 * dt_coarse, acc0 * dt_coarse, DRAG_MAX_DV_FRAC * spd40])
	# The 2026-09-12 derived ballistic is ~7500x weaker than the old hand-picked 0.005
	# (that was the whole point - see docs/ROADMAP.md L.3), so at any realistic in-air
	# speed (entry is itself capped to ENTRY_SPEED_MAX_KMS=3 km/s) this clamp no longer
	# binds - it's a dormant safety net now, not a routinely-hit path. Confirm that,
	# and separately confirm the clamp MECHANISM (not the flight-realistic scenario)
	# still binds given a large enough synthetic speed - the mechanism in ship.gd is
	# untouched by this rescale, only the coefficient it's fed is different.
	failed += _check("drag_clamp_no_longer_binds_at_synthetic_30kms",
		acc0 * dt_coarse < DRAG_MAX_DV_FRAC * spd40)
	# Derive a synthetic speed guaranteed to make the clamp bind, rather than a fixed
	# literal picked for one specific NEWTON_BALLISTIC scale (2026-09-12: a literal
	# 50000 was only large enough to bind under the then-12 km/s target's ballistic;
	# once AIR_TERMINAL_KMS moved to 50 the weaker derived ballistic made 50000 stop
	# binding, silently flipping this into a false pass). Solves acc*dt > cap*spd for
	# spd (acc = 500*ballistic*rho0*spd^2): spd_min_bind = cap/(500*ballistic*rho0*dt);
	# a 5x margin above that stays comfortably inside the binding regime for any
	# ballistic this rescale could plausibly produce.
	var spd_min_bind: float = DRAG_MAX_DV_FRAC / (500.0 * NEWTON_BALLISTIC * rho0 * dt_coarse)
	var spd_synthetic: float = 5.0 * spd_min_bind   # mechanism-only; not a reachable in-game speed
	var acc_synthetic: float = 500.0 * NEWTON_BALLISTIC * rho0 * spd_synthetic * spd_synthetic
	var dv_synthetic: float = minf(acc_synthetic * dt_coarse, DRAG_MAX_DV_FRAC * spd_synthetic)
	failed += _check("drag_clamp_mechanism_still_binds_given_enough_speed",
		acc_synthetic * dt_coarse > DRAG_MAX_DV_FRAC * spd_synthetic)
	failed += _check("drag_clamp_result_is_the_25pct_cap",
		is_equal_approx(dv_synthetic, DRAG_MAX_DV_FRAC * spd_synthetic))

	var hud_src := FileAccess.get_file_as_string("res://scripts/ui/hud.gd")
	failed += _check("hud_mode_line", hud_src.find("Mode    ") >= 0)
	failed += _check("hud_drop_tag", hud_src.find("DROP") >= 0)

	# DEV FASTAIR tour aid: no cap left to multiply, only weaker drag
	# (DEV_AIR_DRAG_MULT). The switch itself is a static shared with the real
	# game - always restore it to false at the end of the test.
	M.dev_fast_air = false
	failed += _check("dev_air_drag_mult_is_weaker", M.DEV_AIR_DRAG_MULT < 1.0)
	failed += _check("dev_fast_air_default_off", not M.dev_fast_air)
	M.dev_fast_air = true
	failed += _check("dev_fast_air_toggles_on", M.dev_fast_air)
	M.dev_fast_air = false
	failed += _check("fastair_switch_restored_false", not M.dev_fast_air)

	# Regression for the reported freeze: a snap-to-shell at large true_pos
	# magnitude used to land close enough to the boundary that float noise
	# (Vector3 in this Godot build is single-precision - real_t = 32-bit
	# float, not double) read it as still outside next frame, re-triggering
	# "dropped" forever with no position advance. Mirrors ship.gd's
	# _newton_advance loop shape (break_at_exclusion once per substep, no
	# early exit on a drop) without gravity/drag - this is a geometry
	# regression, not a gravity one.
	#
	# Scale note: this uses ~4.4e4 km (representative off-origin magnitude,
	# large enough to exercise the SAME catastrophic-cancellation category as
	# the reported Venus bug) rather than Venus's literal true ~1.2e8 km.
	# Two things were verified empirically (debug harnesses, not checked in)
	# while picking this number, both out of scope to fix here:
	#  1. AT Venus's actual magnitude, `pos += vel*dt` for a normal in-air
	#     substep (a few km/s * 0.05s, well under 1 km) is silently absorbed
	#     by Vector3's ~14 km ULP there - integration itself cannot advance.
	#  2. Also at Venus's magnitude, the eps this function needs (scaled to
	#     that ULP, ~450 km with the 32x safety margin) is bigger than the
	#     entire 250 km atmosphere shell, so the discrete "dropped" crossing
	#     event may never fire even once - the ship glides from "outside" to
	#     "already inside" without a detectable transition. There is no eps
	#     value that avoids BOTH failure modes (freeze vs never-fires) at
	#     that true magnitude with a Vector3 (single-precision) absolute
	#     position. Both are why the ship no longer flies in that frame at all
	#     (docs/adr/0002) — the anchored offset keeps every magnitude here
	#     small, and this off-centre case is what it looks like.
	# 4.4e4 km is the magnitude actually used below: big enough to demonstrate
	# the eps fix firing (a fixed mm/m tolerance, what this used to be, is
	# already smaller than the ULP here) while small enough that the eps this
	# scale needs (~190 m) stays well under a substep's advance (~300 m), so
	# the crossing still reliably fires exactly once — unlike literal Venus
	# magnitude, where it may not fire at all (see point 2 above).
	#
	# Note on substep count: the brief's illustrative "300 substeps of 0.05s"
	# (15s) cannot complete a 400 km approach at 6 km/s (needs ~67s to reach
	# the shell) - bumped to 1700 substeps (85s) so the scenario is internally
	# consistent and the ship both crosses and ends up comfortably (>50km)
	# past the shell within the run.
	var off_center := Vector3(3.0e4, 2.5e4, -2.0e4)
	var off_ez: float = M.exclusion_from_center(6051.8, 250.0, false)
	var off_run: Dictionary = _sim_crossing(off_center, off_ez, Vector3(1, 0, 0),
		400.0, 6.0, 0.05, 1700)
	failed += _check("offcenter_scale_crosses_exactly_once", int(off_run.drops) == 1)
	failed += _check("offcenter_scale_ends_well_inside",
		(Vector3(off_run.pos) - off_center).length() < off_ez - 50.0)
	failed += _check("offcenter_scale_alt_monotonic_after_cross", bool(off_run.monotonic))
	failed += _check("offcenter_scale_final_position_not_frozen_on_shell",
		absf((Vector3(off_run.pos) - off_center).length() - off_ez) > 50.0)

	# Same scenario anchored at the Earth-origin (small-magnitude) frame -
	# this always worked, kept as a regression that the eps/inside-snap
	# change did not alter Earth's existing behavior.
	var earth_run: Dictionary = _sim_crossing(Vector3.ZERO, earth_ez, Vector3(1, 0, 0),
		400.0, 6.0, 0.05, 1700)
	failed += _check("earth_scale_crosses_exactly_once", int(earth_run.drops) == 1)
	failed += _check("earth_scale_ends_well_inside",
		Vector3(earth_run.pos).length() < earth_ez - 50.0)
	failed += _check("earth_scale_alt_monotonic_after_cross", bool(earth_run.monotonic))

	# Outbound from inside must never drop, at the same off-origin magnitude
	# (the direction-blind gate is translation-invariant by construction, but
	# assert it explicitly away from the origin too).
	var inside_pos := off_center + Vector3(1, 0, 0) * (off_ez - 100.0)
	var outbound_vel := Vector3(1, 0, 0) * 5.0
	var never_dropped := true
	var p := inside_pos
	for i in range(50):
		var h: Dictionary = M.break_at_exclusion(p, outbound_vel, 0.1, off_center, off_ez)
		if bool(h.dropped):
			never_dropped = false
		p += outbound_vel * 0.1
	failed += _check("offcenter_scale_outbound_from_inside_never_drops", never_dropped)

	# The Venus freeze, now fixed by the anchored frame (docs/adr/0002). The raw
	# fact has not changed and cannot: an ABSOLUTE Vector3 at Venus's real ~1.2e8
	# km cannot represent a normal in-air substep. What changed is that physics no
	# longer runs there — the ship carries an offset from Venus itself, which is a
	# few thousand km, so the same delta lands intact.
	var venus_like := Vector3(1.2e8, 0.0, 0.0)
	var typical_substep_delta := Vector3(0.3, 0.0, 0.0)   # 6 km/s * 0.05s
	failed += _check("absolute_frame_still_swallows_the_substep_at_venus_scale",
		is_equal_approx((venus_like + typical_substep_delta).x, venus_like.x))
	# Same ship, same substep, measured from Venus's centre instead. 400 km up,
	# 3 km/s inbound, 300 substeps of 0.05 s: it must move and keep descending.
	var venus_off := Vector3(6051.8 + 400.0, 0.0, 0.0)
	var venus_start := venus_off
	var venus_vel := Vector3(-3.0, 0.0, 0.0)
	var venus_prev := venus_off.length()
	var venus_monotonic := true
	for i in range(300):
		venus_off += venus_vel * 0.05
		var vr := venus_off.length()
		if vr >= venus_prev:
			venus_monotonic = false
		venus_prev = vr
	failed += _check("anchored_frame_moves_at_venus_scale",
		(venus_off - venus_start).length() >= 40.0)
	failed += _check("anchored_frame_altitude_monotonic_at_venus_scale", venus_monotonic)
	# Saturn is 12x further out (~1.4e9 km, ~170 km ULP) and the anchor does not care.
	var saturn_off := Vector3(58232.0 + 900.0, 0.0, 0.0)
	var saturn_start := saturn_off
	for i in range(300):
		saturn_off += venus_vel * 0.05
	failed += _check("anchored_frame_moves_at_saturn_scale",
		(saturn_off - saturn_start).length() >= 40.0)

	if failed == 0:
		print("flight_mode: OK")
		quit(0)
	else:
		print("flight_mode: FAIL %d" % failed)
		quit(1)


# Regression harness for the reported freeze bug. Mirrors ship.gd's
# _newton_advance loop shape: break_at_exclusion once per substep, no early
# exit on a drop (that early exit was the bug), gravity-free (geometry only).
func _sim_crossing(center: Vector3, ez: float, dir: Vector3, start_alt_km: float,
		inbound_speed_kms: float, sub_dt: float, max_substeps: int) -> Dictionary:
	var pos: Vector3 = center + dir * (ez + start_alt_km)
	var vel: Vector3 = -dir * inbound_speed_kms
	var drops := 0
	var crossed := false
	var monotonic_after_cross := true
	var prev_alt := (pos - center).length() - ez
	for i in range(max_substeps):
		var hit: Dictionary = M.break_at_exclusion(pos, vel, sub_dt, center, ez)
		if bool(hit.dropped):
			pos = hit.pos
			vel = hit.vel
			var spd := vel.length()
			if spd > 3.0:
				vel = vel * (3.0 / spd)
			drops += 1
			crossed = true
		pos += vel * sub_dt
		var alt := (pos - center).length() - ez
		if crossed and alt > prev_alt + 1.0e-6:
			monotonic_after_cross = false
		prev_alt = alt
	return { "pos": pos, "drops": drops, "monotonic": monotonic_after_cross }


func _check(name: String, ok: bool) -> int:
	if not ok:
		print("flight_mode: FAIL %s" % name)
		return 1
	return 0
