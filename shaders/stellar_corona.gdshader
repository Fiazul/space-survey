shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;
uniform vec3 tint : source_color = vec3(1.0);
uniform float strength = 1.3;
uniform float seed = 0.0;
uniform float pulse = 0.0;
uniform float star_radius = 1.0;
uniform float extent = 2.8;
uniform float falloff = 3.8;
uniform float activity = .3;
uniform int stellar_mode = 0;
varying vec4 corona_clip_position;

float corona_hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7)))*43758.5453);
}

float corona_noise(vec2 p) {
	vec2 cell = floor(p);
	vec2 f = fract(p);
	f = f*f*(3.0-2.0*f);
	return mix(mix(corona_hash(cell), corona_hash(cell+vec2(1.0,0.0)), f.x),
		mix(corona_hash(cell+vec2(0.0,1.0)), corona_hash(cell+vec2(1.0)), f.x), f.y);
}

void vertex() {
	vec3 center = MODEL_MATRIX[3].xyz;
	vec3 camera_offset = INV_VIEW_MATRIX[3].xyz-center;
	float model_scale = length(MODEL_MATRIX[0].xyz);
	float angular_scale = 1.0;
	vec3 right = INV_VIEW_MATRIX[0].xyz;
	vec3 up = INV_VIEW_MATRIX[1].xyz;
	vec3 facing = INV_VIEW_MATRIX[2].xyz;
	if (PROJECTION_MATRIX[3][3] < .5) {
		// Place the glow on the silhouette's tangent plane. This keeps its
		// angular edge aligned even just above the photosphere, without a huge quad.
		float radius = star_radius*model_scale;
		float distance = max(length(camera_offset), radius*1.000001);
		float ratio = radius/distance;
		angular_scale = sqrt(max(1.0-ratio*ratio, .000001));
		facing = normalize(camera_offset);
		center += facing*radius*ratio;
		if (abs(dot(up, facing)) > .99) {
			up = INV_VIEW_MATRIX[0].xyz;
		}
		right = normalize(cross(up, facing));
		up = cross(facing, right);
	}
	mat4 billboard = mat4(vec4(right*model_scale*angular_scale, 0.0),
		vec4(up*model_scale*angular_scale, 0.0), vec4(facing*model_scale, 0.0), vec4(center, 1.0));
	MODELVIEW_MATRIX = VIEW_MATRIX * billboard;
	corona_clip_position = PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	POSITION = corona_clip_position;
	// A tilted stellar billboard can cross the far plane while its star is visible.
	POSITION.z = max(POSITION.z, CLIP_SPACE_FAR * POSITION.w);
}
void fragment() {
	// Restore per-pixel depth after vertex clamping so foreground occlusion is intact.
	float clip_depth = corona_clip_position.z / corona_clip_position.w;
	// Glow beyond the far plane lands a hair inside it: exactly-at-far fails GREATER tests on some drivers.
	DEPTH = clamp((clip_depth-CLIP_SPACE_FAR)/(1.0-CLIP_SPACE_FAR), 1e-6, 1.0);
	vec2 p = (UV-.5)*2.0*extent;
	float r = length(p);
	float height = max(r-1.0, 0.0);
	vec2 direction = p/max(r,.001);
	// Cartesian noise is seamless around the limb; radial shear bends the wisps.
	vec2 bent = direction + vec2(-direction.y, direction.x)*height*.35;
	float broad = corona_noise(direction*3.1+seed);
	float wisps = corona_noise(bent*11.0+vec2(seed, TIME*.015));
	float strands = corona_noise(bent*38.0+vec2(seed, TIME*.009));
	float corona = exp(-height*falloff/(.42+.60*broad))*(.24+.40*broad+.16*wisps);
	corona *= .94+.06*strands;
	float veil = .09*exp(-height*falloff*2.8)*wisps;
	float glare = .025*exp(-height*2.6);
	float prominences = 0.0;
	for (int i = 0; i < 6; i++) {
		float id = float(i);
		float phase = seed*1.37 + (i < 3 ? id*.13 : id*2.39996);
		vec2 axis = vec2(cos(phase), sin(phase));
		float tangent = dot(p, vec2(-axis.y, axis.x));
		float radial = dot(p, axis)-.985;
		float reach = (.07+activity*.25)*(1.0+id*.14)+.008*sin(TIME*.08+id);
		// Upper elliptical arc: two narrow footpoints joined by a curved loop.
		vec2 arc = vec2((tangent-radial*.35)/(.06+id*.016+activity*.025), radial/reach);
		float turbulence = corona_noise(p*57.0+vec2(seed+id, TIME*.06));
		float ring = abs(length(arc)-1.0+(turbulence-.5)*.13);
		float width = max(fwidth(ring), .022);
		float filament = 1.0-smoothstep(.008, .008+width, ring);
		float envelope = exp(-ring*ring*60.0)*.30;
		float group = i < 3 ? 1.0 : .15;
		prominences += (filament+envelope)*smoothstep(0.0,.025,radial)*(.55+.45*turbulence)*group;
	}
	prominences *= stellar_mode == 0 ? (.2+activity*1.8) : 0.0;
	// Soft radial support reaches zero before every edge of the quad.
	float mask = smoothstep(.972, 1.012, r)*(1.0-smoothstep(extent*.72, extent*.98, r));
	float poles = pow(abs(p.y/max(r,.001)),24.0)*(.7+.3*sin(TIME*3.0+seed));
	float warmth = clamp((tint.r-tint.b)*5.0+.2, 0.0, 1.0);
	vec3 halo_color = tint*mix(vec3(1.0), vec3(1.0,.28,.025), warmth);
	if (stellar_mode == 4) {
		corona *= 1.3+strands*.25;
		halo_color = mix(tint,vec3(.45,.65,1.0),.45);
	}
	float hot_rim = exp(-height*45.0)*(.5+.5*wisps);
	vec3 loop_color = mix(tint,vec3(1.0,.65,.22),warmth);
	float eruption = 0.0;
	if (stellar_mode == 0) {
		vec2 axis = vec2(cos(seed*1.37+.13),sin(seed*1.37+.13));
		float alignment = max(dot(direction,axis),0.0);
		eruption = pow(alignment,80.0)*exp(-height*9.0)*activity*activity*wisps;
	}
	ALBEDO = halo_color*strength*(corona*1.4+veil+glare+hot_rim*1.8+pulse*poles*corona*22.0)
		+ loop_color*strength*(prominences*4.0+eruption*5.0);
	ALPHA = mask;
}
