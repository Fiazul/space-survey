shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;
uniform vec3 tint : source_color = vec3(1.0);
uniform float strength = .3;
uniform float seed = 0.0;
uniform float pulse = 0.0;
void vertex() {
	mat4 billboard = mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	billboard[0].xyz *= length(MODEL_MATRIX[0].xyz);
	billboard[1].xyz *= length(MODEL_MATRIX[1].xyz);
	billboard[2].xyz *= length(MODEL_MATRIX[2].xyz);
	MODELVIEW_MATRIX = VIEW_MATRIX * billboard;
}
void fragment() {
	vec2 p = (UV - .5) * 3.0;
	float r = length(p);
	if (r < 1.0 || r > 1.49) discard;
	float angle = atan(p.y,p.x);
	float streamer = .6 + .4 * pow(.5 + .5 * sin(angle * 13.0 + seed + sin(TIME*.2 + angle*4.0)), 3.0);
	float halo = exp(-(r-1.0)*9.0) * (1.0-smoothstep(1.3,1.49,r));
	float poles = pow(abs(p.y/r), 24.0) * (.7 + .3*sin(TIME*3.0 + seed));
	ALBEDO = tint * halo * strength * (streamer + pulse*poles*2.0);
}
