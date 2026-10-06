shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;
uniform vec3 tint : source_color = vec3(1.0);
uniform float strength=.1;
uniform float seed=1.0;
#include "res://shaders/stellar_depth.gdshaderinc"
void fragment() {
	DEPTH=stellar_depth();
	float limb=pow(1.0-abs(dot(normalize(NORMAL),normalize(VIEW))),2.0);
	float cloud=.5+.25*sin(UV.x*57.0+sin(UV.y*19.0+seed)*3.0)+.15*sin(UV.y*37.0+seed);
	ALBEDO=tint*strength;
	ALPHA=limb*cloud*cloud;
}
