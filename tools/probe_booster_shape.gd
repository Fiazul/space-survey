extends SceneTree
# What SHAPE is each authored booster socket? A radial falloff from the socket centre
# only shapes a flat aft-facing disc; on an open cylinder wall every vertex sits at
# roughly the socket radius, so the same falloff would switch the wall off entirely.
# For each socket this reports the vertex spread along the exhaust axis (depth) against
# the spread in radial distance, which is what says which coordinate the shader can
# actually grade against. cruiser_propulsion.gdshader has no spatial term at all today.

const SHIPS := [
	{ "name": "class_ii", "path": "res://assets/class_ii_galactic_cruiser/Class II Gallactic Cruiser.obj",
	  "match": ["propulsion"], "sockets": ShipMesh.CLASS_II_BOOSTER_SOCKETS },
	{ "name": "snarkrans", "path": "res://assets/snarkrans_starship/spaceship.obj",
	  "match": ["booster_tip", "booster_bottom", "booster_upper_shell", "booster_lower_shell"],
	  "sockets": ShipMesh.SNARKRANS_BOOSTER_SOCKETS },
	{ "name": "dingo57", "path": "res://assets/dingo57_starship/3d-model.obj",
	  "match": ["booster_group_"], "sockets": ShipMesh.DINGO57_BOOSTER_SOCKETS },
]


func _init() -> void:
	for ship in SHIPS:
		_probe(ship)
	quit()


func _probe(ship: Dictionary) -> void:
	var res := load(ship.path)
	if res == null:
		print("%s: MISSING %s" % [ship.name, ship.path])
		return
	var mesh: Mesh = res if res is Mesh else null
	if mesh == null and res is PackedScene:
		var inst := (res as PackedScene).instantiate()
		for mi in ShipMesh.gather_mesh_instances(inst):
			if mi.mesh != null:
				mesh = mi.mesh
				break
		inst.free()
	if mesh == null:
		print("%s: no mesh" % ship.name)
		return

	var sockets: Array = ship.sockets
	var verts := PackedVector3Array()
	var surfaces := 0
	for si in mesh.get_surface_count():
		var tag: String = mesh.surface_get_name(si).to_lower()
		var hit := false
		for m in ship.match:
			if tag.contains(m):
				hit = true
		if not hit:
			continue
		surfaces += 1
		var arrays := mesh.surface_get_arrays(si)
		verts.append_array(arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array)

	print("\n=== %s: %d booster surfaces, %d verts, %d sockets"
		% [ship.name, surfaces, verts.size(), sockets.size()])
	for i in sockets.size():
		var socket: Dictionary = sockets[i]
		var centre: Vector3 = socket.center
		var radius := float(socket.radius)
		var near := 0
		var r_min := INF
		var r_max := -INF
		var d_min := INF
		var d_max := -INF
		for v in verts:
			if v.distance_to(centre) > radius * 2.0:
				continue
			near += 1
			var offset := v - centre
			# radial = distance from the exhaust axis; depth = along it.
			var radial := Vector2(offset.x, offset.y).length()
			r_min = minf(r_min, radial)
			r_max = maxf(r_max, radial)
			d_min = minf(d_min, offset.z)
			d_max = maxf(d_max, offset.z)
		if near == 0:
			print("  socket %d: no verts within 2x radius (%.3f)" % [i, radius])
			continue
		var radial_span := (r_max - r_min) / radius
		var depth_span := (d_max - d_min) / radius
		var kind := "FLAT DISC (grade radially)" if depth_span < 0.25 \
			else ("CYLINDER WALL (grade by depth)" if radial_span < 0.25 else "MIXED (needs both)")
		print("  socket %d r=%7.3f  verts=%4d  radial %.2f..%.2f (span %.2f r)  depth %+.2f..%+.2f (span %.2f r)  -> %s"
			% [i, radius, near, r_min / radius, r_max / radius, radial_span,
			d_min / radius, d_max / radius, depth_span, kind])
	_report_inside_fraction(ship, mesh, sockets)


# The vertex spreads above are measured in a 2x-radius WINDOW around each socket, which
# on class_ii also catches the neighbouring patches (its sockets are ~14-20 units apart
# with radii of 8.6). So the "reaches 1.8 r" figure is per-window, not per-patch, and
# cannot be turned into "x% of the glow was outside the nozzle". This integrates the
# real thing: triangle area against distance from its OWN nearest socket axis.
func _report_inside_fraction(ship: Dictionary, mesh: Mesh, sockets: Array) -> void:
	var inside := 0.0
	var outside := 0.0
	var beyond := 0.0
	for si in mesh.get_surface_count():
		var tag: String = mesh.surface_get_name(si).to_lower()
		var hit := false
		for m in ship.match:
			if tag.contains(m):
				hit = true
		if not hit:
			continue
		var arrays := mesh.surface_get_arrays(si)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] \
			if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		var tri_count: int = idx.size() / 3 if idx.size() >= 3 else verts.size() / 3
		for t in tri_count:
			var i0: int = idx[t * 3] if idx.size() >= 3 else t * 3
			var i1: int = idx[t * 3 + 1] if idx.size() >= 3 else t * 3 + 1
			var i2: int = idx[t * 3 + 2] if idx.size() >= 3 else t * 3 + 2
			var a: Vector3 = verts[i0]
			var b: Vector3 = verts[i1]
			var c: Vector3 = verts[i2]
			var centroid := (a + b + c) / 3.0
			var area := (b - a).cross(c - a).length() * 0.5
			var best := INF
			for socket in sockets:
				var offset: Vector3 = centroid - (socket.center as Vector3)
				var radial := Vector2(offset.x, offset.y).length() / float(socket.radius)
				best = minf(best, radial)
			if best <= 1.0:
				inside += area
			elif best <= 1.15:
				outside += area          # inside the border fade
			else:
				beyond += area           # fully cut by the border
	var total := inside + outside + beyond
	if total <= 0.0:
		return
	print("  by AREA: %.0f%% within 1.0 r of its own nozzle axis, %.0f%% in the 1.0-1.15 r fade, %.0f%% beyond the border"
		% [inside / total * 100.0, outside / total * 100.0, beyond / total * 100.0])
