extends SceneTree
# Anchored ship frame (docs/adr/0002), pure arithmetic — no autoloads, so this
# runs under `godot --headless --script`. The Ephemeris-backed half lives in
# tools/test_anchor_frame.tscn.
const AF := preload("res://scripts/flight/anchor_frame.gd")

# Real geocentric distances, km. Venus is where the reported freeze happened.
var VENUS64 := PackedFloat64Array([-8.28e7, 6.78e7, 1.40e8])
var SATURN64 := PackedFloat64Array([1.42e9, 7.51e7, 3.21e8])
var MOON64 := PackedFloat64Array([2.99e5, 1.20e5, 2.09e5])

var failed := 0


func _init() -> void:
	_absolute_frame_is_the_bug()
	_round_trip_costs_about_one_ulp(VENUS64, "venus")
	_round_trip_costs_about_one_ulp(SATURN64, "saturn")
	_reanchor_continuity()
	_save_round_trip()
	if failed == 0:
		print("anchor: OK")
		quit(0)
	else:
		print("anchor: FAIL %d" % failed)
		quit(1)


# The premise. Vector3 is 32-bit in this engine build, so an absolute position at
# Venus's real distance cannot even represent a substep of motion. This is not a
# regression to fix — it is why the anchor exists, and it must stay true.
func _absolute_frame_is_the_bug() -> void:
	var abs_pos := AF.absolute(VENUS64, Vector3(6451.8, 0.0, 0.0))
	var after: Vector3 = abs_pos + Vector3(0.15, 0.0, 0.0)   # 3 km/s * 0.05 s
	_check("absolute_vector3_still_swallows_a_substep_at_venus",
		is_equal_approx(after.x, abs_pos.x))


# The real Newton motion at Venus/Saturn's magnitude — actually integrated
# through Ship._newton_advance — lives in tools/test_anchor_frame.gd (Ephemeris
# is an autoload; this file is autoload-free by design). What stays testable
# here in pure arithmetic is AnchorFrame's own round-trip cost: absolute() then
# decompose() is lossy by construction — one ULP of the ANCHOR's magnitude —
# which is exactly why true_pos is a legacy-only setter and physics never
# round-trips through it.
func _round_trip_costs_about_one_ulp(anchor64: PackedFloat64Array, tag: String) -> void:
	var off := Vector3(6451.8, 120.5, -33.25)
	var mag: float = maxf(maxf(absf(anchor64[0]), absf(anchor64[1])), absf(anchor64[2]))
	var round_trip := AF.decompose(AF.absolute(anchor64, off), anchor64).distance_to(off)
	_check("%s_absolute_round_trip_costs_about_one_ulp" % tag,
		round_trip > 0.0 and round_trip < mag * 1.19e-7 * 8.0)


# Handing the ship from Earth to the Moon must not move it: every vector it can
# ask for is identical before and after, and velocity is untouched.
func _reanchor_continuity() -> void:
	var earth_off := Vector3(2.0e5, 8.0e4, 1.4e5)          # between Earth and the Moon
	var to_moon_before := AF.sub64(MOON64, AF.ZERO64) - earth_off
	var to_earth_before := -earth_off
	var moon_off := AF.reanchor(earth_off, AF.ZERO64, MOON64)
	var to_moon_after := AF.sub64(MOON64, MOON64) - moon_off
	var to_earth_after := AF.sub64(AF.ZERO64, MOON64) - moon_off
	_check("reanchor_body_vector_agrees_within_1m",
		to_moon_before.distance_to(to_moon_after) < 0.001)
	_check("reanchor_earth_vector_agrees_within_1m",
		to_earth_before.distance_to(to_earth_after) < 0.001)
	_check("reanchor_is_reversible",
		AF.reanchor(moon_off, MOON64, AF.ZERO64).distance_to(earth_off) < 0.001)
	# Velocity is inertial in the Sol frame — an anchor is a static body this
	# session, so a hand-off carries no velocity term. Asserted through a real
	# Ship.set_anchor call (not this pure-arithmetic file, which has no Ship
	# to exercise): tools/test_anchor_frame.gd's reanchor_velocity_unchanged.


# ConfigFile round-trip of what main.gd persists.
func _save_round_trip() -> void:
	var path := "user://test_anchor_save.cfg"
	var off := Vector3(6451.8, 120.5, -33.25)
	var cfg := ConfigFile.new()
	cfg.set_value("player", "anchor", "Venus")
	cfg.set_value("player", "off", off)
	cfg.set_value("player", "pos", AF.absolute(VENUS64, off))
	cfg.save(path)
	var back := ConfigFile.new()
	back.load(path)
	_check("save_keeps_anchor", str(back.get_value("player", "anchor", "")) == "Venus")
	_check("save_keeps_offset_within_1m",
		(back.get_value("player", "off", Vector3.ZERO) as Vector3).distance_to(off) < 0.001)
	# A pre-anchor save has only "pos", which was Earth-centred by definition.
	# The real decode (Ship.true_pos setter against a live "Earth" anchor) needs
	# Ephemeris — tools/test_anchor_frame.gd's legacy_save_lands_on_earth.
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _check(name: String, ok: bool) -> void:
	if not ok:
		print("anchor: FAIL %s" % name)
		failed += 1
