class_name StellarStructures
extends Node3D
## Core-relative, bounded batches for resolved stars; attached below the corona,
## whose shader billboard does not change the children's CPU transforms.
const FILAMENT := preload("res://shaders/stellar_filament.gdshader")
const HALO := preload("res://shaders/stellar_shell.gdshader")
const DISK := preload("res://shaders/stellar_disk.gdshader")
const CLOUD := preload("res://shaders/stellar_cloud.gdshader")
const AURORA := preload("res://shaders/stellar_aurora.gdshader")
const CACHE_LIMIT := 8
const LOW_ANGLE := .02
const HIGH_ANGLE := .12
static var _mesh_cache: Dictionary = {}
var recipe: Dictionary
var radius := 1.0
var _lod := 0

static func attach(corona: MeshInstance3D, resolved: Dictionary, rendered_radius: float) -> Node3D:
	var node = load("res://scripts/world/stellar_structures.gd").new()
	node.recipe = resolved
	node.radius = rendered_radius
	node.scale = Vector3.ONE * rendered_radius
	corona.add_child(node)
	return node

static func update(sphere: MeshInstance3D, angular_radius: float, shown: bool) -> void:
	if sphere.get_child_count() == 0:
		return
	var corona := sphere.get_child(0)
	if corona.get_child_count() > 0 and corona.get_child(0).get_script() == load("res://scripts/world/stellar_structures.gd"):
		corona.get_child(0).update_lod(angular_radius, shown)

func _process(_delta: float) -> void:
	var sphere := get_parent().get_parent() as MeshInstance3D
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var displayed_radius := radius * sphere.global_basis.get_scale().x
	var angle := atan(displayed_radius / maxf(camera.global_position.distance_to(sphere.global_position), .000001))
	if camera.projection == Camera3D.PROJECTION_ORTHOGONAL:
		angle = displayed_radius / maxf(camera.size, .000001)
	update_lod(angle, sphere.is_visible_in_tree())

func update_lod(angular_radius: float, shown: bool) -> void:
	var extent := 1.0
	var visual: Dictionary = recipe.stellar.visual
	if visual.debris_disk: extent = float(visual.disk_outer_radii)
	if visual.wind_nebula: extent = float(visual.wind_extent_radii)
	angular_radius = atan(tan(minf(angular_radius, PI*.49))*extent)
	var wanted := 0
	if shown and angular_radius >= LOW_ANGLE:
		wanted = 2 if angular_radius >= HIGH_ANGLE else 1
	# Hysteresis prevents rebuilding while crossing a threshold in a circular orbit.
	if shown and _lod > 0 and angular_radius >= LOW_ANGLE * .8:
		if _lod == 2 and angular_radius >= HIGH_ANGLE * .8:
			wanted = 2
		elif wanted == 0:
			wanted = 1
	if wanted == _lod:
		return
	for child in get_children():
		child.free()
	_lod = wanted
	var halo := get_parent().material_override as ShaderMaterial
	halo.set_shader_parameter("structure_active", false)
	if wanted == 0:
		return
	for batch in geometry(recipe, wanted):
		var mesh := MeshInstance3D.new()
		mesh.mesh = batch.mesh
		mesh.rotation_degrees = batch.get("rotation", Vector3.ZERO)
		var mat := ShaderMaterial.new()
		mat.render_priority = halo.render_priority
		match str(batch.kind):
			"disk": mat.shader = DISK
			"aurora": mat.shader = AURORA
			"shell": mat.shader = HALO
			"cloud": mat.shader = CLOUD
			_: mat.shader = FILAMENT
		mat.set_shader_parameter("seed", recipe.seed)
		mat.set_shader_parameter("tint", batch.get("tint", recipe.stellar.display_hot_color))
		mat.set_shader_parameter("cloud_extent", batch.get("extent", 1.0))
		var strength: float = batch.strength
		if str(batch.kind) == "filament" and not recipe.stellar.visual.wind_nebula:
			strength *= .2 + .8 * float(recipe.stellar.activity)
			if recipe.stellar.visual.sensor_mode != "visible": strength *= 3.0
		if str(batch.kind) == "aurora" and recipe.stellar.visual.sensor_mode == "visible": strength *= .3
		mat.set_shader_parameter("strength", strength)
		mat.set_shader_parameter("closed", batch.get("closed", false))
		mat.set_shader_parameter("jet", batch.get("jet", false))
		mesh.material_override = mat
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mesh.extra_cull_margin = float(batch.get("extent", 2.0))
		add_child(mesh)
	halo.set_shader_parameter("structure_active", get_child_count() > 0)

static func cache_size() -> int:
	return _mesh_cache.size()

static func geometry(resolved: Dictionary, lod: int, cached := true) -> Array:
	var visual: Dictionary = resolved.stellar.visual
	var key := str([resolved.seed, resolved.stellar.type, lod, visual])
	if cached and _mesh_cache.has(key):
		return _mesh_cache[key]
	var rng := RandomNumberGenerator.new()
	rng.seed = int(float(resolved.seed) * 100000.0)
	var batches: Array = []
	var family := str(resolved.stellar.type)
	if family in ["main_sequence", "subdwarf", "subgiant", "wolf_rayet"]:
		batches = _corona(rng, lod)
	elif family in ["giant", "bright_giant", "supergiant", "carbon_star"]:
		var shell := SphereMesh.new()
		shell.radius = 1.08
		shell.height = 2.16
		shell.radial_segments = 32 if lod == 2 else 16
		shell.rings = 16 if lod == 2 else 8
		batches.append({"mesh":shell, "kind":"shell", "strength":.10, "extent":1.1})
	if visual.debris_disk:
		batches.append(_disk(rng, lod, visual))
	if visual.wind_nebula:
		batches.append_array(_wind(rng, lod, float(visual.wind_extent_radii)))
	if visual.aurora:
		batches.append(_aurora(rng, lod))
	if cached:
		if _mesh_cache.size() >= CACHE_LIMIT:
			_mesh_cache.erase(_mesh_cache.keys()[0])
		_mesh_cache[key] = batches
	return batches

static func _tool() -> SurfaceTool:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	return st

static func _tube(st: SurfaceTool, points: PackedVector3Array, width: float, alpha: float, sides: int) -> void:
	for i in range(points.size()-1):
		var tangent := (points[i+1]-points[i]).normalized()
		var right := tangent.cross(Vector3.FORWARD)
		if right.length_squared() < .001:
			right = tangent.cross(Vector3.RIGHT)
		right = right.normalized()
		var up := tangent.cross(right).normalized()
		for sector in sides:
			var a := TAU * float(sector) / sides
			var b := TAU * float(sector+1) / sides
			var ra := right*cos(a)+up*sin(a)
			var rb := right*cos(b)+up*sin(b)
			for corner in [Vector2(0,0),Vector2(1,0),Vector2(1,1),Vector2(0,0),Vector2(1,1),Vector2(0,1)]:
				var index := i + int(corner.x)
				var radial := ra if corner.y < .5 else rb
				st.set_normal(radial)
				st.set_color(Color(1,1,1,alpha))
				st.set_uv(Vector2((float(sector)+corner.y)/sides, float(index)/float(points.size()-1)))
				st.add_vertex(points[index]+radial*width)

static func _corona(rng: RandomNumberGenerator, lod: int) -> Array:
	var bright := _tool()
	var haze := _tool()
	var groups := 12 if lod == 2 else 6
	var strands := 4 if lod == 2 else 2
	var steps := 16 if lod == 2 else 8
	var sides := 4 if lod == 2 else 3
	for group in groups:
		var z := rng.randf_range(-1.0,1.0)
		var longitude := rng.randf()*TAU
		var n := Vector3(cos(longitude)*sqrt(1.0-z*z),sin(longitude)*sqrt(1.0-z*z),z)
		var tangent := n.cross(Vector3.UP).normalized()
		var side := n.cross(tangent)
		var twist := rng.randf()*TAU
		tangent = (tangent*cos(twist)+side*sin(twist)).normalized()
		side = n.cross(tangent)
		var group_width := rng.randf_range(.035,.085)
		var group_height := rng.randf_range(.07,.22)
		for strand in strands:
			var width := group_width + strand*.004 + rng.randf_range(-.006,.006)
			var height := group_height + strand*.006
			var points := PackedVector3Array()
			for step in steps+1:
				var phase := PI * float(step) / steps
				var wobble := sin(phase*7.0+strand)*.004*sin(phase)
				points.append(n*(sqrt(1.0-width*width)+height*sin(phase))+tangent*width*cos(phase)+side*((strand-1.5)*.003+wobble))
			_tube(bright,points,.0025,.35,sides)
			if strand == 0:
				_tube(haze,points,.012,.20,sides)
	for plume in groups:
		var z := rng.randf_range(-1.0,1.0)
		var angle := rng.randf()*TAU
		var n := Vector3(cos(angle)*sqrt(1.0-z*z),sin(angle)*sqrt(1.0-z*z),z)
		var tangent := n.cross(Vector3.UP).normalized()
		var points := PackedVector3Array()
		var reach := rng.randf_range(.15,.5)
		var plume_steps := 8 if lod == 2 else 6
		for step in plume_steps+1:
			var t := float(step)/plume_steps
			points.append(n*(1.01+reach*t)+tangent*t*t*.15)
		_tube(haze,points,rng.randf_range(.012,.028),.12,sides)
	return [{"mesh":bright.commit(),"kind":"filament","strength":.24,"extent":1.6},
		{"mesh":haze.commit(),"kind":"filament","strength":.35,"extent":1.6}]

static func _disk(rng: RandomNumberGenerator, lod: int, visual: Dictionary) -> Dictionary:
	var st := _tool()
	var bands := 8 if lod == 2 else 4
	var sectors := 96 if lod == 2 else 48
	for band in bands:
		for sector in sectors:
			for corner in [Vector2(0,0),Vector2(1,0),Vector2(1,1),Vector2(0,0),Vector2(1,1),Vector2(0,1)]:
				var uv := Vector2((band+corner.x)/bands,(sector+corner.y)/sectors)
				var r := lerpf(visual.disk_inner_radii,visual.disk_outer_radii,uv.x)
				st.set_uv(uv)
				st.set_normal(Vector3.UP)
				st.add_vertex(Vector3(cos(uv.y*TAU)*r,sin(uv.y*TAU*9.0)*.025*r,sin(uv.y*TAU)*r))
	# Small debris is batched into the same annular surface instead of 160 nodes.
	for rock in (48 if lod == 2 else 16):
		var angle := rng.randf()*TAU
		var r := float(visual.disk_outer_radii)*rng.randf_range(.96,1.12)
		var center := Vector3(cos(angle)*r,rng.randf_range(-.02,.02)*r,sin(angle)*r)
		var size := rng.randf_range(.002,.008)*r
		for point in [Vector3(-1,0,0),Vector3(0,1,0),Vector3(1,0,0)]:
			st.set_normal(Vector3.UP)
			st.set_uv(Vector2(.9,angle/TAU))
			st.add_vertex(center+point*size)
	return {"mesh":st.commit(),"kind":"disk","strength":1.0,"rotation":Vector3(28,0,-27),"extent":float(visual.disk_outer_radii)*1.2}

static func _cloud(st: SurfaceTool, center: Vector3, size: float, alpha: float) -> void:
	for uv in [Vector2(0,0),Vector2(1,0),Vector2(1,1),Vector2(0,0),Vector2(1,1),Vector2(0,1)]:
		st.set_uv(uv)
		st.set_color(Color(1,1,1,alpha))
		st.set_normal(Vector3.FORWARD)
		st.set_custom(0, Color(center.x,center.y,center.z,size))
		st.add_vertex(center+Vector3(uv.x-.5,uv.y-.5,0)*size)

static func _wind(_rng: RandomNumberGenerator, lod: int, extent: float) -> Array:
	var bright := _tool()
	var haze := _tool()
	var clouds := _tool()
	clouds.set_custom_format(0, SurfaceTool.CUSTOM_RGBA_FLOAT)
	var steps := 64 if lod == 2 else 32
	var sides := 4 if lod == 2 else 3
	for ring in 3:
		var points := PackedVector3Array()
		var radius := (.22+ring*.09)*extent
		for step in steps+1:
			var angle := TAU*float(step)/steps
			var r := radius*(1.0+.035*sin(angle*7.0+ring))
			points.append(Vector3(cos(angle)*r,(ring*.03-.03)*extent,sin(angle)*r))
		_tube(bright,points,(.012+ring*.004)*extent,.38,sides)
		_tube(haze,points,(.05+ring*.012)*extent,.60,sides)
		var knots := 16 if lod == 2 else 8
		for knot in knots:
			var angle := TAU*float(knot)/knots
			_cloud(clouds,Vector3(cos(angle)*radius,(ring*.03-.03)*extent,sin(angle)*radius),.22*extent,1.0)
	for side in [-1.0,1.0]:
		for strand in 2:
			var points := PackedVector3Array()
			for step in steps+1:
				var t := float(step)/steps
				var r := .004+t*.008
				var phase := t*5.0+strand*.8
				points.append(Vector3(sin(phase)*r+sin(t*5.0)*t*.05,side*(.04+t*.80),cos(phase)*r)*extent)
			_tube(bright,points,.007*extent,.5 if side > 0 else .20,sides)
			_tube(haze,points,.026*extent,.55 if side > 0 else .16,sides)
		var knots := 8 if lod == 2 else 6
		for knot in knots:
			var t := float(knot)/knots
			_cloud(clouds,Vector3(sin(t*5.0)*t*.05,side*(.04+t*.80),0)*extent,(.08+t*.06)*extent,.5 if side > 0 else .16)
	_cloud(clouds,Vector3.ZERO,1.35*extent,.35)
	var rotation := Vector3(25,0,-35)
	return [{"mesh":bright.commit(),"kind":"filament","strength":1.65,"rotation":rotation,"extent":extent,"closed":true,"jet":true},
		{"mesh":haze.commit(),"kind":"filament","strength":1.3,"rotation":rotation,"extent":extent,"closed":true,"jet":true,"tint":Color("2270d0")},
		{"mesh":clouds.commit(),"kind":"cloud","strength":1.6,"rotation":rotation,"extent":extent,"tint":Color("4895f2")}]

static func _aurora(_rng: RandomNumberGenerator, lod: int) -> Dictionary:
	var st := _tool()
	var sectors := 128 if lod == 2 else 64
	for layer in 2:
		for sector in sectors:
			for corner in [Vector2(0,0),Vector2(1,0),Vector2(1,1),Vector2(0,0),Vector2(1,1),Vector2(0,1)]:
				var uv := Vector2((sector+corner.x)/sectors,corner.y)
				var angle := uv.x*TAU
				var r := .55+layer*.01+.018*sin(angle*8.0)+.015*sin(angle*19.0)
				var reach := .06+.06*(.5+.5*sin(angle*13.0))
				st.set_uv(uv)
				st.set_normal(Vector3(cos(angle),0,sin(angle)))
				st.add_vertex(Vector3(cos(angle)*r,.835,sin(angle)*r)*(1.0+reach*uv.y))
	return {"mesh":st.commit(),"kind":"aurora","strength":.5,"extent":1.2}
