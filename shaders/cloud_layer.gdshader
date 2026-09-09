shader_type spatial;
// A cloud deck shell, body-radius + cloud_alt_km, alive only while the terrain
// ring is (CloudLayer.should_show mirrors SurfacePatch.should_show). The globe's
// own cloud_tex/fbm fallback (planet_cook.gdshader) vanishes with the globe at
// the band ceiling; this shell is what covers the gap from there to the ground.
// cull_disabled + FRONT_FACING gives one mesh both looks: sun-lit white tops
// with a shadowed side from above, grey-blue lit-rim underside from below.
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

uniform sampler2D cloud_tex : source_color, hint_default_black, filter_linear_mipmap;
uniform float has_clouds = 0.0;
uniform float cloud_amount = 0.4;
uniform float cloud_opacity = 1.0;
uniform float air_amount = 0.0;
uniform float seed = 0.0;
// Shell radius (body radius + cloud_alt_km), set by CloudLayer.update_for's own
// `want_r` — the ONLY input the detail octaves need to convert a wavelength in
// km into a noise-domain frequency, so a bigger/smaller body's puffs stay
// km-true instead of a fixed screen-space frequency that shrinks with radius.
uniform float shell_radius_km = 6371.0;
uniform vec3 sun_dir = vec3(0.72, 0.28, 0.63);
uniform vec3 color_air : source_color = vec3(0.30, 0.56, 1.0);
uniform float term_lo = -0.04;
uniform float term_hi = 0.28;
// Deterministic sim time (CloudLayer accumulates from `delta`, NOT the
// wall-clock TIME builtin) — planet_system.gd hands the identical value to
// this shell and to the globe's cook material (PlanetGenerator.set_cloud_drift)
// each frame, so the deck and the globe's own clouds meet at the 35 km handoff
// instead of jumping. CloudLayer.cloud_uv_offset() (cloud_layer.gd) mirrors the
// drift part of this on the CPU for the fly-through fog.
uniform float time_s = 0.0;
uniform vec2 uv_offset = vec2(0.0, 0.0);

varying vec3 v_n;
varying vec3 v_world;
varying vec2 v_uv;

float hash(vec3 p) {
	return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453);
}

float noise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float n000 = hash(i);
	float n100 = hash(i + vec3(1.0, 0.0, 0.0));
	float n010 = hash(i + vec3(0.0, 1.0, 0.0));
	float n110 = hash(i + vec3(1.0, 1.0, 0.0));
	float n001 = hash(i + vec3(0.0, 0.0, 1.0));
	float n101 = hash(i + vec3(1.0, 0.0, 1.0));
	float n011 = hash(i + vec3(0.0, 1.0, 1.0));
	float n111 = hash(i + vec3(1.0, 1.0, 1.0));
	float nx00 = mix(n000, n100, f.x);
	float nx10 = mix(n010, n110, f.x);
	float nx01 = mix(n001, n101, f.x);
	float nx11 = mix(n011, n111, f.x);
	return mix(mix(nx00, nx10, f.y), mix(nx01, nx11, f.y), f.z);
}

float fbm(vec3 p) {
	float a = 0.5;
	float s = 0.0;
	for (int i = 0; i < 5; i++) {
		s += a * noise(p);
		p *= 2.07;
		a *= 0.5;
	}
	return s;
}

// Sub-texel detail: a 2k cloud map's texel is ~19.5 km at Earth's equator, so a
// map-backed deck has NO structure between that and the few-hundred-metre scale
// props/terrain already show — read from 20 km up as a smooth blob with blurry
// ~50 km holes (reported 2026-09-09, clouds_above_20km_r4). Real cumulus/strato-
// cumulus has cell structure at 1-10 km and edge detail below 1 km, so three
// octaves are layered UNDER the map/procedural macro shape: 8 km (cell size),
// 2.5 km (puff/gap breakup within a cell), 0.8 km (ragged edge — this replaces
// the old single-scale `edge_n` erosion, which is now just this stack's finest
// term instead of a second, unrelated erosion pass).
//
// Wavelength -> noise frequency is derived from geometry, not tuned by eye:
// - map-backed branch samples in UV space, where one full 0..1 cycle of uv.x
//   is one trip around the equator (TAU * shell_radius_km km) — scale =
//   circumference_km / wavelength_km turns a km wavelength into "cycles per
//   UV unit" directly.
// - procedural branch samples along the unit direction vector `n`; for two
//   points on a unit sphere separated by a small angle theta, chord distance
//   approx= theta and arclength = theta * shell_radius_km, so scaling the
//   direction input by k = shell_radius_km / wavelength_km puts one noise-grid
//   unit at wavelength_km of arclength — the same relationship, just inverted
//   because this branch's domain is already in "radians" rather than "UV".
const float DETAIL_WAVELEN_KM_0 = 8.0;
const float DETAIL_WAVELEN_KM_1 = 2.5;
const float DETAIL_WAVELEN_KM_2 = 0.8;
const float DETAIL_WEIGHT_0 = 0.55;
const float DETAIL_WEIGHT_1 = 0.30;
const float DETAIL_WEIGHT_2 = 0.15;

// Band-limit law: identical shape to SurfaceRecipe._band_weight
// (scripts/world/surface_recipe.gd, DETAIL_LIMIT_SAMPLES_MIN/MAX) — an octave
// needs at least ~1.5 pixel footprints per wavelength to read as anything but
// noise, and ~4 to read clean; between those it fades. `footprint_km` is the
// per-pixel footprint of the sample coordinate (from fwidth, see fragment()),
// the GPU-side equivalent of the ring's mesh-vertex spacing. <=0 means "no
// footprint measured" (the CPU mirror's ship-local fog call) -> full detail,
// matching detail_km<=0 in the terrain law.
const float DETAIL_LIMIT_SAMPLES_MIN = 1.5;
const float DETAIL_LIMIT_SAMPLES_MAX = 4.0;
// noise()'s hash/lerp chain has no bias toward 0 or 1, so its long-run mean is
// 0.5 — fading an octave toward this instead of toward 0 keeps the combined
// field's mean (and therefore erode_with_detail's mean erosion) unchanged as
// the octave drops out with distance, so coverage % doesn't drift when the
// deck is viewed from farther away.
const float DETAIL_MEAN = 0.5;

float detail_band_weight(float wavelength_km, float footprint_km) {
	if (footprint_km <= 0.0) {
		return 1.0;
	}
	return smoothstep(DETAIL_LIMIT_SAMPLES_MIN, DETAIL_LIMIT_SAMPLES_MAX, wavelength_km / footprint_km);
}

float detail_field_uv(vec2 uv_base, float circumference_km, float seed_v, float footprint_km) {
	float s0 = circumference_km / DETAIL_WAVELEN_KM_0;
	float s1 = circumference_km / DETAIL_WAVELEN_KM_1;
	float s2 = circumference_km / DETAIL_WAVELEN_KM_2;
	float d0 = noise(vec3(uv_base * s0, seed_v * 1.7));
	float d1 = noise(vec3(uv_base * s1, seed_v * 2.3 + 5.0));
	float d2 = noise(vec3(uv_base * s2, seed_v * 3.1 + 11.0));
	d0 = mix(DETAIL_MEAN, d0, detail_band_weight(DETAIL_WAVELEN_KM_0, footprint_km));
	d1 = mix(DETAIL_MEAN, d1, detail_band_weight(DETAIL_WAVELEN_KM_1, footprint_km));
	d2 = mix(DETAIL_MEAN, d2, detail_band_weight(DETAIL_WAVELEN_KM_2, footprint_km));
	return d0 * DETAIL_WEIGHT_0 + d1 * DETAIL_WEIGHT_1 + d2 * DETAIL_WEIGHT_2;
}

float detail_field_dir(vec3 dir, float shell_radius_km_v, float t_drift, float seed_v, float footprint_km) {
	float k0 = shell_radius_km_v / DETAIL_WAVELEN_KM_0;
	float k1 = shell_radius_km_v / DETAIL_WAVELEN_KM_1;
	float k2 = shell_radius_km_v / DETAIL_WAVELEN_KM_2;
	vec3 p = dir + vec3(t_drift, 0.0, 0.0);
	float d0 = noise(p * k0 + seed_v * 2.4);
	float d1 = noise(p * k1 + seed_v * 3.1 + 5.0);
	float d2 = noise(p * k2 + seed_v * 4.2 + 11.0);
	d0 = mix(DETAIL_MEAN, d0, detail_band_weight(DETAIL_WAVELEN_KM_0, footprint_km));
	d1 = mix(DETAIL_MEAN, d1, detail_band_weight(DETAIL_WAVELEN_KM_1, footprint_km));
	d2 = mix(DETAIL_MEAN, d2, detail_band_weight(DETAIL_WAVELEN_KM_2, footprint_km));
	return d0 * DETAIL_WEIGHT_0 + d1 * DETAIL_WEIGHT_1 + d2 * DETAIL_WEIGHT_2;
}

// HZD/Schneider-style additive erosion (the brief's stated formula): a texel
// only ever loses coverage relative to the macro field, never gains beyond it,
// and the loss is scaled by (1 - coverage) so a fully-clear texel (coverage=0)
// stays EXACTLY 0 after the clamp below (the negative term clamps away) while a
// marginal texel (coverage near the threshold) can lose almost everything
// except where `detail` is high — scattering it into cells instead of a
// uniform grey wash. A dense texel (coverage near 1) loses almost nothing,
// so it stays "mostly filled" per the brief, with just enough erosion at its
// own partially-covered rim (from the macro smoothstep/edge falloff) to grow
// puffs and gaps there.
const float DETAIL_ERODE_K = 1.2;
// The macro gradient (gx/gy above) is later multiplied by 6.0 in fake_n; the
// detail gradient's raw finite-diff amplitude is comparable (same [0,1]-ish
// noise range) so it gets the same order-of-magnitude weight here rather than
// a second unrelated tuning constant, then the shared *6.0 below applies to both.
const float DETAIL_NORMAL_WEIGHT = 1.0;

float erode_with_detail(float coverage, float detail) {
	float eroded = coverage - (1.0 - coverage) * DETAIL_ERODE_K * (1.0 - detail);
	return clamp(eroded, 0.0, 1.0);
}

void vertex() {
	v_n = normalize(VERTEX);
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	// This mesh is a plain SphereMesh, whose built-in UV convention does NOT
	// match CloudLayer._dir_uv() (GDScript) / SurfacePatch/TerrainSampler's
	// explicit equirect formula that the ring's own custom mesh UVs use — using
	// the mesh-intrinsic UV here read the cloud map at the wrong lon/lat
	// entirely, so a spot the CPU (coverage_at, same formula) reported ~0.85
	// coverage rendered as bare clear sky. Compute the SAME formula here so the
	// shell samples exactly where the CPU fog math says it does.
	float lon = atan(v_n.z, v_n.x);
	float lat = asin(clamp(v_n.y, -1.0, 1.0));
	v_uv = vec2(lon / TAU + 0.5, 0.5 - lat / PI);
}

// LO/HI, erosion amp and the coverage->density ramp are shared by BOTH
// branches below (map-backed and procedural) — every place coverage turns
// into alpha or colour goes through this one pair of steps, not a per-branch
// patch. Measured (tools' dbg_cover_stats, Earth's real map, 2026-09-09):
// old LO/HI 0.10/0.22 gave 66.6% any-cloud / 57.3% dense (a paper-white
// horizon blob is actually near-total coverage once you fold in the old
// linear alpha); new 0.28/0.65 gives 42.1% any-cloud / 24.6% dense, inside
// the requested 40-55% / 15-25% bands for Earth's ~60-70%-covered map.
const float MAP_THRESH_LO = 0.28;
const float MAP_THRESH_HI = 0.65;

// Player report (2026-09-09b): Light quality only faded alpha, never removed
// area — LO/HI above were fixed regardless of cloud_amount. Shift them UP as
// cloud_amount drops so fewer texels clear the threshold at all, mirroring
// CloudLayer.coverage_from_raw()/THRESH_SHIFT_LO_MAX/HI_MAX exactly. LO only
// ever moves upward from an already-positive floor, so raw=0 stays
// coverage=0 for every cloud_amount (same invariant the GDScript mirror's
// comment explains in full).
const float THRESH_SHIFT_LO_MAX = 0.45;
const float THRESH_SHIFT_HI_MAX = 0.25;

void fragment() {
	vec3 n = normalize((MODEL_MATRIX * vec4(v_n, 0.0)).xyz);
	vec3 sun = normalize(sun_dir);

	float raw;
	float coverage;
	// Fake thickness normal: the gradient of coverage across the shell's own
	// UV tangent plane, blended with the true outward normal — a lit side and
	// a shaded side across ONE blob instead of a flat white fill, the same
	// idea as an analytic terrain normal but for cloud "puffiness".
	vec3 east = normalize(cross(vec3(0.0, 1.0, 0.0), n));
	vec3 north = normalize(cross(n, east));
	float gx = 0.0;
	float gy = 0.0;

	if (has_clouds > 0.5) {
		// Advect (uv_offset, deterministic sim time) then MORPH: warp the
		// sample point with slow low-frequency noise and crossfade between two
		// differently-warped reads, so blobs change shape over minutes instead
		// of just sliding as a rigid decal. Warp/crossfade are a visual-only
		// flourish (not mirrored on the CPU side; only the drift is).
		vec2 uv_base = v_uv + uv_offset;
		float t_slow = time_s / 300.0;   // one warp cycle per ~5 sim-minutes
		float warp_amp = (0.75 / 360.0) * 2.0;   // ~0.75 deg of longitude
		vec2 warp_a = (vec2(noise(vec3(v_uv * 6.0, t_slow)),
			noise(vec3(v_uv * 6.0 + 5.0, t_slow))) - 0.5) * warp_amp;
		vec2 warp_b = (vec2(noise(vec3(v_uv * 6.0, t_slow + 7.0)),
			noise(vec3(v_uv * 6.0 + 5.0, t_slow + 7.0))) - 0.5) * warp_amp;
		float cross_w = 0.5 + 0.5 * sin(t_slow * 6.2831853);
		float raw_a = texture(cloud_tex, uv_base + warp_a).r;
		float raw_b = texture(cloud_tex, uv_base + warp_b).r;
		raw = mix(raw_a, raw_b, cross_w);

		float grad_eps = 1.0 / 400.0;
		gx = texture(cloud_tex, uv_base + vec2(grad_eps, 0.0)).r
			- texture(cloud_tex, uv_base - vec2(grad_eps, 0.0)).r;
		gy = texture(cloud_tex, uv_base + vec2(0.0, grad_eps)).r
			- texture(cloud_tex, uv_base - vec2(0.0, grad_eps)).r;

		// The map already encodes real coverage — cloud_amount ALSO shifts LO/HI
		// up as it drops (fewer texels clear the threshold, see the const block
		// above), and cloud_opacity/cloud_amount separately scale the FINAL
		// opacity below (opacity_from_coverage) on top of that. LO only ever
		// moves UPWARD from an already-positive floor, so raw=0 stays
		// coverage=0 for every cloud_amount — the 2026-09-08 bug this guards
		// slid the centre DOWN toward 0 instead, which put the effective
		// threshold at 0 for Earth (cloud_amount 1.0) and read a genuinely
		// clear texel back as nonzero coverage.
		float amt = clamp(cloud_amount, 0.0, 1.0);
		float lo = clamp(MAP_THRESH_LO + (1.0 - amt) * THRESH_SHIFT_LO_MAX, 0.0, 0.97);
		float hi = clamp(max(MAP_THRESH_HI + (1.0 - amt) * THRESH_SHIFT_HI_MAX, lo + 0.02), 0.0, 0.999);
		coverage = smoothstep(lo, hi, raw);

		// Sub-texel detail (8/2.5/0.8 km octaves, see detail_field_uv above),
		// sampled at the SAME uv_base (post drift + warp) as the map read, so
		// the fine structure rides along with the macro shape instead of
		// sliding against it. erode_with_detail replaces the old flat edge_n
		// erosion outright (not stacked alongside it).
		float circumference_km = TAU * shell_radius_km;
		// Per-pixel footprint of uv_base in km: fwidth is the screen-space
		// derivative magnitude of the sample coordinate, the same "how much
		// ground does one pixel cover" quantity the ring's mesh-vertex
		// spacing stands in for on the terrain side. Same footprint feeds
		// every detail_field_uv call below (detail + both gradient probes) so
		// the fade doesn't jitter between the three reads of one pixel.
		float footprint_uv_km = length(fwidth(uv_base)) * circumference_km;
		float detail = detail_field_uv(uv_base, circumference_km, seed, footprint_uv_km);
		coverage = erode_with_detail(coverage, detail);

		// Fold the detail field's own gradient into the fake-thickness normal
		// so a puff gets its own lit/shaded side, not just the macro texel's —
		// step sized to resolve the finest (0.8 km) octave without aliasing.
		// A faded-out octave has already collapsed to its constant mean above,
		// so its finite difference here is naturally ~0 — no separate fade
		// needed for the normal contribution.
		float dg_eps = 0.15 * DETAIL_WAVELEN_KM_2 / circumference_km;
		float dgx = detail_field_uv(uv_base + vec2(dg_eps, 0.0), circumference_km, seed, footprint_uv_km)
			- detail_field_uv(uv_base - vec2(dg_eps, 0.0), circumference_km, seed, footprint_uv_km);
		float dgy = detail_field_uv(uv_base + vec2(0.0, dg_eps), circumference_km, seed, footprint_uv_km)
			- detail_field_uv(uv_base - vec2(0.0, dg_eps), circumference_km, seed, footprint_uv_km);
		gx += dgx * DETAIL_NORMAL_WEIGHT;
		gy += dgy * DETAIL_NORMAL_WEIGHT;
	} else {
		// Mirrors planet_cook.gdshader's fbm fallback (same fbm, same seed) so a
		// procedural world's deck matches the coverage its globe would have shown.
		// No map to encode coverage, so cloud_amount is allowed to move the
		// threshold here — but clamped so it can never collapse to the 0/1 edge
		// and make every texel read as cloud (or none).
		vec3 dp = n * 3.2 + vec3(time_s * 0.004, 0.0, 0.0) + seed * 2.4;
		raw = fbm(dp);
		float center = clamp(1.0 - clamp(cloud_amount, 0.0, 1.0), 0.14, 0.86);
		coverage = smoothstep(center - 0.14, center + 0.14, raw);

		// Analytic gradient of the SAME fbm field along the tangent plane
		// (finite differences), so a procedural world's blobs get the same
		// lit-side/shaded-side puffiness as a map-backed one.
		float ge = 0.05;
		gx = fbm(n * 3.2 + east * ge + vec3(time_s * 0.004, 0.0, 0.0) + seed * 2.4)
			- fbm(n * 3.2 - east * ge + vec3(time_s * 0.004, 0.0, 0.0) + seed * 2.4);
		gy = fbm(n * 3.2 + north * ge + vec3(time_s * 0.004, 0.0, 0.0) + seed * 2.4)
			- fbm(n * 3.2 - north * ge + vec3(time_s * 0.004, 0.0, 0.0) + seed * 2.4);

		// Same km-true octave stack as the map-backed branch (item 3 of the
		// brief: mapless worlds get identical structure, not a second scheme).
		// `dp`'s own drift (time_s * 0.004 along x) is threaded through as
		// detail_field_dir's t_drift so the detail rides with the macro shape.
		// Same footprint idea as the map-backed branch, but the domain here is
		// the unit direction `n`, so shell_radius_km converts fwidth(n)'s
		// radian-ish magnitude into km of arclength (see the header comment
		// on detail_field_dir's k = shell_radius_km/wavelength_km scaling).
		float footprint_dir_km = length(fwidth(n)) * shell_radius_km;
		float detail = detail_field_dir(n, shell_radius_km, time_s * 0.004, seed, footprint_dir_km);
		coverage = erode_with_detail(coverage, detail);

		float ge_detail = 0.15 * DETAIL_WAVELEN_KM_2 / max(shell_radius_km, 1.0);
		float dgx = detail_field_dir(n + east * ge_detail, shell_radius_km, time_s * 0.004, seed, footprint_dir_km)
			- detail_field_dir(n - east * ge_detail, shell_radius_km, time_s * 0.004, seed, footprint_dir_km);
		float dgy = detail_field_dir(n + north * ge_detail, shell_radius_km, time_s * 0.004, seed, footprint_dir_km)
			- detail_field_dir(n - north * ge_detail, shell_radius_km, time_s * 0.004, seed, footprint_dir_km);
		gx += dgx * DETAIL_NORMAL_WEIGHT;
		gy += dgy * DETAIL_NORMAL_WEIGHT;
	}

	vec3 fake_n = normalize(n - east * gx * 6.0 - north * gy * 6.0);
	// Same day/night curve as terrain_tile/planet_cook/air_shell (shared
	// TERMINATOR_LO/HI): a raw clamped dot() stays a dim linear ramp across
	// the whole lit hemisphere, reading as permanently dusk-grey next to
	// ground that's fully saturated bright by the same sun angle.
	float ndotl = smoothstep(term_lo, term_hi, dot(fake_n, sun));
	vec3 to_cam = normalize(CAMERA_POSITION_WORLD - v_world);
	// Silver-lining: looking roughly toward the sun through a thin patch lights
	// the far side of the water/ice droplets, the way a real cloud edge glows.
	float back = pow(clamp(dot(-to_cam, sun), 0.0, 1.0), 3.0);

	float thin = coverage * (1.0 - coverage) * 4.0;   // peaks at a half-covered edge

	vec3 ambient = color_air * 0.16;
	vec3 top_lit = vec3(0.98, 0.98, 1.0);
	vec3 top_shadow = vec3(0.32, 0.34, 0.40);
	vec3 under_lit = vec3(0.38, 0.42, 0.52);
	vec3 under_shadow = vec3(0.05, 0.06, 0.09);

	vec3 col;
	if (FRONT_FACING) {
		col = mix(top_shadow, top_lit, ndotl) + ambient;
	} else {
		col = mix(under_shadow, under_lit, ndotl) + ambient * 0.35;
	}
	col += vec3(1.0, 0.92, 0.78) * back * thin * 1.6;

	// Alpha ramps across the last ~20% of coverage instead of snapping once a
	// texel clears the threshold — then transmittance (not linear coverage
	// =alpha: the NASA map is ~60% coverage, and reading it as a direct alpha
	// painted almost the whole limb opaque). Mirrors
	// CloudLayer.opacity_from_coverage() exactly.
	float density = smoothstep(0.0, 0.8, clamp(coverage, 0.0, 1.0));
	float transmit = min(1.0 - exp(-2.0 * density), 0.85);
	ALBEDO = col;
	ALPHA = transmit * clamp(cloud_amount, 0.0, 1.0) * clamp(cloud_opacity, 0.0, 1.0)
		* clamp(air_amount, 0.0, 1.0) * (FRONT_FACING ? 0.9 : 0.75);
}
