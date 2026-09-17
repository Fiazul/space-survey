shader_type spatial;
render_mode cull_back, depth_draw_opaque, specular_schlick_ggx;

uniform float power : hint_range(0.0, 1.0) = 0.0;
uniform float temperature : hint_range(0.0, 1.0) = 0.0;
uniform float flow_speed = 1.4;
uniform float brightness = 2.0;

void vertex() {
	vec2 p = UV * 2.0 - 1.0;
	float dome = max(0.0, 1.0 - p.x * p.x) * max(0.0, 1.0 - p.y * p.y);
	VERTEX.z += 0.005 * dome;
	NORMAL = normalize(vec3(0.14 * p.x * (1.0 - p.y * p.y),
		-0.31 * p.y * (1.0 - p.x * p.x), 1.0));
}

void fragment() {
	vec2 p = (UV - 0.5) * vec2(2.234375, 1.0);
	vec2 q = abs(p) - vec2(0.9571875, 0.34);
	float boundary = length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0) - 0.16;
	if (boundary > 0.0) {
		discard;
	}
	float depth = smoothstep(0.0, 0.22, -boundary);
	float spread = pow(abs(p.x) / 1.12, 4.0) + pow(abs(p.y) / 0.50, 4.0);
	float core = depth * exp(-1.4 * spread);
	float pulse = 0.985 + 0.015 * sin(TIME * flow_speed);
	vec3 rim = vec3(0.025, 0.18, 0.38);
	vec3 light_color = mix(vec3(0.04, 0.25, 0.60), vec3(0.80, 0.95, 1.0), core);
	float energy = brightness * mix(0.46, 0.72, power) * pulse;
	// A narrow curved reflection keeps the glass legible without a reflection probe.
	float glint = exp(-pow((UV.y - 0.18 - 0.06 * pow(UV.x * 2.0 - 1.0, 2.0)) / 0.026, 2.0));
	glint *= smoothstep(0.02, 0.09, -boundary) * 0.8;
	ALBEDO = mix(rim, vec3(0.12, 0.24, 0.32), depth);
	METALLIC = 0.15;
	ROUGHNESS = 0.12;
	SPECULAR = 0.85;
	EMISSION = light_color * energy * (0.06 + core * 0.94) + vec3(0.7, 0.9, 1.0) * glint;
}
