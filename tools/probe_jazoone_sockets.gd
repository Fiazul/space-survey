extends SceneTree
# Derive JazOone's booster sockets in model space.
#
# Unlike the other three ships, JazOone has no separate booster object - its engines
# exist only as emissive regions painted into spaceship_2.png. So instead of trusting
# any UV constant, this gates every vertex on the emissive mask exactly the way
# jazoone_hull_booster.gdshader does, then clusters the surviving vertices in 3D and
# reports each cluster's rear-facing centre + radius. That output is what
# ShipMesh.JAZOONE_BOOSTER_SOCKETS is built from.
#
# Run: <godot> --headless --path . --script res://tools/probe_jazoone_sockets.gd

const MODEL_PATH := "res://assets/jazoone_spaceship/spaceship.glb"
const EMISSIVE_PATH := "res://assets/jazoone_spaceship/spaceship_2.png"
const EMISSIVE_CUT := 0.25
# Two emissive vertices join the same engine if they sit within this distance.
# Model is roughly 7 x 6 x 12 units, so 0.35 separates nozzles without splitting one.
const LINK := 0.35
const MIN_CLUSTER := 25


func _initialize() -> void:
	var packed := load(MODEL_PATH) as PackedScene
	var emissive_tex := load(EMISSIVE_PATH) as Texture2D
	if packed == null or emissive_tex == null:
		print("probe: FAILED to load model or emissive mask")
		quit(1)
		return
	var model := packed.instantiate() as Node3D
	var emissive := emissive_tex.get_image()
	if emissive.is_compressed():
		emissive.decompress()
	var ew := emissive.get_width()
	var eh := emissive.get_height()

	var lit: Array[Vector3] = []
	var lit_uv: Array[Vector2] = []
	var total_verts := 0
	for mi in _gather(model):
		if mi.mesh == null:
			continue
		var xf := _relative_transform(model, mi)
		for si in mi.mesh.get_surface_count():
			var arrays: Array = mi.mesh.surface_get_arrays(si)
			if arrays.size() <= Mesh.ARRAY_TEX_UV:
				continue
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var uvs = arrays[Mesh.ARRAY_TEX_UV]
			if verts == null or uvs == null or uvs.size() != verts.size():
				continue
			total_verts += verts.size()
			for vi in verts.size():
				var uv: Vector2 = uvs[vi]
				var px := int(clampf(uv.x, 0.0, 0.9999) * float(ew))
				var py := int(clampf(uv.y, 0.0, 0.9999) * float(eh))
				var c := emissive.get_pixel(px, py)
				if maxf(c.r, maxf(c.g, c.b)) >= EMISSIVE_CUT:
					lit.append(xf * verts[vi])
					lit_uv.append(uv)

	print("probe: emissive mask %dx%d, %d verts scanned, %d above cut %.2f"
		% [ew, eh, total_verts, lit.size(), EMISSIVE_CUT])
	print("probe: model aabb pos=%s size=%s" % [_model_aabb(model).position, _model_aabb(model).size])
	if lit.is_empty():
		quit(1)
		return

	# Grid flood fill: bucket by LINK-sized cells, then merge touching cells.
	var cells := {}
	for i in lit.size():
		var key := _cell(lit[i])
		if not cells.has(key):
			cells[key] = []
		cells[key].append(i)
	var seen := {}
	var clusters: Array = []
	for key in cells.keys():
		if seen.has(key):
			continue
		var members: Array = []
		var stack: Array = [key]
		seen[key] = true
		while not stack.is_empty():
			var k: Vector3i = stack.pop_back()
			members.append_array(cells[k])
			for dx in [-1, 0, 1]:
				for dy in [-1, 0, 1]:
					for dz in [-1, 0, 1]:
						var n := Vector3i(k.x + dx, k.y + dy, k.z + dz)
						if cells.has(n) and not seen.has(n):
							seen[n] = true
							stack.append(n)
		if members.size() >= MIN_CLUSTER:
			clusters.append(members)

	clusters.sort_custom(func(a, b): return a.size() > b.size())
	print("probe: %d emissive clusters (>= %d verts)" % [clusters.size(), MIN_CLUSTER])
	for ci in clusters.size():
		var members: Array = clusters[ci]
		var centroid := Vector3.ZERO
		for i in members:
			centroid += lit[i]
		centroid /= float(members.size())
		var rear := centroid.z
		var radius := 0.0
		var uv_lo := Vector2(9.0, 9.0)
		var uv_hi := Vector2(-9.0, -9.0)
		for i in members:
			var p: Vector3 = lit[i]
			radius = maxf(radius, Vector2(p.x - centroid.x, p.y - centroid.y).length())
			rear = minf(rear, p.z)
			uv_lo = uv_lo.min(lit_uv[i])
			uv_hi = uv_hi.max(lit_uv[i])
		print("  cluster %d  n=%-5d centroid=%s radius=%.4f rear_z=%.4f uv=[%.4f,%.4f]-[%.4f,%.4f]"
			% [ci, members.size(), centroid, radius, rear, uv_lo.x, uv_lo.y, uv_hi.x, uv_hi.y])
		print("      { \"center\": Vector3(%.5f, %.5f, %.5f), \"radius\": %.5f },"
			% [centroid.x, centroid.y, rear, radius])
	quit(0)


func _cell(p: Vector3) -> Vector3i:
	return Vector3i(int(floor(p.x / LINK)), int(floor(p.y / LINK)), int(floor(p.z / LINK)))


func _gather(node: Node) -> Array:
	var out := []
	if node is MeshInstance3D:
		out.append(node)
	for c in node.get_children():
		out.append_array(_gather(c))
	return out


func _relative_transform(root: Node3D, node: Node3D) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var cur: Node = node
	while cur != null and cur != root:
		if cur is Node3D:
			xf = (cur as Node3D).transform * xf
		cur = cur.get_parent()
	return xf


func _model_aabb(root: Node3D) -> AABB:
	var out := AABB()
	var first := true
	for mi in _gather(root):
		if mi.mesh == null:
			continue
		var box: AABB = _relative_transform(root, mi) * mi.mesh.get_aabb()
		if first:
			out = box
			first = false
		else:
			out = out.merge(box)
	return out
