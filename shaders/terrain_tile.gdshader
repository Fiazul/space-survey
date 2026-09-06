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

varying vec3 v_world_n;


void vertex() {
	// The tile's parent carries translation only (floating origin), so the model
	// normal is already the world normal — but go through MODEL_MATRIX anyway so a
	// future rotation cannot silently break the lighting.
	v_world_n = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
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
		wet = smoothstep(0.35, 0.65, texture(water_tex, UV).r);
	}
	alb = mix(alb, color_ocean, clamp(wet, 0.0, 1.0));
	vec3 n = normalize(v_world_n);
	vec3 l = normalize(sun_dir);
	float day = smoothstep(term_lo, term_hi, dot(n, l));
	float lit = mix(night_fill, 1.0, day);
	vec3 col = alb * lit;

	// VERTEX is the fragment's VIEW-space position, so its length is the distance
	// to the camera in world units — kilometres in Sol.
	float dist_km = length(VERTEX);
	float haze = (1.0 - exp(-dist_km / max(haze_km, 0.001)));
	haze *= air_amount * haze_density;

	// Forward scattering: looking toward the star, the haze goes warm; looking
	// away it stays the air's own colour. This is what makes a horizon read as
	// atmosphere rather than as a grey fog constant.
	vec3 view_w = normalize((INV_VIEW_MATRIX * vec4(normalize(VERTEX), 0.0)).xyz);
	float warmth = pow(max(dot(view_w, l), 0.0), 2.0);
	vec3 haze_col = mix(color_air, sun_warm, warmth);
	// The haze is itself lit. Without this it glows on the night side and the
	// dark hemisphere ends up brighter than the ground it is covering.
	haze_col *= lit;

	ALBEDO = mix(col, haze_col, clamp(haze, 0.0, 1.0));
}
