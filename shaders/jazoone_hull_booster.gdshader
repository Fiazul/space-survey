shader_type spatial;
render_mode cull_disabled, depth_draw_opaque;

// Textured hull with HDR torch only on the two authored emissive engine discs.
// The actual exhaust volume is separate: ShipMesh.add_jazoone_booster_plumes builds
// cruiser_torch cones on the sockets probed out of this same mask.
// The five Layer_1_Material_0 meshes are vertex-split chunks of the whole ship;
// painting them with the additive propulsion shader made the hull solid white.
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap;
uniform sampler2D emissive_tex : source_color, filter_linear_mipmap;
uniform sampler2D orm_tex : hint_default_white, filter_linear_mipmap;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap;
uniform vec4 plasma_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
// Idle exhaust colour, matched to cruiser_torch so the disc and the plume growing out
// of it are never different temperatures.
uniform vec4 cool_color : source_color = vec4(1.0, 0.33, 0.06, 1.0);
uniform vec4 hot_color : source_color = vec4(0.30, 0.72, 1.0, 1.0);
uniform float power : hint_range(0.0, 1.0) = 0.45;
uniform float flow_speed : hint_range(0.0, 6.0) = 1.4;
uniform float brightness : hint_range(0.05, 4.0) = 4.0;
uniform float temperature : hint_range(0.0, 1.0) = 1.0;
// The two authored engine discs are found by the emissive mask alone. There used to be
// a pair of UV disc centres gating this as well, but tools/probe_jazoone_sockets.gd
// showed NO vertex UV lands within their radius, so that test was always 0 and the
// torch branch below never ran. The mask on its own is precise: it selects 3464 of
// 310277 vertices, in exactly two tight clusters that are the engines.
// --- Disc shaping: the mask alone cannot give this a border ---------------------
// step(0.25, mask) lit every engine texel to one flat value, and softening the mask
// into smoothstep(0.20, 0.62) barely helped: tools/probe_propulsion_area.gd measures
// the mask as saturated, so the gradient keeps 96.1% of the lit texels and the rim is
// still hard. So the discs get the same socket falloff cruiser_propulsion uses, off the
// sockets tools/probe_jazoone_sockets.gd recovered from this same mask. Mind the sign:
// this model imports with yaw 0, so its exhaust runs +Z.
// Array size matches cruiser_propulsion's and ShipMesh.SHAPE_SOCKET_MAX so one wiring
// helper can fill either shader; JazOone itself only ever has two.
uniform vec3 socket_pos[8];
uniform float socket_r[8];
uniform int socket_count : hint_range(0, 8) = 0;
uniform vec3 shape_axis = vec3(0.0, 0.0, 1.0);
uniform float border_start : hint_range(0.1, 2.0) = 0.85;
uniform float border_end : hint_range(0.1, 2.5) = 1.15;
uniform float core_boost : hint_range(1.0, 4.0) = 1.5;
uniform float depth_dim : hint_range(0.0, 1.0) = 0.45;

varying vec3 local_position;

void vertex() {
	local_position = VERTEX;
}

void fragment() {
	vec3 albedo = texture(albedo_tex, UV).rgb;
	vec3 emis = texture(emissive_tex, UV).rgb;
	vec3 orm = texture(orm_tex, UV).rgb;
	float mask = max(max(emis.r, emis.g), emis.b);
	// step() gave the disc a BINARY edge: every texel above 0.25 lit to exactly the
	// same value, so the disc was a hard-rimmed uniform plate and `brightness` scaled
	// the plate rather than a throat. It is why this ship reaches the clip ceiling
	// first of the four (measured: knob x1.16, against x2.00 for the next one).
	// Keep step() as the BRANCH - which texels are engine at all - and use the mask's
	// own value as the gradient inside it, so the disc has a border of its own.
	float booster = step(0.25, mask);
	float disc = smoothstep(0.20, 0.62, mask);

	ALBEDO = albedo;
	METALLIC = orm.b;
	ROUGHNESS = orm.g;
	NORMAL_MAP = texture(normal_tex, UV).rgb;
	// 4.0 put the whole hull's authored emissive well into HDR, and the glow turned
	// that into a halo covering a quarter of the chase-view frame. Keep the lit panels
	// lit, keep them under the bloom threshold.
	EMISSION = emis * 0.9;

	if (booster > 0.5) {
		float facing = abs(dot(normalize(NORMAL), normalize(VIEW)));
		float visibility = mix(0.58, 1.0, smoothstep(0.02, 0.72, facing));
		float flow = TIME * flow_speed;
		float broad = sin(local_position.x * 0.24 - flow * 2.1
			+ sin(local_position.y * 0.19 + flow));
		float fine = sin(local_position.z * 0.62 + local_position.x * 0.41 + flow * 4.7);
		float turbulence = clamp(0.72 + broad * 0.16 + fine * 0.12, 0.35, 1.0);
		float shimmer = mix(0.86, 1.12, turbulence);
		// Above display white so the disc reads as a hot throat, not 20x above it:
		// With brightness 0.40 (see style_jazoone_spaceship) this is 0.2 at rest, 0.43
		// at cruise and 1.03 at full boost - roughly where un-boosted cruise used to
		// sit. `power` arrives as 0..Ship.POWER_CEIL (0.75).
		float energy = mix(0.5, 4.6, pow(power, 1.4)) * shimmer * brightness;
		// Same grading as cruiser_propulsion.gdshader, against the probed disc sockets:
		// hot at the throat, out before the disc's authored edge. socket_count = 0
		// leaves the old flat disc, which is what an unwired material still gets.
		float shape = disc;
		if (socket_count > 0) {
			vec3 axis = normalize(shape_axis);
			float radial_n = 1.0e9;
			float depth_n = 0.0;
			for (int i = 0; i < 8; i++) {
				if (i >= socket_count) {
					break;
				}
				vec3 offset = local_position - socket_pos[i];
				float r = max(socket_r[i], 0.0001);
				float along = dot(offset, axis);
				float candidate = length(offset - along * axis) / r;
				if (candidate < radial_n) {
					radial_n = candidate;
					depth_n = abs(along) / r;
				}
			}
			float rim = 1.0 - smoothstep(border_start, border_end, radial_n);
			float core = mix(1.0, core_boost, 1.0 - smoothstep(0.0, 0.85, radial_n));
			float depth_keep = 1.0 - depth_dim * smoothstep(0.35, 1.6, depth_n);
			shape *= rim * core * depth_keep;
		}
		// Same ramp the plume uses: a cold engine glows orange, a hot one blue-white.
		vec3 tint = mix(cool_color.rgb, hot_color.rgb, smoothstep(0.12, 0.78, temperature));
		vec3 white_core = mix(tint * plasma_color.rgb, vec3(1.0), 0.90 * temperature);
		ALBEDO = white_core;
		METALLIC = 0.0;
		ROUGHNESS = 1.0;
		EMISSION = white_core * energy * visibility * shape;
	}
}
