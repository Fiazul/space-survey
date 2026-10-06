class_name TestStellarCoronaClipping
extends Node3D

const STRUCTURES := preload("res://scripts/world/stellar_structures.gd")
var failed := false
var output: String
var camera: Camera3D
var env: Environment

func _ready() -> void:
	ProfileDir.isolate("stellar_corona_clipping")
	get_window().size = Vector2i(960, 540)
	env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color.BLACK
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = .7
	var world := WorldEnvironment.new()
	world.environment = env
	add_child(world)
	camera = Camera3D.new()
	camera.fov = 70
	camera.near = .001
	camera.position.z = 1.6
	camera.rotation_degrees = Vector3(-20, 20, 25)
	add_child(camera)
	camera.make_current()
	output = OS.get_environment("CORONA_SHOT_DIR")
	if output.is_empty(): output = "/tmp/corona-clipping"
	DirAccess.make_dir_recursive_absolute(output)
	var look := PlanetGenerator.paint({"name":"Sun", "star":true}, 1.0)
	add_child(look.sphere)
	look.sphere.visible = true
	var controller: Node3D = look.sphere.get_child(0).get_child(0)
	controller.set_process(false)
	var corona := look.sphere.get_child(0) as MeshInstance3D
	var frozen := corona.material_override.duplicate() as ShaderMaterial
	var shader := Shader.new()
	shader.code = frozen.shader.code.replace("TIME", "0.0")
	frozen.shader = shader
	corona.material_override = frozen
	camera.far = 1000.0
	var reference := await capture("reference")
	camera.far = Ephemeris.CAM_RENDER_FAR_KM / Ephemeris.SUN_RADIUS_KM
	var game_range := await capture("game_range")
	var changed := changed_pixels(reference,game_range,.02)
	var fraction := float(changed)/(reference.get_width()*reference.get_height())
	print("stellar_corona_clipping: changed fraction %.5f" % fraction)
	check("Game camera range cuts off the stellar corona",fraction <= .001)
	# Isolate the corona so the selected lit pixel cannot belong to the core.
	look.sphere.layers = 0
	var halo_only := await capture("halo_only")
	await foreground_check("corona",halo_only,0.2,0.3)
	look.sphere.layers = 1
	var game_far := Ephemeris.CAM_RENDER_FAR_KM / Ephemeris.SUN_RADIUS_KM
	# Compare glow alone: photosphere triangles legitimately cross this short
	# far plane, and their new unclipped display brightness is below the old
	# test's bright-pixel exclusion. Their clipping does not measure halo loss.
	look.sphere.layers = 0
	camera.position = Vector3(0,0,1.32)
	camera.rotation_degrees = Vector3(0,-72,0)
	env.tonemap_exposure = 4.0
	camera.near = .05 / Ephemeris.SUN_RADIUS_KM
	camera.far = game_far
	var grazing := await capture("grazing_game_range")
	camera.near = .001
	camera.far = 50.0
	var grazing_reference := await capture("grazing_reference")
	changed = changed_pixels(grazing_reference,grazing,.01)
	var glow_pixels := 0
	for y in grazing_reference.get_height():
		for x in grazing_reference.get_width():
			if grazing_reference.get_pixel(x,y).r > .02: glow_pixels += 1
	print("stellar_corona_clipping: grazing glow pixels %d, changed by game far plane %d" % [glow_pixels,changed])
	check("Grazing view: game camera range cuts the corona",glow_pixels >= 2000 and changed <= 50)
	look.sphere.free()
	await optional_checks()
	print("stellar_corona_clipping: ", "FAIL" if failed else "OK")
	get_tree().quit(1 if failed else 0)

func optional_checks() -> void:
	camera.position = Vector3(0,0,1.6)
	camera.rotation = Vector3.ZERO
	camera.near = .001
	env.tonemap_exposure = .7
	for spec in [
		{"star":true,"spectral":"DA3","stellar":{"visual":{"debris_disk":true}}},
		{"star":true,"spectral":"L4","stellar":{"visual":{"aurora":true,"sensor_mode":"enhanced_visible"}}},
		{"star":true,"stellar_type":"pulsar","stellar":{"visual":{"wind_nebula":true,"sensor_mode":"xray","wind_extent_radii":2.6e11}}}]:
		var look := PlanetGenerator.paint(spec,1.0)
		add_child(look.sphere)
		look.sphere.visible = true
		var visual: Dictionary = look.recipe.stellar.visual
		var extent := 1.2
		if visual.debris_disk: extent = float(visual.disk_outer_radii)*1.2
		if visual.wind_nebula: extent = float(visual.wind_extent_radii)
		# Retain the authored geometry; only the parent transform compresses the frame.
		look.sphere.scale = Vector3.ONE/extent
		look.sphere.layers = 0
		var corona := look.sphere.get_child(0) as MeshInstance3D
		corona.layers = 0
		var controller: Node3D = corona.get_child(0)
		controller.set_process(false)
		controller.update_lod(.4,true)
		var batches := controller.get_children()
		for batch in batches: batch.visible = false
		for index in batches.size():
			var batch := batches[index] as MeshInstance3D
			batch.visible = true
			var label := "%s_%s_%d" % [look.recipe.stellar.type,batch.material_override.shader.resource_path.get_file().get_basename(),index]
			camera.far = 1000.0
			var reference := await capture(label+"_reference")
			camera.far = 1.4
			var limited := await capture(label+"_far")
			var changed := changed_pixels(reference,limited,.01)
			print("stellar_corona_clipping: %s far-plane changed %d" % [label,changed])
			check(label+" far-plane projection",changed <= 50)
			# Each transformed batch's nearest bound must lie behind the entire blocker.
			var nearest := nearest_depth(batch)
			check(label+" geometry lies beyond foreground blocker",nearest > .06)
			await foreground_check(label,limited,.04,nearest)
			batch.visible = false
		look.sphere.free()

func nearest_depth(batch: MeshInstance3D) -> float:
	var nearest := INF
	var points: PackedVector3Array = batch.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	for point in points:
		var position := camera.to_local(batch.to_global(point))
		nearest = minf(nearest,-position.z)
	# Cloud vertices rotate toward the camera; enclose the widest quad as well.
	if batch.material_override.shader == STRUCTURES.CLOUD:
		var custom: PackedFloat32Array = batch.mesh.surface_get_arrays(0)[Mesh.ARRAY_CUSTOM0]
		for i in range(0,custom.size(),4):
			var center := Vector3(custom[i],custom[i+1],custom[i+2])
			nearest = minf(nearest,-camera.to_local(batch.to_global(center)).z-custom[i+3]*batch.global_basis.get_scale().x)
	return nearest

func foreground_check(label: String, source: Image, depth: float, nearest: float) -> void:
	var sample := Vector2i(-1,-1)
	var best := .01
	for y in range(12,source.get_height()-12):
		for x in range(12,source.get_width()-12):
			var pixel := source.get_pixel(x,y)
			var light := maxf(pixel.r,pixel.g)
			if label == "corona":
				var screen := (Vector2(x,y)+Vector2(.5,.5))/Vector2(source.get_size())*get_viewport().get_visible_rect().size
				var origin := camera.project_ray_origin(screen)
				var ray := camera.project_ray_normal(screen)
				var along := origin.dot(ray)
				if along*along-origin.length_squared()+1.0 >= 0.0: continue
			if light > best:
				best = light
				sample = Vector2i(x,y)
	check(label+" has a lit effect pixel",sample.x >= 0)
	if sample.x < 0: return
	var screen_sample := (Vector2(sample)+Vector2(.5,.5))/Vector2(source.get_size())*get_viewport().get_visible_rect().size
	var blocker := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3.ONE*.01
	blocker.mesh = box
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(0,0,.8)
	blocker.material_override = material
	add_child(blocker)
	blocker.position = camera.project_position(screen_sample,depth)
	var actual_depth := -camera.to_local(blocker.position).z
	if label == "corona":
		var facing := camera.position.normalized()
		var center := facing/camera.position.length()
		var origin := camera.project_ray_origin(screen_sample)
		var ray := camera.project_ray_normal(screen_sample)
		var distance := facing.dot(center-origin)/facing.dot(ray)
		nearest = -camera.to_local(origin+ray*distance).z
	check(label+" blocker is in front of effect depth",actual_depth+.009 < nearest and actual_depth-.009 > camera.near)
	var blocked := await capture(label+"_foreground")
	var pixel := blocked.get_pixelv(sample)
	var occluded := pixel.r < .02 and pixel.g < .02 and pixel.b > .3
	print("stellar_corona_clipping: %s foreground occlusion %s (source %.3f, blocker depth %.3f, effect bound %.3f)" % [label,str(occluded),best,actual_depth,nearest])
	check(label+" foreground geometry blocks effect",occluded)
	blocker.free()

func capture(label: String) -> Image:
	for i in 4: await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var shot := get_viewport().get_texture().get_image()
	check(label+" capture saved",shot != null and shot.save_png(output.path_join(label+".png")) == OK)
	return shot

func changed_pixels(reference: Image, actual: Image, tolerance: float) -> int:
	var changed := 0
	for y in reference.get_height():
		for x in reference.get_width():
			var a := reference.get_pixel(x,y)
			var b := actual.get_pixel(x,y)
			if maxf(a.r,maxf(a.g,a.b)) < .85 and maxf(absf(a.r-b.r),maxf(absf(a.g-b.g),absf(a.b-b.b))) > tolerance: changed += 1
	return changed

func check(label: String, condition: bool) -> void:
	if not condition:
		failed = true
		push_error(label)
