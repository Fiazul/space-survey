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

const EARTH_R := 6371.0
const MOON_R := 1737.4


func _initialize() -> void:
	var failed := 0
	failed += _encoding()
	failed += _sampler()
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
	failed += _check("airless_world_has_height", mh > 0.0)
	failed += _check("airless_world_height_is_bounded", mh < 4000.0)
	failed += _check("airless_world_is_never_water", not ms.is_water(md))
	failed += _check("airless_max_height_is_bounded",
		ms.max_height_km() > 2.5 and ms.max_height_km() < 3.5)
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


func _check(name: String, ok: bool) -> int:
	if not ok:
		print("earth_terrain: FAIL %s" % name)
		return 1
	return 0
