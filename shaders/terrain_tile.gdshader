shader_type spatial;
// Lit, hazed ground for the skin-band rings.
//
// `render_mode unshaded` means GODOT adds no lighting of its own. It does NOT
// mean the terrain is unlit — this shader computes N.L itself from `sun_dir`,
// using the SAME terminator curve planet_cook.gdshader runs (term_lo / term_hi
// are bound to both materials from PlanetGenerator.TERMINATOR_*). That sharing is
// the point: the tile meets the globe at its own outer edge, and a
// Godot-lambert-versus-project-curve mismatch would show up exactly there.
//
// HOUSE RULE: `unshaded` DISCARDS EMISSION. Everything goes on ALBEDO.
render_mode unshaded, cull_back;

uniform vec3 sun_dir = vec3(0.72, 0.28, 0.63);   // body -> star, normalized
uniform float term_lo = -0.04;                   // PlanetGenerator.TERMINATOR_LO
uniform float term_hi = 0.28;                    // PlanetGenerator.TERMINATOR_HI
// Starlight, body-shine and scattered air on the side facing away from the sun.
// Never zero: a night side at pure black loses the horizon and reads as a hole.
uniform float night_fill = 0.06;

// --- Aerial perspective ---
uniform float air_amount = 0.0;                  // 0 = vacuum, no haze at all
uniform vec3 color_air : source_color = vec3(0.30, 0.56, 1.0);
uniform vec3 sun_warm : source_color = vec3(1.00, 0.86, 0.62);
// Distance at which haze reaches 63%. 70 km dissolves ring 3's 204.8 km rim to
// 95% while leaving the first 20 km at 25% — see the spec's swept table.
uniform float haze_km = 70.0;
uniform float haze_density = 1.0;                // thicker the lower you fly

// --- Maps, sampled PER FRAGMENT ---
// The tile used to take its colour entirely from vertex colours, inherited from
// when it was a small unshaded plate. Ring scale now follows the horizon, so at
// 13 km altitude ring 3's quads are 10.24 km across - and a coastline quantised
// to 10 km vertices is a giant hard-edged angular wedge, which is what showed up
// in play. The globe's own shader has always sampled its maps at UV; this one now
// does too, so the shoreline resolves at the MAP's resolution instead of the
// MESH's. COLOR still carries the procedural palette, which supplies the detail
// the 19.5 km-per-texel map has none of.
uniform sampler2D albedo_tex : source_color, hint_default_white, filter_linear;
uniform sampler2D water_tex : hint_default_black, filter_linear;
uniform float has_albedo = 0.0;
uniform float has_water = 0.0;
uniform vec3 color_ocean : source_color = vec3(0.06, 0.22, 0.32);
uniform float map_weight = 0.0;    // how much the map still knows; see TerrainSampler
uniform float body_radius_km = 6371.0;
uniform float rock_amount = 1.0;
uniform float liquid_amount = 0.0;
uniform float lava_amount = 0.0;
uniform float ice_surface = 0.0;
uniform float wave_scale = 1.0;
uniform float surface_seed = 0.0;

varying vec3 v_world_n;
varying vec3 v_radial;
varying float v_height;
varying vec3 v_surface;

float grain_hash(vec3 p) {
	// Keep hash arithmetic bounded: sin(dot(planet_km * frequency, ...))
	// loses precision and produces rectangular discontinuities on large worlds.
	p = fract(p * vec3(0.1031, 0.1030, 0.0973));
	p += dot(p, p.yxz + 33.33);
	return fract((p.x + p.y) * p.z);
}

float grain(vec3 p) {
	vec3 cell = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(grain_hash(cell), grain_hash(cell + vec3(1, 0, 0)), f.x),
		mix(grain_hash(cell + vec3(0, 1, 0)), grain_hash(cell + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(grain_hash(cell + vec3(0, 0, 1)), grain_hash(cell + vec3(1, 0, 1)), f.x),
		mix(grain_hash(cell + vec3(0, 1, 1)), grain_hash(cell + vec3(1, 1, 1)), f.x), f.y), f.z);
}


void vertex() {
	// The tile's parent carries translation only (floating origin), so the model
	// normal is already the world normal — but go through MODEL_MATRIX anyway so a
	// future rotation cannot silently break the lighting.
	v_world_n = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	v_radial = normalize((MODEL_MATRIX * vec4(normalize(VERTEX), 0.0)).xyz);
	v_height = length(VERTEX) - body_radius_km;
	v_surface = VERTEX;
}


void fragment() {
	// Procedural palette from the vertex, then the MAP at this fragment's own UV
	// wherever the map still has information to give.
	vec3 alb = COLOR.rgb;
	if (has_albedo > 0.5 && map_weight > 0.001) {
		alb = mix(alb, texture(albedo_tex, UV).rgb, map_weight);
	}
	// Shoreline from the mask, PER FRAGMENT. COLOR.a carries the vertex-level
	// wetness as the fallback for worlds with no mask.
	float wet = COLOR.a;
	if (has_water > 0.5) {
		wet = smoothstep(0.35, 0.65, texture(water_tex, UV).r) * (1.0 - smoothstep(0.04, 0.32, v_height));
	}
	wet *= liquid_amount;
	alb = mix(alb, color_ocean, clamp(wet, 0.0, 1.0));
	// World-anchored substrate at kilometre and hundred-metre scales. Fade the
	// fine octave when pixels become larger than it, avoiding distant shimmer.
	float footprint = length(fwidth(v_surface));
	float coarse = grain(v_surface * 0.8) - 0.5;
	float fine = (grain(v_surface * 8.0) - 0.5) * (1.0 - smoothstep(0.03, 0.2, footprint));
	alb *= 1.0 + (coarse * 0.22 + fine * 0.12) * (1.0 - wet * 0.7);
	vec3 n = normalize(v_world_n);
	vec3 l = normalize(sun_dir);
	vec3 view_w = normalize((INV_VIEW_MATRIX * vec4(normalize(VERTEX), 0.0)).xyz);
	vec3 radial = normalize(v_radial);
	float slope = 1.0 - clamp(dot(n, radial), 0.0, 1.0);
	vec3 p = v_surface + vec3(surface_seed);
	float rock_fine = grain(p * 32.0);
	float strata = sin(v_height * 110.0 + grain(p * 0.3) * 12.0);
	float exposed = rock_amount * (1.0 - wet) * (1.0 - ice_surface);
	alb *= 1.0 + exposed * (0.13 * strata * smoothstep(0.005, 0.12, slope) + (rock_fine - 0.5) * 0.20);
	// Fractures across frozen ground: no liquid mask or water glint on Europa.
	float crack_noise = grain(p * 0.6) + 0.16 * grain(p * 3.0);
	float crack = (1.0 - smoothstep(0.012, 0.04, abs(crack_noise - 0.56))) * ice_surface;
	alb = mix(alb, vec3(0.19, 0.32, 0.40), crack * 0.65);
	alb = mix(alb, vec3(0.62, 0.76, 0.84), ice_surface * 0.22 * (1.0 - crack));
	// Two travelling wave directions, anchored in body space, perturb highlights.
	vec3 ripple = vec3(sin(p.z * 90.0 * wave_scale + TIME * 1.2),
		cos(p.x * 73.0 * wave_scale - TIME * 0.9), sin(p.y * 83.0 * wave_scale + TIME));
	ripple = (MODEL_MATRIX * vec4(ripple, 0.0)).xyz;
	n = normalize(n + (ripple - radial * dot(ripple, radial)) * wet * 0.09);
	float day = smoothstep(term_lo, term_hi, dot(normalize(v_radial), l));
	// The terminator alone saturates across the entire day side, flattening hills.
	float lit = mix(night_fill, 0.18 + 0.82 * max(dot(n, l), 0.0), day);
	vec3 col = alb * lit;
	float fresnel = pow(1.0 - max(dot(n, -view_w), 0.0), 5.0);
	float glint = pow(max(dot(reflect(-l, n), -view_w), 0.0), 110.0);
	col += wet * day * (vec3(1.0, 0.84, 0.59) * glint * 1.4 + vec3(0.08, 0.16, 0.24) * fresnel);
	// UV2 carries the SAME volcanic regions that generated the caldera geometry.
	float volcanic = clamp(UV2.x * lava_amount, 0.0, 1.0);
	float channels = 1.0 - smoothstep(0.015, 0.055, abs(grain(p * 1.6) + grain(p * 4.0) * 0.2 - 0.58));
	float molten = max(smoothstep(0.975, 0.995, volcanic), channels * smoothstep(0.08, 0.8, volcanic) * 0.8);
	col = mix(col, vec3(0.025, 0.018, 0.014) * lit, volcanic * 0.72);
	float pulse = 0.82 + 0.18 * sin(TIME * 1.7 + grain(p * 3.0) * 9.0);
	col += mix(vec3(1.6, 0.075, 0.003), vec3(3.2, 0.85, 0.035), molten) * molten * pulse;

	// VERTEX is the fragment's VIEW-space position, so its length is the distance
	// to the camera in world units — kilometres in Sol.
	float dist_km = length(VERTEX);
	float haze = (1.0 - exp(-dist_km / max(haze_km, 0.001)));
	haze *= air_amount * haze_density;

	// Forward scattering: looking toward the star, the haze goes warm; looking
	// away it stays the air's own colour. This is what makes a horizon read as
	// atmosphere rather than as a grey fog constant.
	float warmth = pow(max(dot(view_w, l), 0.0), 2.0);
	vec3 haze_col = mix(color_air, sun_warm, warmth);
	// The haze is itself lit. Without this it glows on the night side and the
	// dark hemisphere ends up brighter than the ground it is covering.
	haze_col *= lit;

	ALBEDO = mix(col, haze_col, clamp(haze, 0.0, 1.0));
}
