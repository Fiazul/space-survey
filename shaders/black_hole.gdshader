shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled, skip_vertex_transform;
// Kerr null geodesics in Cartesian Kerr-Schild form, H = g^{uv}p_u p_v / 2 with
// g^{uv} = eta^{uv} - f l^u l^v (Visser 2007, arXiv:0706.0622, eq. 3.5-3.12),
// RK4 in the affine parameter. Lengths are gravitational radii r_g = GM/c^2.
// Rays are traced backwards as forward rays of the time-reversed hole (spin -a),
// so ingoing Kerr-Schild stays regular where they cross the horizon.
// Circular-orbit redshift: Bardeen, Press & Teukolsky 1972; Cunningham 1975.

uniform sampler2D screen_texture : hint_screen_texture, filter_nearest;
uniform sampler2D depth_texture : hint_depth_texture, filter_nearest;
uniform sampler2D background_texture : source_color, filter_linear;
uniform bool use_core_background = false;
uniform vec3 observer_rg = vec3(186.0, 22.0, 0.0);
uniform float rg_km = 6349356.0;
uniform float spin = 0.9;
uniform float horizon_rg = 1.4359;
uniform float trace_radius = 46.0;
uniform vec2 render_extent = vec2(100000.0);
uniform vec2 render_offset = vec2(0.0);
uniform bool full_screen = false;
uniform float disk_inner = 2.3209;
uniform float disk_outer = 36.0;
// Sensor clock (BlackHoleRenderer.TIME_LAPSE x simulation seconds) and the two
// flow-map phases: seconds advected within each cycle, and cycle ids.
uniform float sim_time = 0.0;
uniform vec2 flow_age = vec2(0.0, 80.0);
uniform vec2 flow_cycle = vec2(0.0, 1.0);
uniform float flow_cycle_s = 160.0;
uniform float seed = 0.0;
// (radius r_g, azimuth rad, wake length rad, brightness) from BlackHoleRenderer.
uniform vec4 hotspots[4];
uniform float flare = 0.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7)) + seed) * 43758.5453);
}
float noise(vec2 p) {
	vec2 cell = floor(p), f = fract(p);
	f = f*f*(3.0-2.0*f);
	return mix(mix(hash(cell), hash(cell+vec2(1,0)), f.x),
		mix(hash(cell+vec2(0,1)), hash(cell+vec2(1,1)), f.x), f.y);
}
float depth_distance(vec2 uv, mat4 inverse_projection) {
	float depth = texture(depth_texture,uv).r;
	#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	depth = depth*2.0-1.0;
	#endif
	vec4 position = inverse_projection * vec4(uv*2.0-1.0,depth,1.0);
	return length(position.xyz / max(abs(position.w),1e-10));
}
// Kerr-Schild spin axis is +z; the flow turns from +x toward +z in scene axes.
vec3 to_ks(vec3 v) { return vec3(v.x, v.z, -v.y); }
vec3 from_ks(vec3 k) { return vec3(k.x, -k.z, k.y); }

float ks_radius(vec3 x, float a) {
	float w = dot(x,x) - a*a;
	return sqrt(max(.5*w + sqrt(.25*w*w + a*a*x.z*x.z), 1e-8));
}
void ks_metric(vec3 x, float a, out float r, out float f, out vec3 l) {
	r = ks_radius(x,a);
	float s = r*r + a*a;
	f = 2.0*r*r*r / (r*r*r*r + a*a*x.z*x.z);
	l = vec3((r*x.x + a*x.y)/s, (r*x.y - a*x.x)/s, x.z/r);
}
void ks_flow(vec3 x, vec3 p, float a, out vec3 dx, out vec3 dp) {
	float r = ks_radius(x,a);
	float r2 = r*r;
	float a2 = a*a;
	float inverse_r = 1.0/r;
	float inverse_s = 1.0/(r2 + a2);
	float inverse_d = 1.0/(r2*r2 + a2*x.z*x.z);
	float f = 2.0*r2*r*inverse_d;
	vec3 l = vec3((r*x.x + a*x.y)*inverse_s, (r*x.y - a*x.x)*inverse_s, x.z*inverse_r);
	float null_l = 1.0 + dot(l,p);
	// The oblate-radius identity replaces the second metric denominator with d/r.
	vec3 dr = vec3(r2*x.x, r2*x.y, (r2 + a2)*x.z)*r*inverse_d;
	vec3 df = f*((3.0*inverse_r - 2.0*f)*dr - vec3(0.0, 0.0, 2.0*a2*x.z*inverse_d));
	vec3 dl = dr*((x.x*p.x + x.y*p.y - 2.0*r*(l.x*p.x + l.y*p.y))*inverse_s - x.z*p.z*inverse_r*inverse_r)
		+ vec3((r*p.x - a*p.y)*inverse_s, (r*p.y + a*p.x)*inverse_s, p.z*inverse_r);
	dx = p - f*null_l*l;
	dp = .5*null_l*null_l*df + f*null_l*dl;
}

const float PEAK_DISPLAY_K = 7500.0;

// Blackbody colour at temperature kelvin, brightest channel 1 (Helland's fit to
// the CIE blackbody locus), warm-biased for the sensor view.
vec3 blackbody(float kelvin) {
	float t = clamp(kelvin, 1000.0, 40000.0) / 100.0;
	vec3 c;
	c.r = t <= 66.0 ? 1.0 : 1.2929 * pow(t - 60.0, -.1332);
	c.g = t <= 66.0 ? .3901 * log(t) - .6318 : 1.1299 * pow(t - 60.0, -.0755);
	c.b = t >= 66.0 ? 1.0 : (t <= 19.0 ? 0.0 : .5432 * log(t - 10.0) - 1.1963);
	c = clamp(c, 0.0, 1.0) * vec3(1.0, .96, .86);
	return c / max(max(c.r, c.g), c.b);
}

// (turbulence, filaments, eddies) of one flow-map phase; age_rg is its age in r_g/c.
vec3 flow_layer(float r, float phase, float age_rg, float cycle) {
	vec2 q = vec2(r*2.5, phase*8.0 + log(r)*3.0) + vec2(37.1, 17.3)*cycle;
	q += vec2(noise(q*.29+3.7),noise(q*.35-1.9))*5.0;
	// Small eddies drift radially over ~10 r_g/c, independent of the orbit.
	float eddy_shift = age_rg*.1;
	float eddies = noise(q*4.37 + vec2(eddy_shift, 0.0))*.6 + noise(q*9.1 - vec2(eddy_shift, 0.0))*.4;
	float turbulence = noise(q)*.3 + noise(q*2.13)*.2 + eddies*.5;
	return vec3(turbulence, pow(.5+.5*sin(r*5.0 + turbulence*22.0 + phase*5.0), 5.0), eddies);
}

vec3 plasma(vec3 hit, float r, float photon_lz, float observer_shift, out vec3 spot_light) {
	float c_over_rg = 299792.458 / rg_km;
	float r15 = r*sqrt(r);
	float omega = 1.0 / (r15 + spin);
	float u_t = (r15 + spin) / (sqrt(sqrt(r*r*r)) * sqrt(max(r15 - 3.0*sqrt(r) + 2.0*spin, 1e-4)));
	// photon_lz is the time-reversed ray's p_phi, i.e. minus the real photon's.
	float g = observer_shift / (u_t * max(1.0 + omega*photon_lz, .05));
	float azimuth = atan(hit.y, hit.x);
	// Flow map: two phases half a cycle apart, each advected at the Kerr rate
	// and restarted on a fresh noise offset while it is faded out.
	vec3 layer_a = flow_layer(r, azimuth - c_over_rg*omega*flow_age.x, flow_age.x*c_over_rg, flow_cycle.x);
	vec3 layer_b = flow_layer(r, azimuth - c_over_rg*omega*flow_age.y, flow_age.y*c_over_rg, flow_cycle.y);
	float weight = abs(2.0*flow_age.x/flow_cycle_s - 1.0);
	vec3 mean = vec3(.5, .2, .5);
	vec3 blended = mean + (mix(layer_a, layer_b, weight) - mean) * inversesqrt(weight*weight + (1.0-weight)*(1.0-weight));
	float turbulence = clamp(blended.x, 0.0, 1.0);
	float filaments = clamp(blended.y, 0.0, 1.0);
	float eddies = clamp(blended.z, 0.0, 1.0);
	float inner = smoothstep(disk_inner, disk_inner + .3, r);
	float outer = 1.0-smoothstep(disk_outer*.7, disk_outer, r);
	// Zero-torque thin-disk profile T ~ r^-3/4 (1 - sqrt(r_in/r))^1/4 (Shakura &
	// Sunyaev 1973; Page & Thorne 1974), normalised to its peak at 49/36 r_in.
	// Only the shape is physical; PEAK_DISPLAY_K sets the sensor colour scale.
	float profile = pow(r, -.75) * pow(max(1.0 - sqrt(disk_inner/r), 0.0), .25);
	float peak_r = disk_inner*49.0/36.0;
	float temperature = profile / (pow(peak_r, -.75) * pow(1.0 - sqrt(36.0/49.0), .25));
	float surge = 1.0 + .8*flare*exp(-(r - disk_inner)/2.5);
	float flow = (.25 + turbulence*.3 + eddies*eddies*1.1 + filaments*.1) * inner * outer * pow(temperature, 2.5) * surge;
	float spot = 0.0;
	for (int k = 0; k < 4; k++) {
		vec4 h = hotspots[k];
		float width = .35 + .06*h.x;
		float lead = (mod(azimuth - h.y + 3.14159265, 6.28318531) - 3.14159265)*h.x/width;
		float radial = exp(-(r-h.x)*(r-h.x)/(width*width));
		// Cooling wake trails behind the plasmoid along its orbit.
		float wake = lead < 0.0 ? .06*exp(lead*width/(h.x*max(h.z, 1e-3))) : 0.0;
		spot += h.w * radial * max(exp(-lead*lead), wake);
	}
	spot *= smoothstep(disk_inner, disk_inner + .5, r);
	// Observed colour temperature is the emitter's times g; flares heat it.
	float heat = PEAK_DISPLAY_K * (1.0 + .35*flare);
	vec3 tint = blackbody(heat * pow(max(temperature, .15), 1.2) * g);
	vec3 spot_tint = blackbody(2.0 * heat * g);
	// Frequency-integrated intensity scales as g^4 (I_nu / nu^3 is invariant).
	spot_light = spot_tint*spot*g*g*g*g;
	return tint*flow*6.0*g*g*g*g;
}

void vertex() {
	vec3 center = (VIEW_MATRIX * MODEL_MATRIX[3]).xyz;
	VERTEX = center + vec3(VERTEX.xy*render_extent+render_offset, 0.0);
	POSITION = PROJECTION_MATRIX * vec4(VERTEX,1.0);
	if (full_screen) POSITION = vec4(UV*2.0-1.0, .5, 1.0);
}

void fragment() {
	float foreground_distance = depth_distance(SCREEN_UV,INV_PROJECTION_MATRIX);
	float lens_distance = length((VIEW_MATRIX * MODEL_MATRIX[3]).xyz);
	if (foreground_distance < lens_distance*.98) discard;
	vec4 view_ray = INV_PROJECTION_MATRIX * vec4(SCREEN_UV*2.0-1.0, 1.0, 1.0);
	vec3 direction = normalize(mat3(INV_VIEW_MATRIX) * (view_ray.xyz / view_ray.w));
	vec3 ro = observer_rg + INV_VIEW_MATRIX[3].xyz / rg_km;
	float observer_r = length(ro);
	float forward = -dot(ro,direction);
	float impact2 = dot(cross(ro,direction), cross(ro,direction));
	float reach = trace_radius;
	if (observer_r > reach && (forward < 0.0 || impact2 > reach*reach)) discard;
	// Begin at the trace boundary after the weak-field segment, taken as straight.
	float entry = max(0.0, forward - sqrt(max(reach*reach-impact2,0.0)));
	float a = -spin;
	vec3 x = to_ks(ro + direction*entry);
	vec3 n = to_ks(direction);
	float r, f;
	vec3 l;
	ks_metric(x, a, r, f, l);
	float c = dot(l,n);
	float k = max(1.0 - f*c*c, 1e-3);
	vec3 p = n * (f*c + sqrt(f*f*c*c + k*(1.0+f))) / k;
	float observer_shift = inversesqrt(max(1.0 - 2.0/max(observer_r, 2.2), .05));
	vec3 emission = vec3(0.0);
	vec3 spots = vec3(0.0);
	float transmission = 1.0;
	bool captured = true;
	vec3 velocity = n;
	for (int i=0; i<96; i++) {
		r = ks_radius(x, a);
		if (r < horizon_rg*1.01) break;
		if (r > reach*1.05 && dot(x,p) > 0.0) { captured = false; break; }
		float step_scale = mix(.25, .5, smoothstep(8.0, 20.0, r));
		float h = clamp(step_scale*(r - .8*horizon_rg), .02, 12.0);
		vec3 flow_x, flow_p;
		ks_flow(x, p, a, flow_x, flow_p);
		// Resolve disk crossings separately from the longer weak-field steps.
		if (x.z*flow_x.z < 0.0) h = min(h, max(.02, -x.z/flow_x.z)*1.05);
		vec3 sum_x = flow_x;
		vec3 sum_p = flow_p;
		ks_flow(x + .5*h*flow_x, p + .5*h*flow_p, a, flow_x, flow_p);
		sum_x += 2.0*flow_x;
		sum_p += 2.0*flow_p;
		ks_flow(x + .5*h*flow_x, p + .5*h*flow_p, a, flow_x, flow_p);
		sum_x += 2.0*flow_x;
		sum_p += 2.0*flow_p;
		ks_flow(x + h*flow_x, p + h*flow_p, a, flow_x, flow_p);
		vec3 next = x + h/6.0*(sum_x + flow_x);
		vec3 next_p = p + h/6.0*(sum_p + flow_p);
		velocity = flow_x;
		if (x.z*next.z < 0.0) {
			float t = x.z/(x.z-next.z);
			vec3 hit = mix(x,next,t);
			vec3 hit_p = mix(p,next_p,t);
			float disk_r = sqrt(max(dot(hit.xy,hit.xy) - spin*spin, 0.0));
			if (disk_r > disk_inner && disk_r < disk_outer) {
				vec3 spot_light;
				emission += transmission*plasma(hit, disk_r, hit.x*hit_p.y - hit.y*hit_p.x, observer_shift, spot_light);
				spots += transmission*spot_light;
				transmission *= .04;
			}
		}
		x = next;
		p = next_p;
	}
	vec3 background = vec3(0.0);
	if (!captured) {
		vec3 escaped_world = normalize(from_ks(velocity));
		vec3 escaped = transpose(mat3(INV_VIEW_MATRIX)) * escaped_world;
		vec4 projected = PROJECTION_MATRIX * vec4(escaped,0.0);
		vec2 uv = projected.xy / max(projected.w,.00001) * .5 + .5;
		if (use_core_background) {
			uv = vec2(atan(escaped_world.z,escaped_world.x)/6.28318530718+.5,acos(clamp(escaped_world.y,-1.0,1.0))/3.14159265359);
			background = texture(background_texture,uv).rgb;
		} else if (projected.w > 0.0 && all(greaterThan(uv,vec2(0.0))) && all(lessThan(uv,vec2(1.0)))) {
			if (depth_distance(uv,INV_PROJECTION_MATRIX) >= lens_distance*.98) background = texture(screen_texture,uv).rgb;
		}
	}
	// Display transfer: the flow rolls off below half brightness so hotspots,
	// Doppler-boosted the same way, stay the brightest features in frame.
	float flow_peak = max(max(emission.r, emission.g), emission.b);
	vec3 flow_shown = emission * .6*(1.0 - exp(-flow_peak/.6)) / max(flow_peak, 1e-5);
	vec3 knee = vec3(.6);
	vec3 total = flow_shown + spots;
	vec3 shown = mix(total, knee + .4*(1.0 - exp(-(total - knee)/.4)), step(knee, total));
	ALBEDO = background * transmission + shown;
	// The bounded weak-field approximation must meet the existing star field
	// continuously instead of exposing the background texture's footprint.
	ALPHA = observer_r > reach ? 1.0-smoothstep(max(reach*.78, disk_outer),reach,sqrt(impact2)) : 1.0;
}
