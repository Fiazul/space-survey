class_name WedgeFighterDesign
extends RefCounted

const HULL := preload("res://shaders/wedge_hull.gdshader")
const EXHAUST := preload("res://shaders/wedge_exhaust.gdshader")
const NOZZLE := preload("res://shaders/cruiser_propulsion.gdshader")

# `tint` is the hangar swatch. It reaches the procedural hull shader as hull_tint and
# repaints the ceramic shell plus every value derived from it; the exhaust, the nozzle
# emitter, the engine nacelles and the nav lights are propulsion/accent and keep their
# authored colours. Default = the shader's own ceramic, so callers that don't paint
# (tools/render_wedge_fighter.gd) get the craft exactly as before.
static func style(model: Node3D, tint := Color(0.38, 0.48, 0.52)) -> Array[ShaderMaterial]:
	var driven: Array[ShaderMaterial] = []
	if model.has_node("InterceptorDetails"):
		return driven
	var meshes := _meshes(model)
	for mi in meshes:
		var tag := String(mi.name)
		for si in mi.mesh.get_surface_count():
			var original := mi.get_active_material(si)
			var name := original.resource_name if original != null else ""
			if tag.begins_with("Exhaust"):
				mi.set_meta("ship_bounds_exclude", true)
				var mat := ShaderMaterial.new()
				mat.shader = EXHAUST
				mi.set_surface_override_material(si, mat)
				mi.position.y = -0.02
				mi.position.z = -3.62475
				mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				driven.append(mat)
				var core := MeshInstance3D.new()
				core.name = "WhiteCore"
				core.set_meta("ship_bounds_exclude", true)
				core.mesh = mi.mesh
				core.scale = Vector3(0.52, 0.52, 0.72)
				core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				var cm := ShaderMaterial.new()
				cm.shader = EXHAUST
				cm.set_shader_parameter("core", 1.0)
				core.material_override = cm
				mi.add_child(core)
				driven.append(cm)
			elif name == "Mat_NozzleEmit":
				var mat := ShaderMaterial.new()
				mat.shader = NOZZLE
				mat.set_shader_parameter("brightness", 2.8)
				mat.set_shader_parameter("cool_color", Color(0.1, 0.4, 1.0))
				mi.set_surface_override_material(si, mat)
				driven.append(mat)
			elif tag == "Canopy":
				var glass := _metal(Color(0.025, 0.15, 0.22), 0.65, 0.11)
				glass.clearcoat_enabled = true
				glass.clearcoat = 1.0
				glass.rim_enabled = true
				glass.rim = 0.35
				mi.set_surface_override_material(si, glass)
			elif name == "Mat_Nav":
				mi.set_surface_override_material(si, _glow(Color(0.1, 0.8, 1.0) if tag == "Wing_L" else Color(1.0, 0.18, 0.08)))
			elif tag.begins_with("Engine"):
				mi.set_surface_override_material(si, _metal(Color(0.12, 0.15, 0.17), 0.85, 0.28))
			else:
				var mat := ShaderMaterial.new()
				mat.shader = HULL
				mat.set_shader_parameter("hull_tint", tint)
				mat.set_shader_parameter("design_offset", mi.position)
				mat.set_shader_parameter("wing", 1.0 if tag.begins_with("Wing") else 0.0)
				mat.set_shader_parameter("armor", 1.0 if name == "Mat_Armor" else 0.0)
				mi.set_surface_override_material(si, mat)
	_add_details(model)
	return driven

static func _meshes(node: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	if node is MeshInstance3D:
		out.append(node)
	for child in node.get_children():
		out.append_array(_meshes(child))
	return out

static func _metal(color: Color, metal: float, rough: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.metallic = metal
	mat.roughness = rough
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return mat

static func _glow(color: Color) -> StandardMaterial3D:
	var mat := _metal(color, 0.1, 0.3)
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 2.0
	return mat

static func _box(parent: Node3D, name: String, pos: Vector3, size: Vector3, material: Material) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var node := MeshInstance3D.new()
	node.name = name
	node.mesh = mesh
	node.position = pos
	node.material_override = material
	parent.add_child(node)
	return node

static func _add_details(model: Node3D) -> void:
	var rig := Node3D.new()
	rig.name = "InterceptorDetails"
	model.add_child(rig)
	var dark := _metal(Color(0.025, 0.038, 0.045), 0.7, 0.35)
	var copper := _metal(Color(0.62, 0.27, 0.105), 0.7, 0.3)
	var silver := _metal(Color(0.56, 0.65, 0.69), 0.65, 0.3)
	var cyan := _glow(Color(0.04, 0.65, 0.95))
	for side in [-1.0, 1.0]:
		# Twin dorsal cooling channels and individual inset louvers.
		_box(rig, "Intake", Vector3(side * 0.78, 0.50, -1.62), Vector3(0.42, 0.12, 1.1), dark)
		for i in 7:
			_box(rig, "CoolingVane", Vector3(side * 0.78, 0.57, -2.04 + i * 0.14), Vector3(0.34, 0.025, 0.045), silver)
		_box(rig, "IntakeLip", Vector3(side * 0.78, 0.54, -1.04), Vector3(0.46, 0.13, 0.07), silver)
		# Swept dorsal stabilizer with a fine silver leading edge.
		var fin := SurfaceTool.new()
		fin.begin(Mesh.PRIMITIVE_TRIANGLES)
		var a := Vector3(side * 1.15, 0.32, -2.65)
		var b := Vector3(side * 1.15, 0.32, -1.15)
		var c := Vector3(side * 1.35, 1.0, -2.50)
		for vertex in [a, b, c]:
			fin.add_vertex(vertex)
		fin.generate_normals()
		var node := MeshInstance3D.new()
		node.name = "SweptFin"
		node.mesh = fin.commit()
		node.material_override = dark
		rig.add_child(node)
		var rail := _box(rig, "FinEdge", (b + c) * 0.5, Vector3(0.018, 0.018, b.distance_to(c)), silver)
		rail.basis = Basis.looking_at(c - b, Vector3.UP)
		# Short paired forward weapon rails, not floating full-length barrels.
		_box(rig, "WeaponRail", Vector3(side * 1.52, 0.18, -0.55), Vector3(0.13, 0.12, 1.15), dark)
		_box(rig, "WeaponStatus", Vector3(side * 1.52, 0.25, -0.30), Vector3(0.035, 0.014, 0.26), cyan)

	# Ventral equipment is inset into the belly, with exposed cooling vanes below.
	var belly := Node3D.new()
	belly.name = "VentralDetails"
	rig.add_child(belly)
	for side in [-1.0, 1.0]:
		_box(belly, "RadiatorCassette", Vector3(side * 0.55, -0.355, -1.72), Vector3(0.38, 0.12, 1.0), dark)
		for i in 7:
			_box(belly, "RadiatorVane", Vector3(side * 0.55, -0.422, -2.11 + i * 0.13), Vector3(0.30, 0.018, 0.045), silver)
		_box(belly, "RadiatorTrim", Vector3(side * 0.755, -0.37, -1.72), Vector3(0.025, 0.10, 1.04), copper)
		_box(belly, "ApproachLight", Vector3(side * 0.55, -0.425, -1.16), Vector3(0.20, 0.018, 0.035), cyan)
		_box(belly, "LandingPad", Vector3(side * 0.55, -0.375, 0.50), Vector3(0.30, 0.075, 0.70), dark)
		_box(belly, "LandingPadInset", Vector3(side * 0.55, -0.419, 0.50), Vector3(0.22, 0.018, 0.53), silver)
	var id := Label3D.new()
	id.name = "VentralIdentification"
	id.text = "S E L E N E"
	id.font_size = 48
	id.pixel_size = 0.0025
	id.outline_size = 0
	id.modulate = Color(0.7, 0.8, 0.85)
	id.position = Vector3(0, -0.411, -0.75)
	id.rotation_degrees.x = 90
	belly.add_child(id)
