class_name TestProfileDir
extends Node
## ASTRYX_PROFILE_DIR moves every player-state file off user://, and a tool's
## default isolate() never overrides a directory the caller chose.
func _ready() -> void:
	var dir := OS.get_environment("TMPDIR") if OS.get_environment("TMPDIR") != "" else "/tmp"
	dir = dir.path_join("astryx_profile_dir_test")
	OS.set_environment(ProfileDir.ENV, dir)
	var ok: bool = GameState.profile_path() == dir.path_join("profile.cfg") \
		and ProfileDir.isolate("other") == dir \
		and not GameState.profile_path().begins_with("user://")
	var cfg := ConfigFile.new()
	cfg.set_value("player", "coins", 7)
	ok = ok and cfg.save(GameState.profile_path()) == OK and FileAccess.file_exists(dir.path_join("profile.cfg"))
	DirAccess.remove_absolute(dir.path_join(Codex.FILE))
	Codex._save()
	ok = ok and ProfileDir.path(Codex.FILE) == dir.path_join("codex.json") \
		and FileAccess.file_exists(dir.path_join("codex.json"))
	ok = ok and ProfileDir.path(HUD.LAYOUT_FILE) == dir.path_join("hud_layout_v3.cfg")
	OS.unset_environment(ProfileDir.ENV)
	ok = ok and GameState.profile_path() == "user://profile.cfg" \
		and ProfileDir.path(Codex.FILE) == "user://codex.json" \
		and ProfileDir.path(HUD.LAYOUT_FILE) == "user://hud_layout_v3.cfg"
	print("profile_dir: ", "OK" if ok else "FAIL")
	get_tree().quit(0 if ok else 1)
