extends SceneTree
# Headless contract: eight authored boosters plus one opaque double-sided hull.
# Run: godot --headless --path . --script res://tools/test_dingo57_starship.gd

const MeshStyler := preload("res://scripts/flight/ship_mesh.gd")
const MODEL_PATH := "res://assets/dingo57_starship/3d-model.obj"
const BOOSTER_GROUPS := ["115", "113", "111", "109", "076", "074", "072", "070"]
# Every remaining source group, including the previously missing bottom chassis
# 053/065/092/104, is merged into one opaque hull_body surface.
const HULL_SURFACE := "hull_body"


func _initialize() -> void:
	var failed := 0
	var mesh := load(MODEL_PATH) as Mesh
	failed += _check("model_imported", mesh != null)
	if mesh == null:
		quit(1)
		return

	failed += _check("godot_safe_surface_count", mesh.get_surface_count() < 256)
	failed += _check("booster_plus_single_hull", mesh.get_surface_count() == 9)
	var imported_indices := 0
	var booster_surfaces := {}
	var booster_surface_count := 0
	var hull_surface := -1
	for si in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(si)
		if arrays[Mesh.ARRAY_INDEX] != null:
			imported_indices += (arrays[Mesh.ARRAY_INDEX] as PackedInt32Array).size()
		var surface_name: String = mesh.surface_get_name(si).to_lower()
		failed += _check("no_glass_bucket_%d" % si,
			not surface_name.contains("translucent") and not surface_name.contains("glass"))
		if surface_name == HULL_SURFACE:
			hull_surface = si
			var hull_mat := mesh.surface_get_material(si)
			failed += _check("hull_import_opaque", hull_mat == null \
				or ((hull_mat is BaseMaterial3D) \
				and (hull_mat as BaseMaterial3D).transparency == BaseMaterial3D.TRANSPARENCY_DISABLED))
		elif surface_name.begins_with("booster_group_"):
			for group in BOOSTER_GROUPS:
				if surface_name == "booster_group_%s" % group:
					if not booster_surfaces.has(group):
						booster_surfaces[group] = []
					(booster_surfaces[group] as Array).append(si)
					booster_surface_count += 1
		else:
			failed += _check("unexpected_surface_%s" % surface_name, false)
	for group in BOOSTER_GROUPS:
		failed += _check("group_%s_preserved" % group, booster_surfaces.has(group))
	failed += _check("hull_body_preserved", hull_surface >= 0)
	failed += _check("complete_source_geometry", imported_indices == 354492)

	var model := MeshInstance3D.new()
	model.mesh = mesh
	var propulsion := MeshStyler.style_dingo57_starship(model)
	failed += _check("eight_booster_surfaces_styled", propulsion.size() == 8 and booster_surface_count == 8)
	for group in BOOSTER_GROUPS:
		for si in booster_surfaces.get(group, []):
			var material := model.get_surface_override_material(si)
			failed += _check("group_%s_torch_shader" % group,
				material is ShaderMaterial \
				and (material as ShaderMaterial).get_shader_parameter("plasma_color") == Color.WHITE \
				and float((material as ShaderMaterial).get_shader_parameter("brightness")) == 4.0)
	var styled_hull: BaseMaterial3D = null
	if hull_surface >= 0:
		styled_hull = model.get_surface_override_material(hull_surface) as BaseMaterial3D
	failed += _check("hull_styled_opaque", styled_hull != null \
		and styled_hull.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED)
	failed += _check("hull_styled_double_sided", styled_hull != null \
		and styled_hull.cull_mode == BaseMaterial3D.CULL_DISABLED)

	for finish in ["metallic", "glassy"]:
		MeshStyler.color_authored_ship(model, Color(0.30, 0.31, 0.34), finish)
		for si in mesh.get_surface_count():
			if mesh.surface_get_name(si).begins_with("booster_group_"):
				continue
			var repaired := model.get_surface_override_material(si) as BaseMaterial3D
			failed += _check("hull_%s_opaque" % finish, repaired != null \
				and repaired.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED \
				and is_equal_approx(repaired.albedo_color.a, 1.0))
			failed += _check("hull_%s_double_sided" % finish, repaired != null \
				and repaired.cull_mode == BaseMaterial3D.CULL_DISABLED)

	failed += _check("eight_authored_booster_sockets", MeshStyler.DINGO57_BOOSTER_SOCKETS.size() == 8)
	var plume_materials := MeshStyler.add_dingo57_booster_plumes(model)
	failed += _check("two_layers_per_dingo_socket", plume_materials.size() == 16)
	var plume_root := model.get_node_or_null("Dingo57AuthoredBoosterPlumes") as Node3D
	failed += _check("dingo_plume_root", plume_root != null)
	failed += _check("sixteen_dingo_plume_meshes", plume_root != null and plume_root.get_child_count() == 16)
	var dingo_torch_ok := plume_root != null
	if plume_root != null:
		for child in plume_root.get_children():
			var torch_mat := (child as MeshInstance3D).material_override as ShaderMaterial if child is MeshInstance3D else null
			dingo_torch_ok = dingo_torch_ok and child is MeshInstance3D \
				and (child as MeshInstance3D).mesh is CylinderMesh \
				and torch_mat != null \
				and torch_mat.shader == MeshStyler.CRUISER_TORCH_SHADER \
				and torch_mat.shader.code.contains("wispy")
	failed += _check("dingo_video_torch_plumes", dingo_torch_ok)
	var ship_source := FileAccess.get_file_as_string("res://scripts/flight/ship.gd")
	failed += _check("authored_plume_hook",
		ship_source.contains("ShipMesh.add_dingo57_booster_plumes(model)"))

	var source := FileAccess.get_file_as_string(MODEL_PATH)
	failed += _check("hull_body_source_mapping",
		source.contains("o hull_body\n") and source.contains("usemtl hull_body"))
	failed += _check("no_translucent_source_objects",
		not source.contains("Translucent_Glass") and not source.contains("outer_chassis_group_"))
	for group in BOOSTER_GROUPS:
		failed += _check("group_%s_source_mapping" % group,
			source.contains("o booster_group_%s\n" % group) \
			and source.contains("usemtl booster_group_%s" % group))

	propulsion.clear()
	for si in model.mesh.get_surface_count():
		model.set_surface_override_material(si, null)
	model.mesh = null
	model.free()

	if failed == 0:
		print("dingo57_starship: OK")
		quit(0)
	else:
		print("dingo57_starship: FAIL %d" % failed)
		quit(1)


func _check(name: String, ok: bool) -> int:
	if not ok:
		print("dingo57_starship: FAIL %s" % name)
		return 1
	return 0
