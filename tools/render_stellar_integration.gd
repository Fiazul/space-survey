class_name RenderStellarIntegration
extends Node3D
## Captures the production cook and structure controller without preview shaders.

const SAMPLES := [
	{"id":"solar-visible", "name":"Sun", "spectral":"G2V", "view":4.6},
	{"id":"solar-uv", "name":"Sun", "spectral":"G2V", "view":4.6,
		"stellar":{"visual":{"sensor_mode":"uv"}}},
	{"id":"red-dwarf", "name":"Active M dwarf", "spectral":"M5.5V", "view":4.6},
	{"id":"red-giant", "name":"Cool giant", "spectral":"M2III", "view":4.6},
	{"id":"white-dwarf-bare", "name":"White dwarf", "spectral":"DA3", "view":4.6},
	{"id":"white-dwarf-disk", "name":"Dusty white dwarf", "spectral":"DA3", "view":62.0,
		"stellar":{"visual":{"debris_disk":true}}},
	{"id":"neutron-star-bare", "name":"Neutron star", "stellar_type":"neutron_star", "view":4.6},
	{"id":"pulsar-wind", "name":"Wind visualization", "stellar_type":"pulsar", "view":110.0,
		"stellar":{"visual":{"sensor_mode":"xray", "wind_nebula":true, "wind_extent_radii":45.0}}},
	{"id":"brown-dwarf-visible", "name":"Brown dwarf", "spectral":"L8", "view":4.6},
	{"id":"brown-dwarf-aurora", "name":"Auroral brown dwarf", "spectral":"L4", "view":4.6,
		"stellar":{"visual":{"sensor_mode":"enhanced_visible", "aurora":true}}},
]

func _ready() -> void:
	ProfileDir.isolate("render_stellar_integration")
	get_window().size = Vector2i(960, 640)
	get_window().content_scale_size = Vector2i(960, 640)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("030609")
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = .7
	EnvironmentLook.apply(env)
	var world := WorldEnvironment.new()
	world.environment = env
	add_child(world)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.near = .01
	camera.far = 500.0
	add_child(camera)
	camera.make_current()
	var output := ProjectSettings.globalize_path("res://docs/reference/stellar-integration")
	DirAccess.make_dir_recursive_absolute(output)
	var manifest: Array[Dictionary] = []
	var failures := 0
	for sample in SAMPLES:
		var spec: Dictionary = sample.duplicate(true)
		spec["star"] = true
		var look := PlanetGenerator.paint(spec, 1.0)
		var sphere: MeshInstance3D = look.sphere
		add_child(sphere)
		sphere.visible = true
		camera.size = float(sample.view)
		camera.position = Vector3(0, 0, float(sample.view) * 2.0)
		var controller: Node3D = sphere.get_child(0).get_child(0)
		for frame in 5:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var capture := get_viewport().get_texture().get_image()
		var saved := capture.save_png(output.path_join(str(sample.id) + ".png"))
		if saved != OK:
			push_error("Production stellar capture failed: " + str(sample.id))
			failures += 1
		manifest.append({"id":sample.id, "spec":spec, "view_diameter_radii":sample.view,
			"structure_batches":controller.get_child_count(), "sensor_mode":look.recipe.stellar.visual.sensor_mode})
		print("stellar integration capture: ", sample.id, " batches=", controller.get_child_count())
		sphere.free()
	var file := FileAccess.open(output.path_join("captures.json"), FileAccess.WRITE)
	if file == null:
		failures += 1
	else:
		file.store_string(JSON.stringify(manifest, "\t"))
		file.close()
	print("stellar_integration_render: ", "OK" if failures == 0 else "FAIL")
	get_tree().quit(1 if failures else 0)
