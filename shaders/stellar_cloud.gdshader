shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;
uniform vec3 tint : source_color = vec3(.27,.58,.95);
uniform float strength = 1.6;
uniform float seed = 1.0;
uniform float cloud_extent = 1.0;
varying vec4 cloud_clip_position;
varying vec3 cloud_local;
float cloud_hash(vec3 p) { return fract(sin(dot(p,vec3(127.1,311.7,74.7)))*43758.5453); }
float cloud_noise(vec3 p) {
	vec3 i=floor(p), f=fract(p); f=f*f*(3.0-2.0*f);
	return mix(mix(mix(cloud_hash(i),cloud_hash(i+vec3(1,0,0)),f.x),mix(cloud_hash(i+vec3(0,1,0)),cloud_hash(i+vec3(1,1,0)),f.x),f.y),
		mix(mix(cloud_hash(i+vec3(0,0,1)),cloud_hash(i+vec3(1,0,1)),f.x),mix(cloud_hash(i+vec3(0,1,1)),cloud_hash(i+vec3(1)),f.x),f.y),f.z);
}
void vertex() {
	vec3 center = (MODEL_MATRIX*vec4(CUSTOM0.xyz,1.0)).xyz;
	float size = CUSTOM0.w*length(MODEL_MATRIX[0].xyz);
	vec2 offset = (UV-.5)*size;
	vec3 point = center+INV_VIEW_MATRIX[0].xyz*offset.x+INV_VIEW_MATRIX[1].xyz*offset.y;
	cloud_local = CUSTOM0.xyz/cloud_extent+vec3((UV-.5)*CUSTOM0.w/cloud_extent,0.0);
	cloud_clip_position = PROJECTION_MATRIX*VIEW_MATRIX*vec4(point,1.0);
	POSITION = cloud_clip_position;
	POSITION.z = max(POSITION.z,CLIP_SPACE_FAR*POSITION.w);
}
void fragment() {
	float clip_depth = cloud_clip_position.z/cloud_clip_position.w;
	DEPTH = clamp((clip_depth-CLIP_SPACE_FAR)/(1.0-CLIP_SPACE_FAR),1e-6,1.0);
	float cloud = cloud_noise(cloud_local*19.0+seed)*.6+cloud_noise(cloud_local*53.0+seed)*.3+cloud_noise(cloud_local*149.0+seed)*.1;
	float r = length((UV-.5)*2.0);
	float mask = pow(max(1.0-r*r,0.0),2.2);
	ALBEDO = tint*strength;
	ALPHA = mask*pow(cloud,1.6)*COLOR.a;
}
