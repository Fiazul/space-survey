extends SceneTree
# Headless contract: JazOone SpaceShip keeps its textured hull. The five
# Layer_1_Material_0 chunks are vertex splits of the whole ship, not five
# boosters. Only the two authored emissive engine discs get the HDR torch.
# Run: godot --headless --path . --script res://tools/test_jazoone_spaceship.gd

const MeshStyler := preload("res://scripts/flight/ship_mesh.gd")
const MODEL_PATH := "res://assets/jazoone_spaceship/spaceship.glb"


func _initialize() -> void:
	var failed := 0
	var packed := load(MODEL_PATH) as PackedScene
	failed += _check("model_imported", packed != null)
	if packed == null:
		quit(1)
		return

	var model := packed.instantiate() as Node3D
	failed += _check("scene_instanced", model != null)
	if model == null:
		quit(1)
		return

	var meshes := MeshStyler.gather_mesh_instances(model)
	failed += _check("five_layer1_meshes", meshes.size() == 5)
	for i in meshes.size():
		failed += _check("mesh_%d_is_layer1" % i, _mesh_tag(meshes[i]).contains("layer_1"))

	var propulsion := MeshStyler.style_jazoone_spaceship(model)
	failed += _check("five_chunks_styled", propulsion.size() == 5)
	failed += _check("not_the_full_ship_torch",
		MeshStyler.JAZOONE_HULL_BOOSTER_SHADER != MeshStyler.CRUISER_PROPULSION_SHADER)
	for i in meshes.size():
		var mi := meshes[i]
		if mi.mesh == null:
			failed += _check("mesh_%d_has_mesh" % i, false)
			continue
		for si in mi.mesh.get_surface_count():
			var material := mi.get_surface_override_material(si) as ShaderMaterial
			failed += _check("mesh_%d_surface_%d_mixed_shader" % [i, si],
				material != null \
				and material.shader == MeshStyler.JAZOONE_HULL_BOOSTER_SHADER \
				and material.get_shader_parameter("albedo_tex") != null \
				and material.get_shader_parameter("emissive_tex") != null \
				and material.get_shader_parameter("plasma_color") == Color.WHITE \
				and float(material.get_shader_parameter("brightness")) == 4.0)
			if material != null and material.shader != null:
				var code: String = material.shader.code
				failed += _check("hull_albedo_path", code.contains("albedo_tex"))
				# The engine discs are found by the emissive mask alone. This used to
				# assert a pair of booster_uv_* disc centres, but probe_jazoone_sockets
				# showed no vertex UV ever lands inside them, so that gate was dead code
				# that kept the torch branch from ever running.
				failed += _check("engine_discs_from_emissive_mask",
					code.contains("step(0.25, mask)")
					and not code.contains("booster_uv_a"))
				failed += _check("disc_temperature_ramp",
					code.contains("temperature") and code.contains("cool_color"))
				failed += _check("not_additive_whole_hull",
					not code.contains("blend_add"))

	var plume_materials := MeshStyler.add_jazoone_booster_plumes(model)
	failed += _check("two_probed_booster_sockets", MeshStyler.JAZOONE_BOOSTER_SOCKETS.size() == 2)
	failed += _check("two_layers_per_socket", plume_materials.size() == 4)
	var plume_root := model.get_node_or_null("JazOoneAuthoredBoosterPlumes") as Node3D
	failed += _check("booster_plume_root", plume_root != null)
	failed += _check("four_booster_meshes", plume_root != null and plume_root.get_child_count() == 4)
	# JazOone imports with yaw 0, so unlike the other three ships its exhaust must run
	# toward +Z. A sign slip here buries the flame inside the hull.
	var exhaust_behind := plume_root != null
	if plume_root != null:
		for child in plume_root.get_children():
			exhaust_behind = exhaust_behind and child is MeshInstance3D \
				and (child as MeshInstance3D).position.z > 0.0
	failed += _check("exhaust_points_aft", exhaust_behind)

	var ship_source := FileAccess.get_file_as_string("res://scripts/flight/ship.gd")
	failed += _check("roster_entry", ship_source.contains("{ \"name\": \"SpaceShip\""))
	failed += _check("authored_plume_hook",
		ship_source.contains("ShipMesh.add_jazoone_booster_plumes(model)"))
	var spaceship_block := ""
	var roster_at := ship_source.find("{ \"name\": \"SpaceShip\"")
	if roster_at >= 0:
		spaceship_block = ship_source.substr(roster_at, 700)
	failed += _check("spaceship_yaw_zero",
		spaceship_block.contains("\"yaw\": 0.0") and not spaceship_block.contains("\"yaw\": 180.0"))
	failed += _check("authored_propulsion_hook",
		ship_source.contains("_authored_propulsion = ShipMesh.style_jazoone_spaceship(model)"))
	failed += _check("four_ship_roster", ship_source.count("{ \"name\":") == 4)
	failed += _check("no_procedural_boosters", not ship_source.contains("_build_boosters") \
		and not ship_source.contains("BOOSTER_LAYOUTS"))

	var credits := FileAccess.get_file_as_string("res://CREDITS.md")
	failed += _check("sketchfab_credit", credits.contains("JazOone") \
		and credits.contains("https://skfb.ly/oJrVX") \
		and credits.contains("Creative Commons Attribution"))

	propulsion.clear()
	model.free()

	if failed == 0:
		print("jazoone_spaceship: OK")
		quit(0)
	else:
		print("jazoone_spaceship: FAIL %d" % failed)
		quit(1)


func _mesh_tag(mi: MeshInstance3D) -> String:
	var tag := mi.name.to_lower()
	if mi.mesh != null:
		tag += " " + String(mi.mesh.resource_name).to_lower()
	var orig := mi.get_active_material(0) if mi.mesh != null and mi.mesh.get_surface_count() > 0 else null
	if orig != null:
		tag += " " + orig.resource_name.to_lower()
	return tag


func _check(name: String, ok: bool) -> int:
	if not ok:
		print("jazoone_spaceship: FAIL %s" % name)
		return 1
	return 0
