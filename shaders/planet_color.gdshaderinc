// Shared per-material colour decisions between planet_cook.gdshader (the
// globe) and terrain_tile.gdshader (the surface ring) — see PLANET_GENERATOR.md
// "one recipe, one shader". These are the terms that must come out numerically
// IDENTICAL at the SurfacePatch.should_show handoff, not every colour the
// ring's own near-field extras (shoreline foam, ripple, rock grain) add on
// top of them. Touch a constant here, both shaders' base colour move together.

// Kind IDs, mirrored from PlanetGenerator._kind_id(). Only rocky bodies with a
// real albedo map (Earth) get the land tint and the map/flat-colour ocean
// blend below — other kinds keep their own existing look, unaffected.
const int KIND_ROCKY = 0;

// Rocky land reads slightly warm/desaturated against its raw map texel — the
// globe has applied this since the first cook; the ring never did, so its
// map-sampled land read flatter/greener than the globe over the same spot.
const vec3 LAND_TINT = vec3(1.10, 1.12, 0.94);

// Flat per-body albedo gain (PLANET_GENERATOR.md "Exposure"). GDScript-side
// bound per-body — SurfaceRecipe.resolve()'s `exposure` field, refined by
// SurfacePatch.bind_recipe() once a real sampler exists to measure the
// body's actual mean ground colour. PlanetGenerator._cook_material() binds
// the same recipe's flat-colour estimate (no sampler at that call site), so
// the globe and the ring agree within the ring's later, sampler-refined gain.
uniform float exposure : hint_range(1.0, 4.0) = 1.0;

vec3 apply_exposure(vec3 col) {
	return col * exposure;
}

vec3 land_tint_color(vec3 map_alb) {
	return apply_exposure(map_alb * LAND_TINT);
}

// How much of the raw map texel still shows through open ocean, vs the
// recipe's flat colour, at the shader's "detail" == 0 (far/globe) end.
// planet_cook.gdshader's own long-standing ratio (mix(0.55, 0.22, detail) at
// detail 0). The ring's per-fragment water blend used to run 100% to the
// recipe's flat colour with none of the map's variation — a flat colour
// swatch — which is the ocean jump the player reported.
const float OCEAN_MAP_BLEND = 0.55;

vec3 ocean_base_color(vec3 map_alb, vec3 color_ocean) {
	return apply_exposure(mix(map_alb, color_ocean, OCEAN_MAP_BLEND));
}
