shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never;
uniform float power = 0.45;
uniform float temperature = 1.0;
uniform float core = 0.0;
varying float axial;
void vertex() {
	float a = clamp((0.00725 - VERTEX.z) / 1.5225, 0.0, 1.0);
	VERTEX.z = 0.00725 - a * 1.5225 * mix(0.35, 1.0, smoothstep(0.0, 0.75, power));
	axial = a;
}
void fragment() {
	float edge = pow(abs(dot(normalize(NORMAL), normalize(VIEW))), 1.4);
	float fade = 1.0 - smoothstep(0.10, 1.0, axial);
	float burn = smoothstep(0.0, 0.75, power);
	vec3 blue = mix(vec3(0.06, 0.25, 0.8), vec3(0.12, 0.65, 1.0), temperature);
	ALBEDO = mix(blue, vec3(0.88, 0.98, 1.0), core * (1.0 - axial * 0.5)) * mix(0.15, 4.0, burn);
	ALPHA = fade * edge * mix(0.32, 0.8, core);
}
