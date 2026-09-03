extends SceneTree
# Headless contract check for Snarkrans' ship and its four authored booster roles.
# Run: godot --headless --path . --script res://tools/test_snarkrans_starship.gd

const MeshStyler := preload("res://scripts/flight/ship_mesh.gd")
const MODEL_PATH := "res://assets/snarkrans_starship/spaceship.obj"


func _initialize() -> void:
	var failed := 0
	var mesh := load(MODEL_PATH) as Mesh
	failed += _check("model_imported", mesh != null)
	if mesh == null:
		quit(1)
		return
	failed += _check("seventy_seven_object_surfaces", mesh.get_surface_count() == 77)
	var imported_indices := 0
	var tip_surface := -1
	var lower_surface := -1
	var upper_shell_surface := -1
	var lower_shell_surface := -1
	for si in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(si)
		if arrays[Mesh.ARRAY_INDEX] != null:
			imported_indices += (arrays[Mesh.ARRAY_INDEX] as PackedInt32Array).size()
		var mat := mesh.surface_get_material(si)
		var material_name := mat.resource_name if mat != null else ""
		if material_name == "booster_tip":
			tip_surface = si
		elif material_name == "booster_bottom":
			lower_surface = si
		elif material_name == "booster_upper_shell":
			upper_shell_surface = si
		elif material_name == "booster_lower_shell":
			lower_shell_surface = si
		else:
			failed += _check("hull_import_material_%d_untouched" % si, mat == null)
	failed += _check("tip_surface_preserved", tip_surface >= 0)
	failed += _check("lower_surface_preserved", lower_surface >= 0)
	failed += _check("upper_shell_surface_preserved", upper_shell_surface >= 0)
	failed += _check("lower_shell_surface_preserved", lower_shell_surface >= 0)
	failed += _check("complete_source_geometry", imported_indices == 1592973)

	var model := MeshInstance3D.new()
	model.mesh = mesh
	var propulsion := MeshStyler.style_snarkrans_starship(model)
	failed += _check("four_authored_booster_surfaces", propulsion.size() == 4)
	failed += _check("main_hull_untouched", model.get_surface_override_material(0) == null)
	failed += _check("accent_hull_untouched", model.get_surface_override_material(2) == null)
	failed += _check("tip_booster_shader", tip_surface >= 0 and model.get_surface_override_material(tip_surface) is ShaderMaterial)
	failed += _check("lower_boosters_shader", lower_surface >= 0 and model.get_surface_override_material(lower_surface) is ShaderMaterial)
	failed += _check("upper_shell_shader", upper_shell_surface >= 0 and model.get_surface_override_material(upper_shell_surface) is ShaderMaterial)
	failed += _check("lower_shell_shader", lower_shell_surface >= 0 and model.get_surface_override_material(lower_shell_surface) is ShaderMaterial)
	for booster_surface in [tip_surface, lower_surface, upper_shell_surface, lower_shell_surface]:
		var drive := model.get_surface_override_material(booster_surface) as ShaderMaterial
		# `brightness` is no longer a flat 4.0 across the fleet: it is scaled against
		# how much of each hull the additive booster shader covers (see
		# SNARKRANS_BOOSTER_GAIN in ship_mesh.gd and tools/probe_propulsion_area.gd).
		# Snarkrans has the largest emissive area of the four, so it gets the lowest
		# gain; a flat value put a white slab across its mid-hull.
		failed += _check("booster_ultimate_white", drive != null \
			and drive.get_shader_parameter("plasma_color") == Color.WHITE \
			and float(drive.get_shader_parameter("brightness")) == MeshStyler.SNARKRANS_BOOSTER_GAIN)
	failed += _check("legacy_shadow_mesh_removed", model.mesh is ArrayMesh and (model.mesh as ArrayMesh).shadow_mesh == null)

	var plume_materials := MeshStyler.add_snarkrans_booster_plumes(model)
	failed += _check("three_authored_booster_sockets", MeshStyler.SNARKRANS_BOOSTER_SOCKETS.size() == 3)
	failed += _check("fill_fog_core_per_socket", plume_materials.size() == 9)
	var plume_root := model.get_node_or_null("SnarkransAuthoredBoosterPlumes") as Node3D
	failed += _check("booster_plume_root", plume_root != null)
	failed += _check("nine_booster_meshes", plume_root != null and plume_root.get_child_count() == 9)
	var dense_fills := 0
	var fog_layers := 0
	var core_layers := 0
	var booster_meshes_ok := plume_root != null
	if plume_root != null:
		for child in plume_root.get_children():
			booster_meshes_ok = booster_meshes_ok and child is MeshInstance3D \
				and (child as MeshInstance3D).mesh is CylinderMesh
			var child_name := String(child.name)
			if child_name.begins_with("BoosterFill"):
				dense_fills += 1
				var fill_mat := (child as MeshInstance3D).material_override as ShaderMaterial
				booster_meshes_ok = booster_meshes_ok and fill_mat != null \
					and fill_mat.shader == MeshStyler.CRUISER_PROPULSION_SHADER
			elif child_name.begins_with("BoosterFog"):
				fog_layers += 1
			elif child_name.begins_with("BoosterCore"):
				core_layers += 1
	failed += _check("three_dense_fills", dense_fills == 3)
	failed += _check("three_fog_layers", fog_layers == 3)
	failed += _check("three_torch_cores", core_layers == 3)
	failed += _check("booster_geometry_valid", booster_meshes_ok)

	var source := FileAccess.get_file_as_string("res://assets/snarkrans_starship/spaceship.obj")
	failed += _check("tip_object_preserved", source.contains("o big_shapes_01_RetopoGroup1.000\n") and source.contains("usemtl booster_tip"))
	failed += _check("lower_objects_preserved", source.contains("o big_shapes_01_RetopoGroup1.005_big_shapes_01_RetopoGroup1.035\n") and source.contains("usemtl booster_bottom"))
	failed += _check("upper_shell_object_preserved", source.contains("o big_shapes_01_RetopoGroup1.010_big_shapes_01_RetopoGroup1.018\n") and source.contains("usemtl booster_upper_shell"))
	failed += _check("lower_shell_object_preserved", source.contains("o big_shapes_01_RetopoGroup1.001_big_shapes_01_RetopoGroup1.034\n") and source.contains("usemtl booster_lower_shell"))
	var ship_source := FileAccess.get_file_as_string("res://scripts/flight/ship.gd")
	failed += _check("authored_plume_hook", ship_source.contains("ShipMesh.add_snarkrans_booster_plumes(model)"))

	propulsion.append_array(plume_materials)
	propulsion.clear()
	for si in model.mesh.get_surface_count():
		model.set_surface_override_material(si, null)
	model.mesh = null
	model.free()

	if failed == 0:
		print("snarkrans_starship: OK")
		quit(0)
	else:
		print("snarkrans_starship: FAIL %d" % failed)
		quit(1)


func _check(name: String, ok: bool) -> int:
	if not ok:
		print("snarkrans_starship: FAIL %s" % name)
		return 1
	return 0
