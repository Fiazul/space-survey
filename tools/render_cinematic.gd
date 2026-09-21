extends Node
# Cinematic flyby capture: Earth surface skim → Earth limb outside air → Moon pass.
# Boots real main.gd, teleports via DevSitesPanel.go, advances anchor_off along a
# great circle at constant AGL. Drive charge / supercruise stay off — motion
# is kinematic (velocity held at zero; offset rewritten each tick).
#
# llvmpipe: viewport get_image() is expensive and ring rebuilds take seconds.
# Each beat is a short keyframe ladder — one grab per key, then file-copy HOLD
# duplicates so the encode is ≥20 s without re-reading the GPU every tick.
#
# Run (real GL context — plain --headless captures nothing):
#   timeout 180 xvfb-run -a godot --path . res://tools/render_cinematic.tscn
# Frames → /tmp/astryx_cinematic/frames/frame_XXXXX.png
# Encode: tools/encode_cinematic.sh

const DS := preload("res://scripts/world/dev_sites.gd")

const BOOT_WAIT := 40
const DISPATCH_WAIT := 4   # frames for update_for to start a ring batch
const LIMB_SETTLE := 6
const FRAMES_DIR := "/tmp/astryx_cinematic/frames"

# Holds pad duration: (5+6+5)*32 = 512 frames ≈ 21 s at 24 fps.
const BEATS := [
	{"body": "Earth", "lat": 27.82, "lon": 86.925, "alt_km": 4.0, "heading_deg": 90.0,
		"travel_km": 360.0, "need_ground": true, "unique": 5, "hold": 32, "label": "earth_surface"},
	{"body": "Earth", "lat": 20.0, "lon": -40.0, "alt_km": 400.0, "heading_deg": 90.0,
		"travel_km": 80.0, "need_ground": false, "unique": 6, "hold": 32, "label": "earth_limb"},
	{"body": "Moon", "lat": 10.0, "lon": 20.0, "alt_km": 7.0, "heading_deg": 90.0,
		"travel_km": 200.0, "need_ground": true, "unique": 5, "hold": 32, "label": "moon_pass"},
]

var _main: Node
var _phase := 0
var _beat_i := 0
var _beats: Array = []
var _t := 0
var _frame_i := 0
var _lat := 0.0
var _lon := 0.0
var _alt := 0.0
var _heading := 0.0
var _body := ""
var _key_i := 0
var _hold := 32
var _unique := 5
var _step_km := 0.0
var _sub := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_priority = 1000
	get_viewport().transparent_bg = false
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1280, 720))
	get_viewport().size = Vector2i(1280, 720)
	DirAccess.make_dir_recursive_absolute(FRAMES_DIR)
	_beats = _select_beats()
	var start_fr := OS.get_environment("CINEMATIC_START_FRAME")
	if not start_fr.is_empty():
		_frame_i = int(start_fr)
	_main = load("res://scripts/core/main.gd").new()
	_main.name = "Main"
	add_child(_main)
	# Contact-kill must stay off — a kinematic offset rewrite can trip the skin
	# sweep for one frame (seen as HULL LOST on the limb beat).
	FlightMode.dev_no_death = true
	print("render_cinematic: boot → %s (start_frame=%d beats=%d)" % [
		FRAMES_DIR, _frame_i, _beats.size()])


func _select_beats() -> Array:
	var only := OS.get_environment("CINEMATIC_BEATS")
	if only.is_empty():
		return BEATS.duplicate(true)
	var want := only.split(",")
	var out: Array = []
	for b in BEATS:
		if str(b.label) in want:
			out.append(b)
	return out


func _process(_delta: float) -> void:
	match _phase:
		0:
			_t += 1
			if _t < BOOT_WAIT:
				return
			if _main.hud != null:
				_main.hud.visible = false
			_start_beat()
		1:
			_tick_keys()


func _start_beat() -> void:
	var b: Dictionary = _beats[_beat_i]
	_body = str(b.body)
	_lat = float(b.lat)
	_lon = float(b.lon)
	_alt = float(b.alt_km)
	_heading = float(b.heading_deg)
	_unique = maxi(int(b.unique), 1)
	_hold = maxi(int(b.hold), 1)
	_step_km = float(b.travel_km) / float(maxi(_unique - 1, 1))
	var site := {
		"name": "cinematic_%s" % b.label,
		"body": _body,
		"mode": "surface",
		"lat_deg": _lat,
		"lon_deg": _lon,
		"alt_km": _alt,
		"heading_deg": _heading,
		"note": "cinematic capture",
	}
	_main.dev_sites.go(site)
	_hold_still()
	_place_ship()
	_phase = 1
	_t = 0
	_key_i = 0
	_sub = 0
	print("render_cinematic: beat %s uniq=%d hold=%d step=%.1fkm alt=%.1f" % [
		b.label, _unique, _hold, _step_km, _alt])


func _tick_keys() -> void:
	var b: Dictionary = _beats[_beat_i]
	var need_ground: bool = bool(b.need_ground)
	match _sub:
		0:
			_t += 1
			_hold_still()
			_place_ship()
			if need_ground:
				var patch = _surface_patch()
				# Wait until a batch is in flight or ground already exists.
				if patch != null and not patch.has_ground() and not patch._rebuild_busy() \
						and _t < 60:
					return
				if _t < DISPATCH_WAIT:
					return
				_force_surface_ready()
			else:
				if _t < LIMB_SETTLE:
					return
			_sub = 1
			_t = 0
		1:
			_t += 1
			_hold_still()
			_place_ship()
			# One drawn frame after commit before grabbing.
			if _t < 2:
				return
			_capture_held(_hold)
			_key_i += 1
			print("render_cinematic: key %d/%d %s frames=%d" % [
				_key_i, _unique, b.label, _frame_i])
			if _key_i >= _unique:
				_next_beat()
				return
			_advance_km(_step_km)
			_place_ship()
			_t = 0
			_sub = 0


func _next_beat() -> void:
	_beat_i += 1
	if _beat_i >= _beats.size():
		print("render_cinematic: done — %d frames" % _frame_i)
		get_tree().quit(0)
		return
	_start_beat()


func _hold_still() -> void:
	var ship = _main.ship
	if ship == null:
		return
	ship.velocity = Vector3.ZERO
	ship.time_rate = 1.0


func _surface_patch():
	var ps = _main.planets
	if ps == null:
		return null
	return ps._surface


func _force_surface_ready() -> void:
	var patch = _surface_patch()
	if patch != null and patch.has_method("force_ready"):
		patch.force_ready()


func _advance_km(dist_km: float) -> void:
	var radius := Ephemeris.body_radius_km(_body)
	if radius <= 1.0 or dist_km <= 0.0:
		return
	var delta_rad := dist_km / radius
	var lat1 := deg_to_rad(_lat)
	var lon1 := deg_to_rad(_lon)
	var brng := deg_to_rad(_heading)
	var sin_lat2 := sin(lat1) * cos(delta_rad) + cos(lat1) * sin(delta_rad) * cos(brng)
	var lat2 := asin(clampf(sin_lat2, -1.0, 1.0))
	var y := sin(brng) * sin(delta_rad) * cos(lat1)
	var x := cos(delta_rad) - sin(lat1) * sin(lat2)
	var lon2 := lon1 + atan2(y, x)
	_lat = rad_to_deg(lat2)
	_lon = rad_to_deg(lon2)
	while _lon > 180.0:
		_lon -= 360.0
	while _lon < -180.0:
		_lon += 360.0


func _place_ship() -> void:
	var ship = _main.ship
	if ship == null:
		return
	if ship.anchor_name != _body:
		_main._anchor_ship(_body)
	var dir := DS.dir_for(_lat, _lon)
	var radius := Ephemeris.body_radius_km(_body)
	var sampler: TerrainSampler = _main.planets.terrain_sampler_for(_body) \
		if _main.planets != null else null
	var ground_r := sampler.ground_radius_km(dir, radius) if sampler != null else radius
	ship.velocity = Vector3.ZERO
	ship.anchor_off = DS.surface_anchor_off(dir, ground_r, _alt)
	var fwd := DS.heading_forward(dir, _heading)
	ship.face_toward(fwd * 80.0 - dir * 8.0)


func _capture_held(n: int) -> void:
	var img := get_viewport().get_texture().get_image()
	if img == null:
		print("render_cinematic: null viewport image at frame %d" % _frame_i)
		return
	var first := "%s/frame_%05d.png" % [FRAMES_DIR, _frame_i]
	img.save_png(first)
	_frame_i += 1
	for _i in range(1, n):
		var dest := "%s/frame_%05d.png" % [FRAMES_DIR, _frame_i]
		var err := DirAccess.copy_absolute(first, dest)
		if err != OK:
			img.save_png(dest)
		_frame_i += 1
