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
#   SHOT_DIR=<dir> SHOT_NAME=<name> xvfb-run -a -s "-screen 0 2400x1080x24" godot --path . \
#     res://tools/render_touch_hud.tscn -- --touch
# The window is fullscreen (project.godot mode=3), so the xvfb screen size IS the resolution;
# `--resolution` alone is ignored. SHOT_W / SHOT_H set a windowed capture size; TOUCH_SCALE=1.6 / SAFE_INSET=l,t,r,b preview a phone
# (see HudScale) since xvfb reports desktop dpi and no cutout.
#
# `-- --touch` reaches OS.get_cmdline_user_args() exactly like main.gd:325 reads
# it on desktop; on a real device OS.has_feature("mobile") does the same job.
# SHOT_HANGAR=1 docks (opens the hangar), SHOT_MENU=1 opens the flight menu, SHOT_TOAST=1
# shows a sample toast, SHOT_SYSTEMS / SHOT_TELEPORT open those menus; SHOT_FRAMES
# overrides OUT_WAIT.

const OUT_WAIT := 90   # frames to let the world spin up (planet gen, ephemeris, HUD build)

var _wait := 0
var _saved := false
var _menu_requested := false


func _ready() -> void:
	ProfileDir.isolate("render_touch_hud")
	process_mode = Node.PROCESS_MODE_ALWAYS
	if OS.has_environment("SHOT_W") and OS.has_environment("SHOT_H"):
		var width := int(OS.get_environment("SHOT_W"))
		var height := int(OS.get_environment("SHOT_H"))
		if width > 0 and height > 0:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			DisplayServer.window_set_size(Vector2i(width, height))
	get_viewport().transparent_bg = false
	var main: Node = load("res://scripts/core/main.gd").new()
	main.name = "Main"
	add_child(main)


func _process(_dt: float) -> void:
	if _saved:
		return
	_wait += 1
	if _wait == 2 and OS.get_environment("SHOT_SYSTEMS") == "1":
		get_node("Main").hud.toggle_systems()
	if _wait == 2 and OS.get_environment("SHOT_TELEPORT") == "1":
		get_node("Main").hud.teleport_sites_button.pressed.emit()
	if _wait == 2 and OS.get_environment("SHOT_DEV") == "1":
		get_node("Main").ship._debug_toggle_dev_speed()
	if _wait == 2 and OS.get_environment("SHOT_MENU") == "1":
		_menu_requested = true
	if _menu_requested and get_node("Main").touch_controls != null:
		get_node("Main").touch_controls.set_menu_open(true)
		_menu_requested = false
	if _wait == 2 and OS.get_environment("SHOT_HANGAR") == "1":
		get_node("Main")._set_docked(true)
	var frames := int(OS.get_environment("SHOT_FRAMES")) if OS.has_environment("SHOT_FRAMES") else OUT_WAIT
	if _wait == frames - 5 and OS.get_environment("SHOT_TOAST") == "1":
		get_node("Main").hud.toast = "Codex  ·  Moon surveyed"
		get_node("Main").hud.toast_t = 3.0
	if _wait < frames:
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
