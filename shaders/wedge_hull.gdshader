shader_type spatial;
render_mode cull_disabled;

uniform vec3 design_offset = vec3(0.0);
uniform float wing = 0.0;
uniform float armor = 0.0;
varying vec3 position;
varying vec3 local_normal;

float band(float p, float lo, float hi) {
	float aa = max(fwidth(p), 0.002);
	return smoothstep(lo - aa, lo + aa, p) * (1.0 - smoothstep(hi - aa, hi + aa, p));
}
void vertex() {
	position = VERTEX + design_offset;
	local_normal = NORMAL;
}
void fragment() {
	float x = abs(position.x);
	float z = position.z;
	float top = smoothstep(0.15, 0.65, abs(local_normal.y)) * smoothstep(-0.04, 0.06, position.y);
	vec3 graphite = vec3(0.025, 0.045, 0.064);
	vec3 ceramic = vec3(0.38, 0.48, 0.52);
	vec3 copper = vec3(0.54, 0.20, 0.075);
	// Dark central spine inside a pale, swept ceramic shell.
	float shell = smoothstep(0.30, 0.38, x) * (1.0 - armor);
	vec3 paint = mix(graphite, ceramic, shell * top);
	paint = mix(paint, vec3(0.07, 0.12, 0.15), armor);
	// Paired canopy accents stay on the main hull, clear of raised armor.
	// Mirror the same curve about the centreline rather than crossing panels.
	float arc_x = 0.46 + 0.09 * (z - 0.35) * (z - 0.35);
	float arc_end = smoothstep(-0.45, -0.20, z) * (1.0 - smoothstep(0.95, 1.20, z));
	float arc = (1.0 - smoothstep(0.009, 0.018, abs(x - arc_x))) * arc_end;
	arc *= (1.0 - wing) * (1.0 - armor);
	float wing_accent = band(z + x * 0.32, -1.10, -1.065) * wing;
	wing_accent *= smoothstep(1.85, 2.05, x) * (1.0 - smoothstep(3.15, 3.30, x));
	float accent = max(arc, wing_accent) * top;
	paint = mix(paint, vec3(0.18, 0.62, 0.72), accent);
	// Sparse panel breaks, interrupted at the spine; no repeating noise texture.
	float seam = band(z, -2.36, -2.34) + band(z, -0.72, -0.70) + band(z, 1.55, 1.57);
	seam *= smoothstep(0.42, 0.5, x) * top;
	paint = mix(paint, graphite, clamp(seam, 0.0, 1.0));
	float rail = band(x, 0.395, 0.41) * band(z, -2.3, -0.85) * top * (1.0 - wing);
	// Ventral armor follows the existing surface, rather than floating decals.
	float underside = smoothstep(0.15, 0.65, abs(local_normal.y)) * (1.0 - smoothstep(-0.05, 0.02, position.y));
	float belly_plate = smoothstep(0.28, 0.38, x);
	vec3 belly = mix(graphite, vec3(0.20, 0.29, 0.33), belly_plate);
	belly = mix(belly, ceramic * 0.78, wing);
	float panel_break = band(z, -2.45, -2.42) + band(z, -0.32, -0.29) + band(z, 1.35, 1.38);
	panel_break += band(x, 1.05, 1.075) * band(z, -2.4, 1.35);
	belly = mix(belly, graphite, clamp(panel_break, 0.0, 1.0));
	float chevron = band(x - z * 0.23, 0.10, 0.16) * band(z, 1.45, 3.25);
	float wing_mark = band(z + x * 0.32, -1.2, -1.03) * wing;
	belly = mix(belly, copper, max(chevron, wing_mark));
	// Circular inspection hatch with a thin copper service ring on the keel.
	float hatch_radius = length(vec2(position.x, z + 0.75));
	float hatch = 1.0 - smoothstep(0.40, 0.42, hatch_radius);
	belly = mix(belly, vec3(0.06, 0.10, 0.13), hatch);
	belly = mix(belly, copper, band(hatch_radius, 0.43, 0.445));
	float belly_light = band(x, 0.92, 0.935) * band(z, -2.48, -1.05);
	paint = mix(paint, belly, underside);
	rail += belly_light * underside;
	ALBEDO = paint;
	METALLIC = mix(0.58, 0.28, shell * top);
	ROUGHNESS = mix(0.34, 0.42, shell * top);
	EMISSION = vec3(0.08, 0.55, 0.8) * (rail * 1.8 + accent * 0.35);
}
