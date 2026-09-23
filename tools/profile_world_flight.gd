class_name ProfileWorldFlight
extends Node
## PERF_PROFILE=1 PROFILE_CASE=forest godot --headless --max-fps 60 --path . res://tools/profile_world_flight.tscn
var main: Node
var frame := 0
var samples := {}
var mode := "forest"
var up := Vector3.UP
var last_frame_us := 0
var hide := OS.get_environment("PROFILE_HIDE")

func _ready() -> void:
	mode = OS.get_environment("PROFILE_CASE") if OS.has_environment("PROFILE_CASE") else "forest"
	main = preload("res://scripts/core/main.gd").new()
	add_child(main)
	main.set_process(false)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
	var sampler: TerrainSampler = main.planets.terrain_sampler_for("Earth")
	var dir := DevSites.dir_for(-3.0, -60.0) if mode == "forest" else DevSites.dir_for(27.99, 86.93)
	if mode == "ruins":
		dir = DevSites.dir_for(51.51, -0.12)
	up = main.planets.surface_basis("Earth") * dir
	main.ship.set_anchor("Earth")
	var altitude := 0.3 if mode in ["forest", "ruins"] else (30.0 if mode == "exit" else 3.0)
	main.ship.anchor_off = up * (sampler.ground_radius_km(dir, 6371.0) + altitude)
	main.ship.velocity = up * 15.0 if mode == "exit" else up.cross(Vector3.UP).normalized() * 0.3
	main.ship.terrain = sampler
	main.ship.terrain_basis = main.planets.surface_basis("Earth")
	main.ship.nearest_name = "Earth"
	main.ship.nearest_radius = 6371.0
	main._prev_body = ""
	main.ship.transform.basis = Basis.looking_at(main.ship.velocity.normalized(), up) if mode != "exit" else Basis.looking_at(up, Vector3.UP)
	main.ship._cam_basis = main.ship.transform.basis

func _process(_delta: float) -> void:
	if main == null:
		return
	var start := Time.get_ticks_usec()
	if frame > 120 and last_frame_us > 0:
		_record("wall_frame", start - last_frame_us)
	last_frame_us = start
	main._process(1.0 / 60.0)
	var elapsed := Time.get_ticks_usec() - start
	var surface: Node = main.planets.get("_surface")
	if hide == "trees":
		for node in surface.get("_prop_nodes"):
			node.visible = false
	elif hide == "terrain":
		surface.visible = false
	elif hide == "air":
		main.planets.get("_air_shell").visible = false
	elif hide == "clouds":
		main.planets.get("_cloud_layer").visible = false
	if frame > 120:
		_record("main_total", elapsed)
		_record("gpu", int(RenderingServer.viewport_get_measured_render_time_gpu(get_viewport().get_viewport_rid()) * 1000.0))
		_record("render_cpu", int(RenderingServer.viewport_get_measured_render_time_cpu(get_viewport().get_viewport_rid()) * 1000.0))
		var patch: Node = main.planets.get("_surface")
		if patch.perf_commit_us > 0:
			_record("terrain_commit", patch.perf_commit_us)
		if patch.perf_props_us > 0:
			_record("prop_upload", patch.perf_props_us)
		for key in main.perf_timings:
			_record(key, main.perf_timings[key])
	frame += 1
	if frame >= 360:
		for key in samples:
			var values: Array = samples[key]
			values.sort()
			print("PROFILE ", mode, " ", key, " median_ms=", values[values.size()/2] / 1000.0,
				" p95_ms=", values[int(values.size()*0.95)] / 1000.0, " max_ms=", values[-1] / 1000.0)
		print("RENDER window=", DisplayServer.window_get_size(), " primitives=", Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME), " draws=", Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
		if OS.has_environment("PROFILE_SHOT"):
			get_viewport().get_texture().get_image().save_png(OS.get_environment("PROFILE_SHOT"))
		print("PIPELINES draw=", Performance.get_monitor(Performance.PIPELINE_COMPILATIONS_DRAW), " mesh=", Performance.get_monitor(Performance.PIPELINE_COMPILATIONS_MESH), " surface=", Performance.get_monitor(Performance.PIPELINE_COMPILATIONS_SURFACE))
		main.queue_free()
		main = null
		await get_tree().process_frame
		get_tree().quit()

func _record(key: String, us: int) -> void:
	if not samples.has(key):
		samples[key] = []
	samples[key].append(us)
