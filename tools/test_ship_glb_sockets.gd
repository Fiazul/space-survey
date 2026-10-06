extends SceneTree
# Checks the seven rostered modular hull GLBs from tools/blender/build_ships.py against the socket/material/
# orientation contract in docs/specs/2026-09-26-ship-roster-and-modules.md.

const ROSTER := [
	["kestrel", 2, 4, 2, 3, 4], ["swift", 2, 6, 2, 4, 4],
	["harrier", 2, 6, 4, 4, 6], ["osprey", 3, 8, 4, 4, 6], ["condor", 4, 8, 6, 6, 8],
	["albatross", 4, 8, 6, 6, 8],
	["sovereign", 4, 8, 8, 6, 8],
]
const MATS := ["Hull_Paint", "Hull_Dark", "Hull_Steel", "Glass", "Accent_Emit", "Nozzle_Emit"]
const TRI_MAX := 25000

var fails := 0


func check(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
		printerr("FAIL ", msg)


func collect(n: Node, xf: Transform3D, sockets: Dictionary, meshes: Array) -> void:
	var t := xf
	if n is Node3D:
		t = xf * (n as Node3D).transform
	if n is MeshInstance3D:
		meshes.append([n, t])
	if String(n.name).begins_with("SOCKET_"):
		sockets[String(n.name)] = t
	for c in n.get_children():
		collect(c, t, sockets, meshes)


func _init() -> void:
	for row in ROSTER:
		var slug: String = row[0]
		var ps: PackedScene = load("res://assets/ships/%s/%s.glb" % [slug, slug])
		check(ps != null, "%s: glb failed to load" % slug)
		if ps == null:
			continue
		var root := ps.instantiate()
		var sockets := {}
		var meshes := []
		collect(root, Transform3D.IDENTITY, sockets, meshes)
		var counts := {"BOOSTER": row[1], "RCS": row[2], "WEAPON": row[3], "PAD": row[4]}
		for kind in counts:
			for i in counts[kind]:
				check(sockets.has("SOCKET_%s_%d" % [kind, i]), "%s: missing SOCKET_%s_%d" % [slug, kind, i])
			check(not sockets.has("SOCKET_%s_%d" % [kind, counts[kind]]), "%s: extra %s socket" % [slug, kind])
		var jets := 0
		while sockets.has("SOCKET_LANDJET_%d" % jets):
			jets += 1
		check(jets == row[5] and jets >= 4 and jets <= 8, "%s: %d landjets, want %d" % [slug, jets, row[5]])
		check(sockets.size() == row[1] + row[2] + row[3] + row[4] + row[5], "%s: stray sockets (%d)" % [slug, sockets.size()])

		var tris := 0
		var mats := {}
		var aabb := AABB()
		var first := true
		var nose := Vector3(0, 0, INF)
		for pair in meshes:
			var mesh: Mesh = pair[0].mesh
			var t: Transform3D = pair[1]
			for s in mesh.get_surface_count():
				var arr := mesh.surface_get_arrays(s)
				var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
				var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
				tris += idx.size() / 3 if idx.size() > 0 else verts.size() / 3
				var m := mesh.surface_get_material(s)
				mats[m.resource_name if m else "<none>"] = true
				for v in verts:
					var w := t * v
					if first:
						aabb = AABB(w, Vector3.ZERO)
						first = false
					else:
						aabb = aabb.expand(w)
					if w.z < nose.z:
						nose = w
		var length := aabb.size.z
		var budget := 30000 if slug == "sovereign" else TRI_MAX
		check(tris <= budget, "%s: %d tris > %d" % [slug, tris, budget])
		if slug == "sovereign":
			check(absf(length - 240.0) < 0.1, "sovereign: expected 240 m hull")
		for m in MATS:
			check(mats.has(m), "%s: material %s missing" % [slug, m])
		for m in mats:
			check(m in MATS, "%s: unexpected material %s" % [slug, m])
		check(length > aabb.size.x and length > aabb.size.y, "%s: Z is not the long axis" % slug)
		check(absf(nose.x) < 0.03 * length, "%s: -Z extreme is off-centreline (%s), nose not at -Z" % [slug, nose])
		for key in sockets:
			var k: String = key
			var st: Transform3D = sockets[k]
			var p := st.origin
			check(aabb.grow(0.01 * length).has_point(p), "%s: %s outside hull bounds" % [slug, k])
			if k.begins_with("SOCKET_BOOSTER"):
				check(p.z > aabb.end.z - 0.15 * length, "%s: %s not under aft hull (z=%.1f)" % [slug, k, p.z])
				check(st.basis.z.normalized().dot(Vector3.BACK) > 0.99, "%s: %s exhaust not +Z" % [slug, k])
				if slug == "sovereign":
					check(p.z >= aabb.end.z - 0.01, "%s: aft armor overlaps exhaust behind %s" % [slug, k])
			elif k.begins_with("SOCKET_WEAPON"):
				check(st.basis.z.normalized().dot(Vector3.BACK) > 0.99, "%s: %s not firing -Z" % [slug, k])
			elif k.begins_with("SOCKET_PAD") or k.begins_with("SOCKET_LANDJET"):
				check(st.basis.y.normalized().dot(Vector3.UP) > 0.99, "%s: %s not deploying -Y" % [slug, k])
			elif k.begins_with("SOCKET_RCS"):
				var d := st.basis.z.normalized()
				var lateral_ok := absf(d.x) < 0.5 or signf(d.x) == signf(p.x)
				check(absf(d.z) < 0.1 and lateral_ok, "%s: %s exhaust not outward" % [slug, k])
			var n := k.get_slice("_", 2).to_int()
			var twin := "SOCKET_%s_%d" % [k.get_slice("_", 1), n + 1]
			if n % 2 == 0 and sockets.has(twin):
				var q: Vector3 = sockets[twin].origin
				check(p.x < 0.0 and q.x > 0.0 and absf(p.x + q.x) < 0.01 * length, "%s: %s/%s not a mirrored -X/+X pair" % [slug, k, twin])
		print("%s: tris=%d length=%.1f nose_z=%.1f sockets=%d" % [slug, tris, length, nose.z, sockets.size()])
		root.free()
	if fails == 0:
		print("ship_glb_sockets: OK")
	else:
		print("ship_glb_sockets: FAIL (%d)" % fails)
	quit(1 if fails else 0)
