class_name RenderStellarProduction
extends Node3D

const STRUCTURES := preload("res://scripts/world/stellar_structures.gd")
const SAMPLES := [
	{"id":"sun-visible","spec":{"name":"Sun"}},
	{"id":"red-dwarf-visible","spec":{"name":"Proxima","spectral":"M5.5V"}},
	{"id":"red-giant-visible","spec":{"name":"Cool giant","spectral":"M3III","stellar":{"temperature_k":3500}}},
	{"id":"white-dwarf-bare","spec":{"name":"Bare white dwarf","spectral":"DA3"}},
	{"id":"neutron-bare","spec":{"name":"Bare neutron star","stellar_type":"neutron_star"}},
	{"id":"brown-clouds-visible","spec":{"name":"Cloudy brown dwarf","spectral":"L4"}},
	{"id":"sun-uv","spec":{"name":"Sun","stellar":{"visual":{"sensor_mode":"uv"}}}},
	{"id":"brown-aurora-enhanced","spec":{"name":"Auroral brown dwarf","spectral":"L4","stellar":{"visual":{"sensor_mode":"enhanced_visible","aurora":true}}}},
	{"id":"white-dwarf-disk","spec":{"name":"Disk-bearing white dwarf","spectral":"DA3","stellar":{"visual":{"debris_disk":true}}}},
	{"id":"pulsar-xray-wind","spec":{"name":"Authored wind example","stellar_type":"pulsar","stellar":{"visual":{"sensor_mode":"xray","wind_nebula":true,"wind_extent_radii":2.6e11}}}},
	{"id":"cool-brown-visible","spec":{"name":"Cool brown dwarf","spectral":"T8"}},
	{"id":"hot-star-visible","spec":{"name":"Hot main sequence","spectral":"B1V"}},
]

func _ready() -> void:
	ProfileDir.isolate("stellar_production")
	get_window().mode = Window.MODE_WINDOWED
	get_window().size = Vector2i(1800,1440)
	get_window().content_scale_size = get_window().size
	var output := OS.get_environment("STELLAR_PRODUCTION_SHOTS")
	if output.is_empty(): output = "/tmp/stellar-production"
	DirAccess.make_dir_recursive_absolute(output)
	var layer := CanvasLayer.new()
	add_child(layer)
	var views: Array[SubViewport] = []
	var manifest: Array[Dictionary] = []
	for i in SAMPLES.size():
		var sample: Dictionary = SAMPLES[i]
		var spec: Dictionary = sample.spec.duplicate(true)
		spec["star"] = true
		var view := SubViewport.new()
		view.size = Vector2i(600,300)
		view.own_world_3d = true
		view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		add_child(view)
		views.append(view)
		var env := Environment.new()
		env.background_mode = Environment.BG_COLOR
		env.background_color = Color.BLACK
		env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
		env.tonemap_exposure = .8
		var world := WorldEnvironment.new()
		world.environment = env
		view.add_child(world)
		var look := PlanetGenerator.paint(spec,1.0)
		view.add_child(look.sphere)
		look.sphere.visible = true
		var visual: Dictionary = look.recipe.stellar.visual
		var extent := 1.0
		if visual.debris_disk: extent = visual.disk_outer_radii
		if visual.wind_nebula: extent = visual.wind_extent_radii
		var camera := Camera3D.new()
		camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		camera.size = extent*3.35
		camera.near = maxf(extent*.0001,.001)
		camera.far = extent*20.0
		camera.position = Vector3(0,extent*.6,extent*10.0)
		view.add_child(camera)
		camera.look_at(Vector3.ZERO)
		camera.make_current()
		STRUCTURES.update(look.sphere,.3/extent,true)
		var origin := Vector2((i%3)*600,(i/3)*360)
		var texture := TextureRect.new()
		texture.position = origin
		texture.size = Vector2(600,300)
		texture.texture = view.get_texture()
		layer.add_child(texture)
		var label := Label.new()
		label.position = origin+Vector2(12,300)
		label.add_theme_font_size_override("font_size",15)
		label.text = "%s · %s\ncore %.0f km; frame %s core radii" % [sample.id,visual.sensor_mode,look.recipe.stellar.radius_km,str(extent*3.35)]
		layer.add_child(label)
		manifest.append({"id":sample.id,"sensor_mode":visual.sensor_mode,"core_radius_km":look.recipe.stellar.radius_km,"frame_core_radii":extent*3.35,"production":true})
	for i in 8: await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var failures := 0
	for i in views.size():
		var capture := views[i].get_texture().get_image()
		if capture == null or capture.save_png(output.path_join(SAMPLES[i].id+".png")) != OK:
			failures += 1
	var gallery := get_viewport().get_texture().get_image()
	if gallery == null or gallery.save_png(output.path_join("gallery.png")) != OK:
		failures += 1
	var file := FileAccess.open(output.path_join("manifest.json"),FileAccess.WRITE)
	if file == null:
		failures += 1
	else:
		file.store_string(JSON.stringify(manifest,"\t"))
		file.close()
	print("stellar_production: %s -> %s" % ["OK" if failures == 0 else "FAIL",output])
	get_tree().quit(1 if failures else 0)
