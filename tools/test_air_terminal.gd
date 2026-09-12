extends SceneTree
# Run: godot --headless --script res://tools/test_air_terminal.gd
#
# Live-state acceptance for the 2026-09-12 drag rescale (player directive: air must
# allow >=10 km/s, was ~0.14 km/s boosted at sea level). FlightMode.air_ballistic is
# autoload-free (args only), so it's called directly; ship.gd cannot be preloaded here
# — it references the Ephemeris autoload at parse time, unavailable under --script
# (see test_chase_rig.gd's header comment for the same constraint). Its thrust/boost
# constants and Ephemeris.RHO0 are mirrored below as literals, named identically and
# commented with their source line — touch one, touch both.

const FM := preload("res://scripts/flight/flight_mode.gd")

# --- Mirrored from scripts/flight/ship.gd — keep these in step with that file ---
const NEWTON_THRUST := 0.01962      # ship.gd:~342, 2 g in km/s^2
const BOOST_MULT := 3.0             # ship.gd:~80, Shift multiplier
# --- Mirrored from scripts/autoload/ephemeris.gd — keep these in step with that file ---
const RHO0 := 1.225                 # ephemeris.gd:62, kg/m^3 at sea level
const EARTH_ATMO_H_KM := 8.5        # ephemeris.gd:61, density scale height
const EARTH_ATMO_TOP_KM := 100.0    # ephemeris.gd:49, Karman line


# Same drag law as ship.gd's _newton_atmo_drag: acc = 500 * ballistic * rho * spd^2.
static func _drag_acc(ballistic: float, alt_km: float, spd_kms: float) -> float:
	var rho: float = RHO0 * exp(-alt_km / EARTH_ATMO_H_KM)
	return 500.0 * ballistic * rho * spd_kms * spd_kms


# Equilibrium speed where thrust_acc == drag_acc(alt, spd).
static func _terminal_speed(ballistic: float, alt_km: float, thrust_acc: float) -> float:
	var rho: float = RHO0 * exp(-alt_km / EARTH_ATMO_H_KM)
	var denom := 500.0 * ballistic * rho
	if denom <= 0.0:
		return INF
	return sqrt(thrust_acc / denom)


func _initialize() -> void:
	var failed := 0
	var ballistic: float = FM.air_ballistic(NEWTON_THRUST, BOOST_MULT, RHO0)
	print("air_terminal: derived ballistic=%.10f (was 0.005 hand-picked)" % ballistic)

	var v_sea_boost := _terminal_speed(ballistic, 0.0, NEWTON_THRUST * BOOST_MULT)
	failed += _check("sea_level_boosted_terminal_matches_target",
		absf(v_sea_boost - FM.AIR_TERMINAL_KMS) <= 0.01 * FM.AIR_TERMINAL_KMS)
	print("air_terminal: sea-level boosted terminal = %.3f km/s (target %.1f)"
		% [v_sea_boost, FM.AIR_TERMINAL_KMS])

	var v_10km_boost := _terminal_speed(ballistic, 10.0, NEWTON_THRUST * BOOST_MULT)
	failed += _check("terminal_increases_with_altitude", v_10km_boost > v_sea_boost)
	print("air_terminal: 10km boosted terminal = %.3f km/s" % v_10km_boost)

	# Air is "not felt" until hypersonic: at ordinary cruise speed (1 km/s) sea level
	# drag accel should be a tiny fraction of the boosted thrust it's up against.
	var thrust_boost_acc := NEWTON_THRUST * BOOST_MULT
	var drag_at_1kms := _drag_acc(ballistic, 0.0, 1.0)
	failed += _check("drag_negligible_at_1kms_sea_level",
		drag_at_1kms < 0.01 * thrust_boost_acc)
	print("air_terminal: drag @ 1 km/s sea level = %.6f km/s^2 (%.2f%% of boosted thrust)"
		% [drag_at_1kms, 100.0 * drag_at_1kms / thrust_boost_acc])

	# air_load table (item 1, HUD Load readout consumer): the 2026-09-12 rescale also
	# moved FlightMode.AIR_LOAD_Q_REF's replacement (air_load_q_ref) so this curve's
	# knee tracks AIR_TERMINAL_KMS instead of saturating to 1.0 everywhere reachable.
	print("air_terminal: sea-level air_load by speed —")
	for v in [0.0, 1.0, 3.0, 7.0, 12.0]:
		print("  %5.1f km/s : load %.4f" % [v, FM.air_load(0.0, v, EARTH_ATMO_TOP_KM)])
	var load_1kms: float = FM.air_load(0.0, 1.0, EARTH_ATMO_TOP_KM)
	failed += _check("light_cruise_load_stays_low", load_1kms < 0.1)

	print("air_terminal: boosted-equilibrium air_load by altitude —")
	for alt in [0.0, 10.0, 30.0]:
		var v_eq: float = _terminal_speed(ballistic, alt, thrust_boost_acc)
		var load_eq: float = FM.air_load(alt, v_eq, EARTH_ATMO_TOP_KM)
		print("  %5.1f km alt : v %8.3f km/s : load %.4f" % [alt, v_eq, load_eq])
		failed += _check("boosted_equilibrium_load_in_target_band_at_%.0fkm" % alt,
			load_eq >= 0.85 and load_eq <= 0.95)

	if failed == 0:
		print("air_terminal: OK")
		quit(0)
	else:
		print("air_terminal: FAIL %d" % failed)
		quit(1)


func _check(name: String, ok: bool) -> int:
	if not ok:
		print("air_terminal: FAIL %s" % name)
		return 1
	return 0
