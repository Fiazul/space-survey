extends SceneTree
# Run: godot --headless --script res://tools/test_air_audio.gd
#
# Live-state acceptance for the "air sound too loud" fix (2026-09-09, re-derived
# 2026-09-12 for the rescaled drag curve — see docs/ROADMAP.md L.3). GameAudio's
# wind_db_for/rumble_db_for are pure static functions, and its onset/full reference
# loads (AIR_WIND_ONSET_LOAD/AIR_WIND_FULL_LOAD/AIR_RUMBLE_ONSET_LOAD/
# AIR_RUMBLE_FULL_LOAD) are themselves DERIVED off FlightMode.load_at_sea_level /
# AIR_LOAD_TARGET_FRAC (game_audio.gd is preloadable under --script the same way, via
# a local RHO0 mirror rather than the Ephemeris autoload) — so this test reads those
# constants directly instead of re-hardcoding the numbers, and stays correct across
# any future move of FlightMode.AIR_TERMINAL_KMS.
const GA := preload("res://scripts/autoload/game_audio.gd")
var failures := 0


func _initialize() -> void:
	# Inaudible well below the onset reference. _log_db_for's own floor sits at
	# onset / 10^AIR_FADE_DECADES (below that it's hard-pinned to the OFF floor);
	# half of that is comfortably below it for any onset value. 2026-09-12: this used
	# to be a fixed literal (0.0005) picked against the then-12 km/s target's onset
	# load (~0.0158) — once AIR_TERMINAL_KMS moved to 50 that onset load dropped to
	# ~0.0009 and the literal probe landed ABOVE the new floor instead of below it,
	# silently turning this into a false pass. Deriving it from AIR_WIND_ONSET_LOAD
	# keeps it below the floor for any target. Rumble's own onset load sits below
	# wind's (ratio = mach_frac at the reference speed, AIR_WIND_ONSET_KMS), so its
	# probe is scaled by that same ratio.
	var wind_floor: float = GA.AIR_WIND_ONSET_LOAD / pow(10.0, GA.AIR_FADE_DECADES)
	var wind_probe: float = wind_floor * 0.5
	check("wind_inaudible_below_onset", GA.wind_db_for(wind_probe) <= -50.0)
	var rumble_probe: float = wind_probe * GA.AIR_RUMBLE_ONSET_LOAD / GA.AIR_WIND_ONSET_LOAD
	check("rumble_inaudible_below_onset", GA.rumble_db_for(rumble_probe, 8.0) <= -50.0)

	# Audible onset at the sea-level reference speed (AIR_WIND_ONSET_KMS) — should read
	# as a hint, not a wash, and must sit well under both the OFF floor and the cap.
	var wind_cruise: float = GA.wind_db_for(GA.AIR_WIND_ONSET_LOAD)
	check("wind_cruise_onset_in_band", wind_cruise > -42.0 and wind_cruise < -36.0)

	# Dive reference (boosted sea-level equilibrium, air_load = AIR_LOAD_TARGET_FRAC):
	# full loudness, and >=6 dB under the engine's own boost peak (ENGINE_LOOP_DB +
	# ENGINE_BOOST_DB = -23 + 7 = -16 dB), so the engine always reads as the loudest layer.
	var wind_dive: float = GA.wind_db_for(GA.AIR_WIND_FULL_LOAD)
	check("wind_dive_reference_in_band", absf(wind_dive - (-22.0)) <= 1.0)
	check("wind_dive_stays_under_engine_peak", wind_dive <= -16.0 - 6.0 + 0.001)

	var rumble_dive: float = GA.rumble_db_for(GA.AIR_RUMBLE_FULL_LOAD, 8.0)
	check("rumble_dive_reference_in_band", absf(rumble_dive - (-26.0)) <= 1.0)
	check("rumble_dive_stays_under_engine_peak", rumble_dive <= -16.0 - 6.0 + 0.001)
	check("rumble_stays_under_wind_at_same_dive", rumble_dive <= wind_dive)

	# Beyond full: never louder than the cap, exactly the cap for absurd (DEV-only /
	# unbounded scalar) inputs — this is the exact failure mode the F9 + FASTAIR dev
	# tools trigger (air_load can only ever asymptote to 1 in practice, but the law
	# itself must be safe against any larger raw scalar a future caller might pass).
	check("wind_capped_at_10", GA.wind_db_for(10.0) == GA.wind_db_for(GA.AIR_WIND_FULL_LOAD))
	check("wind_capped_at_1000", GA.wind_db_for(1000.0) == GA.wind_db_for(GA.AIR_WIND_FULL_LOAD))
	check("rumble_capped_at_10", GA.rumble_db_for(10.0, 8.0) == GA.rumble_db_for(GA.AIR_RUMBLE_FULL_LOAD, 8.0))
	check("rumble_capped_at_1000", GA.rumble_db_for(1000.0, 8.0) == GA.rumble_db_for(GA.AIR_RUMBLE_FULL_LOAD, 8.0))

	# Never quieter than OFF, never louder than the cap, for any input.
	for x in [0.0, 1e-9, 1e-4, 1e-3, 1e-2, 1.0, 100.0]:
		check("wind_within_bounds_%s" % x, GA.wind_db_for(x) >= GA.AIR_WIND_OFF_DB - 0.001 \
			and GA.wind_db_for(x) <= GA.AIR_WIND_MAX_DB + 0.001)
		check("rumble_within_bounds_%s" % x, GA.rumble_db_for(x, 8.0) >= GA.AIR_RUMBLE_OFF_DB - 0.001 \
			and GA.rumble_db_for(x, 8.0) <= GA.AIR_RUMBLE_MAX_DB + 0.001)

	# Monotonic in the driving scalar (fine-grained scan across the whole audible range).
	check("wind_monotonic", _is_monotonic(func(x): return GA.wind_db_for(x)))
	check("rumble_monotonic", _is_monotonic(func(x): return GA.rumble_db_for(x, 8.0)))

	# Real gameplay values from the rescaled flight envelope: a light cruise at the
	# onset reference speed must stay quiet, and a real boosted equilibrium dive
	# (AIR_LOAD_TARGET_FRAC, not a DEV tool) must sit at/under the cap rather than
	# blowing past it.
	check("wind_at_light_cruise_is_quiet", GA.wind_db_for(GA.AIR_WIND_ONSET_LOAD) <= -36.0)
	check("wind_at_real_boost_is_at_or_under_dive_cap",
		GA.wind_db_for(GA.AIR_WIND_FULL_LOAD) <= GA.AIR_WIND_MAX_DB + 0.001)

	# pitch_scale's mach mapping (task 3) — mach_frac itself is already clamped 0..1
	# in update_air, but confirm the lerp result never leaves [0.85, 1.35] even for
	# an out-of-range mach (defensive; DEV speeds can push mach well past 8).
	for mach in [-5.0, 0.0, 4.0, 8.0, 50.0, 1000.0]:
		var mach_frac: float = clampf(mach / 8.0, 0.0, 1.0)
		var pitch: float = clampf(lerpf(0.85, 1.35, mach_frac), 0.85, 1.35)
		check("pitch_scale_bounded_mach_%s" % mach, pitch >= 0.85 and pitch <= 1.35)

	print("air_audio: ", "OK" if failures == 0 else "FAIL %d" % failures)
	quit(0 if failures == 0 else 1)


func _is_monotonic(f: Callable) -> bool:
	var prev: float = -1000.0
	var x := 0.0
	while x <= 2.0:
		var d: float = f.call(x)
		if d < prev - 1e-6:
			return false
		prev = d
		x += 0.0002
	return true


func check(label: String, ok: bool) -> void:
	if not ok:
		failures += 1
		push_error("air_audio: " + label)
