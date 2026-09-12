extends SceneTree
# MusicPlaylist's ordering helpers are pure/static and autoload-free, unlike
# MusicDirector itself (touches the GameAudio autoload, can't compile under --script).
const MusicPlaylist := preload("res://scripts/core/music_playlist.gd")
var failures := 0


func _initialize() -> void:
	check("next_index_wraps_three", MusicPlaylist.next_index(0, 3) == 1
			and MusicPlaylist.next_index(1, 3) == 2
			and MusicPlaylist.next_index(2, 3) == 0)
	check("next_index_single_track_replays", MusicPlaylist.next_index(0, 1) == 0)
	check("next_index_zero_tracks_safe", MusicPlaylist.next_index(0, 0) == 0)

	var all_existing := MusicPlaylist.filter_existing([
		"res://assets/bgm.ogg",
		"res://assets/bgm_lobby.ogg",
	])
	check("filter_existing_keeps_present_files", all_existing.size() == 2)

	var mixed := MusicPlaylist.filter_existing([
		"res://assets/bgm.ogg",
		"res://assets/bgm_flight_2.ogg",
		"res://assets/bgm_flight_3.ogg",
		"res://assets/bgm_flight_nonexistent.ogg",   # never dropped in — must be skipped
	])
	check("filter_existing_keeps_all_present_flight_tracks", mixed.size() == 3)
	check("filter_existing_skips_missing_files", not mixed.has("res://assets/bgm_flight_nonexistent.ogg"))

	print("music_director: ", "OK" if failures == 0 else "FAIL %d" % failures)
	quit(0 if failures == 0 else 1)


func check(label: String, ok: bool) -> void:
	if not ok:
		failures += 1
		push_error("music_director: " + label)
