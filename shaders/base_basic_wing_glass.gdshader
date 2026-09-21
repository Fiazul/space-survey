shader_type spatial;
render_mode blend_mix, depth_prepass_alpha, cull_disabled, diffuse_burley, specular_schlick_ggx;

uniform float power : hint_range(0.0, 1.0) = 0.0;
uniform float temperature : hint_range(0.0, 1.0) = 0.0;
uniform float flow_speed = 1.4;
uniform float brightness = 1.0;
// Mesh-local AABB so the same panel language fits wings, fuselage, and canopy.
uniform vec3 aabb_min = vec3(-0.94922, 0.0872, -0.40175);
uniform vec3 aabb_max = vec3(-0.42218, 0.2569, -0.003355);
uniform vec3 hull_tint = vec3(0.42, 0.60, 0.95);
uniform float density = 1.0;

varying vec2 wing_coord;

void vertex() {
	float xmin = min(abs(aabb_min.x), abs(aabb_max.x));
	float xmax = max(abs(aabb_min.x), abs(aabb_max.x));
	if (aabb_min.x < 0.0 && aabb_max.x > 0.0) {
		xmin = 0.0;
	}
	float zspan = max(aabb_max.z - aabb_min.z, 0.0001);
	wing_coord = vec2(
		clamp((abs(VERTEX.x) - xmin) / max(xmax - xmin, 0.0001), 0.0, 1.0),
		clamp((VERTEX.z - aabb_min.z) / zspan, 0.0, 1.0));
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
	vec3 paint = hull_tint;
	vec3 edge_blue = paint * vec3(0.10, 0.14, 0.22);
	vec3 ice_blue = mix(paint * 0.55, mix(paint, vec3(0.92, 0.96, 1.0), 0.38), glass_core);
	float highlight = pow(max(0.0, dot(normalize(NORMAL), normalize(VIEW))), 18.0);
	ALBEDO = mix(ice_blue, edge_blue, max(edge * 0.76, fresnel * 0.46));
	METALLIC = mix(0.08, 0.28, clamp(density - 1.0, 0.0, 1.0));
	ROUGHNESS = mix(0.075, 0.045, clamp(density - 1.0, 0.0, 1.0));
	SPECULAR = 0.92;
	EMISSION = ice_blue * brightness * heat * (0.16 + glass_core * 0.50)
		+ mix(paint, vec3(0.85, 0.92, 1.0), 0.45) * highlight * 0.18;
	ALPHA = clamp(mix(0.34, 0.54, glass_core) * (1.0 - edge * 0.18) * density, 0.0, 0.92);
}
