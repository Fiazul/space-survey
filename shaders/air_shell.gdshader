shader_type spatial;
// The sky, seen from INSIDE an atmosphere.
//
// The cook shader paints an atmospheric limb for a globe viewed from outside.
// From 15 km up there was nothing at all: black space and stars, which left the
// terrain's haze with nothing to fade into. This is that something.
//
// An inward-facing sphere centred on the ship. `blend_add` over the starfield on
// purpose, so stars stay faintly visible through a thin sky the way they do in
// the reference frame; `depth_draw_never` with depth TEST still on, so terrain
// and the planet's own globe occlude it and it only paints where sky is visible.
render_mode unshaded, blend_add, depth_draw_never, cull_front, shadows_disabled, fog_disabled;

// How much sky there is. PlanetGenerator.air_shell_opacity(): depth^1.5 x
// air_amount, so 0.78 at 15 km of Earth's 100 km column and 0.09 at 80 km —
// a real sky in the band, black space in orbit.
uniform float opacity = 0.0;
uniform vec3 color_air : source_color = vec3(0.30, 0.56, 1.0);
uniform vec3 sun_warm : source_color = vec3(1.00, 0.86, 0.62);
uniform vec3 sun_dir = vec3(0.72, 0.28, 0.63);
uniform vec3 up_dir = vec3(0.0, 1.0, 0.0);   // ship -> away from the body's centre
// The shared terminator, from PlanetGenerator.TERMINATOR_*. Scattered light needs
// SUNLIGHT on the air: without this the sky glowed blue on the night side while
// the ground beside it was black, which is the third item in the standing physics
// note (NEEDS-YOUR-EYES.md).
uniform float term_lo = -0.04;
uniform float term_hi = 0.28;
// Sky brightness at the zenith relative to the horizon. Looking straight up you
// see through the thin column above you; looking at the horizon you look along a
// far longer slant of it, which is why a horizon band exists at all and why
// looking OUT past the limb from altitude has to go dark rather than stay blue.
uniform float zenith_floor = 0.12;

varying vec3 v_dir;


void vertex() {
	v_dir = normalize(VERTEX);
}


void fragment() {
	// NO early `return` here: Godot rejects return in a fragment processor
	// ("Using 'return' in the 'fragment' processor function is incorrect"), and
	// the shader silently fails to compile - the material just renders nothing
	// while a SHADER ERROR goes to stderr where no GDScript assertion can see it.
	// Gate with a multiply instead.
	float on = step(0.001, opacity);
	vec3 d = normalize(v_dir);
	vec3 u = normalize(up_dir);
	// 1 at the zenith, 0 at the horizon, negative below it.
	float up = dot(d, u);

	// AIR MASS ALONG THE VIEW RAY. The old version was brightest at the zenith
	// and only faded below the horizon, so from altitude the sky stayed blue in
	// every outward direction - including straight into space. Air mass is
	// smallest looking up through the thin column and largest along the horizon
	// slant, so this is what makes the vacuum overhead go dark.
	float airmass = mix(1.0, zenith_floor, pow(clamp(up, 0.0, 1.0), 0.65));

	// Sunlit-ness of the air around the observer, on the SAME curve the ground
	// and the globe use. No sun on the air, no scattering, no blue.
	float sunlit = smoothstep(term_lo, term_hi, dot(u, normalize(sun_dir)));

	// Same forward-scattering rule the terrain haze uses, so the shell and the
	// ground meet in one colour instead of showing a seam between them.
	float warmth = pow(max(dot(d, normalize(sun_dir)), 0.0), 2.0);
	vec3 horizon = mix(color_air, sun_warm, warmth);
	// Deep air colour overhead, the scattered band at the horizon. The horizon
	// band is deliberately narrow — smoothstep over the first 0.35 of the dome —
	// because a linear ramp reads as a gradient wash rather than as air.
	vec3 col = mix(horizon, color_air * 0.75, smoothstep(0.0, 0.35, up));

	// Below the horizon the ground normally covers this, but do not let the shell
	// paint under it when the ground is missing.
	float below = smoothstep(-0.12, 0.02, up);

	ALBEDO = col * opacity * airmass * sunlit * below * on;
	ALPHA = 1.0;
}
