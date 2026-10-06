shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled;
uniform float seed=1.0;
#include "res://shaders/stellar_depth.gdshaderinc"
void fragment(){
	DEPTH=stellar_depth();
	float r=UV.x;
	float lanes=.5+.5*sin(r*277.0+sin(r*71.0)*2.0+sin(UV.y*35.0+seed)*.6);
	float fine=.5+.5*sin(r*821.0+sin(UV.y*97.0)*.7);
	float dust=.68+.20*sin(UV.y*57.0+r*117.0)+.12*sin(UV.y*217.0-r*71.0);
	float gaps=1.0-.65*exp(-pow((r-.57)/.023,2.0));
	float edge=smoothstep(0.0,.04,r)*(1.0-smoothstep(.84,1.0,r));
	vec3 inner=vec3(.77,.32,.12),outer=vec3(.18,.13,.10);
	ALBEDO=mix(inner,outer,pow(r,.48))*(.58+lanes*.37+fine*.12)*dust;
	ALPHA=edge*gaps*(.55+lanes*.27+fine*.13);
}
