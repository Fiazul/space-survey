class_name LandingThrusters
extends Node3D
## Belly outlets (one per socket), batched into three draws. Visual pulse variation never
## changes the flight force. All plume vertices start downstream of the nozzle.
const MAX_ACCEL := .025 # km/s²; support engines, independent of developer boost
const CANT := .35
var jets: Array[Dictionary] = []
var _flames: MultiMesh
var _time := 0.0

func configure(sockets: PackedVector3Array, length: float, metal: Material, dark: Material) -> void:
	var radius := length*.035/3.0
	var shell := CylinderMesh.new()
	shell.top_radius = radius
	shell.bottom_radius = radius*.8
	shell.height = radius*1.4
	shell.radial_segments = 8
	shell.rings = 0
	var mouth := CylinderMesh.new()
	mouth.top_radius = radius*.72
	mouth.bottom_radius = radius*.72
	mouth.height = radius*.1
	mouth.radial_segments = 8
	mouth.rings = 0
	var bodies := _batch(shell,metal,sockets.size())
	var openings := _batch(mouth,dark,sockets.size())
	var shader := ShaderMaterial.new()
	shader.shader = preload("res://shaders/ship/landing_plume.gdshader")
	_flames = _batch(_plume(),shader,sockets.size(),true)
	var mid_z := 0.0
	for socket in sockets:
		mid_z += socket.z / maxf(sockets.size(), 1)
	# Cant from where each outlet actually sits, so any socket order or count works.
	for i in sockets.size():
		var side := -1.0 if sockets[i].x < 0.0 else 1.0
		var fore := -1.0 if sockets[i].z < mid_z else 1.0
		var direction := Vector3(side*CANT,-1,fore*CANT*.45).normalized()
		var right := Vector3.FORWARD.cross(direction).normalized()
		var basis := Basis(right,direction,right.cross(direction))
		bodies.set_instance_transform(i,Transform3D(basis,sockets[i]+direction*radius*.25))
		openings.set_instance_transform(i,Transform3D(basis,sockets[i]+direction*radius*.99))
		_flames.set_instance_transform(i,Transform3D(basis.scaled_local(Vector3(radius,radius*8,radius)),sockets[i]+direction*radius*1.06))
		jets.append({"position":sockets[i],"direction":direction,"power":0.0})
	command(Vector3.ZERO,0.0)

func command(local_accel: Vector3, delta: float) -> void:
	_time += delta
	for i in jets.size():
		var jet := jets[i]
		# Differential firing: right outlets push left; aft outlets push forward.
		var differential := -local_accel.x*signf(jet.direction.x)*1.6-local_accel.z*signf(jet.direction.z)*1.6
		var power := clampf((maxf(local_accel.y,0)+differential)/MAX_ACCEL,0,1)
		jet.power = power
		# Asynchronous valve flutter, only while support is actually commanded.
		var flutter := .90+.10*sin(_time*31.0+i*2.399)*sin(_time*17.0+i)
		_flames.set_instance_custom_data(i,Color(power*flutter,0,0,1))

func _batch(mesh: Mesh, material: Material, count: int, custom := false) -> MultiMesh:
	var batch := MultiMesh.new()
	batch.transform_format = MultiMesh.TRANSFORM_3D
	batch.use_custom_data = custom
	batch.mesh = mesh
	batch.instance_count = count
	var node := MultiMeshInstance3D.new()
	node.multimesh = batch
	node.material_override = material
	node.layers = 1 | ShipMesh.SHIP_FILL_LAYER
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(node)
	return batch

static func _plume() -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in 8:
		var a := TAU*i/8.0
		var b := TAU*(i+1)/8.0
		for vertex in [Vector3(cos(a)*.7,0,sin(a)*.7),Vector3(cos(b)*.7,0,sin(b)*.7),Vector3(0,1,0)]:
			surface.set_uv(Vector2(0,vertex.y))
			surface.add_vertex(vertex)
	return surface.commit()
