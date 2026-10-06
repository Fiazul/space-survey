extends Node3D
var failures := 0
class StarScene extends PlanetSystem:
	func _ready() -> void:
		_dot_tex = _make_dot_texture()
		_build_sun_sky()
		_build_star_shell()

func _ready() -> void:
	ProfileDir.isolate("stellar_structures")
	for spec in [{"spectral":"G2V"},{"spectral":"M5.5V"},{"spectral":"K3III"},{"spectral":"DA3"},{"stellar_type":"pulsar"},{"spectral":"L4"}]:
		var recipe := StarRecipe.resolve(spec)
		var visual: Dictionary = recipe.stellar.get("visual", {})
		check("visible light default", visual.get("sensor_mode", "") == "visible")
		check("optional structures absent by default", not visual.get("aurora", true) and not visual.get("debris_disk", true) and not visual.get("wind_nebula", true))
	for pair in [["L4", "aurora"], ["DA3", "debris_disk"]]:
		var options := {pair[1]:true}
		var valid := StarRecipe.resolve({"spectral":pair[0],"stellar":{"visual":options}})
		check("family permits " + pair[1], valid.stellar.get("visual", {}).get(pair[1], false))
		var invalid := StarRecipe.resolve({"spectral":"G2V","stellar":{"visual":options}})
		check("wrong family rejects " + pair[1], not invalid.stellar.get("visual", {}).get(pair[1], false))
	var wind := StarRecipe.resolve({"stellar_type":"pulsar","stellar":{"visual":{"wind_nebula":true,"sensor_mode":"xray","wind_extent_radii":2.6e11}}})
	check("explicit X-ray wind retains enormous authored scale", wind.stellar.get("visual", {}).get("wind_nebula", false) and wind.stellar.visual.wind_extent_radii == 2.6e11)
	for options in [{"wind_nebula":true},{"wind_nebula":true,"sensor_mode":"xray","wind_extent_radii":NAN},{"sensor_mode":"banana"}]:
		var invalid := StarRecipe.resolve({"stellar_type":"pulsar","stellar":{"visual":options}})
		check("invalid wind cannot silently acquire compressed scale", not invalid.stellar.get("visual", {}).get("wind_nebula", false))
	var sun := StarRecipe.resolve({"name":"Sun"})
	var uv := StarRecipe.resolve({"name":"Sun","stellar":{"visual":{"sensor_mode":"uv"}}})
	check("UV palette cannot change physical color or luminosity", sun.color_a == uv.color_a and sun.stellar.luminosity_solar == uv.stellar.luminosity_solar)
	check("UV is explicit display color", uv.stellar.get("display_color", uv.color_a) != uv.color_a)
	var brown := StarRecipe.resolve({"name":"Clouds", "spectral":"L4"})
	var enhanced_brown := StarRecipe.resolve({"name":"Clouds", "spectral":"L4", "stellar":{"visual":{"sensor_mode":"enhanced_visible"}}})
	check("enhanced brown palette preserves continuum and flux", brown.color_a == enhanced_brown.color_a and brown.stellar.luminosity_solar == enhanced_brown.stellar.luminosity_solar)
	check("enhanced brown atmosphere uses approved red palette", enhanced_brown.stellar.display_color == Color("b12712"))
	if not FileAccess.file_exists("res://scripts/world/stellar_structures.gd"):
		check("production geometry module exists", false)
	else:
		_geometry_checks()
		_scene_checks()
	print("stellar_structures: ", "OK" if failures == 0 else "FAIL %d" % failures)
	get_tree().quit(1 if failures else 0)

func _geometry_checks() -> void:
	var module: GDScript = load("res://scripts/world/stellar_structures.gd")
	var spec := {"name":"Structure test", "star":true,"spectral":"M5.5V"}
	var recipe := StarRecipe.resolve(spec)
	for lod in [1,2]:
		var a: Array = module.geometry(recipe, lod, false)
		var b: Array = module.geometry(recipe, lod, false)
		check("geometry is batched", a.size() <= 3)
		var vertices := 0
		for i in a.size():
			var mesh: ArrayMesh = a[i].mesh
			check("one draw surface per batch", mesh.get_surface_count() == 1)
			var points: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
			vertices += points.size()
			check("deterministic geometry", points == b[i].mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX])
			for point in points:
				if not point.is_finite() or point.length() > 1.8:
					check("normalized corona bounds", false)
					break
		check("vertex budget", vertices <= 32768)
		print("corona LOD %d: %d vertices, %d structure draws" % [lod, vertices, a.size()])
	var other: Array = module.geometry(StarRecipe.resolve({"name":"Other star", "spectral":"M5.5V"}),2,false)
	check("seeds change magnetic geometry", other[0].mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] != module.geometry(recipe,2,false)[0].mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX])
	var look := PlanetGenerator.paint(spec, 7.0)
	print("photosphere: %d vertices, corona: 4 vertices; 2 base mesh surfaces" % look.sphere.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size())
	var controller: Node3D = look.sphere.get_child(0).get_child(0)
	check("paint defers structures", controller.get_child_count() == 0)
	controller.update_lod(.001, true)
	check("unresolved stars never allocate structures", controller.get_child_count() == 0)
	controller.update_lod(.05, true)
	check("resolved low LOD constructs bounded batches", controller.get_child_count() > 0 and controller.get_child_count() <= 3)
	check("radius-relative structure scale", controller.scale.is_equal_approx(Vector3.ONE*7.0))
	var low_count := controller.get_child_count()
	controller.update_lod(.06, true)
	check("stable LOD reuses nodes", controller.get_child_count() == low_count)
	controller.update_lod(.4, true)
	check("high LOD bounded batches", controller.get_child_count() <= 3)
	controller.update_lod(.4, false)
	check("hidden sphere releases structures", controller.get_child_count() == 0)
	look.sphere.free()
	module._mesh_cache.clear()
	var first := StarRecipe.resolve({"name":"Cache first"})
	var original: Array = module.geometry(first,2,true)
	check("cache fills on cached construction", module.cache_size() == 1)
	check("cache reuses mesh identity", module.geometry(first,2,true)[0].mesh == original[0].mesh)
	for i in 16:
		module.geometry(StarRecipe.resolve({"name":"Visited %d" % i}),2,true)
		check("visited-star resource cache never exceeds bound", module.cache_size() <= module.CACHE_LIMIT)
	check("visited-star resource cache full", module.cache_size() == module.CACHE_LIMIT)
	var regenerated: Array = module.geometry(first,2,true)
	check("oldest cache mesh evicted and regenerated", regenerated[0].mesh != original[0].mesh)
	check("eviction preserves deterministic geometry", regenerated[0].mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] == original[0].mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX])
	check("regenerated cache entry reused", module.geometry(first,2,true)[0].mesh == regenerated[0].mesh)
	var bare := PlanetGenerator.paint({"star":true,"stellar_type":"pulsar"},1.0)
	var compact: Node3D = bare.sphere.get_child(0).get_child(0)
	compact.update_lod(.4,true)
	check("bare remnant has no generic bands or winds", compact.get_child_count() == 0)
	bare.sphere.free()
	for variant in [
		{"spectral":"DA3","stellar":{"visual":{"debris_disk":true}}},
		{"spectral":"L4","stellar":{"visual":{"aurora":true}}},
		{"stellar_type":"pulsar","stellar":{"visual":{"wind_nebula":true,"sensor_mode":"xray","wind_extent_radii":2.6e11}}}]:
		var optional := StarRecipe.resolve(variant)
		var vertices := 0
		var max_radius := 0.0
		var batches: Array = module.geometry(optional,2,false)
		for batch in batches:
			var points: PackedVector3Array = batch.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
			vertices += points.size()
			var extent := 1.2
			if optional.stellar.visual.debris_disk: extent = optional.stellar.visual.disk_outer_radii*1.2
			if optional.stellar.visual.wind_nebula: extent = optional.stellar.visual.wind_extent_radii
			for point in points:
				max_radius = maxf(max_radius,point.length())
				if not point.is_finite() or point.length() > extent:
					check("optional geometry respects authored bounds",false)
					break
		check("optional vertex/draw budget",vertices <= 32768 and batches.size() <= 3)
		var low_vertices := 0
		var low: Array = module.geometry(optional,1,false)
		for batch in low:
			low_vertices += batch.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size()
		check("optional low LOD vertex/draw budget",low_vertices <= 32768 and low.size() <= 3)
		print("%s optional low: %d vertices, %d structure draws" % [optional.stellar.type,low_vertices,low.size()])
		if optional.stellar.visual.wind_nebula:
			check("wind geometry retains authored extent",max_radius > optional.stellar.visual.wind_extent_radii*.8)
			check("wind has batched diffuse emission",batches.size() == 3 and batches[2].kind == "cloud" and batches[1].mesh != batches[0].mesh)
		print("%s optional: %d vertices, %d structure draws" % [optional.stellar.type,vertices,batches.size()])
		variant["star"] = true
		var optional_look := PlanetGenerator.paint(variant,1.0)
		var optional_controller: Node3D = optional_look.sphere.get_child(0).get_child(0)
		optional_controller.update_lod(.001,true)
		if optional.stellar.visual.wind_nebula:
			check("resolved nebula loads despite unresolved core",optional_controller.get_child_count() == 3)
		optional_look.sphere.free()

func _scene_checks() -> void:
	var scene := StarScene.new()
	add_child(scene)
	for star in scene._stars:
		check("background catalog has no eager sphere",star.sphere == null)
	var spec := {"name":"Sun","star":true,"physical":true,"radius":Ephemeris.SUN_RADIUS_KM,
		"color":Color.WHITE,"stellar":{"visual":{"sensor_mode":"uv"}}}
	scene.load_system([spec])
	var near: MeshInstance3D = scene._bodies[0].sphere
	check("near and sky share authored visual recipe",near.get_meta("stellar_recipe") == scene._sun_sky.get_meta("stellar_recipe"))
	check("production paint binds shared cook",near.material_override.shader == PlanetGenerator.COOK_SHADER and scene._sun_sky.material_override.shader == PlanetGenerator.COOK_SHADER)
	for key in ["kind","seed","color_a","stellar_hot_color","stellar_cool_color","stellar_mode","stellar_cells","stellar_spots","stellar_activity","stellar_brightness","stellar_limb_floor","stellar_detail_contrast","stellar_temperature_k","sensor_mode","granulation"]:
		check("near/sky cook parameter agrees: "+key,near.material_override.get_shader_parameter(key) == scene._sun_sky.material_override.get_shader_parameter(key))
	var display: Color = near.get_meta("stellar_recipe").stellar.display_color
	check("cook binds explicit display color",near.material_override.get_shader_parameter("color_a") == Vector3(display.r,display.g,display.b))
	check("cook binds explicit hot display color",near.material_override.get_shader_parameter("stellar_hot_color") == near.get_meta("stellar_recipe").stellar.display_hot_color)
	check("cook binds UV sensor index",near.material_override.get_shader_parameter("sensor_mode") == 2)
	scene.refresh(Vector3(0,0,Ephemeris.SUN_RADIUS_KM*1.32),.016,"Sun")
	check("near owns resolved structures",near.visible and not scene._sun_sky.visible and near.get_child(0).get_child(0).get_child_count() > 0)
	scene.refresh(Vector3(0,0,Ephemeris.SUN_RADIUS_KM*4.0),.016,"Sun")
	check("far switches structures to sky primary",not near.visible and scene._sun_sky.visible and near.get_child(0).get_child(0).get_child_count() == 0 and scene._sun_sky.get_child(0).get_child(0).get_child_count() > 0)
	scene.refresh(Vector3(0,0,Ephemeris.SUN_RADIUS_KM*1000.0),.016,"Sun")
	check("unresolved sky primary releases geometry",scene._sun_sky.get_child(0).get_child(0).get_child_count() == 0)
	scene.free()

func check(label: String, condition: bool) -> void:
	if not condition:
		failures += 1
		push_error(label)
