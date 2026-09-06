shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never;

// Uses only the model's authored propulsion geometry, keeping the exhaust seated
// at the rear. The core never fades out at grazing angles: many authored booster
// meshes are open cylinders whose visible walls are nearly perpendicular to VIEW.
uniform vec4 plasma_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
// Same ramp as cruiser_torch and jazoone_hull_booster: an engine that is barely
// ticking over glows red-orange, a hot one goes blue-white. Without this the authored
// booster patches sat at flat display-clipped white at every throttle setting, which
// is what made the engine bells read as headlights instead of exhaust.
uniform vec4 cool_color : source_color = vec4(1.0, 0.33, 0.06, 1.0);
uniform vec4 hot_color : source_color = vec4(0.30, 0.72, 1.0, 1.0);
uniform float temperature : hint_range(0.0, 1.0) = 1.0;
uniform float power : hint_range(0.0, 1.0) = 0.45;
uniform float flow_speed : hint_range(0.0, 6.0) = 1.4;
// Range widened past 4.0: the per-ship gains are derived from EFFECTIVE emissive area
// now that the shaping fades most of each housing out, and dingo57 lands at 4.68.
uniform float brightness : hint_range(0.5, 8.0) = 4.0;

// --- Nozzle shaping: the emissive must not be the whole mesh -------------------
// This shader used to have NO spatial term. Across an entire booster patch the only
// variation was `visibility` (view angle, 0.58..1.0) and `shimmer` (0.86..1.12), so
// every pixel sat at the same value and `brightness` scaled a uniformly-lit plate.
// Raising it did not make a hotter throat, it made a wider white area that clipped
// everywhere at once - the "headlights, not exhaust" reading, and the reason three
// rounds of tuning the energy constants changed nothing.
//
// And on two of the four ships most of what was lit is not even the engine.
// tools/probe_booster_shape.gd integrates each booster surface's triangle area against
// its distance from its OWN nearest socket axis:
//
//     ship        within 1.0 r   in the 1.0-1.15 fade   beyond the border
//     class_ii            100%                     0%                  0%
//     snarkrans            33%                    10%                 57%
//     dingo57              11%                     2%                 87%
//
// So on dingo57, 87% of the glow was the HOUSING around the engine, at full intensity -
// that is the white that kept spreading past the nozzle rim. class_ii is the exception:
// its authored patches are the nozzle faces themselves, so the border cuts nothing
// there and only the core gradient below changes its look. (An earlier version of this
// comment claimed 28%/72% fleet-wide, from vertex spreads measured in a 2x-radius
// window that on class_ii also caught the neighbouring patches. Per-patch area is the
// number that means anything.)
//
// So the sockets that position the plumes are handed to the shader as well, and the
// energy is graded against them: hot at the inner edge, dark before the mesh ends.
// `socket_count = 0` disables all of it and restores the old flat plate, which is
// what any material that is not wired with sockets still gets.
uniform vec3 socket_pos[8];              // socket centres, in THIS mesh's local space
uniform float socket_r[8];               // matching usable radii, same space
uniform int socket_count : hint_range(0, 8) = 0;
// Which local axis the exhaust runs along. Model space for the authored hull surfaces
// (+/-Z), but _add_dense_booster_plug puts this shader on its own rotated cylinder
// mesh whose axis is +Y, so it cannot be assumed.
uniform vec3 shape_axis = vec3(0.0, 0.0, 1.0);
// The border. Emission starts fading at `border_start` x the socket radius and is
// fully out by `border_end`, so the outer housing ring stops being a light source and
// the glow gets an edge of its own instead of ending where the mesh does.
uniform float border_start : hint_range(0.1, 2.0) = 0.85;
uniform float border_end : hint_range(0.1, 2.5) = 1.15;
// Extra energy at the inner edge, nearest the plume. This is what makes the knob buy
// contrast: a small hot core against a falloff, rather than a bigger flat plate.
uniform float core_boost : hint_range(1.0, 4.0) = 1.5;
// The deep interior of a housing is shadowed by its own bell and barely visible
// (snarkrans' sockets run ~2 radii deep), so it should not read as bright as the
// throat. A flat ring measures zero depth and is unaffected.
uniform float depth_dim : hint_range(0.0, 1.0) = 0.45;

// --- Mirrored housings --------------------------------------------------------
// The two banks are mirrored copies of one another, so an unmirrored flow pattern
// slides across the hull instead of running outward on both sides. Folding x about
// the hull's centre line makes the animation symmetric.
uniform bool mirror_flow = false;
uniform float symmetry_center_x = 0.0;

// Optional rear-rim glow for complete engine housings; legacy patches use all faces.
uniform bool rear_only = false;
uniform float rear_start = 0.0;
uniform float rear_band = 0.04;

// MERGE NOTE: the fold is for the FLOW NOISE ONLY, and these features arrived from
// three different branches into what used to be one varying. Socket grading and the
// rear-rim cut both measure real distances - socket_pos[] and rear_start are in true
// surface space - so folding x for those too would put every fragment in a different
// frame from its own socket: radial_n explodes, `rim` goes to zero and the booster
// turns BLACK. Two varyings, one job each.
varying vec3 local_position;    // true surface space - socket grading, rear-rim cut
varying vec3 flow_position;     // optionally mirrored - turbulence only

void vertex() {
	local_position = VERTEX;
	flow_position = VERTEX;
	if (mirror_flow) {
		flow_position.x = abs(VERTEX.x - symmetry_center_x);
	}
}

void fragment() {
	if (rear_only && local_position.z > rear_start + rear_band) {
		discard;
	}
	float facing = abs(dot(normalize(NORMAL), normalize(VIEW)));
	float edge_softness = smoothstep(0.02, 0.72, facing);
	float visibility = mix(0.58, 1.0, edge_softness);
	float flow = TIME * flow_speed;
	float broad = sin(flow_position.x * 0.24 - flow * 2.1 + sin(flow_position.y * 0.19 + flow));
	float fine = sin(flow_position.z * 0.62 + flow_position.x * 0.41 + flow * 4.7);
	float turbulence = clamp(0.72 + broad * 0.16 + fine * 0.12, 0.35, 1.0);
	float shimmer = mix(0.86, 1.12, turbulence);
	// READ THIS BEFORE CHANGING ANY NUMBER HERE.
	//
	// `render_mode unshaded` DISCARDS EMISSION. Godot 4 takes ALBEDO as the final
	// colour for an unshaded material and never adds the emission term, so every
	// "HDR energy" value this shader has ever had was dead code. Proven: multiplying
	// EMISSION by 100 moves a 960x540 frame's total luminance by 0.03%.
	//
	// What actually reached the screen was `ALBEDO * ALPHA` under blend_add, with
	// ALBEDO = vec3(1.0) and an ALPHA floor of 0.45 - a slab of near-solid white per
	// patch that no energy constant could turn down. Several rounds of "the booster is
	// too bright" were spent tuning numbers that did nothing.
	//
	// So: ALBEDO carries the HDR value (it goes straight to the rgba16f buffer, values
	// above 1.0 bloom), and `energy` is a real control again. With brightness 4.0 this
	// peaks around 0.9 before the visibility/alpha falloff.
	// `power` arrives as 0..Ship.POWER_CEIL (0.75). Boost lands near where un-boosted
	// cruise used to sit; cruise itself is now well below it.
	float energy = mix(0.04, 0.26, pow(power, 1.4)) * shimmer * brightness;

	// Grade against the NEAREST socket: class_ii's six patches share one surface and
	// therefore one material, so a fragment has to find its own nozzle. Distances are
	// normalised by that socket's radius, which is why sockets of different sizes
	// (class_ii carries both 8.60 and 5.17) grade identically.
	float shape = 1.0;
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
				// Measured signs differ per socket (class_ii socket 0 runs +0.80 r,
				// socket 1 runs -0.78 r off the same authored plane), so depth is the
				// absolute distance from the socket plane, not a signed one.
				depth_n = abs(along) / r;
			}
		}
		float rim = 1.0 - smoothstep(border_start, border_end, radial_n);
		float core = mix(1.0, core_boost, 1.0 - smoothstep(0.0, 0.85, radial_n));
		float depth_keep = 1.0 - depth_dim * smoothstep(0.35, 1.6, depth_n);
		shape = rim * core * depth_keep;
	}
	vec3 tint = mix(cool_color.rgb, hot_color.rgb, smoothstep(0.12, 0.78, temperature));
	vec3 white_core = mix(tint * plasma_color.rgb, vec3(1.0), 0.85 * temperature);

	ALBEDO = white_core * energy * visibility * shape;
	EMISSION = vec3(0.0);
	// The old 0.45 floor stopped grazing faces from ever fading, which is what spread
	// the white past the nozzle rim. `shape` carries into ALPHA as well: under
	// blend_add a zero ALBEDO already contributes nothing, but the old 0.06 floor
	// would otherwise leave a faint plate exactly where the border is meant to end it.
	ALPHA = clamp(mix(0.55, 0.85, power) * visibility * shape, 0.0, 0.85);
}
