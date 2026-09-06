extends Node3D

const ShipScript := preload("res://scripts/flight/ship.gd")
const Design := preload("res://scripts/flight/wedge_fighter.gd")
var failures := 0

func _ready() -> void:
	var ship := ShipScript.new()
	add_child(ship)
	ship.swap_ship(4)
	_check("selected_fifth_ship", ship.current_index() == 4 and ship.ship_name_at(4) == "Selene")
	var models: Node3D = ship.get("_mesh_root")
	var model := models.get_child(0) as Node3D
	_check("design_details", model.has_node("InterceptorDetails"))
	_check("ventral_details", model.has_node("InterceptorDetails/VentralDetails"))
	var driven: Array = ship.get("_authored_propulsion")
	_check("six_driven_engine_materials", driven.size() == 6)
	var engines := 0
	var exhausts := 0
	for mesh in Design._meshes(model):
		if String(mesh.name).begins_with("Engine"):
			engines += 1
			_check("authored_engine_emission", (mesh.get_active_material(1) as ShaderMaterial).shader == Design.NOZZLE)
		if String(mesh.name).begins_with("Exhaust"):
			exhausts += 1
			_check("authored_exhaust_shader", (mesh.get_active_material(0) as ShaderMaterial).shader == Design.EXHAUST)
			_check("exhaust_excluded_from_hull_fit", mesh.get_meta("ship_bounds_exclude", false))
			_check("exhaust_seated", absf(mesh.position.z + 3.62475) < 0.0001)
	_check("two_authored_engines", engines == 2)
	_check("two_authored_exhausts", exhausts == 2)
	ship.call("_update_authored_propulsion", 0.0, 1.0)
	var idle: float = driven[0].get_shader_parameter("power")
	ship.call("_update_authored_propulsion", 1.0, 1.0)
	_check("throttle_increases_emission", float(driven[0].get_shader_parameter("power")) > idle)
	for material in driven:
		_check("engines_share_throttle", is_equal_approx(float(material.get_shader_parameter("power")), float(driven[0].get_shader_parameter("power"))))
	ship.swap_ship(0)
	ship.swap_ship(4)
	model = models.get_child(models.get_child_count() - 1) as Node3D
	_check("repeated_swap_keeps_design", model.has_node("InterceptorDetails"))
	print("wedge_fighter: ", "OK" if failures == 0 else "FAIL %d" % failures)
	ship.queue_free()
	await get_tree().process_frame
	get_tree().quit(0 if failures == 0 else 1)

func _check(label: String, condition: bool) -> void:
	if not condition:
		failures += 1
		push_error("wedge_fighter: " + label)
