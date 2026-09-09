class_name Wormhole
extends Node3D
# Interstellar travel without breaking the engine: each system is its own small
# local space, and a wormhole teleports you between them. You NEVER fly the real
# light-years — the distance only sets how long the tunnel transit lasts and what
# the HUD reads. On arrival main.gd hard-resets the ship to a small local coord.
#
# A system can hold SEVERAL portals (Earth/Sol has one per exoplanet destination,
# spread far apart and parked); every other system has a single portal back to
# Sol. Each portal is a glowing ring with a floating "→ <destination>" label,
# floating-origin tracked. Fly near any portal, press F, and a tunnel sequence
# plays for ~ (ly × SEC_PER_LY) seconds, then main swaps to that portal's system.
#
# Portal positions are ABSOLUTE and static; every query below asks the ship for
# the render-space vector (Ship.rel_to) rather than subtracting its position, so
# a Sol portal stays exact whatever body the ship is anchored to (docs/adr/0002).

const PORTAL_RANGE := 110.0   # F-window around a portal — generous so it's easy to dive in
const MAX_PORTALS := 6                  # pool size (Interstellar hub uses 5; systems use 1)
# Space platforms: ~half the hub wormholes carry a dockable station (see SystemDB.has_station)
# so you never have to fly far — teleport platform→platform, then short-fly the rest. The
# platform parks just off its wormhole ring; main docks at the nearest one (see nearest_station).
const STATION_GLB := "res://assets/space station.glb"
const STATION_SIZE := 34.0                  # fitted longest-axis size of the platform
# Park the platform well clear of the wormhole ring — FARTHER than PORTAL_RANGE (110) so
# that when you're in dock range of the platform you're OUT of the wormhole's F-range
# (F-key priority is wormhole-enter first, dock second; otherwise the platform would be
# unreachable, swallowed by the portal's range).
const STATION_OFFSET := Vector3(150.0, -45.0, 0.0)   # |offset| ≈ 157 > PORTAL_RANGE
const STATION_DOCK_RANGE := 110.0           # F-to-dock proximity at a platform
const STATION_CULL := 3200.0                # stop drawing the platform mesh beyond this
# Transit length = light-years × this (clamped). Tunable: 0.15 → ~18s for K2-18b
# (dev-friendly); set ~2.9 for the ~6-minute "epic haul" the design calls for.
const SEC_PER_LY := 0.15
const TRANSIT_MIN := 4.0
const TRANSIT_MAX := 600.0

var ship: Node3D                       # for parenting/aligning the tunnel
var transiting := false
var dest_id := ""                      # destination of the portal you're at / heading to
var dest_ly := 0.0

# Portal pool. Each entry: { node, mat, label, pos, dest_id, dest_ly, active }.
var _portals := []
var _active := -1                      # index of the portal currently in F-range
var _tunnel: MeshInstance3D
var _tunnel_mat: StandardMaterial3D
var _t := 0.0
var _duration := 0.0
var _station_scene: PackedScene   # the platform GLB, instantiated lazily per platformed portal


func _ready() -> void:
	_station_scene = load(STATION_GLB) as PackedScene
	for i in MAX_PORTALS:
		_portals.append(_build_portal())


func set_ship(s: Node3D) -> void:
	ship = s
	_build_tunnel()   # lives on the ship so it stays aligned with travel


# Lay out a system's portals from SystemDB (a star system's single exit gate). The hub's
# KNOWN-filtered wormhole field is set by main via set_portals() directly.
func set_system(id: String) -> void:
	set_portals(SystemDB.portals(id))

# Show an explicit list of portals: [{ pos, dest, dest_ly? }]. Grows the pool as needed
# (the hub can hold many imaginary wormholes once the player has discovered them).
func set_portals(defs: Array) -> void:
	while _portals.size() < defs.size():
		_portals.append(_build_portal())
	for i in _portals.size():
		var p = _portals[i]
		if i < defs.size():
			p.pos = defs[i].pos
			p.dest_id = defs[i].dest
			p.dest_ly = defs[i].get("dest_ly", SystemDB.light_years(defs[i].dest))
			p.active = true
			p.node.visible = true
			p.label.text = "◇ %s ◇\n%.0f ly" % [SystemDB.display_name(p.dest_id), p.dest_ly]
			p.label.visible = true
			p.station = bool(defs[i].get("station", false))
			if p.station and p.station_node == null:
				p.station_node = _make_station()   # build the platform lazily, once
			if p.station_node != null:
				p.station_node.visible = p.station
			if p.station_label != null:
				p.station_label.text = "⬡ %s PLATFORM" % SystemDB.display_name(p.dest_id)
				p.station_label.visible = p.station
		else:
			p.active = false
			p.node.visible = false
			p.label.visible = false
			p.station = false
			if p.station_node != null:
				p.station_node.visible = false
			if p.station_label != null:
				p.station_label.visible = false
	_active = -1
	if defs.size() > 0:
		dest_id = defs[0].dest
		dest_ly = defs[0].get("dest_ly", SystemDB.light_years(dest_id))

# Render-space offset of the KNOWN wormhole that leads to `dest` (for the nav guide).
# Vector3.ZERO if that wormhole isn't currently present.
func portal_rel_for(dest: String, flyer: Ship) -> Vector3:
	for p in _portals:
		if p.active and p.dest_id == dest:
			return flyer.rel_to(p.pos)
	return Vector3.ZERO


# True if the ship is within F-range of ANY portal; remembers the nearest one so
# start_transit / the HUD know which destination it is.
func in_range(flyer: Ship) -> bool:
	if transiting:
		return false
	_active = -1
	var best := PORTAL_RANGE
	for i in _portals.size():
		var p = _portals[i]
		if not p.active:
			continue
		var d: float = flyer.rel_to(p.pos).length()
		if d < best:
			best = d
			_active = i
	if _active >= 0:
		dest_id = _portals[_active].dest_id
		dest_ly = _portals[_active].dest_ly
		return true
	return false


# Every active portal as { rel, dest } in render space (for the minimap — all wormholes,
# live). Empty inside a system with no known links.
func portals_rel(flyer: Ship) -> Array:
	var out := []
	for p in _portals:
		if p.active:
			out.append({ "rel": flyer.rel_to(p.pos), "dest": p.dest_id })
	return out


# Render-space position of the nearest portal (for the navigator marker).
func portal_rel(flyer: Ship) -> Vector3:
	var best := INF
	var rel := Vector3.ZERO
	for p in _portals:
		if not p.active:
			continue
		var r: Vector3 = flyer.rel_to(p.pos)
		var d := r.length()
		if d < best:
			best = d
			rel = r
	return rel


# Nearest active portal as { rel, name } (for the HUD objective guide). {} if none.
func nearest_portal(flyer: Ship) -> Dictionary:
	var best := INF
	var out := {}
	for p in _portals:
		if not p.active:
			continue
		var r: Vector3 = flyer.rel_to(p.pos)
		var d := r.length()
		if d < best:
			best = d
			out = { "rel": r, "name": SystemDB.display_name(p.dest_id) }
	return out


# Harbour speed-cap as you near a wormhole — the same "ease down so you don't blast past"
# feel as a station/platform, so you can line up and dive in. INF when clear of all
# portals; eases to WH_MIN_SPEED right at the ring. main folds this into ship.struct_limit.
const WH_SLOW_RANGE := 750.0   # start easing down within this of the nearest portal
const WH_EDGE_SPEED := 850.0   # cap as you enter the slow zone (drops you out of warp)
const WH_MIN_SPEED := 40.0     # gentle crawl right at the mouth — easy to settle + press F

func slow_limit(flyer: Ship) -> float:
	if transiting:
		return INF
	var best := INF
	for p in _portals:
		if not p.active:
			continue
		best = minf(best, flyer.rel_to(p.pos).length())
	if best >= WH_SLOW_RANGE:
		return INF
	# Ease firmly from WH_EDGE_SPEED at the zone's rim down to a WH_MIN_SPEED crawl at the
	# mouth, so the whole approach is slow and controllable (the old curve snapped back to
	# full speed almost immediately, which is why landing felt impossible).
	return lerpf(WH_MIN_SPEED, WH_EDGE_SPEED, clampf(best / WH_SLOW_RANGE, 0.0, 1.0))


# Nearest dockable platform as { pos, name, range } (absolute scene pos, for main's dock
# logic — the hub has many). {} when none are present (e.g. inside a star system).
func nearest_station(flyer: Ship) -> Dictionary:
	var best := INF
	var out := {}
	for p in _portals:
		if not p.active or not p.station:
			continue
		var sp: Vector3 = p.pos + STATION_OFFSET
		var d := flyer.rel_to(sp).length()
		if d < best:
			best = d
			out = { "pos": sp, "name": "%s Platform" % SystemDB.display_name(p.dest_id), "range": STATION_DOCK_RANGE }
	return out


func start_transit() -> void:
	transiting = true
	_t = 0.0
	var p = _portals[_active] if _active >= 0 else _portals[0]
	dest_id = p.dest_id
	dest_ly = p.dest_ly
	_duration = clampf(dest_ly * SEC_PER_LY, TRANSIT_MIN, TRANSIT_MAX)
	for pp in _portals:
		pp.node.visible = false
		pp.label.visible = false
		if pp.station_node != null:
			pp.station_node.visible = false
		if pp.station_label != null:
			pp.station_label.visible = false
	_tunnel.visible = true


# Start a transit to an EXPLICIT destination (the star map's "warp here"), no portal
# needed. Same tunnel + distance-scaled duration as a portal jump; main's update loop
# detects completion and calls _arrive(dest_id) just like a normal transit.
func start_warp(dest: String, ly: float) -> void:
	transiting = true
	_t = 0.0
	dest_id = dest
	dest_ly = ly
	_duration = clampf(ly * SEC_PER_LY, TRANSIT_MIN, TRANSIT_MAX)
	for pp in _portals:
		pp.node.visible = false
		pp.label.visible = false
		if pp.station_node != null:
			pp.station_node.visible = false
		if pp.station_label != null:
			pp.station_label.visible = false
	_tunnel.visible = true


func transit_remaining() -> float:
	return maxf(_duration - _t, 0.0)


# Returns true on the frame the transit finishes (main then swaps the system).
func update(flyer: Ship, delta: float) -> bool:
	if transiting:
		_t += delta
		# Rings glide past at a measured pace and the tube swirls slowly — dark + ominous,
		# not a hypersonic storm. The glow pulses for drama but stays restrained; the colour
		# drifts through a deep cold-blue → violet band (low value so it reads dark).
		var rush: float = 5.0 + 2.0 * sin(_t * 0.9)            # measured glide, not a surge
		_tunnel_mat.uv1_offset += Vector3(0.0, -rush * delta, 0.0)
		_tunnel.rotate_object_local(Vector3.UP, 0.6 * delta)   # slow swirl around the axis
		var storm: float = 0.75 + 0.25 * sin(_t * 4.0)         # gentle, slow pulse
		_tunnel_mat.emission_energy_multiplier = 1.8 * storm
		var hue: float = fmod(0.64 + _t * 0.07, 1.0)           # slow drift cold-blue → violet
		var col := Color.from_hsv(hue, 0.7, 0.75)              # deep, low-value -> dark
		_tunnel_mat.emission = col
		var s: float = 1.0 + 0.03 * sin(_t * 5.0)              # subtle breathe only
		_tunnel.scale = Vector3(s, 1.0, s)
		if _t >= _duration:
			transiting = false
			_tunnel.visible = false
			_tunnel.scale = Vector3.ONE
			return true
		return false

	# idle: float every active portal in place (floating origin), spin + pulse it.
	var glow := 2.0 + 0.8 * sin(Time.get_ticks_msec() * 0.004)
	for p in _portals:
		if not p.active:
			continue
		var rel: Vector3 = flyer.rel_to(p.pos)
		p.node.visible = true
		p.node.position = rel
		p.node.rotate_z(0.6 * delta)
		p.mat.emission_energy_multiplier = glow
		p.label.visible = true
		p.label.position = rel + Vector3(0.0, 11.0, 0.0)
		p.label.pixel_size = clampf(rel.length() * 0.00012, 0.02, 1.2)
		# Platform: park it just off the wormhole ring, slowly spinning, with a label.
		# Distance-cull the GLB mesh (heavy) so only nearby platforms draw — at full
		# discovery there can be ~25 of them, and you only ever dock at the close one.
		if p.station and p.station_node != null:
			var srel: Vector3 = flyer.rel_to(p.pos + STATION_OFFSET)
			var near: bool = srel.length() < STATION_CULL
			p.station_node.visible = near
			if near:
				p.station_node.position = srel
				p.station_node.rotate_y(0.05 * delta)
			if p.station_label != null:
				p.station_label.visible = near
				if near:
					p.station_label.position = srel + Vector3(0.0, STATION_SIZE * 0.7, 0.0)
					p.station_label.pixel_size = clampf(srel.length() * 0.00012, 0.02, 1.2)
	return false


# --- visuals ---------------------------------------------------------------
# Build one portal (ring + event-horizon core + danger glow + floating label) and
# return its state dict. The pool of these is positioned per system in set_system.
func _build_portal() -> Dictionary:
	# A dangerous-looking hole: a dark event-horizon core, a fiery accretion ring
	# that spins, and an outer red danger-glow. All emissive — no lights.
	var torus := TorusMesh.new()
	torus.inner_radius = 4.75
	torus.outer_radius = 7.75
	torus.rings = 36
	torus.ring_segments = 16
	var portal := MeshInstance3D.new()
	portal.mesh = torus
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.32, 0.05)        # fiery orange accretion
	mat.albedo_color = Color(1.0, 0.28, 0.04)
	mat.emission_energy_multiplier = 2.6
	portal.material_override = mat
	portal.visible = false
	add_child(portal)

	# Event horizon — a near-black sphere that swallows the center.
	var core := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 4.9; sm.height = 9.8; sm.radial_segments = 20; sm.rings = 10
	core.mesh = sm
	var cmat := StandardMaterial3D.new()
	cmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	cmat.albedo_color = Color(0.01, 0.0, 0.015)          # the hole — eats the light
	core.material_override = cmat
	portal.add_child(core)

	# Outer danger glow — billboarded red haze so it reads as a threat from afar.
	var glow := MeshInstance3D.new()
	var q := QuadMesh.new(); q.size = Vector2(27.5, 27.5)
	glow.mesh = q
	var gmat := StandardMaterial3D.new()
	gmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	gmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	gmat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	gmat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	gmat.albedo_texture = _make_hole_glow()
	gmat.albedo_color = Color(1.0, 0.18, 0.06, 0.85)
	glow.material_override = gmat
	portal.add_child(glow)

	# Floating destination label (billboard), positioned each frame in update().
	var label := Label3D.new()
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.outline_modulate = Color(0, 0, 0, 0.7)
	label.outline_size = 8
	label.font_size = 40
	label.modulate = Color(1.0, 0.7, 0.45)
	label.no_depth_test = true
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.visible = false
	add_child(label)

	# Floating platform label (built once; shown only when this wormhole has a platform).
	var slabel := Label3D.new()
	slabel.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	slabel.outline_modulate = Color(0, 0, 0, 0.7)
	slabel.outline_size = 8
	slabel.font_size = 34
	slabel.modulate = Color(0.55, 0.85, 1.0)
	slabel.no_depth_test = true
	slabel.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	slabel.visible = false
	add_child(slabel)

	return {
		"node": portal, "mat": mat, "label": label,
		"pos": Vector3.ZERO, "dest_id": "", "dest_ly": 0.0, "active": false,
		"station": false, "station_node": null, "station_label": slabel,
	}


# Build one dockable platform: instantiate the station GLB, fit it to STATION_SIZE, and
# self-illuminate it so it reads against black (no Light3D out here). Hidden until placed.
func _make_station() -> Node3D:
	var holder := Node3D.new()
	add_child(holder)
	if _station_scene == null:
		push_warning("Wormhole: station GLB not loaded (%s)" % STATION_GLB)
		holder.visible = false
		return holder
	var model := _station_scene.instantiate() as Node3D
	holder.add_child(model)
	_fit_glb(holder, model, STATION_SIZE)
	_self_light_glb(model, 0.5)
	holder.visible = false
	return holder


# Scale model so its longest axis == target and recenter it on the holder.
func _fit_glb(holder: Node3D, model: Node3D, target: float) -> void:
	var box := _glb_aabb(holder)
	var longest := maxf(box.size.x, maxf(box.size.y, box.size.z))
	if longest <= 0.0001:
		return
	var factor := target / longest
	model.scale = model.scale * factor
	model.position -= (box.position + box.size * 0.5) * factor


func _glb_aabb(root: Node3D) -> AABB:
	var out := AABB()
	var first := true
	var inv := root.global_transform.affine_inverse()
	for mi in _gather_mi(root):
		if mi.mesh == null:
			continue
		var box := (inv * mi.global_transform) * mi.get_aabb()
		if first:
			out = box
			first = false
		else:
			out = out.merge(box)
	return out


func _gather_mi(node: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	if node is MeshInstance3D:
		out.append(node as MeshInstance3D)
	for c in node.get_children():
		out.append_array(_gather_mi(c))
	return out


func _self_light_glb(model: Node3D, glow: float) -> void:
	for mi in _gather_mi(model):
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


# Radial haze: bright near the rim, fading out — the hole's danger glow.
func _make_hole_glow() -> Texture2D:
	var s := 64
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	var c := Vector2(s, s) * 0.5
	for y in s:
		for x in s:
			var d := Vector2(x + 0.5, y + 0.5).distance_to(c) / (s * 0.5)
			var a := pow(clampf(1.0 - d, 0.0, 1.0), 2.0)
			img.set_pixel(x, y, Color(1, 1, 1, a))
	return ImageTexture.create_from_image(img)


func _build_tunnel() -> void:
	var cyl := CylinderMesh.new()
	cyl.top_radius = 7.0
	cyl.bottom_radius = 7.0
	cyl.height = 160.0
	cyl.radial_segments = 28
	cyl.rings = 1
	_tunnel = MeshInstance3D.new()
	_tunnel.mesh = cyl
	_tunnel.rotation = Vector3(deg_to_rad(90.0), 0.0, 0.0)  # length along Z (travel axis)
	_tunnel.position = Vector3(0.0, 0.0, -55.0)             # ahead of the chase camera
	_tunnel_mat = StandardMaterial3D.new()
	_tunnel_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_tunnel_mat.cull_mode = BaseMaterial3D.CULL_DISABLED      # we view it from inside
	_tunnel_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	# ALPHA (not ADD): additive can only brighten the starfield — it can't read "dark".
	# Alpha-blended near-black walls ENCLOSE the ship in a dark tube; the emissive rings
	# punch through against it for the dramatic contrast.
	_tunnel_mat.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
	_tunnel_mat.emission_enabled = true
	_tunnel_mat.emission = Color(0.35, 0.28, 0.7)
	_tunnel_mat.emission_energy_multiplier = 1.6
	_tunnel_mat.albedo_texture = _make_tunnel_texture()
	_tunnel_mat.emission_texture = _tunnel_mat.albedo_texture
	_tunnel_mat.uv1_scale = Vector3(6.0, 12.0, 1.0)          # repeat rings down the tube
	_tunnel.material_override = _tunnel_mat
	_tunnel.visible = false
	ship.add_child(_tunnel)


# Sharp glowing rings on near-black walls that scroll past — a dark "wormhole" wall.
# Walls are dark + fairly opaque so the alpha-blended tube ENCLOSES the ship; the rings
# are sharp (high power) for punchy contrast so "dark" never reads as flat/dull.
func _make_tunnel_texture() -> Texture2D:
	var h := 64
	var img := Image.create(4, h, false, Image.FORMAT_RGBA8)
	for y in h:
		var v := float(y) / float(h)
		var band := pow(0.5 + 0.5 * sin(v * TAU * 3.0), 7.0)   # sharper -> punchier rings
		var c := Color(
			0.02 + 0.55 * band,        # near-black walls, electric-violet rings
			0.015 + 0.35 * band,
			0.06 + 0.95 * band,
			0.55 + 0.45 * band)        # walls fairly opaque -> dark enclosure
		for x in 4:
			img.set_pixel(x, y, c)
	return ImageTexture.create_from_image(img)
