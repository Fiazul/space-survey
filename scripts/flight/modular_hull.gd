class_name ModularHull
extends RefCounted
# Socket-driven styler for the tiered GLB hulls and their modules
# (docs/specs/2026-09-26-ship-roster-and-modules.md). Materials are mapped by name and
# sockets collected by prefix, so no hull is ever special-cased. Model-space units are
# the authored metres; everything here runs before or after fit_model, never across it.

const PREFIXES := {
	"SOCKET_WEAPON_": "weapon",
	"SOCKET_BOOSTER_": "booster",
	"SOCKET_RCS_": "rcs",
	"SOCKET_PAD_": "pad",
	"SOCKET_LANDJET_": "landjet",
}
const BOOSTER_GAIN := 2.2
const ACCENT_ENERGY := 1.8
const RCS_DECAY := 0.12


static func sockets(model: Node) -> Dictionary:
	var found := {}
	for kind in PREFIXES.values():
		found[kind] = []
	_collect(model, found)
	for kind in found:
		(found[kind] as Array).sort_custom(func(a, b): return _socket_index(a) < _socket_index(b))
	return found


static func _collect(node: Node, found: Dictionary) -> void:
	var node_name := String(node.name)
	for prefix in PREFIXES:
		if node_name.begins_with(prefix) and node is Node3D:
			found[PREFIXES[prefix]].append(node)
	for child in node.get_children():
		_collect(child, found)


static func _socket_index(node: Node) -> int:
	return int(String(node.name).get_slice("_", 2))


# `node` expressed in `ancestor`'s space, walked through local transforms so it
# works before the model is in the tree.
static func relative(node: Node, ancestor: Node) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var cursor: Node = node
	while cursor != null and cursor != ancestor:
		if cursor is Node3D:
			xf = (cursor as Node3D).transform * xf
		cursor = cursor.get_parent()
	return xf


# Longest side of the authored hull in model units, ignoring FX; works outside the tree.
static func span(model: Node3D) -> float:
	var box := AABB()
	var first := true
	for mi in ShipMesh.gather_mesh_instances(model):
		if mi.mesh == null or mi.get_meta("ship_bounds_exclude", false) or mi.mesh is PrimitiveMesh:
			continue
		var part := relative(mi, model) * mi.get_aabb()
		box = part if first else box.merge(part)
		first = false
	return box.get_longest_axis_size()


# Booster mouths in model space with a radius measured from the Nozzle_Emit bells
# closest to each socket (the GLB carries no radius, and the plume must sit in its bell).
static func booster_sockets(model: Node3D) -> Array:
	var out := []
	for node in sockets(model).booster:
		out.append({"center": relative(node, model).origin, "radius": 0.0,
			"axis": relative(node, model).basis.z.normalized()})
	if out.is_empty():
		return out
	for mi in ShipMesh.gather_mesh_instances(model):
		if mi.mesh == null or not mi.mesh is ArrayMesh:
			continue
		var to_model := relative(mi, model)
		for si in mi.mesh.get_surface_count():
			var source := mi.mesh.surface_get_material(si)
			if source == null or source.resource_name != "Nozzle_Emit":
				continue
			for vertex in mi.mesh.surface_get_arrays(si)[Mesh.ARRAY_VERTEX]:
				var p: Vector3 = to_model * vertex
				var best := 0
				for i in out.size():
					if p.distance_squared_to(out[i].center) < p.distance_squared_to(out[best].center):
						best = i
				var offset: Vector3 = p - out[best].center
				var radial: Vector3 = offset - out[best].axis * offset.dot(out[best].axis)
				out[best].radius = maxf(out[best].radius, radial.length())
	var fallback := span(model) * 0.02
	for socket in out:
		if socket.radius <= 0.0:
			socket.radius = fallback
	return out


# Restyle every surface by its authored material name. Returns the throttle-driven
# propulsion materials (Nozzle_Emit next passes).
static func style(model: Node3D, tint: Color, finish := "metallic") -> Array[ShaderMaterial]:
	var driven: Array[ShaderMaterial] = []
	var boosters := booster_sockets(model)
	for mi in ShipMesh.gather_mesh_instances(model):
		if mi.mesh == null:
			continue
		for si in mi.mesh.get_surface_count():
			var source := mi.mesh.surface_get_material(si)
			var key := source.resource_name if source != null else ""
			var material: Material
			match key:
				"Hull_Paint":
					material = _paint(source, tint, finish)
				"Glass":
					material = _glass(source)
				"Accent_Emit":
					material = _accent(source)
				"Nozzle_Emit":
					var bell := _duplicate(source)
					bell.albedo_color = Color(0.05, 0.055, 0.06)
					var drive := ShaderMaterial.new()
					drive.shader = ShipMesh.CRUISER_PROPULSION_SHADER
					drive.set_shader_parameter("plasma_color", Color.WHITE)
					drive.set_shader_parameter("brightness", ShipMesh.booster_gain(BOOSTER_GAIN))
					if not boosters.is_empty():
						ShipMesh._wire_nozzle_shape(drive, boosters,
							ShipMesh._model_to_surface_space(model, mi), Vector3(0.0, 0.0, 1.0))
					bell.next_pass = drive
					driven.append(drive)
					material = bell
				_:
					continue
			material.resource_name = key
			mi.set_surface_override_material(si, material)
	return driven


static func _duplicate(source: Material) -> StandardMaterial3D:
	if source is StandardMaterial3D:
		return (source as StandardMaterial3D).duplicate() as StandardMaterial3D
	return StandardMaterial3D.new()


static func _paint(source: Material, tint: Color, finish: String) -> StandardMaterial3D:
	var paint := _duplicate(source)
	paint.albedo_color = Color(tint.r, tint.g, tint.b, 1.0)
	paint.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
	paint.metallic_specular = 0.9
	paint.rim_enabled = true
	paint.rim_tint = 0.35
	if finish == "glassy":
		# Opaque lacquer: a see-through hull would expose the closed interior shell.
		paint.metallic = 0.05
		paint.roughness = 0.04
		paint.clearcoat_enabled = true
		paint.clearcoat = 1.0
		paint.clearcoat_roughness = 0.02
		paint.rim = 0.5
	else:
		if paint.metallic_texture == null:
			paint.metallic = 0.58
		if paint.roughness_texture == null:
			paint.roughness = 0.24
		paint.clearcoat_enabled = false
		paint.rim = 0.24
	return paint


static func _glass(source: Material) -> StandardMaterial3D:
	var glass := _duplicate(source)
	glass.metallic = 0.0
	glass.metallic_specular = 1.0
	glass.roughness = 0.03
	glass.clearcoat_enabled = true
	glass.clearcoat = 1.0
	glass.clearcoat_roughness = 0.01
	glass.rim_enabled = true
	glass.rim = 0.5
	glass.rim_tint = 0.2
	return glass


static func _accent(source: Material) -> StandardMaterial3D:
	var accent := _duplicate(source)
	accent.emission_enabled = true
	accent.emission = accent.albedo_color
	accent.emission_energy_multiplier = ACCENT_ENERGY
	return accent


static func emitter(model: Node) -> StandardMaterial3D:
	for mi in ShipMesh.gather_mesh_instances(model):
		for si in mi.get_surface_override_material_count():
			var material := mi.get_surface_override_material(si)
			if material is StandardMaterial3D and material.resource_name == "Accent_Emit":
				return material
	return null


# Two torch layers per booster socket, same proportions as the retired hand-placed
# rigs. Called after fit_model so depth fades are in world units.
static func add_plumes(model: Node3D, accent := Color(0.35, 0.70, 1.0)) -> Array[ShaderMaterial]:
	var materials: Array[ShaderMaterial] = []
	var boosters := booster_sockets(model)
	var rig := Node3D.new()
	rig.name = "ModularBoosterPlumes"
	model.add_child(rig)
	var world_scale: float = model.scale.x
	for i in boosters.size():
		var center: Vector3 = boosters[i].center
		var radius: float = boosters[i].radius
		materials.append(ShipMesh._add_torch_layer(rig, "BoosterFog%02d" % (i + 1),
			center, radius, radius * 6.0, 0.666667, 0.10, 1.20, 0.55, 0.42,
			false, 1.0, world_scale))
		materials.append(ShipMesh._add_torch_layer(rig, "BoosterCore%02d" % (i + 1),
			center, radius, radius * 3.6, 0.90, 0.05, 3.20, 0.82, 0.995,
			true, 1.0, world_scale))
	ShipMesh._attach_socket_extras(model, boosters, 1.0, world_scale, accent)
	return materials


static func add_rcs_puffs(model: Node3D) -> Array:
	var puffs := []
	var hull_span := span(model)
	var rig := Node3D.new()
	rig.name = "RcsPuffs"
	model.add_child(rig)
	for node in sockets(model).rcs:
		var xf := relative(node, model)
		var axis := xf.basis.z.normalized()
		var length := hull_span * 0.022
		var cone := CylinderMesh.new()
		cone.height = length
		cone.bottom_radius = hull_span * 0.0035
		cone.top_radius = hull_span * 0.0004
		cone.radial_segments = 10
		cone.rings = 1
		cone.cap_top = false
		cone.cap_bottom = false
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
		material.albedo_color = Color(0.75, 0.88, 1.0, 0.0)
		var puff := MeshInstance3D.new()
		puff.name = "Cone"
		puff.mesh = cone
		puff.material_override = material
		puff.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		puff.set_meta("ship_bounds_exclude", true)
		var side := axis.cross(Vector3.UP)
		if side.length_squared() < 0.01:
			side = axis.cross(Vector3.RIGHT)
		side = side.normalized()
		# Cylinder +Y is the exhaust axis; the pivot sits on the socket so the puff
		# grows out of the nozzle.
		var pivot := Node3D.new()
		pivot.name = "RcsPuff%02d" % puffs.size()
		pivot.transform = Transform3D(Basis(side, axis, side.cross(axis)), xf.origin)
		pivot.visible = false
		rig.add_child(pivot)
		puff.position = Vector3(0.0, length * 0.5, 0.0)
		pivot.add_child(puff)
		puffs.append({"node": pivot, "material": material, "axis": axis, "level": 0.0})
	return puffs


# `command` is acceleration in the visual hull's frame, including lateral braking.
# Only jets opposing that acceleration fire; input magnitude controls valve opening.
static func drive_rcs(puffs: Array, command: Vector3, braking: bool, delta: float) -> void:
	var t := Time.get_ticks_msec() * 0.001
	for i in puffs.size():
		var puff: Dictionary = puffs[i]
		var target := 0.0
		if command.length_squared() > 0.0001:
			target = clampf(-(puff.axis as Vector3).dot(command), 0.0, 1.0)
		if braking:
			target = minf(target, 0.55)
		puff.level = maxf(target, float(puff.level) - delta / RCS_DECAY)
		var node: Node3D = puff.node
		node.visible = puff.level > 0.02
		if node.visible:
			var material: StandardMaterial3D = puff.material
			var color := material.albedo_color
			color.a = float(puff.level) * (0.85 + 0.15 * sin(t * 43.0 + i * 1.7))
			material.albedo_color = color
			node.scale = Vector3(1.0, 0.4 + 0.6 * float(puff.level), 1.0)
