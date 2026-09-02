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
uniform float brightness : hint_range(0.5, 4.0) = 4.0;
uniform float temperature : hint_range(0.0, 1.0) = 1.0;
// The two authored engine discs are found by the emissive mask alone. There used to be
// a pair of UV disc centres gating this as well, but tools/probe_jazoone_sockets.gd
// showed NO vertex UV lands within their radius, so that test was always 0 and the
// torch branch below never ran. The mask on its own is precise: it selects 3464 of
// 310277 vertices, in exactly two tight clusters that are the engines.
varying vec3 local_position;

void vertex() {
	local_position = VERTEX;
}

void fragment() {
	vec3 albedo = texture(albedo_tex, UV).rgb;
	vec3 emis = texture(emissive_tex, UV).rgb;
	vec3 orm = texture(orm_tex, UV).rgb;
	float mask = max(max(emis.r, emis.g), emis.b);
	float booster = step(0.25, mask);

	ALBEDO = albedo;
	METALLIC = orm.b;
	ROUGHNESS = orm.g;
	NORMAL_MAP = texture(normal_tex, UV).rgb;
	EMISSION = emis * 4.0;

	if (booster > 0.5) {
		float facing = abs(dot(normalize(NORMAL), normalize(VIEW)));
		float visibility = mix(0.58, 1.0, smoothstep(0.02, 0.72, facing));
		float flow = TIME * flow_speed;
		float broad = sin(local_position.x * 0.24 - flow * 2.1
			+ sin(local_position.y * 0.19 + flow));
		float fine = sin(local_position.z * 0.62 + local_position.x * 0.41 + flow * 4.7);
		float turbulence = clamp(0.72 + broad * 0.16 + fine * 0.12, 0.35, 1.0);
		float shimmer = mix(0.86, 1.12, turbulence);
		float energy = mix(64.0, 128.0, power) * shimmer * brightness;
		// Same ramp the plume uses: a cold engine glows orange, a hot one blue-white.
		vec3 tint = mix(cool_color.rgb, hot_color.rgb, smoothstep(0.12, 0.78, temperature));
		vec3 white_core = mix(tint * plasma_color.rgb, vec3(1.0), 0.90 * temperature);
		ALBEDO = vec3(1.0);
		METALLIC = 0.0;
		ROUGHNESS = 1.0;
		EMISSION = white_core * energy * visibility;
	}
}
