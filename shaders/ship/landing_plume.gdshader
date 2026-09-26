shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;
varying float power;
void vertex() {
	power = INSTANCE_CUSTOM.r;
	VERTEX.y *= power;
}
void fragment() {
	ALBEDO = mix(vec3(1.0,0.85,0.55),vec3(0.25,0.65,1.0),UV.y)*3.0;
	ALPHA = power*(1.0-smoothstep(0.25,1.0,UV.y));
}
