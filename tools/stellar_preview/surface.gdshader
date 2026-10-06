shader_type spatial;
render_mode unshaded, cull_back;
uniform vec3 base_color : source_color = vec3(1.0, .9, .8);
uniform vec3 hot_color : source_color = vec3(1.0, .97, .93);
uniform int family = 0;
uniform float seed = 1.0;
uniform float brightness = 1.0;
uniform bool enhanced = false;
varying vec3 sphere_pos;

float hash3(vec3 p) { return fract(sin(dot(p, vec3(127.1,311.7,74.7)))*43758.5453); }
float noise3(vec3 p) {
	vec3 i=floor(p), f=fract(p); f=f*f*(3.0-2.0*f);
	return mix(mix(mix(hash3(i),hash3(i+vec3(1,0,0)),f.x),mix(hash3(i+vec3(0,1,0)),hash3(i+vec3(1,1,0)),f.x),f.y),
		mix(mix(hash3(i+vec3(0,0,1)),hash3(i+vec3(1,0,1)),f.x),mix(hash3(i+vec3(0,1,1)),hash3(i+vec3(1)),f.x),f.y),f.z);
}
float fbm(vec3 p) { return noise3(p)*.54+noise3(p*2.07)*.27+noise3(p*4.13)*.13+noise3(p*8.3)*.06; }
void vertex() { sphere_pos=normalize(VERTEX); }
void fragment() {
	vec3 n=normalize(sphere_pos);
	float mu=max(dot(normalize(NORMAL),normalize(VIEW)),0.0);
	float limb=.28+.72*pow(mu,.48);
	vec3 col=base_color;
	if (family==0 || family==1) {
		float scale=family==1 ? 12.0 : 125.0;
		vec3 warp=n+vec3(fbm(n*5.0+seed),fbm(n*5.0+seed+11.0),fbm(n*5.0+seed-7.0))*.055;
		float fine=fbm(warp*scale+seed);
		float network=fbm(warp*19.0+seed);
		float active=smoothstep(.51,.71,fbm(n*5.0+seed));
		float spot=family==1 ? 0.0 : smoothstep(.70,.80,noise3(warp*16.0+seed))*active;
		float veins=pow(1.0-abs(noise3(warp*95.0+seed)-.5)*2.0,9.0);
		float contrast=family==1 ? .65 : .32;
		col=mix(base_color*.82,hot_color,fine);
		col*=1.0+(fine-.5)*contrast;
		col*=1.0-spot*.65;
		if (enhanced) {
			col=mix(base_color*.045,hot_color*.80,smoothstep(.22,.75,network));
			col+=hot_color*veins*(.1+active*.8);
			col*=.65+fine*.7;
		} else { col+=hot_color*active*veins*.16; }
	} else if (family==2) {
		float lon=atan(n.z,n.x);
		float lat=asin(clamp(n.y,-1.0,1.0));
		vec3 flow=vec3(lon*6.0,lat*32.0,seed);
		float storms=fbm(vec3(lon*2.8,lat*5.0,seed));
		float shear=lat+.045*sin(lon*3.0+lat*9.0)+.12*(storms-.5);
		float belts=.5+.5*sin(shear*21.0+sin(shear*8.0)*1.9);
		float streaks=fbm(vec3(lon*3.0,shear*170.0,seed+7.0));
		float broad=fbm(vec3(lon*7.0,shear*42.0,seed));
		col=mix(base_color*.28,base_color*.66,smoothstep(.0,1.0,belts*.40+broad*.60));
		col+=hot_color*pow(streaks,3.0)*(.04+.09*belts);
		col*=.38+.62*pow(mu,.50);
		limb=1.0;
	} else { col*=.65+.35*pow(mu,.5); }
	ALBEDO=col*limb*brightness;
}
