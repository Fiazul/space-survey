class_name PlasmaProjectiles
extends Node3D
## Kilometres throughout. Each pulse is one dense additive ray with no outer shell.
## Its swept collision remains narrow and independent of the visual length.
const RADIUS := .00015
const LENGTH := .080
const LAUNCH_LENGTH := LENGTH
const MAX_STREAK_LENGTH := .64
const EXPOSURE_TIME := 1.0/60.0
const TRACE_TIME := .045
const CORE_DIAMETER := .0008
const BASE_SPEED := 1.2 # km/s at 1x
const DEFAULT_SPEED_MULTIPLIER := 32.0
const DEFAULT_DAMAGE_MULTIPLIER := 32.0
var damage_multiplier := DEFAULT_DAMAGE_MULTIPLIER
var speed_multiplier := DEFAULT_SPEED_MULTIPLIER
const RANGE := 3.0
const MAX_SHOTS := 48
const COLOR := Color(.94, .98, 1.0)
const FLASH_TIME := .055
const IMPACT_TIME := .18
const GLOW := preload("res://shaders/plasma_glow.gdshader")
var shots: Array = []
var flashes: Array = []
var bursts: Array = []
var traces: Array = [] # visual only; resolved shots can never deal damage again
var _mesh: CapsuleMesh
var _material: ShaderMaterial
var _halo_mesh: SphereMesh
var _flash_mesh: CapsuleMesh
var _impact_mesh: SphereMesh
var _glow: ShaderMaterial
var _surface_body := ""
var _surface_basis := Basis.IDENTITY
var _surface_center := Vector3.ZERO

func _init() -> void:
	_mesh = CapsuleMesh.new()
	_mesh.radius = CORE_DIAMETER*.5
	_mesh.height = LENGTH
	_mesh.radial_segments = 6
	_mesh.rings = 1
	_material = ShaderMaterial.new()
	_material.shader = preload("res://shaders/plasma_ray.gdshader")
	_halo_mesh = SphereMesh.new()
	_halo_mesh.radius = .002
	_halo_mesh.height = .006
	_halo_mesh.radial_segments = 12
	_halo_mesh.rings = 6
	_glow = ShaderMaterial.new()
	_glow.shader = GLOW
	_glow.set_shader_parameter("energy", 12.0)
	_glow.set_shader_parameter("tint", Color(.72,.88,1,1))
	_flash_mesh = CapsuleMesh.new()
	_flash_mesh.radius = .0022
	_flash_mesh.height = .024
	_flash_mesh.radial_segments = 12
	_flash_mesh.rings = 2
	_impact_mesh = SphereMesh.new()
	_impact_mesh.radius = .007
	_impact_mesh.height = .014
	_impact_mesh.radial_segments = 12
	_impact_mesh.rings = 6

func emit(origin: Vector3, inherited_velocity: Vector3, direction: Vector3,
		damage: int, render_origin: Vector3, muzzle: Node3D = null) -> void:
	if shots.size() >= MAX_SHOTS:
		_remove(0)
	var node := MeshInstance3D.new()
	node.mesh = _mesh
	node.material_override = _material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(node)
	if is_instance_valid(muzzle):
		if flashes.size() >= 8:
			if is_instance_valid(flashes[0].node):
				flashes[0].node.queue_free()
			flashes.remove_at(0)
		var flash := _add_effect(muzzle, _flash_mesh, _glow)
		flash.rotation.x = -PI*.5
		flash.position.z = -.012
		var light := OmniLight3D.new()
		light.light_color = Color(.65, .82, 1)
		light.light_energy = 8.0
		light.omni_range = .06
		light.shadow_enabled = false
		light.light_cull_mask = ShipMesh.SHIP_FILL_LAYER
		flash.add_child(light)
		flashes.append({"node": flash, "light": light, "life": FLASH_TIME})
	var speed := muzzle_speed()
	shots.append({"pos": origin, "vel": inherited_velocity + direction * speed,
		"life": RANGE / speed, "speed": speed, "damage": maxi(1, roundi(damage*maxf(damage_multiplier,.1))),
		"node": node, "age": 0.0, "visual_direction": direction.normalized(), "visual_length": LAUNCH_LENGTH,
		"body": _surface_body})
	_pose_ray(shots.back(), render_origin, get_viewport().get_camera_3d())

func muzzle_speed() -> float:
	return BASE_SPEED * maxf(speed_multiplier, .1)

func advance(delta: float, render_origin: Vector3, targets: Array,
		sampler: TerrainSampler = null, body_center: Vector3 = Vector3.ZERO,
		body_basis: Basis = Basis.IDENTITY, body_radius: float = 0.0,
		render_velocity: Vector3 = Vector3.ZERO) -> Array:
	var impacts := []
	var camera := get_viewport().get_camera_3d()
	for i in range(traces.size()-1,-1,-1):
		var trace: Dictionary = traces[i]
		trace.life -= delta
		if trace.life <= 0.0:
			trace.node.queue_free()
			traces.remove_at(i)
		else:
			_pose_ray(trace,render_origin,camera)
			trace.node.set_instance_shader_parameter("strength", pow(trace.life/TRACE_TIME,2.0))
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
			burst.node.set_instance_shader_parameter("strength", remaining*remaining)
	for i in range(flashes.size()-1, -1, -1):
		var flash: Dictionary = flashes[i]
		flash.life -= delta
		if not is_instance_valid(flash.node):
			flashes.remove_at(i)
		elif flash.life <= 0.0:
			flash.node.queue_free()
			flashes.remove_at(i)
		else:
			var remaining: float = flash.life / FLASH_TIME
			# Abrupt white discharge, then a fast collapse; no lingering blue hose.
			flash.node.scale = Vector3(sqrt(remaining),remaining,sqrt(remaining))
			flash.node.position.z = -.012*remaining
			flash.node.set_instance_shader_parameter("strength", remaining*remaining)
			flash.light.light_energy = 8.0*remaining*remaining
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
		var elapsed := dt*first if first < INF else dt
		shot.life -= elapsed
		shot.age += elapsed
		shot.pos = start.lerp(end,first) if first < INF else end
		# Camera exposure follows relative motion: inherited ship speed must not
		# tilt the tracer sideways or turn it into a huge ray while cruising.
		var relative: Vector3 = shot.vel-render_velocity
		if relative.length_squared() > 1e-12:
			shot.visual_direction = relative.normalized()
		shot.visual_length = minf(shot.age*shot.speed,
			minf(MAX_STREAK_LENGTH,maxf(LENGTH,relative.length()*minf(delta,EXPOSURE_TIME))))
		_pose_ray(shot, render_origin, camera)
		if first < INF:
			_impact(start.lerp(end, first), render_origin,shot.body)
			if target != null:
				impacts.append({"target": target, "damage": shot.damage})
			_retire(i)
		elif shot.life <= 0.0:
			_retire(i)
	return impacts

func sync_surface_frame(body: String, center: Vector3, body_basis: Basis) -> void:
	# Atmospheric flight transports the ship with the rotating planet. Carry
	# its shots through that SAME frame before integrating muzzle-relative motion.
	# Ship steering is deliberately absent: fired shots never follow later yaw.
	if body != "" and body == _surface_body and (body_basis != _surface_basis or center != _surface_center):
		var rotation := body_basis*_surface_basis.inverse()
		for list in [shots,traces,bursts]:
			for item in list:
				if item.get("body","") != body:
					continue
				item.pos = center+rotation*(item.pos-_surface_center)
				if item.has("vel"):
					item.vel = rotation*item.vel
				if item.has("visual_direction"):
					item.visual_direction = rotation*item.visual_direction
	_surface_body = body
	_surface_center = center
	_surface_basis = body_basis

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
	_surface_center -= shift
	for shot in shots:
		shot.pos -= shift
	for burst in bursts:
		burst.pos -= shift
	for trace in traces:
		trace.pos -= shift

func clear() -> void:
	_surface_body = ""
	_surface_basis = Basis.IDENTITY
	_surface_center = Vector3.ZERO
	for trace in traces:
		trace.node.queue_free()
	traces.clear()
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

func _retire(index: int) -> void:
	# Keep the final collision-clipped segment visible for a brief exposure.
	# The physics shot is removed immediately, even when it hit within one frame.
	if traces.size() >= MAX_SHOTS:
		traces[0].node.queue_free()
		traces.remove_at(0)
	var trace: Dictionary = shots.pop_at(index)
	trace.life = TRACE_TIME
	traces.append(trace)

func _add_effect(parent: Node3D, mesh: Mesh, material: Material) -> MeshInstance3D:
	var effect := MeshInstance3D.new()
	effect.mesh = mesh
	effect.material_override = material
	effect.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(effect)
	return effect

func _pose_ray(shot: Dictionary, render_origin: Vector3, camera: Camera3D) -> void:
	var node: MeshInstance3D = shot.node
	var direction: Vector3 = shot.visual_direction
	var length: float = maxf(.00001,shot.visual_length)
	var center: Vector3 = shot.pos + direction*length*(.5 if shot.age == 0.0 else -.5)
	node.position = center-render_origin
	var up := Vector3.RIGHT if absf(direction.dot(Vector3.UP)) > .98 else Vector3.UP
	node.basis = Basis.looking_at(direction, up)*Basis(Vector3.RIGHT, -PI*.5)
	var width := 1.0
	if camera != null:
		var distance := node.global_position.distance_to(camera.global_position)
		var height := maxf(get_viewport().get_visible_rect().size.y, 1.0)
		var km_per_pixel := 2.0*distance*tan(deg_to_rad(camera.fov)*.5)/height
		# Dense, narrow exposure: screen readability without a halo or fat hitbox.
		width = clampf(2.5*km_per_pixel/CORE_DIAMETER, 1.0, 6.0)
	node.scale = Vector3(width, length/LENGTH, width)

func _impact(position: Vector3, render_origin: Vector3, body := "") -> void:
	if bursts.size() >= 16:
		bursts[0].node.queue_free()
		bursts.remove_at(0)
	var burst := _add_effect(self, _impact_mesh, _glow)
	burst.position = position - render_origin
	var core := _add_effect(burst, _halo_mesh, _material)
	core.scale = Vector3.ONE*.7
	bursts.append({"node": burst, "pos": position, "life": IMPACT_TIME, "body":body})
