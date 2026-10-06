float stellar_surface_hash(vec3 p) { return fract(sin(dot(p,vec3(127.1,311.7,74.7)))*43758.5453); }
float stellar_surface_noise(vec3 p) {
	vec3 i=floor(p), f=fract(p); f=f*f*(3.0-2.0*f);
	return mix(mix(mix(stellar_surface_hash(i),stellar_surface_hash(i+vec3(1,0,0)),f.x),mix(stellar_surface_hash(i+vec3(0,1,0)),stellar_surface_hash(i+vec3(1,1,0)),f.x),f.y),
		mix(mix(stellar_surface_hash(i+vec3(0,0,1)),stellar_surface_hash(i+vec3(1,0,1)),f.x),mix(stellar_surface_hash(i+vec3(0,1,1)),stellar_surface_hash(i+vec3(1)),f.x),f.y),f.z);
}
float stellar_surface_fbm(vec3 p) { return stellar_surface_noise(p)*.54+stellar_surface_noise(p*2.07)*.27+stellar_surface_noise(p*4.13)*.13+stellar_surface_noise(p*8.3)*.06; }
float stellar_surface_granules(vec3 p) {
	vec3 cell=floor(p), local=fract(p);
	float nearest=8.0;
	for (int x=-1; x<=1; x++) for (int y=-1; y<=1; y++) for (int z=-1; z<=1; z++) {
		vec3 offset=vec3(float(x),float(y),float(z));
		vec3 at=cell+offset;
		vec3 center=vec3(stellar_surface_hash(at),stellar_surface_hash(at+19.7),stellar_surface_hash(at-8.3));
		vec3 d=offset+center-local;
		nearest=min(nearest,dot(d,d));
	}
	return 1.0-smoothstep(.02,.45,nearest);
}
vec3 stellar_surface_color(vec3 n, float mu) {
	float limb=mix(stellar_limb_floor,1.0,pow(mu,.55));
	vec3 col=color_a;
	if (stellar_mode==0 || stellar_mode==4) {
		bool giant=stellar_cells<25.0;
		float scale=giant ? 12.0 : stellar_cells*2.0;
		vec3 warp=n+vec3(stellar_surface_noise(n*5.0+seed),stellar_surface_noise(n*5.0+seed+11.0),stellar_surface_noise(n*5.0+seed-7.0))*.025;
		vec3 gp=warp*scale+seed;
		float footprint=length(fwidth(gp));
		float fine=.5;
		float weight=1.0-smoothstep(.4,1.5,footprint);
		if (weight>.01) fine=mix(.5,giant ? stellar_surface_fbm(gp) : stellar_surface_granules(gp),weight);
		fine=mix(.5,fine,granulation);
		float network=stellar_surface_fbm(warp*19.0+seed);
		float active=smoothstep(.51,.71,stellar_surface_fbm(n*5.0+seed));
		float spot=smoothstep(.70,.80,stellar_surface_noise(warp*16.0+seed))*active*stellar_spots*2.0;
		float heat=clamp(.5+(fine-.43)*1.5,0.0,1.0);
		col=mix(stellar_cool_color.rgb,stellar_hot_color.rgb,heat);
		col*=1.0+(fine-.5)*(giant ? .65 : stellar_detail_contrast);
		col*=1.0-spot*.65;
		float veins=.5;
		float vein_weight=1.0-smoothstep(.4,1.5,length(fwidth(warp*95.0)));
		if (vein_weight>.01) veins=pow(1.0-abs(stellar_surface_noise(warp*95.0+seed)-.5)*2.0,9.0)*vein_weight;
		if (sensor_mode==2) {
			col=mix(color_a*.045,stellar_hot_color.rgb*.80,smoothstep(.22,.75,network));
			col+=stellar_hot_color.rgb*veins*(.1+active*.8);
			col*=.65+fine*.7;
		} else { col+=stellar_hot_color.rgb*active*veins*stellar_activity*.08; }
	} else if (stellar_mode==1) {
		float lat=asin(clamp(n.y,-1.0,1.0));
		float storms=stellar_surface_fbm(n*5.0+seed);
		float shear=lat+.045*sin(n.x*3.0+lat*9.0)+.12*(storms-.5);
		vec3 flow=vec3(n.x*3.0,shear*170.0,n.z*3.0)+seed;
		float footprint=length(fwidth(flow));
		float streaks=.5;
		float weight=1.0-smoothstep(.4,1.5,footprint);
		if (weight>.01) streaks=mix(.5,stellar_surface_fbm(flow+7.0),weight);
		float broad=stellar_surface_fbm(vec3(n.x*7.0,shear*42.0,n.z*7.0)+seed);
		float clouds=stellar_surface_fbm(vec3(n.x*2.8,shear*12.0,n.z*2.8)+seed);
		col=mix(color_a*.28,color_a*.75,smoothstep(.12,.86,clouds*.4+broad*.6));
		col+=stellar_hot_color.rgb*pow(streaks,3.0)*(.04+.09*storms);
		if (sensor_mode==1) col*=3.0;
	} else {
		// Compact cooling surfaces: no gas-giant latitude bands or mandatory nebula.
		col*=.97+.03*stellar_surface_noise(n*45.0+seed);
	}
	float display_brightness=stellar_brightness/(1.0+stellar_brightness*.65);
	return col*limb*display_brightness;
}
