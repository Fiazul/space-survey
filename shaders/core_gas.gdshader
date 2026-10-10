shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled, skip_vertex_transform;
uniform vec3 observer_ly = vec3(0.0);
uniform bool panorama = false;
varying float strength;
varying float cloud_seed;

float noise(vec2 p) {
	vec2 i = floor(p), f = fract(p);
	f = f*f*(3.0-2.0*f);
	vec4 h = fract(sin(vec4(dot(i,vec2(127.1,311.7)),dot(i+vec2(1,0),vec2(127.1,311.7)),
		dot(i+vec2(0,1),vec2(127.1,311.7)),dot(i+vec2(1,1),vec2(127.1,311.7))))*43758.5453);
	return mix(mix(h.x,h.y,f.x),mix(h.z,h.w,f.x),f.y);
}
void vertex() {
	vec3 offset = VERTEX - observer_ly;
	float d = max(length(offset),.001);
	float render_distance = 512000.0;
	vec3 center = (VIEW_MATRIX * vec4(offset/d*render_distance,1.0)).xyz;
	float extent = min(UV2.x/d, .5)*render_distance;
	VERTEX = center + vec3(UV*extent,0.0);
	POSITION = PROJECTION_MATRIX*vec4(VERTEX,1.0);
	if (panorama) {
		vec3 direction = offset/d;
		vec2 uv = vec2(atan(direction.z,direction.x)/6.28318530718+.5, acos(clamp(direction.y,-1.0,1.0))/3.14159265359);
		float angle = atan(UV2.x/d);
		uv += UV*angle/vec2(6.28318530718*max(length(direction.xz),.05),3.14159265359);
		uv.x += round(COLOR.a*2.0)-1.0;
		vec2 clip = uv*2.0-1.0;
		#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
		clip.y = -clip.y;
		#endif
		POSITION = vec4(clip,.6,1.0);
	} else if (abs(COLOR.a-.5) > .1) {
		POSITION = vec4(2.0,2.0,2.0,1.0);
	}
	strength = smoothstep(UV2.x*.2,UV2.x*2.0,d)*.08;
	cloud_seed = UV2.y;
}
void fragment() {
	float radial = length(UV);
	if (radial > 1.0) discard;
	float clouds = noise(UV*3.0+cloud_seed)*.55 + noise(UV*8.0+cloud_seed)*.3 + noise(UV*19.0+cloud_seed)*.15;
	ALBEDO = COLOR.rgb;
	ALPHA = (1.0-smoothstep(.05,1.0,radial))*pow(clouds,2.0)*strength;
}
