class_name PlanetSystem
extends Node3D

const SurfacePatchScript := preload("res://scripts/world/surface_patch.gd")
const FlightModeScript := preload("res://scripts/flight/flight_mode.gd")
# Real bodies with floating-origin LOD. Positions come from Ephemeris (live JPL
# Horizons for the Sun + planets, real catalog for the stars) — nothing here is
# hand-placed. See ephemeris.gd for the data, frame and scale.
#
# Two render paths, matching two physical realities:
#   • Sun + Earth are physical-scale (1u = 1 km; Earth 6,371 u, Sun 1 AU away) -> the
#     dot<->sphere crossfade LOD, translated every frame by floating origin.
#   • Stars are millions of units away -> a fixed direction-only backdrop shell
#     at STAR_SHELL_RADIUS (real RA/Dec), NOT floating-origin translated and NOT
#     subject to the camera far-plane problem. Real distance shows on the label.
#
# refresh() is called by main.gd with the ship's true position each frame.

# Approach speed-zone (units/s). Ceiling stays >= cruise so normal flight near a
# body isn't throttled.
# Force-slow "gravity safe-zones" (NO pull — just a speed cap). A body force-slows the
# ship within radius × zone-mult (stars get the wider zone, like a much bigger gravity
# reach), eased down to a floor that's LOWER for more massive bodies. Zones are finite,
# so you can always fly back out — and outside every zone you're free to warp.
const STAR_ZONE_MULT := 120.0    # star slow-zone radius = star radius × this (wider: felt sooner)
const STAR_ZONE_FLOOR := 45.0    # speed cap at a star's CENTRE. The approach still slows you (warp
								 # drops at the zone edge), but this floor stays high enough to fly
								 # straight THROUGH the sun instead of crawling to a near-stop.
const STAR_EDGE_SPEED := 64.0    # speed cap at a STAR's zone edge — lower than planets, so you
								 # notice the drag the moment you enter a star's range
const PLANET_ZONE_MULT := 45.0   # planet/moon slow-zone radius = radius × this
# VISUAL size boost: planets/moons (and their moon-orbit spacing + LOD + capture range) are
# rendered this much bigger so they read as substantial worlds, not specks dwarfed by the ship.
# Heliocentric DISTANCES (real JPL positions) and gravity/slow-zones are NOT scaled — only the
# look. Relative geometry is preserved (moons scale with their parent, so they stay outside it).
const VISUAL_SCALE := 2.7   # mild bump: bodies a touch bigger so Mercury isn't dwarfed by the ship (stars stay unscaled)
# Visual orbital revolution: planets circle the Sun for life (they START at their real JPL
# position, then drift). Kepler-ordered: inner planets visibly orbit, outer ones crawl.
# Speeds are accelerated (real motion is invisible over a play session). Sun + Earth stay put.
const ORBIT_ENABLED := true
const ORBIT_K := 16.0      # bigger = faster orbits (angular speed = ORBIT_K / r^1.5)
# NOTE units: 1u = 0.01 AU, so 100 u/s = 1 AU/s. These are deliberately LOW so flight
# near Sol/any body is a slow crawl (fractions of an AU per second), never "a few AU
# per press". You only get warp-fast out in the deep, beyond every zone.
const ZONE_EDGE_SPEED := 90.0    # speed cap at the zone's outer edge (~0.9 AU/s)
const ZONE_FLOOR := 8.0          # slowest cap, at a very massive body's centre (~0.08 AU/s)

# Gravity: a gentle, mass-scaled tug toward each planet (mass ~ radius²), falling
# off with distance², clamped so thrust always wins. Retuned for the 0.1-AU scale.
const GRAVITY_ENABLED := false   # no gravitational pull — bodies are SAFE ZONES (speed-limited), not wells
# Mass-based gravity: accel = GRAV_G × mass(Earth=1) / dist². Real masses (see the
# body specs) make the giants + Sun grab hard while Mercury/Mars barely tug. Capped
# below thrust (~1650) so a planet can pull you in, but full throttle always escapes.
const GRAV_G := 31400.0             # gravity constant for the gameplay scale
const GRAVITY_MAX_ACCEL := 800.0    # per-body pull ceiling (units/s²)
const GRAVITY_RANGE_MULT := 60.0    # a body's well reaches within radius × this
# Stars are tiny on screen but carry a sun's mass — up close they pull hard enough to
# visibly bend your hull's path. Felt only within STAR_GRAVITY_RANGE. This is ON (the
# ship feels star gravity) while planet gravity + BOLT gravity stay OFF (GRAVITY_ENABLED):
# keeping gravity_at() returning zero means bullets fly dead-straight near every star.
const STAR_GRAVITY_ENABLED := true     # stars pull the SHIP (planets don't; bullets don't)
const STAR_GRAVITY_K := 18000000000.0  # accel = K / dist² (capped) — retuned for the ×10 spread
const STAR_GRAVITY_RANGE := 90000.0    # the well reaches out far enough to "call" you in
const STAR_GRAVITY_MAX := 160.0        # ceiling (units/s²); thrust (~1650) still wins

# Assigned by main before this node enters the tree.
@onready var eph := Ephemeris   # autoload

# Filled in by refresh(), read by the HUD / ship.
var nearest_name := ""
var nearest_dist := INF
var nearest_dir := Vector3.ZERO   # unit vector from ship toward the nearest body
var nearest_radius := 1.0         # visual radius of the nearest body (capture range scales with it)
var speed_limit := INF
var gravity := Vector3.ZERO
var star_dist := INF              # distance to this system's primary star (gates FTL / warp)
var speed_zones := false          # Sol 1:1 slice: speed pass comes later
var cook_n := 0                   # physical worlds this frame
var cook_mesh_n := 0              # cook balls in range
var cook_sky_n := 0               # sky discs past the far plane
var cook_look := ""               # nearest: name  mesh|sky  source  kind
# Nearest named hub star you could "fly-arrive" into (id + distance + render offset). main reads
# these in the hub: fly close enough and it drops you into that star's local frame (see _arrive).
var hub_star_id := ""
var hub_star_dist := INF
var hub_star_rel := Vector3.ZERO   # render-space vector ship→star (so arrival keeps your spot)

var _bodies := []
var _stars := []        # named real stars as floating-origin destinations
var _dot_tex: Texture2D
var _rel := {}          # body name -> current render-space position (for navigator)
var _sun_sky: MeshInstance3D   # photosphere disc on the sky shell (real Sun is 1 AU)
var _sun_corona: MeshInstance3D
var _sun_core_r := 1.0
const SUN_CORONA_MULT := 10.0
const SUN_CORONA_MAX_ANG := 0.07   # ~4° radius — never a screen-filling card
const SUN_CORONA_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;
void fragment() {
	vec2 p = UV - vec2(0.5);
	float d = length(p) * 2.0;
	if (d >= 0.99) {
		discard;
	}
	float core = smoothstep(0.16, 0.0, d);
	float halo = exp(-d * 5.5) * (1.0 - smoothstep(0.45, 0.92, d));
	ALBEDO = vec3(1.0, 0.92, 0.55) * core * 3.2 + vec3(1.0, 0.55, 0.12) * halo * 0.65;
}
"""
var _surface: Node3D           # skin-band bird-view ground (rings / water / kit)
var _samplers := {}            # body name -> TerrainSampler, built on first need
# Inside-the-atmosphere sky. An inward-facing sphere centred on the ship, drawn
# only while there is air around you. Radius is large so terrain and the body's
# own globe occlude it by depth test and it paints only where sky is visible.
var _air_shell: MeshInstance3D
var _air_mat: ShaderMaterial
const AIR_SHELL_KM := 200000.0

const STAR_RADIUS := 22.0     # visual size when you arrive
const STAR_SKY := 28000.0    # far dots clamp here so they read as sky points
const STAR_NEAR := 4200.0    # within this -> growing emissive sphere


# Names of bodies that can be navigation targets (planets, then named stars).
func targetables() -> Array:
	var out := []
	for b in _bodies:
		out.append(b.name)
	for st in _stars:
		out.append(st.name)
	return out

# Current render-space position of a body (relative to the ship).
func rel_of(name: String) -> Vector3:
	return _rel.get(name, Vector3.ZERO)


# Rich targetable list for the aim-based Tab picker: each entry carries the body's
# render-space offset, its kind (star/planet/moon/craft) and visual radius, so the
# picker can apply a per-type pick range (a big star reaches out many ly, a probe
# only a fraction of one). See main._aim_sorted_targets / _tab_pick_range.
func target_candidates() -> Array:
	var out := []
	for b in _bodies:
		var kind := "planet"
		if b.get("star", false):
			kind = "star"
		elif b.get("craft", false):
			kind = "craft"
		elif String(b.get("parent", "")) != "":
			kind = "moon"
		out.append({ "name": b.name, "rel": _rel.get(b.name, Vector3.ZERO),
			"kind": kind, "radius": float(b.radius) })
	for st in _stars:
		out.append({ "name": st.name, "rel": _rel.get(st.name, Vector3.ZERO),
			"kind": "star", "radius": STAR_RADIUS })
	return out


# Kind of a body by name: "star" | "planet" | "moon" | "craft" | "" (unknown). Used to label
# an undiscovered Tab target ("Unknown Star" / "Unknown Planet" …) without leaking its name.
func is_physical(name: String) -> bool:
	for b in _bodies:
		if b.name == name:
			return bool(b.get("physical", false))
	return false


func kind_of(name: String) -> String:
	for b in _bodies:
		if b.name == name:
			if b.get("star", false):
				return "star"
			elif b.get("craft", false):
				return "craft"
			elif String(b.get("parent", "")) != "":
				return "moon"
			return "planet"
	for st in _stars:
		if st.name == name:
			return "star"
	return ""


func _ready() -> void:
	_dot_tex = _make_dot_texture()
	_build_sun_sky()
	_surface = SurfacePatchScript.new()
	add_child(_surface)
	_build_air_shell()
	load_system(SystemDB.bodies(SystemDB.SOL))
	_build_star_shell()


# Swap the rendered bodies to a different star system (used on wormhole arrival).
# Clears the current bodies and rebuilds from the given specs.
func load_system(specs: Array) -> void:
	for b in _bodies:
		b.dot.queue_free()
		b.label.queue_free()
		if b.sphere != null:
			b.sphere.queue_free()
		if b.model != null:
			b.model.queue_free()
		if b.ring != null:
			b.ring.queue_free()
		if b.get("sky") != null:
			b.sky.queue_free()
	_bodies.clear()
	# Samplers are keyed by BODY NAME, so a new system containing a same-named
	# body would otherwise be handed the previous world's terrain.
	_samplers.clear()
	for spec in specs:
		_build_planet(spec)
	var nphys := 0
	for b in _bodies:
		if b.get("physical", false):
			nphys += 1
	if nphys > 0:
		print("[sol cook] %d physical worlds through the generator" % nphys)
		for b in _bodies:
			if str(b.name) == "Moon" or str(b.name) == "Earth" or str(b.name) == "Io":
				print("[sol cook] %s  r=%.1f km  map=%s  parent=%s" % [
					b.name, float(b.radius),
					PlanetGenerator.has_map(b.recipe), str(b.get("parent", ""))])
	# reset transient readouts so a stale name doesn't linger one frame
	nearest_name = ""
	nearest_dist = INF
	speed_limit = INF


func _build_planet(p: Dictionary) -> void:
	var is_star: bool = p.get("star", false)

	var dot := Sprite3D.new()
	dot.texture = _dot_tex
	dot.modulate = p.color
	dot.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	dot.shaded = false
	dot.pixel_size = 0.02
	add_child(dot)

	# Close-up body: craft keep their GLB. Everything else goes through the cook.
	# Catalog stars have no model — spectral type paints the ball.
	var model: Node3D = null
	var sphere: MeshInstance3D = null
	var mat: Material = null
	var recipe: Dictionary = PlanetGenerator.recipe_for(p)
	var use_model: bool = p.has("model") and (
		p.get("craft", false) or (is_star and not PlanetGenerator.has_map(recipe))
	)
	if use_model:
		model = _make_glb_body(p)
	if model == null:
		var vis: float = 1.0 if (is_star or p.get("physical", false)) else VISUAL_SCALE
		var look := PlanetGenerator.paint(p, float(p.radius) * vis)
		sphere = look.sphere
		mat = look.mat
		recipe = look.recipe
		add_child(sphere)

	# Optional flat planetary ring (Saturn). Radial SSS strip on the annulus UV.
	var ring: MeshInstance3D = null
	if p.get("ring", false):
		ring = MeshInstance3D.new()
		var rvis: float = 1.0 if p.get("physical", false) else VISUAL_SCALE
		ring.mesh = _make_ring_mesh(float(p.radius) * 1.15 * rvis, float(p.radius) * 2.35 * rvis, 96)
		ring.material_override = PlanetGenerator.make_ring_material(recipe)
		ring.rotation = Vector3(deg_to_rad(26.7), 0.0, deg_to_rad(7.0))   # Saturn's tilt
		ring.visible = false
		add_child(ring)

	var label := Label3D.new()
	label.text = p.name
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.modulate = Color(1, 1, 1, 0)
	label.outline_modulate = Color(0, 0, 0, 0.8)
	label.outline_size = 16
	label.font_size = 72
	label.pixel_size = 0.0058
	add_child(label)

	# Craft (Voyagers) drift outward forever from their start point at a constant speed.
	var is_craft: bool = p.get("craft", false)
	var craft_pos := Vector3.ZERO
	var drift_vel := Vector3.ZERO
	if is_craft:
		craft_pos = eph.scene_pos(p.name)
		var dir := craft_pos.normalized()
		if dir == Vector3.ZERO:
			dir = Vector3(0, 0, -1)
		drift_vel = dir * float(p.get("drift", 0.0))
	_bodies.append({
		"name": p.name, "radius": float(p.radius),
		"mass": float(p.get("mass", float(p.radius) * float(p.radius) * 0.05)),   # Earth=1; fallback ~ size
		"craft": is_craft, "drift_vel": drift_vel,
		"live": p.get("live", true) and not is_craft,   # craft use their own drift, not live
		"pos": craft_pos if is_craft else p.get("pos", Vector3.ZERO),
		"star": is_star,                      # the system's primary — gates FTL (star field)
		"parent": p.get("parent", ""),        # non-empty => a moon orbiting that body
		"orbit_r": float(p.get("orbit_r", 0.0)),
		"orbit_speed": float(p.get("orbit_speed", 0.0)),
		"fixed": p.get("fixed", false),       # Earth: stays put (geocentric origin), no sun-orbit
		# Moons get a random start phase (spread them); planets start at 0 so they begin at
		# their real JPL position, then revolve.
		"orbit_a": (randf() * TAU if String(p.get("parent", "")) != "" else 0.0),
		"dot": dot, "sphere": sphere, "mat": mat, "model": model, "label": label,
		"ring": ring,
		"sky": _make_body_sky(p, recipe) if (p.get("physical", false) and not p.get("star", false)) else null,
		"recipe": recipe,
		"mu": eph.gm(str(p.name)),
		"spin": eph.spin_rad_s(str(p.name)),
		"physical": p.get("physical", false),
		"close_maps": false,
	})


# A flat annulus (planetary ring) in the XZ plane, double-sided via the material.
func _make_ring_mesh(inner: float, outer: float, seg: int) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in seg:
		var a0 := TAU * float(i) / float(seg)
		var a1 := TAU * float(i + 1) / float(seg)
		var ci0 := Vector3(cos(a0) * inner, 0.0, sin(a0) * inner)
		var co0 := Vector3(cos(a0) * outer, 0.0, sin(a0) * outer)
		var ci1 := Vector3(cos(a1) * inner, 0.0, sin(a1) * inner)
		var co1 := Vector3(cos(a1) * outer, 0.0, sin(a1) * outer)
		st.set_normal(Vector3.UP)
		st.set_uv(Vector2(0.0, 0.5)); st.add_vertex(ci0)
		st.set_uv(Vector2(1.0, 0.5)); st.add_vertex(co0)
		st.set_uv(Vector2(1.0, 0.5)); st.add_vertex(co1)
		st.set_uv(Vector2(0.0, 0.5)); st.add_vertex(ci0)
		st.set_uv(Vector2(1.0, 0.5)); st.add_vertex(co1)
		st.set_uv(Vector2(0.0, 0.5)); st.add_vertex(ci1)
	return st.commit()


# Instantiate a GLB body, scale it to the visual radius, self-light it (no scene)
# lights) and add it hidden. Returns null if the model can't load (-> sphere).
func _make_glb_body(p: Dictionary) -> Node3D:
	# Loads a PackedScene (.glb/.gltf) OR a bare Mesh (.obj) — wrap a Mesh in a
	# MeshInstance3D so both paths produce a model Node3D.
	var res := load(p.model)
	var inst: Node3D = null
	if res is PackedScene:
		inst = (res as PackedScene).instantiate() as Node3D
	elif res is Mesh:
		var mi := MeshInstance3D.new()
		mi.mesh = res
		inst = mi
	if inst == null:
		push_warning("PlanetSystem: couldn't load %s — using sphere" % p.model)
		return null
	var holder := Node3D.new()
	add_child(holder)
	holder.add_child(inst)
	# Stars keep their real size; only planets/moons are visually enlarged.
	var vis: float = 1.0 if (p.get("star", false) or p.get("physical", false)) else VISUAL_SCALE
	_fit(holder, inst, float(p.radius) * 2.0 * vis)   # longest axis == diameter
	_self_light(inst, p.color, float(p.get("glow", 1.0)), p.get("star", false))
	holder.visible = false
	return holder


func _fade_body_mat(mat: Material, a: float) -> void:
	if mat is StandardMaterial3D:
		var sm := mat as StandardMaterial3D
		var col: Color = sm.albedo_color
		col.a = a
		sm.albedo_color = col
		sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA


func _make_body_sky(p: Dictionary, recipe: Dictionary = {}) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = 1.0
	mesh.height = 2.0
	mesh.radial_segments = 24
	mesh.rings = 12
	mi.mesh = mesh
	if recipe.is_empty():
		recipe = PlanetGenerator.recipe_for(p)
	var mat: Material = PlanetGenerator.make_material(recipe, p)
	if mat is StandardMaterial3D:
		var sm := mat as StandardMaterial3D
		sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		sm.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_OPAQUE_ONLY
		PlanetGenerator.apply_sky(sm, recipe, p)
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.extra_cull_margin = Ephemeris.SKY_STAR_KM
	mi.visible = false
	add_child(mi)
	return mi


func _place_body_sky(b: Dictionary, rel: Vector3, dist: float, too_far: bool) -> void:
	if not too_far or dist < 0.001:
		b.sky.visible = false
		return
	var shell: float = eph.sky_impostor_km(dist)
	var ang := asin(clampf(float(b.radius) / dist, 0.0, 0.999))
	var r: float = shell * tan(ang)
	r = maxf(r, 2.0)
	b.sky.scale = Vector3.ONE * r
	b.sky.position = (rel / dist) * shell
	b.sky.visible = true
	if b.sky.material_override is ShaderMaterial:
		var body_true: Vector3 = eph.scene_pos(str(b.name)) if b.live else b.pos
		var sm := b.sky.material_override as ShaderMaterial
		PlanetGenerator.apply_view(sm, _star_true() - body_true, 0.0)
		sm.set_shader_parameter("sky_glow", 1.0)


func _build_sun_sky() -> void:
	# Real Sun mesh sits at 1 AU, bigger than the far plane. Sky disc + corona
	# are the only Sun you can see from GEO. Core stays ~0.53°. Corona is the glare.
	_sun_core_r = Ephemeris.SKY_SHELL_KM * tan(deg_to_rad(Ephemeris.SUN_ANG_RADIUS_DEG))
	var spec := { "name": "Sun", "star": true, "physical": true, "color": Color(1.0, 0.85, 0.30) }
	var look := PlanetGenerator.paint(spec, _sun_core_r)
	_sun_sky = look.sphere
	_sun_sky.visible = true
	_sun_sky.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_sun_sky.extra_cull_margin = Ephemeris.SKY_STAR_KM
	if look.mat is ShaderMaterial:
		(look.mat as ShaderMaterial).set_shader_parameter("sky_glow", 1.0)
	if not _sun_sky.is_inside_tree():
		add_child(_sun_sky)
	_sun_corona = MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(2.0, 2.0)
	_sun_corona.mesh = quad
	var sh := Shader.new()
	sh.code = SUN_CORONA_SHADER
	var sm := ShaderMaterial.new()
	sm.shader = sh
	_sun_corona.material_override = sm
	_sun_corona.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_sun_corona.extra_cull_margin = Ephemeris.SKY_STAR_KM
	_sun_corona.scale = Vector3.ONE * (_sun_core_r * SUN_CORONA_MULT)
	add_child(_sun_corona)
	print("[sol cook] Sun sky disc %.2f deg + corona x%.0f" % [
		Ephemeris.SUN_ANG_RADIUS_DEG * 2.0, SUN_CORONA_MULT])


# Named real stars at their TRUE distances — floating-origin destinations you can
# fly to. Far away they read as labelled sky points (clamped); up close they bloom
# into an emissive sphere. Positions/labels update every frame in refresh().
func _build_star_shell() -> void:
	for s in Ephemeris.STARS:
		var dot := Sprite3D.new()
		dot.texture = _dot_tex
		dot.modulate = s.color
		dot.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		dot.shaded = false
		dot.pixel_size = 5.0
		add_child(dot)

		var sphere := MeshInstance3D.new()
		var mesh := SphereMesh.new()
		mesh.radius = STAR_RADIUS
		mesh.height = STAR_RADIUS * 2.0
		mesh.radial_segments = 16
		mesh.rings = 8
		sphere.mesh = mesh
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = s.color
		mat.emission_enabled = true
		mat.emission = s.color
		mat.emission_energy_multiplier = 2.2
		sphere.material_override = mat
		sphere.visible = false
		add_child(sphere)

		var label := Label3D.new()
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.modulate = Color(s.color, 0.9)
		label.outline_modulate = Color(0, 0, 0, 0.8)
		label.outline_size = 12
		label.font_size = 46
		label.pixel_size = 1.0
		add_child(label)

		_stars.append({
			"name": s.name, "id": SystemDB.id_for_name(s.name),
			"true_pos": eph.star_true_pos(s), "ly": s.ly,
			"mass": float(s.get("mass", 333000.0)),
			"dot": dot, "sphere": sphere, "label": label,
		})


func refresh(ship_pos: Vector3, delta: float) -> void:
	nearest_dist = INF
	nearest_name = ""
	speed_limit = INF
	gravity = Vector3.ZERO
	star_dist = INF
	hub_star_dist = INF
	hub_star_id = ""
	nearest_radius = 1.0
	cook_n = 0
	cook_mesh_n = 0
	cook_sky_n = 0
	cook_look = ""

	# Render positions computed THIS frame, by name. Moons read their parent from here so
	# they track the planet's visually-revolved position, not its raw Horizons spot (planets
	# are built before moons in _sol(), so a parent is always present by the time a moon needs
	# it). Without this, fast inner planets (Mars) drift off and their moons orbit empty space.
	var star_true := _star_true()
	var frame_pos := {}
	for b in _bodies:
		var rad: float = b.radius
		var vrad: float = rad * (1.0 if (b.star or b.get("physical", false)) else VISUAL_SCALE)
		# Moons orbit their (live) parent; Sol bodies read live Horizons positions; others static.
		var bpos: Vector3
		if b.get("craft", false):
			b.pos += b.drift_vel * delta       # Voyagers drift outward forever
			bpos = b.pos
		elif b.parent != "" and not b.get("physical", false):
			# Arcade moons only. Sol 1:1 moons stay on live JPL / fallback spots.
			b.orbit_a += float(b.orbit_speed) * delta
			var oa: float = b.orbit_a
			var off: Vector3 = Vector3(cos(oa), 0.18 * sin(oa * 0.5), sin(oa)) * float(b.orbit_r) * VISUAL_SCALE
			# Follow the parent's revolved render position (this frame), falling back to its raw
			# Horizons spot if for some reason it wasn't computed yet.
			bpos = frame_pos.get(b.parent, eph.scene_pos(b.parent)) + off
		elif b.live:
			bpos = eph.scene_pos(b.name)
			# Visual revolution around the Sun (planets only). Advance the phase and rotate the
			# real heliocentric vector about the ecliptic-ish up axis.
			if ORBIT_ENABLED and not b.star and not b.fixed and not b.get("physical", false):
				var sunp: Vector3 = eph.scene_pos("Sun")
				var h: Vector3 = bpos - sunp
				var r := h.length()
				if r > 0.01:
					b.orbit_a += (ORBIT_K / pow(r, 1.5)) * delta
					bpos = sunp + h.rotated(Vector3.UP, b.orbit_a)
		else:
			# Authored systems: spread the static planet layout by the same factor the planets
			# grew, so bigger bodies don't end up inside their (unscaled) star. Star sits at origin.
			bpos = b.pos * (1.0 if b.star else VISUAL_SCALE)
		frame_pos[b.name] = bpos   # parents are computed before their moons (see _sol order)
		var rel: Vector3 = bpos - ship_pos  # floating origin
		var dist := rel.length()

		var mu: float = float(b.get("mu", 0.0))
		if mu > 0.0 and dist > 0.001:
			# Physical Sol: real GM/r². No range fade, no arcade ceiling.
			gravity += (rel / dist) * (mu / (dist * dist))
		elif GRAVITY_ENABLED and dist > 0.001 and dist < rad * GRAVITY_RANGE_MULT:
			var a := minf(GRAV_G * float(b.mass) / (dist * dist), GRAVITY_MAX_ACCEL)
			gravity += (rel / dist) * a

		# Force-slow safe-zone (NO pull): cap speed within a mass/size-scaled radius, eased from
		# the edge speed down to a floor at the body. Stars use a HIGHER floor (STAR_ZONE_FLOOR)
		# so you still decelerate on approach but can fly THROUGH the sun, not crawl to a stop.
		if speed_zones:
			var zone: float = rad * (STAR_ZONE_MULT if b.star else PLANET_ZONE_MULT)
			if dist < zone:
				var zt := dist / zone
				var edge: float = STAR_EDGE_SPEED if b.star else ZONE_EDGE_SPEED
				var floor_spd: float = STAR_ZONE_FLOOR if b.star else _slow_min(float(b.mass))
				speed_limit = minf(speed_limit, lerpf(floor_spd, edge, zt))

		b.dot.position = rel
		b.label.position = rel + Vector3(0.0, vrad * 1.5 + 0.5, 0.0)
		_rel[b.name] = rel        # for the navigator (render-space position)

		if dist < nearest_dist:
			nearest_dist = dist
			nearest_name = b.name
			nearest_radius = vrad
		if b.get("star", false) and dist < star_dist:
			star_dist = dist   # how far we are from this system's sun (FTL gate)

		if b.get("mat") != null and b.mat is ShaderMaterial:
			var to_sun: Vector3 = star_true - bpos
			var alt := dist - vrad
			var det := PlanetGenerator.close_detail(alt)
			PlanetGenerator.apply_view(b.mat, to_sun, det)
			if not b.get("close_maps", false) and PlanetGenerator.close_enough(dist, vrad):
				PlanetGenerator.ensure_close_maps(b.mat, b.recipe)
				b.close_maps = true

		# crossfade: dot (far) -> body (near), scaled to the RENDERED body size
		var far_d := vrad * 70.0
		var near_d := vrad * 18.0
		var frac := clampf((dist - near_d) / maxf(far_d - near_d, 0.001), 0.0, 1.0)
		var sphere_a := 1.0 - frac

		# Physical Sol bodies keep the mesh while the near face is inside the far
		# plane. Past that the mesh is clipped, so a sky-shell disc holds the disc.
		# Stars use the same cut — never force the cook mesh off.
		var physical: bool = b.get("physical", false)
		var too_far: bool = physical and eph.physical_too_far(dist, rad)
		if physical and not b.get("craft", false):
			cook_n += 1
			if too_far:
				cook_sky_n += 1
			else:
				cook_mesh_n += 1
		if b.model != null:
			var on: bool = (physical and not too_far) or ((not physical) and sphere_a > 0.45)
			b.model.visible = on
			if on:
				b.model.position = rel
				b.model.rotate_y(b.spin * delta)
		else:
			b.sphere.position = rel
			b.sphere.rotate_y(b.spin * delta)
			b.sphere.visible = (physical and not too_far) or ((not physical) and sphere_a > 0.45)

		if b.get("sky") != null:
			_place_body_sky(b, rel, dist, too_far)

		# Planetary ring (Saturn): track the body, fade in with the close-up sphere.
		if b.ring != null:
			b.ring.position = rel
			b.ring.visible = (not too_far) and (physical or sphere_a > 0.02)
			if b.ring.visible:
				var rc: Color = b.ring.material_override.albedo_color
				rc.a = 0.6 * (1.0 if physical else sphere_a)
				b.ring.material_override.albedo_color = rc

		b.dot.visible = (not physical) and frac > 0.02
		if b.dot.visible:
			var dc: Color = b.dot.modulate
			dc.a = frac
			b.dot.modulate = dc
			b.dot.pixel_size = clampf(dist * 0.0008, 0.02, 2.0)

		if too_far and dist > 0.001:
			var sdir: Vector3 = rel / dist
			b.label.visible = true
			b.label.position = sdir * eph.sky_impostor_km(dist) + Vector3(0.0, 12.0, 0.0)
			b.label.text = "%s\n%s" % [b.name, _fmt_star_dist(dist)]
			var lc: Color = b.label.modulate
			lc.a = 0.85
			b.label.modulate = lc
		else:
			var label_range := maxf(vrad * 130.0, 500.0)
			var la := clampf((label_range - dist) / (label_range * 0.3), 0.0, 1.0)
			b.label.visible = la > 0.02
			b.label.text = b.name
			if b.label.visible:
				var lc2: Color = b.label.modulate
				lc2.a = la
				b.label.modulate = lc2

	# Named stars: floating-origin destinations. Far -> a labelled sky point in the
	# right direction (clamped); near -> a growing emissive sphere. Live distance.
	for st in _stars:
		var srel: Vector3 = st.true_pos - ship_pos
		var sdist := srel.length()
		_rel[st.name] = srel
		# A star's gravity well — strong up close, so a near pass bends your trajectory.
		if STAR_GRAVITY_ENABLED and sdist > 0.001 and sdist < STAR_GRAVITY_RANGE:
			var sa := minf(STAR_GRAVITY_K / (sdist * sdist), STAR_GRAVITY_MAX)
			gravity += (srel / sdist) * sa
		if sdist < nearest_dist:
			nearest_dist = sdist
			nearest_name = st.name
			nearest_radius = STAR_RADIUS
		# Nearest star you could fly-arrive into (must be a real travel destination).
		if st.get("id", "") != "" and sdist < hub_star_dist:
			hub_star_dist = sdist
			hub_star_id = str(st.id)
			hub_star_rel = srel
		# Force-slow safe-zone around the star (no pull) — this is what eases you out
		# of warp as you arrive, scaled by the star's mass.
		var szone := STAR_RADIUS * STAR_ZONE_MULT
		if sdist < szone:
			# Higher floor (STAR_ZONE_FLOOR) than planets so you fly THROUGH the star, not crawl.
			speed_limit = minf(speed_limit, lerpf(STAR_ZONE_FLOOR, STAR_EDGE_SPEED, sdist / szone))
		var sdir: Vector3 = srel.normalized()
		if sdist < STAR_NEAR:
			st.sphere.visible = true
			st.sphere.position = srel
			st.dot.visible = false
			st.label.position = srel + Vector3(0.0, STAR_RADIUS * 1.6 + 2.0, 0.0)
		else:
			st.sphere.visible = false
			st.dot.visible = true
			var sky: float = Ephemeris.SKY_STAR_KM
			var rd := minf(sdist, sky)
			st.dot.position = sdir * rd
			st.dot.pixel_size = clampf(rd * 0.00000002, 1.5, 7.0)
			st.label.position = sdir * rd + Vector3(0.0, 14.0, 0.0)
		st.label.text = "%s\n%s" % [st.name, _fmt_star_dist(sdist)]

	# speed_limit was accumulated above from each body's force-slow zone (min cap).
	# Direction toward the nearest body (for the warp arrival ease-out).
	nearest_dir = _rel.get(nearest_name, Vector3.ZERO).normalized()
	# The nearest body's recipe and truth flag, picked up here so the skin band
	# below can be driven by the same row the tape reports.
	var near_recipe := {}
	var near_physical := false
	for b in _bodies:
		if str(b.name) != nearest_name:
			continue
		var rec: Dictionary = b.get("recipe", {})
		near_recipe = rec
		near_physical = b.get("physical", false)
		var path := "sky" if (b.get("physical", false) and eph.physical_too_far(nearest_dist, float(b.radius))) else "mesh"
		cook_look = "%s  %s  %s  %s" % [
			str(b.name), path, str(rec.get("source", "?")), str(rec.get("kind", "?"))]
		break
	_place_sun_sky(ship_pos)
	# Skin band: ONE local ground tile, nearest body only, alive between that body's
	# kill line and its own terrain-derived ceiling. Everything it paints comes from
	# `near_recipe`, so the Moon gets lunar crust and not Earth's continents.
	# `near_physical` is load-bearing: an arcade system's "altitude" is in 0.01-AU
	# units, and a tile must never pop out there (see SurfacePatch.should_show).
	if _surface != null:
		var sampler := terrain_sampler_for(nearest_name)
		var ceiling: float = PlanetGenerator.band_ceiling_km(sampler)
		# Altitude above LOCAL GROUND, not above the sphere. Over Everest the two
		# differ by ~8.9 km, which is the whole point of this slice. `_rel` holds
		# the render-space vector ship->body, so the ship's offset from the body's
		# centre - the frame the sampler works in - is its negation.
		var salt: float = nearest_dist - nearest_radius
		var body_basis := surface_basis(nearest_name)
		var from_centre: Vector3 = body_basis.inverse() * -_rel.get(nearest_name, Vector3.ZERO)
		if sampler != null and near_physical and from_centre.length() > 0.001:
			salt = sampler.alt_above_ground_km(from_centre, nearest_radius)
			# Fold the band cap into speed_limit, which the ship already reads.
			# Deliberately NOT gated on `speed_zones`: that flag defers the
			# approach-zone pass, while this cap is what makes the contact kill
			# sound - one frame at the cap must be shorter than a ring-0 quad.
			if salt < ceiling:
				speed_limit = minf(speed_limit,
					FlightModeScript.band_speed_cap_units(salt))
		_surface.transform = Transform3D(body_basis, _rel.get(nearest_name, Vector3.ZERO))
		_surface.update_for(from_centre, nearest_name, near_physical, nearest_radius,
			salt, eph.surface_kill_km(nearest_name), ceiling, near_recipe, sampler)
		# The coarse globe has a different displacement and can protrude through
		# valleys. The complete horizon-covering terrain replaces it in this band.
		if _surface.visible:
			for b in _bodies:
				if str(b.name) == nearest_name:
					b.sphere.visible = false
		# Light and air. The sun vector is body -> star, exactly what
		# PlanetGenerator.apply_view() hands the globe's material.
		var to_star: Vector3 = star_true - (ship_pos + _rel.get(nearest_name, Vector3.ZERO))
		_update_air(to_star, salt, ceiling, near_recipe, nearest_name, near_physical)


func surface_basis(body: String) -> Basis:
	for b in _bodies:
		if str(b.name) == body:
			return b.sphere.basis.orthonormalized()
	return Basis.IDENTITY


func ground_altitude_km(body: String) -> float:
	var sampler := terrain_sampler_for(body)
	for b in _bodies:
		if str(b.name) == body and sampler != null:
			return sampler.alt_above_ground_km(surface_basis(body).inverse() * -rel_of(body), float(b.radius))
	return INF


func _build_air_shell() -> void:
	var mesh := SphereMesh.new()
	mesh.radius = AIR_SHELL_KM
	mesh.height = AIR_SHELL_KM * 2.0
	mesh.radial_segments = 32
	mesh.rings = 16
	_air_shell = MeshInstance3D.new()
	_air_shell.name = "AirShell"
	_air_shell.mesh = mesh
	_air_shell.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_air_shell.visible = false
	add_child(_air_shell)


# Sky, light and haze for the nearest body, every frame. `sun_dir` is the SAME
# vector the globe's own material gets, so the tile's terminator and the globe's
# cannot drift apart at the tile's edge.
func _update_air(sun_dir: Vector3, alt_km: float, ceiling_km: float,
		recipe: Dictionary, body: String, physical: bool) -> void:
	if _surface != null and _surface.has_method("set_view"):
		# Haze follows the AIR, not the band ceiling: at 30 km there is almost
		# nothing to scatter in, so distant ground has to go clear.
		_surface.set_view(sun_dir, alt_km, eph.atmo_top_km(body))
	if _air_shell == null:
		return
	var air_top: float = eph.atmo_top_km(body)
	var opacity := 0.0
	if physical:
		opacity = PlanetGenerator.air_shell_opacity(
			alt_km, air_top, float(recipe.get("air_amount", 0.0)))
	if opacity <= 0.001:
		_air_shell.visible = false
		return
	if _air_mat == null or _air_mat.shader != PlanetGenerator.AIR_SHELL_SHADER:
		_air_mat = PlanetGenerator.air_shell_material(recipe, {"spectral": "G"})
		_air_shell.material_override = _air_mat
	_air_shell.visible = true
	var air_color: Color = recipe.get("color_air", Color(0.30, 0.56, 1.0))
	_air_mat.set_shader_parameter("color_air", Vector3(air_color.r, air_color.g, air_color.b))
	# The shell is centred on the ship, which is the render-space origin.
	_air_shell.position = Vector3.ZERO
	var up: Vector3 = -_rel.get(body, Vector3.ZERO)
	_air_mat.set_shader_parameter("opacity", opacity)
	_air_mat.set_shader_parameter("sun_dir", sun_dir.normalized())
	_air_mat.set_shader_parameter("term_lo", PlanetGenerator.TERMINATOR_LO)
	_air_mat.set_shader_parameter("term_hi", PlanetGenerator.TERMINATOR_HI)
	if up.length_squared() > 0.0001:
		_air_mat.set_shader_parameter("up_dir", up.normalized())


# The shared TerrainSampler for a body, built once. main's contact kill and the
# ground tile MUST receive the same instance: two samplers would be two height
# functions, and the mesh and the lethality would drift apart.
func terrain_sampler_for(body: String) -> TerrainSampler:
	if body.is_empty():
		return null
	if not _samplers.has(body):
		for b in _bodies:
			if str(b.name) == body:
				_samplers[body] = PlanetGenerator.terrain_sampler(b.get("recipe", {}))
				break
	return _samplers.get(body, null)


func hush_surface() -> void:
	if _surface != null and _surface.has_method("hush"):
		_surface.hush()


func _star_true() -> Vector3:
	for b in _bodies:
		if not b.get("star", false):
			continue
		if b.live:
			return eph.scene_pos(b.name)
		return b.pos
	return eph.scene_pos("Sun")


func _place_sun_sky(ship_pos: Vector3) -> void:
	if _sun_sky == null:
		return
	var sunp: Vector3 = eph.scene_pos("Sun")
	var rel: Vector3 = sunp - ship_pos
	var dist := rel.length()
	if dist < 0.001:
		_sun_sky.visible = false
		if _sun_corona != null:
			_sun_corona.visible = false
		return
	# Same cut as the cook mesh. Hide the disc only when the ball is on.
	var show_sky: bool = eph.show_sky_impostor(dist, float(Ephemeris.SUN_RADIUS_KM))
	_sun_sky.visible = show_sky
	if _sun_corona != null:
		_sun_corona.visible = show_sky
	if not show_sky:
		return
	var dir: Vector3 = rel / dist
	var shell: float = eph.sky_impostor_km(dist)
	var pos: Vector3 = dir * shell
	var ang: float = atan(Ephemeris.SUN_RADIUS_KM / dist)
	var core: float = maxf(shell * tan(ang), 2.0)
	_sun_sky.position = pos
	_sun_sky.scale = Vector3.ONE * (core / _sun_core_r)
	if _sun_sky.material_override is ShaderMaterial:
		var sm := _sun_sky.material_override as ShaderMaterial
		PlanetGenerator.apply_view(sm, -pos, 0.0)
		sm.set_shader_parameter("sky_glow", 1.0)
	if _sun_corona != null:
		_sun_corona.position = pos
		var corona_ang: float = minf(ang * SUN_CORONA_MULT, SUN_CORONA_MAX_ANG)
		var corona_r: float = maxf(shell * tan(corona_ang), core * 1.6)
		_sun_corona.scale = Vector3.ONE * corona_r
		if pos.length_squared() > 0.001:
			var up := Vector3.UP
			if absf(dir.dot(up)) > 0.95:
				up = Vector3.RIGHT
			_sun_corona.look_at(Vector3.ZERO, up)


# Adaptive distance label for a star: light-years when genuinely far, but AU once you're
# in-system so the number actually CHANGES as you move closer/away (instead of "0.00 ly").
# (1 unit = 0.01 AU; Ephemeris.UNITS_PER_LY converts to light-years.)
func _fmt_star_dist(units: float) -> String:
	var ly := units / Ephemeris.UNITS_PER_LY
	if ly >= 0.05:
		return "%.2f ly" % ly
	var au := units / Ephemeris.AU_TO_UNITS
	if au >= 10.0:
		return "%.1f AU" % au
	if au >= 0.01:
		return "%.2f AU" % au
	return "%.0f km" % units


# Slowest speed cap a body imposes at its centre, from its mass (Earth=1): heavier =>
# slower. log() keeps the enormous mass range (Mercury 0.05 → Sun 333000) sensible.
func _slow_min(mass: float) -> float:
	return clampf(ZONE_EDGE_SPEED / (1.0 + log(1.0 + maxf(mass, 0.0)) * 0.42), ZONE_FLOOR, ZONE_EDGE_SPEED)


# Gravitational acceleration at an arbitrary true-space position, summed over every
# planet and star. Used by combat.gd so bullets curve through gravity wells too.
func gravity_at(pos: Vector3) -> Vector3:
	var g := Vector3.ZERO
	var frame_pos := {}   # parent render positions this call (planets precede moons in _sol)
	for b in _bodies:
		var bpos: Vector3
		if b.parent != "":
			var oa: float = b.orbit_a
			var off: Vector3 = Vector3(cos(oa), 0.18 * sin(oa * 0.5), sin(oa)) * float(b.orbit_r) * VISUAL_SCALE
			bpos = frame_pos.get(b.parent, eph.scene_pos(b.parent)) + off
		elif b.live:
			bpos = eph.scene_pos(b.name)
			if ORBIT_ENABLED and not b.star and not b.fixed and not b.get("physical", false):
				var sunp: Vector3 = eph.scene_pos("Sun")
				var h: Vector3 = bpos - sunp
				if h.length() > 0.01:
					bpos = sunp + h.rotated(Vector3.UP, b.orbit_a)   # read-only (refresh advances the phase)
		else:
			bpos = b.pos * (1.0 if b.star else VISUAL_SCALE)   # match refresh's authored-system spread
		frame_pos[b.name] = bpos
		var rel: Vector3 = bpos - pos
		var d := rel.length()
		var mu: float = float(b.get("mu", 0.0))
		if mu > 0.0 and d > 0.001:
			g += (rel / d) * (mu / (d * d))
		elif GRAVITY_ENABLED and d > 0.001 and d < float(b.radius) * GRAVITY_RANGE_MULT:
			var a := minf(GRAV_G * float(b.mass) / (d * d), GRAVITY_MAX_ACCEL)
			g += (rel / d) * a
	if not GRAVITY_ENABLED:
		return g
	for st in _stars:
		var rel: Vector3 = st.true_pos - pos
		var d := rel.length()
		if d > 0.001 and d < STAR_GRAVITY_RANGE:
			var a := minf(STAR_GRAVITY_K / (d * d), STAR_GRAVITY_MAX)
			g += (rel / d) * a
	return g


# --- GLB helpers (scale, recenter, self-light) ------------------------------
func _fit(holder: Node3D, model: Node3D, target_len: float) -> void:
	var box := _combined_aabb(holder)
	var size := box.size
	var longest := maxf(size.x, maxf(size.y, size.z))
	if longest <= 0.0001:
		return
	var factor := target_len / longest
	model.scale = model.scale * factor
	model.position -= (box.position + size * 0.5) * factor


func _combined_aabb(root: Node3D) -> AABB:
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


func _gather(node: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	if node is MeshInstance3D:
		out.append(node as MeshInstance3D)
	for c in node.get_children():
		out.append_array(_gather(c))
	return out


# Self-illuminate every surface so the body reads without scene lights. Stars
# burn from their own color; planets emit their texture so the map shows.
func _self_light(model: Node3D, tint: Color, glow: float, is_star: bool) -> void:
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
			if is_star:
				m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
				m.emission = tint
				m.albedo_color = tint
			else:
				# A planet surface, NOT metal. glTF defaults metalness to 1.0,
				# which hides the texture (this is why Earth looked colourless) —
				# force it matte so the map shows, lit by the Sun key light. Tint
				# the (desaturated) map toward the body colour so Earth reads blue.
				m.metallic = 0.0
				m.roughness = 0.9
				m.albedo_color = tint
				m.emission = tint   # dim flat floor; night side stays dark-ish
			m.emission_energy_multiplier = glow
			mi.set_surface_override_material(si, m)


# Soft radial glow circle, generated once (no binary asset to ship).
func _make_dot_texture() -> Texture2D:
	var size := 64
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var center := Vector2(size, size) * 0.5
	var half := size * 0.5
	for y in size:
		for x in size:
			var d := Vector2(x + 0.5, y + 0.5).distance_to(center) / half
			var a := clampf(1.0 - d, 0.0, 1.0)
			a = pow(a, 1.6)
			img.set_pixel(x, y, Color(1.0, 1.0, 1.0, a))
	return ImageTexture.create_from_image(img)
