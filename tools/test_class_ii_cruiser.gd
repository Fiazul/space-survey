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
	# This used to assert the literal "128.0" was in the shader, which pinned the exact
	# constant that made every engine bell a flat clipped white plate. Assert the SHAPE
	# instead: the energy must rise with throttle, and its top must stay inside the
	# range where FILMIC + glow_hdr_threshold 1.0 still resolve a core rather than a
	# featureless blob. Anything in the hundreds is what this test now exists to catch.
	var ramp := RegEx.new()
	ramp.compile("mix\\(([0-9.]+), *([0-9.]+), *(?:pow\\()?power")
	var hit: RegExMatch = ramp.search(drive.shader.code) if drive != null else null
	var idle_energy := float(hit.get_string(1)) if hit != null else -1.0
	var full_energy := float(hit.get_string(2)) if hit != null else -1.0
	var gain := float(drive.get_shader_parameter("brightness")) if drive != null else 0.0
	print("class_ii_cruiser: propulsion energy %.2f..%.2f x brightness %.2f = %.1f..%.1f"
		% [idle_energy, full_energy, gain, idle_energy * gain, full_energy * gain])
	failed += _check("propulsion_energy_ramps_with_throttle",
		hit != null and idle_energy > 0.0 and full_energy > idle_energy)
	failed += _check("propulsion_hdr_is_on_albedo_not_emission",
		drive != null and drive.shader.code.contains("ALBEDO = white_core * energy")
		and drive.shader.code.contains("EMISSION = vec3(0.0)"))
	failed += _check("propulsion_peak_stays_off_the_slab", full_energy * gain <= 1.5)
	failed += _check("propulsion_temperature_ramp", drive != null \
		and drive.shader.code.contains("cool_color") \
		and drive.shader.code.contains("temperature"))
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
				and float(torch_mat.get_shader_parameter("plume_length")) > 0.0 \
				and float(torch_mat.get_shader_parameter("depth_fade")) > 0.0
	failed += _check("tapered_torch_geometry", torch_meshes_ok)
	failed += _check("open_plasma_cones", open_cones)
	failed += _check("torch_hdr_edge_fade", torch_shaders_ok)

	# A mirrored housing must occlude its emitter on both sides, including after
	# hangar customization duplicates the materials.
	MeshStyler.color_authored_ship(model, Color(0.42, 0.60, 0.95), "metal")
	for si in [3, 4]:
		var housing := model.get_active_material(si) as BaseMaterial3D
		failed += _check("mirrored_housing_%d_stays_opaque" % si,
			housing != null and housing.cull_mode == BaseMaterial3D.CULL_DISABLED
			and housing.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED)
	failed += _check("paired_emitter_flow", drive.get_shader_parameter("mirror_flow") == true)
	for i in 3:
		for layer in ["Fog", "Core"]:
			var left := plume_root.get_node("Booster%s%02d" % [layer, i + 1]) as MeshInstance3D
			var right := plume_root.get_node("Booster%s%02d" % [layer, i + 4]) as MeshInstance3D
			var lm := left.mesh as CylinderMesh
			var rm := right.mesh as CylinderMesh
			failed += _check("paired_%s_%d_dimensions" % [layer, i],
				is_equal_approx(lm.height, rm.height)
				and is_equal_approx(lm.bottom_radius, rm.bottom_radius)
				and is_equal_approx(lm.top_radius, rm.top_radius))
			var left_mat := left.material_override as ShaderMaterial
			var right_mat := right.material_override as ShaderMaterial
			failed += _check("paired_%s_%d_brightness" % [layer, i],
				left_mat.get_shader_parameter("brightness") == right_mat.get_shader_parameter("brightness"))

	# Unshaded exhaust must put its radiance in ALBEDO. Brightness and plume
	# separation are checked with render_thruster.tscn at cruise/boost and chase;
	# a source-text energy ceiling cannot measure the composited image.
	var torch_code := MeshStyler.CRUISER_TORCH_SHADER.code
	failed += _check("torch_hdr_is_on_albedo_not_emission",
		torch_code.contains("ALBEDO = torch_color * energy")
		and torch_code.contains("EMISSION = vec3(0.0)"))

	# The standalone test runner does not initialize project autoload identifiers
	# before compiling ship.gd, so check registry wiring as source and exercise the
	# actual Ship node through the normal project-start smoke test.
	var ship_source := FileAccess.get_file_as_string("res://scripts/flight/ship.gd")
	failed += _check("default_registry_entry", ship_source.find("{ \"name\": \"Class II Galactic Cruiser\"") >= 0)
	failed += _check("five_ship_roster", ship_source.count("{ \"name\":") == 5)
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
