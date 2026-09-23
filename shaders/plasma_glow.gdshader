shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, shadows_disabled;
uniform vec4 tint : source_color = vec4(0.16, 0.55, 1.0, 1.0);
uniform float energy = 3.0;
uniform float axial_length = 0.0;
varying float axial;
void vertex() {
	axial = axial_length > 0.0 ? clamp(VERTEX.y / axial_length + 0.5, 0.0, 1.0) : 1.0;
}
void fragment() {
	float soft_edge = pow(max(dot(normalize(NORMAL), normalize(VIEW)), 0.0), 2.0);
	// A rear chase view sees the wake at grazing incidence. Fresnel-style
	// softening is for the rounded corona; applying it to the wake erases rays.
	if (axial_length > 0.0) {
		soft_edge = 0.7;
	}
	ALBEDO = tint.rgb;
	EMISSION = tint.rgb * energy;
	ALPHA = soft_edge * axial * axial * tint.a;
}
