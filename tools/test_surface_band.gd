extends SceneTree
# Contract check for the skin band — the bird-eye ground tile.
# Run: godot --headless --path . --script res://tools/test_surface_band.gd
#
# Why this exists: before this slice the tile was UNREACHABLE CODE. should_show()
# allowed only Earth, and ground_stamp_ok() asked for `alt > kill and alt < 3.0`
# with Earth's kill at 29 km — a window that is empty for every altitude. So
# _rebuild, the prop MultiMesh and the height sampling had never once rendered,
# and no test noticed, because every assertion was about the numbers rather than
# about whether the band contains anything at all.
#
# So the first thing this file asserts is that each band is NON-EMPTY. Then that
# the tile never binds Earth's maps on another world, and never appears in an
# arcade system where "altitude" is not in kilometres.

const G := preload("res://scripts/world/planet_generator.gd")
const SP := preload("res://scripts/world/surface_patch.gd")

const E := preload("res://scripts/autoload/ephemeris.gd")
# The contact margin, read from the SHIPPED constant rather than copied. It was
# 29.0 for Earth and 0.1 elsewhere, back when the kill was an altitude bubble.
#
# Read, not copied, on purpose: with a local 0.02 here, widening the shipped
# margin back to 29 km left every assertion in this file green while Earth's band
# was actually shut in the game - the exact decoupling that let the band sit
# unreachable for two slices without a single test noticing.
const EARTH_KILL := E.CONTACT_KILL_FLOOR_KM
const AIRLESS_KILL := E.CONTACT_KILL_FLOOR_KM


func _initialize() -> void:
	var failed := 0
	failed += _band()
	failed += _kits()
	failed += _sources()
	failed += _crust()
	failed += _tile()
	if failed == 0:
		print("surface_band: OK")
		quit(0)
	else:
		print("surface_band: FAIL %d" % failed)
		quit(1)


# --- The band has to actually contain altitudes ------------------------------
func _band() -> int:
	var failed := 0
	var moon := G.recipe_for({"name": "Moon"})
	var earth := G.recipe_for({"name": "Earth"})

	# Sweep 0..120 km in 10 m steps and count what each world would show.
	var moon_alts := _open_window(moon, AIRLESS_KILL)
	var earth_alts := _open_window(earth, EARTH_KILL)

	failed += _check("airless_band_is_not_empty", moon_alts.size() > 0)
	failed += _check("airless_band_starts_above_the_kill_line",
		moon_alts.size() > 0 and float(moon_alts[0]) > AIRLESS_KILL)
	failed += _check("airless_band_ends_below_the_ceiling",
		moon_alts.size() > 0 and float(moon_alts[-1]) < _ceiling_of(moon))
	# The whole point of going airless-first: a band you can actually fly in.
	failed += _check("airless_band_is_at_least_2km_thick",
		moon_alts.size() > 0 and float(moon_alts[-1]) - float(moon_alts[0]) > 2.0)

	# EARTH'S BAND IS LIVE. This is the inverse of an assertion planted two slices
	# ago (earth_band_still_empty_until_the_kill_line_moves) specifically so that
	# moving the kill line would announce itself. It has.
	failed += _check("earth_band_is_no_longer_empty", earth_alts.size() > 0)
	failed += _check("earth_band_reaches_everest_height",
		earth_alts.size() > 0 and float(earth_alts[-1]) > 8.848)
	failed += _check("earth_band_opens_near_the_ground",
		earth_alts.size() > 0 and float(earth_alts[0]) < 0.2)
	# ...and the regression that closed it stays closed.
	failed += _check("no_tile_at_earth_ez",
		not G.ground_stamp_ok(100.0, EARTH_KILL, _ceiling_of(earth)))
	failed += _check("no_tile_in_earth_air",
		not G.ground_stamp_ok(50.0, EARTH_KILL, _ceiling_of(earth)))

	# A gas giant / a star has no surface to stand a plate on, at any altitude.
	var jup := G.recipe_for({"name": "Jupiter"})
	var sun := G.recipe_for({"name": "Sun"})
	failed += _check("gas_giant_gets_no_tile", _open_window(jup, AIRLESS_KILL).is_empty())
	failed += _check("star_gets_no_tile", _open_window(sun, AIRLESS_KILL).is_empty())

	# An arcade system reports "altitude" in 0.01-AU units. A tile there would be a
	# ground plate floating in deep space.
	failed += _check("arcade_system_gets_no_tile",
		not SP.should_show("Kepler-22b", false, 1.0, AIRLESS_KILL, _ceiling_of(moon), moon))
	failed += _check("nameless_body_gets_no_tile",
		not SP.should_show("", true, 1.0, AIRLESS_KILL, _ceiling_of(moon), moon))

	# The five plate assertions that stood here (plate_grows_with_altitude,
	# plate_never_below_min / above_max, plate_always_dwarfs_the_altitude,
	# tile_plate_scales_to_the_altitude) described tile_km_for(), which four nested
	# rings retired: rings are a fixed size and reach 205 km, so a plate-to-altitude
	# ratio no longer describes anything. Ring geometry is asserted in
	# tools/test_earth_terrain.gd _rings(); the ceiling rule that replaced the ratio
	# is asserted in its _band().

	print("surface_band: airless band %.2f..%.2f km (ceiling %.2f from %.2f km of relief)"
		% [float(moon_alts[0]), float(moon_alts[-1]), _ceiling_of(moon),
		G.terrain_sampler(moon).max_height_km()])
	print("surface_band: EARTH band %.2f..%.2f km (ceiling %.2f from %.2f km of terrain) — LIVE"
		% [float(earth_alts[0]), float(earth_alts[-1]), _ceiling_of(earth),
		G.terrain_sampler(earth).max_height_km()])
	return failed


# Every altitude in 0..120 km at which this world would show a ground tile.
func _open_window(recipe: Dictionary, kill: float) -> Array:
	var out := []
	var ceiling := _ceiling_of(recipe)
	for i in 12000:
		var alt := float(i) * 0.01
		if SP.should_show("Probe", true, alt, kill, ceiling, recipe):
			out.append(alt)
	return out


# This world's own band ceiling, from its terrain's height.
func _ceiling_of(recipe: Dictionary) -> float:
	return G.band_ceiling_km(G.terrain_sampler(recipe))


# --- The kit is chosen by physics, not by colour -----------------------------
func _kits() -> int:
	var failed := 0
	var earth := G.recipe_for({"name": "Earth"})
	var moon := G.recipe_for({"name": "Moon"})
	var mars := G.recipe_for({"name": "Mars"})
	var europa := G.recipe_for({"name": "Europa"})
	var jup := G.recipe_for({"name": "Jupiter"})

	failed += _check("earth_gets_vegetation", G.surface_kit(earth) == "tree")
	# The load-bearing one: an airless world must NOT grow trees. A biosphere needs
	# air and standing liquid, and the Moon has neither.
	failed += _check("moon_gets_rock_not_trees", G.surface_kit(moon) == "rock")
	failed += _check("mars_gets_rock_not_trees", G.surface_kit(mars) == "rock")
	failed += _check("icy_moon_gets_ice", G.surface_kit(europa) == "ice")
	failed += _check("gas_giant_gets_no_kit", G.surface_kit(jup) == "none")

	# An invented world has to land somewhere too — never "none" if it has a surface.
	var made := G.invent({"name": "Kepler-22b", "radius": 2.0, "color": Color(0.6, 0.5, 0.4)})
	failed += _check("invented_rocky_world_gets_a_kit",
		not G.has_surface(made) or G.surface_kit(made) != "none")

	print("surface_band: kit  Earth=%s  Moon=%s  Mars=%s  Europa=%s  invented=%s"
		% [G.surface_kit(earth), G.surface_kit(moon), G.surface_kit(mars),
		G.surface_kit(europa), G.surface_kit(made)])
	return failed


# --- The tile paints the world it is standing on -----------------------------
func _sources() -> int:
	var failed := 0
	var patch := SP.new()
	# _ready() builds the child nodes; SceneTree scripts have no tree to add to, so
	# drive it directly. bind_recipe() is what a real arrival calls.
	patch._ready()

	patch.bind_recipe(G.recipe_for({"name": "Earth"}))
	var e: Dictionary = patch.report()
	failed += _check("earth_uses_its_height_map", str(e.height_source) == "map")
	failed += _check("earth_uses_its_water_mask", str(e.water_source) == "mask")

	patch.bind_recipe(G.recipe_for({"name": "Moon"}))
	var m: Dictionary = patch.report()
	# THE bug this slice had to avoid: earth_height.jpg bound on lunar regolith.
	failed += _check("moon_does_not_borrow_earths_height", str(m.height_source) == "noise")
	failed += _check("moon_has_no_water_mask", str(m.water_source) != "mask")
	failed += _check("moon_still_paints_its_own_albedo", str(m.albedo_source) == "map")
	failed += _check("moon_swapped_to_the_rock_kit", str(m.kit) == "rock")

	# A world with no map at all still cooks a tile — colours from the recipe.
	patch.bind_recipe(G.invent({"name": "Kepler-22b", "radius": 2.0, "color": Color(0.6, 0.5, 0.4)}))
	var k: Dictionary = patch.report()
	failed += _check("invented_world_paints_from_recipe_colors",
		str(k.albedo_source) == "recipe-colors")
	failed += _check("invented_world_heights_from_noise", str(k.height_source) == "noise")

	# Binding is idempotent and does not leak the previous world's images.
	patch.bind_recipe(G.recipe_for({"name": "Earth"}))
	failed += _check("rebinding_earth_restores_its_maps",
		str(patch.report().height_source) == "map")

	patch.free()
	print("surface_band: sources  Earth h=%s w=%s | Moon h=%s w=%s a=%s | invented a=%s"
		% [e.height_source, e.water_source, m.height_source, m.water_source,
		m.albedo_source, k.albedo_source])
	return failed


# --- The tile's hills must agree with the globe's crust ----------------------
func _crust() -> int:
	var failed := 0
	# crust_height mirrors planet_cook.gdshader sample_height()'s fallback,
	# fbm(n * 6.0 + seed). If these drift apart the tile's hills stop lining up
	# with the crust painted on the globe overhead.
	var n := Vector3(0.3, 0.5, 0.81).normalized()
	var h0 := G.crust_height(n, 0.0)
	var h1 := G.crust_height(n, 3.7)
	failed += _check("crust_is_in_range", h0 >= 0.0 and h0 <= 1.0)
	failed += _check("crust_is_deterministic", is_equal_approx(h0, G.crust_height(n, 0.0)))
	failed += _check("crust_follows_the_seed", not is_equal_approx(h0, h1))

	# fbm with 5 octaves at a=0.5 halving: the sum of amplitudes is 0.96875, and
	# noise is 0..1, so the result can never leave 0..0.97. A value pinned at 0 or
	# 1 everywhere would mean the noise collapsed and every world came out flat.
	var lo := 1.0
	var hi := 0.0
	var acc := 0.0
	for i in 400:
		var a := float(i) * 0.0157
		var p := Vector3(cos(a), sin(a * 1.7), sin(a)).normalized()
		var v := G.crust_height(p, 1.3)
		lo = minf(lo, v)
		hi = maxf(hi, v)
		acc += v
	failed += _check("crust_actually_varies", hi - lo > 0.15)
	failed += _check("crust_stays_in_fbm_range", lo >= 0.0 and hi <= 0.97)
	var mean := acc / 400.0
	failed += _check("crust_is_not_stuck_at_an_extreme", mean > 0.2 and mean < 0.8)

	print("surface_band: crust  %.3f..%.3f  mean %.3f  (seeded 0 -> %.3f, 3.7 -> %.3f)"
		% [lo, hi, mean, h0, h1])
	return failed


# --- Build a real tile ---------------------------------------------------------
# The rest of this file is arithmetic about a window. This section puts a hull
# 1 km over the Moon and makes the plate commit geometry, because "the band is
# non-empty" and "a tile exists" are different claims and only the second one
# had never been true.
const MOON_R := 1737.4      # km, Ephemeris.PLANETS


# Ring geometry, prop coverage and the mesh/height agreement moved to
# tools/test_earth_terrain.gd _rings() when the single plate became four nested
# rings — keeping duplicate geometry assertions in two files would let them drift.
# What stays here is what this file uniquely covers: that the tile appears and
# disappears at the right ALTITUDES, on the right BODIES, and never at Earth's EZ.
func _tile() -> int:
	var failed := 0
	var moon := G.recipe_for({"name": "Moon"})
	var patch := SP.new()
	patch._ready()

	var dir := Vector3(0.42, 0.31, 0.85).normalized()
	var pos: Vector3 = dir * (MOON_R + 1.0)      # 1 km over the surface
	var sampler: TerrainSampler = G.terrain_sampler(moon)
	patch.bind_body(moon, sampler)
	var m_ceiling := _ceiling_of(moon)
	# ONE ring builds per update, so a cold tile needs RING_COUNT updates. Four
	# rings landing in a single frame was the 1.2 s freeze on arrival.
	for _i in SP.RING_COUNT:
		patch.update_for(pos, "Moon", true, MOON_R, 1.0, AIRLESS_KILL, m_ceiling, moon, sampler)
	var r: Dictionary = patch.report()

	failed += _check("tile_is_visible_1km_over_the_moon", bool(r.visible))
	failed += _check("tile_committed_geometry", int(r.tris) > 0)
	failed += _check("tile_bound_to_the_right_body", str(r.body) == "Moon")
	failed += _check("tile_planted_its_kit_props", int(r.props) > 0)
	failed += _check("tile_offered_more_props_than_it_shows",
		int(r.prop_pool) >= int(r.props))

	# Standing still must not throw the rings away and rebuild them.
	var tris0 := int(r.tris)
	patch.update_for(pos, "Moon", true, MOON_R, 1.0, AIRLESS_KILL, m_ceiling, moon, sampler)
	failed += _check("standing_still_keeps_the_same_rings",
		int(patch.report().tris) == tris0)

	# Climbing out of the band puts it away again.
	patch.update_for(dir * (MOON_R + 40.0), "Moon", true, MOON_R, 40.0, AIRLESS_KILL, m_ceiling, moon, sampler)
	failed += _check("tile_hides_above_the_band", not bool(patch.report().visible))

	# Earth at EZ: the regression commit 8933730 fixed, checked on the live object
	# and not only on the arithmetic.
	var earth_recipe := G.recipe_for({"name": "Earth"})
	patch.update_for(Vector3(0.0, 6471.0, 0.0), "Earth", true, 6371.0, 100.0,
		EARTH_KILL, _ceiling_of(earth_recipe), earth_recipe,
		G.terrain_sampler(earth_recipe))
	failed += _check("no_ground_tile_at_earth_ez", not bool(patch.report().visible))

	print("surface_band: tile  %d tris across %d rings, %d/%d props, body %s"
		% [tris0, int(r.rings), int(r.props), int(r.prop_pool), str(r.body)])
	patch.free()
	return failed


func _check(name: String, ok: bool) -> int:
	if not ok:
		print("surface_band: FAIL %s" % name)
		return 1
	return 0
