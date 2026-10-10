class_name TestBlackHolePlunge
extends Node
## Pseudo-Newtonian Kerr ship gravity at Sgr A* (BlackHoleGravity): circular orbits at
## 20 r_g hold through time warp at 60 and 20 fps, a start inside the ISCO
## enters forced capture, the force law's ISCO matches the recipe, Sol's
## inverse-square gravity is untouched, and the fear cues read the real orbit.
## godot --headless tools/test_black_hole_plunge.tscn  -> "black_hole_plunge: OK"
const ShipScript := preload("res://scripts/flight/ship.gd")
const BHG := preload("res://scripts/flight/black_hole_gravity.gd")
const RECIPE := preload("res://scripts/world/black_hole_recipe.gd")
const HUD_SCRIPT := preload("res://scripts/ui/hud.gd")
const HOLE := "Sagittarius A*"
const PROGRADE := Vector3(0, 0, 1)   # r along +X, v along +Z: L along -Y = SPIN_AXIS
var failures := 0


func check(name: String, ok: bool) -> void:
	if not ok:
		failures += 1
		print("black_hole_plunge: FAIL ", name)


func _ready() -> void:
	ProfileDir.isolate("test_black_hole_plunge")
	_sol_unchanged()
	_isco_matches_recipe()
	_circular_orbit(60.0, 20.0)
	_circular_orbit(20.0, 20.0)
	_inside_isco_plunges()
	_warnings()
	_cues()
	await get_tree().process_frame
	print("black_hole_plunge: ", "OK" if failures == 0 else "FAIL %d" % failures)
	get_tree().quit(0 if failures == 0 else 1)


func _recipe() -> Dictionary:
	return RECIPE.resolve(SystemDB.star_row(SystemDB.SAGITTARIUS_A)).stellar


func _hole_ship() -> Ship:
	Ephemeris.switch_system(SystemDB.SAGITTARIUS_A)
	var ship: Ship = ShipScript.new()
	add_child(ship)
	ship.set_anchor(HOLE)
	ship.nearest_name = HOLE
	ship.nearest_radius = Ephemeris.body_radius_km(HOLE)
	return ship


# One fly()-shaped frame at the highest requested warp the hole clamp allows.
func _frame(ship: Ship, delta: float) -> float:
	ship._time_idx = Ship.TIME_RATES.size() - 1
	ship.time_rate = Ship.TIME_RATES[ship._time_idx]
	ship._clamp_hole_warp(delta)
	ship.nearest_dist = ship.anchor_distance_km()
	ship.nearest_dir = -ship.anchor_off.normalized()
	var sim := delta * ship.time_rate
	ship._newton_advance(sim)
	return sim


func _sol_unchanged() -> void:
	Ephemeris.switch_system(SystemDB.SOL)
	check("sol_has_no_black_hole", Ephemeris.black_hole().is_empty())
	var ship: Ship = ShipScript.new()
	add_child(ship)
	ship.set_anchor("Earth")
	var r0 := Ephemeris.GEO_RADIUS_KM
	ship.relocate(Vector3(r0, 0, 0))
	ship.velocity = Vector3(0, 0, 3.07)
	var got := ship._newton_g()
	# Reference: the plain inverse-square sum with the anchor-frame subtraction.
	var a64 := ship.anchor64()
	var gx := 0.0
	var gy := 0.0
	var gz := 0.0
	for p in Ephemeris.gravity_bodies():
		var b64: PackedFloat64Array = Ephemeris.pos64(str(p.name))
		var ax: float = b64[0] - a64[0]
		var ay: float = b64[1] - a64[1]
		var az: float = b64[2] - a64[2]
		var rx := ax - float(ship.anchor_off.x)
		var ry := ay - float(ship.anchor_off.y)
		var rz := az - float(ship.anchor_off.z)
		var d2 := rx*rx + ry*ry + rz*rz
		var a2 := ax*ax + ay*ay + az*az
		var mu: float = float(p.mu)
		if mu / d2 < Ship.NEWTON_G_SKIP_THRESHOLD and mu / maxf(a2, 1.0e-6) < Ship.NEWTON_G_SKIP_THRESHOLD:
			continue
		if d2 > 1.0e-6:
			var k := mu / (d2 * sqrt(d2))
			gx += rx * k
			gy += ry * k
			gz += rz * k
		if a2 > 1.0e-6:
			var ka := mu / (a2 * sqrt(a2))
			gx -= ax * ka
			gy -= ay * ka
			gz -= az * ka
	check("sol_gravity_bit_identical", got == Vector3(gx, gy, gz))
	var tangent := Vector3(0, 0, 1)
	check("sol_circular_velocity_newtonian", Ephemeris.circular_velocity("Earth", ship.anchor_off, tangent)
		== tangent * sqrt(Ephemeris.gm("Earth") / r0))
	ship._time_idx = Ship.TIME_RATES.size() - 1
	ship.time_rate = Ship.TIME_RATES[ship._time_idx]
	ship._clamp_hole_warp(1.0 / 20.0)
	check("sol_warp_untouched", ship.time_rate == Ship.TIME_RATES[-1])
	ship._update_hole_cues(1.0 / 60.0)
	check("sol_no_hole_cues", ship.hole_orbit.is_empty() and ship._shake_deg == 0.0)
	ship.queue_free()


# L² = g r³ for circular orbits; its minimum is the ISCO. Measured through the
# ship's own _newton_g, prograde in the disk plane.
func _isco_matches_recipe() -> void:
	var ship := _hole_ship()
	var stellar := _recipe()
	var hole := Ephemeris.black_hole()
	var r_g: float = hole.r_g
	var best_r := 0.0
	var best_l2 := INF
	var x := 1.5
	while x < 8.0:
		var r := x * r_g
		ship.relocate(Vector3(r, 0, 0))
		ship.velocity = PROGRADE * 1.0e5
		var l2 := ship._newton_g().length() * r * r * r
		if l2 < best_l2:
			best_l2 = l2
			best_r = r
		x += 0.001
	var isco: float = stellar.get("isco_km", BHG.isco_rg(float(stellar.get("spin", 0.0))) * r_g)
	print("black_hole_plunge: force-law ISCO %.4f r_g, recipe %.4f r_g (spin %.3f)" % [best_r / r_g, isco / r_g, hole.spin])
	check("isco_within_3pct", absf(best_r / isco - 1.0) < 0.03)
	# Marginally bound: circular orbit with zero total energy.
	var lo: float = hole.horizon_km * 1.0001
	var hi: float = best_r
	for i in 60:
		var mid := (lo + hi) * 0.5
		var e := 0.5 * BHG.pull(hole, mid, hole.spin) * mid + BHG.potential(hole, mid, hole.spin)
		if e > 0.0:
			lo = mid
		else:
			hi = mid
	var mb: float = stellar.get("marginally_bound_km", BHG.marginally_bound_rg(hole.spin) * r_g)
	print("black_hole_plunge: force-law marginally bound %.4f r_g, Kerr %.4f r_g" % [hi / r_g, mb / r_g])
	check("marginally_bound_within_3pct", absf(hi / mb - 1.0) < 0.03)
	check("horizon_is_kill_radius", is_equal_approx(hole.horizon_km, Ephemeris.body_radius_km(HOLE)))
	ship.queue_free()


func _circular_orbit(fps: float, x: float) -> void:
	var ship := _hole_ship()
	var hole := Ephemeris.black_hole()
	var r0: float = x * hole.r_g
	ship.relocate(Vector3(r0, 0, 0))
	ship.velocity = Ephemeris.circular_velocity(HOLE, ship.anchor_off, PROGRADE)
	var period := TAU * r0 / ship.velocity.length()
	var t := 0.0
	var frames := 0
	var rmin := INF
	var rmax := 0.0
	var warp_min := INF
	var t0 := Time.get_ticks_msec()
	while t < 5.0 * period and frames < 200000:
		t += _frame(ship, 1.0 / fps)
		warp_min = minf(warp_min, ship.time_rate)
		frames += 1
		var r := ship.anchor_distance_km()
		rmin = minf(rmin, r)
		rmax = maxf(rmax, r)
	print("black_hole_plunge: %.0f r_g @ %d fps  5 orbits (%.0f s) in %d frames, warp ×%.0f  r %.4f..%.4f r0  %d ms" % [
		x, fps, 5.0 * period, frames, warp_min, rmin / r0, rmax / r0, Time.get_ticks_msec() - t0])
	check("orbit_%.0frg_within_1pct_%dfps" % [x, fps], rmin > 0.99 * r0 and rmax < 1.01 * r0 and not ship.horizon_crossed)
	check("warp_clamped_near_hole_%.0frg_%dfps" % [x, fps], warp_min < Ship.TIME_RATES[-1])
	ship.queue_free()


func _inside_isco_plunges() -> void:
	var ship := _hole_ship()
	var hole := Ephemeris.black_hole()
	var r0: float = 0.95 * float(_recipe().get("isco_km", hole.isco_km))
	ship.relocate(Vector3(r0, 0, 0))
	ship.velocity = Ephemeris.circular_velocity(HOLE, ship.anchor_off, PROGRADE)
	var start := BHG.orbit(hole, ship.anchor_off, ship.velocity, ship.max_thrust_accel())
	check("start_below_isco", start.r < start.isco_km)
	var period := TAU * r0 / ship.velocity.length()
	var t := 0.0
	var frames := 0
	while not ship.horizon_crossed and t < 20.0 * period:
		t += _frame(ship, 1.0 / 60.0)
		frames += 1
	print("black_hole_plunge: 0.95 ISCO start: horizon crossed=%s after %.0f s (%.2f orbits, %d frames)" % [
		ship.horizon_crossed, t, t / period, frames])
	check("inside_isco_crosses_horizon", ship.horizon_crossed)
	ship._update_hole_cues(0.0)
	var hud: Node = HUD_SCRIPT.new()
	check("gameplay_capture_has_unconditional_no_escape_cue", ship.hole_captured and "CORE CAPTURE — NO ESCAPE" in hud.hole_warnings(ship.hole_orbit))
	hud.free()
	ship.queue_free()


func _warnings() -> void:
	Ephemeris.switch_system(SystemDB.SAGITTARIUS_A)
	var hole := Ephemeris.black_hole()
	var r_g: float = hole.r_g
	var hud: Node = HUD_SCRIPT.new()
	var thrust := ShipScript.NEWTON_THRUST * ShipScript.BOOST_MULT
	var rel := Vector3(10.0 * r_g, 0, 0)
	var o := BHG.orbit(hole, rel, Ephemeris.circular_velocity(HOLE, rel, PROGRADE), thrust)
	var x := 10.0
	var a: float = hole.spin
	var kerr_rate := sqrt(1.0 - 3.0/x + 2.0*a*pow(x, -1.5)) / (1.0 + a*pow(x, -1.5))
	print("black_hole_plunge: 10 r_g clock %.4f (Kerr circular %.4f)  warnings: %s" % [o.clock_rate, kerr_rate, hud.hole_warnings(o).replace("\n", " | ")])
	check("stable_orbit_no_plunge", not o.plunging and o.r > o.isco_km)
	check("clock_rate_near_kerr", absf(o.clock_rate / kerr_rate - 1.0) < 0.02)
	check("stable_orbit_only_clock_line", hud.hole_warnings(o).strip_edges().begins_with("SHIP CLOCK"))
	rel = Vector3(0.95 * hole.isco_km, 0, 0)
	o = BHG.orbit(hole, rel, Ephemeris.circular_velocity(HOLE, rel, PROGRADE) * 0.999, thrust)
	check("decaying_below_isco", "PLUNGE" in hud.hole_warnings(o) or "ORBIT DECAYING" in hud.hole_warnings(o))
	# Dropped from rest at 20 r_g: no angular momentum, nothing stops the fall. Boosted
	# 3 g held to the horizon is ~10^2 km/s against a ~10^4 km/s burn; dev thrust is not.
	rel = Vector3(20.0 * r_g, 0, 0)
	o = BHG.orbit(hole, rel, Vector3.ZERO, thrust)
	print("black_hole_plunge: rest at 20 r_g  fall %.0f s, burn %.0f km/s, thrust gives %.0f km/s" % [o.fall_s, o.dv_kms, thrust * o.fall_s])
	check("radial_fall_plunges_no_escape", o.plunging and o.no_escape and "NO ESCAPE AT CURRENT THRUST" in hud.hole_warnings(o))
	o = BHG.orbit(hole, rel, Vector3.ZERO, thrust * ShipScript.DEV_THRUST_MULT)
	check("dev_thrust_can_escape", o.plunging and not o.no_escape and "BURN" in hud.hole_warnings(o))
	_braked_at_1au(hole, thrust, hud)
	rel = Vector3(1.5 * r_g, 0, 0)
	o = BHG.orbit(hole, rel, Ephemeris.circular_velocity(HOLE, rel, PROGRADE), thrust)
	check("photon_orbit_line", o.r < o.photon_km and "PHOTON ORBIT" in hud.hole_warnings(o))
	rel = Vector3(2000.0 * r_g, 0, 0)
	o = BHG.orbit(hole, rel, Ephemeris.circular_velocity(HOLE, rel, PROGRADE), thrust)
	check("far_orbit_quiet", hud.hole_warnings(o) == "")
	hud.free()


func _cues() -> void:
	var hole := Ephemeris.black_hole()
	var isco_hz := BHG.kepler_hz(hole, hole.isco_km, hole.spin)
	print("black_hole_plunge: drone %.1f Hz at ISCO, %.1f Hz at horizon" % [
		isco_hz * GameAudio.HOLE_DRONE_TIME_SCALE, BHG.kepler_hz(hole, hole.horizon_km, hole.spin) * GameAudio.HOLE_DRONE_TIME_SCALE])
	check("drone_audible_at_isco", absf(GameAudio.hole_drone_pitch(isco_hz) * GameAudio.HOLE_DRONE_BASE_HZ - isco_hz * GameAudio.HOLE_DRONE_TIME_SCALE) < 1.0)
	check("drone_silent_far", GameAudio.hole_drone_db(BHG.proximity(hole, 7.0 * hole.isco_km, hole.spin, 6.0)) == GameAudio.HOLE_DRONE_OFF_DB)
	check("drone_louder_closer", GameAudio.hole_drone_db(BHG.proximity(hole, 1.2 * hole.isco_km, hole.spin, 6.0))
		> GameAudio.hole_drone_db(BHG.proximity(hole, 4.0 * hole.isco_km, hole.spin, 6.0)))
	var ship := _hole_ship()
	ship.relocate(Vector3(1.5 * hole.isco_km, 0, 0))
	ship.velocity = Ephemeris.circular_velocity(HOLE, ship.anchor_off, PROGRADE)
	var pos := ship.anchor_off
	var vel := ship.velocity
	for i in 120:
		ship._update_hole_cues(1.0 / 60.0)
		ship._update_camera(1.0 / 60.0)
	check("shake_inside_3_isco", ship._shake_deg > 0.0 and ship._shake_deg < 1.3)
	check("cues_never_move_ship", ship.anchor_off == pos and ship.velocity == vel)
	ship.relocate(Vector3(4.0 * hole.isco_km, 0, 0))
	ship._shake_deg = 0.0
	ship._update_hole_cues(1.0 / 60.0)
	check("no_shake_beyond_3_isco", ship._shake_deg == 0.0)
	ship.relocate(Vector3(7.9 * Ephemeris.KM_PER_AU, 0, 0))
	ship.velocity = Vector3.ZERO
	ship.hole_orbit = {}
	ship._update_hole_cues(1.0 / 60.0)
	check("far_radial_fall_is_a_plunge_but_quiet", ship.hole_orbit.plunging and ship._shake_deg == 0.0
		and BHG.proximity(hole, ship.anchor_off.length(), 0.0, 6.0) == 0.0)
	ship.queue_free()


# In-game report: braked to near rest at 1.21 AU (~30 r_g), 5.48 km/s inbound. The
# HUD once offered "BURN 5.48 km/s" — cancelling the fall, which still plunges with no
# angular momentum. The burn must be the one that really escapes, checked in the sim.
func _braked_at_1au(hole: Dictionary, thrust: float, hud: Node) -> void:
	var rel := Vector3(1.21 * Ephemeris.KM_PER_AU, 0, 0)
	var inbound := Vector3(-5.48, 0, 0)
	var t0 := Time.get_ticks_usec()
	var o := BHG.orbit(hole, rel, inbound, thrust)
	var cost_ms := (Time.get_ticks_usec() - t0) / 1000.0
	print("black_hole_plunge: braked at 1.21 AU (%.1f r_g): burn %.0f km/s (%.0f°from outward), fall %.0f s, thrust gives %.0f km/s, %.1f ms  HUD: %s" % [
		rel.x / hole.r_g, o.dv_kms, rad_to_deg(o.burn.angle_to(rel)), o.fall_s, thrust * o.fall_s, cost_ms,
		hud.hole_warnings(o).replace("\n", " | ")])
	check("braked_plunges_no_escape", o.plunging and o.no_escape and "NO ESCAPE AT CURRENT THRUST" in hud.hole_warnings(o))
	check("braked_burn_is_orbital_scale", o.dv_kms > 20000.0 and o.dv_kms < BHG.C_KM_S)
	check("cancelling_fall_alone_still_plunges", BHG.plunges(hole, rel, Vector3.ZERO))
	check("burn_escapes_per_model", not BHG.plunges(hole, rel, inbound + o.burn))
	check("80pct_of_burn_still_plunges", BHG.plunges(hole, rel, inbound + o.burn * 0.8))
	# Fly it: gameplay capture shortens the physical fall. Even the physical escape
	# burn is captured when its trajectory enters the separate 0.6 AU boundary.
	var ship := _hole_ship()
	ship.relocate(rel)
	ship.velocity = inbound
	var t := 0.0
	while not ship.horizon_crossed and t < 4.0 * o.fall_s:
		t += _frame(ship, 1.0 / 60.0)
	print("black_hole_plunge: braked, engines off: horizon at %.0f s (predicted %.0f s)" % [t, o.fall_s])
	check("capture_finishes_by_physical_fall_prediction", ship.horizon_crossed and ship.hole_captured and t <= 1.1*o.fall_s)
	ship.relocate(rel)
	ship.velocity = inbound + o.burn
	ship.horizon_crossed = false
	var period := TAU * sqrt(pow(rel.x, 3.0) / float(hole.gm))
	var rmin := INF
	t = 0.0
	while not ship.horizon_crossed and t < 3.0 * period:
		t += _frame(ship, 1.0 / 60.0)
		rmin = minf(rmin, ship.anchor_distance_km())
	print("black_hole_plunge: braked + burn: periapsis %.2f r_g over %.0f s, horizon crossed=%s" % [rmin / hole.r_g, t, ship.horizon_crossed])
	check("physical_escape_burn_cannot_override_gameplay_capture", ship.horizon_crossed and ship.hole_captured and rmin <= Ship.HOLE_CAPTURE_AU*Ephemeris.KM_PER_AU)
	ship.queue_free()
