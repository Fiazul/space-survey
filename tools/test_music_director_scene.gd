extends Node
# Scene-based because MusicDirector touches the GameAudio autoload, unreachable under
# --script (see tools/test_music_director.gd for the autoload-free playlist-ordering math):
#   godot --headless tools/test_music_director_scene.tscn
const MusicDirectorScript := preload("res://scripts/core/music_director.gd")

var failures := 0


func _ready() -> void:
	var director := MusicDirectorScript.new()
	add_child(director)
	await get_tree().process_frame

	if director._music == null:
		# No flight tracks loaded in this environment — nothing left to probe.
		print("music_director_scene: OK (no flight tracks loaded)")
		get_tree().quit(0)
		return

	# Let the flight track actually play forward for real wall time.
	await get_tree().create_timer(0.5).timeout
	var pos_before: float = director._music.get_playback_position()
	check("flight_played_forward_before_dock", pos_before > 0.0)

	# Dock: drive the state machine (fake deltas — only playback position needs real time)
	# through debounce/fadeout/gap/fadein until PLATFORM is steady.
	_drive_until_steady(director, true)
	check("docked_reaches_platform_steady", director._cur_track == "platform"
			and director._xfade_phase == "steady")

	# Undock: drive back to FLIGHT steady.
	_drive_until_steady(director, false)
	check("undocked_reaches_flight_steady", director._cur_track == "flight"
			and director._xfade_phase == "steady")

	var pos_after: float = director._music.get_playback_position()
	check("flight_resumes_not_reset", pos_after >= pos_before)

	# Forced end-of-track handoff must not drop through MUSIC_OFF_DB (MAJOR 2 regression check).
	var vol_before_finish: float = director._music.volume_db
	var idx_before_finish: int = director._flight_idx
	director._on_flight_finished()
	check("finished_does_not_drop_to_off_db", director._music.volume_db > director.MUSIC_OFF_DB + 1.0)
	check("finished_advances_or_wraps_index", director._flight_idx != idx_before_finish
			or director._flight_streams.size() <= 1)
	check("finished_keeps_volume_near_prior_level",
			absf(director._music.volume_db - vol_before_finish) < 0.01)

	print("music_director_scene: ", "OK" if failures == 0 else "FAIL %d" % failures)
	get_tree().quit(0 if failures == 0 else 1)


func _drive_until_steady(director, docked_target: bool, max_iters := 200) -> void:
	var want_track := "platform" if docked_target else "flight"
	var i := 0
	while (director._cur_track != want_track or director._xfade_phase != "steady") and i < max_iters:
		director.update(1.0, docked_target)
		i += 1
	check("%s_converged_within_iteration_budget" % want_track, i < max_iters)


func check(label: String, ok: bool) -> void:
	if not ok:
		failures += 1
		push_error("music_director_scene: " + label)
