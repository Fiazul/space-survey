class_name CloudLayer
extends Node3D
# The cloud deck the globe's own `cloud_tex`/fbm paint cannot show once the ring
# has replaced the globe (planet_cook.gdshader:256-265 stops drawing the moment
# `_surface.visible` hides the sphere). This shell exists exactly while the ring
# does — CloudLayer.should_show mirrors SurfacePatch.should_show()
# (surface_patch.gd:237) so the handoff at the band ceiling never gaps or
# double-covers. Same floating-origin pattern as PlanetSystem._air_shell
# (planet_system.gd:768-815): body true position minus ship true position, no
# autoload reference held here so this stays testable under plain `--script`.
#
# `cloud_alt_km`/`cloud_thickness_km` are recipe fields with defaults below —
# never a body-name branch. No SurfaceRecipe/RECIPES edit: read with .get().

const SurfacePatchScript := preload("res://scripts/world/surface_patch.gd")
const CLOUD_SHADER := preload("res://shaders/cloud_layer.gdshader")

const DEFAULT_CLOUD_ALT_KM := 9.0
const DEFAULT_THICKNESS_KM := 3.0

# A low-poly SphereMesh's flat facets sag below the true sphere by
# radius*(1-cos(pi/segments)) — at the shipped 48/24, that sagitta is ~13.6 km
# on an Earth-radius shell, deeper than the 3-9 km cloud deck itself. At a
# grazing near-horizon view the facet edge shows as a dead-straight diagonal
# cut through the cloud mass (reported 2026-09-09, clouds_above_20km_r3).
# Size the mesh so the sagitta stays well under the deck's own thickness
# instead of a fixed segment count picked for a coarse rock, not a thin shell.
const MIN_RADIAL_SEGMENTS := 48
const MAX_RADIAL_SEGMENTS := 256
const SAGITTA_FRACTION := 0.25


static func _segments_for(shell_radius_km: float, thickness_km: float) -> int:
	var target_sagitta: float = clampf(thickness_km * SAGITTA_FRACTION, 0.05, 2.0)
	var segs: int = int(ceil(PI * sqrt(shell_radius_km / (2.0 * target_sagitta))))
	return clampi(segs, MIN_RADIAL_SEGMENTS, MAX_RADIAL_SEGMENTS)

var _mesh: MeshInstance3D
var _mat: ShaderMaterial
var _cloud_path := ""
var _cloud_img: Image
var _cloud_w := 0
var _cloud_h := 0
var visible_now := false
var _sim_time_s := 0.0
var _shell_radius_km := 6371.0


func _ready() -> void:
	var mesh := SphereMesh.new()
	mesh.radius = 1.0
	mesh.height = 2.0
	mesh.radial_segments = 48
	mesh.rings = 24
	_mesh = MeshInstance3D.new()
	_mesh.name = "CloudMesh"
	_mesh.mesh = mesh
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mesh.visible = false
	add_child(_mesh)
	_mat = ShaderMaterial.new()
	_mat.shader = CLOUD_SHADER
	_mesh.material_override = _mat


static func cloud_alt_km(recipe: Dictionary) -> float:
	return float(recipe.get("cloud_alt_km", DEFAULT_CLOUD_ALT_KM))


static func cloud_thickness_km(recipe: Dictionary) -> float:
	return float(recipe.get("cloud_thickness_km", DEFAULT_THICKNESS_KM))


static func has_clouds(recipe: Dictionary) -> bool:
	return float(recipe.get("cloud_amount", 0.0)) > 0.01


# Measured (tools' dbg_cover_stats one-off, Earth's real cloud map,
# 2026-09-09): the old 0.10/0.22 gave 66.6% any-cloud / 57.3% dense coverage
# (a paper-white patch reading as near-total once the old linear alpha folded
# it in) against a raw texel mean of 0.278. 0.28/0.65 gives 42.1% any-cloud /
# 24.6% dense — inside the requested 40-55% / 15-25% for a ~60-70%-covered
# real map. Mirrors shaders/cloud_layer.gdshader's MAP_THRESH_LO/HI exactly.
const MAP_THRESH_LO := 0.28
const MAP_THRESH_HI := 0.65

# Player report (2026-09-09b): "too much cloud ... Light was only thinner, not
# fewer." At LO/HI fixed, cloud_amount only ever scaled the FINAL opacity
# (see opacity_from_coverage) — Light and Full covered the identical AREA,
# just at half the alpha, so the deck still read as an unbroken translucent
# sheet. Light must remove clouds, not just fade them: shift the map-backed
# threshold UP as cloud_amount drops, so fewer texels clear it at all — while
# keeping raw=0 -> coverage=0 for every amount (LO only ever moves upward from
# 0.28, never below it, so a genuinely clear texel can never be pushed into
# coverage). Measured against Earth's real map (dbg script, 2026-09-09b):
#   Full (amount=1.0, shift=0):      any 41.2%  dense 24.6%
#   Light (amount=0.5, shift half):  any 20.7%  dense 11.7%  (target ~20/~10)
#   Off (amount=0.0, shift full):    any  6.6%  dense  1.6%  — moot in practice,
#     CLOUD_QUALITY_MULT[0]=0.0 already zeroes cloud_amount so has_clouds()
#     gates the whole deck off and opacity_from_coverage multiplies alpha by
#     0 regardless of area; "Off = no clouds anywhere" holds independent of
#     this shift.
# Mirrors shaders/cloud_layer.gdshader's fragment() and shaders/
# planet_cook.gdshader's cloud sampling identically — all three must move
# together on any tuning change.
const THRESH_SHIFT_LO_MAX := 0.45
const THRESH_SHIFT_HI_MAX := 0.25
const PROC_BAND_HALF := 0.14
const PROC_CENTER_MIN := 0.14
const PROC_CENTER_MAX := 0.86

# Transmittance, not a linear coverage->alpha map: the NASA map is ~60%
# coverage (roughly real), and a direct coverage=alpha reading of it paints
# almost the whole limb opaque. opacity = 1 - exp(-k*density) lets thin wisps
# stay translucent (ground visible through) while only dense cores approach
# the cap — k tuned so a 20 km flyover over the Atlantic sees ocean through
# most of the deck with a few solid cores.
const TRANSMIT_K := 2.0
const OPACITY_CAP := 0.85

# Real zonal wind is ~10-30 m/s => ~0.02-0.05 deg/min of longitude at the
# equator. Rendered at ~5x that so a flyover actually reads as moving weather,
# not a frozen snapshot: 0.15 deg/min.
const DRIFT_DEG_PER_MIN := 0.15
const DRIFT_UV_PER_SEC := (DRIFT_DEG_PER_MIN / 60.0) / 360.0


# Mirrors shaders/cloud_layer.gdshader's fragment() threshold exactly — keep
# both in lockstep on any tuning change. `cloud_amount` shifts the map-backed
# threshold UP as it drops below 1.0 (see coverage_from_raw, THRESH_SHIFT_LO/
# HI_MAX) so Light genuinely covers less AREA, not just fainter alpha — but
# only ever moves LO upward from 0.28, never below it: a 2026-09-08 bug slid
# the centre down by (1.0 - cloud_amount) instead, which put the effective
# threshold at 0 for Earth (cloud_amount 1.0), so a genuinely clear texel
# (raw=0) read back ~0.5 coverage — grey haze over bare desert regardless of
# the map. raw=0 must stay coverage=0 always, for every cloud_amount, on every
# map-backed body — the new shift preserves that by construction (LO strictly
# increases from an already-positive floor).
# Sub-texel detail: same 8/2.5/0.8 km octave stack as shaders/cloud_layer.gdshader's
# detail_field_uv/erode_with_detail, reimplemented in GDScript rather than
# approximated with a FastNoiseLite (a DIFFERENT hash than the shader's would
# desync the fly-through fog from the visible deck by more than a texel).
# hash()/noise() below are a line-for-line port of the shader's — same inputs
# produce the same bit pattern modulo GLSL-vs-GDScript float rounding, so the
# 20-direction parity check in test_cloud_layer.gd measures that rounding only,
# not a second algorithm. Warp/crossfade morph is still NOT mirrored here (per
# the pre-existing comment on coverage_at below) — this only adds the detail
# field on the same unwarped uv the CPU already uses for the raw texel read.
const DETAIL_WAVELEN_KM_0 := 8.0
const DETAIL_WAVELEN_KM_1 := 2.5
const DETAIL_WAVELEN_KM_2 := 0.8
const DETAIL_WEIGHT_0 := 0.55
const DETAIL_WEIGHT_1 := 0.30
const DETAIL_WEIGHT_2 := 0.15
const DETAIL_ERODE_K := 1.2

# Mirrors shaders/cloud_layer.gdshader's detail_band_weight/DETAIL_LIMIT_SAMPLES_*
# exactly (same constants as SurfaceRecipe._band_weight). On the GPU, footprint_km
# comes from fwidth() — a per-pixel screen-space derivative that has no CPU
# equivalent, so this mirror only exists to be called with the caller's own
# measured footprint; the one live caller (coverage_at, ship-local fog) always
# passes 0.0 (footprint effectively zero at the ship's own position) which
# keeps every octave at full weight, same as looking at the deck from up close.
const DETAIL_LIMIT_SAMPLES_MIN := 1.5
const DETAIL_LIMIT_SAMPLES_MAX := 4.0
const DETAIL_MEAN := 0.5


static func _detail_band_weight(wavelength_km: float, footprint_km: float) -> float:
	if footprint_km <= 0.0:
		return 1.0
	return smoothstep(DETAIL_LIMIT_SAMPLES_MIN, DETAIL_LIMIT_SAMPLES_MAX, wavelength_km / footprint_km)


static func _hash3(p: Vector3) -> float:
	var s := sin(p.dot(Vector3(127.1, 311.7, 74.7))) * 43758.5453
	return s - floor(s)


static func _noise3(p: Vector3) -> float:
	var i := p.floor()
	var f := p - i
	f = f * f * (Vector3.ONE * 3.0 - f * 2.0)
	var n000 := _hash3(i)
	var n100 := _hash3(i + Vector3(1.0, 0.0, 0.0))
	var n010 := _hash3(i + Vector3(0.0, 1.0, 0.0))
	var n110 := _hash3(i + Vector3(1.0, 1.0, 0.0))
	var n001 := _hash3(i + Vector3(0.0, 0.0, 1.0))
	var n101 := _hash3(i + Vector3(1.0, 0.0, 1.0))
	var n011 := _hash3(i + Vector3(0.0, 1.0, 1.0))
	var n111 := _hash3(i + Vector3(1.0, 1.0, 1.0))
	var nx00: float = lerp(n000, n100, f.x)
	var nx10: float = lerp(n010, n110, f.x)
	var nx01: float = lerp(n001, n101, f.x)
	var nx11: float = lerp(n011, n111, f.x)
	var ny0: float = lerp(nx00, nx10, f.y)
	var ny1: float = lerp(nx01, nx11, f.y)
	return lerp(ny0, ny1, f.z)


static func detail_field_uv(uv_base: Vector2, circumference_km: float, seed_v: float, footprint_km: float = 0.0) -> float:
	var s0 := circumference_km / DETAIL_WAVELEN_KM_0
	var s1 := circumference_km / DETAIL_WAVELEN_KM_1
	var s2 := circumference_km / DETAIL_WAVELEN_KM_2
	var d0 := _noise3(Vector3(uv_base.x * s0, uv_base.y * s0, seed_v * 1.7))
	var d1 := _noise3(Vector3(uv_base.x * s1, uv_base.y * s1, seed_v * 2.3 + 5.0))
	var d2 := _noise3(Vector3(uv_base.x * s2, uv_base.y * s2, seed_v * 3.1 + 11.0))
	d0 = lerp(DETAIL_MEAN, d0, _detail_band_weight(DETAIL_WAVELEN_KM_0, footprint_km))
	d1 = lerp(DETAIL_MEAN, d1, _detail_band_weight(DETAIL_WAVELEN_KM_1, footprint_km))
	d2 = lerp(DETAIL_MEAN, d2, _detail_band_weight(DETAIL_WAVELEN_KM_2, footprint_km))
	return d0 * DETAIL_WEIGHT_0 + d1 * DETAIL_WEIGHT_1 + d2 * DETAIL_WEIGHT_2


static func erode_with_detail(coverage: float, detail: float) -> float:
	var eroded := coverage - (1.0 - coverage) * DETAIL_ERODE_K * (1.0 - detail)
	return clampf(eroded, 0.0, 1.0)


static func coverage_from_raw(raw: float, cloud_amount: float, has_map: bool) -> float:
	var amt := clampf(cloud_amount, 0.0, 1.0)
	if has_map:
		var lo: float = clampf(MAP_THRESH_LO + (1.0 - amt) * THRESH_SHIFT_LO_MAX, 0.0, 0.97)
		var hi: float = clampf(maxf(MAP_THRESH_HI + (1.0 - amt) * THRESH_SHIFT_HI_MAX, lo + 0.02), 0.0, 0.999)
		return smoothstep(lo, hi, raw)
	var center := clampf(1.0 - amt, PROC_CENTER_MIN, PROC_CENTER_MAX)
	return smoothstep(center - PROC_BAND_HALF, center + PROC_BAND_HALF, raw)


# The transmittance step (item B): coverage (already thresholded, so 0 stays
# 0) drives an exponential opacity curve instead of a direct linear alpha,
# capped below full opacity so even a dense core still reads as cloud, not a
# wall. cloud_amount and the recipe's cloud_opacity both scale here, never the
# threshold — see coverage_from_raw's comment for why that distinction matters.
static func opacity_from_coverage(coverage: float, cloud_amount: float, cloud_opacity: float) -> float:
	# Ramp across the last ~20% of coverage instead of snapping the moment a
	# texel clears the threshold — mirrors the shader's `density` step exactly.
	var density := smoothstep(0.0, 0.8, clampf(coverage, 0.0, 1.0))
	var transmit := 1.0 - exp(-TRANSMIT_K * density)
	return minf(transmit, OPACITY_CAP) * clampf(cloud_amount, 0.0, 1.0) * clampf(cloud_opacity, 0.0, 1.0)


static func cloud_opacity(recipe: Dictionary) -> float:
	return float(recipe.get("cloud_opacity", 1.0))


# Deterministic sim-time drift (not Time.get_ticks/TIME, which is wall-clock
# and would desync the shell from planet_cook's globe clouds and from a
# paused/resumed game). PlanetSystem accumulates sim_time_s from `delta` and
# hands the SAME value to this shell and to the globe's cook material
# (PlanetGenerator.set_cloud_drift) each frame, so the two meet at the 35 km
# handoff instead of jumping. A static so the shader constant and CPU
# coverage_at() (the fly-through fog) read the identical offset.
static func cloud_uv_offset(sim_time_s: float) -> Vector2:
	return Vector2(sim_time_s * DRIFT_UV_PER_SEC, 0.0)


# The gate the ring itself uses (`should_show(...)` is the same call
# planet_system reads through `_surface.visible`), narrowed by whether this
# body's recipe carries any cloud coverage at all — an airless/cloudless rocky
# world (Moon, Mercury) still opens the ring but must not spawn a deck.
static func should_show(body: String, physical: bool, alt_km: float, kill_km: float,
		ceiling_km: float, recipe: Dictionary) -> bool:
	if not has_clouds(recipe):
		return false
	return SurfacePatchScript.should_show(body, physical, alt_km, kill_km, ceiling_km, recipe)


func hush() -> void:
	_mesh.visible = false
	visible_now = false


func update_for(body_pos_rel: Vector3, body: String, physical: bool, radius_km: float,
		alt_km: float, kill_km: float, ceiling_km: float, recipe: Dictionary,
		sun_dir: Vector3, sim_time_s: float) -> void:
	var show := should_show(body, physical, alt_km, kill_km, ceiling_km, recipe)
	visible_now = show
	_mesh.visible = show
	if not show:
		return
	var want_r: float = radius_km + cloud_alt_km(recipe)
	_shell_radius_km = want_r
	var mesh: SphereMesh = _mesh.mesh
	if not is_equal_approx(mesh.radius, want_r):
		mesh.radius = want_r
		mesh.height = want_r * 2.0
		var segs := _segments_for(want_r, cloud_thickness_km(recipe))
		mesh.radial_segments = segs
		mesh.rings = maxi(segs / 2, 8)
	_mesh.position = body_pos_rel
	_bind(recipe)
	_sim_time_s = sim_time_s
	_mat.set_shader_parameter("cloud_amount", float(recipe.get("cloud_amount", 0.0)))
	_mat.set_shader_parameter("cloud_opacity", cloud_opacity(recipe))
	_mat.set_shader_parameter("air_amount", float(recipe.get("air_amount", 0.0)))
	_mat.set_shader_parameter("seed", float(recipe.get("seed", 0.0)))
	_mat.set_shader_parameter("sun_dir", sun_dir.normalized())
	_mat.set_shader_parameter("term_lo", PlanetGenerator.TERMINATOR_LO)
	_mat.set_shader_parameter("term_hi", PlanetGenerator.TERMINATOR_HI)
	_mat.set_shader_parameter("time_s", sim_time_s)
	_mat.set_shader_parameter("uv_offset", cloud_uv_offset(sim_time_s))
	_mat.set_shader_parameter("shell_radius_km", want_r)
	var air_c: Color = recipe.get("color_air", Color(0.30, 0.56, 1.0))
	_mat.set_shader_parameter("color_air", Vector3(air_c.r, air_c.g, air_c.b))


func _bind(recipe: Dictionary) -> void:
	PlanetGenerator._bind_tex(_mat, recipe, "clouds", "cloud_tex", "has_clouds")
	var path := str(recipe.get("clouds", ""))
	if path != _cloud_path:
		_cloud_path = path
		_cloud_img = null
		if not path.is_empty() and ResourceLoader.exists(path):
			var tex := load(path) as Texture2D
			if tex != null:
				var img := tex.get_image()
				if img != null:
					if img.is_compressed():
						img.decompress()
					img.convert(Image.FORMAT_R8)
					_cloud_img = img
					_cloud_w = img.get_width()
					_cloud_h = img.get_height()


# Equirectangular, matching surface_patch._dir_uv()/terrain_sampler._dir_uv().
static func _dir_uv(dir: Vector3) -> Vector2:
	var lon := atan2(dir.z, dir.x)
	var lat := asin(clampf(dir.y, -1.0, 1.0))
	return Vector2(lon / TAU + 0.5, 0.5 - lat / PI)


# CPU-side coverage under a given direction from the body's centre, for the
# in-cloud whiteout (item 2 of the brief): read the SAME texture the shell/globe
# paint, not a second noise curve. Map worlds sample the texel; worlds with only
# the procedural fallback report their flat `cloud_amount` (accurate on average,
# since sampling the shader's fbm on the CPU would be a second implementation of
# the same function to keep in sync — the flat value never drifts from it).
func coverage_at(dir_from_center: Vector3, recipe: Dictionary) -> float:
	if not has_clouds(recipe):
		return 0.0
	var amount: float = clampf(float(recipe.get("cloud_amount", 0.0)), 0.0, 1.0)
	var opac: float = cloud_opacity(recipe)
	if _cloud_img == null or _cloud_w <= 0 or _cloud_h <= 0:
		return opacity_from_coverage(1.0, amount, opac)
	# Same drift the shell shader paints (cloud_uv_offset), so the fly-through
	# fog whites out where the DECK actually is right now, not where the
	# static map alone would place it.
	var uv := _dir_uv(dir_from_center) + cloud_uv_offset(_sim_time_s)
	var x := clampi(int(fposmod(uv.x, 1.0) * float(_cloud_w)), 0, _cloud_w - 1)
	var y := clampi(int(clampf(uv.y, 0.0, 0.999) * float(_cloud_h)), 0, _cloud_h - 1)
	var raw: float = _cloud_img.get_pixel(x, y).r
	var coverage := coverage_from_raw(raw, amount, true)
	# Same erode_with_detail step the shell shader applies to the map-backed
	# branch (uv, not the warped uv_base — see the const block above for why).
	var seed_v: float = float(recipe.get("seed", 0.0))
	var circumference_km := TAU * _shell_radius_km
	var detail := detail_field_uv(uv, circumference_km, seed_v)
	coverage = erode_with_detail(coverage, detail)
	return opacity_from_coverage(coverage, amount, opac)
