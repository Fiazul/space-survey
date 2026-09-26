class_name SurfaceFacilities
extends Node3D
## Nearby facility mesh only; fixed recipe geometry shared with collision.
var _sampler: TerrainSampler
var _nodes := {}

func update_for(sampler: TerrainSampler, position_body: Vector3) -> void:
	if sampler != _sampler:
		for node in _nodes.values(): node.queue_free()
		_nodes.clear()
		_sampler = sampler
	for site in sampler.facilities:
		var nearby: bool = position_body.distance_to(site.transform.origin) < 15.0
		if not nearby:
			if _nodes.has(site.id):
				_nodes[site.id].queue_free()
				_nodes.erase(site.id)
			continue
		if not _nodes.has(site.id):
			var node := build(site)
			add_child(node)
			node.transform = site.transform
			_nodes[site.id] = node

static func build(site: Dictionary) -> Node3D:
	var root := Node3D.new()
	root.name = str(site.id)
	var pieces: Array = site.parts.duplicate(true)
	# Raised paint strips avoid z-fighting without changing the physical pad.
	for side in [-1,1]:
		pieces.append({"box":AABB(Vector3(side*.121-.002,.00015,-.12),Vector3(.004,.0001,.24)),"material":4})
		pieces.append({"box":AABB(Vector3(-.12,.00015,side*.121-.002),Vector3(.24,.0001,.004)),"material":4})
		pieces.append({"box":AABB(Vector3(side*.024-.004,.0002,-.04),Vector3(.008,.0001,.08)),"material":4})
	pieces.append({"box":AABB(Vector3(-.024,.0002,-.004),Vector3(.048,.0001,.008)),"material":4})
	for side in [-1,1]:
		pieces.append({"box":AABB(Vector3(-.715,-.0125,side*.642),Vector3(1.43,.0002,.002)),"material":3})
		pieces.append({"box":AABB(Vector3(side*.715,-.0125,-.642),Vector3(.002,.0002,1.284)),"material":3})
	for z in [-.32,-.28,-.24,-.20,-.16,.16,.20,.24,.28,.32]:
		pieces.append({"box":AABB(Vector3(-.001,-.0125,z),Vector3(.002,.0002,.02)),"material":4})
	var colors := [Color(.28,.29,.28),Color(.07,.085,.09),Color(.18,.20,.21),Color(.52,.54,.53),Color(.85,.67,.28)]
	for index in colors.size():
		var surface := SurfaceTool.new()
		surface.begin(Mesh.PRIMITIVE_TRIANGLES)
		for part in pieces:
			if part.material != index: continue
			var box := BoxMesh.new()
			box.size = part.box.size
			surface.append_from(box,0,Transform3D(Basis.IDENTITY,part.box.get_center()))
		var node := MeshInstance3D.new()
		node.mesh = surface.commit()
		var material := StandardMaterial3D.new()
		material.albedo_color = colors[index]
		material.roughness = .9
		if index == 4:
			material.emission_enabled = true
			material.emission = colors[index]
			material.emission_energy_multiplier = .45
		node.material_override = material
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(node)
	var label := Label3D.new()
	label.text = "%s\n%s  /  PAD 01" % [site.name,site.operator]
	label.position = Vector3(0,.065,-.16)
	label.font_size = 32
	label.pixel_size = .00012
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.modulate = Color(.8,.9,.95)
	root.add_child(label)
	return root
