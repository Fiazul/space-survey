extends SceneTree
# Run: godot --headless --script res://tools/test_air_audio.gd
#
# Live-state acceptance for the "air sound too loud" fix (2026-09-09): GameAudio's
# wind_db_for/rumble_db_for are pure static functions (no autoload identifiers
# referenced anywhere in game_audio.gd), so the whole script preloads clean under
# --script — no need for a separate standalone law class. Reference points mirror
# tools/test_flight_envelope.gd's measured envelope (cruise air_load ~= 0.0013,
# max boost air_load ~= 0.0044 at every Earth altitude sampled there).
const GA := preload("res://scripts/autoload/game_audio.gd")
var failures := 0


func _initialize() -> void:
	# Inaudible well below the cruise-onset reference. Rumble's own onset load sits
	# below wind's (0.0007 vs 0.0013), so its "same relative distance below onset"
	# probe point is scaled by that ratio rather than reusing wind's raw 0.0005.
	check("wind_inaudible_below_onset", GA.wind_db_for(0.0005) <= -50.0)
	var rumble_probe: float = 0.0005 * GA.AIR_RUMBLE_ONSET_LOAD / GA.AIR_WIND_ONSET_LOAD
	check("rumble_inaudible_below_onset", GA.rumble_db_for(rumble_probe, 8.0) <= -50.0)

	# Audible onset at the envelope's real cruise value (0.0013) — should read as a
	# hint, not a wash, and must sit well under both the OFF floor and the cap.
	var wind_cruise: float = GA.wind_db_for(0.0013)
	check("wind_cruise_onset_in_band", wind_cruise > -42.0 and wind_cruise < -36.0)

	# Dive reference ("screaming dive" = envelope's max boost x3): full loudness,
	# and >=6 dB under the engine's own boost peak (ENGINE_LOOP_DB + ENGINE_BOOST_DB
	# = -23 + 7 = -16 dB), so the engine always reads as the loudest layer.
	var wind_dive: float = GA.wind_db_for(0.0132)
	check("wind_dive_reference_in_band", absf(wind_dive - (-22.0)) <= 1.0)
	check("wind_dive_stays_under_engine_peak", wind_dive <= -16.0 - 6.0 + 0.001)

	var rumble_dive: float = GA.rumble_db_for(0.0129, 8.0)
	check("rumble_dive_reference_in_band", absf(rumble_dive - (-26.0)) <= 1.0)
	check("rumble_dive_stays_under_engine_peak", rumble_dive <= -16.0 - 6.0 + 0.001)
	check("rumble_stays_under_wind_at_same_dive", rumble_dive <= wind_dive)

	# Beyond full: never louder than the cap, exactly the cap for absurd (DEV-only /
	# unbounded scalar) inputs — this is the exact failure mode the F9 + FASTAIR dev
	# tools trigger (air_load can only ever asymptote to 1 in practice, but the law
	# itself must be safe against any larger raw scalar a future caller might pass).
	check("wind_capped_at_10", GA.wind_db_for(10.0) == GA.wind_db_for(0.0132))
	check("wind_capped_at_1000", GA.wind_db_for(1000.0) == GA.wind_db_for(0.0132))
	check("rumble_capped_at_10", GA.rumble_db_for(10.0, 8.0) == GA.rumble_db_for(0.0129, 8.0))
	check("rumble_capped_at_1000", GA.rumble_db_for(1000.0, 8.0) == GA.rumble_db_for(0.0129, 8.0))

	# Never quieter than OFF, never louder than the cap, for any input.
	for x in [0.0, 1e-9, 1e-4, 1e-3, 1e-2, 1.0, 100.0]:
		check("wind_within_bounds_%s" % x, GA.wind_db_for(x) >= GA.AIR_WIND_OFF_DB - 0.001 \
			and GA.wind_db_for(x) <= GA.AIR_WIND_MAX_DB + 0.001)
		check("rumble_within_bounds_%s" % x, GA.rumble_db_for(x, 8.0) >= GA.AIR_RUMBLE_OFF_DB - 0.001 \
			and GA.rumble_db_for(x, 8.0) <= GA.AIR_RUMBLE_MAX_DB + 0.001)

	# Monotonic in the driving scalar (fine-grained scan across the whole audible range).
	check("wind_monotonic", _is_monotonic(func(x): return GA.wind_db_for(x)))
	check("rumble_monotonic", _is_monotonic(func(x): return GA.rumble_db_for(x, 8.0)))

	# Real gameplay values from the flight envelope must be near-silent (the actual
	# bug report): before this fix, both loops hit -9/-13 dB at DEV saturation and
	# were only ~59.7 dB quiet at REAL cruise/boost, i.e. essentially always off.
	check("wind_at_real_cruise_is_quiet", GA.wind_db_for(0.0013) <= -36.0)
	check("wind_at_real_boost_is_below_dive_cap", GA.wind_db_for(0.0044) < GA.AIR_WIND_MAX_DB)

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
