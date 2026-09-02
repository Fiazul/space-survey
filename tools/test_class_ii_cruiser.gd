extends SceneTree
# Headless check for the default Class II cruiser asset and its dedicated surfaces.
# Run: godot --headless --path . --script res://tools/test_class_ii_cruiser.gd

const MeshStyler := preload("res://scripts/flight/ship_mesh.gd")
const MODEL_PATH := "res://assets/class_ii_galactic_cruiser/Class II Gallactic Cruiser.obj"


func _initialize() -> void:
	var failed := 0
	var mesh := load(MODEL_PATH) as Mesh
	failed += _check("model_imported", mesh != null)
	if mesh == null:
		quit(1)
		return
	failed += _check("five_authored_surfaces", mesh.get_surface_count() == 5)
	var authored_materials := 0
	for si in mesh.get_surface_count():
		if mesh.surface_get_material(si) != null:
			authored_materials += 1
	failed += _check("five_authored_materials", authored_materials == 5)

	var model := MeshInstance3D.new()
	model.mesh = mesh
	var propulsion := MeshStyler.style_class_ii_cruiser(model)
	failed += _check("one_propulsion_surface", propulsion.size() == 1)
	failed += _check("cockpit_glass", model.get_surface_override_material(0) is StandardMaterial3D)
	failed += _check("a1_led_shader", model.get_surface_override_material(1) is ShaderMaterial)
	failed += _check("propulsion_shader", model.get_surface_override_material(2) is ShaderMaterial)
	failed += _check("textured_hull", model.get_surface_override_material(3) is StandardMaterial3D)
	failed += _check("colored_engine_cover", model.get_surface_override_material(4) is StandardMaterial3D)
	failed += _check("legacy_shadow_mesh_disabled", model.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
	failed += _check("legacy_shadow_mesh_removed", model.mesh is ArrayMesh and (model.mesh as ArrayMesh).shadow_mesh == null)
	var led := model.get_surface_override_material(1) as ShaderMaterial
	var drive := model.get_surface_override_material(2) as ShaderMaterial
	failed += _check("led_mask_bound", led != null and led.get_shader_parameter("led_mask") != null)
	failed += _check("propulsion_hdr_hot", drive != null and drive.shader.code.contains("128.0"))
	failed += _check("propulsion_never_angle_invisible", drive != null \
		and drive.shader.code.contains("mix(0.58, 1.0, edge_softness)"))
	failed += _check("propulsion_ultimate_white", drive != null \
		and drive.get_shader_parameter("plasma_color") == Color.WHITE \
		and float(drive.get_shader_parameter("brightness")) == 4.0)

	var plume_materials := MeshStyler.add_class_ii_booster_plumes(model)
	failed += _check("six_authored_booster_sockets", MeshStyler.CLASS_II_BOOSTER_SOCKETS.size() == 6)
	failed += _check("two_layers_per_socket", plume_materials.size() == 12)
	var plume_root := model.get_node_or_null("ClassIIAuthoredBoosterPlumes") as Node3D
	failed += _check("booster_plume_root", plume_root != null)
	failed += _check("twelve_booster_meshes", plume_root != null and plume_root.get_child_count() == 12)
	var torch_meshes_ok := plume_root != null
	var torch_shaders_ok := true
	var open_cones := true
	if plume_root != null:
		for child in plume_root.get_children():
			torch_meshes_ok = torch_meshes_ok and child is MeshInstance3D \
				and (child as MeshInstance3D).mesh is CylinderMesh
			if child is MeshInstance3D and (child as MeshInstance3D).mesh is CylinderMesh:
				var cone := (child as MeshInstance3D).mesh as CylinderMesh
				open_cones = open_cones and not cone.cap_bottom and not cone.cap_top
			var torch_mat := (child as MeshInstance3D).material_override as ShaderMaterial
			torch_shaders_ok = torch_shaders_ok and torch_mat != null \
				and torch_mat.shader == MeshStyler.CRUISER_TORCH_SHADER \
				and torch_mat.shader.code.contains("1920.0") \
				and torch_mat.shader.code.contains("tip_fade") \
				and torch_mat.shader.code.contains("wispy") \
				and torch_mat.shader.code.contains("billow") \
				and torch_mat.shader.code.contains("VERTEX.x")
	failed += _check("tapered_torch_geometry", torch_meshes_ok)
	failed += _check("open_plasma_cones", open_cones)
	failed += _check("torch_hdr_edge_fade", torch_shaders_ok)
	failed += _check("torch_video_flow", torch_shaders_ok)

	# The standalone test runner does not initialize project autoload identifiers
	# before compiling ship.gd, so check registry wiring as source and exercise the
	# actual Ship node through the normal project-start smoke test.
	var ship_source := FileAccess.get_file_as_string("res://scripts/flight/ship.gd")
	failed += _check("default_registry_entry", ship_source.find("{ \"name\": \"Class II Galactic Cruiser\"") >= 0)
	failed += _check("four_ship_roster", ship_source.count("{ \"name\":") == 4)
	failed += _check("authored_propulsion_hook", ship_source.find("_authored_propulsion = ShipMesh.style_class_ii_cruiser(model)") >= 0)
	failed += _check("authored_plume_hook", ship_source.find("ShipMesh.add_class_ii_booster_plumes(model)") >= 0)
	failed += _check("no_procedural_boosters", not ship_source.contains("_build_boosters") and not ship_source.contains("BOOSTER_LAYOUTS"))
	propulsion.append_array(plume_materials)
	propulsion.clear()
	for si in mesh.get_surface_count():
		model.set_surface_override_material(si, null)
	model.mesh = null
	model.free()

	if failed == 0:
		print("class_ii_cruiser: OK")
		quit(0)
	else:
		print("class_ii_cruiser: FAIL %d" % failed)
		quit(1)


func _check(name: String, ok: bool) -> int:
	if not ok:
		print("class_ii_cruiser: FAIL %s" % name)
		return 1
	return 0
