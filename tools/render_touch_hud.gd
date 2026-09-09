extends Node
# Render the real game (boots res://scripts/core/main.gd, same as scenes/Main.tscn)
# offscreen so the touch-controls overlay can be LOOKED at instead of guessed.
#
# Reported: "hud buttons controller/joystick circle missing, i think everything
# missing or messed up" on Android. We cannot see the phone, so this boots the
# real Main scene under a real window (needs a GL context — plain --headless
# never delivers a frame, see render_terrain.gd) at a phone-like resolution and
# saves what actually gets drawn.
#
# Run (see render_terrain.gd for the same xvfb/--headless caveat):
#   SHOT_DIR=<dir> SHOT_NAME=<name> xvfb-run -a godot --path . \
#     --resolution 2400x1080 res://tools/render_touch_hud.tscn -- --touch
#
# `-- --touch` reaches OS.get_cmdline_user_args() exactly like main.gd:325 reads
# it on desktop; on a real device OS.has_feature("mobile") does the same job.

const OUT_WAIT := 90   # frames to let the world spin up (planet gen, ephemeris, HUD build)

var _wait := 0
var _saved := false


func _ready() -> void:
	get_viewport().transparent_bg = false
	var main: Node = load("res://scripts/core/main.gd").new()
	main.name = "Main"
	add_child(main)


func _process(_dt: float) -> void:
	if _saved:
		return
	_wait += 1
	if _wait < OUT_WAIT:
		return
	_saved = true
	var shot_dir := OS.get_environment("SHOT_DIR")
	if shot_dir.is_empty():
		shot_dir = "/tmp"
	DirAccess.make_dir_recursive_absolute(shot_dir)
	var shot_name := OS.get_environment("SHOT_NAME")
	if shot_name.is_empty():
		shot_name = "touch_hud"
	var img := get_viewport().get_texture().get_image()
	var path := "%s/%s.png" % [shot_dir, shot_name]
	img.save_png(path)
	print("render_touch_hud: %s -> %s (viewport=%s)" % [shot_name, path, get_viewport().get_visible_rect().size])
	get_tree().quit(0)
