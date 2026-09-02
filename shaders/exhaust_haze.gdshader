shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never;

// Screen-space refraction shell wrapped around a booster plume.
//
// Godot 4 needs no SubViewport for this: `hint_screen_texture` hands a transparent
// spatial material the already-composited opaque frame, so the shell can simply
// re-sample it at an offset. Because that copy is taken BEFORE the transparent pass,
// the haze refracts the starfield and the hull but not the plume drawn beside it -
// which is what we want anyway, since a plume refracting itself reads as a glitch.
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform sampler2D noise_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
uniform float power : hint_range(0.0, 1.0) = 0.45;
uniform float flow_speed : hint_range(0.0, 6.0) = 1.4;
// Peak UV displacement in screen space. Keep this small; heat shimmer that reads as
// a lens is worse than none at all.
uniform float strength : hint_range(0.0, 0.08) = 0.018;
uniform float plume_length = 1.0;
uniform float depth_fade = 0.0;

const float INV_TAU = 0.15915494;

varying vec3 local_position;
varying float axial;

vec4 flow_sample(vec2 uv) {
	vec2 dx = dFdx(uv);
	vec2 dy = dFdy(uv);
	dx.x = fract(dx.x + 0.5) - 0.5;
	dy.x = fract(dy.x + 0.5) - 0.5;
	return textureGrad(noise_tex, uv, dx, dy);
}

void vertex() {
	local_position = VERTEX;
	axial = clamp(VERTEX.y / max(plume_length, 0.001) + 0.5, 0.0, 1.0);
}

void fragment() {
	float a = axial;
	float flow = TIME * flow_speed;
	float ang = atan(local_position.z, local_position.x);
	vec2 nuv = vec2(ang * INV_TAU, a * 1.6 - flow * 0.48);
	vec2 shimmer = vec2(
		flow_sample(nuv * 1.7).r,
		flow_sample(nuv * 1.9 + vec2(0.37, 0.11)).b) - 0.5;

	// Strongest just past the throat, gone by the tip; and fade at grazing angles so
	// the shell's own silhouette never becomes a visible outline.
	float along = smoothstep(0.0, 0.16, a) * (1.0 - smoothstep(0.35, 1.0, a));
	float facing = abs(dot(normalize(NORMAL), normalize(VIEW)));
	float mask = along * mix(0.15, 1.0, pow(facing, 1.4)) * smoothstep(0.10, 0.55, power);

	// Same soft-particle guard the torch uses: never refract across a hull edge.
	if (depth_fade > 0.0) {
		float raw = texture(depth_tex, SCREEN_UV).x;
		vec4 view = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, raw, 1.0);
		view.xyz /= view.w;
		mask *= clamp((-view.z + VERTEX.z) / depth_fade, 0.0, 1.0);
	}

	vec2 offset = shimmer * strength * mask;
	ALBEDO = textureLod(screen_tex, clamp(SCREEN_UV + offset, vec2(0.001), vec2(0.999)), 0.0).rgb;
	ALPHA = clamp(mask, 0.0, 1.0);
}
