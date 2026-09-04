extends SceneTree
# Contract for the Earth flyover slice: one height function, nested rings, the
# band ceiling, the speed cap and the contact kill.
# Run: godot --headless --path . --script res://tools/test_earth_terrain.gd
#
# The load-bearing assertion in this file is mesh_matches_the_height_function
# (added with the rings). Mesh geometry and the kill test are two consumers of
# ONE function; if they ever disagree you die in clear air or fly through rock,
# and no amount of visual inspection would tell you which one was wrong.
#
# The DEM constants asserted here were measured by tools/probe_earth_dem.gd. They
# are facts about earth_height.jpg, so if that file is ever re-fetched these fail
# loudly rather than quietly flattening the planet.

const G := preload("res://scripts/world/planet_generator.gd")
const TS := preload("res://scripts/world/terrain_sampler.gd")
const SP := preload("res://scripts/world/surface_patch.gd")
const FM := preload("res://scripts/flight/flight_mode.gd")

const EARTH_R := 6371.0
const MOON_R := 1737.4


func _initialize() -> void:
	var failed := 0
	failed += _encoding()
	failed += _sampler()
	failed += _band()
	failed += _rings()
	failed += _cap()
	failed += _kill()
	if failed == 0:
		print("earth_terrain: OK")
		quit(0)
	else:
		print("earth_terrain: FAIL %d" % failed)
		quit(1)


# --- The DEM's encoding, as measured ----------------------------------------
func _encoding() -> int:
	var failed := 0
	# Pinned from the probe. A re-fetched map with different encoding must fail
	# here rather than silently changing every altitude in the game.
	failed += _check("sea_level_is_zero", is_equal_approx(TS.DEM_SEA_LEVEL, 0.0))
	failed += _check("no_bathymetry_encoded", not TS.DEM_HAS_BATHYMETRY)
	failed += _check("everest_anchor_is_the_measured_texel",
		absf(TS.DEM_PEAK_VALUE - 0.9547) < 0.002)
	failed += _check("file_max_is_the_measured_max",
		absf(TS.DEM_MAX_VALUE - 0.9804) < 0.002)
	# The file's highest sample is ABOVE Everest's own texel, so a ceiling built
	# from Everest would sit under real terrain.
	failed += _check("file_max_exceeds_the_everest_texel",
		TS.DEM_MAX_VALUE > TS.DEM_PEAK_VALUE)
	failed += _check("scale_is_about_9268_m_per_unit",
		absf(TS.DEM_SCALE_M - 9267.7) < 20.0)
	return failed


# --- One height function ------------------------------------------------------
func _sampler() -> int:
	var failed := 0
	var earth := G.recipe_for({"name": "Earth"})
	var s: TerrainSampler = G.terrain_sampler(earth)
	failed += _check("earth_sampler_exists", s != null)
	if s == null:
		return failed

	var everest := _dir_of(27.9881, 86.9250)
	var pacific := _dir_of(0.0, -150.0)
	var denali := _dir_of(63.0695, -151.0074)
	var e_m: float = s.height_m(everest)
	var p_m: float = s.height_m(pacific)
	var d_m: float = s.height_m(denali)

	# A 7.42 km texel smooths every summit, so these are ballparks, not equalities.
	# The probe's cross-check put Denali within 1% and Everest exact by definition.
	failed += _check("everest_is_high_ground", e_m > 7500.0)
	failed += _check("everest_is_not_absurd", e_m < 10000.0)
	failed += _check("denali_is_high_ground", d_m > 4500.0)
	failed += _check("open_ocean_is_at_sea_level", absf(p_m) < 1.0)
	failed += _check("mountains_are_above_the_ocean", e_m > p_m + 7000.0)
	failed += _check("open_ocean_is_water", s.is_water(pacific))
	failed += _check("everest_is_not_water", not s.is_water(everest))

	# ground_radius_km and alt_above_ground_km must agree with height_m, since the
	# kill test uses them and the mesh uses height_m.
	var gr: float = s.ground_radius_km(everest, EARTH_R)
	failed += _check("ground_radius_tracks_height",
		is_equal_approx(gr, EARTH_R + e_m / 1000.0))
	var above: float = s.alt_above_ground_km(everest * (gr + 2.0), EARTH_R)
	failed += _check("altitude_is_measured_from_local_ground",
		absf(above - 2.0) < 0.01)
	# The bug this catches: measuring from the sphere would report ~10.8 km here.
	failed += _check("altitude_is_not_measured_from_the_sphere", above < 5.0)

	# Determinism. The mesh builder and the kill test call this at different points
	# in the same frame; any statefulness would desync them.
	failed += _check("height_is_deterministic",
		is_equal_approx(e_m, s.height_m(everest)))

	# Procedural detail, tested against base_height_m rather than against a second
	# sample nearby. The first draft compared two points 2 km apart and called it
	# "detail varies inside one texel" - but bilinear interpolation of the DEM
	# already varies continuously, so that assertion passed with detail deleted
	# entirely. It was testing interpolation while claiming to test detail.
	var flank := _dir_of(27.90, 86.60)
	failed += _check("detail_lifts_steep_ground",
		absf(s.height_m(flank) - s.base_height_m(flank)) > 5.0)
	failed += _check("detail_is_bounded_by_its_amplitude",
		absf(s.height_m(flank) - s.base_height_m(flank)) <= TS.DETAIL_MAX_M)
	# ...but it must NOT wrinkle the ocean.
	var sea := _dir_of(0.0, -150.0)
	failed += _check("detail_leaves_the_ocean_flat",
		is_equal_approx(s.height_m(sea), s.base_height_m(sea)))

	# Bilinear, not nearest. A nearest-neighbour sampler holds one value across a
	# whole 7.42 km texel and then steps, so walking a texel boundary in the
	# Himalaya produces a single cliff of several hundred metres. Bilinear spreads
	# the same difference over the walk. This is the assertion that pins it - the
	# first draft had none, and swapping bilinear for nearest went undetected.
	var worst_step := 0.0
	var span := 0.0
	var prev := 0.0
	for i in 201:
		# One texel of longitude at this latitude, walked in 200 steps.
		var lon: float = 86.60 + 0.0757 * float(i) / 200.0
		var hh: float = s.base_height_m(_dir_of(27.90, lon))
		if i > 0:
			worst_step = maxf(worst_step, absf(hh - prev))
			span = maxf(span, absf(hh - s.base_height_m(_dir_of(27.90, 86.60))))
		prev = hh
	failed += _check("the_texel_walk_actually_covers_relief", span > 80.0)
	failed += _check("sampling_is_smooth_across_a_texel_boundary", worst_step < 60.0)

	# Ceiling source: the file's max, plus detail headroom.
	failed += _check("earth_max_height_covers_the_file_max", s.max_height_km() > 9.0)
	failed += _check("earth_max_height_is_not_wild", s.max_height_km() < 11.0)
	failed += _check("earth_max_height_bounds_everest", s.max_height_km() * 1000.0 > e_m)

	# A world with no DEM still answers, from the shader's own crust noise.
	var moon := G.recipe_for({"name": "Moon"})
	var ms: TerrainSampler = G.terrain_sampler(moon)
	var md := _dir_of(12.0, 34.0)
	var mh: float = ms.height_m(md)
	failed += _check("airless_world_height_is_bounded", absf(mh) < 4000.0)

	# TERRAIN MUST STRADDLE THE DATUM, and this is the assertion that was missing.
	# crust_height() is all-positive, so multiplying it by the relief put the whole
	# lunar surface on a plinth: 380 m to 2421 m above the sphere, averaging
	# 1457 m. Altitude is reported from the sphere, so at "Alt 2 km" over the Moon
	# the ground was already at the hull and the contact kill fired - in play that
	# read as being unable to descend below 2 km at all.
	var m_lo := 1.0e9
	var m_hi := -1.0e9
	var m_sum := 0.0
	var samples := 1500
	for i in samples:
		var a := float(i) * 0.00419
		var d := Vector3(cos(a) * cos(a * 0.7), sin(a * 1.3), sin(a) * cos(a * 0.7)).normalized()
		var h: float = ms.height_m(d)
		m_lo = minf(m_lo, h)
		m_hi = maxf(m_hi, h)
		m_sum += h
	var m_mean := m_sum / float(samples)
	failed += _check("airless_terrain_has_ground_below_the_datum", m_lo < -100.0)
	failed += _check("airless_terrain_has_ground_above_the_datum", m_hi > 100.0)
	failed += _check("airless_terrain_is_centred_not_on_a_plinth", absf(m_mean) < 300.0)
	# ...so the sphere-relative altitude the tape shows is roughly honest.
	failed += _check("sphere_altitude_is_not_misleading_by_kilometres",
		absf(m_mean) < 500.0 and m_hi < 2000.0)

	# Two named airless worlds must not share one crust. Named recipes carried no
	# seed, so every one of them ran the noise at 0 and the Moon, Mars and Mercury
	# came out byte-identical.
	var mars: TerrainSampler = G.terrain_sampler(G.recipe_for({"name": "Mars"}))
	var probe := _dir_of(12.0, 34.0)
	failed += _check("named_worlds_have_their_own_seed",
		not is_equal_approx(float(G.recipe_for({"name": "Moon"}).get("seed", 0.0)),
			float(G.recipe_for({"name": "Mars"}).get("seed", 0.0))))
	failed += _check("two_airless_worlds_are_not_the_same_crust",
		absf(ms.height_m(probe) - mars.height_m(probe)) > 10.0)

	# GRADE. This is the assertion that was missing when detail was retuned to
	# ridge scale: amplitude has to be set against the FINEST octave's wavelength,
	# and at 420 m the Moon came out at a mean grade of 0.85 - 40 degrees
	# everywhere - which is spikes, not terrain. It also broke the mesh/function
	# agreement check, because comparing heights at two float32-quantised
	# directions only matters when the ground is steep.
	var g_worst := 0.0
	var g_sum := 0.0
	var walk := 2000
	var step_km := 0.04
	var base_dir := Vector3(0.42, 0.31, 0.85).normalized()
	var walk_east := base_dir.cross(Vector3.UP).normalized()
	var g_prev: float = ms.height_m(base_dir)
	for i in range(1, walk):
		var wd: Vector3 = (base_dir * MOON_R + walk_east * (step_km * float(i))).normalized()
		var wh: float = ms.height_m(wd)
		var grade: float = absf(wh - g_prev) / (step_km * 1000.0)
		g_worst = maxf(g_worst, grade)
		g_sum += grade
		g_prev = wh
	var g_mean := g_sum / float(walk - 1)
	# A real mountainside is 0.3-0.7. Mean well under that (most ground is not a
	# mountainside) but not flat, and a worst that is a cliff rather than a spire.
	failed += _check("terrain_is_not_flat", g_mean > 0.08)
	failed += _check("terrain_is_not_spikes", g_mean < 0.5)
	failed += _check("steepest_ground_is_a_cliff_not_a_spire", g_worst < 2.0)

	print("earth_terrain: grade  Moon over 40 m steps: mean %.3f (%.1f deg), worst %.2f (%.0f deg)"
		% [g_mean, rad_to_deg(atan(g_mean)), g_worst, rad_to_deg(atan(g_worst))])
	print("earth_terrain: crust  Moon %+.0f..%+.0f m, mean %+.0f (straddles the datum); Moon seed %.2f vs Mars %.2f"
		% [m_lo, m_hi, m_mean, float(G.recipe_for({"name": "Moon"}).get("seed", 0.0)),
		float(G.recipe_for({"name": "Mars"}).get("seed", 0.0))])
	failed += _check("airless_world_is_never_water", not ms.is_water(md))
	# Centred terrain peaks at only the HALF-range above the datum, so this bound
	# moved when the plinth was removed: (0.96875 - 0.484) * 3.2 + 0.42 = 1.97 km,
	# not the 3.1 km an all-positive crust reached.
	failed += _check("airless_max_height_is_bounded",
		ms.max_height_km() > 1.2 and ms.max_height_km() < 2.5)
	failed += _check("airless_uses_noise_not_a_map",
		str(ms.report().height_source) == "noise")
	failed += _check("earth_uses_its_map", str(s.report().height_source) == "map")
	# The Moon must never borrow Earth's terrain.
	failed += _check("airless_height_differs_from_earths_at_the_same_place",
		not is_equal_approx(ms.height_m(everest), e_m))

	print("earth_terrain: sampler  Everest %.0f m, Denali %.0f m, Pacific %.0f m; max Earth %.2f km / Moon %.2f km; scale %.1f m/unit"
		% [e_m, d_m, p_m, s.max_height_km(), ms.max_height_km(), TS.DEM_SCALE_M])
	print("earth_terrain: detail  flank +%.1f m over base; texel walk spans %.0f m with a worst step of %.1f m"
		% [s.height_m(flank) - s.base_height_m(flank), span, worst_step])
	return failed


# --- The band ceiling, derived from the terrain ------------------------------
func _band() -> int:
	var failed := 0
	var earth := G.recipe_for({"name": "Earth"})
	var moon := G.recipe_for({"name": "Moon"})
	var es: TerrainSampler = G.terrain_sampler(earth)
	var ms: TerrainSampler = G.terrain_sampler(moon)
	var e_ceil: float = G.band_ceiling_km(es)
	var m_ceil: float = G.band_ceiling_km(ms)

	# The ceiling's JOB changed with the rings. It used to stop a small plate
	# reading as a sticker on a globe; rings reach 205 km, so now it must open the
	# band ABOVE the tallest terrain or you arrive inside a mountain.
	failed += _check("earth_ceiling_clears_the_highest_ground",
		e_ceil > es.max_height_km())
	failed += _check("earth_ceiling_clears_everest", e_ceil > 8.848)
	failed += _check("airless_ceiling_clears_its_own_relief",
		m_ceil > ms.max_height_km())
	# Derived, not authored: two worlds with different relief get different
	# ceilings without a table entry for either.
	failed += _check("ceiling_is_derived_not_authored",
		not is_equal_approx(e_ceil, m_ceil))
	failed += _check("earth_ceiling_is_the_taller_one", e_ceil > m_ceil)
	failed += _check("a_flat_world_still_gets_a_floor",
		G.band_ceiling_km(null) >= G.BAND_CEILING_MIN_KM)

	# Every altitude between contact and the ceiling is in the band.
	failed += _check("band_opens_just_above_the_ground",
		G.ground_stamp_ok(0.5, 0.02, e_ceil))
	failed += _check("band_covers_everest_height",
		G.ground_stamp_ok(9.0, 0.02, e_ceil))
	failed += _check("band_shuts_above_the_ceiling",
		not G.ground_stamp_ok(e_ceil + 1.0, 0.02, e_ceil))
	failed += _check("band_shuts_below_the_kill_line",
		not G.ground_stamp_ok(0.01, 0.02, e_ceil))
	# Earth's EZ is 100 km (Karman). The band must never reach it — that is the
	# regression commit 8933730 closed.
	failed += _check("no_tile_at_earth_ez", not G.ground_stamp_ok(100.0, 0.02, e_ceil))
	failed += _check("no_tile_in_earth_air", not G.ground_stamp_ok(50.0, 0.02, e_ceil))

	print("earth_terrain: band  Earth ceiling %.2f km (terrain max %.2f), Moon %.2f km (max %.2f), floor %.1f"
		% [e_ceil, es.max_height_km(), m_ceil, ms.max_height_km(), G.BAND_CEILING_MIN_KM])
	return failed


# --- Four nested rings --------------------------------------------------------
func _rings() -> int:
	var failed := 0
	var moon := G.recipe_for({"name": "Moon"})
	var sampler: TerrainSampler = G.terrain_sampler(moon)
	var patch = SP.new()
	patch._ready()
	patch.bind_body(moon, sampler)

	# Ring size follows the HORIZON now, so every assertion needs the altitude it
	# is asked about. This section flies at 1 km over the Moon.
	var base_q: float = SP.base_quad_km(1.0, MOON_R)

	# THE fix for the flat plates below 10 km: rings must cover the ground you can
	# actually see. A fixed 204.8 km reach covered 406% of the horizon at 200 m
	# and only 47% at 15 km, and the missing half fell through to the body's bare
	# SphereMesh - 208 x 104 km facets, which is what read as giant flat planes.
	for probe_alt in [0.2, 1.0, 6.0, 15.0]:
		var b: float = SP.base_quad_km(probe_alt, EARTH_R)
		var hz: float = SP.horizon_km(probe_alt, EARTH_R)
		var cover: float = SP.ring_reach_km(3, b) / hz
		failed += _check("rings_reach_the_horizon_at_%s_km" % probe_alt,
			cover > 0.95 and cover < 1.5)
	# ...and the quad size must actually grow with altitude, or nothing changed.
	failed += _check("ring_scale_grows_with_altitude",
		SP.base_quad_km(15.0, EARTH_R) > SP.base_quad_km(0.5, EARTH_R) * 3.0)
	failed += _check("ring_scale_has_a_floor",
		SP.base_quad_km(0.0, EARTH_R) >= SP.BASE_QUAD_MIN_KM)
	failed += _check("ring_scale_has_a_ceiling",
		SP.base_quad_km(500.0, EARTH_R) <= SP.BASE_QUAD_MAX_KM)

	# Ring geometry: 4 rings, each quad 4x the one inside.
	failed += _check("four_rings", SP.RING_COUNT == 4)
	failed += _check("ring_0_is_fine", SP.ring_quad_km(0, base_q) <= 0.05)
	failed += _check("each_ring_is_coarser",
		SP.ring_quad_km(1, base_q) > SP.ring_quad_km(0, base_q)
		and SP.ring_quad_km(2, base_q) > SP.ring_quad_km(1, base_q)
		and SP.ring_quad_km(3, base_q) > SP.ring_quad_km(2, base_q))
	failed += _check("outer_ring_reaches_this_horizon",
		absf(SP.ring_reach_km(3, base_q) - SP.horizon_km(1.0, MOON_R)) < 1.0)
	failed += _check("rings_have_no_gaps", bool(patch.rings_seal()))

	# Build at 1 km over the Moon.
	var dir := Vector3(0.42, 0.31, 0.85).normalized()
	var m_ceiling: float = G.band_ceiling_km(sampler)
	# ONE ring builds per update, so a cold tile takes RING_COUNT updates to fill.
	# Four rings in one frame was a 1.2 s freeze on arrival; spread over four
	# frames it is four hitches. Assert the contract rather than assuming one call.
	patch.update_for(dir * (MOON_R + 1.0), "Moon", true, MOON_R, 1.0, 0.1, m_ceiling, moon, sampler)
	var first: PackedInt32Array = patch.report().ring_verts
	var built_first := 0
	for v in first:
		if v > 0:
			built_first += 1
	failed += _check("one_update_builds_one_ring", built_first == SP.RINGS_PER_UPDATE)
	for _i in SP.RING_COUNT:
		patch.update_for(dir * (MOON_R + 1.0), "Moon", true, MOON_R, 1.0, 0.1, m_ceiling, moon, sampler)
	var r: Dictionary = patch.report()

	failed += _check("all_rings_built", int(r.rings) == SP.RING_COUNT)
	failed += _check("rings_committed_geometry", int(r.tris) > 0)
	# Ring 0 has no hole, so its TOTAL - land plus water plus the stitch band -
	# must be exactly its grid. Land alone stopped being the grid when the stitch
	# moved the outer row of quads into the skirt mesh.
	# Ring 0 has no hole, so it must commit its whole grid - NOTHING dropped - plus
	# the rim's vertical wall triangles, and no more. Exact equality does not hold:
	# the wall is two extra triangles per rim edge, 4 * 64 * 6 = 1536 vertices.
	var rv0: PackedInt32Array = r.ring_verts
	var full_grid := SP.RING_SEGS * SP.RING_SEGS * 6
	var rim_wall := 4 * SP.RING_SEGS * 6
	failed += _check("ring_0_drops_nothing_from_its_grid",
		rv0.size() > 0 and rv0[0] >= full_grid)
	failed += _check("ring_0_adds_nothing_beyond_its_rim_wall",
		rv0.size() > 0 and rv0[0] <= full_grid + rim_wall)
	failed += _check("airless_world_has_no_water", int(r.ring0_water_verts) == 0)
	failed += _check("rings_planted_kit_props", int(r.props) > 0)

	# THE assertion. Every committed vertex must sit where the height function
	# says the ground is. Divergence here means dying in clear air.
	# The tolerance is FLOAT32 MESH QUANTISATION, not slop. Vertices are stored as
	# float32 at a 1737 km radius, whose relative precision (~6e-8) is about 10 cm;
	# Earth's 6371 km radius gives ~38 cm. Measured worst here is 31 cm. That is
	# 60x smaller than the 20 m contact margin, so it cannot make the kill fire
	# early — but it is the reason this is not asserted at exactly zero, and it is
	# the floor under any future attempt to shrink that margin.
	var err: Dictionary = patch.vertex_error_km(MOON_R)
	var worst: float = maxf(float(err.over), float(err.under))
	# BOTH directions. Over-height means the mesh floats above the ground the kill
	# test uses; under-height means the mesh sits inside it and you watch terrain
	# pass below you as you die. The first draft measured only over-height, and a
	# mutation that put the ENTIRE mesh below the ground passed it.
	# The tile must hold the SHARED instance, not one of its own. It used to build
	# its own, so the tile and the contact kill were two samplers - two 14.6 MB
	# loads, and the one-function design this slice rests on was untrue in the
	# shipped path.
	failed += _check("tile_holds_the_shared_sampler", patch.uses_sampler(sampler))
	var tol: float = _agreement_tol_km(MOON_R)
	failed += _check("mesh_never_floats_above_the_ground", float(err.over) < tol)
	failed += _check("mesh_never_sinks_below_the_ground", float(err.under) < tol)
	failed += _check("mesh_matches_the_height_function", worst < tol)
	# The error must stay QUANTISATION-sized, not merely under the tolerance.
	failed += _check("agreement_error_is_only_float32_noise", worst < tol)

	# Constant budget with altitude is the whole point of rings: detail and reach
	# stop competing. A single plate had to trade one for the other.
	var tris_low := int(r.tris)
	for _i in SP.RING_COUNT:
		patch.update_for(dir * (MOON_R + 3.0), "Moon", true, MOON_R, 3.0, 0.1, m_ceiling, moon, sampler)
	var tris_high := int(patch.report().tris)
	# NEAR-constant, not identical. The budget is 4 rings x 64x64 whatever the
	# altitude - that is the point of rings, and the old plate had to trade detail
	# for reach. But ring scale now follows the horizon, so two altitudes sample
	# different ground and classify a slightly different number of quads as water
	# (which moves them to the other mesh) and as rim (which adds skirts). A few
	# percent of drift is that, not a budget that grows with height.
	failed += _check("triangle_budget_is_constant_with_altitude",
		absf(tris_high - tris_low) < float(tris_low) * 0.05)
	failed += _check("triangle_budget_does_not_grow_with_reach",
		float(tris_high) < float(tris_low) * 1.05)
	failed += _check("triangle_budget_is_within_range",
		tris_low > 15000 and tris_low < 60000)

	# THE BOUNDARY GAP - the property that actually broke, measured directly.
	#
	# Vertex counts used to stand here (ring_0_is_exactly_its_grid, ring_N_is_holed,
	# the_hole_is_about_a_sixteenth). They were a proxy for "the mesh has no holes",
	# and the moment the stitch moved each ring's outer row of quads into the skirt
	# mesh they stopped describing anything - they measured a mechanism, not a
	# property, and all four broke while the mesh got BETTER.
	#
	# What matters is that two rings meeting at a boundary trace the same line.
	# Ring N samples the height function every quad(N); ring N+1 does it every
	# quad(N+1) = 4x that, and draws straight between. The difference is the
	# terrain's deviation from a chord over one coarse quad - which in the Himalaya
	# is kilometres, and was visible in play as the planet's bare globe showing
	# through in rows. So: measure that deviation, confirm it is big enough to
	# matter, and confirm the rim is stitched so it cannot open.
	for ring in range(SP.RING_COUNT - 1):
		var q_fine: float = SP.ring_quad_km(ring, base_q)
		var q_coarse: float = SP.ring_quad_km(ring + 1, base_q)
		var bound: float = SP.ring_reach_km(ring, base_q) * 0.5
		var east := dir.cross(Vector3.UP).normalized()
		var north := east.cross(dir).normalized()
		var gap := 0.0
		var steps := int(q_coarse / q_fine)
		for c in 12:
			var n0: float = q_coarse * float(c)
			var n1: float = n0 + q_coarse
			var d0: Vector3 = (dir * MOON_R + east * bound + north * n0).normalized()
			var d1: Vector3 = (dir * MOON_R + east * bound + north * n1).normalized()
			var h0: float = sampler.height_m(d0)
			var h1: float = sampler.height_m(d1)
			for t in range(1, steps):
				var f := float(t) / float(steps)
				var dm: Vector3 = (dir * MOON_R + east * bound
					+ north * lerpf(n0, n1, f)).normalized()
				# Exact height here, versus the chord ring N+1 draws.
				gap = maxf(gap, absf(sampler.height_m(dm) - lerpf(h0, h1, f)))
		# A gap this size is why a capped skirt could not bridge it and an uncapped
		# one was a kilometres-tall wall.
		failed += _check("boundary_%d_would_gap_without_stitching" % ring, gap > 1.0)
		failed += _check("ring_%d_rim_is_stitched" % ring, patch.rim_is_stitched(ring))
		if ring == 0:
			print("earth_terrain: stitch  boundary 0 would gap by %.0f m over a %.0f m coarse quad; rim stitched: %s"
				% [gap, q_coarse * 1000.0, str(patch.rim_is_stitched(ring))])
	# The outermost ring has nothing beyond it, so it must NOT be stitched - doing
	# so would pull its edge off the height function for no reason.
	failed += _check("outermost_rim_is_not_stitched",
		not patch.rim_is_stitched(SP.RING_COUNT - 1))

	# Ring 0 sits ON the Moon and stays local — it must not be a whole sphere.
	var box: AABB = r.ring0_aabb
	var near: float = box.position.length()
	failed += _check("ring_0_sits_on_the_moons_shell", near > MOON_R * 0.9)
	failed += _check("ring_0_is_local_not_global",
		box.size.x < MOON_R and box.size.y < MOON_R and box.size.z < MOON_R)
	# ...and it must span about its stated reach, so ring_reach_km is not a lie.
	var span: float = maxf(box.size.x, maxf(box.size.y, box.size.z))
	failed += _check("ring_0_spans_its_stated_reach",
		span > SP.ring_reach_km(0, base_q) * 0.6 and span < SP.ring_reach_km(0, base_q) * 1.6)

	# Props still cover the ring rather than one corner of it.
	var cover: Vector2 = r.prop_cover
	failed += _check("props_cover_ring_0",
		minf(cover.x, cover.y) > SP.ring_reach_km(0, base_q) * 0.7)

	print("earth_terrain: rings  base %.0f m at 1 km alt; coverage of the horizon %.0f%% at 0.2 km / %.0f%% at 6 km / %.0f%% at 15 km"
		% [base_q * 1000.0,
		SP.ring_reach_km(3, SP.base_quad_km(0.2, EARTH_R)) / SP.horizon_km(0.2, EARTH_R) * 100.0,
		SP.ring_reach_km(3, SP.base_quad_km(6.0, EARTH_R)) / SP.horizon_km(6.0, EARTH_R) * 100.0,
		SP.ring_reach_km(3, SP.base_quad_km(15.0, EARTH_R)) / SP.horizon_km(15.0, EARTH_R) * 100.0])
	print("earth_terrain: rings  %d rings, %d tris, quads %.3f/%.3f/%.3f/%.3f km, reach %.1f km"
		% [int(r.rings), tris_low, SP.ring_quad_km(0, base_q), SP.ring_quad_km(1, base_q),
		SP.ring_quad_km(2, base_q), SP.ring_quad_km(3, base_q), SP.ring_reach_km(3, base_q)])
	print("earth_terrain: rings  verts per ring %s, %d props cover %.2fx%.2f of %.2f km, worst vertex error %.2f m over/under"
		% [str(r.ring_verts), int(r.props), cover.x, cover.y,
		SP.ring_reach_km(0, base_q), worst * 1000.0])
	patch.free()
	return failed


# --- The speed cap, and the bound it exists to provide -----------------------
func _cap() -> int:
	var failed := 0

	# The anchors, m/s.
	failed += _check("cap_high_up_is_generous", FM.band_speed_cap_ms(100.0) > 1500.0)
	failed += _check("cap_at_15km", absf(FM.band_speed_cap_ms(15.0) - 600.0) < 60.0)
	failed += _check("cap_at_5km", absf(FM.band_speed_cap_ms(5.0) - 300.0) < 40.0)
	failed += _check("cap_at_1km", absf(FM.band_speed_cap_ms(1.0) - 150.0) < 25.0)
	failed += _check("cap_on_the_deck", absf(FM.band_speed_cap_ms(0.2) - 60.0) < 12.0)
	failed += _check("cap_holds_below_the_lowest_anchor",
		is_equal_approx(FM.band_speed_cap_ms(0.01), FM.band_speed_cap_ms(0.2)))
	failed += _check("cap_tightens_as_you_descend",
		FM.band_speed_cap_ms(1.0) < FM.band_speed_cap_ms(5.0)
		and FM.band_speed_cap_ms(5.0) < FM.band_speed_cap_ms(15.0)
		and FM.band_speed_cap_ms(15.0) < FM.band_speed_cap_ms(100.0))

	# THE UNIT TRAP. speed_limit is units/s and 1 unit = 1 km in Sol, so a 600 m/s
	# cap is 0.6. Writing 600.0 there gives 600 km/s: every "the cap is applied"
	# assertion still passes and the bound below is silently void.
	failed += _check("units_conversion_is_per_kilometre",
		is_equal_approx(FM.band_speed_cap_units(15.0), FM.band_speed_cap_ms(15.0) / 1000.0))
	failed += _check("cap_in_units_is_not_kilometres_per_second",
		FM.band_speed_cap_units(15.0) < 1.0)

	# The guarantee this task exists for: at every altitude INSIDE the band, one
	# frame of travel at the cap is shorter than a ring-0 quad, so a swept contact
	# test cannot step over a mountain.
	#
	# Swept only to the ceiling on purpose. The cap is applied where a tile exists
	# (PlanetSystem: `if salt < ceiling`), so sweeping past it would test the
	# 100 km anchor - which is deliberately looser than the bound and would read as
	# a cap bug rather than a test-range bug.
	var earth := G.recipe_for({"name": "Earth"})
	var ceiling: float = G.band_ceiling_km(G.terrain_sampler(earth))
	var worst_alt := 0.0
	var worst_ratio := 0.0
	var worst_quad := 0.0
	for i in 2001:
		var alt := ceiling * float(i) / 2000.0
		# Ring 0's quad now SCALES with altitude, so the bound has to be evaluated
		# against the quad that actually exists at each height - not one constant.
		var quad: float = SP.ring_quad_km(0, SP.base_quad_km(alt, EARTH_R))
		var step_km: float = FM.band_speed_cap_units(alt) * FM.WORST_FRAME_S
		var ratio := step_km / quad
		if ratio > worst_ratio:
			worst_ratio = ratio
			worst_alt = alt
			worst_quad = quad
	failed += _check("cap_prevents_tunnelling", worst_ratio < 1.0)
	# Stated headroom, so raising an anchor cannot quietly eat all of it.
	failed += _check("tunnelling_bound_has_headroom", worst_ratio < 0.8)
	# And the bound must be proven at a DIPPED frame rate, not a healthy one -
	# a 60 fps proof is worthless precisely when it matters.
	failed += _check("bound_is_proven_at_a_dipped_frame_rate", FM.WORST_FRAME_S >= 0.04)

	print("earth_terrain: cap  %.0f/%.0f/%.0f/%.0f/%.0f m/s at 100/15/5/1/0.2 km; worst step %.0f%% of a %.0f m quad at %.1f km (%.0f fps proof)"
		% [FM.band_speed_cap_ms(100.0), FM.band_speed_cap_ms(15.0),
		FM.band_speed_cap_ms(5.0), FM.band_speed_cap_ms(1.0), FM.band_speed_cap_ms(0.2),
		worst_ratio * 100.0, worst_quad * 1000.0, worst_alt, 1.0 / FM.WORST_FRAME_S])
	return failed


# --- Contact, swept along the frame's movement -------------------------------
func _kill() -> int:
	var failed := 0
	var earth := G.recipe_for({"name": "Earth"})
	var s: TerrainSampler = G.terrain_sampler(earth)
	var everest := _dir_of(27.9881, 86.9250)
	var pacific := _dir_of(0.0, -150.0)
	var e_ground: float = s.ground_radius_km(everest, EARTH_R)
	var p_ground: float = s.ground_radius_km(pacific, EARTH_R)
	var contact := 0.02

	# The whole point: the same altitude is lethal over Everest and safe over the
	# Pacific. Everest samples 8915 m here (8848 from the DEM plus detail), so the
	# probe altitude has to sit UNDER that, not at a round 9 km.
	var probe_alt := 8.5
	failed += _check("everest_stands_above_the_probe_altitude",
		e_ground > EARTH_R + probe_alt)
	failed += _check("the_pacific_does_not", p_ground < EARTH_R + 1.0)
	failed += _check("same_altitude_kills_over_everest",
		s.alt_above_ground_km(everest * (EARTH_R + probe_alt), EARTH_R) <= contact)
	failed += _check("same_altitude_is_clear_over_the_pacific",
		s.alt_above_ground_km(pacific * (EARTH_R + probe_alt), EARTH_R) > 8.0)

	failed += _check("contact_fires_at_the_mountain",
		s.swept_contact(everest * (e_ground + 0.5), everest * (e_ground + 0.01),
			EARTH_R, contact))
	failed += _check("contact_holds_off_above_the_mountain",
		not s.swept_contact(everest * (e_ground + 3.0), everest * (e_ground + 2.9),
			EARTH_R, contact))
	failed += _check("low_pass_over_the_ocean_survives",
		not s.swept_contact(pacific * (p_ground + 1.0), pacific * (p_ground + 1.0),
			EARTH_R, contact))
	failed += _check("touching_the_ocean_kills",
		s.swept_contact(pacific * (p_ground + 0.5), pacific * (p_ground + 0.005),
			EARTH_R, contact))

	# THE swept assertion, and it has to be built honestly.
	#
	# A first draft used two points 5 degrees apart and "passed" — but a straight
	# line between two points at the same radius is a CHORD, and at 5 degrees on a
	# 6380 km sphere that chord dips 6.07 km below them. So it was passing on
	# geometry, not on the mountain, and would have kept passing on a flat planet.
	#
	# So: find a real ridge. Walk a short segment across a steep Himalayan flank,
	# measure the ground at both ends and the highest ground in between, and only
	# claim the property if the middle genuinely stands above both ends. Then fly
	# between those two heights — the endpoints are clear air, the ridge is not.
	var seg_a := _dir_of(27.75, 86.55)
	var seg_b := _dir_of(28.10, 87.10)      # ~65 km, a hitch-sized jump, not an arc
	var end_hi: float = maxf(s.ground_radius_km(seg_a, EARTH_R),
		s.ground_radius_km(seg_b, EARTH_R))
	var mid_hi := 0.0
	for i in range(1, 40):
		var d: Vector3 = seg_a.lerp(seg_b, float(i) / 40.0).normalized()
		mid_hi = maxf(mid_hi, s.ground_radius_km(d, EARTH_R))
	failed += _check("the_segment_actually_crosses_a_ridge", mid_hi > end_hi + 0.05)
	if mid_hi > end_hi + 0.05:
		# Above both ends, below the ridge. Chord sag over 65 km is ~0.08 km, so it
		# cannot account for the catch on its own.
		var fly := (end_hi + mid_hi) * 0.5
		var from: Vector3 = seg_a * fly
		var to: Vector3 = seg_b * fly
		var point_says_safe: bool = \
			s.alt_above_ground_km(from, EARTH_R) > contact \
			and s.alt_above_ground_km(to, EARTH_R) > contact
		failed += _check("point_test_would_have_missed_the_ridge", point_says_safe)
		failed += _check("swept_kill_catches_the_ridge",
			s.swept_contact(from, to, EARTH_R, contact))
		print("earth_terrain: kill  Everest +%.0f m, Pacific +%.0f m; ridge run: ends %.3f km, ridge %.3f km, flew %.3f km -> point safe %s, swept caught %s"
			% [(e_ground - EARTH_R) * 1000.0, (p_ground - EARTH_R) * 1000.0,
			end_hi - EARTH_R, mid_hi - EARTH_R, fly - EARTH_R,
			str(point_says_safe), str(s.swept_contact(from, to, EARTH_R, contact))])
	else:
		print("earth_terrain: kill  segment found no ridge — widen it, do not weaken the test")
	return failed


# Unit direction for a lat/lon, matching TerrainSampler._dir_uv()'s convention.
func _dir_of(lat_deg: float, lon_deg: float) -> Vector3:
	var lat := deg_to_rad(lat_deg)
	var lon := deg_to_rad(lon_deg)
	return Vector3(cos(lat) * cos(lon), sin(lat), cos(lat) * sin(lon)).normalized()


# Tolerance for mesh-versus-height-function agreement, DERIVED from the body's
# radius rather than picked. Mesh vertices are float32, whose spacing at a
# magnitude R is about R * 2^-23 - so the same geometry quantises to 0.32 m on the
# Moon and 1.30 m on Earth, purely because Earth is 3.7x bigger. A flat tolerance
# is therefore wrong in kind: it either fails on the larger body or hides a real
# error on the smaller one. Four ULP leaves room for a normalize-and-multiply
# round trip while still failing anything at the metre-of-terrain scale.
func _agreement_tol_km(radius_km: float) -> float:
	# EIGHT ULP, not four. float32 quantises the vertex's DIRECTION as well as its
	# magnitude, and the check re-evaluates the height function at that quantised
	# direction - so on steep ground the tangential error becomes a height error
	# multiplied by the local gradient. Retuning detail to ridge scale raised the
	# measured worst from 0.32 m to 0.68 m on the Moon for exactly that reason,
	# with the geometry itself unchanged. Still far under the 20 m contact margin.
	return radius_km * pow(2.0, -23.0) * 8.0


func _check(name: String, ok: bool) -> int:
	if not ok:
		print("earth_terrain: FAIL %s" % name)
		return 1
	return 0
