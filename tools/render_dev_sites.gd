extends Node
# Boots the real Main scene (same pattern as render_touch_hud.gd) and captures
# the Ctrl+P dev-sites panel: one shot of the panel open, one shot ~90 frames
# after jumping to "Everest summit +3 km".
#
# Run (needs a real GL context — plain --headless never delivers a frame, see
# render_terrain.gd):
#   SHOT_DIR=<dir> xvfb-run -a godot --path . res://tools/render_dev_sites.tscn

const DS := preload("res://scripts/world/dev_sites.gd")
const BOOT_WAIT := 90     # frames to let the world spin up (planet gen, ephemeris, HUD build)
const SETTLE_WAIT := 90   # frames to let the teleport's frame-shift/camera settle

var _main: Node
var _stage := 0   # 0=booting, 1=panel open shot taken, 2=post-teleport shot taken (done)
var _t := 0


func _ready() -> void:
	# Opening the panel pauses the tree (SettingsMenu/CodexPanel house pattern) —
	# this capture driver has to keep ticking through that pause to take the
	# "panel open" shot and then fire the teleport.
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_viewport().transparent_bg = false
	_main = load("res://scripts/core/main.gd").new()
	_main.name = "Main"
	add_child(_main)


func _shot_dir() -> String:
	var d := OS.get_environment("SHOT_DIR")
	return d if not d.is_empty() else "/tmp"


func _save(name: String) -> void:
	var dir := _shot_dir()
	DirAccess.make_dir_recursive_absolute(dir)
	var img := get_viewport().get_texture().get_image()
	var path := "%s/%s.png" % [dir, name]
	img.save_png(path)
	print("render_dev_sites: %s -> %s" % [name, path])


func _process(_dt: float) -> void:
	_t += 1
	match _stage:
		0:
			if _t < BOOT_WAIT:
				return
			_main.dev_sites.toggle()   # open the panel (Ctrl+P equivalent)
			_stage = 1
			_t = 0
		1:
			if _t < 6:
				return
			_save("dev_sites_panel")
			var everest: Variant = null
			for site in DS.sites():
				if str(site.name) == "Everest summit +3 km":
					everest = site
					break
			_main.dev_sites._pick(everest)   # closes the panel + calls go()
			_stage = 2
			_t = 0
		2:
			if _t < SETTLE_WAIT:
				return
			_save("dev_sites_everest")
			get_tree().quit(0)
