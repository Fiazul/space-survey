shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never;

// Additive plasma torch shared by every ship's authored booster sockets.
//
// Five things carry the effect, all driven from one live `power` value in
// ship.gd::_update_authored_propulsion so the layers can never disagree:
//   1. advected turbulence sampled from the tileable exhaust noise (not sin())
//   2. a shock-diamond train on the core layer only
//   3. a temperature ramp: dull orange at idle -> blue-white at full burn
//   4. throttle-driven length/flare, stretched about the nozzle in the vertex stage
//   5. a soft depth fade so the cone does not cut a hard line into the hull
// Keep the shell visible, but break the rigid cone. Do not floor alpha.
uniform sampler2D noise_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
uniform vec4 edge_color : source_color = vec4(0.22, 0.78, 1.0, 1.0);
// Idle/low-throttle exhaust colour. Combustion runs red-orange until it is hot
// enough to go blue, so a cold engine must not be blue.
uniform vec4 cool_color : source_color = vec4(1.0, 0.33, 0.06, 1.0);
uniform float power : hint_range(0.0, 1.0) = 0.45;
uniform float flow_speed : hint_range(0.0, 6.0) = 1.4;
uniform float brightness : hint_range(0.05, 8.0) = 1.0;
uniform float opacity : hint_range(0.0, 1.0) = 0.8;
uniform float white_mix : hint_range(0.0, 1.0) = 0.96;
uniform float plume_length = 1.0;
uniform float base_radius = 1.0;
uniform float tip_radius = 0.2;
// Live throttle shaping. 1.0 = the authored mesh size.
uniform float length_scale : hint_range(0.05, 3.0) = 1.0;
uniform float flare_scale : hint_range(0.2, 3.0) = 1.0;
// Shock train is a core-layer feature; the outer fog sheath passes 0.0.
uniform float shock_strength : hint_range(0.0, 6.0) = 0.0;
uniform float temperature : hint_range(0.0, 1.0) = 1.0;
uniform float turbulence : hint_range(0.0, 2.0) = 1.0;
// World units over which the plume fades out as it approaches solid geometry.
// 0.0 skips the depth lookup entirely.
uniform float depth_fade = 0.0;

const float INV_TAU = 0.15915494;

varying vec3 local_position;
varying float axial;

// atan() jumps a full turn at the back of the plume. Automatic mip selection reads
// that one-pixel-wide jump as an enormous UV step and drops to the blurriest mip,
// painting a grey seam line down the exhaust. Wrapping the derivative back into a
// single period removes it while keeping proper mipmapping everywhere else.
vec4 flow_sample(vec2 uv) {
	vec2 dx = dFdx(uv);
	vec2 dy = dFdy(uv);
	dx.x = fract(dx.x + 0.5) - 0.5;
	dy.x = fract(dy.x + 0.5) - 0.5;
	return textureGrad(noise_tex, uv, dx, dy);
}

void vertex() {
	float base_y = plume_length * -0.5;
	// Stretch about the nozzle end, never about the centre, so a longer flame keeps
	// its root seated on the authored socket instead of sliding into the hull.
	VERTEX.y = base_y + (VERTEX.y - base_y) * length_scale;
	float a = clamp((VERTEX.y - base_y) / max(plume_length * length_scale, 0.001), 0.0, 1.0);
	float flow = TIME * flow_speed;
	float ang = atan(VERTEX.z, VERTEX.x);
	// Advected silhouette billow: sampling in (angle, axial - flow) space makes the
	// wobble travel downstream instead of standing still on the mesh.
	vec2 buv = vec2(ang * INV_TAU, a * 1.35 - flow * 0.42);
	float billow = textureLod(noise_tex, buv, 0.0).g * 2.0 - 1.0;
	billow += (textureLod(noise_tex, buv * 2.3 + vec2(0.31, 0.17), 0.0).r * 2.0 - 1.0) * 0.5;
	float flare = mix(0.05, 0.30, a) * turbulence;
	float swell = 1.0 + billow * flare;
	VERTEX.x *= swell * flare_scale;
	VERTEX.z *= swell * flare_scale;
	local_position = VERTEX;
	axial = a;
}

void fragment() {
	float a = axial;
	float max_r = mix(base_radius, tip_radius, a) * flare_scale;
	float radial_n = length(vec2(local_position.x, local_position.z)) / max(max_r, 0.001);
	float tip_fade = 1.0 - smoothstep(0.20, 1.0, a);
	float radial_fade = mix(1.0, 0.55, clamp(radial_n, 0.0, 1.0));
	float facing = abs(dot(normalize(NORMAL), normalize(VIEW)));
	float soft_edge = mix(0.06, 1.0, pow(facing, 1.15));
	float flow = TIME * flow_speed;
	float ang = atan(local_position.z, local_position.x);

	vec2 nuv = vec2(ang * INV_TAU, a * 1.9 - flow * 0.55);
	// Domain warp, so the filaments curl and shear instead of running as straight
	// parallel stripes down the cone.
	float warp = flow_sample(nuv * 0.7 + vec2(0.0, flow * 0.11)).b - 0.5;
	vec2 wuv = nuv + vec2(warp * 0.22, warp * 0.34);
	float fine = flow_sample(wuv * 2.1).r;
	float fila = flow_sample(wuv * vec2(1.4, 3.2) + vec2(0.13, -flow * 0.30)).a;
	// Flow leaves the throat laminar and only breaks up downstream, so scale the
	// turbulence in rather than applying it evenly along the whole plume.
	float growth = smoothstep(0.0, 0.55, a);
	float wispy = clamp(0.42
		+ (fine - 0.5) * 1.15 * mix(0.35, 1.0, growth) * turbulence
		+ (fila - 0.35) * 0.75 * growth * turbulence, 0.08, 1.35);

	// Mach disks. Supersonic exhaust forms a repeating shock train past the nozzle:
	// nodes sit on the axis, spacing widens downstream, and the train grows longer
	// as chamber pressure rises. This is the single strongest "real rocket" cue.
	float shock_phase = pow(a, 0.72) * mix(2.2, 6.5, power) * TAU;
	float diamonds = pow(max(sin(shock_phase), 0.0), 7.0);
	diamonds *= (1.0 - smoothstep(0.0, 0.62, radial_n))
		* (1.0 - smoothstep(0.22, 0.80, a));
	diamonds *= shock_strength * smoothstep(0.20, 0.65, power);

	// Hotter gas radiates bluer. Idle burn is a dull orange; full throttle is
	// blue-white. `temperature` is driven from live throttle by ship.gd.
	vec3 fog = mix(cool_color.rgb, edge_color.rgb, smoothstep(0.12, 0.78, temperature));
	vec3 core = mix(fog, vec3(1.0), white_mix);
	vec3 torch_color = mix(core, fog,
		clamp(a * 0.7 + (1.0 - radial_fade) * 0.35, 0.0, 1.0) * (1.0 - white_mix));
	// Shock nodes are the hottest points in the flow.
	torch_color = mix(torch_color, vec3(1.0), clamp(diamonds, 0.0, 1.0));

	// Soft-particle fade. Without it the cone draws a hard intersection line wherever
	// it clips the hull or another plume. depth_fade == 0.0 skips the lookup.
	float near_fade = 1.0;
	if (depth_fade > 0.0) {
		float raw = texture(depth_tex, SCREEN_UV).x;
		vec4 view = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, raw, 1.0);
		view.xyz /= view.w;
		near_fade = clamp((-view.z + VERTEX.z) / depth_fade, 0.0, 1.0);
	}

	float body = clamp(tip_fade * wispy * soft_edge, 0.0, 1.0);
	// READ THIS BEFORE CHANGING ANY NUMBER HERE.
	//
	// `render_mode unshaded` DISCARDS EMISSION. Godot 4 takes ALBEDO as the final
	// colour for an unshaded material and never adds the emission term, so the old
	// mix(480.0, 1920.0, power) - 1632..6528 on the core layer - was dead code that
	// never reached a pixel. Proven twice over: zeroing `brightness` outright and
	// multiplying EMISSION by 100 each move a 960x540 frame's total luminance by well
	// under 1%, while HIDING the plumes removes 40% of all the light in the frame.
	//
	// What actually reached the screen was `ALBEDO * ALPHA` under blend_add: with
	// ALBEDO = torch_color (near white) and ALPHA up to 0.88, each layer laid down
	// most of a white plate, and six sockets x two overlapping cones summed to a slab
	// across the whole tail that no energy tuning could touch.
	//
	// So: ALBEDO carries the HDR value (it goes straight to the rgba16f buffer, values
	// above 1.0 bloom), and `energy` is a real control again.
	//
	// `power` arrives as 0..Ship.POWER_CEIL (0.75), so this ramp spans the throttle
	// properly - it used to arrive as 0.42..1.0, which meant idle already sat three
	// fifths of the way up. Landing points, with the core layer's brightness 3.4:
	//   at rest      0.02 -> 0.07     (a dull ember, not half throttle)
	//   cruise       0.04 -> 0.13
	//   full boost   0.10 -> 0.35     (about where un-boosted cruise used to sit)
	float energy = mix(0.02, 0.20, pow(power, 1.6)) * brightness * (1.0 + diamonds * 2.4);
	ALBEDO = torch_color * energy * body * near_fade;
	EMISSION = vec3(0.0);
	ALPHA = clamp(opacity * body * near_fade, 0.0, 0.88);
}
