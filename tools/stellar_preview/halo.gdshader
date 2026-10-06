shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;
uniform vec3 tint : source_color = vec3(.4,.7,1.0);
uniform float strength=.2;
uniform float seed=1.0;
uniform bool billboard=true;
uniform bool shell=false;
varying vec3 local_pos;
float h(vec3 p){return fract(sin(dot(p,vec3(127.1,311.7,74.7)))*43758.5453);}
float n(vec3 p){vec3 i=floor(p),f=fract(p);f=f*f*(3.0-2.0*f);
return mix(mix(mix(h(i),h(i+vec3(1,0,0)),f.x),mix(h(i+vec3(0,1,0)),h(i+vec3(1,1,0)),f.x),f.y),mix(mix(h(i+vec3(0,0,1)),h(i+vec3(1,0,1)),f.x),mix(h(i+vec3(0,1,1)),h(i+vec3(1)),f.x),f.y),f.z);}
void vertex(){local_pos=VERTEX;if(billboard){MODELVIEW_MATRIX=VIEW_MATRIX*mat4(INV_VIEW_MATRIX[0],INV_VIEW_MATRIX[1],INV_VIEW_MATRIX[2],MODEL_MATRIX[3]);}}
void fragment(){
	float cloud=n(local_pos*6.0+seed)*.6+n(local_pos*17.0+seed)*.3+n(local_pos*47.0+seed)*.1;
	float mask;
	if(shell){mask=pow(1.0-abs(dot(normalize(NORMAL),normalize(VIEW))),2.0);}
	else {float r=length((UV-.5)*2.0);mask=pow(max(1.0-r*r,0.0),2.2);}
	ALBEDO=tint*strength;
	ALPHA=mask*pow(cloud,1.6);
}
