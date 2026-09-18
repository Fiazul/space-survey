shader_type spatial;
render_mode blend_mix, depth_prepass_alpha, cull_disabled, diffuse_burley, specular_schlick_ggx;

uniform float power : hint_range(0.0, 1.0) = 0.0;
uniform float temperature : hint_range(0.0, 1.0) = 0.0;
uniform float flow_speed = 1.4;
uniform float brightness = 1.0;

varying vec2 wing_coord;

void vertex() {
	wing_coord = vec2(
		clamp((abs(VERTEX.x) - 0.42218) / (0.94922 - 0.42218), 0.0, 1.0),
		clamp((VERTEX.z + 0.40175) / (0.40175 - 0.003355), 0.0, 1.0));
	VERTEX += NORMAL * 0.0012;
}

void fragment() {
	vec2 p = abs(wing_coord * 2.0 - 1.0);
	float edge_distance = min(1.0 - p.x, 1.0 - p.y);
	float edge = 1.0 - smoothstep(0.035, 0.22, edge_distance);
	float sweep = 0.5 + 0.5 * sin((wing_coord.x * 1.35 - wing_coord.y * 0.42) * 6.28318
		+ TIME * flow_speed * 0.035);
	float fresnel = pow(1.0 - abs(dot(normalize(NORMAL), normalize(VIEW))), 3.0);
	float glass_core = smoothstep(0.04, 0.72, edge_distance) * (0.86 + 0.14 * sweep);
	float heat = mix(0.58, 1.0, max(power, temperature));
	vec3 edge_blue = vec3(0.012, 0.075, 0.19);
	vec3 ice_blue = mix(vec3(0.26, 0.63, 0.96), vec3(0.82, 0.95, 1.0), glass_core);
	float highlight = pow(max(0.0, dot(normalize(NORMAL), normalize(VIEW))), 18.0);
	ALBEDO = mix(ice_blue, edge_blue, max(edge * 0.76, fresnel * 0.46));
	METALLIC = 0.08;
	ROUGHNESS = 0.075;
	SPECULAR = 0.92;
	EMISSION = ice_blue * brightness * heat * (0.16 + glass_core * 0.50)
		+ vec3(0.65, 0.88, 1.0) * highlight * 0.18;
	ALPHA = mix(0.34, 0.54, glass_core) * (1.0 - edge * 0.18);
}
