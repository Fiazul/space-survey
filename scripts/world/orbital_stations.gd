class_name OrbitalStations
extends Node3D
## Real station positions and scaled visual references. Future berth geometry
## must explicitly qualify gear contact; proximity never grants a landing lock.
var catalogue := StationOrbits.new()
var unix_s := Time.get_unix_time_from_system()
var _nodes := {}

func state_for(id: String) -> Dictionary:
	return catalogue.state_at(id,unix_s)

func update_for(ship: Ship, delta: float) -> void:
	unix_s += maxf(0,delta)
	visible = ship.newton
	if not visible: return
	for row in catalogue.rows:
		var state: Dictionary = state_for(row.id)
		var rel := ship.rel_to(state.position)
		if rel.length() > 120.0:
			if _nodes.has(row.id): _nodes[row.id].visible = false
			continue
		if not _nodes.has(row.id):
			var holder := Node3D.new()
			add_child(holder)
			if row.id == "iss":
				var model := (load("res://assets/International Space Station.glb") as PackedScene).instantiate() as Node3D
				holder.add_child(model)
				Props._fit(holder,model,.109)
			else:
				_build_tiangong(holder)
			var label := Label3D.new()
			label.name = "Name"
			label.position.y = .08
			label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			label.font_size = 28
			holder.add_child(label)
			_nodes[row.id] = holder
		var node: Node3D = _nodes[row.id]
		node.visible = true
		node.position = rel
		var label: Label3D = node.get_node("Name")
		label.text = "%s / %s\n2026 ORBIT DATA · %s" % [row.name,"SIMULATED" if state.approximate else "DATED TRAJECTORY",Time.get_datetime_string_from_unix_time(int(unix_s))]
		label.pixel_size = clampf(rel.length()*.000025,.00005,.006)

func _build_tiangong(holder: Node3D) -> void:
	# Simplified T-shaped reference model, dimensions in kilometres; not a replica.
	var metal := StandardMaterial3D.new()
	metal.albedo_color = Color(.8,.82,.85)
	metal.roughness = .65
	var solar := StandardMaterial3D.new()
	solar.albedo_color = Color(.08,.18,.32)
	for spec in [[Vector3(0,0,0),Vector3(.0042,.0042,.0166)],
			[Vector3(-.009,0,-.006),Vector3(.018,.0042,.0042)],
			[Vector3(.009,0,-.006),Vector3(.018,.0042,.0042)],
			[Vector3(-.025,0,-.006),Vector3(.018,.0002,.006)],
			[Vector3(.025,0,-.006),Vector3(.018,.0002,.006)]]:
		var node := MeshInstance3D.new()
		node.position = spec[0]
		var size: Vector3 = spec[1]
		if size.y < .001:
			var panel := BoxMesh.new()
			panel.size = size
			node.mesh = panel
			node.material_override = solar
		else:
			var module := CylinderMesh.new()
			module.top_radius = .0021
			module.bottom_radius = .0021
			module.height = maxf(size.x,size.z)
			module.radial_segments = 16
			node.mesh = module
			node.rotation.z = PI*.5 if size.x > size.z else 0.0
			node.rotation.x = PI*.5 if size.z > size.x else 0.0
			node.material_override = metal
		holder.add_child(node)
