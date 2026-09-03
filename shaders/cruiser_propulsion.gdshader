shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never;

// Uses only the model's authored propulsion geometry, keeping the exhaust seated
// at the rear. The core never fades out at grazing angles: many authored booster
// meshes are open cylinders whose visible walls are nearly perpendicular to VIEW.
uniform vec4 plasma_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
// Same ramp as cruiser_torch and jazoone_hull_booster: an engine that is barely
// ticking over glows red-orange, a hot one goes blue-white. Without this the authored
// booster patches sat at flat display-clipped white at every throttle setting, which
// is what made the engine bells read as headlights instead of exhaust.
uniform vec4 cool_color : source_color = vec4(1.0, 0.33, 0.06, 1.0);
uniform vec4 hot_color : source_color = vec4(0.30, 0.72, 1.0, 1.0);
uniform float temperature : hint_range(0.0, 1.0) = 1.0;
uniform float power : hint_range(0.0, 1.0) = 0.45;
uniform float flow_speed : hint_range(0.0, 6.0) = 1.4;
uniform float brightness : hint_range(0.5, 4.0) = 4.0;
varying vec3 local_position;

void vertex() {
	local_position = VERTEX;
}

void fragment() {
	float facing = abs(dot(normalize(NORMAL), normalize(VIEW)));
	float edge_softness = smoothstep(0.02, 0.72, facing);
	float visibility = mix(0.58, 1.0, edge_softness);
	float flow = TIME * flow_speed;
	float broad = sin(local_position.x * 0.24 - flow * 2.1 + sin(local_position.y * 0.19 + flow));
	float fine = sin(local_position.z * 0.62 + local_position.x * 0.41 + flow * 4.7);
	float turbulence = clamp(0.72 + broad * 0.16 + fine * 0.12, 0.35, 1.0);
	float shimmer = mix(0.86, 1.12, turbulence);
	// READ THIS BEFORE CHANGING ANY NUMBER HERE.
	//
	// `render_mode unshaded` DISCARDS EMISSION. Godot 4 takes ALBEDO as the final
	// colour for an unshaded material and never adds the emission term, so every
	// "HDR energy" value this shader has ever had was dead code. Proven: multiplying
	// EMISSION by 100 moves a 960x540 frame's total luminance by 0.03%.
	//
	// What actually reached the screen was `ALBEDO * ALPHA` under blend_add, with
	// ALBEDO = vec3(1.0) and an ALPHA floor of 0.45 - a slab of near-solid white per
	// patch that no energy constant could turn down. Several rounds of "the booster is
	// too bright" were spent tuning numbers that did nothing.
	//
	// So: ALBEDO carries the HDR value (it goes straight to the rgba16f buffer, values
	// above 1.0 bloom), and `energy` is a real control again. With brightness 4.0 this
	// peaks around 0.9 before the visibility/alpha falloff.
	// `power` arrives as 0..Ship.POWER_CEIL (0.75). Boost lands near where un-boosted
	// cruise used to sit; cruise itself is now well below it.
	float energy = mix(0.04, 0.26, pow(power, 1.4)) * shimmer * brightness;
	vec3 tint = mix(cool_color.rgb, hot_color.rgb, smoothstep(0.12, 0.78, temperature));
	vec3 white_core = mix(tint * plasma_color.rgb, vec3(1.0), 0.85 * temperature);

	ALBEDO = white_core * energy * visibility;
	EMISSION = vec3(0.0);
	// The old 0.45 floor stopped grazing faces from ever fading, which is what spread
	// the white past the nozzle rim.
	ALPHA = clamp(mix(0.55, 0.85, power) * visibility, 0.06, 0.85);
}
