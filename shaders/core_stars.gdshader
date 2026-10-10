shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled, skip_vertex_transform;

uniform vec3 observer_ly = vec3(0.0);
uniform vec3 pole = vec3(0.0,1.0,0.0);
uniform bool include_physical_points = false;
uniform bool panorama = false;
varying float gain;
varying float extinction;

void vertex() {
	vec3 offset = VERTEX - observer_ly;
	float distance_ly = max(length(offset), 1e-7);
	vec3 middle = mix(observer_ly, VERTEX, .6);
	float height = abs(dot(middle,pole));
	float in_disc = exp(-height/75.0) * exp(-length(middle)/4500.0);
	float lane = .5+.5*sin(dot(middle,vec3(.0027,.009,.0041)) + 2.0*sin(dot(middle,vec3(.008,.003,.001))));
	extinction = exp(-in_disc * lane * min(distance_ly/1800.0, 5.0));
	float flux = UV.x/(distance_ly*distance_ly);
	// Each sample stands for a larger unresolved population; shared enhanced
	// exposure lets its integrated bulge light survive the display tone curve.
	gain = clamp(pow(flux,.25)*6.0, .02, 12.0)*extinction;
	if (!include_physical_points && UV2.x > .5 && length(observer_ly) < 10000.0) gain = 0.0;
	float pixel_radius = UV.y/distance_ly * VIEWPORT_SIZE.y * PROJECTION_MATRIX[1][1];
	POINT_SIZE = clamp(max(pixel_radius*2.0, 1.4+log(1.0+flux)*.24), 1.0, 80.0);
	vec3 shell = offset/distance_ly * min(515000.0, distance_ly * 9.46073e12);
	VERTEX = (VIEW_MATRIX * vec4(shell,1.0)).xyz;
	POSITION = PROJECTION_MATRIX * vec4(VERTEX,1.0);
	if (panorama) {
		POINT_SIZE = clamp(pixel_radius*2.0,.75,2.0);
		vec3 direction = offset/distance_ly;
		vec2 uv = vec2(atan(direction.z,direction.x)/6.28318530718+.5, acos(clamp(direction.y,-1.0,1.0))/3.14159265359);
		vec2 clip = uv*2.0-1.0;
		#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
		clip.y = -clip.y;
		#endif
		POSITION = vec4(clip,.5,1.0);
		if (distance_ly < length(observer_ly)) gain = 0.0;
	}
}

void fragment() {
	if (gain < .0001) discard;
	float radius = length(POINT_COORD-vec2(.5))*2.0;
	if (radius > 1.0) discard;
	ALBEDO = COLOR.rgb * gain;
	ALPHA = exp(-radius*radius*5.0);
}
