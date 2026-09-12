class_name MusicPlaylist
extends RefCounted
# Pure, autoload-free playlist-ordering helpers pulled out of MusicDirector so
# tools/test_music_director.gd can preload and test them without pulling in the
# GameAudio autoload reference that lives in music_director.gd (which doesn't compile
# under `--script`, per CLAUDE.md's autoload false-positive note).


static func next_index(cur: int, count: int) -> int:
	if count <= 0:
		return 0
	return (cur + 1) % count


static func filter_existing(paths: Array) -> Array:
	var out := []
	for path in paths:
		if ResourceLoader.exists(path):
			out.append(path)
	return out
