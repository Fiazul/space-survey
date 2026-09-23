class_name PlasmaProjectiles
extends Node3D
## Kilometres throughout. Collision stays small; the hot core/corona and short
## wake communicate the pulse's energy at the actual chase-camera distance.
const RADIUS := .00015
const LENGTH := .0035
const CORE_DIAMETER := .0012
const BASE_SPEED := 1.2 # km/s at 1x
const DEFAULT_SPEED_MULTIPLIER := 8.0
var speed_multiplier := DEFAULT_SPEED_MULTIPLIER
const RANGE := 3.0
const MAX_SHOTS := 48
const COLOR := Color(.94, .98, 1.0)
const WAKE_LENGTH := .035
const FLASH_TIME := .065
const IMPACT_TIME := .12
const GLOW := preload("res://shaders/plasma_glow.gdshader")
var shots: Array = []
var flashes: Array = []
var bursts: Array = []
var _mesh: CapsuleMesh
var _material: StandardMaterial3D
var _halo_mesh: SphereMesh
var _wake_mesh: CylinderMesh
var _flash_mesh: SphereMesh
var _glow: ShaderMaterial
var _wake_glow: ShaderMaterial

func _init() -> void:
	_mesh = CapsuleMesh.new()
	_mesh.radius = CORE_DIAMETER*.5
	_mesh.height = LENGTH
	_mesh.radial_segments = 6
	_mesh.rings = 1
	_material = StandardMaterial3D.new()
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.albedo_color = COLOR
	_material.emission_enabled = true
	_material.emission = COLOR
	_material.emission_energy_multiplier = 12.0
	_halo_mesh = SphereMesh.new()
	_halo_mesh.radius = .002
	_halo_mesh.height = .006
	_halo_mesh.radial_segments = 12
	_halo_mesh.rings = 6
	_glow = ShaderMaterial.new()
	_glow.shader = GLOW
	_glow.set_shader_parameter("energy", 6.0)
	_wake_glow = _glow.duplicate()
	_wake_glow.set_shader_parameter("axial_length", WAKE_LENGTH)
	_wake_glow.set_shader_parameter("energy", 4.0)
	_wake_mesh = CylinderMesh.new()
	_wake_mesh.top_radius = .001
	_wake_mesh.bottom_radius = .00002
	_wake_mesh.height = WAKE_LENGTH
	_wake_mesh.radial_segments = 8
	_wake_mesh.rings = 1
	_wake_mesh.cap_top = false
	_wake_mesh.cap_bottom = false
	_flash_mesh = SphereMesh.new()
	_flash_mesh.radius = .004
	_flash_mesh.height = .012
	_flash_mesh.radial_segments = 12
	_flash_mesh.rings = 6

func emit(origin: Vector3, inherited_velocity: Vector3, direction: Vector3,
		damage: int, render_origin: Vector3, muzzle: Node3D = null) -> void:
	if shots.size() >= MAX_SHOTS:
		_remove(0)
	var node := MeshInstance3D.new()
	node.mesh = _mesh
	node.material_override = _material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(node)
	node.position = origin - render_origin
	var up := Vector3.RIGHT if absf(direction.dot(Vector3.UP)) > .98 else Vector3.UP
	node.basis = Basis.looking_at(direction, up) * Basis(Vector3.RIGHT, -PI*.5)
	_scale_for_view(node, get_viewport().get_camera_3d())
	var corona := _add_effect(node, _halo_mesh, _glow)
	corona.scale = Vector3(.7, 1.0, .7)
	var wake := _add_effect(node, _wake_mesh, _wake_glow)
	wake.visible = false
	if is_instance_valid(muzzle):
		var flash := _add_effect(muzzle, _flash_mesh, _glow)
		flash.rotation.x = -PI*.5
		flash.position.z = -.004
		var light := OmniLight3D.new()
		light.light_color = Color(.45, .7, 1)
		light.light_energy = 2.5
		light.omni_range = .035
		light.shadow_enabled = false
		light.light_cull_mask = ShipMesh.SHIP_FILL_LAYER
		flash.add_child(light)
		flashes.append({"node": flash, "life": FLASH_TIME})
	var speed := muzzle_speed()
	shots.append({"pos": origin, "vel": inherited_velocity + direction * speed,
		"life": RANGE / speed, "speed": speed, "damage": damage, "node": node, "wake": wake, "age": 0.0})

func muzzle_speed() -> float:
	return BASE_SPEED * maxf(speed_multiplier, .1)

func advance(delta: float, render_origin: Vector3, targets: Array,
		sampler: TerrainSampler = null, body_center: Vector3 = Vector3.ZERO,
		body_basis: Basis = Basis.IDENTITY, body_radius: float = 0.0) -> Array:
	var impacts := []
	var camera := get_viewport().get_camera_3d()
	for i in range(bursts.size()-1, -1, -1):
		var burst: Dictionary = bursts[i]
		burst.life -= delta
		if burst.life <= 0:
			burst.node.queue_free()
			bursts.remove_at(i)
		else:
			burst.node.position = burst.pos - render_origin
			var remaining: float = burst.life / IMPACT_TIME
			burst.node.scale = Vector3.ONE * lerpf(3.0, 1.0, remaining) * sqrt(remaining)
	for i in range(flashes.size()-1, -1, -1):
		var flash: Dictionary = flashes[i]
		flash.life -= delta
		if not is_instance_valid(flash.node):
			flashes.remove_at(i)
		elif flash.life <= 0.0:
			flash.node.queue_free()
			flashes.remove_at(i)
		else:
			flash.node.scale = Vector3.ONE * sqrt(flash.life / FLASH_TIME)
	for i in range(shots.size()-1, -1, -1):
		var shot: Dictionary = shots[i]
		var start: Vector3 = shot.pos
		var dt := minf(delta, shot.life)
		var end: Vector3 = start + shot.vel * dt
		var first := INF
		var target: Variant = null
		if sampler != null and body_radius > 0.0:
			var inv := body_basis.inverse()
			var contact := sampler.resolve_motion(inv*(start-body_center), inv*(end-body_center), inv*shot.vel, body_radius, RADIUS)
			if contact.hit or contact.budget_limited:
				var point: Vector3 = body_center + body_basis * contact.position
				first = clampf((point-start).dot(end-start) / maxf((end-start).length_squared(), 1e-12), 0.0, 1.0)
		for candidate in targets:
			if not candidate.alive:
				continue
			var t := sphere_entry(start, end, candidate.pos, float(candidate.size)*.5 + RADIUS)
			if t < first:
				first = t
				target = candidate
		shot.life -= dt
		shot.age += dt
		shot.pos = end
		shot.node.position = end - render_origin
		_scale_for_view(shot.node, camera)
		# A short attached wake ends behind each pulse; never tether it to the gun.
		var wake_scale := minf(shot.age*shot.speed / WAKE_LENGTH, 1.0)
		shot.wake.visible = wake_scale > .001
		shot.wake.scale.y = maxf(wake_scale, .001)
		shot.wake.position.y = -WAKE_LENGTH*.5*wake_scale
		if first < INF:
			_impact(start.lerp(end, first), render_origin)
			if target != null:
				impacts.append({"target": target, "damage": shot.damage})
			_remove(i)
		elif shot.life <= 0.0:
			_remove(i)
	return impacts

static func sphere_entry(start: Vector3, end: Vector3, center: Vector3, radius: float) -> float:
	var offset := start-center
	var d := end-start
	var c := offset.length_squared()-radius*radius
	if c <= 0:
		return 0.0
	var a := d.length_squared()
	if a < 1e-12:
		return INF
	var b := offset.dot(d)
	var disc := b*b-a*c
	if disc < 0:
		return INF
	var t := (-b-sqrt(disc))/a
	return t if t >= 0.0 and t <= 1.0 else INF

func shift_frame(shift: Vector3) -> void:
	for shot in shots:
		shot.pos -= shift
	for burst in bursts:
		burst.pos -= shift

func clear() -> void:
	for burst in bursts:
		burst.node.queue_free()
	bursts.clear()
	for flash in flashes:
		if is_instance_valid(flash.node):
			flash.node.queue_free()
	flashes.clear()
	for i in range(shots.size()-1, -1, -1):
		_remove(i)

func _remove(index: int) -> void:
	shots[index].node.queue_free()
	shots.remove_at(index)

func _add_effect(parent: Node3D, mesh: Mesh, material: Material) -> MeshInstance3D:
	var effect := MeshInstance3D.new()
	effect.mesh = mesh
	effect.material_override = material
	effect.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(effect)
	return effect

func _scale_for_view(node: Node3D, camera: Camera3D) -> void:
	if camera == null:
		return
	# The core should cover ~3 pixels from the chase camera instead of aliasing
	# into a dribble of disappearing subpixel dots. Cap at 7.2 m visual diameter;
	# this scales only the light effect, never the 30 cm collision diameter.
	var distance := node.global_position.distance_to(camera.global_position)
	var height := maxf(get_viewport().get_visible_rect().size.y, 1.0)
	var km_per_pixel := 2.0*distance*tan(deg_to_rad(camera.fov)*.5)/height
	node.scale = Vector3.ONE * clampf(3.0*km_per_pixel / CORE_DIAMETER, 1.0, 6.0)

func _impact(position: Vector3, render_origin: Vector3) -> void:
	if bursts.size() >= 16:
		bursts[0].node.queue_free()
		bursts.remove_at(0)
	var burst := _add_effect(self, _flash_mesh, _glow)
	burst.position = position - render_origin
	var core := _add_effect(burst, _halo_mesh, _material)
	core.scale = Vector3.ONE*.7
	bursts.append({"node": burst, "pos": position, "life": IMPACT_TIME})
