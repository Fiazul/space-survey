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
#
# RAW area is no longer the number the gains come from. cruiser_propulsion.gdshader now
# grades its energy against the nozzle sockets and fades to zero before the mesh edge,
# so most of a housing surface contributes nothing. This probe therefore also reports
# the EFFECTIVE (shape-weighted) area - the same falloff the shader applies, integrated
# over the triangles - and derives each ship's booster gain from that instead. Deriving
# from raw area would over-compensate the wide-housing ships all over again, in the
# opposite direction.

const ShipMesh := preload("res://scripts/flight/ship_mesh.gd")

const SHIPS := [
	{ "label": "class_ii", "path": "res://assets/class_ii_galactic_cruiser/Class II Gallactic Cruiser.obj", "kind": "class_ii" },
	{ "label": "snarkrans", "path": "res://assets/snarkrans_starship/spaceship.obj", "kind": "snarkrans" },
	{ "label": "dingo57", "path": "res://assets/dingo57_starship/3d-model.obj", "kind": "dingo57" },
	{ "label": "jazoone", "path": "res://assets/jazoone_spaceship/spaceship.glb", "kind": "jazoone" },
]


var _tally := {}   # label -> { raw_pct, eff_pct }


func _initialize() -> void:
	for ship in SHIPS:
		_probe(ship)
	_report_gains()
	quit(0)


# The gains exist so that ships whose booster surfaces cover ten times more hull do not
# come out ten times as washed: gain = anchor * sqrt(anchor_area / own_area), on area as
# a FRACTION OF HULL so ship size cancels. class_ii stays the anchor at 4.0, which keeps
# its broad-area peak where it already measures (0.75 at full boost, under the 1.5 slab
# threshold); the shaping raises only the small core above that.
func _report_gains() -> void:
	if not _tally.has("class_ii"):
		return
	var anchor: float = float(_tally["class_ii"]["eff_pct"])
	print("\n=== derived booster gains (effective area, anchor class_ii = 4.0) ===")
	print("%-11s %9s %9s %7s   %8s %8s" % ["ship", "raw %", "eff %", "kept", "gain now", "derived"])
	var current := {
		"class_ii": ShipMesh.CLASS_II_BOOSTER_GAIN,
		"dingo57": ShipMesh.DINGO57_BOOSTER_GAIN,
		"snarkrans": ShipMesh.SNARKRANS_BOOSTER_GAIN,
		"jazoone": ShipMesh.JAZOONE_BOOSTER_GAIN,
	}
	for label in ["class_ii", "dingo57", "snarkrans", "jazoone"]:
		if not _tally.has(label):
			continue
		var raw: float = float(_tally[label]["raw_pct"])
		var eff: float = float(_tally[label]["eff_pct"])
		var derived := ShipMesh.CLASS_II_BOOSTER_GAIN * sqrt(anchor / maxf(eff, 0.0001))
		# JazOone is not in this family. Its discs run through jazoone_hull_booster,
		# whose energy ramp is mix(0.5, 4.6) against cruiser_propulsion's
		# mix(0.04, 0.26) - a gain from this column would be ~12x too hot. Its 0.40 was
		# measured against a 44%-of-frame blowout instead. Area shown, gain not derived.
		var shown := "%8.2f" % derived if label != "jazoone" else "     n/a"
		print("%-11s %8.2f%% %8.2f%% %6.0f%%   %8.2f %s"
			% [label, raw, eff, eff / maxf(raw, 0.0001) * 100.0, float(current[label]), shown])


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


# Defaults declared in cruiser_propulsion.gdshader. Read from the material when it sets
# them, so this probe cannot drift from what the shader actually does.
const SHAPE_DEFAULTS := {
	"border_start": 0.85, "border_end": 1.15, "core_boost": 1.5, "depth_dim": 0.45,
}


func _param(mat: ShaderMaterial, key: String) -> float:
	var v = mat.get_shader_parameter(key)
	return float(v) if v != null else float(SHAPE_DEFAULTS[key])


# The shader's shaping term, in GDScript. Kept deliberately literal so it can be read
# against the fragment code side by side.
func _shape_at(point: Vector3, centres: PackedVector3Array, radii: PackedFloat32Array,
		count: int, axis: Vector3, border_start: float, border_end: float,
		core_boost: float, depth_dim: float) -> float:
	if count <= 0:
		return 1.0
	var a := axis.normalized()
	var radial_n := INF
	var depth_n := 0.0
	for i in mini(count, centres.size()):
		var offset := point - centres[i]
		var r := maxf(radii[i], 0.0001)
		var along := offset.dot(a)
		var candidate := (offset - along * a).length() / r
		if candidate < radial_n:
			radial_n = candidate
			depth_n = absf(along) / r
	var rim := 1.0 - smoothstep(border_start, border_end, radial_n)
	var core := lerpf(1.0, core_boost, 1.0 - smoothstep(0.0, 0.85, radial_n))
	var depth_keep := 1.0 - depth_dim * smoothstep(0.35, 1.6, depth_n)
	return rim * core * depth_keep


# Area with each triangle weighted by the shaping term at its centroid.
func _effective_area(mesh: Mesh, si: int, mat: ShaderMaterial) -> float:
	var count := int(mat.get_shader_parameter("socket_count") 		if mat.get_shader_parameter("socket_count") != null else 0)
	if count <= 0:
		return _surface_area(mesh, si)   # unwired material: still the old flat plate
	var centres: PackedVector3Array = mat.get_shader_parameter("socket_pos")
	var radii: PackedFloat32Array = mat.get_shader_parameter("socket_r")
	var axis: Vector3 = mat.get_shader_parameter("shape_axis")
	var bs := _param(mat, "border_start")
	var be := _param(mat, "border_end")
	var cb := _param(mat, "core_boost")
	var dd := _param(mat, "depth_dim")
	var arrays: Array = mesh.surface_get_arrays(si)
	if arrays.is_empty():
		return 0.0
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null \
		else PackedInt32Array()
	var total := 0.0
	var tris := []
	if idx.size() >= 3:
		var i := 0
		while i + 2 < idx.size():
			tris.append([verts[idx[i]], verts[idx[i + 1]], verts[idx[i + 2]]])
			i += 3
	else:
		var i := 0
		while i + 2 < verts.size():
			tris.append([verts[i], verts[i + 1], verts[i + 2]])
			i += 3
	for t in tris:
		var centroid: Vector3 = (t[0] + t[1] + t[2]) / 3.0
		total += _tri(t[0], t[1], t[2]) * _shape_at(centroid, centres, radii, count, axis,
			bs, be, cb, dd)
	return total


# JazOone has no separate booster geometry: its engines are emissive regions painted
# into spaceship_2.png, and this shader keeps step(0.25, mask) as the branch. So the
# emissive area is a TEXTURE-space question, and reporting the five Layer_1 hull chunks
# as "100% of the ship emissive" (which this probe used to do) is meaningless. Integrate
# per triangle instead: gate on the mask at the centroid, then weight by the mask
# gradient and the socket shaping the shader applies there.
func _jazoone_disc_area(mesh: Mesh, si: int, mat: ShaderMaterial) -> Array:
	var arrays: Array = mesh.surface_get_arrays(si)
	if arrays.is_empty():
		return [0.0, 0.0]
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV] \
		if arrays[Mesh.ARRAY_TEX_UV] != null else PackedVector2Array()
	if uvs.size() != verts.size():
		return [0.0, 0.0]
	var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] \
		if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
	var tex := mat.get_shader_parameter("emissive_tex") as Texture2D
	if tex == null:
		return [0.0, 0.0]
	var img := tex.get_image()
	if img == null:
		return [0.0, 0.0]
	if img.is_compressed():
		img.decompress()
	var w := img.get_width()
	var h := img.get_height()
	var count := int(mat.get_shader_parameter("socket_count") \
		if mat.get_shader_parameter("socket_count") != null else 0)
	var centres: PackedVector3Array = mat.get_shader_parameter("socket_pos") \
		if count > 0 else PackedVector3Array()
	var radii: PackedFloat32Array = mat.get_shader_parameter("socket_r") \
		if count > 0 else PackedFloat32Array()
	var axis: Vector3 = mat.get_shader_parameter("shape_axis") if count > 0 else Vector3.FORWARD
	var lit := 0.0
	var effective := 0.0
	var tri_count: int = idx.size() / 3 if idx.size() >= 3 else verts.size() / 3
	for t in tri_count:
		var i0: int = idx[t * 3] if idx.size() >= 3 else t * 3
		var i1: int = idx[t * 3 + 1] if idx.size() >= 3 else t * 3 + 1
		var i2: int = idx[t * 3 + 2] if idx.size() >= 3 else t * 3 + 2
		var uv: Vector2 = (uvs[i0] + uvs[i1] + uvs[i2]) / 3.0
		var px := clampi(int(fposmod(uv.x, 1.0) * float(w)), 0, w - 1)
		var py := clampi(int(fposmod(uv.y, 1.0) * float(h)), 0, h - 1)
		var c := img.get_pixel(px, py)
		var mask: float = maxf(maxf(c.r, c.g), c.b)
		if mask < 0.25:
			continue                      # not an engine texel: the branch never runs
		var area := _tri(verts[i0], verts[i1], verts[i2])
		lit += area
		var weight := smoothstep(0.20, 0.62, mask)
		if count > 0:
			var centroid: Vector3 = (verts[i0] + verts[i1] + verts[i2]) / 3.0
			weight *= _shape_at(centroid, centres, radii, count, axis,
				_param(mat, "border_start"), _param(mat, "border_end"),
				_param(mat, "core_boost"), _param(mat, "depth_dim"))
		effective += area * weight
	return [lit, effective]


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
					var lit := area
					var eff := area
					if sh == ShipMesh.CRUISER_PROPULSION_SHADER:
						eff = _effective_area(mi.mesh, si, mat as ShaderMaterial)
					elif sh == ShipMesh.JAZOONE_HULL_BOOSTER_SHADER:
						var disc := _jazoone_disc_area(mi.mesh, si, mat as ShaderMaterial)
						lit = float(disc[0])
						eff = float(disc[1])
					rows.append({ "tag": name_tag, "area": lit, "eff": eff, "kind": kind })

	print("\n%s: total surface area %.1f, %d emissive surface(s)" % [ship.label, total, rows.size()])
	var emissive := 0.0
	var effective := 0.0
	for r in rows:
		emissive += float(r.area)
		effective += float(r.eff)
		print("   %-40s %-22s area %10.2f  = %6.2f%% of ship   effective %6.2f%% of ship"
			% [r.tag, r.kind, r.area, float(r.area) / maxf(total, 0.0001) * 100.0,
			float(r.eff) / maxf(total, 0.0001) * 100.0])
	print("   -> emissive %.2f%% of the ship's area, effective (shape-weighted) %.2f%%"
		% [emissive / maxf(total, 0.0001) * 100.0, effective / maxf(total, 0.0001) * 100.0])
	_tally[ship.label] = {
		"raw_pct": emissive / maxf(total, 0.0001) * 100.0,
		"eff_pct": effective / maxf(total, 0.0001) * 100.0,
	}
	model.free()
