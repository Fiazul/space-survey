class_name ShipSystems
extends Node3D
## Landing gear, gun mounts and belly support jets in fitted ship-local kilometres.
## Modular hulls hand in their named sockets and get swappable GLB modules
## (assets/modules/); the primitive fallback ship keeps the procedural recipe below.
const FALLBACK_LAYOUT := {"legs": [Vector2(0, -.31), Vector2(-.28, .24), Vector2(.28, .24)], "reach": .12, "guns": 2}
const WEAPON_SCENES := {
	"mk1": preload("res://assets/modules/weapon_mk1.glb"),
	"mk2": preload("res://assets/modules/weapon_mk2.glb"),
}
const PAD_SCENES := {
	"mk1": preload("res://assets/modules/pad_mk1.glb"),
	"mk2": preload("res://assets/modules/pad_mk2.glb"),
}
const WEAPON_SCALE := .0145 # module metres per hull km: a ~6 m cannon spans ~9% of the hull
const PAD_SCALE := .012     # module metres per hull km: a 4.6 m pad strokes ~5.5% of the hull
const PAD_CLEAR := .012     # feet always drop at least this far below the hull's lowest point
var gear_target := false
var weapons_target := false
var gear_fraction := 0.0
var weapons_fraction := 0.0
var legs: Array = []
var mounts: Array = []
var support: LandingThrusters
var hull := AABB()
var length_km := .1
var _steel: StandardMaterial3D
var _dark: StandardMaterial3D
var _paint: StandardMaterial3D
var _mark: StandardMaterial3D
var _last_pose := Vector2(-1, -1)
var modular := false
var weapon_key := "mk1"
var pad_key := "mk1"

# `sockets` maps kind ("weapon"/"pad"/"landjet") to socket transforms in this node's
# space; empty means the primitive fallback recipe.
func configure(box: AABB, tint: Color, geometry: Node3D = null, sockets := {},
		weapon_set := "mk1", pad_set := "mk1") -> void:
	hull = box
	length_km = maxf(box.size.x, maxf(box.size.y, box.size.z))
	_steel = _material(Color(.36, .40, .43), .75, .28)
	_dark = _material(Color(.07, .085, .095), .55, .7)
	_paint = _material(tint.darkened(.25), .55, .48)
	_mark = _material(Color(.82, .55, .12), .25, .55)
	if not sockets.is_empty():
		_configure_modular(sockets, tint, weapon_set, pad_set)
		pose()
		return
	var recipe: Dictionary = FALLBACK_LAYOUT
	var reach := length_km * float(recipe.reach)
	var surfaces := []
	if geometry != null:
		var inverse := geometry.global_transform.affine_inverse()
		for mi in ShipMesh.gather_mesh_instances(geometry):
			if mi.mesh != null and not mi.get_meta("ship_bounds_exclude", false):
				surfaces.append({"mesh": mi.mesh.generate_triangle_mesh(), "transform": inverse * mi.global_transform})
	for socket in recipe.legs:
		var root := Node3D.new()
		root.name = "LandingLeg%d" % legs.size()
		root.position = _socket(surfaces, Vector3(socket.x * box.size.x, box.position.y, socket.y * box.size.z))
		add_child(root)
		var door := _box(root, Vector3(length_km*.05, length_km*.006, length_km*.10), _paint)
		var upper := _cylinder(root, length_km*.013, _dark)
		var piston := _cylinder(root, length_km*.008, _steel)
		var brace := _cylinder(root, length_km*.005, _steel)
		var foot_size := Vector3(length_km*.095, length_km*.018, length_km*.13)
		var foot := _box(root, foot_size, _dark)
		var stripe := _box(foot, Vector3(foot_size.x*.95, foot_size.y*.12, foot_size.z*.18), _mark)
		stripe.position.y = foot_size.y*.51
		var side := signf(socket.x) if absf(socket.x) > .01 else 1.0
		var final := Vector3(side * reach * .28, box.position.y - reach - root.position.y, 0)
		legs.append({"root": root, "door": door, "upper": upper, "piston": piston,
			"brace": brace, "foot": foot, "size": foot_size, "final": final, "side": side})
	for i in int(recipe.guns):
		var side := -1.0 if i % 2 == 0 else 1.0
		var pair := i / 2
		var root := Node3D.new()
		root.name = "WeaponSlot%d" % i
		# Underside bay: split doors open before the cannon lowers and slides out.
		root.position = _socket(surfaces, Vector3(side * box.size.x * (.15 + pair*.10), box.position.y, -box.size.z*.40 + pair*length_km*.18))
		add_child(root)
		var doors := []
		for door_side in [-1.0, 1.0]:
			var hinge := Node3D.new()
			hinge.position = Vector3(door_side*length_km*.038, -length_km*.015, 0)
			root.add_child(hinge)
			var cover := _box(hinge, Vector3(length_km*.037, length_km*.006, length_km*.14), _paint)
			cover.position.x = -door_side*length_km*.019
			doors.append(hinge)
		var lift := _cylinder(root, length_km*.009, _steel)
		var carriage := Node3D.new()
		carriage.name = "Gimbal"
		root.add_child(carriage)
		var cannon := PlasmaMountMesh.new().build(length_km, _paint, _dark, _steel)
		carriage.add_child(cannon)
		var muzzle := Marker3D.new()
		muzzle.name = "Muzzle"
		muzzle.position = PlasmaMountMesh.MUZZLE*length_km
		carriage.add_child(muzzle)
		mounts.append({"root": root, "doors": doors, "lift": lift, "carriage": carriage, "muzzle": muzzle, "side": side,
			"emitter": cannon.mesh.surface_get_material(3), "heat": 0.0})

	# Fit every support outlet to the underside using the same hull triangles
	# as the landing legs. Keep clear of the central guns and outer leg sockets.
	var outlets := PackedVector3Array()
	for side in [-1.0,1.0]:
		for z in [-.24,-.08,.08,.24]:
			outlets.append(_socket(surfaces,Vector3(side*box.size.x*.22,box.position.y,z*box.size.z))-Vector3.UP*length_km*.016)
	support = LandingThrusters.new()
	add_child(support)
	support.configure(outlets,length_km,_steel,_dark)
	pose()

func _configure_modular(sockets: Dictionary, tint: Color, weapon_set: String, pad_set: String) -> void:
	modular = true
	weapon_key = weapon_set if WEAPON_SCENES.has(weapon_set) else "mk1"
	pad_key = pad_set if PAD_SCENES.has(pad_set) else "mk1"
	var pads: Array = sockets.get("pad", [])
	var probe := (PAD_SCENES[pad_key] as PackedScene).instantiate() as Node3D
	var foot_node := probe.get_node_or_null("FOOT") as Node3D
	var foot := foot_node.position if foot_node != null else Vector3(0, -4.6, 0)
	probe.free()
	# One shared foot plane below the whole hull, so the ship rests level and every
	# foot touches; a pad on a high wing socket is scaled up to reach it.
	var plane := hull.position.y - length_km*PAD_CLEAR
	for xf in pads:
		plane = minf(plane, (xf as Transform3D).origin.y + foot.y*length_km*PAD_SCALE)
	for xf in pads:
		var root := Node3D.new()
		root.name = "LandingPad%d" % legs.size()
		root.transform = Transform3D((xf as Transform3D).basis.orthonormalized(), xf.origin)
		add_child(root)
		var module := (PAD_SCENES[pad_key] as PackedScene).instantiate() as Node3D
		ModularHull.style(module, tint)
		var pad_scale: float = ((xf as Transform3D).origin.y - plane) / maxf(-foot.y, .001)
		module.scale = Vector3.ONE * pad_scale
		var stroke := Node3D.new()
		stroke.name = "Stroke"
		root.add_child(stroke)
		stroke.add_child(module)
		var width: float = _module_box(module).size.x * pad_scale * 1.25
		var door := _box(root, Vector3(width, length_km*.004, width), _paint)
		legs.append({"root": root, "stroke": stroke, "module": module, "door": door,
			"foot": foot, "width": width, "side": signf(xf.origin.x) if absf(xf.origin.x) > 1e-6 else 1.0})
	var weapon_scale := length_km * WEAPON_SCALE
	for xf in sockets.get("weapon", []):
		var root := Node3D.new()
		root.name = "WeaponSlot%d" % mounts.size()
		root.transform = Transform3D((xf as Transform3D).basis.orthonormalized(), xf.origin)
		add_child(root)
		var module := (WEAPON_SCENES[weapon_key] as PackedScene).instantiate() as Node3D
		ModularHull.style(module, tint)
		module.scale = Vector3.ONE * weapon_scale
		var box := _module_box(module)
		var doors := []
		for door_side in [-1.0, 1.0]:
			var hinge := Node3D.new()
			hinge.position = Vector3(door_side*box.size.x*weapon_scale*.55, 0, 0)
			root.add_child(hinge)
			var cover := _box(hinge, Vector3(box.size.x*weapon_scale*.55, length_km*.004, box.size.z*weapon_scale), _paint)
			cover.position = Vector3(-door_side*box.size.x*weapon_scale*.275, 0, box.get_center().z*weapon_scale)
			doors.append(hinge)
		var carriage := Node3D.new()
		carriage.name = "Gimbal"
		root.add_child(carriage)
		carriage.add_child(module)
		var muzzle_node := module.get_node_or_null("MUZZLE") as Node3D
		var muzzle := Marker3D.new()
		muzzle.name = "Muzzle"
		muzzle.position = module.transform * (muzzle_node.position if muzzle_node != null else Vector3(0, -.85, -4.5))
		carriage.add_child(muzzle)
		mounts.append({"root": root, "doors": doors, "lift": null, "carriage": carriage, "muzzle": muzzle,
			"side": signf(xf.origin.x), "emitter": ModularHull.emitter(module), "heat": 0.0,
			"module": module, "stow": box.size.y*weapon_scale})
	var outlets := PackedVector3Array()
	for xf in sockets.get("landjet", []):
		outlets.append((xf as Transform3D).origin - Vector3.UP*length_km*.004)
	support = LandingThrusters.new()
	add_child(support)
	support.configure(outlets, length_km, _steel, _dark)


static func _module_box(module: Node3D) -> AABB:
	var out := AABB()
	var first := true
	for mi in ShipMesh.gather_mesh_instances(module):
		if mi.mesh == null:
			continue
		var box := ModularHull.relative(mi, module) * mi.get_aabb()
		out = box if first else out.merge(box)
		first = false
	return out


func step(delta: float) -> void:
	for mount in mounts:
		if mount.heat > 0.0:
			mount.heat = maxf(0.0,mount.heat-delta/.12)
			if mount.emitter != null:
				mount.emitter.emission_energy_multiplier = 1.8+22.0*mount.heat*mount.heat
	gear_fraction = move_toward(gear_fraction, 1.0 if gear_target else 0.0, delta / 2.0)
	weapons_fraction = move_toward(weapons_fraction, 1.0 if weapons_target else 0.0, delta / 1.0)
	pose()

func discharge(slot: int) -> void:
	if mounts.is_empty():
		return
	var mount: Dictionary = mounts[posmod(slot,mounts.size())]
	mount.heat = 1.0
	if mount.emitter != null:
		mount.emitter.emission_energy_multiplier = 23.8

func pose() -> void:
	var state := Vector2(gear_fraction, weapons_fraction)
	if state == _last_pose:
		return
	_last_pose = state
	if modular:
		_pose_modular()
		return
	var g := smoothstep(.12, .94, gear_fraction)
	var door_angle := smoothstep(0.0, .25, gear_fraction) * 1.4
	for leg in legs:
		var folded := Vector3(0, length_km*.013, length_km*.065)
		var ankle: Vector3 = folded.lerp(leg.final, g)
		var knee := Vector3(float(leg.side)*length_km*.05*g, ankle.y*.5, length_km*(.05-.025*g))
		_segment(leg.upper, Vector3.ZERO, knee)
		_segment(leg.piston, knee, ankle)
		_segment(leg.brace, Vector3(0, 0, -length_km*.04), ankle*.78)
		leg.foot.position = ankle
		leg.foot.rotation.x = (1.0-g) * PI*.5
		leg.door.position = Vector3(float(leg.side)*length_km*.03*gear_fraction, -length_km*.008, 0)
		leg.door.rotation.z = float(leg.side)*door_angle
		for part in [leg.upper, leg.piston, leg.brace, leg.foot]:
			part.visible = gear_fraction > .1
	var w := smoothstep(.15, 1.0, weapons_fraction)
	for mount in mounts:
		var opening := smoothstep(0.0, .3, weapons_fraction)
		mount.doors[0].rotation.z = opening*1.15
		mount.doors[1].rotation.z = -opening*1.15
		mount.carriage.position = Vector3(0, -length_km*.075*w, -length_km*.025*w)
		mount.carriage.visible = weapons_fraction > .15
		mount.lift.visible = weapons_fraction > .15
		_segment(mount.lift, Vector3.ZERO, mount.carriage.position+Vector3.UP*length_km*.025)

func _pose_modular() -> void:
	var g := smoothstep(.12, .94, gear_fraction)
	var door_open := smoothstep(0.0, .25, gear_fraction)
	for leg in legs:
		leg.stroke.scale = Vector3(1, lerpf(.06, 1.0, g), 1)
		leg.stroke.visible = gear_fraction > .1
		leg.door.position = Vector3(float(leg.side)*float(leg.width)*.9*door_open, -length_km*.002, 0)
	var w := smoothstep(.15, 1.0, weapons_fraction)
	var opening := smoothstep(0.0, .3, weapons_fraction)
	for mount in mounts:
		mount.doors[0].rotation.z = opening*1.15
		mount.doors[1].rotation.z = -opening*1.15
		mount.carriage.position = Vector3(0, float(mount.stow)*(1.0-w), 0)
		mount.carriage.visible = weapons_fraction > .15

func foot_points() -> PackedVector3Array:
	var out := PackedVector3Array()
	if gear_fraction <= .1:
		return out
	if modular:
		for leg in legs:
			out.append(leg.root.transform * (leg.stroke.transform * (leg.module.transform * (leg.foot as Vector3))))
		return out
	for leg in legs:
		var foot: MeshInstance3D = leg.foot
		var xf: Transform3D = leg.root.transform * foot.transform
		var half: Vector3 = leg.size * .5
		for x in [-1.0, 1.0]:
			for z in [-1.0, 1.0]:
				out.append(xf * Vector3(half.x*x, -half.y, half.z*z))
	return out

func muzzle_local(slot: int = 0) -> Vector3:
	if mounts.is_empty():
		return Vector3(0, 0, hull.position.z)
	var mount: Dictionary = mounts[posmod(slot, mounts.size())]
	return mount.root.transform * (mount.carriage.transform * mount.muzzle.position)

func muzzle_node(slot: int = 0) -> Node3D:
	return mounts[posmod(slot, mounts.size())].muzzle if not mounts.is_empty() else null

func aim_mount(slot: int, local_direction: Vector3) -> void:
	if mounts.is_empty():
		return
	var mount: Dictionary = mounts[posmod(slot, mounts.size())]
	mount.carriage.basis = Basis.looking_at(mount.root.basis.inverse() * local_direction, Vector3.UP)

func weapons_ready() -> bool:
	return weapons_target and weapons_fraction >= .999 and gear_fraction < .01

static func _material(color: Color, metal: float, rough: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.metallic = metal
	material.roughness = rough
	return material

func _box(parent: Node3D, size: Vector3, material: Material) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	node.mesh = mesh
	node.material_override = material
	parent.add_child(node)
	return node

func _cylinder(parent: Node3D, radius: float, material: Material) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = 1.0
	mesh.radial_segments = 8
	mesh.rings = 0
	node.mesh = mesh
	node.material_override = material
	parent.add_child(node)
	return node

static func _segment(node: Node3D, a: Vector3, b: Vector3) -> void:
	var d := b - a
	node.position = (a+b)*.5
	var up := d.normalized() if d.length_squared() > 1e-12 else Vector3.UP
	var side := up.cross(Vector3.FORWARD).normalized()
	if side.length_squared() < .1:
		side = up.cross(Vector3.RIGHT).normalized()
	node.basis = Basis(side, up, side.cross(up)).scaled_local(Vector3(1, maxf(d.length(), .000001), 1))

# Ray against the already fitted hull, before exhaust is attached. Move a socket
# inward if the proposed plot misses a swept wing; never leave a floating leg.
func _socket(surfaces: Array, wanted: Vector3) -> Vector3:
	for attempt in 9:
		var p := wanted * Vector3(1.0-attempt*.1, 1.0, 1.0-attempt*.06)
		var from := Vector3(p.x, hull.position.y-length_km, p.z)
		var to := Vector3(p.x, hull.end.y+length_km, p.z)
		var best := INF
		for surface in surfaces:
			var xf: Transform3D = surface.transform
			var inv := xf.affine_inverse()
			var hit: Dictionary = surface.mesh.intersect_segment(inv * from, inv * to)
			if not hit.is_empty():
				var position: Vector3 = xf * hit.position
				best = minf(best, position.y)
		if best < INF:
			return Vector3(p.x, best + length_km*.015, p.z)
	return wanted + Vector3.UP*length_km*.015
