class_name MapView3D
extends Control
# Elite-style 3D navigation chart (SubViewport + Camera3D). Replaces the 2D MapChart
# inside StarMap — one map UI, two modes, shared holo look (dark / cyan):
#   GLOBAL — SystemDB.coord() stars + known wormhole lanes + player marker
#   LOCAL  — current system star / planets / moons / wormhole gates / station + ship
# Potato-friendly meshes. Real catalog / ephemeris / wormhole graph / ship.true_pos.
# Public API mirrors MapChart so StarMap glue stays small:
#   filters, view_system, main, star_clicked, init_view(), center_on(), span_ly()

signal star_clicked(id: String)
signal mode_changed(mode: String)  # "local" | "global"

enum Mode { GLOBAL, LOCAL }

const HIT_PX := 18.0
const ZOOM_STEP := 1.15
const GLOBAL_SCALE := 1.0
const LOCAL_MAP_R := 28.0

var main: Node
var view_system := ""
var filters := {
	"stars": true, "wormholes": true, "planets": true, "lanes": true, "platforms": true,
}
var mode: Mode = Mode.GLOBAL

var _box: SubViewportContainer
var _vp: SubViewport
var _cam: Camera3D
var _world: Node3D
var _lanes: MeshInstance3D

var _yaw := 0.55
var _pitch := 0.42
var _dist := 48.0
var _focus := Vector3.ZERO
var _dist_min := 8.0
var _dist_max := 220.0

var _dragging := false
var _moved := false
var _press := Vector2.ZERO
var _pickables: Array = []  # { id: String, pos: Vector3 }
var _hover := ""
var _t := 0.0

var _local_center := Vector3.ZERO
var _local_ref := 1000.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true
	_build_viewport()
	resized.connect(_sync_vp_size)


func _build_viewport() -> void:
	_box = SubViewportContainer.new()
	_box.set_anchors_preset(Control.PRESET_FULL_RECT)
	_box.stretch = true
	_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_box)

	_vp = SubViewport.new()
	_vp.own_world_3d = true
	_vp.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	_vp.transparent_bg = false
	_vp.msaa_3d = Viewport.MSAA_2X
	_vp.size = Vector2i(700, 500)
	_box.add_child(_vp)

	var env_n := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.008, 0.015, 0.04, 1.0)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.2, 0.32, 0.45)
	env.ambient_light_energy = 0.9
	env.glow_enabled = true
	env.glow_intensity = 0.4
	env.glow_bloom = 0.12
	env.set_glow_level(2, 1.0)
	env.set_glow_level(3, 0.6)
	env_n.environment = env
	_vp.add_child(env_n)

	_cam = Camera3D.new()
	_cam.current = true
	_cam.fov = 42.0
	_cam.near = 0.05
	_cam.far = 4000.0
	_vp.add_child(_cam)

	_world = Node3D.new()
	_world.name = "MapWorld"
	_vp.add_child(_world)

	_lanes = MeshInstance3D.new()
	_lanes.name = "Lanes"
	_world.add_child(_lanes)

	var light := DirectionalLight3D.new()
	light.light_color = Color(0.55, 0.8, 1.0)
	light.light_energy = 0.55
	light.rotation_degrees = Vector3(-48, 36, 0)
	_vp.add_child(light)


func _sync_vp_size() -> void:
	# SubViewportContainer.stretch owns the viewport size; nothing to do.
	pass


func init_view() -> void:
	_sync_vp_size()
	if mode == Mode.GLOBAL:
		_yaw = 0.55
		_pitch = 0.42
		_dist = 48.0
		_dist_min = 6.0
		_dist_max = 260.0
	else:
		_yaw = 0.9
		_pitch = 0.55
		_dist = 55.0
		_dist_min = 12.0
		_dist_max = 140.0
	rebuild()


func center_on(id: String) -> void:
	if mode != Mode.GLOBAL or id == "":
		return
	_focus = _gpos(id)
	_apply_cam()


func span_ly() -> int:
	if mode == Mode.LOCAL or _cam == null:
		return 0
	var half: float = tan(deg_to_rad(_cam.fov * 0.5)) * _dist
	return int(maxi(1, int(half * 2.0 / maxf(GLOBAL_SCALE, 0.001))))


func set_mode(m: Mode) -> void:
	if mode == m:
		return
	mode = m
	mode_changed.emit("local" if m == Mode.LOCAL else "global")
	init_view()


func toggle_mode() -> void:
	set_mode(Mode.LOCAL if mode == Mode.GLOBAL else Mode.GLOBAL)


func rebuild() -> void:
	if main == null or _world == null:
		return
	for c in _world.get_children():
		if c != _lanes:
			c.queue_free()
	_pickables.clear()
	_lanes.mesh = null
	if mode == Mode.GLOBAL:
		_build_global()
	else:
		_build_local()
	_apply_cam()
	queue_redraw()


func _gpos(id: String) -> Vector3:
	# Alien Zone: hand-set 2D `map` pocket so its 666 ly coord does not yank the camera.
	for r in SystemDB.AUTHORED:
		if str(r.get("id", "")) == id and r.has("map"):
			var m: Vector2 = r.map
			return Vector3(m.x, 2.5, m.y) * GLOBAL_SCALE
	if id == SystemDB.INTERSTELLAR:
		return Vector3(0.0, 3.0, 0.0) * GLOBAL_SCALE
	return SystemDB.coord(id) * GLOBAL_SCALE


func _build_global() -> void:
	var here: String = main.current_system
	_focus = _gpos(here)

	if filters.lanes or filters.wormholes:
		_build_global_lanes()

	if filters.stars:
		for id in SystemDB.all():
			var p := _gpos(id)
			var st: String = main.star_state(id)
			var core: Color = SystemDB.star_color(id)
			var ring := _state_col(st)
			var r: float = 0.55 if st == "here" else (0.42 if st == "discovered" else 0.32)
			if id == view_system:
				r *= 1.25
			var alpha: float = 0.55 if st == "locked" else 1.0
			_add_sphere(p, r, core, ring, alpha)
			if st == "here" or st == "discovered" or id == view_system:
				_add_label(p + Vector3(0, r + 0.4, 0), SystemDB.display_name(id), ring)
			_pickables.append({ "id": id, "pos": p })
			if filters.platforms and SystemDB.has_station(id):
				_add_platform(p + Vector3(0.55, 0.45, 0.0), st != "locked")

	var hp := _gpos(here)
	_add_ring(hp, 1.15, Color(0.45, 1.0, 0.7, 0.85), 0.04)
	_add_player(hp + Vector3(0, 1.35, 0))


func _build_global_lanes() -> void:
	var verts := PackedVector3Array()
	var cols := PackedColorArray()
	for e in SystemDB.wh_edges():
		var a: String = e[0]
		var b: String = e[1]
		if a == SystemDB.INTERSTELLAR or b == SystemDB.INTERSTELLAR:
			continue
		if not main.is_edge_known(a, b):
			continue
		var pa := _gpos(a)
		var pb := _gpos(b)
		if filters.lanes:
			verts.append(pa)
			verts.append(pb)
			var c := Color(0.35, 0.85, 1.0, 0.55)
			cols.append(c)
			cols.append(c)
		if filters.wormholes:
			_add_wormhole((pa + pb) * 0.5, 0.28)
	_set_lanes(verts, cols)


func _build_local() -> void:
	var sys: String = main.current_system
	view_system = sys
	var rows: Array = []

	if sys == SystemDB.INTERSTELLAR:
		for p in main._known_portals(sys):
			rows.append({
				"name": "◌ " + SystemDB.display_name(str(p.dest)),
				"pos": p.pos, "kind": "wormhole",
				"color": Color(0.7, 0.55, 1.0), "radius": 40.0, "id": str(p.dest),
			})
	else:
		for spec in SystemDB.bodies(sys):
			var bname: String = str(spec.name)
			if bname.contains("✦"):
				continue
			var pos := Vector3.ZERO
			if bool(spec.get("live", false)) and Ephemeris.has_pos(bname):
				pos = Ephemeris.scene_pos(bname)
			elif spec.has("pos"):
				pos = spec.pos
			rows.append({
				"name": bname, "pos": pos,
				"kind": "star" if bool(spec.get("star", false)) else "body",
				"color": spec.get("color", Color(0.7, 0.8, 0.9)),
				"radius": float(spec.get("radius", 1.0)), "id": sys,
			})
		for p in main._known_portals(sys):
			rows.append({
				"name": "◌ " + SystemDB.display_name(str(p.dest)),
				"pos": p.pos, "kind": "wormhole",
				"color": Color(0.65, 0.5, 1.0), "radius": 80.0, "id": str(p.dest),
			})
		if SystemDB.is_teleport_platform(sys):
			rows.append({
				"name": "⬡ Station", "pos": SystemDB.arrival_pos(sys),
				"kind": "station", "color": Color(0.35, 1.0, 0.85),
				"radius": 60.0, "id": sys,
			})

	var star_pos := Vector3.ZERO
	var found_star := false
	for r in rows:
		if r.kind == "star":
			star_pos = r.pos
			found_star = true
			break
	_local_center = star_pos if found_star else Vector3.ZERO
	if not found_star and not rows.is_empty():
		var acc := Vector3.ZERO
		for r in rows:
			acc += r.pos
		_local_center = acc / float(rows.size())

	var dists: Array = []
	for r in rows:
		var d: float = (r.pos - _local_center).length()
		if d > 0.01:
			dists.append(d)
	dists.sort()
	_local_ref = maxf(dists[dists.size() / 2], 1.0) if not dists.is_empty() else 1000.0

	var ship_pos := Vector3.ZERO
	if main.ship != null:
		ship_pos = main.ship.true_pos
	rows.append({
		"name": "YOU", "pos": ship_pos, "kind": "player",
		"color": Color(0.55, 1.0, 0.75), "radius": 1.0, "id": sys,
	})

	_add_ring(Vector3.ZERO, LOCAL_MAP_R * 0.55, Color(0.35, 0.6, 0.9, 0.22), 0.02)
	_add_ring(Vector3.ZERO, LOCAL_MAP_R * 0.9, Color(0.35, 0.6, 0.9, 0.12), 0.015)

	for r in rows:
		var mp := _compress_local(r.pos)
		match String(r.kind):
			"star":
				_add_sphere(mp, 1.6, r.color, Color(1.0, 0.9, 0.5), 1.0)
				_add_label(mp + Vector3(0, 2.1, 0), r.name, Color(1.0, 0.9, 0.55))
				_pickables.append({ "id": r.id, "pos": mp })
			"body":
				if not filters.planets:
					continue
				var br: float = clampf(0.25 + log(1.0 + float(r.radius)) * 0.12, 0.28, 0.85)
				_add_sphere(mp, br, r.color, Color(0.55, 0.8, 1.0), 1.0)
				_add_label(mp + Vector3(0, br + 0.35, 0), r.name, Color(0.7, 0.9, 1.0))
				_pickables.append({ "id": r.id, "pos": mp })
			"wormhole":
				if not filters.wormholes:
					continue
				_add_wormhole(mp, 0.55)
				_add_label(mp + Vector3(0, 0.9, 0), r.name, Color(0.75, 0.65, 1.0))
				_pickables.append({ "id": r.id, "pos": mp })
			"station":
				if not filters.platforms:
					continue
				_add_platform(mp, true)
				_add_label(mp + Vector3(0, 0.7, 0), r.name, Color(0.4, 1.0, 0.85))
			"player":
				_add_player(mp)
				_add_label(mp + Vector3(0, 1.1, 0), "YOU", Color(0.65, 1.0, 0.8))

	_focus = Vector3.ZERO


func _compress_local(true_pos: Vector3) -> Vector3:
	var rel := true_pos - _local_center
	var d: float = rel.length()
	if d < 0.0001:
		return Vector3.ZERO
	var map_d: float = log(1.0 + d / _local_ref) / log(1.0 + 40.0)
	map_d = clampf(map_d, 0.0, 1.0) * LOCAL_MAP_R
	return rel.normalized() * map_d


func _mat(col: Color, emit_mul: float = 1.2, alpha: float = 1.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(col.r, col.g, col.b, alpha)
	m.emission_enabled = true
	m.emission = Color(col.r, col.g, col.b)
	m.emission_energy_multiplier = emit_mul
	if alpha < 0.99:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return m


func _add_sphere(pos: Vector3, radius: float, core: Color, rim: Color, alpha: float) -> void:
	var mi := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 12
	mesh.rings = 8
	mi.mesh = mesh
	mi.material_override = _mat(core, 1.4, alpha)
	mi.position = pos
	_world.add_child(mi)
	var rim_mi := MeshInstance3D.new()
	var rm := SphereMesh.new()
	rm.radius = radius * 1.18
	rm.height = radius * 2.36
	rm.radial_segments = 10
	rm.rings = 6
	rim_mi.mesh = rm
	var mat := _mat(rim, 0.6, 0.22)
	mat.cull_mode = BaseMaterial3D.CULL_FRONT
	rim_mi.material_override = mat
	rim_mi.position = pos
	_world.add_child(rim_mi)


func _add_ring(pos: Vector3, radius: float, col: Color, thickness: float) -> void:
	var mi := MeshInstance3D.new()
	var mesh := TorusMesh.new()
	mesh.inner_radius = maxf(radius - thickness, 0.01)
	mesh.outer_radius = radius
	mesh.rings = 24
	mesh.ring_segments = 12
	mi.mesh = mesh
	mi.material_override = _mat(col, 0.8, col.a)
	mi.position = pos
	mi.rotation_degrees = Vector3(90, 0, 0)
	_world.add_child(mi)


func _add_wormhole(pos: Vector3, radius: float) -> void:
	_add_ring(pos, radius, Color(0.65, 0.5, 1.0, 0.85), radius * 0.12)
	_add_ring(pos, radius * 0.55, Color(0.85, 0.7, 1.0, 0.7), radius * 0.08)
	var core := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = radius * 0.22
	sm.height = radius * 0.44
	sm.radial_segments = 8
	sm.rings = 4
	core.mesh = sm
	core.material_override = _mat(Color(0.9, 0.8, 1.0), 2.0)
	core.position = pos
	_world.add_child(core)


func _add_platform(pos: Vector3, lit: bool) -> void:
	var mi := MeshInstance3D.new()
	var mesh := PrismMesh.new()
	mesh.size = Vector3(0.55, 0.7, 0.55)
	mi.mesh = mesh
	var c := Color(0.35, 1.0, 0.85, 0.95) if lit else Color(0.25, 0.55, 0.5, 0.45)
	mi.material_override = _mat(c, 1.2 if lit else 0.4, c.a)
	mi.position = pos
	_world.add_child(mi)


func _add_player(pos: Vector3) -> void:
	var mi := MeshInstance3D.new()
	var mesh := PrismMesh.new()
	mesh.size = Vector3(0.55, 1.1, 0.55)
	mi.mesh = mesh
	mi.material_override = _mat(Color(0.55, 1.0, 0.75), 2.2)
	mi.position = pos
	mi.rotation_degrees = Vector3(0, 0, 180)
	_world.add_child(mi)
	_add_ring(pos, 1.0, Color(0.5, 1.0, 0.7, 0.55), 0.05)


func _add_label(pos: Vector3, text: String, col: Color) -> void:
	var lab := Label3D.new()
	lab.text = text
	lab.font_size = 28
	lab.pixel_size = 0.018
	lab.modulate = col
	lab.outline_modulate = Color(0, 0, 0, 0.85)
	lab.outline_size = 6
	lab.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lab.no_depth_test = true
	lab.position = pos
	_world.add_child(lab)


func _set_lanes(verts: PackedVector3Array, cols: PackedColorArray) -> void:
	if verts.is_empty():
		_lanes.mesh = null
		return
	var arr: Array = []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_COLOR] = cols
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, arr)
	_lanes.mesh = am
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_lanes.material_override = mat


func _state_col(st: String) -> Color:
	match st:
		"here":       return Color(0.5, 1.0, 0.6)
		"discovered": return Color(1.0, 0.78, 0.32)
		"nav":        return Color(0.45, 0.85, 1.0)
		_:            return Color(0.55, 0.6, 0.68)


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	_t += delta
	if not _dragging and mode == Mode.GLOBAL:
		_yaw += delta * 0.05
		_apply_cam()
	var h := _pick_at(get_local_mouse_position())
	if h != _hover:
		_hover = h
		queue_redraw()


func _apply_cam() -> void:
	if _cam == null:
		return
	_pitch = clampf(_pitch, -1.2, 1.2)
	_dist = clampf(_dist, _dist_min, _dist_max)
	var cp := cos(_pitch)
	var offset := Vector3(sin(_yaw) * cp, sin(_pitch), cos(_yaw) * cp) * _dist
	_cam.position = _focus + offset
	_cam.look_at(_focus, Vector3.UP)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_dist /= ZOOM_STEP
			_apply_cam()
			accept_event()
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_dist *= ZOOM_STEP
			_apply_cam()
			accept_event()
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_dragging = true
				_moved = false
				_press = mb.position
			else:
				_dragging = false
				if not _moved:
					var id := _pick_at(mb.position)
					if id != "":
						star_clicked.emit(id)
				accept_event()
		elif mb.button_index == MOUSE_BUTTON_RIGHT or mb.button_index == MOUSE_BUTTON_MIDDLE:
			if mb.pressed:
				_dragging = true
				_moved = true
				_press = mb.position
			else:
				_dragging = false
			accept_event()
	elif event is InputEventMouseMotion and _dragging:
		var mm := event as InputEventMouseMotion
		if mm.position.distance_to(_press) > 4.0:
			_moved = true
		_yaw -= mm.relative.x * 0.007
		_pitch -= mm.relative.y * 0.007
		_apply_cam()
		accept_event()


func _pick_at(local_px: Vector2) -> String:
	if _cam == null or _pickables.is_empty():
		return ""
	var best := HIT_PX
	var hit := ""
	for p in _pickables:
		if _cam.is_position_behind(p.pos):
			continue
		var sp: Vector2 = _cam.unproject_position(p.pos)
		var d: float = sp.distance_to(local_px)
		if d < best:
			best = d
			hit = str(p.id)
	return hit


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.15, 0.45, 0.7, 0.35), false, 1.5)
	var font := ThemeDB.fallback_font
	var tag := "LOCAL SYSTEM" if mode == Mode.LOCAL else "GALAXY NETWORK"
	draw_string(font, Vector2(10, 18), tag, HORIZONTAL_ALIGNMENT_LEFT, -1, 12,
		Color(0.55, 0.95, 1.0, 0.9))
	if _hover == "" or main == null:
		return
	var st: String = main.star_state(_hover) if mode == Mode.GLOBAL else "here"
	var head := "%s — %s" % [SystemDB.display_name(_hover), SystemDB.spectral(_hover)]
	if mode == Mode.GLOBAL:
		head += " · %.1f ly" % SystemDB.light_years(_hover)
	var sub: String = {
		"here": "you are here",
		"discovered": "discovered · click to browse",
		"nav": "wormhole known · click to browse",
		"locked": "locked · click to browse",
	}.get(st, "click to browse")
	var w: float = maxf(
		font.get_string_size(head, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x,
		font.get_string_size(sub, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x) + 14.0
	var p := get_local_mouse_position() + Vector2(14, -36)
	p.x = clampf(p.x, 4.0, size.x - w - 4.0)
	p.y = clampf(p.y, 4.0, size.y - 36.0)
	draw_rect(Rect2(p, Vector2(w, 32)), Color(0.03, 0.06, 0.11, 0.92))
	draw_rect(Rect2(p, Vector2(w, 32)), Color(0.45, 0.85, 1.0, 0.5), false, 1.0)
	draw_string(font, p + Vector2(7, 13), head, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.9, 0.95, 1.0))
	draw_string(font, p + Vector2(7, 27), sub, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, _state_col(st))
