extends SceneTree
const G := preload("res://scripts/world/planet_generator.gd")
const SP := preload("res://scripts/world/surface_patch.gd")
const CL := preload("res://scripts/world/cloud_layer.gd")
var failures := 0

func _initialize() -> void:
	var earth := G.recipe_for({"name": "Earth"})
	var moon := G.recipe_for({"name": "Moon"})
	var earth_s := G.terrain_sampler(earth)
	var ceiling := G.band_ceiling_km(earth_s)

	# Shell radius = body radius + cloud_alt_km.
	var layer := CL.new()
	layer.call("_ready")
	layer.update_for(Vector3.ZERO, "Earth", true, 6371.0, 10.0, 0.02, ceiling, earth, Vector3.RIGHT, 0.0)
	var mesh: SphereMesh = layer.get("_mesh").mesh
	check("shell_radius_is_body_plus_cloud_alt",
		is_equal_approx(mesh.radius, 6371.0 + CL.cloud_alt_km(earth)))

	# Visible-gate mirrors the ring gate (SurfacePatch.should_show), narrowed by
	# whether the recipe carries any cloud coverage.
	check("cloud_gate_true_when_ring_open_and_recipe_has_clouds",
		CL.should_show("Earth", true, 10.0, 0.02, ceiling, earth)
		== SP.should_show("Earth", true, 10.0, 0.02, ceiling, earth))
	check("cloud_gate_false_above_ceiling_like_ring",
		not CL.should_show("Earth", true, ceiling + 5.0, 0.02, ceiling, earth)
		and not SP.should_show("Earth", true, ceiling + 5.0, 0.02, ceiling, earth))
	check("cloud_gate_false_below_kill_like_ring",
		not CL.should_show("Earth", true, 0.0, 0.02, ceiling, earth)
		and not SP.should_show("Earth", true, 0.0, 0.02, ceiling, earth))

	# Airless/cloudless body: ring can still open (rock terrain), the deck must not.
	var moon_ceiling := G.band_ceiling_km(G.terrain_sampler(moon))
	check("ring_opens_on_moon", SP.should_show("Moon", true, 1.0, 0.02, moon_ceiling, moon))
	check("no_cloud_layer_on_airless_moon",
		not CL.should_show("Moon", true, 1.0, 0.02, moon_ceiling, moon))

	# Arcade "altitude" is really a million km in 0.01-AU units — never gate open.
	check("cloud_gate_guards_non_physical_bodies",
		not CL.should_show("Fictional", false, 10.0, 0.02, ceiling, earth))

	# Regression (2026-09-08): Earth's cloud_amount=1.0 used to slide the
	# map-backed threshold centre to 0, so a genuinely clear texel (raw=0)
	# read back ~0.5 coverage — grey haze over bare desert regardless of the
	# map. raw=0 must stay coverage=0 for every cloud_amount, map-backed or not.
	check("map_backed_clear_texel_is_never_covered_at_full_cloud_amount",
		CL.coverage_from_raw(0.0, 1.0, true) == 0.0)
	check("map_backed_clear_texel_is_never_covered_at_any_cloud_amount",
		CL.coverage_from_raw(0.0, 0.5, true) == 0.0
		and CL.coverage_from_raw(0.0, 0.01, true) == 0.0)
	check("map_backed_dense_texel_is_covered",
		CL.coverage_from_raw(1.0, 1.0, true) > 0.9)
	check("procedural_clear_raw_is_never_covered",
		CL.coverage_from_raw(0.0, 1.0, false) == 0.0
		and CL.coverage_from_raw(0.0, 0.01, false) == 0.0)
	check("procedural_coverage_stays_in_unit_range",
		CL.coverage_from_raw(0.5, 1.0, false) >= 0.0 and CL.coverage_from_raw(0.5, 1.0, false) <= 1.0
		and CL.coverage_from_raw(0.5, 0.01, false) >= 0.0 and CL.coverage_from_raw(0.5, 0.01, false) <= 1.0)

	# Player report (2026-09-08b): "too much cloud, Earth always covered" — a
	# direct coverage=alpha reading of the ~60%-coverage NASA map paints almost
	# the whole limb opaque. opacity_from_coverage must (a) stay 0 at 0
	# coverage, (b) cap below full opacity even at max coverage/amount, and
	# (c) scale down with cloud_amount/cloud_opacity so a thin recipe reads thin.
	check("clear_coverage_is_never_opaque",
		CL.opacity_from_coverage(0.0, 1.0, 1.0) == 0.0)
	check("opacity_never_reaches_full_even_at_max_coverage",
		CL.opacity_from_coverage(1.0, 1.0, 1.0) < 1.0
		and CL.opacity_from_coverage(1.0, 1.0, 1.0) <= CL.OPACITY_CAP)
	check("opacity_scales_down_with_cloud_amount",
		CL.opacity_from_coverage(1.0, 0.5, 1.0) < CL.opacity_from_coverage(1.0, 1.0, 1.0))
	check("opacity_scales_down_with_cloud_opacity_field",
		CL.opacity_from_coverage(1.0, 1.0, 0.4) < CL.opacity_from_coverage(1.0, 1.0, 1.0))
	check("cloud_opacity_field_defaults_to_1",
		is_equal_approx(CL.cloud_opacity({}), 1.0))

	# Player report (2026-09-08b): "clouds are always in the same spot." Drift
	# must be zero at t=0, strictly advance with sim time, and CPU/shader share
	# the identical static so coverage_at()'s fog can never desync from what
	# the shell actually paints.
	check("drift_is_zero_at_time_zero", CL.cloud_uv_offset(0.0) == Vector2.ZERO)
	check("drift_advances_with_sim_time",
		CL.cloud_uv_offset(120.0).x > CL.cloud_uv_offset(0.0).x)
	check("drift_is_purely_a_function_of_time_not_wallclock",
		CL.cloud_uv_offset(60.0) == CL.cloud_uv_offset(60.0))

	# Sub-texel detail (2026-09-09): from 20 km a map-backed deck read as a
	# smooth blob with blurry ~50 km holes — no structure between the 2k map's
	# ~20 km texel and the ground. erode_with_detail must still guarantee
	# raw=0 -> coverage=0 for EVERY detail value (a clear texel never grows
	# cloud out of noise), erode a dense texel only a little (stays "mostly
	# filled"), and be able to fully clear a marginal texel when detail is low
	# (the "scattered cells" case).
	var clear_coverage := CL.coverage_from_raw(0.0, 1.0, true)
	for d in [0.0, 0.3, 0.7, 1.0]:
		check("raw_zero_stays_zero_with_detail_on_%s" % d,
			CL.erode_with_detail(clear_coverage, d) == 0.0)
	check("dense_texel_barely_erodes_at_worst_detail",
		CL.erode_with_detail(0.98, 0.0) > 0.9)
	check("marginal_texel_can_clear_to_zero_at_low_detail",
		CL.erode_with_detail(0.3, 0.0) == 0.0)
	check("marginal_texel_survives_at_high_detail",
		CL.erode_with_detail(0.3, 1.0) == 0.3)

	# detail_field_uv/detail_field_dir are a line-for-line GDScript port of the
	# shader's detail_field_uv/detail_field_dir + noise()/hash() (see the
	# const block above coverage_from_raw) — same formula, same inputs, so
	# parity with the GPU is by construction rather than tuned; the residual
	# is only GLSL-vs-GDScript float rounding (float32 either side, ~1e-6).
	# This --script test has no GL context to read back an actual rendered
	# frame (CLAUDE.md: plain --headless never delivers one), so this checks
	# the CPU port's own behaviour across 20 sample directions instead of
	# diffing against a live GPU pixel: bounded output, and NOT constant
	# (proving the octaves actually vary the field, not a no-op).
	var samples: Array[float] = []
	for i in range(20):
		var lon := float(i) * TAU / 20.0
		var lat := (float(i % 5) / 5.0 - 0.5) * PI * 0.9
		var dir := Vector3(cos(lat) * cos(lon), sin(lat), cos(lat) * sin(lon)).normalized()
		var uv := CL._dir_uv(dir)
		var val := CL.detail_field_uv(uv, TAU * 6371.0, 0.0)
		samples.append(val)
		check("detail_field_uv_in_unit_range_%d" % i, val >= 0.0 and val <= 1.0)
	var all_same := true
	for v in samples:
		if not is_equal_approx(v, samples[0]):
			all_same = false
			break
	check("detail_field_uv_varies_across_directions", not all_same)

	# Band-limit fix (2026-09-09, clouds_above_20km_r5 speckle): each octave's
	# weight must fade to 0 as its footprint approaches the aliasing zone
	# (wavelength/1.5) and stay at 1 well inside it (wavelength/4), monotonic
	# in between, matching SurfaceRecipe's terrain law exactly.
	for wavelen in [CL.DETAIL_WAVELEN_KM_0, CL.DETAIL_WAVELEN_KM_1, CL.DETAIL_WAVELEN_KM_2]:
		check("band_weight_full_at_wavelen_over_4_%s" % wavelen,
			is_equal_approx(CL._detail_band_weight(wavelen, wavelen / 4.0), 1.0))
		check("band_weight_zero_at_wavelen_over_1_5_%s" % wavelen,
			is_equal_approx(CL._detail_band_weight(wavelen, wavelen / 1.5), 0.0))
		var prev := 2.0  # weight at the smallest footprint sampled below
		var monotonic := true
		for step in range(1, 21):
			var footprint: float = (wavelen / 4.0) + (float(step) / 20.0) * (wavelen / 1.2 - wavelen / 4.0)
			var w: float = CL._detail_band_weight(wavelen, footprint)
			if w > prev + 1e-6:
				monotonic = false
			prev = w
		check("band_weight_monotonic_non_increasing_%s" % wavelen, monotonic)
	check("band_weight_full_detail_when_footprint_zero",
		is_equal_approx(CL._detail_band_weight(CL.DETAIL_WAVELEN_KM_2, 0.0), 1.0))

	# Faded octaves must land on their MEAN, not 0 — coverage can't shift just
	# because the deck is viewed from farther away. A footprint far past every
	# octave's aliasing zone collapses detail_field_uv to a constant (all three
	# terms sit at DETAIL_MEAN), and that constant must match the unfaded
	# field's own average across many directions within sampling tolerance.
	var huge_footprint := 10000.0
	var faded_samples: Array[float] = []
	for i in range(20):
		var lon2 := float(i) * TAU / 20.0
		var lat2 := (float(i % 5) / 5.0 - 0.5) * PI * 0.9
		var dir2 := Vector3(cos(lat2) * cos(lon2), sin(lat2), cos(lat2) * sin(lon2)).normalized()
		var uv2 := CL._dir_uv(dir2)
		faded_samples.append(CL.detail_field_uv(uv2, TAU * 6371.0, 0.0, huge_footprint))
	var faded_mean := 0.0
	for v in faded_samples:
		faded_mean += v
	faded_mean /= faded_samples.size()
	check("fully_faded_detail_is_constant_at_mean",
		absf(faded_mean - CL.DETAIL_MEAN) < 0.001)
	var unfaded_mean := 0.0
	for v in samples:
		unfaded_mean += v
	unfaded_mean /= samples.size()
	check("faded_mean_matches_unfaded_mean_within_tolerance",
		absf(faded_mean - unfaded_mean) < 0.15)

	# Player report (2026-09-09b): "Light was only thinner, not fewer clouds" —
	# LO/HI used to be fixed regardless of cloud_amount, so Light and Full
	# covered the identical AREA at half the alpha. Measure the actual area
	# fraction over Earth's real cloud map at each GameState.cloud_quality
	# level (CLOUD_QUALITY_MULT = [0.0, 0.5, 1.0], mirrors PlanetSystem's
	# table) so this is a real regression guard, not just a unit-level check
	# of coverage_from_raw in isolation.
	var cloud_tex := load("res://assets/planets/earth_clouds_2k.jpg") as Texture2D
	var cloud_img := cloud_tex.get_image()
	if cloud_img.is_compressed():
		cloud_img.decompress()
	cloud_img.convert(Image.FORMAT_R8)
	var cw := cloud_img.get_width()
	var ch := cloud_img.get_height()
	var quality_mult := [0.0, 0.5, 1.0]
	var any_frac: Array[float] = [0.0, 0.0, 0.0]
	var dense_frac: Array[float] = [0.0, 0.0, 0.0]
	for q in range(quality_mult.size()):
		var amount: float = quality_mult[q]
		var any_n := 0
		var dense_n := 0
		# Full-resolution sweep is too slow for a --script test loop; stride
		# samples every 4th texel (~131k of the 2048x1024 texels), enough to
		# measure area fraction within a fraction of a percent.
		var stride := 4
		var total := 0
		for y in range(0, ch, stride):
			for x in range(0, cw, stride):
				var raw: float = cloud_img.get_pixel(x, y).r
				var cov: float = CL.coverage_from_raw(raw, amount, true)
				if cov > 0.02:
					any_n += 1
				if cov > 0.5:
					dense_n += 1
				total += 1
		any_frac[q] = float(any_n) / total
		dense_frac[q] = float(dense_n) / total
		print("cloud_layer: area quality=%d (amount=%.2f) any=%.3f dense=%.3f"
			% [q, amount, any_frac[q], dense_frac[q]])
	check("full_any_cloud_in_35_50_pct_of_real_map", any_frac[2] >= 0.35 and any_frac[2] <= 0.50)
	check("light_any_cloud_near_20_pct", any_frac[1] >= 0.12 and any_frac[1] <= 0.28)
	check("light_dense_near_10_pct", dense_frac[1] >= 0.05 and dense_frac[1] <= 0.18)
	check("light_covers_meaningfully_less_area_than_full", any_frac[1] < any_frac[2] * 0.7)
	check("any_cloud_area_monotonic_with_quality", any_frac[0] <= any_frac[1] and any_frac[1] <= any_frac[2])
	check("dense_cloud_area_monotonic_with_quality", dense_frac[0] <= dense_frac[1] and dense_frac[1] <= dense_frac[2])

	# Shader/CPU formula parity (same idea as the detail_field_uv line-for-line
	# port above, but GLSL has no way to import a GDScript const, so both
	# shaders re-declare these four numbers as literal text — scan the actual
	# shipped source for the same numbers rather than trusting the mirror
	# comments, catching the category of bug where only one of the three
	# copies gets tuned).
	check("cl_consts_are_the_measured_values",
		is_equal_approx(CL.MAP_THRESH_LO, 0.28) and is_equal_approx(CL.MAP_THRESH_HI, 0.65)
		and is_equal_approx(CL.THRESH_SHIFT_LO_MAX, 0.45) and is_equal_approx(CL.THRESH_SHIFT_HI_MAX, 0.25))
	var shell_src := FileAccess.get_file_as_string("res://shaders/cloud_layer.gdshader")
	var globe_src := FileAccess.get_file_as_string("res://shaders/planet_cook.gdshader")
	check("shell_shader_thresh_lo_matches_cpu", "MAP_THRESH_LO = 0.28;" in shell_src)
	check("shell_shader_thresh_hi_matches_cpu", "MAP_THRESH_HI = 0.65;" in shell_src)
	check("shell_shader_shift_lo_matches_cpu", "THRESH_SHIFT_LO_MAX = 0.45;" in shell_src)
	check("shell_shader_shift_hi_matches_cpu", "THRESH_SHIFT_HI_MAX = 0.25;" in shell_src)
	check("globe_shader_thresh_lo_matches_cpu", "CLOUD_MAP_THRESH_LO = 0.28;" in globe_src)
	check("globe_shader_thresh_hi_matches_cpu", "CLOUD_MAP_THRESH_HI = 0.65;" in globe_src)
	check("globe_shader_shift_lo_matches_cpu", "CLOUD_THRESH_SHIFT_LO_MAX = 0.45;" in globe_src)
	check("globe_shader_shift_hi_matches_cpu", "CLOUD_THRESH_SHIFT_HI_MAX = 0.25;" in globe_src)

	# Globe wiring (item 2, player report "far globe ignores the setting"): the
	# far globe's material used to bake cloud_amount ONCE at construction and
	# never again. PlanetGenerator.set_cloud_amount() is the per-frame setter
	# planet_system.gd's refresh calls next to set_cloud_drift — confirm it
	# actually reaches the material's shader parameter, both up and down to 0
	# (Off quality).
	var globe_recipe := G.recipe_for({"name": "Earth"})
	var globe_mat: ShaderMaterial = G.make_material(globe_recipe, {"spectral": "G"}) as ShaderMaterial
	check("globe_cloud_amount_starts_at_recipe_value",
		is_equal_approx(float(globe_mat.get_shader_parameter("cloud_amount")), float(globe_recipe.cloud_amount)))
	G.set_cloud_amount(globe_mat, 0.5)
	check("globe_cloud_amount_follows_setter", is_equal_approx(float(globe_mat.get_shader_parameter("cloud_amount")), 0.5))
	G.set_cloud_amount(globe_mat, 0.0)
	check("globe_cloud_amount_can_go_to_zero_for_off_quality",
		is_equal_approx(float(globe_mat.get_shader_parameter("cloud_amount")), 0.0))

	# Limb altitude fade (item 3, "60 km glowing wall"): apply_view()'s new
	# optional alt_km/atmo_top_km args must reach the shader, and omitting
	# them must keep the old sentinel (no narrowing) so every un-updated call
	# site is unaffected.
	var limb_mat: ShaderMaterial = G.make_material(globe_recipe, {"spectral": "G"}) as ShaderMaterial
	G.apply_view(limb_mat, Vector3.RIGHT, 0.0)
	check("apply_view_defaults_alt_km_to_sentinel",
		float(limb_mat.get_shader_parameter("ship_alt_km")) < 0.0)
	check("apply_view_defaults_atmo_top_km_to_sentinel",
		float(limb_mat.get_shader_parameter("atmo_top_km")) < 0.0)
	G.apply_view(limb_mat, Vector3.RIGHT, 0.0, 60.0, 100.0)
	check("apply_view_threads_alt_km", is_equal_approx(float(limb_mat.get_shader_parameter("ship_alt_km")), 60.0))
	check("apply_view_threads_atmo_top_km", is_equal_approx(float(limb_mat.get_shader_parameter("atmo_top_km")), 100.0))

	layer.free()
	print("cloud_layer: ", "OK" if failures == 0 else "FAIL %d" % failures)
	quit(0 if failures == 0 else 1)

func check(label: String, ok: bool) -> void:
	if not ok:
		failures += 1
		push_error("cloud_layer: " + label)
