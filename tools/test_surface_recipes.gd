extends SceneTree
const G := preload("res://scripts/world/planet_generator.gd")
var failures := 0

func _initialize() -> void:
	# Removing the recipe binding must fail even if a shader has useful defaults.
	for row in [["Earth", 1.0, 0.0], ["Moon", 0.0, 0.0], ["Io", 0.0, 1.0], ["Europa", 0.0, 0.0]]:
		var mat := G.terrain_material(G.recipe_for({"name": row[0]}), {})
		check("%s_liquid_selection" % row[0], mat.get_shader_parameter("liquid_amount") == row[1])
		check("%s_lava_selection" % row[0], mat.get_shader_parameter("lava_amount") == row[2])
	var moon := G.terrain_sampler(G.recipe_for({"name": "Moon"}))
	var profile = moon.get("surface")
	check("geology_profile_reaches_sampler", profile is Dictionary)
	if profile is Dictionary:
		var centre: Vector3 = profile.craters[0].direction
		var width: float = profile.craters[0].width
		var rim := centre.rotated(centre.cross(Vector3.UP).normalized(), width)
		check("crater_has_bowl_and_raised_rim", moon.geology_height_m(centre) < -100.0 and moon.geology_height_m(rim) > 20.0)
		check("lunar_crater_is_dry", moon.water01(centre) == 0.0)
		var io := G.terrain_sampler(G.recipe_for({"name": "Io"}))
		var vent: Vector3 = io.surface.volcanoes[0].direction
		var vw: float = io.surface.volcanoes[0].width
		var shoulder := vent.rotated(vent.cross(Vector3.UP).normalized(), vw * 0.25)
		check("volcano_has_caldera", io.geology_height_m(shoulder) > io.geology_height_m(vent) + 100.0)
		check("lava_is_local_to_vents", io.lava01(vent) > 0.5 and io.lava01(-vent) == 0.0)
		check("generated_volcano_is_collidable", io.swept_contact(shoulder * (io.ground_radius_km(shoulder, 1821.6) + 0.1), shoulder * (io.ground_radius_km(shoulder, 1821.6) - 0.01), 1821.6, 0.02))
		var again := G.terrain_sampler(G.recipe_for({"name": "Io"}))
		check("geology_is_repeatable", is_equal_approx(io.height_m(shoulder), again.height_m(shoulder)))
		for body in ["Sun", "Jupiter", "Uranus", "Neptune"]:
			check(body + "_does_not_spawn_ground", not G.has_surface(G.recipe_for({"name": body})))
			var s := G.terrain_sampler(G.recipe_for({"name": body}))
			check(body + "_has_no_ground_features", s.surface.craters.is_empty() and s.surface.volcanoes.is_empty() and s.surface.liquid_amount == 0.0 and s.geology_height_m(Vector3.RIGHT) == 0.0)
	for row in [["Sun", "granulation"], ["Jupiter", "storm_strength"]]:
		var painted := G.paint({"name": row[0]}, 10.0)
		check(str(row[0]) + "_recipe_drives_globe", painted.mat.get_shader_parameter(row[1]) == 1.0)
		painted.sphere.free()
	var ocean := G.terrain_sampler({"name": "Ocean probe", "kind": "rocky", "seed": 13.0, "land_amount": 0.0, "surface": {"liquid_amount": 1.0}})
	check("procedural_ocean_has_level_surface", absf(ocean.height_m(Vector3.RIGHT)) < 0.01 and absf(ocean.height_m(Vector3.UP)) < 0.01)
	var custom := G.recipe_for({"name": "Custom volcano", "kind": "rocky", "surface": {"lava_amount": 1.0, "volcano_count": 4}})
	check("invented_world_accepts_surface_recipe", G.terrain_sampler(custom).surface.volcanoes.size() == 4)
	var moon_s := G.terrain_sampler(G.recipe_for({"name": "Moon"}))
	check("ice_profile_prevents_false_oceans", G.terrain_sampler(G.recipe_for({"name": "Europa"})).water01(Vector3.UP) == 0.0)
	for features in [moon_s.surface.craters, moon_s.surface.volcanoes]:
		for i in features.size():
			for j in range(i + 1, features.size()):
				check("landmark_supports_do_not_overlap", (features[i].direction as Vector3).distance_to(features[j].direction) >= 1.7 * (float(features[i].width) + float(features[j].width)))
	var forced_star := G.terrain_sampler(G.recipe_for({"name": "Sun", "surface": {"volcano_count": 12, "liquid_amount": 1.0}}))
	check("stellar_type_overrides_invalid_solid_features", forced_star.surface.volcanoes.is_empty() and forced_star.surface.liquid_amount == 0.0)
	for i in 100:
		var n := Vector3(sin(i * 2.1), cos(i * 3.1), sin(i * 1.7)).normalized()
		check("terrain_height_within_declared_bound", moon_s.height_m(n) <= moon_s.max_height_km() * 1000.0)
	var patch := preload("res://scripts/world/surface_patch.gd").new()
	patch.call("_ready")
	patch.bind_body(G.recipe_for({"name": "Moon"}), moon_s)
	var props: MultiMeshInstance3D = patch.get("_props")
	var arrays := props.multimesh.mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	check("rock_exterior_is_clockwise", (verts[1] - verts[0]).cross(verts[2] - verts[0]).dot(normals[0]) < 0.0)
	check("rock_side_normal_faces_out", normals[0].x > 0.0)
	var moon_color: Color = arrays[Mesh.ARRAY_COLOR][0]
	patch.bind_body(G.recipe_for({"name": "Mars"}), G.terrain_sampler(G.recipe_for({"name": "Mars"})))
	var mars_color: Color = props.multimesh.mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR][0]
	check("rock_color_follows_body_changes", moon_color != mars_color)
	patch.free()
	print("surface_recipes: ", "OK" if failures == 0 else "FAIL %d" % failures)
	quit(0 if failures == 0 else 1)

func check(label: String, ok: bool) -> void:
	if not ok:
		failures += 1
		push_error("surface_recipes: " + label)
