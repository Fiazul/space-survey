shader_type spatial;
// Lit, hazed ground for the skin-band rings.
//
// `render_mode unshaded` means GODOT adds no lighting of its own. It does NOT
// mean the terrain is unlit — this shader computes N.L itself from `sun_dir`,
// using the SAME terminator curve planet_cook.gdshader runs (term_lo / term_hi
// are bound to both materials from PlanetGenerator.TERMINATOR_*). That sharing is
// the point: the tile meets the globe at its own outer edge, and a
// Godot-lambert-versus-project-curve mismatch would show up exactly there.
//
// HOUSE RULE: `unshaded` DISCARDS EMISSION. Everything goes on ALBEDO.
render_mode unshaded, cull_back;

#include "res://shaders/planet_color.gdshaderinc"

uniform int kind = 0;                            // PlanetGenerator._kind_id() — gates the
                                                  // rocky-only land tint/ocean blend below,
                                                  // same gate planet_cook.gdshader uses.
uniform vec3 sun_dir = vec3(0.72, 0.28, 0.63);   // body -> star, normalized
uniform float term_lo = -0.04;                   // PlanetGenerator.TERMINATOR_LO
uniform float term_hi = 0.28;                    // PlanetGenerator.TERMINATOR_HI
// Starlight, body-shine and scattered air on the side facing away from the sun.
// Never zero: a night side at pure black loses the horizon and reads as a hole.
uniform float night_fill = 0.06;

// --- Aerial perspective ---
uniform float air_amount = 0.0;                  // 0 = vacuum, no haze at all
uniform vec3 color_air : source_color = vec3(0.30, 0.56, 1.0);
uniform vec3 sun_warm : source_color = vec3(1.00, 0.86, 0.62);
// Distance at which haze reaches 63%. 70 km dissolves ring 3's 204.8 km rim to
// 95% while leaving the first 20 km at 25% — see the spec's swept table.
uniform float haze_km = 70.0;
uniform float haze_density = 1.0;                // thicker the lower you fly

// --- Maps, sampled PER FRAGMENT ---
// The tile used to take its colour entirely from vertex colours, inherited from
// when it was a small unshaded plate. Ring scale now follows the horizon, so at
// 13 km altitude ring 3's quads are 10.24 km across - and a coastline quantised
// to 10 km vertices is a giant hard-edged angular wedge, which is what showed up
// in play. The globe's own shader has always sampled its maps at UV; this one now
// does too, so the shoreline resolves at the MAP's resolution instead of the
// MESH's. COLOR still carries the procedural palette, which supplies the detail
// the 19.5 km-per-texel map has none of.
uniform sampler2D albedo_tex : source_color, hint_default_white, filter_linear_mipmap;
uniform sampler2D water_tex : hint_default_black, filter_linear_mipmap;
uniform float has_albedo = 0.0;
uniform float has_water = 0.0;
uniform vec3 color_ocean : source_color = vec3(0.06, 0.22, 0.32);
uniform float map_weight = 0.0;    // how much the map still knows; see TerrainSampler
uniform float body_radius_km = 6371.0;
uniform float rock_amount = 1.0;
uniform float liquid_amount = 0.0;
uniform float lava_amount = 0.0;
uniform float ice_surface = 0.0;
uniform float snow_line_km = 0.0;
uniform float snow_polar_drop_km = 0.0;
uniform float sea_ice_latitude = 1.0;
uniform float tree_line_km = 3.5;
uniform float vegetation_density = 0.0;
uniform bool vegetation_from_albedo = false;
uniform float wave_strength = 0.09;
uniform float wave_scale = 1.0;
uniform float surface_seed = 0.0;
// Nearest authored district; zero radius on uninhabited recipes.
uniform vec3 district_center = vec3(0.0);
uniform vec3 district_east = vec3(1.0, 0.0, 0.0);
uniform vec3 district_north = vec3(0.0, 0.0, 1.0);
uniform float district_radius = 0.0;
// Per-ring fade for streamed commits. Default 1 so a cold bind matches the
// pre-stream look; only a freshly swapped ring ever writes a value below 1.
instance uniform float stream_fade : hint_range(0.0, 1.0) = 1.0;

// Mirrors TerrainSampler.ICE_ALBEDO_LUM_MIN (0.45, measured on the RAW sRGB PNG
// bytes). Textures bound `source_color` are linearized by the GPU sampler, so the
// same physical cut sits lower here — approx 0.45 sRGB -> ~0.17 linear.
const float ICE_ALBEDO_LUM_MIN = 0.17;

// Shoreline bands, in KILOMETRES of real distance from the wet/dry boundary —
// see the shore_km derivation in fragment() for why this is resolution-independent
// of the water mask's own texel size.
// The mask is ~19.6 km/texel on Earth (2048 px around the circumference) — its
// bilinearly-interpolated 0.5 contour is a STAIRCASE at that scale wherever a
// coastline crosses the texel grid at an angle, because the raster genuinely does
// not know the true coastline path between texels. No sampler/filter setting fixes
// that (verified: mipmaps regenerated for earth_spec_2k.png, tried both
// filter_linear_mipmap and filter_linear_mipmap_anisotropic — the staircase is
// identical, since it isn't a view-dependent minification artifact). These bands
// are the narrowest that still read as a clean line rather than the mask's own
// texel steps; going tighter reproduces the raw raster staircase, not a smoother
// shoreline, until the mask itself is higher-resolution.
const float FOAM_BAND_KM = 0.08;      // ~80 m: a shoreline, not a coastal shelf
const float SHALLOW_BAND_KM = 0.35;   // ~350 m of lighter water either side of it
// Ripple invisible past this camera distance — bounds the aliasing region rather
// than letting a screen-filling ocean plate carry a screen-filling moiré.
const float RIPPLE_FADE_KM = 3.0;
// FOV-driven natural world-size of one screen pixel per km of distance (70 deg
// vertical FOV / 720 px project-default height: 2*tan(35 deg)/720 = 0.00195),
// with headroom so it never clips a correctly-resolved close mesh - see the
// footprint ceiling note in fragment().
const float FOOTPRINT_CEIL_PER_KM = 0.0035;

varying vec3 v_world_n;
varying vec3 v_radial;
varying float v_height;
varying vec3 v_surface;

float grain_hash(vec3 p) {
	// Keep hash arithmetic bounded: sin(dot(planet_km * frequency, ...))
	// loses precision and produces rectangular discontinuities on large worlds.
	p = fract(p * vec3(0.1031, 0.1030, 0.0973));
	p += dot(p, p.yxz + 33.33);
	return fract((p.x + p.y) * p.z);
}

float grain(vec3 p) {
	vec3 cell = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(grain_hash(cell), grain_hash(cell + vec3(1, 0, 0)), f.x),
		mix(grain_hash(cell + vec3(0, 1, 0)), grain_hash(cell + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(grain_hash(cell + vec3(0, 0, 1)), grain_hash(cell + vec3(1, 0, 1)), f.x),
		mix(grain_hash(cell + vec3(0, 1, 1)), grain_hash(cell + vec3(1, 1, 1)), f.x), f.y), f.z);
}


void vertex() {
	// The tile's parent carries translation only (floating origin), so the model
	// normal is already the world normal — but go through MODEL_MATRIX anyway so a
	// future rotation cannot silently break the lighting.
	v_world_n = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	v_radial = normalize((MODEL_MATRIX * vec4(normalize(VERTEX), 0.0)).xyz);
	v_height = length(VERTEX) - body_radius_km;
	v_surface = VERTEX;
}


void fragment() {
	// Procedural palette from the vertex, then the MAP at this fragment's own UV
	// wherever the map still has information to give.
	vec3 alb = COLOR.rgb;
	if (has_albedo > 0.5 && map_weight > 0.001) {
		alb = mix(alb, texture(albedo_tex, UV).rgb, 1.0);
	}
	// Pre-tint map colour, kept for the ocean blend below — planet_cook.gdshader
	// mixes the RAW map texel toward color_ocean, tinting only the land half.
	vec3 map_alb = alb;
	if (kind == KIND_ROCKY) {
		alb = land_tint_color(alb);
	}
	// VERTEX is the fragment's VIEW-space position, so its length is the distance
	// to the camera in world units — kilometres in Sol. Read early: the ripple
	// fade below needs it too, not just the haze at the bottom.
	float dist_km = length(VERTEX);
	// Shoreline from the mask, PER FRAGMENT. COLOR.a carries the vertex-level
	// wetness as the fallback for worlds with no mask.
	float wet = COLOR.a;
	// The mask says water, but permanent/sea ice reflects like snow, not ocean —
	// same override as TerrainSampler.ice01(), applied per-texel here because this
	// branch re-samples the mask at the fragment's own UV, bypassing the vertex
	// COLOR.a the CPU already fixed up.
	float ice_mask = 0.0;
	// The MASK alone, with none of wet's other factors mixed in — used only for
	// shore_km below. v_height is a per-VERTEX varying, linearly interpolated
	// across each ring triangle; folding its height-fade into the same value used
	// for the foam/shallow distance made the foam band facet along the mesh's own
	// triangle edges at a grazing angle (confirmed by disabling the ripple and the
	// mipmap fixes separately — neither changed the pattern, but this did). The
	// mask by itself has no per-vertex interpolation, so it stays smooth.
	float mask01 = 0.0;
	if (has_water > 0.5) {
		float mask_raw = texture(water_tex, UV).r;
		mask01 = smoothstep(0.35, 0.65, mask_raw);
		wet = mask01 * (1.0 - smoothstep(0.04, 0.32, v_height));
		if (has_albedo > 0.5 && mask_raw > 0.5) {
			float lum = dot(texture(albedo_tex, UV).rgb, vec3(0.299, 0.587, 0.114));
			ice_mask = smoothstep(ICE_ALBEDO_LUM_MIN, ICE_ALBEDO_LUM_MIN + 0.06, lum)
				* smoothstep(sea_ice_latitude, sea_ice_latitude + 0.12, abs(normalize(v_surface).y));
			wet *= (1.0 - ice_mask);
		}
	}
	wet *= liquid_amount;
	// World-anchored substrate at kilometre and hundred-metre scales. footprint is
	// needed here too, for the fine octave fade further down.
	float footprint = length(fwidth(v_surface));
	// Ring LOD jumps quad size 4x with no transition (SurfacePatch.RING_STEP), so
	// fwidth of the mesh's own position steps discretely right at each ring's
	// inner boundary, and every consumer below (mask_reliable, fine, ripple_fade)
	// steps with it - a straight seam line across the frame (reported:
	// moon_1km_nadir_lowsun, a near-nadir view chosen specifically because a
	// grazing angle would have hidden it in foreshortening). dist_km is
	// screen-space CONTINUOUS (an interpolated view-space length, no ring
	// dependency) - the same fix SurfacePatch._detail_km_at() already applies to
	// the identical class of bug (a ring-boundary texture-change band, fixed by
	// deriving detail_km from distance instead of from which ring is asking).
	// The ceiling only clips the artificial spike a coarser ring produces right
	// after its own boundary, pulling that spike back down toward the continuous
	// curve the finer ring was already on.
	footprint = min(footprint, dist_km * FOOTPRINT_CEIL_PER_KM);
	// Distance to the mask's 0.5 boundary, IN REAL KILOMETRES — computed
	// ANALYTICALLY from the mask's own texel size, not from a per-pixel
	// screen-space derivative. A derivative version (footprint / |d(mask01)|) was
	// tried first and was numerically unstable: water_tex has no mipmaps, so at a
	// shallow viewing angle the UV changes faster than one texel per screen pixel,
	// minification-aliases mask_raw, and the division amplifies that noise into a
	// jagged static band along the near shoreline. The mask's 0.35-0.65 smoothstep
	// is crossed over roughly 0.3 texels of PHYSICAL width (the raw mask goes 0->1
	// across about one texel at a coastline), so scaling by the texture's own
	// resolution and the body's true circumference gives the same number with none
	// of the per-pixel noise, and it re-derives correctly if the mask is ever
	// re-fetched at a different resolution.
	float texel_km = 1000.0;
	if (has_water > 0.5) {
		float water_texels = float(textureSize(water_tex, 0).x);
		if (water_texels > 0.0) {
			texel_km = (6.283185307 * body_radius_km) / water_texels;
		}
	}
	float shore_km = abs(mask01 - 0.5) * 0.3 * texel_km;
	// Once a pixel's footprint grows past the mask's own texel size — a grazing
	// horizon view, or a coarse distant ring — the mask is being minified with no
	// mipmap chain, so treating its instantaneous sample as "very close to 0.5" is
	// noise, not a coastline. Without this gate that noise painted a false foam
	// line along the ENTIRE horizon. Real coastlines are always seen at a
	// footprint far under one texel by the time they matter (a ship is never
	// looking at the ground 20 km beneath its own texel from orbit).
	float mask_reliable = 1.0 - smoothstep(texel_km * 0.5, texel_km * 2.0, footprint);
	float foam_t = clamp(1.0 - shore_km / FOAM_BAND_KM, 0.0, 1.0) * mask_reliable;
	float shallow_t = clamp(1.0 - shore_km / SHALLOW_BAND_KM, 0.0, 1.0) * mask_reliable;
	// Same map/flat-colour ratio the globe uses for open ocean (OCEAN_MAP_BLEND)
	// — the ring used to run this blend all the way to color_ocean (a flat
	// swatch with none of the map's own variation), which is the ocean colour
	// jump reported at the globe/ring handoff.
	vec3 ocean_base = (kind == KIND_ROCKY) ? ocean_base_color(map_alb, color_ocean) : color_ocean;
	vec3 shallow_col = mix(ocean_base, vec3(0.14, 0.40, 0.42), 0.6);
	vec3 water_col = mix(ocean_base, shallow_col, shallow_t);
	alb = mix(alb, water_col, clamp(wet, 0.0, 1.0));
	alb = mix(alb, vec3(0.80, 0.86, 0.92), ice_mask * 0.85);
	// Alpine snow cover from height. Slope fade waits until `slope` exists below.
	float snow = 0.0;
	if (snow_line_km > 0.001 && wet < 0.999) {
		// Broad accumulation follows terrain rather than a ruler-straight height
		// contour. Smaller wind drifts soften its edge without a cracked-ice net.
		float drift = grain(v_surface * 0.65) - 0.5;
		float latitude = abs(normalize(v_surface).y);
		float local_line = max(0.0, snow_line_km - snow_polar_drop_km * latitude * latitude) + drift * 0.7;
		snow = smoothstep(local_line - 0.15, local_line + 0.85, v_height);
		snow *= (1.0 - clamp(wet, 0.0, 1.0)) * (1.0 - ice_mask);
	}
	// Fade the fine octave when pixels become larger than it, avoiding distant
	// shimmer.
	float coarse = 0.0;
	float fine = 0.0;
	if (wet < 0.999) {
		coarse = grain(v_surface * 0.8) - 0.5;
		if (footprint < 0.2) {
			fine = (grain(v_surface * 8.0) - 0.5) * (1.0 - smoothstep(0.03, 0.2, footprint));
		}
	}
	alb *= 1.0 + (coarse * 0.22 + fine * 0.12) * (1.0 - wet * 0.7);
	vec3 n = normalize(v_world_n);
	vec3 l = normalize(sun_dir);
	vec3 view_w = normalize((INV_VIEW_MATRIX * vec4(normalize(VERTEX), 0.0)).xyz);
	vec3 radial = normalize(v_radial);
	float slope = 1.0 - clamp(dot(n, radial), 0.0, 1.0);
	// Snow collects on shelves and releases from steep rock faces.
	snow *= 1.0 - smoothstep(0.12, 0.42, slope);
	vec3 snow_albedo = mix(vec3(0.68, 0.77, 0.86), vec3(0.91, 0.94, 0.97),
		0.65 + coarse * 0.35 + fine * 0.12);
	alb = mix(alb, snow_albedo, snow);
	// Distant forest becomes filtered canopy colour rather than thousands of
	// subpixel triangles. Explicit biosphere control; liquid alone isn't life.
	if (vegetation_density > 0.001 && wet < 0.999) {
		float green = vegetation_from_albedo ? smoothstep(0.0, 0.045,
			map_alb.g - max(map_alb.r, map_alb.b) * 1.05) : 1.0;
		float latitude = abs(normalize(v_surface).y);
		float snow_limit = snow_line_km > 0.001
			? max(0.0, snow_line_km - snow_polar_drop_km * latitude * latitude) - 0.5 : tree_line_km;
		float treeline = min(tree_line_km, snow_limit);
		float forest = vegetation_density * green * (1.0 - wet) * (1.0 - snow)
			* (1.0 - ice_mask) * (1.0 - smoothstep(0.85, 0.96, latitude))
			* (1.0 - smoothstep(max(0.0, treeline - 0.5), max(0.001, treeline), v_height))
			* (1.0 - smoothstep(0.12, 0.22, slope));
		float crowns = mix(0.5, grain(v_surface * 45.0),
			1.0 - smoothstep(0.01, 0.06, footprint));
		vec3 canopy = mix(vec3(0.045, 0.085, 0.026), vec3(0.11, 0.20, 0.055), crowns);
		alb = mix(alb, canopy, forest * 0.8);
	}
	// Weathered streets share the building plot grid, conform to the actual
	// ground mesh and remain visible beyond the individual-building budget.
	if (district_radius > 0.0 && wet < 0.999) {
		vec3 offset = v_surface - district_center;
		vec2 city = vec2(dot(offset, district_east), dot(offset, district_north));
		float district = (1.0 - smoothstep(district_radius - 0.15, district_radius, length(city)))
			* (1.0 - wet) * (1.0 - snow) * (1.0 - smoothstep(0.08, 0.2, slope));
		vec2 plot = abs(fract(city / 0.12) - 0.5) * 0.12;
		float street_distance = 0.06 - max(plot.x, plot.y);
		float aa = max(footprint * 0.7, 0.0004);
		float street = 1.0 - smoothstep(0.008 - aa, 0.008 + aa, street_distance);
		float slab = 1.0 - smoothstep(0.045 - aa, 0.048 + aa, max(plot.x, plot.y));
		float wear = grain(vec3(city.x * 130.0, 0.0, city.y * 130.0));
		alb = mix(alb, vec3(0.14, 0.13, 0.10), district * 0.45);
		vec3 worn = mix(vec3(0.095, 0.09, 0.072), vec3(0.18, 0.16, 0.13), wear);
		alb = mix(alb, worn, district * slab * 0.7);
		alb = mix(alb, vec3(0.043, 0.045, 0.042) * (0.8 + wear * 0.4), district * street * (0.45 + wear * 0.42));
	}
	vec3 p = v_surface + vec3(surface_seed);
	float exposed = rock_amount * (1.0 - wet) * (1.0 - ice_surface) * (1.0 - ice_mask) * (1.0 - snow);
	if (exposed > 0.001) {
		float rock_fine = 0.5;
		if (footprint < 0.04) {
			rock_fine = mix(0.5, grain(p * 32.0), 1.0 - smoothstep(0.008, 0.04, footprint));
		}
		float strata = sin(v_height * 110.0 + grain(p * 0.3) * 12.0);
		alb *= 1.0 + exposed * (0.13 * strata * smoothstep(0.005, 0.12, slope) + (rock_fine - 0.5) * 0.20);
	}
	// Fractures across frozen ground: no liquid mask or water glint on Europa.
	if (ice_surface > 0.001) {
		float crack_noise = grain(p * 0.6) + 0.16 * grain(p * 3.0);
		float crack = (1.0 - smoothstep(0.012, 0.04, abs(crack_noise - 0.56))) * ice_surface;
		alb = mix(alb, vec3(0.19, 0.32, 0.40), crack * 0.65);
		alb = mix(alb, vec3(0.62, 0.76, 0.84), ice_surface * 0.22 * (1.0 - crack));
	}
	// Two travelling layers at unrelated scales AND a relative rotation, so their
	// sum never lines up into a repeating grid. The old single 3-axis sin sum's
	// wavelengths (about 70/77/86 m) beat against the ring quad sizes
	// (40/160/640/2560 m) into exactly the regular screen-space moiré that was
	// reported. Faded by both camera distance and pixel footprint, the same way
	// the fine rock grain above fades: ripple finer than a pixel can resolve reads
	// as aliasing noise, not water, so it fades out instead of aliasing.
	float ripple_fade = (1.0 - smoothstep(0.0, RIPPLE_FADE_KM, dist_km))
		* (1.0 - smoothstep(0.02, 0.10, footprint));
	// Three nonparallel wave directions projected onto the local tangent plane.
	// Derivative of wave height supplies normals; no full-screen refraction pass.
	if (wet > 0.001 && ripple_fade > 0.001) {
		vec3 local_up = normalize(v_surface);
		vec3 wa = normalize(vec3(0.81, 0.23, 0.54));
		vec3 wb = normalize(vec3(-0.37, 0.86, 0.35));
		vec3 wc = normalize(vec3(0.21, -0.47, 0.86));
		vec3 ripple = wa * cos(dot(p, wa) * 34.0 * wave_scale - TIME * 1.9)
			+ wb * cos(dot(p, wb) * 73.0 * wave_scale - TIME * 2.7) * 0.48
			+ wc * cos(dot(p, wc) * 139.0 * wave_scale - TIME * 3.6) * 0.22;
		ripple -= local_up * dot(ripple, local_up);
		ripple = (MODEL_MATRIX * vec4(ripple, 0.0)).xyz;
		n = normalize(n + ripple * wet * wave_strength * ripple_fade);
	}
	float day = smoothstep(term_lo, term_hi, dot(normalize(v_radial), l));
	// UV2.y carries SurfacePatch._horizon_shadow()'s per-vertex cast-shadow
	// factor (rings 0-2 only; ring 3 defaults to 1.0 - see
	// HORIZON_SHADOW_MAX_RING). Only the DIRECT term is gated, never the
	// ambient floor (0.18) or the night side (night_fill) - a fully shadowed
	// crater bowl still reads as ground, not a hole into space.
	float sun_shadow = clamp(UV2.y, 0.0, 1.0);
	// The terminator alone saturates across the entire day side, flattening hills.
	float lit = mix(night_fill, 0.18 + 0.82 * max(dot(n, l), 0.0) * sun_shadow, day);
	vec3 col = alb * lit;
	float fresnel = pow(1.0 - max(dot(n, -view_w), 0.0), 5.0);
	float glint = pow(max(dot(reflect(-l, n), -view_w), 0.0), 110.0);
	col += wet * day * (vec3(1.0, 0.84, 0.59) * glint * 1.4 + vec3(0.08, 0.16, 0.24) * fresnel);
	float ice_glint = pow(max(dot(reflect(-l, n), -view_w), 0.0), 60.0);
	col += ice_mask * day * vec3(0.9, 0.95, 1.0) * ice_glint * 0.55;
	// Snow is a rough diffuse surface, with a subdued broad highlight.
	float snow_glint = pow(max(dot(reflect(-l, n), -view_w), 0.0), 12.0);
	col += snow * day * sun_shadow * vec3(0.92, 0.96, 1.0) * snow_glint * 0.08;
	float shore_surge = 0.65 + 0.35 * sin(TIME * 0.9 - shore_km * 140.0 + coarse * 4.0);
	col += foam_t * lit * vec3(0.85, 0.9, 0.92) * shore_surge * 0.6 * liquid_amount * (1.0 - ice_mask);
	// Broad reflected sky makes liquid read as a surface even away from the sun.
	col += wet * day * air_amount * fresnel * color_air * 0.22;
	// UV2 carries the SAME volcanic regions that generated the caldera geometry.
	// Uniform branch: Earth pays no per-pixel volcanic noise cost.
	if (lava_amount > 0.001) {
		float volcanic = clamp(UV2.x * lava_amount, 0.0, 1.0);
		float channels = 1.0 - smoothstep(0.015, 0.055, abs(grain(p * 1.6) + grain(p * 4.0) * 0.2 - 0.58));
		float molten = max(smoothstep(0.975, 0.995, volcanic), channels * smoothstep(0.08, 0.8, volcanic) * 0.8);
		col = mix(col, vec3(0.025, 0.018, 0.014) * lit, volcanic * 0.72);
		float pulse = 0.82 + 0.18 * sin(TIME * 1.7 + grain(p * 3.0) * 9.0);
		col += mix(vec3(1.6, 0.075, 0.003), vec3(3.2, 0.85, 0.035), molten) * molten * pulse;
	}

	float haze = (1.0 - exp(-dist_km / max(haze_km, 0.001)));
	haze *= air_amount * haze_density;

	// Forward scattering: looking toward the star, the haze goes warm; looking
	// away it stays the air's own colour. This is what makes a horizon read as
	// atmosphere rather than as a grey fog constant.
	float warmth = pow(max(dot(view_w, l), 0.0), 2.0);
	vec3 haze_col = mix(color_air, sun_warm, warmth);
	// The haze is itself lit. Without this it glows on the night side and the
	// dark hemisphere ends up brighter than the ground it is covering.
	haze_col *= lit;

	ALBEDO = mix(col, haze_col, clamp(haze, 0.0, 1.0)) * stream_fade;
}
