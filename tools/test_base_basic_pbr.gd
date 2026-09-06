extends Node3D

const ShipScript := preload("res://scripts/flight/ship.gd")
const MeshStyler := preload("res://scripts/flight/ship_mesh.gd")
var failures := 0

func _ready() -> void:
	var ship := ShipScript.new()
	add_child(ship)
	ship.swap_ship(2)
	_check("third_slot", ship.current_index() == 2 and ship.ship_name_at(2) == "Base Basic PBR")
	var model: Node3D = ship.get("_mesh_root").get_child(0)
	var engines := 0
	var hulls := 0
	for mi in MeshStyler.gather_mesh_instances(model):
		if not String(mi.name).begins_with("root_"):
			continue
		var material := mi.get_active_material(0)
		if String(mi.name) in ["root_1", "root_3"]:
			engines += 1
			_check("booster_shader", material is BaseMaterial3D and material.albedo_texture != null and material.next_pass is ShaderMaterial and material.next_pass.shader == MeshStyler.CRUISER_PROPULSION_SHADER)
		else:
			hulls += 1
			_check("pbr_preserved", material is BaseMaterial3D and material.albedo_texture != null and material.normal_texture != null and material.emission_enabled and material.emission_energy_multiplier > 0.0)
	_check("two_boosters", engines == 2)
	_check("four_pbr_hulls", hulls == 4)
	var rig := model.get_node("BaseBasicAuthoredBoosterPlumes")
	for plume in rig.get_children():
		var nozzle: MeshInstance3D = model.get_node("ROOT/root_1" if String(plume.name).ends_with("1") else "ROOT/root_3")
		var rear := nozzle.get_aabb().position.z
		var base_z: float = plume.position.z + plume.mesh.height * 0.5
		_check("exhaust_fits_outlet", plume.mesh.bottom_radius <= 0.083 and plume.mesh.bottom_radius >= 0.073)
		_check("exhaust_width_locked", plume.material_override.get_shader_parameter("lock_nozzle_width") == true)
		_check("exhaust_overlaps_outlet", base_z > rear and base_z < rear + 0.025)
	_check("four_torch_layers", ship.get("_torch_materials").size() == 4)
	var driven: Array = ship.get("_authored_propulsion")
	_check("driven_materials", driven.size() >= 6)
	if not driven.is_empty():
		ship.call("_update_authored_propulsion", 0.0, 1.0)
		var idle: float = driven[0].get_shader_parameter("power")
		ship.call("_update_authored_propulsion", 1.0, 1.0)
		_check("throttle_response", float(driven[0].get_shader_parameter("power")) > idle)
	var box := MeshStyler.combined_aabb(ship.get("_mesh_root"))
	_check("fitted_model", box.size.is_finite() and box.size.x > 0.0)
	ship.swap_ship(0)
	ship.swap_ship(2)
	_check("swap_back", ship.get("_torch_materials").size() == 4)
	print("base_basic_pbr: ", "OK" if failures == 0 else "FAIL %d" % failures)
	ship.queue_free()
	await get_tree().process_frame
	get_tree().quit(0 if failures == 0 else 1)

func _check(label: String, condition: bool) -> void:
	if not condition:
		failures += 1
		push_error("base_basic_pbr: " + label)
