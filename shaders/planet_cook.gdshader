shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_opaque;

#include "res://shaders/planet_color.gdshaderinc"

// One cook. Kind 0 = rocky, 1 = gas, 2 = ice, 3 = star.
// Maps when we have them. Invented land/ocean when we do not.
uniform vec3 color_a : source_color = vec3(0.40, 0.35, 0.28);
uniform vec3 color_b : source_color = vec3(0.55, 0.45, 0.35);
uniform vec3 color_land : source_color = vec3(0.28, 0.38, 0.16);
uniform vec3 color_ocean : source_color = vec3(0.03, 0.09, 0.22);
uniform vec3 color_ice : source_color = vec3(0.86, 0.89, 0.93);
uniform int kind = 0;
uniform float seed = 0.0;
uniform float ice_amount = 0.12;
uniform float land_amount = 0.32;
uniform float cloud_amount = 0.4;
// Drift-only, deterministic sim time from CloudLayer.cloud_uv_offset() via
// PlanetGenerator.set_cloud_drift() (planet_system.gd) — so the globe's own
// cloud pixels and the close-up CloudLayer shell line up at the 35 km
// handoff instead of jumping. Offset only; sample_height()'s own fbm math
// (the no-map fallback, mirrored with PlanetGenerator.crust_height()) is
// untouched — only which UV variable feeds texture() calls changed, below.
uniform vec2 cloud_uv_offset = vec2(0.0, 0.0);
uniform float city_amount = 0.0;
uniform float water_shine = 0.7;
uniform float air_amount = 0.0;
uniform vec3 color_air : source_color = vec3(0.30, 0.56, 1.0);
uniform float band_count = 8.0;
uniform float detail = 0.0;
// The 60 km "glowing wall" (reported 2026-09-09b, earth_alt_60km_all.png): the
// limb term below only faded with `detail` (zero above close_detail()'s
// FAR_KM=35), so from 35 km all the way out to orbit the limb ran at one
// fixed screen-space sharpness — but a fixed pow() exponent in ndotv-space
// maps to a WIDER apparent band the closer the camera sits to the sphere
// (grazing/near-limb geometry covers more of the visible disc from up close),
// so the same "correct at 1.5 R" curve read as a thick cyan wall at 60 km.
// Bound from PlanetGenerator.apply_view()'s new optional args — both default
// to a negative sentinel (unknown/far) so every call site that doesn't pass
// them (the sky-impostor discs, tests) keeps the old unmodified curve.
uniform float ship_alt_km = -1.0;
uniform float atmo_top_km = -1.0;
uniform vec3 sun_dir = vec3(0.72, 0.28, 0.63);
// The day/night terminator, bound from PlanetGenerator.TERMINATOR_* and shared
// with shaders/terrain_tile.gdshader. Was hardcoded as smoothstep(-0.04, 0.28)
// in three places here; the ground tile meets this globe at the tile's own edge,
// so the two must run ONE curve or that seam shows a step in the light.
uniform float term_lo = -0.04;
uniform float term_hi = 0.28;
// Starlight/body-shine on the side facing away from the star, bound from
// PlanetGenerator.NIGHT_FILL and shared with shaders/terrain_tile.gdshader —
// was hardcoded to 0.04 here (a different value from the ring's night_fill),
// so a body's night side changed brightness at the tile/globe seam. Never
// zero: a night side at pure black loses its horizon and reads as a hole.
uniform float night_fill = 0.06;

uniform sampler2D albedo_tex : source_color, hint_default_black, filter_linear_mipmap;
uniform sampler2D cloud_tex : source_color, hint_default_black, filter_linear_mipmap;
uniform sampler2D night_tex : source_color, hint_default_black, filter_linear_mipmap;
uniform sampler2D height_tex : hint_default_black, filter_linear_mipmap;
uniform sampler2D spec_tex : hint_default_black, filter_linear_mipmap;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap;
uniform float has_albedo = 0.0;
uniform float has_clouds = 0.0;
uniform float has_night = 0.0;
uniform float has_height = 0.0;
// Mars/Moon's height maps are stored R=hi/G=lo byte-packed (Godot flattens a
// real 16-bit grayscale PNG to 8-bit on load, tools/probe_dem16.gd) - decode
// value = (R*256+G)/65535 instead of plain .r. Bound from
// PlanetGenerator._cook_material()'s recipe.height_encoding, mirroring
// TerrainSampler._h_stride/_texel() - touch one, touch both.
uniform float height_rg16 = 0.0;
// Where "sea level" (0 m) sits in the raw 0..1 decode, and whether values
// below it are a real signed depth (bathymetry) rather than meaningless.
// Bound from PlanetGenerator._cook_material()'s recipe.height_datum/
// height_signed (PLANET_GENERATOR.md's DEM calibration section). Defaults
// (0.0 / false) reproduce the old constant-based behaviour on any r8/
// mapless body - sample_height()/decode_height() themselves are untouched,
// this only affects "how high above sea level" reads of their result below.
uniform float height_datum = 0.0;
uniform float height_signed = 0.0;
uniform float has_spec = 0.0;
uniform float has_normal = 0.0;
uniform float sky_glow = 0.0;   // far sky disc: never go fully black
uniform float granulation = 1.0;
uniform float storm_strength = 1.0;

varying vec3 v_mdl;
varying vec3 v_world;
varying float v_height;
// Equirectangular UV derived from direction, matching TerrainSampler._dir_uv()
// / CloudLayer._dir_uv() (GDScript) and cloud_layer.gdshader's own vertex() —
// NOT this SphereMesh's built-in UV, whose convention does not match theirs.
// Sampling albedo/height/spec/night/cloud at the mesh-intrinsic UV read a
// different lon/lat than every other consumer of the same textures, so the
// globe showed different ground than the ring/cloud-deck at the same real
// spot. tools/test_globe_ring_uv.gd pins this formula against _dir_uv().
varying vec2 v_map_uv;

// Mirrors CloudLayer.MAP_THRESH_LO/HI + THRESH_SHIFT_LO/HI_MAX (scripts/world/
// cloud_layer.gd) and shaders/cloud_layer.gdshader's identical consts exactly —
// all three must move together on any tuning change (see the cloud sampling
// block in fragment() below for why the globe needed this law at all).
const float CLOUD_MAP_THRESH_LO = 0.28;
const float CLOUD_MAP_THRESH_HI = 0.65;
const float CLOUD_THRESH_SHIFT_LO_MAX = 0.45;
const float CLOUD_THRESH_SHIFT_HI_MAX = 0.25;

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

// Mirrors TerrainSampler._texel() - value = (R*256+G)/65535 for the RG16
// byte-pack, plain .r for Earth's R8 map.
float decode_height(vec2 uv) {
	vec3 texel = texture(height_tex, uv).rgb;
	if (height_rg16 > 0.5) {
		// texel.r/.g are R/G normalized to 0..1 (i.e. R/255, G/255). Raw16 =
		// R*256+G = 255*(256*texel.r + texel.g), and 65535/255 == 257 exactly,
		// so value = raw16/65535 reduces to this without re-multiplying by 255.
		return (texel.r * 256.0 + texel.g) / 257.0;
	}
	return texel.r;
}

float sample_height(vec2 uv, vec3 n) {
	if (has_height > 0.5) {
		return decode_height(uv);
	}
	return fbm(n * 6.0 + seed);
}

float sample_water(vec2 uv, vec3 n, vec3 alb) {
	if (has_spec > 0.5) {
		return texture(spec_tex, uv).r;
	}
	if (has_albedo > 0.5) {
		return smoothstep(0.015, 0.16, alb.b - max(alb.r, alb.g));
	}
	float edge = 1.0 - land_amount;
	float h = fbm(n * 2.1 + seed);
	return 1.0 - smoothstep(edge - 0.05, edge + 0.05, h);
}

void vertex() {
	v_mdl = normalize(VERTEX);
	float lon = atan(v_mdl.z, v_mdl.x);
	float lat = asin(clamp(v_mdl.y, -1.0, 1.0));
	v_map_uv = vec2(lon / TAU + 0.5, 0.5 - lat / PI);
	float h = sample_height(v_map_uv, v_mdl);
	v_height = h;
	float wat = 0.0;
	if (has_spec > 0.5) {
		wat = texture(spec_tex, v_map_uv).r;
	} else if (has_albedo > 0.5) {
		vec3 alb = texture(albedo_tex, v_map_uv).rgb;
		wat = smoothstep(0.015, 0.16, alb.b - max(alb.r, alb.g));
	}
	float land_v = 1.0 - wat;
	// Close-up only: push land up so hills read on the horizon. Units = km.
	// 0.08 is the old unsigned-map floor (kept verbatim on any r8/mapless
	// body); a signed DEM's real sea level is height_datum, not 0.08.
	float sea_v = height_signed > 0.5 ? height_datum : 0.08;
	float disp = max(h - sea_v, 0.0) * land_v * detail * 2.6;
	VERTEX += NORMAL * disp;
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 n = normalize(v_mdl);
	vec3 n_world = normalize((MODEL_MATRIX * vec4(n, 0.0)).xyz);
	vec3 light = normalize(sun_dir);
	float ndotl = dot(n_world, light);
	float day = smoothstep(term_lo, term_hi, ndotl);
	float lat = n.y;
	vec3 alb = (has_albedo > 0.5) ? texture(albedo_tex, v_map_uv).rgb : color_a;
	// Incomplete mosaics (Voyager moons) store unmapped limbs as black.
	// Wrapped on a sphere that is a pacman bite. Fill with recipe crust.
	if (has_albedo > 0.5 && kind != 3) {
		float lum = max(alb.r, max(alb.g, alb.b));
		float hole = 1.0 - smoothstep(0.015, 0.06, lum);
		vec3 fillc = mix(color_a, color_b, fbm(n * 5.0 + seed));
		alb = mix(alb, fillc, hole);
	}
	vec3 view_w0 = normalize(-v_world);
	if (kind == 3) {
		float mu = max(dot(n_world, view_w0), 0.0);
		float limb = 0.18 + 0.82 * pow(mu, 0.55);
		vec3 gp = n * 16.0 + vec3(TIME * 0.045, TIME * -0.032, TIME * 0.021);
		float g1 = fbm(gp);
		float g2 = fbm(gp * 3.2 + vec3(TIME * 0.08, seed, 0.0));
		float cells = clamp(g1 * 0.62 + g2 * 0.38, 0.0, 1.0);
		float fine_cells = noise(n * 160.0 + vec3(TIME * 0.1, seed, -TIME * 0.06));
		cells = mix(0.5, clamp(cells + (fine_cells - 0.5) * 0.40, 0.0, 1.0), granulation);
		vec3 hot = color_a * vec3(1.20, 1.08, 0.72);
		vec3 cool = color_b * vec3(0.78, 0.38, 0.10);
		if (has_albedo > 0.5) {
			hot = mix(alb * vec3(1.25, 1.10, 0.70), hot, 0.22);
			cool = mix(alb * vec3(0.72, 0.36, 0.12), cool, 0.30);
		}
		vec3 phot = mix(cool, hot, cells);
		phot *= 0.62 + 0.70 * cells;
		float flare = smoothstep(0.80, 0.96, fbm(n * 11.0 + vec3(TIME * 0.18, seed * 2.0, 0.0)));
		phot += vec3(1.15, 0.72, 0.22) * flare * 0.55;
		phot *= limb;
		float rim = pow(1.0 - mu, 2.8);
		phot += vec3(1.05, 0.22, 0.04) * rim * 1.65;
		if (sky_glow > 0.01) {
			phot *= 1.0 + 1.15 * sky_glow;
			phot += vec3(1.0, 0.55, 0.12) * rim * sky_glow * 2.4;
		}
		ALBEDO = clamp(phot * 1.85, vec3(0.0), vec3(8.0));
	} else {
	float water = sample_water(v_map_uv, n, alb);
	float land = 1.0 - water;
	float h = v_height;

	vec3 col;
	if (kind == 1) {
		float bands = sin((lat + 0.07 * sin(n.x * 7.0 + seed)) * band_count * 3.14159);
		float storm = fbm(n * 6.0 + seed * 2.0 + vec3(TIME * 0.013, 0.0, -TIME * 0.009));
		col = mix(color_a, color_b, 0.5 + 0.5 * bands);
		col = mix(col, color_a * 0.7, smoothstep(0.62, 0.82, storm) * 0.45);
		if (has_albedo > 0.5) {
			col = alb;
		}
		float eddies = fbm(n * 44.0 + vec3(sin(lat * 15.0) * 2.0 + TIME * 0.025, seed, 0.0));
		col *= 1.0 + storm_strength * ((storm - 0.5) * 0.24 + (eddies - 0.5) * (0.16 + 0.32 * detail));
	} else if (has_albedo > 0.5) {
		col = alb;
		if (kind == KIND_ROCKY) {
			vec3 land_col = land_tint_color(alb);
			vec3 ocean_col = ocean_base_color(alb, color_ocean);
			col = mix(land_col, ocean_col, water);
		}
	} else {
		vec3 dirt = mix(color_land, color_b, fbm(n * 8.0 + seed) * 0.45);
		col = mix(color_ocean, dirt, land);
		float coast = smoothstep(0.0, 0.1, land) * (1.0 - smoothstep(0.08, 0.24, land));
		col = mix(col, vec3(0.52, 0.46, 0.28), coast * 0.7);
		float ice = smoothstep(1.0 - ice_amount, 1.0 - ice_amount * 0.32, abs(lat));
		col = mix(col, color_ice, ice * (0.55 + 0.45 * land));
		if (kind == 2) {
			float crack = smoothstep(0.55, 0.75, fbm(n * 14.0 + seed));
			col = mix(color_ice * 0.82, color_ice, 1.0 - crack * 0.35);
			col = mix(col, color_ocean * 1.2, water * 0.25);
		}
	}

	// Close-up hills: real height + fine noise. Land only.
	if (detail > 0.02 && land > 0.05 && kind != 1) {
		float micro = fbm(n * mix(14.0, 70.0, detail) + seed * 3.0);
		float slope = 0.0;
		if (has_height > 0.5) {
			vec2 e = vec2(0.0012, 0.0);
			float hx = decode_height(v_map_uv + e) - decode_height(v_map_uv - e);
			float hy = decode_height(v_map_uv + e.yx) - decode_height(v_map_uv - e.yx);
			slope = clamp(length(vec2(hx, hy)) * 18.0, 0.0, 1.0);
			n_world = normalize(n_world + detail * land * vec3(hx, hy, 0.0) * 8.0);
		} else {
			float ee = 0.01;
			float hx = fbm(n * 22.0 + vec3(ee, 0.0, 0.0)) - fbm(n * 22.0 - vec3(ee, 0.0, 0.0));
			float hy = fbm(n * 22.0 + vec3(0.0, ee, 0.0)) - fbm(n * 22.0 - vec3(0.0, ee, 0.0));
			slope = clamp(length(vec2(hx, hy)) * 4.0, 0.0, 1.0);
			n_world = normalize(n_world + detail * land * vec3(hx, hy, 0.0) * 1.2);
		}
		if (has_normal > 0.5) {
			vec3 tn = texture(normal_tex, v_map_uv).xyz * 2.0 - 1.0;
			n_world = normalize(n_world + detail * land * tn * 0.45);
		}
		vec3 grass = vec3(0.16, 0.30, 0.09);
		vec3 rock = vec3(0.40, 0.36, 0.32);
		vec3 dirt = vec3(0.38, 0.28, 0.16);
		// "How high above sea level" for the low/high land colour split - a
		// signed DEM's sea level is height_datum, not raw 0.0; datum defaults
		// to 0.0 on any r8/mapless body, so h_land reduces to h unchanged there.
		float h_land = clamp(h - height_datum, 0.0, 1.0);
		vec3 high = mix(col, mix(dirt, color_ice, smoothstep(0.45, 0.75, h_land)), 0.55);
		vec3 low = mix(col, grass, 0.4);
		vec3 hill = mix(low, high, clamp(h_land * 1.4, 0.0, 1.0));
		hill = mix(hill, rock, slope * 0.65);
		col = mix(col, hill, detail * land * 0.72);
		col *= 1.0 + (micro - 0.5) * detail * 0.45;
		ndotl = dot(n_world, light);
		day = smoothstep(term_lo, term_hi, ndotl);
	}

	// Close-up water: waves, depth colour, moving glint.
	if (detail > 0.02 && water > 0.05 && kind != 1) {
		vec3 wp = n * mix(30.0, 220.0, detail) + vec3(TIME * 0.03, 0.0, TIME * 0.02);
		float w1 = fbm(wp);
		float w2 = fbm(wp * 2.8 + vec3(TIME * -0.04, 0.2, 0.0));
		float waves = w1 * 0.62 + w2 * 0.38;
		vec3 deep = color_ocean * 1.15;
		vec3 shallow = vec3(0.07, 0.28, 0.30);
		vec3 foam = vec3(0.78, 0.86, 0.90);
		// Depth below sea level for the deep/shallow tint - water > 0.05 (the
		// mask, not h) is what decided this pixel IS water; a signed DEM's
		// depth is height_datum - h, not 1.0 - h (which assumed unsigned h with
		// sea level pinned at raw 0.0). Unsigned/mapless default (height_signed
		// false) keeps the old 1.0 - h term verbatim.
		float depth_below = height_signed > 0.5 ? clamp(height_datum - h, 0.0, 1.0) : (1.0 - h);
		vec3 wcol = mix(deep, shallow, waves * 0.55 + depth_below * 0.15);
		wcol = mix(wcol, foam, smoothstep(0.72, 0.92, waves) * detail * 0.35);
		col = mix(col, wcol, water * detail);
		float we = 0.006;
		float dwx = fbm(wp + vec3(we, 0.0, 0.0)) - fbm(wp - vec3(we, 0.0, 0.0));
		float dwz = fbm(wp + vec3(0.0, 0.0, we)) - fbm(wp - vec3(0.0, 0.0, we));
		n_world = normalize(n_world + detail * water * vec3(dwx, 0.35, dwz) * 1.6);
		ndotl = dot(n_world, light);
		day = smoothstep(term_lo, term_hi, ndotl);
	}

	// Same coverage law as CloudLayer.coverage_from_raw()/shaders/
	// cloud_layer.gdshader (MAP_THRESH_LO/HI + THRESH_SHIFT_LO/HI_MAX) — the
	// globe used to read the map's raw texel directly with no threshold at
	// all, so it never dimmed with GameState.cloud_quality (player report
	// 2026-09-09b: "far globe ignores the setting") and disagreed with the
	// close-up CloudLayer deck's actual coverage shape. LO only ever moves
	// UP from an already-positive floor as cloud_amount drops, so raw=0
	// still reads coverage=0 for every cloud_amount.
	float cloud = 0.0;
	if (has_clouds > 0.5) {
		float cloud_raw = texture(cloud_tex, v_map_uv + cloud_uv_offset).r;
		float cloud_amt = clamp(cloud_amount, 0.0, 1.0);
		float cloud_lo = clamp(CLOUD_MAP_THRESH_LO + (1.0 - cloud_amt) * CLOUD_THRESH_SHIFT_LO_MAX, 0.0, 0.97);
		float cloud_hi = clamp(max(CLOUD_MAP_THRESH_HI + (1.0 - cloud_amt) * CLOUD_THRESH_SHIFT_HI_MAX, cloud_lo + 0.02), 0.0, 0.999);
		cloud = smoothstep(cloud_lo, cloud_hi, cloud_raw);
	} else if (cloud_amount > 0.01 && kind != 1) {
		// Same centre-shift law as the map-backed branch and CloudLayer's own
		// procedural fallback (PROC_BAND_HALF=0.14 each side, width 0.28) —
		// was a narrower 0.18 here, a second unrelated width the globe alone
		// used, disagreeing with the deck's procedural fallback shape.
		float center = clamp(1.0 - cloud_amount, 0.0, 1.0);
		cloud = smoothstep(center - 0.14, center + 0.14, fbm(n * 3.2 + seed * 2.4));
	}
	cloud *= clamp(cloud_amount, 0.0, 1.0);
	cloud *= 1.0 - detail * 0.7;
	col *= 1.0 - cloud * 0.22 * day;
	col = mix(col, vec3(0.94, 0.96, 0.99), cloud);

	vec3 view_w = normalize(-v_world);
	vec3 halfv = normalize(light + view_w);
	float spec = pow(max(dot(n_world, halfv), 0.0), mix(48.0, 22.0, detail));
	spec *= water * (1.0 - cloud) * water_shine * day;
	spec *= 1.0 + detail * 1.4;

	vec3 night = vec3(0.0);
	if (has_night > 0.5) {
		night = texture(night_tex, v_map_uv).rgb * city_amount;
	} else if (city_amount > 0.01 && land > 0.45) {
		float c = step(0.84, noise(n * 42.0 + seed * 5.0));
		night = vec3(1.0, 0.82, 0.52) * c * city_amount * 0.55;
	}

	// Lit by the real sun angle, not a flat post-terminator floor — the SAME
	// rule terrain_tile.gdshader's `lit` uses (its own comment explains why:
	// a flat floor here flattened hills/slopes past the terminator's edge).
	// A flat 0.16+0.92*day made the globe stay one fixed brightness across the
	// whole day hemisphere regardless of sun angle, while the ring darkened
	// toward the terminator — the two disagreed by up to ~40% at the same spot.
	float ndotl_lit = max(dot(n_world, light), 0.0);
	vec3 day_col = col * (0.18 + 0.82 * ndotl_lit) + vec3(spec);
	vec3 night_col = col * night_fill + night;
	col = mix(night_col, day_col, day);
	if (sky_glow > 0.01) {
		col = max(col, alb * (0.20 + 0.55 * day));
	}

	// Limb is a disc effect. Fade it on the skin so close-up is not a blue wall.
	float air_w = air_amount * (1.0 - smoothstep(0.12, 0.75, detail));
	if (air_w > 0.001) {
		float ndotv = max(dot(n_world, view_w), 0.0);
		// Real atmosphere is a scale-height-thin shell seen edge-on: fine from
		// orbit (small angular size, thin rim regardless of exponent) and fine
		// deep inside close_detail's <35 km band (air_w above already zeroes
		// it there). Between those — 35 km out to a few hundred km, where
		// close_detail() is already 0 but the disc still fills much of the
		// screen — a FIXED pow() exponent in ndotv-space reads as an
		// ever-thicker band because near-limb points subtend more of the
		// visible sphere the closer the camera sits (perspective, not a
		// second density curve). `closeness` follows the same
		// exp(-alt/reference) family PlanetGenerator.air_shell_opacity() uses
		// for the sky's own density, but keyed to atmo_top_km itself (not
		// air_shell_opacity's 8.5 km molecular scale height, which would
		// already be ~0 by 60 km and erase the rim at 1.5 R too) — atmo_top_km
		// is the natural length for "how close is close" here: ~0 well before
		// a body-radii-scale distance (1.5 R), so the far rim this brief says
		// to KEEP is untouched, and ~0.5+ through the 35-150 km zone where the
		// wall was reported, sharpening (not just dimming) the band so its
		// SCREEN-SPACE width shrinks back down with it.
		float closeness = 0.0;
		if (ship_alt_km >= 0.0 && atmo_top_km > 0.0) {
			closeness = exp(-max(ship_alt_km, 0.0) / atmo_top_km);
		}
		float limb_exp = mix(4.6, 20.0, closeness);
		float limb_dim = mix(1.0, 0.3, closeness);
		float limb = pow(1.0 - ndotv, limb_exp);
		float term = exp(-ndotl * ndotl * 10.0) * smoothstep(-0.18, 0.22, ndotl);
		vec3 air = color_air;
		col = mix(col, air, limb * 0.42 * air_w * limb_dim * (0.25 + 0.75 * day));
		col += air * (limb * (0.22 + 1.45 * day) + term * 0.38) * air_w * limb_dim;
	}

	ALBEDO = clamp(col, vec3(0.0), vec3(1.8));
	}
}
