shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;
uniform vec3 tint : source_color = vec3(1.0,.75,.4);
uniform float strength = 1.0;
uniform float seed = 1.0;
uniform bool closed = false;
uniform bool jet = false;
#include "res://shaders/stellar_depth.gdshaderinc"
void fragment() {
	DEPTH=stellar_depth();
	float edge=pow(abs(dot(normalize(NORMAL),normalize(VIEW))),1.8);
	float waves=.64+.18*sin(UV.y*74.0+seed)+.12*sin(UV.y*193.0-seed);
	float tips=closed ? 1.0 : pow(max(sin(UV.y*3.14159265),0.0),.35);
	float knots=jet ? .4+.6*pow(.5+.5*sin(UV.y*31.0+seed),2.0) : 1.0;
	ALBEDO=tint*strength*waves*knots;
	ALPHA=edge*tips*COLOR.a;
}
