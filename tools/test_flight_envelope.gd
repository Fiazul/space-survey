extends SceneTree
# Run: godot --headless --script res://tools/test_flight_envelope.gd
#
# Live-state acceptance for the hypersonic-entry-feel audit (2026-09-09): solves the
# ship's own thrust-vs-drag equilibrium at a handful of altitudes and prints the max
# SUSTAINED airspeed and the resulting FlightMode.air_load there. The audit found this
# regime unreachable in controlled flight (2 g thrust vs 2.5*rho*v^2 drag caps out at
# ~80 m/s at sea level, ~250 m/s at 10 km, air_load <= 0.005 — below every FX threshold),
# which is why the whole visual entry layer (plasma sheath, hull heat, camera buffet)
# was ripped out rather than kept unreachable. If a future thrust/drag change makes the
# assert below fail, the regime became reachable and docs/ROADMAP.md "G.8" must be
# revisited before any visual FX is re-added.
#
# ship.gd cannot be preloaded here: it references the Ephemeris autoload at parse
# time, which does not exist under --script (see test_chase_rig.gd's header comment
# for the same constraint). Its thrust/drag constants are hardcoded below instead,
# named identically and commented with their ship.gd source line — touch one, touch
# both. FlightMode itself has no such reference at parse time (only inside function
# bodies, which GDScript resolves lazily) and preloads clean, so air_load()/mach() are
# called directly.

const FM := preload("res://scripts/flight/flight_mode.gd")

# --- Mirrored from scripts/flight/ship.gd — keep these in step with that file ---
const NEWTON_BALLISTIC := 0.005     # ship.gd:~316
const NEWTON_THRUST := 0.01962      # ship.gd:~319, 2 g in km/s^2
const BOOST_MULT := 3.0             # ship.gd:~73, Shift multiplier
# --- Mirrored from scripts/autoload/ephemeris.gd — keep these in step with that file ---
const RHO0 := 1.225                 # ephemeris.gd:58, kg/m^3 at sea level
const EARTH_ATMO_H_KM := 8.5        # ephemeris.gd:57, density scale height
const EARTH_ATMO_TOP_KM := 100.0    # ephemeris.gd:45, Karman line

const ALTITUDES_KM := [0.0, 5.0, 10.0, 20.0, 30.0, 50.0]


# Same drag law as ship.gd's _newton_atmo_drag: acc = 500 * NEWTON_BALLISTIC * rho * spd^2.
static func _drag_acc(alt_km: float, spd_kms: float) -> float:
	var rho: float = RHO0 * exp(-alt_km / EARTH_ATMO_H_KM)
	return 500.0 * NEWTON_BALLISTIC * rho * spd_kms * spd_kms


# Equilibrium speed where thrust_acc == drag_acc(alt, spd): spd = sqrt(thrust_acc / (500*NEWTON_BALLISTIC*rho)).
static func _max_sustained_speed(alt_km: float, thrust_acc: float) -> float:
	var rho: float = RHO0 * exp(-alt_km / EARTH_ATMO_H_KM)
	var denom := 500.0 * NEWTON_BALLISTIC * rho
	if denom <= 0.0:
		return INF
	return sqrt(thrust_acc / denom)


func _initialize() -> void:
	var failed := 0
	for alt in ALTITUDES_KM:
		var spd_cruise: float = _max_sustained_speed(alt, NEWTON_THRUST)
		var spd_boost: float = _max_sustained_speed(alt, NEWTON_THRUST * BOOST_MULT)
		var load_cruise: float = FM.air_load(alt, spd_cruise, EARTH_ATMO_TOP_KM)
		var load_boost: float = FM.air_load(alt, spd_boost, EARTH_ATMO_TOP_KM)
		print("flight_envelope: alt %5.1f km  cruise %8.4f km/s (load %.4f)  boost %8.4f km/s (load %.4f)"
			% [alt, spd_cruise, load_cruise, spd_boost, load_boost])
		failed += _check("air_load_boost_below_threshold_at_%.0fkm" % alt, load_boost < 0.05)

	if failed == 0:
		print("flight_envelope: OK")
		quit(0)
	else:
		print("flight_envelope: FAIL %d" % failed)
		quit(1)


func _check(name: String, ok: bool) -> int:
	if not ok:
		print("flight_envelope: FAIL %s" % name)
		return 1
	return 0
