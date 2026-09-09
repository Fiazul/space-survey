extends Node
# The Ephemeris-backed half of the anchored frame (docs/adr/0002). Scene-based
# because Ephemeris is an autoload and `--script` runs have none:
#   godot --headless tools/test_anchor_frame.tscn
# The pure arithmetic lives in tools/test_anchor.gd.
const ShipScript := preload("res://scripts/flight/ship.gd")
const PS := preload("res://scripts/world/planet_system.gd")
const CombatScript := preload("res://scripts/combat/combat.gd")
const FM := preload("res://scripts/flight/flight_mode.gd")

var failures := 0


func _ready() -> void:
	_rel_km()
	_ship_moves_at_venus()
	_ship_moves_at_saturn()
	_reanchor_keeps_the_ship_still()
	_planet_system_agrees_with_the_legacy_path()
	_drag_model_gated_to_earth()
	_anchor_rejects_craft()
	_entry_handshake_survives_time_warp()
	_entry_edge_fires_on_every_frame_in_the_sweep()
	_combat_shift_frame_matches_ship()
	_legacy_save_lands_on_earth()
	_true_pos_handoff_continuity()
	if failures == 0:
		print("anchor_frame: OK")
	else:
		print("anchor_frame: FAIL %d" % failures)
	get_tree().quit(1 if failures > 0 else 0)


func _rel_km() -> void:
	check("earth_is_the_origin", Ephemeris.rel_km("Earth", "Earth") == Vector3.ZERO)
	check("earth_pos64_is_zero", Ephemeris.pos64("Earth") == PackedFloat64Array([0.0, 0.0, 0.0]))
	for pair in [["Venus", "Earth"], ["Saturn", "Moon"], ["Io", "Jupiter"]]:
		var a: Vector3 = Ephemeris.rel_km(pair[0], pair[1])
		var b: Vector3 = Ephemeris.rel_km(pair[1], pair[0])
		check("rel_km_antisymmetric_%s_%s" % [pair[0], pair[1]], (a + b).length() < 0.001)
	# Against Earth it must still be the position scene_pos has always reported.
	for body in ["Venus", "Mars", "Saturn", "Titan"]:
		var d: float = Ephemeris.rel_km(body, "Earth").distance_to(Ephemeris.scene_pos(body))
		check("rel_km_from_earth_matches_scene_pos_%s" % body, d < 1.0)
	check("unknown_body_is_not_anchorable", not Ephemeris.has_pos("Nowhere"))
	check("moons_are_anchorable", Ephemeris.has_pos("Titan") and Ephemeris.has_pos("Io"))
	# The moons pull too — the old planets-only sum silently dropped them.
	var names := []
	for b in Ephemeris.gravity_bodies():
		names.append(str(b.name))
	check("gravity_includes_physical_moons", names.has("Titan") and names.has("Europa"))
	check("gravity_excludes_craft", not names.has("Voyager 1"))


func _ship_moves_at_venus() -> void:
	_falls_toward("Venus", 400.0, 3.0, 20.0, 40.0)


func _ship_moves_at_saturn() -> void:
	_falls_toward("Saturn", 900.0, 3.0, 20.0, 40.0)


# The reported bug, end to end: a real Newton run at a real planet's real
# distance from Earth must actually move the ship and lose altitude.
func _falls_toward(body: String, start_alt: float, speed: float, secs: float,
		min_move: float) -> void:
	var ship := ShipScript.new()
	add_child(ship)
	ship.newton = true
	ship.set_anchor(body)
	check("%s_anchor_taken" % body, ship.anchor_name == body)
	var radius: float = Ephemeris.body_radius_km(body)
	var dir := Vector3(1.0, 0.0, 0.0)
	ship.anchor_off = dir * (radius + start_alt)
	ship.velocity = -dir * speed
	var alt0: float = ship.anchor_alt_km()
	var start: Vector3 = ship.anchor_off
	ship.call("_newton_advance", secs)
	var moved: float = (ship.anchor_off - start).length()
	check("%s_ship_actually_moves" % body, moved >= min_move)
	check("%s_altitude_drops" % body, ship.anchor_alt_km() < alt0 - min_move * 0.5)
	# The anchor sits at the origin of its own frame, exactly.
	check("%s_anchor_is_its_own_origin" % body,
		ship.to_body(body).distance_to(-ship.anchor_off) < 1.0e-6)
	ship.queue_free()


func _reanchor_keeps_the_ship_still() -> void:
	var ship := ShipScript.new()
	add_child(ship)
	ship.newton = true
	var moon: Vector3 = Ephemeris.rel_km("Moon", "Earth")
	ship.anchor_off = moon * 0.5              # halfway out to the Moon
	ship.velocity = Vector3(1.5, -0.25, 3.0)
	var to_moon_before: Vector3 = ship.to_body("Moon")
	var to_earth_before: Vector3 = ship.to_body("Earth")
	var vel_before: Vector3 = ship.velocity
	ship.set_anchor("Moon")
	check("anchor_switched", ship.anchor_name == "Moon")
	check("reanchor_moon_vector_within_1m",
		to_moon_before.distance_to(ship.to_body("Moon")) < 0.001)
	check("reanchor_earth_vector_within_1m",
		to_earth_before.distance_to(ship.to_body("Earth")) < 0.001)
	check("reanchor_velocity_unchanged", ship.velocity == vel_before)
	ship.set_anchor("Earth")
	check("reanchor_back_is_reversible",
		ship.anchor_off.distance_to(moon * 0.5) < 0.001)
	# An absolute fixture (a Sol wormhole portal sits ~80,000 km out) renders at
	# the same offset whichever body the ship is anchored to.
	var portal := Vector3(80000.0, 0.0, 0.0)
	var portal_from_earth: Vector3 = ship.rel_to(portal)
	ship.set_anchor("Moon")
	check("rel_to_absolute_survives_reanchor",
		portal_from_earth.distance_to(ship.rel_to(portal)) < 0.001)
	ship.queue_free()


# Near Earth the anchored and legacy paths must produce the same render offsets —
# that is the regression guard on everything downstream of _rel.
func _planet_system_agrees_with_the_legacy_path() -> void:
	var planets := PS.new()
	add_child(planets)
	var here := Vector3(42157.0, 0.0, 0.0)
	planets.refresh(here, 0.0)
	var legacy := {}
	for name in ["Moon", "Venus", "Mars", "Sun"]:
		legacy[name] = planets.rel_of(name)
	planets.refresh(here, 0.0, "Earth")
	for name in legacy:
		check("anchored_rel_matches_legacy_%s" % name,
			planets.rel_of(name).distance_to(legacy[name]) < 1.0)
	planets.queue_free()


# Finding 5: air_load/mach/drag/corotate must all agree — Earth is the only
# body with a density model, so nothing Earth-shaped fires near Venus (which
# HAS an atmosphere in Ephemeris.ATMO_TOP_KM, just no matching drag model yet).
func _drag_model_gated_to_earth() -> void:
	check("earth_has_drag_model", FM.has_drag_model("Earth"))
	check("venus_no_drag_model", not FM.has_drag_model("Venus"))
	check("venus_has_atmo_but_no_drag_model", Ephemeris.atmo_top_km("Venus") > 0.0)

	var venus := ShipScript.new()
	add_child(venus)
	venus.newton = true
	venus.set_anchor("Venus")
	var v_alt := Ephemeris.body_radius_km("Venus") + 50.0
	venus.anchor_off = Vector3(1.0, 0.0, 0.0) * v_alt
	venus.velocity = Vector3(-3.0, 0.0, 0.0)
	var v_vel_before: Vector3 = venus.velocity
	venus.call("_newton_atmo_drag", 0.05)
	check("venus_drag_noop", venus.velocity == v_vel_before)
	var v_off_before: Vector3 = venus.anchor_off
	venus.call("_newton_corotate", 0.05)
	check("venus_corotate_noop", venus.anchor_off == v_off_before)
	check("venus_zone_still_air", Ephemeris.flight_zone("Venus", v_alt) == "AIR")
	venus.queue_free()

	# Earth unchanged: drag still fires there.
	var earth := ShipScript.new()
	add_child(earth)
	earth.newton = true
	earth.set_anchor("Earth")
	earth.anchor_off = Vector3(1.0, 0.0, 0.0) * (Ephemeris.EARTH_RADIUS_KM + 50.0)
	earth.velocity = Vector3(-3.0, 0.0, 0.0)
	var e_vel_before: Vector3 = earth.velocity
	earth.call("_newton_atmo_drag", 0.05)
	check("earth_drag_still_fires", earth.velocity != e_vel_before)
	earth.queue_free()


# Craft (Voyager 1/2) drift — anchoring there would clamp the ship at a moving
# point while the render drifts away (docs/adr/0002 finding 3). Mirrors the
# guard in main._anchor_ship / Ship.set_anchor.
func _anchor_rejects_craft() -> void:
	var ship := ShipScript.new()
	add_child(ship)
	ship.newton = true
	ship.set_anchor("Earth")
	check("voyager_has_pos", Ephemeris.has_pos("Voyager 1"))
	check("voyager_not_anchorable", not Ephemeris.is_anchorable("Voyager 1"))
	var shift: Vector3 = ship.set_anchor("Voyager 1")
	check("anchor_unchanged_for_craft", ship.anchor_name == "Earth" and shift == Vector3.ZERO)
	ship.queue_free()


# Finding 1: nearest_dir/nearest_dist are frozen for the whole _newton_advance
# call while anchor_off advances across substeps at time warp. A radial dive
# from GEO-range altitude at rate 100 and 1000 must fire the entry handshake
# EXACTLY once, cap speed at the crossing, and never reach the surface.
func _entry_handshake_survives_time_warp() -> void:
	for rate in [100.0, 1000.0]:
		var ship := ShipScript.new()
		add_child(ship)
		ship.newton = true
		ship.set_anchor("Earth")
		var dir := Vector3(1.0, 0.0, 0.0)
		ship.anchor_off = dir * (Ephemeris.EARTH_RADIUS_KM + 42000.0)
		ship.velocity = -dir * 100.0
		ship.nearest_name = "Earth"
		ship.nearest_dir = -dir
		ship.nearest_dist = ship.anchor_off.length()
		ship.time_rate = rate
		var drops := 0
		var capped_ok := true
		var hit_ground := false
		var delta := 1.0 / 60.0
		for f in range(500):
			var prev_outside: bool = ship._was_outside_shell
			ship.nearest_dist = ship.anchor_off.length()   # main refreshes this once per real frame
			var sim: float = delta * ship.time_rate
			ship.call("_newton_advance", sim)
			var now_outside: bool = ship._was_outside_shell
			if prev_outside and not now_outside:
				drops += 1
				# Checked after the WHOLE _newton_advance call, which can run several
				# more substeps past the crossing one at high warp (gravity keeps
				# acting — "no cap once you're flying inside the air"). A loose bound
				# still tells apart "the handshake fired" from the old bug (still
				# diving at the pre-entry ~100 km/s).
				if ship.velocity.length() > ShipScript.ENTRY_SPEED_MAX_KMS * 2.0:
					capped_ok = false
			if ship.anchor_off.length() <= Ephemeris.EARTH_RADIUS_KM:
				hit_ground = true
				break
		check("entry_drop_fires_once_rate_%d" % int(rate), drops == 1)
		check("entry_speed_capped_rate_%d" % int(rate), capped_ok)
		check("entry_no_surface_impact_rate_%d" % int(rate), not hit_ground)
		ship.queue_free()


# Finding 2: break_at_exclusion's own "already inside" eps used to swallow ~40%
# of entries at Earth's shell (a 3 km/s frame travels ~50 m, well inside the
# old 24.6 m tolerance). Sweep 40 starts spanning one frame's travel at two
# speeds — the ship-side edge (_was_outside_shell) must fire on every one,
# independent of break_at_exclusion's own tolerance.
func _entry_edge_fires_on_every_frame_in_the_sweep() -> void:
	var ez: float = Ephemeris.EARTH_RADIUS_KM + Ephemeris.atmo_top_km("Earth")
	var delta := 1.0 / 60.0
	var n := 40
	for spd in [3.0, 8.0]:
		var travel: float = spd * delta
		var fired := 0
		for i in range(n):
			var ship := ShipScript.new()
			add_child(ship)
			ship.newton = true
			ship.set_anchor("Earth")
			var frac: float = 0.02 + 0.96 * (float(i) / float(n - 1))   # (0.02 .. 0.98) of travel
			var dir := Vector3(1.0, 0.0, 0.0)
			ship.anchor_off = dir * (ez + travel * frac)                # genuinely outside
			ship.velocity = -dir * spd
			ship.nearest_name = "Earth"
			ship.nearest_dir = -dir
			ship.nearest_dist = ship.anchor_off.length()
			ship._was_outside_shell = true
			ship._shell_edge_known = true
			ship.drop_flash = 0.0
			ship.call("_newton_advance", delta)
			if ship.drop_flash > 0.0:
				fired += 1
			ship.queue_free()
		check("entry_edge_fires_all_%d_starts_at_%dkms" % [n, int(spd)], fired == n)


# Finding 7: combat.shift_frame must keep an alien's ship-relative position
# invariant across the same reanchor main._anchor_ship applies to the ship.
func _combat_shift_frame_matches_ship() -> void:
	var ship := ShipScript.new()
	add_child(ship)
	ship.newton = true
	ship.set_anchor("Earth")
	ship.anchor_off = Vector3(6800.0, 300.0, -150.0)
	var combat := CombatScript.new()
	add_child(combat)
	var alien := { "pos": ship.anchor_off + Vector3(120.0, -40.0, 60.0), "vel": Vector3.ZERO, "hp": 10 }
	combat._aliens.append(alien)
	var rel_before: Vector3 = alien.pos - ship.anchor_off
	var shift: Vector3 = ship.set_anchor("Moon")   # main._anchor_ship-equivalent
	combat.shift_frame(shift)
	var rel_after: Vector3 = alien.pos - ship.anchor_off
	check("combat_shift_frame_keeps_alien_ship_relative",
		rel_before.distance_to(rel_after) < 0.001)
	combat.queue_free()
	ship.queue_free()


# Finding 7: a pre-anchor save has only "pos" (Earth-centred by definition).
# Exercise the REAL decode path — Ship.true_pos's setter against the default
# "Earth" anchor — not AF.decompose(x, ZERO64) == x (tautological against
# itself, catches nothing).
func _legacy_save_lands_on_earth() -> void:
	var ship := ShipScript.new()
	add_child(ship)
	ship.newton = true
	check("fresh_ship_anchors_earth", ship.anchor_name == "Earth")
	var legacy_pos := Vector3(42157.0, 0.0, 0.0)
	ship.true_pos = legacy_pos
	check("legacy_pos_only_save_lands_on_earth_within_1m",
		ship.anchor_off.distance_to(legacy_pos) < 0.001 and ship.anchor_name == "Earth")
	ship.queue_free()


# Finding 7: the LEGACY absolute round-trip (Ship.true_pos, ADR §3) genuinely
# loses precision across a reanchor — about one ULP of the anchor body's own
# absolute magnitude — unlike to_body()/rel_to() above, which are exact by
# construction (same rel_km() call feeds both sides of the comparison). A 1 mm
# bound here is impossible: at the Moon's own ~384,400 km magnitude a float32
# ULP is already ~46 m, two orders of magnitude above 1 mm. Measured via
# true_pos: ~8 m at Earth<->Moon (GEO altitude), up to ~4 km at Saturn<->Titan
# (bigger anchor magnitude, bigger ULP) — offset-dependent, bounded generously.
func _true_pos_handoff_continuity() -> void:
	var cases = [
		["Earth", "Moon", Vector3(42157.0, 0.0, 0.0), 8.0],
		# Saturn's own absolute magnitude (~1.42e9 km) has a much bigger ULP
		# (~169 km) than Earth's (~1.5e8 km, ~18 m) — measured worst case found
		# here is ~4 km, still far under the full-ULP ceiling.
		["Saturn", "Titan", Vector3(-4071.528, -7890.471, 4084.947), 6000.0],
	]
	for c in cases:
		var a: String = c[0]
		var b: String = c[1]
		var off: Vector3 = c[2]
		var bound: float = c[3]
		var ship := ShipScript.new()
		add_child(ship)
		ship.newton = true
		ship.set_anchor(a)
		ship.anchor_off = off
		var true_before: Vector3 = ship.true_pos
		ship.set_anchor(b)
		var true_after: Vector3 = ship.true_pos
		var err_m := true_before.distance_to(true_after) * 1000.0
		check("true_pos_handoff_%s_%s_within_bound" % [a, b], err_m < bound)
		check("true_pos_handoff_%s_%s_not_submillimeter" % [a, b], err_m > 0.001)
		ship.queue_free()


func check(name: String, ok: bool) -> void:
	if not ok:
		print("anchor_frame: FAIL %s" % name)
		failures += 1
