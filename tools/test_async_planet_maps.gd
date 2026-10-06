extends SceneTree
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var delayed_script := "/tmp/astryx_delayed_texture.gd"
	var script_file := FileAccess.open(delayed_script, FileAccess.WRITE)
	script_file.store_string("extends GradientTexture2D\nfunc _init():\n OS.delay_msec(600)\n")
	script_file.close()
	var delayed_path := "/tmp/astryx_delayed_texture.tres"
	var resource_file := FileAccess.open(delayed_path, FileAccess.WRITE)
	resource_file.store_string('[gd_resource type="GradientTexture2D" load_steps=2 format=3]\n[ext_resource type="Script" path="%s" id="1"]\n[resource]\nscript = ExtResource("1")\n' % delayed_script)
	resource_file.close()
	var ready_path := "/tmp/astryx_ready_texture.tres"
	var gradient := GradientTexture2D.new()
	gradient.gradient = Gradient.new()
	ResourceSaver.save(gradient, ready_path)
	var recipe := {"clouds": ready_path, "normal": delayed_path}
	var mat := PlanetGenerator.make_material({"kind": "rocky"}, {}) as ShaderMaterial
	var started := Time.get_ticks_msec()
	var connections_before := process_frame.get_connections().size()
	PlanetGenerator.ensure_close_maps(mat, recipe)
	check("starting map loads does not block on slow asset", Time.get_ticks_msec() - started < 300)
	var saw_early := false
	for i in 100:
		await process_frame
		if float(mat.get_shader_parameter("has_clouds")) > .5:
			saw_early = true
			break
		OS.delay_msec(2)
	check("fast map binds before the slow map", saw_early and float(mat.get_shader_parameter("has_normal")) < .5)
	for i in 3:
		await process_frame
		check("completed maps remain enabled while other maps load", float(mat.get_shader_parameter("has_clouds")) > .5)
	for i in 400:
		await process_frame
		if float(mat.get_shader_parameter("has_normal")) > .5:
			break
		OS.delay_msec(2)
	check("late map eventually binds", float(mat.get_shader_parameter("has_normal")) > .5)
	for i in 3:
		await process_frame
		check("both maps stay enabled after completion", float(mat.get_shader_parameter("has_clouds")) > .5 and float(mat.get_shader_parameter("has_normal")) > .5)
	check("map poll disconnects after all loads", process_frame.get_connections().size() == connections_before)
	print("async_planet_maps: ", "OK" if failures == 0 else "FAIL %d" % failures)
	quit(0 if failures == 0 else 1)

func check(label: String, condition: bool) -> void:
	if not condition:
		failures += 1
		printerr("FAIL: ", label)
