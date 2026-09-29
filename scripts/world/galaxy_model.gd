class_name GalaxyModel
extends Node3D
# The Milky Way as a real textured model (assets/galaxy.glb, CC-BY 4.0 — see CREDITS.md),
# placed as a distant backdrop toward the real Sgr A* direction. Its materials are made
# unshaded + additive so the spiral reads as glowing light in empty space (there are no
# lights out here). Auto-scaled to a target on-sky size so it doesn't matter what units the
# model shipped in. World-fixed (the ship sits at the origin and only rotates).

const GLB := "res://assets/galaxy.glb"
const DIR := Vector3(-0.0546, -0.4849, -0.8728)   # toward galactic centre (Sgr A*) — IN the plane
const POLE := Vector3(-0.868, 0.456, -0.198)      # galactic north pole = the disc's normal
# Sky-shell backdrop (same order as the starfield). Must stay inside CAM_FAR_SOL.
# TARGET_RADIUS is the glowing DISC radius. It must stay below DIST or the
# camera sits inside the mesh — facing Sgr A* then shows a dark ball.
const DIST := 120000.0
const TARGET_RADIUS := 45000.0
const BRIGHTNESS := 1.0         # edge-on is faint, so keep it up

# --- Voyage to the core (the looming approach) ---
# The real Sun→Sgr A* distance. The galaxy is a fixed backdrop, so to make it actually GROW as
# the Vela Iron Pulse flies the galactic drive toward it, we move the disc's CENTRE from DIST
# (the far backdrop look) in toward the origin as `remaining_ly` shrinks 26000 → 0. The disc
# keeps its physical size (TARGET_RADIUS), so when its centre reaches you the band wraps 360°
# and you're AT the core. CRUCIAL: we never use the real ~1.6e11-unit distance (float32 would
# shatter) — the render distance is a safe, bounded [0, DIST] mapping while the SCANNER still
# reports the true light-years. Nothing drives advance_ly() since the galactic drive left the roster (2026-09-29).
const CORE_LY := 26000.0       # real distance to the galactic centre (the scanner's full reading)
var remaining_ly := CORE_LY    # live distance still to go; CORE_LY = far backdrop, 0 = at the core
var _dir_n := DIR.normalized() # cached core direction (render space)


func _init() -> void:
	# Honest Sol sky: you are inside the disc. The Milky Way is stars (the HYG
	# field), not an outside-in spiral painting. Keep the node for the later
	# core voyage; do not draw it as a backdrop.
	visible = false


func _ready() -> void:
	var ps := load(GLB) as PackedScene
	if ps == null:
		push_warning("GalaxyModel: %s missing/not imported — open the project in the editor once." % GLB)
		return
	var inst := ps.instantiate() as Node3D
	if inst == null:
		push_warning("GalaxyModel: scene root is not Node3D")
		return
	add_child(inst)

	# Collect every MeshInstance, glow-ify its materials, and gather a combined AABB.
	# The GLB ships a huge untextured black sphere (halo/core). Fitted as the
	# longest extent it swallows the camera at DIST — hide it; size the disc only.
	var meshes: Array[MeshInstance3D] = []
	_gather(inst, meshes)
	var mn := Vector3(INF, INF, INF)
	var mx := -mn
	var inv := inst.global_transform.affine_inverse()
	for mi in meshes:
		_glowify(mi)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.extra_cull_margin = 20000.0
		if mi.mesh == null:
			continue
		if not _is_disc(mi):
			mi.visible = false
			continue
		var to_root := inv * mi.global_transform
		var ab := mi.mesh.get_aabb()
		for i in range(8):
			var corner: Vector3 = to_root * (ab.position + ab.size * _CORNER[i])
			mn = mn.min(corner)
			mx = mx.max(corner)

	# Auto-fit: scale so the largest extent matches TARGET_RADIUS, and recentre.
	var size := mx - mn
	var longest: float = maxf(size.x, maxf(size.y, size.z))
	if longest > 0.0001:
		inst.scale = Vector3.ONE * (2.0 * TARGET_RADIUS / longest)
	inst.position = -((mn + mx) * 0.5) * inst.scale.x   # centre the model on this node

	# Physically correct view: lay the disc in the REAL galactic plane (its normal, local +Z,
	# aligned to the galactic pole) with its centre toward Sgr A*. The ship (origin) lies in
	# that plane and inside the disc radius, so the galaxy is seen EDGE-ON — a thin glowing band
	# brightest toward the core — exactly as you'd see it from inside the disc.
	var z := POLE.normalized()
	var x := Vector3.UP.cross(z)
	if x.length() < 0.01:
		x = Vector3.RIGHT.cross(z)
	x = x.normalized()
	var y := z.cross(x).normalized()
	basis = Basis(x, y, z)
	_apply_loom()


# Place the disc centre at the render distance for the current `remaining_ly`. Linear map:
# remaining = CORE_LY → DIST (far backdrop, the normal look); remaining = 0 → origin (you're
# inside the core). Bounded in [0, DIST], so coordinates stay tiny and float-safe the whole way.
func _apply_loom() -> void:
	position = _dir_n * (DIST * remaining_ly / CORE_LY)


# Loom the core in by `ly` light-years this frame (SIGNED: positive = toward the core / looms in,
# negative = flying back out / recedes). Fed by the retired galactic drive, the fixed
# voyage pace — decoupled from the ship's real translation, so true_pos is never moved astronomically.
# Clamped to [0, CORE_LY]; the signed form is what lets you actually LEAVE the core instead of being
# trapped at 0.
func advance_ly(ly: float) -> void:
	remaining_ly = clampf(remaining_ly - ly, 0.0, CORE_LY)
	_apply_loom()


# Snap the backdrop back to its full far distance. main calls this on every system arrival
# (wormhole hop, emergency jump home), since you're then ~26,000 ly from the core again — so
# you never stay wrapped inside the core/clouds after leaving the voyage.
func reset_distance() -> void:
	remaining_ly = CORE_LY
	_apply_loom()


# Scanner readouts (the Iron Pulse's live core-distance gauge, surfaced on the ship + HUD).
func remaining() -> float:
	return remaining_ly

func total() -> float:
	return CORE_LY


const _CORNER := [
	Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, 1),
	Vector3(1, 1, 0), Vector3(1, 0, 1), Vector3(0, 1, 1), Vector3(1, 1, 1),
]


func _is_disc(mi: MeshInstance3D) -> bool:
	if mi.mesh == null:
		return false
	for s in range(mi.mesh.get_surface_count()):
		var src := mi.get_active_material(s)
		if src is BaseMaterial3D and (src as BaseMaterial3D).albedo_texture != null:
			return true
		if src is ShaderMaterial:
			return true
	return false


func _gather(node: Node, out: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D:
		out.append(node)
	for c in node.get_children():
		_gather(c, out)


# Radial-fade shader for the flat disc card: additive glow that fades to ZERO before the
# UV edge, so the low-poly (82-vert) card's straight polygon silhouette never shows as a
# hard "pentagon" outline — the glow ends in a soft round falloff instead.
const DISC_SHADER := """
shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;
uniform sampler2D tex : source_color;
uniform float brightness = 1.0;
uniform float fade_start = 0.2 ;
uniform float fade_end = .98;
void fragment() {
	vec4 c = texture(tex, UV);
	float d = length(UV - vec2(0.5)) * 2.0;      // 0 at centre, 1 at edge-midpoint
	float mask = 1.0 - smoothstep(fade_start, fade_end, d);
	ALBEDO = c.rgb * brightness;
	ALPHA = mask;                                 // additive contribution fades to 0 at the rim
}
"""


# Make a mesh glow. The flat disc card (it has an albedo texture) gets the radial-fade shader
# so its polygon edge disappears. The round core sphere keeps the simple additive path.
func _glowify(mi: MeshInstance3D) -> void:
	var n := mi.mesh.get_surface_count() if mi.mesh != null else 0
	for s in range(n):
		var src := mi.get_active_material(s)

		# Disc card → radial-fade shader (rounds off the polygon silhouette).
		if src is BaseMaterial3D and (src as BaseMaterial3D).albedo_texture != null:
			var b := src as BaseMaterial3D
			var tex := b.emission_texture
			if tex == null:
				tex = b.albedo_texture
			var sh := Shader.new()
			sh.code = DISC_SHADER
			var sm := ShaderMaterial.new()
			sm.shader = sh
			sm.set_shader_parameter("tex", tex)
			sm.set_shader_parameter("brightness", BRIGHTNESS)
			mi.set_surface_override_material(s, sm)
			continue

		var mat: BaseMaterial3D
		if src is BaseMaterial3D:
			mat = (src as BaseMaterial3D).duplicate()
		else:
			mat = StandardMaterial3D.new()
		# The model is authored to GLOW via its emissive texture (black base colour). Respect
		# that — keep it shaded so emission shows, the black albedo stays dark, and the spiral's
		# real colours/structure survive (additive would wash it into a moon-like blob). We only:
		#  - scale the emissive energy by BRIGHTNESS (dim it for the deep/distant look),
		#  - show both faces (cull off) so it reads from any side,
		#  - never cast shadows (the GPU-crash lesson).
		mat.emission_enabled = true
		mat.emission_energy_multiplier = BRIGHTNESS
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		mat.disable_receive_shadows = true
		# ADDITIVE: the spiral lives in an emissive texture on a BLACK, OPAQUE base, so by
		# default the dark disc renders as a solid wall that occludes the starfield behind it
		# ("dark mass behind us" bug). Additive blend makes black contribute nothing (stars
		# show through) while the glowing arms add light — the correct look for a galaxy in
		# space. Stays SHADED (unshaded ignores emission); with no lights out here the black
		# albedo adds ~0, so only the emission shows. Don't write depth (it's a backdrop).
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
		mi.set_surface_override_material(s, mat)
