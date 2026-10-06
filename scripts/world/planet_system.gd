class_name PlanetSystem
extends Node3D
const StellarStructuresScript := preload("res://scripts/world/stellar_structures.gd")
const _AF := preload("res://scripts/flight/anchor_frame.gd")

const SurfacePatchScript := preload("res://scripts/world/surface_patch.gd")
const FlightModeScript := preload("res://scripts/flight/flight_mode.gd")
const CloudLayerScript := preload("res://scripts/world/cloud_layer.gd")
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

# Assigned by main before this node enters the tree.
@onready var eph := Ephemeris   # autoload

# Filled in by refresh(), read by the HUD / ship.
var nearest_name := ""
var nearest_dist := INF
var nearest_dir := Vector3.ZERO   # unit vector from ship toward the nearest body
var nearest_radius := 1.0         # visual radius of the nearest body (capture range scales with it)
var stellar_hazard := {}          # non-lethal proximity telemetry, reset on system changes
var cook_n := 0                   # physical worlds this frame
var cook_mesh_n := 0              # cook balls in range
var cook_sky_n := 0               # sky discs past the far plane
var cook_look := ""               # nearest: name  mesh|sky  source  kind

var _bodies := []
var _stars := []        # named real stars as floating-origin destinations
var _dot_tex: Texture2D
var _rel := {}          # body name -> current render-space position (for navigator)
var _sun_sky: MeshInstance3D   # photosphere disc on the sky shell (real Sun is 1 AU)
var _sun_corona: MeshInstance3D
var _sun_core_r := 1.0
var _sun_sky_star := "Sun"
const SUN_CORONA_MULT := 10.0
const SUN_CORONA_MAX_ANG := 0.07   # ~4° radius — never a screen-filling card
const SUN_CORONA_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;
uniform vec3 tint : source_color = vec3(1.0, 0.95, 0.86);
uniform float strength = 1.0;
void fragment() {
	vec2 p = UV - vec2(0.5);
	float d = length(p) * 2.0;
	if (d >= 0.99) {
		discard;
	}
	float core = smoothstep(0.16, 0.0, d);
	float halo = exp(-d * 5.5) * (1.0 - smoothstep(0.45, 0.92, d));
	ALBEDO = tint * strength * (core * 3.2 + halo * 0.65);
}
"""
var _surface: Node3D           # skin-band bird-view ground (rings / water / kit)
var _cloud_layer: Node3D       # deck between the band ceiling and the ground,
								# alive exactly while _surface is (see CloudLayer.should_show)
var _cloud_time_s := 0.0       # deterministic sim clock (accumulated `delta`, not wall-clock
								# TIME) shared by the shell and the globe's cook material — see
								# CloudLayer.cloud_uv_offset() / PlanetGenerator.set_cloud_drift()
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
			"kind": "star", "radius": st.radius })
	return out


# Kind of a body by name: "star" | "planet" | "moon" | "craft" | "" (unknown). Used to label
# an undiscovered Tab target ("Unknown Star" / "Unknown Planet" …) without leaking its name.
func stellar_recipe_for(name: String) -> Dictionary:
	for body in _bodies:
		if body.name == name and body.recipe.has("stellar"):
			return body.recipe
	for star in _stars:
		if star.name == name:
			return star.recipe
	return {}


func has_body(name: String) -> bool:
	for b in _bodies:
		if b.name == name:
			return true
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
	_cloud_layer = CloudLayerScript.new()
	add_child(_cloud_layer)
	_build_air_shell()
	load_system(SystemDB.bodies(SystemDB.SOL))
	_build_star_shell()


# Swap the rendered bodies to a different star system (used on arrival).
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
	stellar_hazard.clear()
	# Samplers are keyed by BODY NAME, so a new system containing a same-named
	# body would otherwise be handed the previous world's terrain.
	_samplers.clear()
	for spec in specs:
		_build_planet(spec)
	var nphys := 0
	for b in _bodies:
		if not b.craft:
			nphys += 1
	if nphys > 0:
		print("[sol cook] %d physical worlds through the generator" % nphys)
		for b in _bodies:
			if str(b.name) == "Moon" or str(b.name) == "Earth" or str(b.name) == "Io":
				print("[sol cook] %s  r=%.1f km  map=%s  parent=%s" % [
					b.name, float(b.radius),
					PlanetGenerator.has_map(b.recipe), str(b.get("parent", ""))])
	_match_sun_sky(specs)
	# reset transient readouts so a stale name doesn't linger one frame
	nearest_name = ""
	nearest_dist = INF


func _build_planet(p: Dictionary) -> void:
	var is_star: bool = p.get("star", false)
	if is_star:
		p = p.duplicate(true)
		var stellar_recipe := StarRecipe.resolve(p)
		p.color = stellar_recipe.color_a

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
	var use_model: bool = p.has("model") and p.get("craft", false)
	if use_model:
		model = _make_glb_body(p)
	if model == null:
		var look := PlanetGenerator.paint(p, float(p.radius))
		sphere = look.sphere
		mat = look.mat
		recipe = look.recipe
		add_child(sphere)

	# Optional flat planetary ring (Saturn). Radial SSS strip on the annulus UV.
	var ring: MeshInstance3D = null
	if p.get("ring", false):
		ring = MeshInstance3D.new()
		ring.mesh = _make_ring_mesh(float(p.radius) * 1.15, float(p.radius) * 2.35, 96)
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
	if sphere != null:
		sphere.basis = eph.surface_basis(str(p.name))
	_bodies.append({
		"name": p.name, "radius": float(p.radius),
		"mass": float(p.get("mass", float(p.radius) * float(p.radius) * 0.05)),   # Earth=1; fallback ~ size
		"craft": is_craft, "drift_vel": drift_vel,
		"pos": craft_pos,                     # craft only: drifts from here
		"star": is_star,                      # the system's primary
		"parent": p.get("parent", ""),        # non-empty => a moon of that body
		"dot": dot, "sphere": sphere, "mat": mat, "model": model, "label": label,
		"ring": ring,
		"sky": _make_body_sky(p, recipe) if not is_star and not is_craft else null,
		"recipe": recipe,
		"mu": eph.gm(str(p.name)),
		"spin": eph.spin_rad_s(str(p.name)),
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
	var vis := 1.0
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
	b.sky.basis = surface_basis(str(b.name)).scaled(Vector3.ONE*r)
	b.sky.position = (rel / dist) * shell
	b.sky.visible = true
	if b.sky.material_override is ShaderMaterial:
		var body_true: Vector3 = b.pos if b.craft else eph.scene_pos(str(b.name))
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


# The sky disc wears the current primary star's photosphere (Sol's is built in
# _build_sun_sky). Arcade systems keep Sol's, as before.
func _match_sun_sky(specs: Array) -> void:
	if _sun_sky == null:
		return
	for spec in specs:
		if spec.get("star", false) and str(spec.name) == eph.primary_star:
			if _sun_sky.get_meta("stellar_recipe", {}) == PlanetGenerator.recipe_for(spec):
				return
			var look := PlanetGenerator.paint(spec, _sun_core_r)
			var old := _sun_sky
			_sun_sky = look.sphere
			_sun_sky.visible = old.visible
			_sun_sky.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			_sun_sky.extra_cull_margin = Ephemeris.SKY_STAR_KM
			if look.mat is ShaderMaterial:
				(look.mat as ShaderMaterial).set_shader_parameter("sky_glow", 1.0)
			add_child(_sun_sky)
			old.queue_free()
			_sun_sky_star = eph.primary_star
			if _sun_corona != null:
				var glare := _sun_corona.material_override as ShaderMaterial
				var tint: Color = look.recipe.stellar.display_color
				glare.set_shader_parameter("tint", Vector3(tint.r,tint.g,tint.b))
				glare.set_shader_parameter("strength", minf(float(look.recipe.stellar.brightness),1.0))
			return


# Named real stars at their TRUE distances — floating-origin destinations you can
# fly to. Far away they read as labelled sky points (clamped); up close they bloom
# into an emissive sphere. Positions/labels update every frame in refresh().
func _build_star_shell() -> void:
	for s in Ephemeris.STARS:
		var id := SystemDB.id_for_name(s.name)
		var spec := {"name":s.name,"star":true,"spectral":SystemDB.spectral(id)}
		var recipe := StarRecipe.resolve(spec)
		var radius := STAR_RADIUS*StarRecipe.scene_radius(recipe)/5.0
		var dot := Sprite3D.new()
		dot.texture = _dot_tex
		dot.modulate = recipe.color_a
		dot.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		dot.shaded = false
		dot.pixel_size = 5.0
		add_child(dot)

		var sphere: MeshInstance3D = null

		var label := Label3D.new()
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.modulate = Color(recipe.color_a, 0.9)
		label.outline_modulate = Color(0, 0, 0, 0.8)
		label.outline_size = 12
		label.font_size = 46
		label.pixel_size = 1.0
		add_child(label)

		_stars.append({
			"name": s.name, "id": id, "recipe": recipe, "radius": radius, "spec": spec,
			"true_pos": eph.star_true_pos(s), "ly": s.ly,
			"mass": float(s.get("mass", 333000.0)),
			"dot": dot, "sphere": sphere, "label": label,
		})


# `ship_off` is the ship's offset from `anchor` in km (docs/adr/0002). With no
# anchor the offset is taken as a position in the current system's frame.
# Everything this writes into `_rel` stays SHIP-relative, so nothing downstream
# (navigator, minimap, HUD, surface band) has to know an anchor exists.
func refresh(ship_off: Vector3, delta: float, anchor := "", ship_vel: Vector3 = Vector3.ZERO) -> void:
	_cloud_time_s += delta
	stellar_hazard = {}
	nearest_dist = INF
	nearest_name = ""
	nearest_radius = 1.0
	cook_n = 0
	cook_mesh_n = 0
	cook_sky_n = 0
	cook_look = ""

	var star_true := _star_true()
	var anchored := anchor != ""
	var ship_pos: Vector3 = _AF.absolute(eph.pos64(anchor), ship_off) if anchored else ship_off
	for b in _bodies:
		var rad: float = b.radius
		var bpos: Vector3
		if b.craft:
			b.pos += b.drift_vel * delta       # Voyagers drift outward forever
			bpos = b.pos
		else:
			bpos = eph.scene_pos(b.name)
		var rel: Vector3 = _rel_to_ship(b, anchored, anchor, ship_off, bpos, ship_pos)
		var dist := rel.length()
		if b.star and b.recipe.has("stellar"):
			var exposure := StarRecipe.exposure(b.recipe, dist, rad)
			if stellar_hazard.is_empty() or float(exposure.flux_w_m2) > float(stellar_hazard.flux_w_m2):
				stellar_hazard = exposure

		b.dot.position = rel
		b.label.position = rel + Vector3(0.0, rad * 1.5 + 0.5, 0.0)
		_rel[b.name] = rel        # for the navigator (render-space position)

		if dist < nearest_dist:
			nearest_dist = dist
			nearest_name = b.name
			nearest_radius = rad

		if b.get("mat") != null and b.mat is ShaderMaterial:
			var to_sun: Vector3 = eph.rel_km(eph.primary_star, str(b.name)) \
				if (anchored and not b.craft and eph.has_pos(str(b.name))) \
				else star_true - bpos
			var alt := dist - rad
			var det := PlanetGenerator.close_detail(alt)
			PlanetGenerator.apply_view(b.mat, to_sun, det, alt, eph.atmo_top_km(str(b.name)))
			PlanetGenerator.set_cloud_drift(b.mat, CloudLayerScript.cloud_uv_offset(_cloud_time_s))
			# Push the globe's cloud_amount only when GameState.cloud_quality
			# actually changed since the last push (cached per body) — see
			# PlanetGenerator.set_cloud_amount's comment for why _cook_material's
			# one-time bind at construction is not enough on its own.
			var wanted_cloud_amount: float = float(_cloud_recipe(b.recipe).get("cloud_amount", 0.0))
			if not is_equal_approx(float(b.get("_pushed_cloud_amount", -1.0)), wanted_cloud_amount):
				PlanetGenerator.set_cloud_amount(b.mat, wanted_cloud_amount)
				b["_pushed_cloud_amount"] = wanted_cloud_amount
			if not b.get("close_maps", false) and PlanetGenerator.close_enough(dist, rad):
				PlanetGenerator.ensure_close_maps(b.mat, b.recipe)
				b.close_maps = true

		# The mesh stays while the near face is inside the far plane. Past that the
		# mesh is clipped, so a sky-shell disc holds the disc. Stars use the same cut.
		var too_far: bool = eph.physical_too_far(dist, rad)
		if not b.craft:
			cook_n += 1
			if too_far:
				cook_sky_n += 1
			else:
				cook_mesh_n += 1
		if b.model != null:
			b.model.visible = not too_far
			if not too_far:
				b.model.position = rel
				b.model.rotate_y(b.spin * delta)
		else:
			b.sphere.position = rel
			b.sphere.basis = eph.surface_basis(str(b.name))
			b.sphere.visible = not too_far
			if b.star:
				StellarStructuresScript.update(b.sphere, atan(rad/maxf(dist, .000001)), not too_far)

		if b.get("sky") != null:
			_place_body_sky(b, rel, dist, too_far)

		# Planetary ring (Saturn): tracks the body while its mesh is on.
		if b.ring != null:
			b.ring.position = rel
			b.ring.visible = not too_far
			if b.ring.visible:
				var rc: Color = b.ring.material_override.albedo_color
				rc.a = 0.6
				b.ring.material_override.albedo_color = rc

		b.dot.visible = false

		if too_far and dist > 0.001:
			var sdir: Vector3 = rel / dist
			b.label.visible = true
			b.label.position = sdir * eph.sky_impostor_km(dist) + Vector3(0.0, 12.0, 0.0)
			b.label.text = "%s\n%s" % [b.name, _fmt_dist_km(dist)]
			var lc: Color = b.label.modulate
			lc.a = 0.85
			b.label.modulate = lc
		else:
			var label_range := maxf(rad * 130.0, 500.0)
			var la := clampf((label_range - dist) / (label_range * 0.3), 0.0, 1.0)
			b.label.visible = la > 0.02
			b.label.text = b.name
			if b.label.visible:
				var lc2: Color = b.label.modulate
				lc2.a = la
				b.label.modulate = lc2

	# Named catalogue stars: sky points in their real direction (clamped to the sky
	# shell), labelled with their real distance.
	for st in _stars:
		# Interstellar scale (~1e13 km): the ship's own magnitude is a rounding
		# error against it, so the anchor buys nothing here and the sky point's
		# precision is bounded by st.true_pos itself either way.
		var srel: Vector3 = st.true_pos - ship_pos
		var sdist := srel.length()
		_rel[st.name] = srel
		if sdist < nearest_dist:
			nearest_dist = sdist
			nearest_name = st.name
			nearest_radius = st.radius
		var sdir: Vector3 = srel.normalized()
		if sdist < STAR_NEAR:
			var exposure := StarRecipe.exposure(st.recipe,sdist,st.radius)
			if stellar_hazard.is_empty() or float(exposure.flux_w_m2) > float(stellar_hazard.flux_w_m2):
				stellar_hazard = exposure
			if st.sphere == null:
				st.sphere = PlanetGenerator.paint(st.spec, st.radius).sphere
				add_child(st.sphere)
			st.sphere.visible = true
			StellarStructuresScript.update(st.sphere, atan(st.radius/maxf(sdist, .000001)), true)
			st.sphere.position = srel
			st.dot.visible = false
			st.label.position = srel + Vector3(0.0, st.radius * 1.6 + 2.0, 0.0)
		else:
			if st.sphere != null:
				st.sphere.queue_free()
				st.sphere = null
			st.dot.visible = true
			var sky: float = Ephemeris.SKY_STAR_KM
			var rd := minf(sdist, sky)
			st.dot.position = sdir * rd
			st.dot.pixel_size = clampf(rd * 0.00000002, 1.5, 7.0)
			st.label.position = sdir * rd + Vector3(0.0, 14.0, 0.0)
		st.label.text = "%s\n%s" % [st.name, _fmt_dist_km(sdist)]

	nearest_dir = _rel.get(nearest_name, Vector3.ZERO).normalized()
	# The nearest body's recipe, picked up here so the skin band below can be
	# driven by the same row the tape reports.
	var near_recipe := {}
	for b in _bodies:
		if str(b.name) != nearest_name:
			continue
		var rec: Dictionary = b.get("recipe", {})
		near_recipe = rec
		var path := "sky" if eph.physical_too_far(nearest_dist, float(b.radius)) else "mesh"
		cook_look = "%s  %s  %s  %s" % [
			str(b.name), path, str(rec.get("source", "?")), str(rec.get("kind", "?"))]
		break
	_place_sun_sky(ship_off, anchor)
	# Skin band: ONE local ground tile, nearest body only, alive between that body's
	# kill line and its own terrain-derived ceiling. Everything it paints comes from
	# `near_recipe`, so the Moon gets lunar crust and not Earth's continents.
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
		if sampler != null and from_centre.length() > 0.001:
			salt = sampler.alt_above_ground_km(from_centre, nearest_radius)
		# Player decision 2026-09-08: no hard speed cap in air at all. Sol
		# speed is Newton + drag only - see NEEDS-YOUR-EYES.md. The band
		# speed cap fold that used to sit here (and its inward-only gate)
		# is removed; FlightMode.band_speed_cap_* is removed alongside it.
		_surface.transform = Transform3D(body_basis, _rel.get(nearest_name, Vector3.ZERO))
		var to_star: Vector3 = (eph.rel_km(eph.primary_star, anchor) if anchored else star_true) \
			- (ship_off + _rel.get(nearest_name, Vector3.ZERO))
		_surface.set_sun_direction(to_star)
		var vel_body: Vector3 = body_basis.inverse() * ship_vel
		_surface.update_for(from_centre, nearest_name, nearest_radius,
			salt, eph.surface_kill_km(nearest_name), ceiling, near_recipe, sampler, vel_body)
		# The coarse globe has a different displacement and pokes through
		# valleys — z-fight flicker, worst as you close in. Hide it when the
		# tile covers the horizon, AND whenever we are low enough that the
		# two surfaces share the view (the reported close-range strobe).
		# Higher up, a lagging tile may not cover the limb yet; keep the
		# globe as the gap fill so the body does not vanish.
		const CLOSE_GLOBE_HIDE_KM := 8.0
		if _surface.visible and _surface.has_ground() \
				and (_surface.covers_horizon(from_centre) or salt < CLOSE_GLOBE_HIDE_KM):
			for b in _bodies:
				if str(b.name) == nearest_name:
					b.sphere.visible = false
		# Light and air. The sun vector is body -> star, exactly what
		# PlanetGenerator.apply_view() hands the globe's material.
		var deck_recipe: Dictionary = _cloud_recipe(near_recipe)
		if _cloud_layer != null:
			_cloud_layer.update_for(_rel.get(nearest_name, Vector3.ZERO), nearest_name,
				nearest_radius, salt, eph.surface_kill_km(nearest_name),
				ceiling, deck_recipe, to_star, _cloud_time_s, body_basis)
		_update_air(to_star, salt, ceiling, deck_recipe, nearest_name, from_centre)


# A body's render-space offset from the ship. Worlds go through Ephemeris.rel_km
# (64-bit); drifting craft stay direct.
func _rel_to_ship(b: Dictionary, anchored: bool, anchor: String, ship_off: Vector3,
		bpos: Vector3, ship_pos: Vector3) -> Vector3:
	if anchored and not b.craft and eph.has_pos(str(b.name)):
		return eph.rel_km(str(b.name), anchor) - ship_off
	return bpos - ship_pos


func surface_basis(body: String) -> Basis:
	return eph.surface_basis(body) if has_body(body) else Basis.IDENTITY


# NAN for a name that is not one of this system's bodies (a catalogue sky star).
func surface_angle(body: String) -> float:
	return eph.surface_angle(body) if has_body(body) else NAN


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


# GameState.cloud_quality index (Off/Light/Full) -> cloud_amount multiplier.
# Player control since clouds are optional: this scales a COPY of the recipe,
# never the shared one, so the deck (CloudLayer reads cloud_amount) and the
# fly-through fog above (coverage_at reads the same recipe) both shrink or
# vanish together under Off/Light. Does not touch the globe's own baked
# material - that cloud_amount is set once at body construction, outside this
# region.
const CLOUD_QUALITY_MULT := [0.0, 0.5, 1.0]

# Pure (no autoload) so tools/test_low_alt_haze.gd can assert the mapping
# headlessly - GameState is unavailable under `--script` (see CLAUDE.md).
static func cloud_recipe_for_quality(recipe: Dictionary, quality_idx: int) -> Dictionary:
	var idx: int = clampi(quality_idx, 0, CLOUD_QUALITY_MULT.size() - 1)
	var mult: float = CLOUD_QUALITY_MULT[idx]
	if mult >= 0.999:
		return recipe
	var scaled: Dictionary = recipe.duplicate()
	scaled["cloud_amount"] = float(recipe.get("cloud_amount", 0.0)) * mult
	return scaled

func _cloud_recipe(recipe: Dictionary) -> Dictionary:
	return cloud_recipe_for_quality(recipe, GameState.cloud_quality)


# Sky, light and haze for the nearest body, every frame. `sun_dir` is the SAME
# vector the globe's own material gets, so the tile's terminator and the globe's
# cannot drift apart at the tile's edge.
func _update_air(sun_dir: Vector3, alt_km: float, ceiling_km: float,
		recipe: Dictionary, body: String, from_centre: Vector3) -> void:
	if _surface != null and _surface.has_method("set_view"):
		# Haze follows the AIR, not the band ceiling: at 30 km there is almost
		# nothing to scatter in, so distant ground has to go clear.
		_surface.set_view(sun_dir, alt_km, eph.atmo_top_km(body))
	if _air_shell == null:
		return
	var air_top: float = eph.atmo_top_km(body)
	var opacity: float = PlanetGenerator.air_shell_opacity(
		alt_km, air_top, float(recipe.get("air_amount", 0.0)))
	if opacity <= 0.001:
		_air_shell.visible = false
		return
	if _air_mat == null or _air_mat.shader != PlanetGenerator.AIR_SHELL_SHADER:
		_air_mat = PlanetGenerator.air_shell_material(recipe, {"spectral": "G"})
		_air_shell.material_override = _air_mat
	_air_shell.visible = true
	var air_color: Color = recipe.get("color_air", Color(0.30, 0.56, 1.0))
	# Flying INTO the deck: no second density curve, just fog the existing air
	# colour/opacity toward white by how deep in the cloud band the ship is and
	# how much cloud actually covers this lon/lat (CloudLayer.coverage_at reads
	# the same texture/cloud_amount the deck itself paints).
	#
	# The band used to ramp over the FULL thickness on each side of cloud_alt_km
	# (dividing by cthick, not cthick/2), so a 3 km-thick deck fogged the air
	# across a 6 km zone - reaching 1 km below the deck's real base. Reported: a
	# 2 km shot under a dense deck read as uniform murk with no clear air below
	# it. Tightened to the deck's actual half-thickness plus a small margin so
	# the ramp starts at the true edge, and zeroes a short distance outside it -
	# "1 km below the base" now measures fog == 0, matching the reference (air
	# under a deck is clear; only INSIDE the deck does it go white).
	if _cloud_layer != null and CloudLayerScript.has_clouds(recipe) \
			and from_centre.length_squared() > 0.0001:
		var calt: float = CloudLayerScript.cloud_alt_km(recipe)
		var half: float = maxf(CloudLayerScript.cloud_thickness_km(recipe), 0.001) * 0.5
		var margin: float = clampf(half * 0.3, 0.1, 1.0)
		var d: float = absf(alt_km - calt)
		var band := clampf((half + margin - d) / margin, 0.0, 1.0)
		if band > 0.0:
			var cov: float = _cloud_layer.coverage_at(from_centre.normalized(), recipe)
			var fog: float = band * cov
			air_color = air_color.lerp(Color(0.94, 0.96, 0.99), fog)
			# Budget: sum never exceeds 1.0 (fully opaque). Fog alone can now reach
			# 1.0 (no *0.9 damping) so being fully immersed in dense cloud is a real
			# white-out, independent of how much sky opacity was already there.
			opacity = clampf(opacity + fog, 0.0, 1.0)
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
	if _cloud_layer != null:
		_cloud_layer.hush()


func _star_true() -> Vector3:
	return eph.scene_pos(eph.primary_star)


func _place_sun_sky(ship_off: Vector3, anchor := "") -> void:
	if _sun_sky == null:
		return
	var star := eph.primary_star
	var star_r := eph.body_radius_km(star)
	var rel: Vector3 = eph.rel_km(star, anchor) - ship_off if anchor != "" \
		else eph.scene_pos(star) - ship_off
	var dist := rel.length()
	if dist < 0.001:
		_sun_sky.visible = false
		StellarStructuresScript.update(_sun_sky, 0.0, false)
		if _sun_corona != null:
			_sun_corona.visible = false
		return
	# Same cut as the cook mesh. Hide the disc only when the ball is on.
	var show_sky: bool = eph.show_sky_impostor(dist, star_r)
	_sun_sky.visible = show_sky
	StellarStructuresScript.update(_sun_sky, atan(star_r/maxf(dist, .000001)), show_sky)
	if _sun_corona != null:
		_sun_corona.visible = show_sky
	if not show_sky:
		return
	var dir: Vector3 = rel / dist
	var shell: float = eph.sky_impostor_km(dist)
	var pos: Vector3 = dir * shell
	var ang: float = atan(star_r / dist)
	var core: float = maxf(shell * tan(ang), 2.0)
	var recipe: Dictionary = _sun_sky.get_meta("stellar_recipe", {})
	if not recipe.is_empty() and (recipe.stellar.visual.wind_nebula or recipe.stellar.visual.debris_disk):
		core = shell * tan(ang)
	_sun_sky.position = pos
	_sun_sky.basis = surface_basis(star).scaled(Vector3.ONE * (core / _sun_core_r))
	if _sun_sky.material_override is ShaderMaterial:
		var sm := _sun_sky.material_override as ShaderMaterial
		PlanetGenerator.apply_view(sm, -pos, 0.0)
		sm.set_shader_parameter("sky_glow", 1.0)
	if _sun_corona != null:
		# Resolved discs already have their recipe's corona; extra point glare washes out detail.
		_sun_corona.visible = ang < .02
		_sun_corona.position = pos
		var corona_ang: float = minf(ang * SUN_CORONA_MULT, SUN_CORONA_MAX_ANG)
		var corona_r: float = maxf(shell * tan(corona_ang), core * 1.6)
		_sun_corona.scale = Vector3.ONE * corona_r
		if pos.length_squared() > 0.001:
			var up := Vector3.UP
			if absf(dir.dot(up)) > 0.95:
				up = Vector3.RIGHT
			_sun_corona.look_at(Vector3.ZERO, up)


# Distance label: light-years when genuinely far, AU in-system, km up close.
func _fmt_dist_km(km: float) -> String:
	var ly := km / Ephemeris.UNITS_PER_LY
	if ly >= 0.05:
		return "%.2f ly" % ly
	var au := km / Ephemeris.AU_TO_UNITS
	if au >= 10.0:
		return "%.1f AU" % au
	if au >= 0.01:
		return "%.2f AU" % au
	return "%.0f km" % km


# Newton pull at an anchor-frame position, summed over every body with mass.
# combat.gd uses it so bolts curve through gravity wells too.
func gravity_at(pos_off: Vector3, anchor := "") -> Vector3:
	var g := Vector3.ZERO
	var anchored := anchor != ""
	var pos: Vector3 = _AF.absolute(eph.pos64(anchor), pos_off) if anchored else pos_off
	for b in _bodies:
		var mu: float = float(b.get("mu", 0.0))
		if mu <= 0.0:
			continue
		var bpos: Vector3 = b.pos if b.craft else eph.scene_pos(b.name)
		var rel: Vector3 = _rel_to_ship(b, anchored, anchor, pos_off, bpos, pos)
		var d := rel.length()
		if d > 0.001:
			g += (rel / d) * (mu / (d * d))
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
