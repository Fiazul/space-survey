class_name StellarStructureReview
extends Node3D

const SURFACE := preload("res://tools/stellar_preview/surface.gdshader")
const FILAMENT := preload("res://tools/stellar_preview/filament.gdshader")
const HALO := preload("res://tools/stellar_preview/halo.gdshader")
const DISK := preload("res://tools/stellar_preview/disk.gdshader")
const AURORA := preload("res://tools/stellar_preview/aurora.gdshader")
const SIZE := Vector2i(2040, 1480)
const SHOTS := [
	{"id": "main-sequence", "title": "MAIN SEQUENCE / UV-INSPIRED CORONA", "note": "Coronal network, clustered plasma strands and extended streamers.", "detail": "Gold is an enhanced sensor palette; visible-light Sun supplied separately."},
	{"id": "red-giant", "title": "RED GIANT / CONVECTION", "note": "Broad convection cells, mottled lanes and a diffuse outer envelope.", "detail": "Cool giant preset; surface pattern is a procedural estimate."},
	{"id": "white-dwarf-disk", "title": "WHITE DWARF / DEBRIS DISK", "note": "Small luminous remnant inside a tilted, dusty disk with gaps and debris.", "detail": "Optional disk-bearing system variant; disks are not universal."},
	{"id": "pulsar-wind", "title": "PULSAR / WIND NEBULA", "note": "Tiny core, broken equatorial arcs and a knotty, bending particle jet.", "detail": "Vela-inspired X-ray color visualization; structure scale compressed."},
	{"id": "red-dwarf", "title": "RED DWARF / MAGNETIC ACTIVITY", "note": "Orange photosphere with active regions and bundled 3D plasma loops.", "detail": "Active M-dwarf variant; magnetic activity varies by star."},
	{"id": "brown-dwarf", "title": "BROWN DWARF / CLOUDS + AURORA", "note": "Uneven cloud belts, fine sheared streaks and a localized polar curtain.", "detail": "Aurora-bearing variant; brightness enhanced for visual review."},
]

var _rng := RandomNumberGenerator.new()
var _shots: Array[Dictionary] = []
var _manifest: Array[Dictionary] = []

func _ready() -> void:
	ProfileDir.isolate("stellar_structure_review")
	_rng.seed = 18353259
	get_window().mode = Window.MODE_WINDOWED
	get_window().size = SIZE
	get_window().content_scale_size = SIZE
	RenderingServer.set_default_clear_color(Color("05080c"))
	var layer := CanvasLayer.new()
	add_child(layer)
	var root := Control.new()
	root.size = Vector2(SIZE)
	layer.add_child(root)
	_label(root, "ASTRYX / STELLAR STRUCTURE STUDIES / PREVIEW 02", Vector2(35, 24), 21, Color("86adc8"))
	_label(root, "Corona, debris, winds and weather", Vector2(35, 63), 43, Color("edf2f6"))
	_label(root, "Reference-driven Godot renders. Proposed geometry and materials; gameplay remains unchanged.", Vector2(35, 124), 21, Color("a5b4c4"))
	for i in SHOTS.size():
		var shot: Dictionary = SHOTS[i]
		var origin := Vector2(35 + (i % 3) * 660, 177 + (i / 3) * 625)
		var panel := Panel.new()
		panel.position = origin
		panel.size = Vector2(650, 605)
		var style := StyleBoxFlat.new()
		style.bg_color = Color("091018")
		style.border_color = Color("253545")
		style.set_border_width_all(1)
		style.set_corner_radius_all(10)
		panel.add_theme_stylebox_override("panel", style)
		root.add_child(panel)
		_label(panel, shot.title, Vector2(16, 16), 21, Color("b7ccdc"))
		var viewport := _scene(str(shot.id))
		var texture := TextureRect.new()
		texture.position = Vector2(10, 58)
		texture.size = Vector2(630, 435)
		texture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		texture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		texture.texture = viewport.get_texture()
		panel.add_child(texture)
		_label(panel, shot.note, Vector2(16, 510), 17, Color("e0e7ef"), 610)
		_label(panel, shot.detail, Vector2(16, 555), 16, Color("91a4b5"), 610)
		_shots.append({"id": shot.id, "viewport": viewport})
	for extra in ["solar-visible", "white-dwarf-bare", "neutron-star-bare", "brown-dwarf-no-aurora"]:
		_shots.append({"id": extra, "viewport": _scene(extra)})
	_label(root, "UV / X-ray palettes and enhanced emission reveal structure. Disks, wind nebulae and aurorae are selectable variants, not mandatory for every star.", Vector2(35, 1438), 18, Color("a5b4c4"))
	for i in 8:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var output := ProjectSettings.globalize_path("res://docs/reference/stellar-structure-review")
	DirAccess.make_dir_recursive_absolute(output)
	var failures := 0
	for shot in _shots:
		var capture: Image = shot.viewport.get_texture().get_image()
		if capture.save_png(output.path_join(str(shot.id) + ".png")) != OK:
			failures += 1
		var peak := 0.0
		for y in range(120, 520, 8):
			for x in range(100, 860, 8):
				var pixel := capture.get_pixel(x, y)
				peak = maxf(peak, maxf(pixel.r, maxf(pixel.g, pixel.b)))
		if peak < .15:
			push_error("Missing stellar preview: " + str(shot.id))
			failures += 1
	if get_viewport().get_texture().get_image().save_png(output.path_join("review-02.png")) != OK:
		failures += 1
	var manifest := FileAccess.open(output.path_join("structures.json"), FileAccess.WRITE)
	if manifest == null:
		failures += 1
	else:
		manifest.store_string(JSON.stringify({"status": "preview_only", "presets": _manifest}, "\t"))
		manifest.close()
	print("stellar_structure_review: %s / %d captures -> %s" % ["OK" if failures == 0 else "FAIL", _shots.size(), output])
	get_tree().quit(1 if failures else 0)

func _scene(id: String) -> SubViewport:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(960, 640)
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	var world := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color.BLACK
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.tonemap_exposure = .8
	world.environment = environment
	viewport.add_child(world)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 3.35
	camera.position = Vector3(0, 0, 12)
	viewport.add_child(camera)
	camera.make_current()
	var scene := Node3D.new()
	viewport.add_child(scene)
	var structure: String = id
	var sphere: MeshInstance3D
	match id:
		"main-sequence", "solar-visible":
			var uv := id == "main-sequence"
			sphere = _star(scene, {"name": "Sun", "spectral": "G2V"}, 1.0, 0, uv)
			_corona(scene, Color("f4bb51") if uv else Color("fff0cf"), uv)
			structure = "clustered 3D plasma bundles, soft streamers and layered coronal shells"
		"red-giant":
			sphere = _star(scene, {"name": "Cool giant", "spectral": "M3III", "stellar": {"temperature_k": 3500.0}}, 1.0, 1)
			_shell(scene, 1.08, Color("df995b"), .16, 4.0)
			structure = "large convection cells and diffuse envelope"
		"red-dwarf":
			sphere = _star(scene, {"name": "Active M dwarf", "spectral": "M5.5V"}, 1.0, 0, true)
			_corona(scene, Color("ffa76d"), false)
			structure = "enhanced magnetic network and bundled plasma loops"
		"white-dwarf-disk", "white-dwarf-bare":
			camera.size = 5.6 if id == "white-dwarf-disk" else 3.35
			sphere = _star(scene, {"name": "White dwarf", "spectral": "DA3", "stellar": {"temperature_k": 18000.0}}, .12 if id == "white-dwarf-disk" else .62, 3)
			var core := .12 if id == "white-dwarf-disk" else .62
			_glow(scene, Vector3.ZERO, core * 8.0, Color("e1ebff"), 1.8)
			if id == "white-dwarf-disk":
				_debris_disk(scene)
				structure = "optional inclined dust disk, gaps, outer debris and compact luminous core"
			else:
				structure = "bare cooling remnant without disk"
		"pulsar-wind", "neutron-star-bare":
			camera.size = 6.0 if id == "pulsar-wind" else 3.35
			sphere = _star(scene, {"name": "Neutron remnant", "stellar_type": "pulsar"}, .045 if id == "pulsar-wind" else .32, 3)
			_glow(scene, Vector3.ZERO, .65 if id == "pulsar-wind" else 1.6, Color("92ceff"), 2.2)
			if id == "pulsar-wind":
				_wind(scene)
				structure = "X-ray-inspired toroidal wind arcs, diffuse emission and a bent particle jet; compressed geometry ratios"
			else:
				structure = "bare neutron remnant with compact luminous surface, no wind nebula"
		"brown-dwarf", "brown-dwarf-no-aurora":
			sphere = _star(scene, {"name": "Auroral brown dwarf", "spectral": "L4"}, 1.0, 2)
			sphere.rotation_degrees.z = -13.0
			if id == "brown-dwarf":
				_aurora(sphere)
				structure = "enhanced cloud visibility and optional red polar auroral curtain"
			else:
				structure = "uneven cloud belts and sheared streaks without aurora"
	_manifest.append({"id": id, "structure": structure, "production_changes": false})
	return viewport

func _star(parent: Node3D, spec: Dictionary, radius: float, family: int, enhanced := false) -> MeshInstance3D:
	spec["star"] = true
	var look := PlanetGenerator.paint(spec, radius)
	var sphere: MeshInstance3D = look.sphere
	sphere.get_child(0).free()
	var material := ShaderMaterial.new()
	material.shader = SURFACE
	material.set_shader_parameter("base_color", look.recipe.color_a)
	material.set_shader_parameter("hot_color", look.recipe.stellar.hot_color)
	material.set_shader_parameter("family", family)
	material.set_shader_parameter("seed", look.recipe.seed)
	material.set_shader_parameter("enhanced", enhanced)
	material.set_shader_parameter("brightness", 1.15 if family != 3 else 3.0)
	if spec.name == "Sun" and enhanced:
		material.set_shader_parameter("base_color", Color("ba890f"))
		material.set_shader_parameter("hot_color", Color("ffdc70"))
		material.set_shader_parameter("brightness", 1.25)
	if family == 2:
		material.set_shader_parameter("base_color", Color("b12712"))
		material.set_shader_parameter("hot_color", Color("f1763d"))
		material.set_shader_parameter("brightness", .85)
	sphere.material_override = material
	parent.add_child(sphere)
	sphere.visible = true
	return sphere

func _corona(parent: Node3D, tint: Color, enhanced: bool) -> void:
	_glow(parent, Vector3(0,0,-1.05), 3.3, tint, .8)
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var haze := SurfaceTool.new()
	haze.begin(Mesh.PRIMITIVE_TRIANGLES)
	var anchors: Array[Vector3] = []
	for cluster in 28:
		var longitude := _rng.randf()*TAU
		var z := _rng.randf_range(.04,.9)
		var r := sqrt(1.0-z*z)
		anchors.append(Vector3(cos(longitude)*r,sin(longitude)*r,z))
	for group in anchors.size():
		var n: Vector3 = anchors[group].normalized()
		var tangent := n.cross(Vector3.UP).normalized()
		var side := n.cross(tangent)
		var twist := _rng.randf()*TAU
		tangent = (tangent * cos(twist) + side * sin(twist)).normalized()
		side = n.cross(tangent)
		var group_width := _rng.randf_range(.035,.085)
		var group_height := _rng.randf_range(.07,.22)
		for strand in 12:
			var width := group_width + strand * .002 + _rng.randf_range(-.010,.010)
			var height := group_height + strand * .003
			var offset := (strand - 5.5) * .002
			var points := PackedVector3Array()
			for step in 49:
				var phase := PI * float(step) / 48.0
				var wobble := sin(phase * 7.0 + strand) * .004 * sin(phase)
				points.append(n * (sqrt(1.0-width*width)+height*sin(phase)) + tangent*width*cos(phase) + side*(offset+wobble))
			_tube(surface, points, .0016 + _rng.randf()*.0016, .35)
			if strand % 4 == 0:
				_tube(haze, points, .013, .50)
			if strand == 6:
				var apex := points[24]
				_glow(parent,apex,.20,tint,.32)
	for plume in 70:
		var angle := _rng.randf()*TAU
		var n := Vector3(cos(angle),sin(angle),_rng.randf_range(-.12,.12)).normalized()
		var tangent := Vector3(-n.y,n.x,0)
		var points := PackedVector3Array()
		var reach := _rng.randf_range(.15,.50)
		for step in 25:
			var t := float(step)/24.0
			points.append(n*(1.01+reach*t)+tangent*t*t*.15+Vector3(0,0,sin(t*5.0+plume)*.018))
		_tube(haze, points, _rng.randf_range(.012,.034), .20)
	_commit(parent, surface, tint, .38 if enhanced else .25)
	_commit(parent, haze, tint, .90)

func _shell(parent: Node3D, radius: float, tint: Color, strength: float, seed: float) -> void:
	var sphere := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius*2.0
	sphere.mesh = mesh
	var material := ShaderMaterial.new()
	material.shader = HALO
	material.set_shader_parameter("tint", tint)
	material.set_shader_parameter("strength", strength)
	material.set_shader_parameter("seed", seed)
	material.set_shader_parameter("billboard", false)
	material.set_shader_parameter("shell", true)
	sphere.material_override = material
	parent.add_child(sphere)

func _glow(parent: Node3D, at: Vector3, size: float, tint: Color, strength: float) -> void:
	var glow := MeshInstance3D.new()
	var mesh := QuadMesh.new()
	mesh.size = Vector2.ONE*size
	glow.mesh = mesh
	glow.position = at
	var material := ShaderMaterial.new()
	material.shader = HALO
	material.set_shader_parameter("tint", tint)
	material.set_shader_parameter("strength", strength)
	material.set_shader_parameter("seed", _rng.randf()*100.0)
	glow.material_override = material
	parent.add_child(glow)

func _debris_disk(parent: Node3D) -> void:
	var root := Node3D.new()
	root.rotation_degrees = Vector3(28,0,-27)
	parent.add_child(root)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for band in 20:
		var low := float(band)/20.0
		var high := float(band+1)/20.0
		for sector in 256:
			var a := float(sector)/256.0
			var b := float(sector+1)/256.0
			for uv in [Vector2(low,a),Vector2(high,a),Vector2(high,b),Vector2(low,a),Vector2(high,b),Vector2(low,b)]:
				var radius := lerpf(.48,3.1,uv.x)
				st.set_uv(uv)
				st.set_normal(Vector3.UP)
				st.add_vertex(Vector3(cos(uv.y*TAU)*radius, sin(uv.y*TAU*9.0)*.025*uv.x, sin(uv.y*TAU)*radius))
	var disk := MeshInstance3D.new()
	disk.mesh = st.commit()
	var material := ShaderMaterial.new()
	material.shader = DISK
	disk.material_override = material
	root.add_child(disk)
	for i in 160:
		var angle := _rng.randf()*TAU
		var r := _rng.randf_range(2.9,3.8)
		var debris := MeshInstance3D.new()
		var mesh := SphereMesh.new()
		mesh.radius = _rng.randf_range(.005,.025)
		mesh.height = mesh.radius*2.0
		mesh.radial_segments = 6
		mesh.rings = 3
		debris.mesh = mesh
		debris.position = Vector3(cos(angle)*r,_rng.randf_range(-.12,.12),sin(angle)*r)
		debris.scale = Vector3(1,_rng.randf_range(.4,1.4),_rng.randf_range(.4,1.4))
		var rock := StandardMaterial3D.new()
		rock.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		rock.albedo_color = Color(.15,.13,.12)*_rng.randf_range(.5,1.6)
		debris.material_override = rock
		root.add_child(debris)

func _wind(parent: Node3D) -> void:
	var root := Node3D.new()
	root.rotation_degrees = Vector3(25,0,-35)
	parent.add_child(root)
	var bright := SurfaceTool.new()
	bright.begin(Mesh.PRIMITIVE_TRIANGLES)
	var mist := SurfaceTool.new()
	mist.begin(Mesh.PRIMITIVE_TRIANGLES)
	for ring in 3:
		var radius := .7+ring*.29
		var points := PackedVector3Array()
		for step in 129:
			var angle := TAU*float(step)/128.0
			var r := radius*(1.0+.035*sin(angle*7.0+ring))
			points.append(Vector3(cos(angle)*r,ring*.10-.1,sin(angle)*r))
		_tube(bright,points,.036+ring*.012,.38)
		_tube(mist,points,.16+ring*.04,.60)
		for knot in 36:
			var angle := TAU*float(knot)/36.0
			_glow(root,Vector3(cos(angle)*radius,ring*.10-.1,sin(angle)*radius),.58,Color("4895f2"),1.6)
	for side in [-1.0,1.0]:
		for strand in 4:
			var points := PackedVector3Array()
			for step in 81:
				var t := float(step)/80.0
				var radius := .014+t*.025
				var phase := t*5.0+strand*.8
				points.append(Vector3(sin(phase)*radius+sin(t*5.0)*t*.18,side*(.14+t*2.6),cos(phase)*radius))
			_tube(bright,points,.022,.5 if side > 0 else .20)
			_tube(mist,points,.08,.55 if side > 0 else .16)
		for knot in 24:
			var t := float(knot)/23.0
			_glow(root,Vector3(sin(t*5.0)*t*.18,side*(.14+t*2.6),0),.22+t*.15,Color("529de9"),.8 if side > 0 else .22)
	_commit(root,bright,Color("59b5ff"),1.65,true,true)
	_commit(root,mist,Color("2270d0"),1.3,true,true)
	_glow(parent,Vector3.ZERO,3.8,Color("2463b5"),1.4)

func _aurora(parent: Node3D) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for layer in 3:
		for sector in 256:
			var a := float(sector)/256.0
			var b := float(sector+1)/256.0
			for uv in [Vector2(a,0),Vector2(b,0),Vector2(b,1),Vector2(a,0),Vector2(b,1),Vector2(a,1)]:
				var angle: float = uv.x*TAU
				var radius: float = .55+layer*.01+.018*sin(angle*8.0)+.015*sin(angle*19.0)
				var reach := .06+.06*(.5+.5*sin(angle*13.0))
				st.set_uv(uv)
				st.set_normal(Vector3(cos(angle),0,sin(angle)))
				st.add_vertex(Vector3(cos(angle)*radius,.835,sin(angle)*radius)*(1.0+reach*uv.y))
	var curtain := MeshInstance3D.new()
	curtain.mesh = st.commit()
	var material := ShaderMaterial.new()
	material.shader = AURORA
	curtain.material_override = material
	parent.add_child(curtain)
	_glow(parent,Vector3(0,.89,.35),1.25,Color("d52a07"),.7)

func _tube(st: SurfaceTool, points: PackedVector3Array, width: float, alpha: float) -> void:
	for i in range(points.size()-1):
		var tangent := (points[i+1]-points[i]).normalized()
		var right := tangent.cross(Vector3.FORWARD)
		if right.length_squared() < .001:
			right = tangent.cross(Vector3.RIGHT)
		right = right.normalized()
		var up := tangent.cross(right).normalized()
		for segment in 6:
			var a := TAU*float(segment)/6.0
			var b := TAU*float(segment+1)/6.0
			var ra := right*cos(a)+up*sin(a)
			var rb := right*cos(b)+up*sin(b)
			for corner in [Vector2(0,0),Vector2(1,0),Vector2(1,1),Vector2(0,0),Vector2(1,1),Vector2(0,1)]:
				var index := i+int(corner.x)
				var radial := ra if corner.y < .5 else rb
				st.set_normal(radial)
				st.set_color(Color(1,1,1,alpha))
				st.set_uv(Vector2((float(segment)+corner.y)/6.0,float(index)/float(points.size()-1)))
				st.add_vertex(points[index]+radial*width)

func _commit(parent: Node3D, st: SurfaceTool, tint: Color, strength: float, closed := false, jet := false) -> void:
	var mesh := MeshInstance3D.new()
	mesh.mesh = st.commit()
	var material := ShaderMaterial.new()
	material.shader = FILAMENT
	material.set_shader_parameter("tint",tint)
	material.set_shader_parameter("strength",strength)
	material.set_shader_parameter("closed",closed)
	material.set_shader_parameter("jet",jet)
	mesh.material_override = material
	parent.add_child(mesh)

func _label(parent: Control, value: String, at: Vector2, font_size: int, color: Color, width := 1970.0) -> void:
	var label := Label.new()
	label.text = value
	label.position = at
	label.size = Vector2(width,45)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size",font_size)
	label.add_theme_color_override("font_color",color)
	parent.add_child(label)
