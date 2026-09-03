extends SceneTree
# Run: godot --headless --path . --script res://tools/probe_propulsion_area.gd
#
# Which surfaces are being painted with the additive white-hot propulsion shader, and
# how big are they? `cruiser_propulsion.gdshader` is blend_add with a near-white ALBEDO
# and an ALPHA floor, so it lays down close to solid white over whatever it covers. On a
# small nozzle face that is a hot throat. On a whole booster HOUSING it is a white slab
# that eats the hull, and no amount of tuning the energy constant fixes that - the area
# is the problem.
#
# Prints, per emissive surface: its triangle area as a percentage of the whole ship's
# surface area, and its bounding box. Anything up in the double digits is a housing that
# should be lit metal, not an emitter.

const ShipMesh := preload("res://scripts/flight/ship_mesh.gd")

const SHIPS := [
	{ "label": "class_ii", "path": "res://assets/class_ii_galactic_cruiser/Class II Gallactic Cruiser.obj", "kind": "class_ii" },
	{ "label": "snarkrans", "path": "res://assets/snarkrans_starship/spaceship.obj", "kind": "snarkrans" },
	{ "label": "dingo57", "path": "res://assets/dingo57_starship/3d-model.obj", "kind": "dingo57" },
	{ "label": "jazoone", "path": "res://assets/jazoone_spaceship/spaceship.glb", "kind": "jazoone" },
]


func _initialize() -> void:
	for ship in SHIPS:
		_probe(ship)
	quit(0)


func _surface_area(mesh: Mesh, si: int) -> float:
	var arrays: Array = mesh.surface_get_arrays(si)
	if arrays.is_empty():
		return 0.0
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null \
		else PackedInt32Array()
	var total := 0.0
	if idx.size() >= 3:
		var i := 0
		while i + 2 < idx.size():
			total += _tri(verts[idx[i]], verts[idx[i + 1]], verts[idx[i + 2]])
			i += 3
	else:
		var i := 0
		while i + 2 < verts.size():
			total += _tri(verts[i], verts[i + 1], verts[i + 2])
			i += 3
	return total


func _tri(a: Vector3, b: Vector3, c: Vector3) -> float:
	return (b - a).cross(c - a).length() * 0.5


func _probe(ship: Dictionary) -> void:
	var res := load(ship.path)
	var model: Node3D
	if res is PackedScene:
		model = (res as PackedScene).instantiate() as Node3D
	elif res is Mesh:
		var mi := MeshInstance3D.new()
		mi.mesh = res
		model = mi
	if model == null:
		print("%s: SKIP (model failed to load)" % ship.label)
		return

	match ship.kind:
		"class_ii": ShipMesh.style_class_ii_cruiser(model)
		"snarkrans": ShipMesh.style_snarkrans_starship(model)
		"dingo57": ShipMesh.style_dingo57_starship(model)
		"jazoone": ShipMesh.style_jazoone_spaceship(model)

	# Total surface area first, so each emissive patch can be reported as a share.
	var total := 0.0
	var rows := []
	for mi in ShipMesh.gather_mesh_instances(model):
		if mi.mesh == null:
			continue
		for si in mi.mesh.get_surface_count():
			var area := _surface_area(mi.mesh, si)
			total += area
			var mat := mi.get_surface_override_material(si)
			if mat is ShaderMaterial:
				var sh: Shader = (mat as ShaderMaterial).shader
				var kind := ""
				if sh == ShipMesh.CRUISER_PROPULSION_SHADER:
					kind = "propulsion(additive)"
				elif sh == ShipMesh.JAZOONE_HULL_BOOSTER_SHADER:
					kind = "jazoone_hull"
				if kind != "":
					var name_tag := "surface%d" % si
					if mi.mesh.has_method("surface_get_name"):
						var n := String(mi.mesh.surface_get_name(si))
						if n != "":
							name_tag = n
					rows.append({ "tag": name_tag, "area": area, "kind": kind })

	print("\n%s: total surface area %.1f, %d emissive surface(s)" % [ship.label, total, rows.size()])
	var emissive := 0.0
	for r in rows:
		emissive += float(r.area)
		print("   %-40s %-22s area %10.2f  = %6.2f%% of ship"
			% [r.tag, r.kind, r.area, float(r.area) / maxf(total, 0.0001) * 100.0])
	print("   -> emissive surfaces are %.2f%% of the ship's total area"
		% (emissive / maxf(total, 0.0001) * 100.0))
	model.free()
