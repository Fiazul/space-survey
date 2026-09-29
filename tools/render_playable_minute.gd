class_name RenderPlayableMinute
extends Node
## The playable minute in the real game (docs/plans/2026-09-29-playable-minute.md):
## boots main with ASTRYX_START=pad, flies MinutePilot at a fixed dt 1/60 through
## main._process, saves the four moments and logs frame time at the look-back
## and the re-entry. Run windowed under a virtual display with an isolated profile:
##   SHOT_DIR=/tmp/shots ASTRYX_START=pad xvfb-run -a godot --path . res://tools/render_playable_minute.tscn
## Plain --headless still flies and prints state, but captures nothing.
## FAST=<n> physics frames per rendered frame between moments (default 6).
const DT := 1.0/60.0
const PAD_ID := "kennedy_lc39a"

var main: Node
var pilot: MinutePilot
var out_dir := "/tmp/playable_minute"
var fast := 6
var frame := 0
var sim_frames := 0
var shots := {}
var timing := {}
var _last_us := 0
var _peak_load := 0.0
var _landed_frames := -1

func _ready() -> void:
	ProfileDir.isolate("render_playable_minute")
	if OS.get_environment("SHOT_DIR") != "": out_dir = OS.get_environment("SHOT_DIR")
	if OS.get_environment("FAST") != "": fast = maxi(1, int(OS.get_environment("FAST")))
	DirAccess.make_dir_recursive_absolute(out_dir)
	main = preload("res://scripts/core/main.gd").new()
	add_child(main)
	main.set_process(false)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
	var ship: Ship = main.ship
	print("boot: fresh_profile=%s ASTRYX_START=%s landing_site=%s id=%s landed=%s gear=%.2f anchor=%s alt_km=%.4f vel=%.6f" % [main._fresh_game, OS.get_environment("ASTRYX_START"), ship.landing_site, ship.landing_site_id, ship.landed, ship.systems.gear_fraction, ship.anchor_name, ship.anchor_distance_km()-6371.0, ship.velocity.length()])
	var sampler: TerrainSampler = main.planets.terrain_sampler_for("Earth")
	for site in sampler.facilities:
		if site.id == PAD_ID: pilot = MinutePilot.new(ship, site)

func _process(_delta: float) -> void:
	if main == null or pilot == null:
		return
	var now := Time.get_ticks_usec()
	var wall_us := now-_last_us if _last_us > 0 else 0
	_last_us = now
	frame += 1
	var ship: Ship = main.ship
	var alt := pilot.altitude()
	var moment := _moment(alt)
	if moment != "" and wall_us > 0:
		_record(moment, "wall_frame", wall_us)
		_record(moment, "render_cpu", int(RenderingServer.viewport_get_measured_render_time_cpu(get_viewport().get_viewport_rid())*1000.0))
		_record(moment, "gpu", int(RenderingServer.viewport_get_measured_render_time_gpu(get_viewport().get_viewport_rid())*1000.0))
	if frame == 1 and ship.landing_site_id == PAD_ID:
		print("boot: pad locked on first frame")
	if frame < 180:
		_step(false)
		if frame == 170: _shot("1_on_pad_noon")
		return
	var steps := 1 if moment != "" else fast
	for i in steps:
		if pilot.done():
			break
		pilot.drive(DT)
		_step(true)
	if pilot.phase in ["ascent", "coast"] and alt > 80.0 and not shots.has("2_thin_air_80km"): _shot("2_thin_air_80km")
	if pilot.phase in ["ascent", "coast"] and alt > 100.0 and not shots.has("3_skin_climb"): _shot("3_skin_climb")
	if pilot.phase == "return" and not shots.has("4_lookback_300km"): _shot("4_lookback_300km")
	if pilot.phase == "brake":
		if ship.air_load < _peak_load and not shots.has("5_reentry"): _shot("5_reentry")
		_peak_load = maxf(_peak_load, ship.air_load)
	if pilot.done():
		if _landed_frames < 0:
			_landed_frames = frame
			print("landed: landing_site=%s id=%s after %.1f s flight at dt 1/60" % [ship.landing_site, ship.landing_site_id, sim_frames*DT])
		if frame-_landed_frames == 60:
			_shot("6_relocked")
			_finish()

func _moment(alt: float) -> String:
	if (pilot.phase == "coast" and alt > 280.0) or pilot.phase == "return": return "lookback"
	if pilot.phase == "brake" and alt > 5.0: return "reentry"
	return ""

func _step(fly: bool) -> void:
	var start := Time.get_ticks_usec()
	main._process(DT)
	if fly: sim_frames += 1
	var moment := _moment(pilot.altitude())
	if moment != "": _record(moment, "main_process", Time.get_ticks_usec()-start)

func _record(moment: String, key: String, us: int) -> void:
	if not timing.has(moment): timing[moment] = {}
	if not timing[moment].has(key): timing[moment][key] = []
	timing[moment][key].append(us)

func _shot(name: String) -> void:
	var ship: Ship = main.ship
	var state := "phase=%s alt_km=%.2f v=%.3f air_load=%.6f mach=%.2f warp=%.0f landing_site=%s" % [pilot.phase, pilot.altitude(), ship.velocity.length(), ship.air_load, ship.mach_number, ship.time_rate, ship.landing_site]
	shots[name] = state
	var tex := get_viewport().get_texture()
	var img: Image = tex.get_image() if tex != null else null
	if img == null:
		print("shot %s: no GL frame (headless) %s" % [name, state])
		return
	var path := out_dir.path_join(name+".png")
	img.save_png(path)
	print("shot %s: %s %s" % [name, path, state])

func _finish() -> void:
	for moment in timing:
		for key in timing[moment]:
			var values: Array = timing[moment][key]
			values.sort()
			print("FRAME %s %s n=%d median_ms=%.2f p95_ms=%.2f max_ms=%.2f" % [moment, key, values.size(), values[values.size()/2]/1000.0, values[int(values.size()*.95)]/1000.0, values[-1]/1000.0])
	pilot.release()
	set_process(false)
	main.queue_free()
	main = null
	await get_tree().process_frame
	get_tree().quit()
