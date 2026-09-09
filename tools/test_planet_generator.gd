extends SceneTree
# Headless check: one cook, named Sol recipes, invented look for strangers.
# Run: godot --headless --path . --script res://tools/test_planet_generator.gd

const G := preload("res://scripts/world/planet_generator.gd")


func _initialize() -> void:
	var failed := 0
	var earth := G.recipe_for({ "name": "Earth", "color": Color(0.2, 0.5, 0.8), "physical": true })
	failed += _check("earth_named", earth.name == "Earth")
	failed += _check("earth_rocky", earth.kind == "rocky")
	failed += _check("earth_has_slot", str(earth.albedo).begins_with("res://assets/planets/"))
	failed += _check("earth_map_exists", G.has_map(earth))
	failed += _check("earth_features_slot", earth.has("features"))

	var mars := G.recipe_for({ "name": "Mars" })
	failed += _check("mars_map", G.has_map(mars))

	var prox := G.invent({ "name": "Proxima b", "color": Color(0.62, 0.46, 0.40), "radius": 3.2 })
	failed += _check("proxima_invented", prox.source == "invented")
	failed += _check("proxima_no_map", not G.has_map(prox))
	failed += _check("proxima_rocky", prox.kind == "rocky")
	failed += _check("proxima_has_land", float(prox.get("land_amount", 0.0)) > 0.2)
	failed += _check("proxima_split", prox.get("color_land") != prox.get("color_ocean"))

	var hycean := G.invent({ "name": "K2-18b", "color": Color(0.32, 0.62, 0.78), "radius": 3.8 })
	failed += _check("k218b_ice_or_gas", hycean.kind == "ice" or hycean.kind == "gas")
	failed += _check("hycean_has_islands", float(hycean.get("land_amount", 0.0)) > 0.05)
	failed += _check("hycean_mostly_ocean", float(hycean.get("land_amount", 1.0)) < 0.4)

	var a := G.invent({ "name": "Proxima b", "color": Color(0.62, 0.46, 0.40), "radius": 3.2 })
	var b := G.invent({ "name": "Proxima b", "color": Color(0.62, 0.46, 0.40), "radius": 3.2 })
	failed += _check("invent_stable_seed", is_equal_approx(float(a.seed), float(b.seed)))

	var unknown := G.recipe_for({ "name": "NoSuchWorld", "color": Color(0.5, 0.4, 0.3), "radius": 2.0 })
	failed += _check("unknown_falls_to_invent", unknown.source == "invented")

	var earth_r := G.recipe_for({ "name": "Earth" })
	failed += _check("earth_cloud_slot", str(earth_r.get("clouds", "")).contains("earth_clouds"))
	failed += _check("earth_night_slot", str(earth_r.get("night", "")).contains("earth_night"))
	failed += _check("earth_has_air", float(earth_r.get("air_amount", 0.0)) > 0.5)
	failed += _check("earth_height_slot", str(earth_r.get("height", "")).contains("earth_height"))
	failed += _check("earth_spec_slot", str(earth_r.get("specular", "")).contains("earth_spec"))
	failed += _check("earth_normal_slot", str(earth_r.get("normal", "")).contains("earth_normal"))
	failed += _check("mars_no_air", float(mars.get("air_amount", 0.0)) < 0.01)
	failed += _check("proxima_no_air", float(prox.get("air_amount", 0.0)) < 0.01)

	var painted := G.paint({ "name": "Earth", "color": Color(0.2, 0.5, 0.8), "physical": true, "radius": 10.0 }, 10.0)
	failed += _check("paint_sphere", painted.sphere != null and painted.mat != null)
	failed += _check("paint_uses_shader", painted.mat is ShaderMaterial)
	if painted.mat is ShaderMaterial:
		var sm := painted.mat as ShaderMaterial
		failed += _check("earth_cook_is_opaque", not sm.shader.code.contains("ALPHA ="))
		failed += _check("earth_uses_map", float(sm.get_shader_parameter("has_albedo")) > 0.5)
		failed += _check("earth_extras_lazy", float(sm.get_shader_parameter("has_clouds")) < 0.5)
		G.ensure_close_maps(sm, painted.recipe, false)   # sync bind — no frame loop to poll here
		failed += _check("earth_uses_clouds", float(sm.get_shader_parameter("has_clouds")) > 0.5)
		failed += _check("earth_uses_night", float(sm.get_shader_parameter("has_night")) > 0.5)
		failed += _check("earth_uses_air", float(sm.get_shader_parameter("air_amount")) > 0.5)
		failed += _check("earth_uses_height", float(sm.get_shader_parameter("has_height")) > 0.5)
		failed += _check("earth_uses_spec", float(sm.get_shader_parameter("has_spec")) > 0.5)
		var earth_height_tex := sm.get_shader_parameter("height_tex") as Texture2D
		failed += _check("earth_globe_binds_4k", earth_height_tex != null and str(earth_height_tex.resource_path).contains("earth_height_4k"))
		failed += _check("earth_datum_bound", absf(float(sm.get_shader_parameter("height_datum")) - 0.598) < 0.01)
		failed += _check("earth_signed_bound", float(sm.get_shader_parameter("height_signed")) > 0.5)
	painted.sphere.free()

	# globe_height_path(): one helper, every GPU height bind goes through it.
	failed += _check("globe_height_path_prefers_override", G.globe_height_path(earth_r) == "res://assets/planets/earth_height_4k.png")
	failed += _check("globe_height_path_falls_back", G.globe_height_path(mars) == str(mars.get("height", "")))
	failed += _check("globe_height_path_no_map", G.globe_height_path(G.recipe_for({ "name": "Sun", "star": true })) == "")

	var moon_r := G.recipe_for({ "name": "Moon" })
	var moon_p := G.paint({ "name": "Moon", "physical": true, "radius": 4.0 }, 4.0)
	if moon_p.mat is ShaderMaterial:
		var msm := moon_p.mat as ShaderMaterial
		G.ensure_close_maps(msm, moon_p.recipe, false)
		var moon_height_tex := msm.get_shader_parameter("height_tex") as Texture2D
		failed += _check("moon_binds_own_height", moon_height_tex != null and str(moon_height_tex.resource_path).contains("moon_height_4k"))
		failed += _check("moon_datum_bound", absf(float(msm.get_shader_parameter("height_datum")) - float(moon_r.get("height_datum", 0.0))) < 0.001)
	moon_p.sphere.free()

	var mars_p := G.paint({ "name": "Mars", "physical": true, "radius": 3.4 }, 3.4)
	if mars_p.mat is ShaderMaterial:
		var mrsm := mars_p.mat as ShaderMaterial
		G.ensure_close_maps(mrsm, mars_p.recipe, false)
		var mars_height_tex := mrsm.get_shader_parameter("height_tex") as Texture2D
		failed += _check("mars_binds_own_height", mars_height_tex != null and str(mars_height_tex.resource_path).contains("mars_height_4k"))
		failed += _check("mars_datum_bound", absf(float(mrsm.get_shader_parameter("height_datum")) - float(mars.get("height_datum", 0.0))) < 0.001)
	mars_p.sphere.free()

	var sun_r := G.recipe_for({ "name": "Sun", "star": true })
	failed += _check("sun_star", sun_r.kind == "star")
	failed += _check("sun_map", G.has_map(sun_r))
	var sun_p := G.paint({ "name": "Sun", "star": true, "physical": true, "radius": 20.0 }, 20.0)
	if sun_p.mat is ShaderMaterial:
		var sun_sm := sun_p.mat as ShaderMaterial
		failed += _check("sun_kind3", int(sun_sm.get_shader_parameter("kind")) == 3)
		failed += _check("sun_uses_map", float(sun_sm.get_shader_parameter("has_albedo")) > 0.5)
		G.ensure_close_maps(sun_sm, sun_r, false)
		failed += _check("sun_binds_no_height", float(sun_sm.get_shader_parameter("has_height")) < 0.5)
	sun_p.sphere.free()

	var sat := G.recipe_for({ "name": "Saturn" })
	failed += _check("saturn_rings", G.has_rings(sat))
	var rmat := G.make_ring_material(sat)
	failed += _check("ring_mat", rmat != null and rmat.albedo_texture != null)
	var sat_p := G.paint({ "name": "Saturn", "physical": true, "radius": 9.0 }, 9.0)
	if sat_p.mat is ShaderMaterial:
		var sat_sm := sat_p.mat as ShaderMaterial
		G.ensure_close_maps(sat_sm, sat, false)
		failed += _check("gas_binds_no_height", float(sat_sm.get_shader_parameter("has_height")) < 0.5)
	sat_p.sphere.free()

	for nm in ["Io", "Europa", "Titan", "Enceladus", "Phobos", "Ganymede", "Callisto", "Mimas", "Tethys", "Dione", "Rhea", "Iapetus", "Miranda", "Ariel", "Umbriel", "Titania", "Oberon", "Triton", "Pluto", "Charon"]:
		var rec := G.recipe_for({ "name": nm })
		failed += _check(nm + "_named", rec.name == nm)
		failed += _check(nm + "_not_invented_kind", rec.get("kind", "") != "")
		failed += _check(nm + "_map", G.has_map(rec))

	failed += _check("europa_map", G.has_map(G.recipe_for({ "name": "Europa" })))
	failed += _check("io_map", G.has_map(G.recipe_for({ "name": "Io" })))
	failed += _check("enceladus_map", G.has_map(G.recipe_for({ "name": "Enceladus" })))
	failed += _check("titan_map", G.has_map(G.recipe_for({ "name": "Titan" })))
	failed += _check("deimos_pending_or_map", G.recipe_for({ "name": "Deimos" }).source in ["ready-map", "named-pending-map"])
	failed += _check("geo_is_close", G.close_enough(42157.0, 6371.0))
	failed += _check("mars_from_geo_far", not G.close_enough(2.2e8, 3389.5))

	var star_inv := G.invent({ "name": "Proxima Centauri", "star": true, "color": Color(1.0, 0.6, 0.4) })
	failed += _check("invent_star", star_inv.kind == "star")

	# Catalog → cook. No hand mesh. Spectral/size pick the look.
	var m_col: Color = G.color_from_spectral("M4.0V")
	var a_col: Color = G.color_from_spectral("A1V")
	failed += _check("spectral_m_redder", m_col.r >= a_col.r and m_col.b < a_col.b)
	var sirius := G.catalog_star({ "name": "Sirius", "spectral": "A1V", "ly": 8.71 })
	failed += _check("catalog_star_flag", bool(sirius.get("star", false)))
	failed += _check("catalog_star_no_glb", not sirius.has("model"))
	failed += _check("catalog_star_spectral", str(sirius.get("spectral", "")) == "A1V")
	var sirius_r := G.recipe_for(sirius)
	failed += _check("sirius_cooks_star", sirius_r.kind == "star")
	failed += _check("sirius_not_sol_map", not G.has_map(sirius_r))
	failed += _check("sirius_evidence_spectral", str(sirius_r.get("evidence", "")).contains("A1V"))
	var rock := G.catalog_planet({ "name": "Proxima b", "pl_rade": 1.07, "pl_eqt": 234.0 })
	failed += _check("catalog_earthish_rocky", str(rock.get("kind_hint", rock.get("kind", ""))) == "rocky" or float(rock.get("pl_rade", 9.0)) < 1.6)
	var rec_rock := G.recipe_for(rock)
	failed += _check("proxima_b_from_catalog", rec_rock.kind == "rocky" or rec_rock.kind == "ice")
	var gas := G.catalog_planet({ "name": "K2-18b", "pl_rade": 2.6, "pl_eqt": 250.0 })
	var rec_gas := G.recipe_for(gas)
	failed += _check("sub_neptune_not_star", rec_gas.kind != "star")
	var giant := G.catalog_planet({ "name": "HD 209458 b", "pl_rade": 15.0, "pl_eqt": 1400.0 })
	failed += _check("hot_jupiter_gas", G.recipe_for(giant).kind == "gas")
	var sirius_p := G.paint(sirius, float(sirius.get("radius", 5.0)))
	if sirius_p.mat is ShaderMaterial:
		failed += _check("catalog_star_kind3", int((sirius_p.mat as ShaderMaterial).get_shader_parameter("kind")) == 3)
	sirius_p.sphere.free()

	var cooked := G.paint({ "name": "Proxima b", "color": Color(0.62, 0.46, 0.40), "radius": 3.2 }, 3.2)
	failed += _check("cook_shader", cooked.mat is ShaderMaterial)
	if cooked.mat is ShaderMaterial:
		var cm := cooked.mat as ShaderMaterial
		failed += _check("cook_no_map", float(cm.get_shader_parameter("has_albedo")) < 0.5)
		failed += _check("cook_has_land", float(cm.get_shader_parameter("land_amount")) > 0.2)
		G.apply_view(cm, Vector3(0, 1, 0), 0.5)
		failed += _check("apply_view_detail", is_equal_approx(float(cm.get_shader_parameter("detail")), 0.5))
	cooked.sphere.free()

	var sh := FileAccess.get_file_as_string("res://shaders/planet_cook.gdshader")
	failed += _check("fills_map_voids", sh.find("pacman") >= 0 or sh.find("unmapped limbs") >= 0)
	var gan := G.recipe_for({ "name": "Ganymede" })
	failed += _check("ganymede_grid_noted", str(gan.get("notes", "")).contains("grid"))
	var doc := FileAccess.get_file_as_string("res://PLANET_GENERATOR.md")
	failed += _check("cook_doc", doc.find("Pacman") >= 0)
	failed += _check("cook_log_spec", doc.find("Cook    ") >= 0)
	var hud_src := FileAccess.get_file_as_string("res://scripts/ui/hud.gd")
	failed += _check("hud_cook_line", hud_src.find("Cook    ") >= 0)
	failed += _check("hud_look_line", hud_src.find("Look    ") >= 0)
	var patch_src := FileAccess.get_file_as_string("res://scripts/world/surface_patch.gd")
	failed += _check("trees_unshaded", patch_src.find("SHADING_MODE_UNSHADED") >= 0)

	# 100 km AIR is EZ bird-eye: the cook globe, not a 36 km black stamp.
	# The ceiling is per-world now (band_ceiling_km), so it arrives as an argument.
	# Earth's is 16.16 km; the EZ at 100 km and the air at 50 km stay outside it.
	var e_ceil: float = G.band_ceiling_km(G.terrain_sampler(G.recipe_for({"name": "Earth"})))
	failed += _check("no_stamp_at_earth_ez", not G.ground_stamp_ok(100.0, 0.02, e_ceil))
	failed += _check("no_stamp_in_air", not G.ground_stamp_ok(50.0, 0.02, e_ceil))
	failed += _check("ez_globe_no_hills", G.close_detail(100.0) < 0.05)
	failed += _check("skin_hills", G.close_detail(1.5) > 0.9)

	if failed == 0:
		print("planet_generator: OK")
		quit(0)
	else:
		print("planet_generator: FAIL %d" % failed)
		quit(1)


func _check(name: String, ok: bool) -> int:
	if not ok:
		print("planet_generator: FAIL %s" % name)
		return 1
	return 0
