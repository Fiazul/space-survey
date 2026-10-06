shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;
void fragment(){
	float striation=.55+.25*sin(UV.x*741.0+sin(UV.y*7.0)*2.0)+.20*sin(UV.x*317.0-UV.y*13.0);
	float base=exp(-UV.y*4.5);
	float fade=1.0-smoothstep(.35,1.0,UV.y);
	ALBEDO=vec3(1.5,.07,.008)*(base*.65+striation*.50);
	ALPHA=fade*(.3+striation*.3);
}
