class_name ProfileGalacticCore
extends Node

var main: Node
var frame := 0
var samples := {}
var observer := Vector3.ZERO
var velocity := Vector3.ZERO
var ship_basis := Basis.IDENTITY
var camera_transform := Transform3D.IDENTITY
var camera_fov := 70.0
var previous_us := 0
var mode := ""
var frames := 120
var warmup := 40
var gpu_budget_ms := 0.0
var cpu_budget_ms := 0.0
var failures := 0
var shader_override: Shader
var render_size := Vector2i(1280, 720)
var output := "res://.scratch-assets/core-profile"
var case_index := 0
var cases := [
	{"name": "close", "au": 2.0, "hide": ""},
	{"name": "no_lens", "au": 2.0, "hide": "lens"},
	{"name": "no_stars", "au": 2.0, "hide": "stars"},
	{"name": "no_gas", "au": 2.0, "hide": "gas"},
	{"name": "no_core", "au": 2.0, "hide": "core"},
	{"name": "no_background", "au": 2.0, "hide": "background"},
	{"name": "approach", "au": 1.2, "hide": ""},
	{"name": "infall", "au": 1.2, "hide": "", "inward": true},
	{"name": "arrival", "au": 7.9, "hide": ""},
	{"name": "wide", "au": 79.0, "hide": ""},
]

func _ready() -> void:
	ProfileDir.isolate("profile_galactic_core")
	if DisplayServer.get_name() == "headless":
		push_error("Core profiling requires a rendering display; headless timing cannot verify GPU cost")
		get_tree().quit(1)
		return
	OS.set_environment("PERF_PROFILE", "1")
	get_window().mode = Window.MODE_WINDOWED
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
	if OS.has_environment("CORE_PROFILE_FRAMES"):
		frames = maxi(20, int(OS.get_environment("CORE_PROFILE_FRAMES")))
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--case="):
			cases = cases.filter(func(c): return c.name == argument.trim_prefix("--case="))
		elif argument.begins_with("--gpu-budget-ms="):
			gpu_budget_ms = float(argument.trim_prefix("--gpu-budget-ms="))
		elif argument.begins_with("--cpu-budget-ms="):
			cpu_budget_ms = float(argument.trim_prefix("--cpu-budget-ms="))
		elif argument.begins_with("--shader="):
			var shader_path := argument.trim_prefix("--shader=")
			if not FileAccess.file_exists(shader_path):
				push_error("Reference shader does not exist: " + shader_path)
				get_tree().quit(1)
				return
			var resource := load(shader_path)
			if not resource is Shader:
				push_error("Reference resource is not a shader: " + shader_path)
				get_tree().quit(1)
				return
			shader_override = resource
		elif argument.begins_with("--size="):
			var dimensions := argument.trim_prefix("--size=").split("x")
			if dimensions.size() != 2 or int(dimensions[0]) <= 0 or int(dimensions[1]) <= 0:
				push_error("Profile size must be positive WIDTHxHEIGHT")
				get_tree().quit(1)
				return
			render_size = Vector2i(int(dimensions[0]), int(dimensions[1]))
		elif argument.begins_with("--shots="):
			output = argument.trim_prefix("--shots=")
	if cases.is_empty():
		push_error("Unknown core profile case")
		get_tree().quit(1)
		return
	get_window().size = render_size
	var config := ConfigFile.new()
	config.set_value("player", "system", SystemDB.SAGITTARIUS_A)
	config.save(GameState.profile_path())
	main = load("res://scenes/Main.tscn").instantiate()
	add_child(main)
	main.set_process(false)
	main.set_process_input(false)
	main.set_process_unhandled_input(false)
	main.onboarding.set_process(false)
	main.ship.set_process_input(false)
	main.ship.set_process_unhandled_input(false)
	_begin_case()

func _begin_case() -> void:
	var current: Dictionary = cases[case_index]
	mode = current.hide
	frame = 0
	samples.clear()
	previous_us = 0
	main.galactic_core.visible = true
	main.galactic_core._stars.visible = true
	main.galactic_core._gas.visible = true
	main.dev_sites.go_core({"au": current.au, "polar": false})
	if shader_override != null:
		for body in main.planets._bodies:
			if body.name == "Sagittarius A*": body.mat.shader = shader_override
	main.ship._set_capture(false)
	observer = main.ship.anchor_off
	velocity = main.ship.velocity
	if current.get("inward", false): velocity = -observer.normalized()*50000.0
	ship_basis = main.ship.transform.basis
	main.ship._cam_basis = ship_basis
	main.ship._kill_turn_rates()
	main.ship._mouse_delta = Vector2.ZERO
	main.ship._update_camera(0.0)
	camera_transform = main.ship.camera.global_transform
	camera_fov = Ship.FOV_BASE + clampf(velocity.length()/Ship.MAX_SPEED, 0.0, 1.0)*Ship.FOV_KICK
	main.ship.camera.fov = camera_fov
	main._process(0.0)
	_lock_view()
	print("CORE_PROFILE begin case=", current.name, " au=", current.au, " hide=", mode,
		" adapter=", RenderingServer.get_video_adapter_name(), " window=", get_window().size,
		" renderer=", RenderingServer.get_current_rendering_method(), " scale=", get_viewport().scaling_3d_scale,
		" shader=", shader_override.resource_path if shader_override != null else BlackHoleRenderer.SHADER.resource_path)

func _process(_delta: float) -> void:
	if main == null: return
	var start := Time.get_ticks_usec()
	if frame > warmup and previous_us > 0:
		_record("wall_frame", start - previous_us)
	previous_us = start
	main.ship.relocate(observer)
	main.ship.velocity = velocity
	main.ship.transform.basis = ship_basis
	main.ship._cam_basis = ship_basis
	main.ship._mouse_delta = Vector2.ZERO
	main._process(1.0 / 60.0)
	_record_if_warm("main_cpu", Time.get_ticks_usec() - start)
	_lock_view()
	for body in main.planets._bodies:
		if body.name == "Sagittarius A*" and mode == "lens": body.sphere.visible = false
	if mode == "stars": main.galactic_core._stars.visible = false
	if mode == "gas": main.galactic_core._gas.visible = false
	if mode == "core": main.galactic_core.visible = false
	if mode in ["background", "lens"] and main.planets.black_hole_background != null:
		main.planets.black_hole_background.suspend()
	var viewport := get_viewport().get_viewport_rid()
	_record_if_warm("gpu", int(RenderingServer.viewport_get_measured_render_time_gpu(viewport) * 1000.0))
	_record_if_warm("render_cpu", int(RenderingServer.viewport_get_measured_render_time_cpu(viewport) * 1000.0))
	for key in main.perf_timings:
		_record_if_warm(key, main.perf_timings[key])
	frame += 1
	if frame >= warmup + frames:
		_finish_case()

func _lock_view() -> void:
	main.ship.transform.basis = ship_basis
	main.ship.camera.global_transform = camera_transform
	main.ship.camera.fov = camera_fov
	for body in main.planets._bodies:
		if body.name == "Sagittarius A*":
			BlackHoleRenderer.update(body.sphere, -main.ship.anchor_off, float(body.radius),
				float(body.mat.get_shader_parameter("sim_time"))/BlackHoleRenderer.TIME_LAPSE)

func _finish_case() -> void:
	set_process(false)
	var current: Dictionary = cases[case_index]
	for key in samples:
		var values: Array = samples[key]
		values.sort()
		print("CORE_PROFILE ", current.name, " ", key, " median_ms=", values[values.size()/2]/1000.0,
			" p95_ms=", values[int(values.size()*.95)]/1000.0, " max_ms=", values[-1]/1000.0)
		if key == "gpu" and gpu_budget_ms > 0.0:
			if values[values.size()/2] <= 0:
				push_error("GPU timer is unavailable; the requested budget cannot be verified")
				failures += 1
			elif values[values.size()/2]/1000.0 > gpu_budget_ms:
				push_error("Core GPU frame exceeds %.1f ms budget" % gpu_budget_ms)
				failures += 1
		if key == "main_cpu" and cpu_budget_ms > 0.0 and values[int(values.size()*.95)]/1000.0 > cpu_budget_ms:
			push_error("Core CPU p95 frame exceeds %.1f ms budget" % cpu_budget_ms)
			failures += 1
	print("CORE_PROFILE ", current.name, " draws=", Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		" primitives=", Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
	await RenderingServer.frame_post_draw
	var directory_error := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	if directory_error != OK:
		push_error("Cannot create profile screenshot directory: " + output)
		failures += 1
	elif get_viewport().get_texture().get_image().save_png(output.path_join(current.name + ".png")) != OK:
		push_error("Cannot save profile screenshot for " + current.name)
		failures += 1
	case_index += 1
	if case_index < cases.size():
		_begin_case()
		set_process(true)
		return
	main.queue_free()
	main = null
	await get_tree().process_frame
	get_tree().quit(1 if failures else 0)

func _record_if_warm(key: String, us: int) -> void:
	if frame > warmup: _record(key, us)

func _record(key: String, us: int) -> void:
	if not samples.has(key): samples[key] = []
	samples[key].append(us)
