shader_type spatial;
// Pure additive light: cannot darken the background, write depth, or cast shadows.
render_mode unshaded, blend_add, depth_draw_never, shadows_disabled, fog_disabled;
uniform vec4 tint : source_color = vec4(0.8, 0.94, 1.0, 1.0);
uniform float energy = 14.0;
instance uniform float strength = 1.0;
void fragment() {
	ALBEDO = tint.rgb * energy;
	ALPHA = strength;
}
