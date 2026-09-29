class_name Starfield
extends MeshInstance3D
# Background star field rendered from a BAKED real-catalogue points mesh — one mesh,
# one draw call, even at a million points. The geometry (positions on a 6000-unit shell,
# per-star colour from real B-V (measured, else spectral type), size from V magnitude)
# is built offline by tools/build_starfield.gd, so the game pays ZERO startup cost.
#
# It lives on the world root and never moves: the ship stays at the origin and only
# rotates, so a fixed shell is a correct parallax-free backdrop (stars are effectively
# infinitely far away).
#
# Quality (potato switch):
#   NAKED (~15.6k pts) = real HYG stars an eye can resolve (mag ≤ 7) — the default.
#   TYCHO (~355k pts)  = Tycho-2 mag ≤ 10. Dense; reads as TV snow. Missing first-magnitude stars.
#   HIGH  (~500k pts)  = real HYG + procedural Milky-Way fill — cinematic.
#   LOW   (~118k pts)  = real HYG only, mag ≤ 12 — accurate, still busy.
# All are one draw call; extra faint points cost fragment/overdraw, not draw calls.

# Quality tier — set this to taste / hardware:
#   "naked" = REAL HYG, mag ≤ 7 (~15.6k, includes Sirius) — default. See STARFIELD.md.
#   "tycho" = REAL Tycho-2, brightest ~355,360 (mag ≤ 10). Incomplete on first-magnitude stars.
#   "high"  = real HYG (~118k) + procedural Milky-Way band (~500k total) — cinematic.
#   "low"   = real HYG only (~118k) — accurate, featherweight (potato).
const QUALITY := "naked"
const MESHES := {
	"naked": "res://assets/starfield_naked.res",
	"tycho": "res://assets/starfield_tycho.res",
	"high": "res://assets/starfield_high.res",
	"low": "res://assets/starfield_low.res",
}

# Per-star SIZE is baked into UV.x; per-star COLOUR (with magnitude baked into its
# intensity) is the vertex colour. A soft round additive glow sells each as a star.
# star_gain scales overall brightness live (no re-bake) — raise/lower if the field is too
# dim or too "busy". The baked colours already encode each star's magnitude.
const STAR_GAIN := 1.0
const STAR_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform float star_gain = 1.0;

void vertex() {
	POINT_SIZE = UV.x;   // baked per-star point size (apparent magnitude)
}

void fragment() {
	float d = distance(POINT_COORD, vec2(0.5));
	float a = smoothstep(0.5, 0.04, d);   // soft round falloff (no hard squares)
	ALBEDO = COLOR.rgb * star_gain;        // real B-V colour, magnitude in its brightness
	ALPHA = a;
}
"""


func _ready() -> void:
	var path: String = MESHES.get(QUALITY, MESHES["naked"])
	var m := load(path) as ArrayMesh
	if m == null:
		push_warning("Starfield: baked mesh missing (%s) — run tools/build_starfield.gd" % path)
		return
	mesh = m

	var sh := Shader.new()
	sh.code = STAR_SHADER
	var smat := ShaderMaterial.new()
	smat.shader = sh
	smat.set_shader_parameter("star_gain", STAR_GAIN)
	# First of the transparent pass: the alpha-blended air shell sits at the same
	# sort depth (both centred on the origin) and must draw over the stars.
	smat.render_priority = Material.RENDER_PRIORITY_MIN
	material_override = smat
	# Baked on a 6000-unit shell; sit behind planet/sun impostors so they occlude.
	var baked_r := 6000.0
	var sky_r: float = Ephemeris.SKY_STAR_KM
	scale = Vector3.ONE * (sky_r / baked_r)
	extra_cull_margin = sky_r * 2.0
