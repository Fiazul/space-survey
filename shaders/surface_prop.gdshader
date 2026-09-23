shader_type spatial;
render_mode unshaded, cull_back;

uniform vec3 sun_dir = vec3(0.72, 0.28, 0.63);
uniform vec3 color_air : source_color = vec3(0.3, 0.56, 1.0);
uniform float air_amount = 0.0;
uniform float haze_density = 1.0;
uniform float haze_km = 70.0;
uniform float ice_surface = 0.0;
// Same per-body gain as shaders/planet_color.gdshaderinc's `exposure` (bound
// from SurfacePatch.bind_recipe, see PLANET_GENERATOR.md "Exposure") - folded
// into the lit term rather than ALBEDO so a rock doesn't float bright/dark
// against the ground it stands on when the ground's own gain changes.
uniform float exposure : hint_range(1.0, 4.0) = 1.0;
// Streamed plant fade. Default 1 so existing renders are unchanged; a fresh
// ring-0 plant writes 0 and rises over ~0.25 s from SurfacePatch.
uniform float stream_fade : hint_range(0.0, 1.0) = 1.0;
varying vec3 world_normal;
varying vec3 world_up;
varying vec3 local_point;

void vertex() {
	// Combined tree+boulder mesh: INSTANCE_CUSTOM.x picks the part (UV2.x).
	if (abs(UV2.x - INSTANCE_CUSTOM.x) > 0.45) {
		VERTEX = vec3(0.0);
	}
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	world_up = normalize((MODEL_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz);
	local_point = VERTEX;
}

void fragment() {
	vec3 n = normalize(world_normal);
	vec3 up = normalize(world_up);
	float grit = fract(sin(dot(floor(local_point * 95.0), vec3(12.9, 78.2, 41.7))) * 43758.5);
	float seam = 0.5 + 0.5 * sin(local_point.y * 42.0 + sin(local_point.x * 11.0) * 1.5);
	vec3 stone = pow(COLOR.rgb, vec3(2.2)) * (0.78 + 0.18 * grit + 0.12 * seam);
	stone = mix(stone, vec3(0.46, 0.66, 0.76), ice_surface * 0.5);
	vec3 l = normalize(sun_dir);
	// The planet blocks sunlight below the local horizon, including on faces
	// whose normals happen to point toward the Sun through the planet.
	float day = smoothstep(-0.04, 0.28, dot(up, l));
	float ndl = max(dot(n, l), 0.0);
	float sun_term = 0.92 * ndl;
	float sky = air_amount * (0.22 + 0.28 * max(dot(n, up), 0.0));
	float fill = 0.03;
	float lit = (fill + day * (sun_term + sky)) * exposure;
	float haze = clamp((1.0 - exp(-length(VERTEX) / haze_km)) * air_amount * haze_density, 0.0, 1.0);
	ALBEDO = mix(stone * lit, color_air * lit, haze) * stream_fade;
}
