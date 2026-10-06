class_name StarFamilyReview
extends Node3D

const SIZE := Vector2i(1800, 1650)
const INK := Color("eef2f6")
const MUTED := Color("9eacbc")
const GROUPS := [
	{"title": "01  MAIN SEQUENCE", "accent": "abc8ff",
		"note": "Temperature sets the hue; hotter envelopes have quieter surfaces.",
		"samples": [
			{"name": "Hot O star", "spectral": "O5V"},
			{"name": "Sun", "spectral": "G2V"},
			{"name": "Cool K star", "spectral": "K5V"}]},
	{"title": "02  RED GIANTS", "accent": "edc392",
		"note": "Large convection cells, dark lanes and a soft limb. Low-density envelopes.",
		"samples": [
			{"name": "Warm giant", "spectral": "K3III", "stellar": {"temperature_k": 4600.0}},
			{"name": "Cool giant", "spectral": "M3III", "stellar": {"temperature_k": 3500.0}},
			{"name": "Late M giant", "spectral": "M7III", "stellar": {"temperature_k": 2800.0}}]},
	{"title": "03  WHITE DWARFS", "accent": "bcd8ff",
		"note": "Compact, smooth remnants; cooling shifts blue-white toward warm white.",
		"samples": [
			{"name": "Hot remnant", "spectral": "DA2", "stellar": {"temperature_k": 25000.0}},
			{"name": "Cooling remnant", "spectral": "DA6", "stellar": {"temperature_k": 8400.0}},
			{"name": "Old remnant", "spectral": "DA12", "stellar": {"temperature_k": 4200.0}}]},
	{"title": "04  NEUTRON STARS", "accent": "9edbff",
		"note": "Smooth crust and hot caps. Beams / magnetic field lines are schematic overlays.",
		"samples": [
			{"name": "Neutron star", "stellar_type": "neutron_star"},
			{"name": "Pulsar", "stellar_type": "pulsar"},
			{"name": "Magnetar", "stellar_type": "magnetar"}]},
	{"title": "05  RED DWARFS", "accent": "efa56c",
		"note": "Small orange photospheres; spots and magnetic activity vary by star.",
		"samples": [
			{"name": "K2-18", "spectral": "M2.5V"},
			{"name": "Proxima Centauri", "spectral": "M5.5V"},
			{"name": "TRAPPIST-1", "spectral": "M8V"}]},
	{"title": "06  BROWN DWARFS", "accent": "be7761",
		"note": "Cloud bands; mostly infrared emission. Insets are illustrative false-color views.",
		"samples": [
			{"name": "Warm L dwarf", "spectral": "L0"},
			{"name": "Luhman-like L8", "spectral": "L8"},
			{"name": "Cool T dwarf", "spectral": "T8"}]},
]

var _captures: Array[Dictionary] = []
var _records: Array[Dictionary] = []
var _compact_shader: Shader

func _ready() -> void:
	ProfileDir.isolate("star_family_review")
	get_window().mode = Window.MODE_WINDOWED
	get_window().size = SIZE
	get_window().content_scale_size = SIZE
	RenderingServer.set_default_clear_color(Color("05080c"))
	_compact_shader = _make_compact_shader()
	var layer := CanvasLayer.new()
	add_child(layer)
	var root := Control.new()
	root.size = Vector2(SIZE)
	layer.add_child(root)
	_label(root, "ASTRYX  /  STELLAR RECIPE REVIEW", Vector2(42, 25), Vector2(1716, 28), 19, Color("84a9cd"))
	_label(root, "Star families, from photospheres to remnants.", Vector2(42, 60), Vector2(1716, 55), 40, INK)
	_label(root, "PREVIEW PROPOSAL  |  Shared game renderer  |  Equal disc sizes for appearance; physical radii labeled below", Vector2(42, 124), Vector2(1716, 30), 19, MUTED)
	for i in GROUPS.size():
		_build_card(root, GROUPS[i], Vector2(42 + (i % 2) * 878, 180 + (i / 2) * 468))
	_label(root, "Surface patterns and activity are procedural estimates, not observations of these stars. All physical values here are recipe estimates.", Vector2(42, 1595), Vector2(1716, 28), 18, MUTED)
	for i in 12:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var output := OS.get_environment("STAR_FAMILY_REVIEW_DIR")
	if output.is_empty():
		output = ProjectSettings.globalize_path("res://docs/reference/star-family-review")
	DirAccess.make_dir_recursive_absolute(output)
	var failed := false
	for shot in _captures:
		var capture: Image = shot.viewport.get_texture().get_image()
		if capture.save_png(output.path_join(shot.file)) != OK:
			failed = true
		if not shot.get("sensor", false) and shot.family != "brown_dwarf":
			var center := capture.get_pixel(140, 132)
			if maxf(center.r, maxf(center.g, center.b)) < .08:
				push_error("Missing photosphere: " + shot.file)
				failed = true
	var board := get_viewport().get_texture().get_image()
	if board.save_png(output.path_join("review.png")) != OK:
		failed = true
	var manifest := FileAccess.open(output.path_join("recipes.json"), FileAccess.WRITE)
	if manifest == null:
		failed = true
	else:
		manifest.store_string(JSON.stringify({"status": "preview_only", "physical_values": "recipe estimates", "equal_angular_sizes": true, "samples": _records}, "\t"))
		manifest.close()
	print("star_family_review: %s -> %s" % ["FAIL" if failed else "OK (18 recipes, six families)", output])
	get_tree().quit(1 if failed else 0)

func _build_card(root: Control, group: Dictionary, origin: Vector2) -> void:
	var card := Panel.new()
	card.position = origin
	card.size = Vector2(854, 446)
	var style := StyleBoxFlat.new()
	style.bg_color = Color("0b1119")
	style.border_color = Color("253142")
	style.set_border_width_all(1)
	style.set_corner_radius_all(12)
	card.add_theme_stylebox_override("panel", style)
	root.add_child(card)
	_label(card, group.title, Vector2(20, 14), Vector2(815, 35), 25, Color(group.accent))
	_label(card, group.note, Vector2(20, 54), Vector2(815, 30), 17, MUTED)
	for j in group.samples.size():
		var spec: Dictionary = group.samples[j].duplicate(true)
		spec["star"] = true
		var recipe := _proposal(spec)
		var view := _viewport(card, spec, recipe, Vector2(7 + j * 280, 86), false)
		var s: Dictionary = recipe.stellar
		_captures.append({"viewport": view, "file": _slug(spec.name) + ".png", "family": s.type})
		_label(card, spec.name, Vector2(9 + j * 280, 350), Vector2(276, 27), 20, INK, true)
		_label(card, "%s K  /  %s" % [_temperature(s.temperature_k), s.spectral if int(s.mode) != 3 else s.type.replace("_", " ")], Vector2(9 + j * 280, 383), Vector2(276, 23), 17, MUTED, true)
		_label(card, "Radius  %s km" % _radius(s.radius_km), Vector2(9 + j * 280, 410), Vector2(276, 23), 16, MUTED, true)
		var record := {"name": spec.name, "spec": spec, "resolved_preview": s.duplicate(true), "image": _slug(spec.name) + ".png"}
		record.resolved_preview.cool_color = s.cool_color.to_html(false)
		record.resolved_preview.hot_color = s.hot_color.to_html(false)
		record["color_srgb"] = recipe.color_a.to_html(false)
		record["color_model"] = "CIE 1931 blackbody continuum approximation"
		if int(s.mode) == 3:
			record["preview_surface"] = "smooth crust with tilted magnetic polar caps; no gas-cloud belts"
			record["overlays"] = "schematic radiation beams" if s.type == "pulsar" else ("schematic field lines" if s.type == "magnetar" else "none")
		_records.append(record)
		if int(s.mode) == 1:
			record["sensor_inset"] = "illustrative false color; enhanced brightness and authored palette, not a computed infrared spectrum"
			var inset := _viewport(card, spec, recipe, Vector2(188 + j * 280, 269), true)
			inset.get_parent().size = Vector2(83, 74)
			_captures.append({"viewport": inset, "file": _slug(spec.name) + "-sensor.png", "family": s.type, "sensor": true})
			_label(card, "SENSOR", Vector2(187 + j * 280, 249), Vector2(85, 20), 12, Color("cdad92"), true)

func _proposal(spec: Dictionary) -> Dictionary:
	var recipe := StarRecipe.resolve(spec)
	var s: Dictionary = recipe.stellar
	# Review-local changes never enter StarRecipe or a travel destination.
	match s.type:
		"main_sequence":
			if str(s.spectral).begins_with("M"):
				s.spots = .42
				s.activity = .55
			else:
				s.activity *= .45
			s.corona_strength *= .42
		"giant":
			s.cells = 12.0
			s.spots = .06
			s.activity = .12
			s.detail_contrast = 1.0
			s.limb_floor = .35
			s.corona_strength *= .30
		"white_dwarf":
			s.limb_floor = .56
			s.brightness = 3.0
			s.corona_strength = .075
		"neutron_star", "pulsar", "magnetar":
			s.limb_floor = .48
			s.brightness = 3.2
			s.corona_strength = .075
	return recipe

func _viewport(parent: Control, spec: Dictionary, recipe: Dictionary, at: Vector2, sensor: bool) -> SubViewport:
	var container := SubViewportContainer.new()
	container.position = at
	container.size = Vector2(280, 260)
	container.stretch = true
	parent.add_child(container)
	var viewport := SubViewport.new()
	viewport.size = Vector2i(280, 260)
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	container.add_child(viewport)
	var world := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("0b1119")
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.tonemap_exposure = .7
	EnvironmentLook.apply(environment)
	world.environment = environment
	viewport.add_child(world)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 2.8
	camera.position.z = 8.0
	viewport.add_child(camera)
	camera.make_current()
	var look := PlanetGenerator.paint(spec, .83)
	var sphere: MeshInstance3D = look.sphere
	var mat: ShaderMaterial = look.mat
	var s: Dictionary = recipe.stellar
	for key in ["mode", "cells", "spots", "activity", "brightness", "limb_floor", "detail_contrast", "temperature_k", "cool_color", "hot_color"]:
		mat.set_shader_parameter("stellar_" + key, s[key])
	if int(s.mode) == 3:
		mat.shader = _compact_shader
		if s.type == "pulsar":
			_add_beams(sphere)
		elif s.type == "magnetar":
			_add_field_lines(sphere)
	var halo: ShaderMaterial = sphere.get_child(0).material_override
	halo.set_shader_parameter("activity", s.activity)
	halo.set_shader_parameter("strength", s.corona_strength)
	halo.set_shader_parameter("pulse", 0.0)
	if sensor:
		mat.set_shader_parameter("stellar_brightness", 2.2)
		mat.set_shader_parameter("color_a", Color("b88164"))
		mat.set_shader_parameter("color_b", Color("39271f"))
		halo.set_shader_parameter("strength", 0.0)
		camera.size = 2.05
	viewport.add_child(sphere)
	sphere.visible = true
	return viewport

func _make_compact_shader() -> Shader:
	var shader := Shader.new()
	var source := PlanetGenerator.COOK_SHADER.code
	var start := source.find("\t\t} else if (stellar_mode == 3) {")
	var end := source.find("\t\t} else if (stellar_mode == 4) {", start)
	assert(start >= 0 and end > start, "Compact preview shader branch not found")
	shader.code = source.substr(0, start) + """
		} else if (stellar_mode == 3) {
			vec3 magnetic_axis = normalize(vec3(.42, .82, .38));
			float cap = pow(abs(dot(n, magnetic_axis)), 28.0);
			phot = color_a * (.76 + cap * .8);
""" + source.substr(end)
	return shader

func _add_beams(sphere: MeshInstance3D) -> void:
	var shader := Shader.new()
	shader.code = """shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled;
void fragment() {
	float cross_beam = pow(max(sin(UV.x * 3.14159265), 0.0), 3.0);
	float fade = pow(1.0 - UV.y, 1.8) * smoothstep(0.0, .18, UV.y);
	ALBEDO = vec3(.35, .63, 1.0);
	ALPHA = cross_beam * fade * .40;
}"""
	var material := ShaderMaterial.new()
	material.shader = shader
	var axis := Vector3(.42, .82, .0).normalized()
	for direction in [axis, -axis]:
		var beam := MeshInstance3D.new()
		var mesh := CylinderMesh.new()
		mesh.top_radius = .22
		mesh.bottom_radius = .02
		mesh.height = .65
		beam.mesh = mesh
		beam.material_override = material
		sphere.add_child(beam)
		beam.position = direction * 1.10
		beam.quaternion = Quaternion(Vector3.UP, direction)

func _add_field_lines(sphere: MeshInstance3D) -> void:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(.42, .73, 1.0, .30)
	var axis := Vector3(.42, .82, 0.0).normalized()
	var tangent := Vector3(axis.y, -axis.x, 0.0)
	for side in [-1.0, 1.0]:
		for reach in [1.10, 1.38]:
			var mesh := ImmediateMesh.new()
			mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP, material)
			for step in 65:
				var angle := PI * float(step) / 64.0
				var r: float = reach * pow(sin(angle), 2.0)
				mesh.surface_add_vertex(axis * (r * cos(angle)) + tangent * (side * r * sin(angle)) + Vector3(0, 0, .12))
			mesh.surface_end()
			var line := MeshInstance3D.new()
			line.mesh = mesh
			sphere.add_child(line)

func _label(parent: Control, value: String, at: Vector2, extent: Vector2, font_size: int, color: Color, centered := false) -> void:
	var label := Label.new()
	label.text = value
	label.position = at
	label.size = extent
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER if centered else HORIZONTAL_ALIGNMENT_LEFT
	parent.add_child(label)

func _slug(value: String) -> String:
	return value.to_lower().replace(" ", "-")

func _temperature(value: float) -> String:
	return "%.0f" % value

func _radius(value: float) -> String:
	return "%.0f" % value
