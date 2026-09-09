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
	failed += _quantisation_hysteresis()
	failed += _band_edge_hysteresis()
	failed += _ring_boundary_normal_agreement()
	failed += _ring_boundary_height_agreement()
	failed += _ring_rim_color_agreement()
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
	# Moon carries its own real DEM as of 2026-09-09 (moon_height_2k.png,
	# docs/research/2026-09-09-dem-ingest.md) - height_source is legitimately
	# "map" now, no longer "noise". THE bug this slice had to avoid is still
	# live, just phrased differently: the map bound must be the Moon's OWN
	# file, never earth_height.jpg.
	failed += _check("moon_uses_its_own_height_map", str(m.height_source) == "map")
	failed += _check("moon_does_not_borrow_earths_height",
		str(G.recipe_for({"name": "Moon"}).get("height", "")) \
		!= str(G.recipe_for({"name": "Earth"}).get("height", "")))
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
	# update_for only DISPATCHES a rebuild (WorkerThreadPool, off the main
	# thread); force_ready() is the test-only hook that blocks until it lands
	# and commits, so a deterministic test does not have to guess how many
	# frames a real background job needs.
	patch.update_for(pos, "Moon", true, MOON_R, 1.0, AIRLESS_KILL, m_ceiling, moon, sampler)
	patch.force_ready()
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


# base_quad_km() quantises to a power of two so a rescale is rare and always
# exactly 2x (surface_patch.gd:156). Without hysteresis, an altitude sitting a
# float epsilon either side of the boundary flips the bucket every call - a
# ~600 ms four-ring rebuild (tools/_probe_timing.gd, unmeasured before this
# slice) every single frame the ship holds that altitude. This finds the real
# crossing altitude by bisection and checks the band around it.
func _quantisation_hysteresis() -> int:
	var failed := 0
	var radius := 6371.0
	var lo := 0.01
	var hi := 2000.0
	# base_quad_km is monotonic in altitude, so bisection finds the one
	# crossing from 0.16 to 0.32 km without hard-coding the horizon formula.
	for _i in 60:
		var mid := (lo + hi) * 0.5
		if SP.base_quad_km(mid, radius) <= 0.16:
			lo = mid
		else:
			hi = mid
	var crossing := (lo + hi) * 0.5
	failed += _check("quantisation_crossing_found",
		is_equal_approx(SP.base_quad_km(lo, radius), 0.16)
		and is_equal_approx(SP.base_quad_km(hi, radius), 0.32))
	# A hair past the crossing, ALREADY at 0.16: must hold, not flip.
	failed += _check("quantisation_holds_just_past_the_boundary",
		is_equal_approx(SP.base_quad_km(crossing * 1.001, radius, 0.16), 0.16))
	# Comfortably past it: must actually grow, or a real rescale would never happen.
	failed += _check("quantisation_still_grows_once_clearly_past",
		is_equal_approx(SP.base_quad_km(crossing * 1.5, radius, 0.16), 0.32))
	# Comfortably below it: must actually shrink back.
	failed += _check("quantisation_still_shrinks_once_clearly_below",
		is_equal_approx(SP.base_quad_km(crossing * 0.5, radius, 0.32), 0.16))
	return failed


# The ring (and, in planet_system.gd, the body's own globe it hides) used to
# flip on `alt` crossing a single line with no margin - a ship holding level
# flight exactly at the ceiling strobes both every frame. should_show() itself
# must stay a pure boundary test (CloudLayer.should_show and
# tools/test_cloud_layer.gd assert it at exact edge values), so the hysteresis
# lives in the instance-side wrapper instead.
func _band_edge_hysteresis() -> int:
	var failed := 0
	var moon := G.recipe_for({"name": "Moon"})
	var ceiling := _ceiling_of(moon)
	var patch := SP.new()
	patch._ready()
	failed += _check("hyst_enters_band_on_first_nominal_pass",
		patch._in_band_hyst("Moon", true, ceiling - 0.01, AIRLESS_KILL, ceiling, moon))
	failed += _check("hyst_holds_a_hair_past_the_ceiling",
		patch._in_band_hyst("Moon", true, ceiling + 0.01, AIRLESS_KILL, ceiling, moon))
	failed += _check("hyst_releases_once_clearly_past_the_ceiling",
		not patch._in_band_hyst("Moon", true, ceiling * 1.1, AIRLESS_KILL, ceiling, moon))
	# Once released, it must not simply always say yes - re-entering from
	# clearly outside still needs a nominal pass.
	failed += _check("hyst_stays_out_far_above_the_ceiling",
		not patch._in_band_hyst("Moon", true, ceiling * 2.0, AIRLESS_KILL, ceiling, moon))
	failed += _check("hyst_re_enters_on_a_real_nominal_pass",
		patch._in_band_hyst("Moon", true, ceiling - 0.01, AIRLESS_KILL, ceiling, moon))
	patch.free()
	return failed


# The category fix for the reported shading crease at ring boundaries
# (himalaya_9km, moon_7km's rectangular step): normals are now derived
# analytically from the height function at a fixed world step, the same for
# every ring, instead of from each mesh's own local (ring-scale-dependent)
# neighbours. This checks the COMMITTED meshes, not just the helper function
# in isolation: ring 0's outer rim corner and ring 1's corresponding
# inner-hole-boundary vertex are the same world point (already guaranteed by
# vertex_error_km()/rings_seal() elsewhere) - their stored normals must now
# also agree, where before they were computed from grids of different scale
# and generally did not.
func _ring_boundary_normal_agreement() -> int:
	var failed := 0
	var moon := G.recipe_for({"name": "Moon"})
	var patch := SP.new()
	patch._ready()
	var dir := Vector3(0.42, 0.31, 0.85).normalized()
	var pos: Vector3 = dir * (MOON_R + 1.0)
	var sampler: TerrainSampler = G.terrain_sampler(moon)
	patch.bind_body(moon, sampler)
	var m_ceiling := _ceiling_of(moon)
	patch.update_for(pos, "Moon", true, MOON_R, 1.0, AIRLESS_KILL, m_ceiling, moon, sampler)
	patch.force_ready()

	var base: float = float(patch.report().base_quad_km)
	var hit: Vector3 = pos.normalized() * MOON_R
	var up := hit.normalized()
	var east := up.cross(Vector3.UP)
	if east.length_squared() < 0.0001:
		east = up.cross(Vector3.RIGHT)
	east = east.normalized()
	var north := east.cross(up).normalized()
	# The corner of ring 0's reach - coarse-aligned on BOTH axes, so ring 1's
	# grid (hole = ring 0's full reach) has an actual vertex at this exact
	# world position too.
	var half0: float = SP.ring_reach_km(0, base) * 0.5
	var step: float = SP.ring_quad_km(0, base) * SP.NORMAL_STEP_FRAC
	var expect_n: Vector3 = patch._analytic_normal(hit, east, north, MOON_R, half0, half0, step)
	var expect_dir: Vector3 = (hit + east * half0 + north * half0).normalized()
	var expect_p: Vector3 = expect_dir * sampler.ground_radius_km(expect_dir, MOON_R)

	var n0 := _closest_normal(patch, 0, expect_p)
	var n1 := _closest_normal(patch, 1, expect_p)
	failed += _check("ring0_boundary_vertex_found", n0.d < 0.01)
	failed += _check("ring1_boundary_vertex_found", n1.d < 0.01)
	failed += _check("ring0_normal_matches_the_height_function",
		n0.n.distance_to(expect_n) < 1e-3)
	failed += _check("ring1_normal_matches_the_height_function",
		n1.n.distance_to(expect_n) < 1e-3)
	failed += _check("ring0_ring1_boundary_normals_agree",
		n0.n.distance_to(n1.n) < 1e-3)
	patch.free()
	return failed


# Sibling to _ring_boundary_normal_agreement: proves the `detail_km` band-limit
# (SurfacePatch._detail_km_at, TerrainSampler/SurfaceRecipe's band-weighted
# octaves) did not reopen a height seam at the same shared corners the normal
# check uses. `detail_km` is a function of distance from the hull ONLY, not of
# which ring is asking, so ring i and ring i+1 must land on the identical
# height at every point they actually share - 20+ of them, spread across all
# three ring boundaries, not just the one corner the normal check samples.
func _ring_boundary_height_agreement() -> int:
	var failed := 0
	var moon := G.recipe_for({"name": "Moon"})
	var patch := SP.new()
	patch._ready()
	var dir := Vector3(0.42, 0.31, 0.85).normalized()
	var pos: Vector3 = dir * (MOON_R + 1.0)
	var sampler: TerrainSampler = G.terrain_sampler(moon)
	patch.bind_body(moon, sampler)
	var m_ceiling := _ceiling_of(moon)
	patch.update_for(pos, "Moon", true, MOON_R, 1.0, AIRLESS_KILL, m_ceiling, moon, sampler)
	patch.force_ready()

	var base: float = float(patch.report().base_quad_km)
	var hit: Vector3 = pos.normalized() * MOON_R
	var up := hit.normalized()
	var east := up.cross(Vector3.UP)
	if east.length_squared() < 0.0001:
		east = up.cross(Vector3.RIGHT)
	east = east.normalized()
	var north := east.cross(up).normalized()

	var tol_km: float = MOON_R * pow(2.0, -23.0) * 8.0   # same 8-ULP budget as test_earth_terrain
	var checked := 0
	for ring in [0, 1, 2]:
		var half_i: float = SP.ring_reach_km(ring, base) * 0.5
		var quad_next: float = SP.ring_quad_km(ring + 1, base)
		var steps: int = SP.RING_SEGS / int(SP.RING_STEP)   # coarse-aligned points along one edge
		for k in [0, 2, 4, 6, 8, 10, steps]:
			var off_e: float = -half_i + quad_next * float(k)
			var off_n: float = half_i
			var d: Vector3 = (hit + east * off_e + north * off_n).normalized()
			var detail_km: float = SP._detail_km_at(off_e, off_n)
			var want: float = sampler.ground_radius_km(d, MOON_R, detail_km)
			var expect_p: Vector3 = d * want
			var a := _closest_normal(patch, ring, expect_p)
			var b := _closest_normal(patch, ring + 1, expect_p)
			checked += 1
			failed += _check("boundary_%d_%d_k%d_ring%d_vertex_found" % [ring, ring + 1, k, ring],
				a.d < 0.01)
			failed += _check("boundary_%d_%d_k%d_ring%d_vertex_found" % [ring, ring + 1, k, ring + 1],
				b.d < 0.01)
			failed += _check("boundary_%d_%d_k%d_heights_agree" % [ring, ring + 1, k],
				a.p.length() - b.p.length() < tol_km and b.p.length() - a.p.length() < tol_km)
	failed += _check("checked_at_least_20_shared_rim_points", checked >= 20)
	patch.free()
	return failed


# Straight-line-nadir review (2026-09-09): a horizontal shading discontinuity
# reported at moon_1km_nadir_lowsun, in-frame well inside ring 0's OWN outer
# rim (not any ring's actual boundary circle - probed with
# tools/_probe_ring_screen.gd). `_snap()` moves the 3 of every 4 rim vertices
# that are not on the coarser neighbour's own grid onto the straight line
# between the two that are - needed so the two rings' edges coincide with no
# gap. But it ALSO overwrites those vertices' COLOUR with a straight lerp
# between the same two bracket vertices, discarding the TRUE per-vertex
# procedural colour _vert() already computed there. The rasterizer already
# blends a triangle's corner colours continuously; layering a second, coarser
# lerp on top of that flattens out the terrain's natural short-wavelength
# albedo variation in a one-quad-wide band running along every ring boundary,
# on every body, at every altitude - which is exactly a visible band where the
# terrain "grain" stops while its neighbours keep it. This proves the category:
# a snapped, non-shared rim vertex's stored colour disagrees with its own true
# procedural colour (computed at its true, pre-snap direction) by more than
# ordinary neighbour-to-neighbour variance would explain.
func _ring_rim_color_agreement() -> int:
	var failed := 0
	var moon := G.recipe_for({"name": "Moon"})
	var patch := SP.new()
	patch._ready()
	var dir := Vector3(0.42, 0.31, 0.85).normalized()
	var pos: Vector3 = dir * (MOON_R + 1.0)
	var sampler: TerrainSampler = G.terrain_sampler(moon)
	patch.bind_body(moon, sampler)
	var m_ceiling := _ceiling_of(moon)
	patch.update_for(pos, "Moon", true, MOON_R, 1.0, AIRLESS_KILL, m_ceiling, moon, sampler)
	patch.force_ready()

	var base: float = float(patch.report().base_quad_km)
	var hit: Vector3 = pos.normalized() * MOON_R
	var up := hit.normalized()
	var east := up.cross(Vector3.UP)
	if east.length_squared() < 0.0001:
		east = up.cross(Vector3.RIGHT)
	east = east.normalized()
	var north := east.cross(up).normalized()

	var quad0: float = SP.ring_quad_km(0, base)
	var half0: float = SP.ring_reach_km(0, base) * 0.5
	var step := int(SP.RING_STEP)
	var checked := 0
	var worst := 0.0
	# The south rim (j=0, off_n=-half0): every non-coarse-aligned i (kk = k+t,
	# t in 1..step-1) is a vertex _snap() moved and recoloured.
	for k in range(0, SP.RING_SEGS + 1, step):
		for t in range(1, step):
			var kk: int = k + t
			if kk >= SP.RING_SEGS:
				break
			var off_e: float = -half0 + quad0 * float(kk)
			var off_n: float = -half0
			var detail_km: float = SP._detail_km_at(off_e, off_n)
			var d: Vector3 = (hit + east * off_e + north * off_n).normalized()
			var uv := patch._dir_uv(d)
			var gr: float = sampler.ground_radius_km(d, MOON_R, detail_km)
			var h: float = clampf((gr - MOON_R) / maxf(sampler.max_height_km(), 0.001), 0.0, 1.0)
			var true_col: Color = patch._color_at(d, uv, h).srgb_to_linear()
			var expect_p: Vector3 = d * gr
			var got := _closest_color(patch, 0, expect_p)
			checked += 1
			failed += _check("rim_k%d_vertex_found" % kk, got.d < INF)
			if got.d < INF:
				var dc: Color = got.c
				var delta: float = sqrt(pow(dc.r - true_col.r, 2) + pow(dc.g - true_col.g, 2)
					+ pow(dc.b - true_col.b, 2))
				worst = maxf(worst, delta)
				failed += _check("rim_k%d_color_matches_true_procedural_color" % kk, delta < 0.02)
	failed += _check("checked_at_least_9_rim_points", checked >= 9)
	print("surface_band: rim color worst true-vs-committed delta %.4f over %d points" % [worst, checked])
	patch.free()
	return failed


func _closest_color(patch: SP, ring: int, target: Vector3) -> Dictionary:
	var best_d := INF
	var best_c := Color.BLACK
	for kind in ["land", "skirt"]:
		var mi: MeshInstance3D = patch.mesh_for(kind, ring)
		if mi == null or mi.mesh == null or mi.mesh.get_surface_count() == 0:
			continue
		var arrays: Array = mi.mesh.surface_get_arrays(0)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var cols: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
		for i in verts.size():
			var d := verts[i].distance_to(target)
			if d < best_d:
				best_d = d
				best_c = cols[i]
	return {"d": best_d, "c": best_c}


func _closest_normal(patch: SP, ring: int, target: Vector3) -> Dictionary:
	var best_d := INF
	var best_n := Vector3.ZERO
	var best_p := Vector3.ZERO
	for kind in ["land", "skirt"]:
		var mi: MeshInstance3D = patch.mesh_for(kind, ring)
		if mi == null or mi.mesh == null or mi.mesh.get_surface_count() == 0:
			continue
		var arrays: Array = mi.mesh.surface_get_arrays(0)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var norms: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		for i in verts.size():
			var d := verts[i].distance_to(target)
			if d < best_d:
				best_d = d
				best_n = norms[i]
				best_p = verts[i]
	return {"d": best_d, "n": best_n, "p": best_p}


func _check(name: String, ok: bool) -> int:
	if not ok:
		print("surface_band: FAIL %s" % name)
		return 1
	return 0
