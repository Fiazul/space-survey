class_name Props
extends Node3D
# Hand-placed GLB landmarks (the dockable station, Finn the astronaut), anchored like the
# ship (docs/adr/0002): each sits at an offset `off` from a body and renders at
# ship.to_body(body) + off, so the 64-bit subtraction never lands in a Vector3.
#
# The station parks beside every system's spawn (20 km off the spawn park, 2 radii out
# in generated systems, sunlit GEO at Earth); Finn stays in Sol. system = "*" shows a
# prop in every system. Decorative points-of-interest — no collision; auto-fitted to a
# target size, self-lit, slowly spun.
const PROP_LIST := [
	# --- the station (dockable, every system) + Finn, drifting nearby in Sol ---
	{
		"name": "", "path": "res://assets/Wikiplanet Space Station (WSS).glb",
		"system": "*",
		"size": 4.0, "yaw": 25.0, "spin": 0.03, "glow": 0.18,
		"dock": true, "dock_range": 90.0,
	},
	{
		"name": "Finn", "path": "res://assets/Astronaut.glb",
		"system": "sol",
		"size": 0.3, "yaw": 200.0, "spin": 0.35, "glow": 0.45,
	},
]

var _items := []
var current_system := "sol"

# Dock target (the prop flagged "dock") for the current system, read by main.
var has_dock := false
var dock_name := ""
var dock_range := 0.0
var _dock: Dictionary = {}


func _ready() -> void:
	for p in PROP_LIST:
		var packed := load(p.path) as PackedScene
		if packed == null:
			push_warning("Props: couldn't load %s (imported yet?)" % p.path)
			continue
		var holder := Node3D.new()
		add_child(holder)
		var model := packed.instantiate() as Node3D
		holder.add_child(model)
		model.rotation = Vector3(0.0, deg_to_rad(p.yaw), 0.0)
		_fit(holder, model, p.size)
		_self_light(model, p.glow)

		# Floating name label (billboard), positioned each frame in update().
		var label: Label3D = null
		if p.has("name"):
			label = Label3D.new()
			label.text = p.name
			label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			label.outline_modulate = Color(0, 0, 0, 0.7)
			label.outline_size = 8
			label.font_size = 40
			label.no_depth_test = true
			add_child(label)

		_items.append({
			"holder": holder,
			"label": label,
			"name": p.get("name", ""),
			"system": p.get("system", "sol"),
			"body": "",
			"off": Vector3.ZERO,
			"up": float(p.size) * 0.7,      # label height above the prop
			"spin": float(p.get("spin", 0.0)),
			"cull": float(p.size) * 90.0,   # stop drawing big meshy props when far
			"is_dock": bool(p.get("dock", false)),
			"dock_range": float(p.get("dock_range", float(p.size) * 1.8)),
		})

	set_system(current_system)


func set_system(id: String) -> void:
	current_system = id
	_park_at_spawn()
	has_dock = false
	dock_name = ""
	_dock = {}
	for it in _items:
		var here := _in_system(it)
		it.holder.visible = here
		if it.label != null:
			it.label.visible = here
		if here and it.is_dock:
			has_dock = true
			dock_name = it.name
			dock_range = it.dock_range
			_dock = it


func _in_system(it: Dictionary) -> bool:
	return it.system == "*" or it.system == current_system


func _park_at_spawn() -> void:
	var body: String = Ephemeris.spawn_body()
	var park: Vector3 = Ephemeris.spawn_pos()
	var side := park.cross(Vector3.UP)
	if side.length_squared() < 0.0001:
		side = park.cross(Vector3.RIGHT)
	side = side.normalized()
	for it in _items:
		it.body = body
		if it.is_dock:
			it.off = park + side * 20.0
		elif str(it.name) == "Finn":
			it.off = park + side * 16.0 + Vector3(0.0, 2.0, 0.0)


# Render-space vector from the ship to the dock ("" dock → INF).
func dock_rel(flyer: Ship) -> Vector3:
	if _dock.is_empty():
		return Vector3.INF
	return flyer.to_body(_dock.body) + _dock.off


func update(flyer: Ship, delta: float) -> void:
	for it in _items:
		if not _in_system(it):
			continue
		var rel: Vector3 = flyer.to_body(it.body) + it.off
		it.holder.position = rel
		var dist := rel.length()
		var vis: bool = dist < it.cull
		it.holder.visible = vis
		if vis and it.spin != 0.0:
			it.holder.rotate_y(it.spin * delta)
		if it.label != null:
			it.label.visible = vis
			if vis:
				it.label.position = rel + Vector3(0.0, it.up, 0.0)
				# Keep the name roughly readable regardless of distance.
				it.label.pixel_size = clampf(dist * 0.00012, 0.02, 1.2)


static func _fit(holder: Node3D, model: Node3D, target_len: float) -> void:
	var box := _combined_aabb(holder)
	var size := box.size
	var longest := maxf(size.x, maxf(size.y, size.z))
	if longest <= 0.0001:
		return
	var factor := target_len / longest
	model.scale = model.scale * factor
	var center := box.position + size * 0.5
	model.position -= center * factor


static func _combined_aabb(root: Node3D) -> AABB:
	var out := AABB()
	var first := true
	var inv := root.global_transform.affine_inverse()
	for mi in _gather(root):
		if mi.mesh == null:
			continue
		var box := (inv * mi.global_transform) * mi.get_aabb()
		if first:
			out = box
			first = false
		else:
			out = out.merge(box)
	return out


static func _gather(node: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	if node is MeshInstance3D:
		out.append(node as MeshInstance3D)
	for c in node.get_children():
		out.append_array(_gather(c))
	return out


# Self-illuminate every surface so props read against black space without lights.
func _self_light(model: Node3D, glow: float) -> void:
	for mi in _gather(model):
		if mi.mesh == null:
			continue
		for si in mi.mesh.get_surface_count():
			var orig := mi.get_active_material(si)
			var m: BaseMaterial3D
			if orig is BaseMaterial3D:
				m = orig.duplicate() as BaseMaterial3D
			else:
				m = StandardMaterial3D.new()
			m.emission_enabled = true
			if m.albedo_texture != null:
				m.emission_texture = m.albedo_texture
				m.emission = Color(1, 1, 1)
			else:
				m.emission = m.albedo_color
			m.emission_energy_multiplier = glow
			mi.set_surface_override_material(si, m)
