class_name TestOnePhysics
extends Node
## One flight model (slice 2 of docs/plans/2026-09-29-one-physics-ripout.md):
## no arcade `newton` switch left in scripts/, the anchor frame free-falls with its
## body (GEO stays circular with the Sun pulling, a Moon-distance park does not
## drift sunward), a generated HYG system boots and falls at GM/r², and the combat
## fire gate. Needs ASTRYX_PROFILE_DIR (isolated here).
## godot --headless tools/test_one_physics.tscn  -> "one_physics: OK"
const ShipScript := preload("res://scripts/flight/ship.gd")
const DT := 1.0 / 60.0
const DAY_S := 86400.0
const GENERATED := "tau_ceti"
var failures := 0


func check(name: String, ok: bool) -> void:
	if not ok:
		failures += 1
		print("one_physics: FAIL ", name)


func _ready() -> void:
	ProfileDir.isolate("test_one_physics")
	_no_newton_switch()
	_geo_stays_circular()
	_moon_distance_no_sunward_drift()
	await _generated_system_boots()
	await get_tree().process_frame
	print("one_physics: ", "OK" if failures == 0 else "FAIL %d" % failures)
	get_tree().quit(0 if failures == 0 else 1)


func _no_newton_switch() -> void:
	var re := RegEx.create_from_string("\\.newton\\b|newton :=")
	var hits := []
	for path in _scripts("res://scripts"):
		var src := FileAccess.get_file_as_string(path)
		for m in re.search_all(src):
			hits.append("%s: %s" % [path, m.get_string()])
	print("one_physics: newton symbol hits in scripts/ = %d %s" % [hits.size(), hits])
	check("no_newton_symbol", hits.is_empty())


func _scripts(dir: String) -> Array:
	var out := []
	var d := DirAccess.open(dir)
	if d == null:
		return out
	for f in d.get_files():
		if f.ends_with(".gd"):
			out.append(dir.path_join(f))
	for sub in d.get_directories():
		out.append_array(_scripts(dir.path_join(sub)))
	return out


func _earth_ship() -> Ship:
	Ephemeris.switch_system(SystemDB.SOL)
	var ship: Ship = ShipScript.new()
	add_child(ship)
	ship.set_anchor("Earth")
	ship.nearest_name = "Earth"
	ship.nearest_radius = Ephemeris.body_radius_km("Earth")
	return ship


# One simulated day of the ship's own integrator (_newton_advance, 0.25 s substeps)
# at GEO with every gravity body on, the Sun included. Before the frame fix the
# Sun's direct pull (GM_sun / 1 AU² = 5.93e-6 km/s², 2.6 % of Earth's 2.24e-4 at
# GEO) went unbalanced and the orbit smeared by thousands of km in a day.
func _geo_stays_circular() -> void:
	var ship := _earth_ship()
	var r0 := Ephemeris.GEO_RADIUS_KM
	var sun := Ephemeris.rel_km("Sun", "Earth").normalized()
	var radial := sun.cross(Vector3.UP).normalized()
	ship.relocate(radial * r0)
	ship.velocity = radial.cross(Vector3.UP).normalized() * sqrt(Ephemeris.gm("Earth") / r0)
	var names := []
	for p in Ephemeris.gravity_bodies():
		names.append(str(p.name))
	check("sun_in_gravity_list", names.has("Sun"))
	var rmin := INF
	var rmax := 0.0
	var t0 := Time.get_ticks_msec()
	var step := 16.0   # 64 substeps of 0.25 s: MAX_SUBSTEPS, so no enlarged final substep
	var steps := int(DAY_S / step)
	for i in steps:
		ship.nearest_dist = ship.anchor_distance_km()
		ship.nearest_dir = -ship.anchor_off.normalized()
		ship.call("_newton_advance", step)
		var r := ship.anchor_distance_km()
		rmin = minf(rmin, r)
		rmax = maxf(rmax, r)
	print("one_physics: GEO 1 day  r %.3f..%.3f km  (r0 %.3f, spread %.5f %%)  %d ms" % [
		rmin, rmax, r0, 100.0 * (rmax - rmin) / r0, Time.get_ticks_msec() - t0])
	check("geo_radius_within_0p1pct", rmin > r0 * 0.999 and rmax < r0 * 1.001)
	check("geo_still_anchored_earth", ship.anchor_name == "Earth")
	ship.queue_free()


# At the Moon's distance the Sun's direct pull (5.93e-6 km/s²) is twice Earth's
# (GM_earth / 384400² = 2.70e-6). Parked perpendicular to the Sun line, in the
# free-falling frame only the tidal residue is left, and it has no sunward part
# there to first order: over an hour the sunward drift must stay under 1 % of the
# uncorrected 0.5 * g_sun * t² (38.4 km).
func _moon_distance_no_sunward_drift() -> void:
	var ship := _earth_ship()
	var sun := Ephemeris.rel_km("Sun", "Earth").normalized()
	var moon := Ephemeris.rel_km("Moon", "Earth").normalized()
	var side := sun.cross(moon)
	side = side.normalized() if side.length_squared() > 1.0e-6 else sun.cross(Vector3.UP).normalized()
	var r0 := 384400.0
	ship.relocate(side * r0)
	ship.velocity = Vector3.ZERO
	var g_sun := Ephemeris.gm("Sun") / pow(Ephemeris.rel_km("Sun", "Earth").length(), 2.0)
	var secs := 3600.0
	for i in int(secs / 16.0):
		ship.nearest_dist = ship.anchor_distance_km()
		ship.nearest_dir = -ship.anchor_off.normalized()
		ship.call("_newton_advance", 16.0)
	var moved := ship.anchor_off - side * r0
	var sunward := moved.dot(sun)
	var fell := r0 - ship.anchor_distance_km()
	var uncorrected := 0.5 * g_sun * secs * secs
	var earth_fall := 0.5 * Ephemeris.gm("Earth") / (r0 * r0) * secs * secs
	print("one_physics: Moon distance 1 h  sunward %.4f km (uncorrected %.2f)  fell toward Earth %.3f km (GM/r² %.3f)" % [
		sunward, uncorrected, fell, earth_fall])
	check("moon_distance_no_sunward_drift", absf(sunward) < 0.01 * uncorrected)
	# Earthward the fall is GM_earth/r² plus the Sun's perpendicular tidal squeeze
	# GM_sun·r/d³ = 1.5e-8 km/s² (+0.56 %), the Moon's residue and r shrinking
	# over the hour: ~1 % above GM/r² alone, hence the 2 % bound.
	check("moon_distance_falls_to_earth", absf(fell / earth_fall - 1.0) < 0.02)
	ship.queue_free()


func _generated_system_boots() -> void:
	var main: Node = preload("res://scripts/core/main.gd").new()
	add_child(main)
	main.set_process(false)
	await get_tree().process_frame
	main._arrive(GENERATED)
	var ship: Ship = main.ship
	var worlds := []
	for p in Ephemeris.live_worlds():
		worlds.append(str(p.name))
	check("generated_system_current", Ephemeris.system_id == GENERATED and Ephemeris.current() is GeneratedEphemeris)
	check("generated_anchor", ship.anchor_name == Ephemeris.spawn_body() and ship.anchor_name in worlds)
	check("generated_not_sol_body", not SolEphemeris.worlds().any(func(p): return p.name == ship.anchor_name))
	check("fire_allowed_in_flight", Combat.fire_allowed(ship))
	ship.velocity = Vector3.ZERO
	var anchor := ship.anchor_name
	var r0 := ship.anchor_distance_km()
	var g := Ephemeris.gm(anchor) / (r0 * r0)
	var secs := 10.0
	for i in int(secs / DT):
		main._process(DT)
	var fell := r0 - ship.anchor_distance_km()
	var predicted := 0.5 * g * secs * secs
	print("one_physics: %s  anchor %s  r0 %.1f km  fell %.5f km in %.0f s (GM/r² %.5f)" % [
		GENERATED, anchor, r0, fell, secs, predicted])
	check("generated_still_anchored", ship.anchor_name == anchor)
	check("generated_falls_gm_over_r2_1pct", absf(fell / predicted - 1.0) < 0.01)
	ship.frozen = true
	check("fire_blocked_docked", not Combat.fire_allowed(ship))
	ship.frozen = false
	ship.transiting = true
	check("fire_blocked_transiting", not Combat.fire_allowed(ship))
	ship.transiting = false
	main.queue_free()
	await get_tree().process_frame
