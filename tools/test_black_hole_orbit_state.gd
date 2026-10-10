class_name TestBlackHoleOrbitState
extends SceneTree

const BHG := preload("res://scripts/flight/black_hole_gravity.gd")
var failures := 0

func _initialize() -> void:
	var gravity := BHG.new()
	if not gravity.has_method("orbit_state"):
		check("lightweight orbit telemetry is available", false)
		quit(1)
		return
	var hole := {"gm": 5.706634920774e17, "r_g": 6349356.0, "spin": .9, "horizon_km": 9117000.0}
	var radius := 20.0*float(hole.r_g)
	var rel := Vector3(radius, 0.0, 0.0)
	var circular := Vector3.BACK*BHG.circular_speed(hole, rel, Vector3.BACK)
	for velocity in [Vector3.ZERO, Vector3(-50000.0,0,0), circular]:
		var state: Dictionary = gravity.call("orbit_state", hole, rel, velocity)
		var full := BHG.orbit(hole, rel, velocity, 10.0)
		check("telemetry retains physical orbit classification", state.plunging == full.plunging)
		check("telemetry retains gravitational clock and orbital frequency", state.clock_rate == full.clock_rate and state.kepler_hz == full.kepler_hz)
		check("telemetry retains orbit scales", state.r == radius and state.isco_km == full.isco_km and state.photon_km == full.photon_km)
		check("uncomputed escape advice stays absent", not state.has("burn") and not state.has("dv_kms") and not state.has("no_escape") and not state.has("fall_s"))
	var falling: Dictionary = gravity.call("orbit_state", hole, rel, Vector3.ZERO)
	check("resting outside the horizon is a plunge", falling.plunging and falling.clock_rate > 0.0)
	var parked: Dictionary = gravity.call("orbit_state", hole, rel, circular)
	check("a circular exterior orbit remains stable", not parked.plunging)
	var interior: Dictionary = gravity.call("orbit_state", hole, Vector3(9000000.0,0,0), Vector3.ZERO)
	check("inside the horizon is classified without escape advice", interior.plunging and interior.clock_rate == 0.0 and not interior.has("burn"))
	print("black_hole_orbit_state: ", "OK" if failures == 0 else "FAIL %d" % failures)
	quit(1 if failures else 0)

func check(label: String, ok: bool) -> void:
	if not ok:
		failures += 1
		push_error(label)
