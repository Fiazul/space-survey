extends Node3D

const ShipScript := preload("res://scripts/flight/ship.gd")
const Styler := preload("res://scripts/flight/ship_mesh.gd")
const WEDGE_HULL := preload("res://shaders/wedge_hull.gdshader")
var failures := 0

func _ready() -> void:
	var ship := ShipScript.new()
	add_child(ship)
	var names := ["Class II Galactic Cruiser", "Snarkrans Starship", "Base Basic PBR", "Vanguard", "Selene"]
	_check("playable_roster", ship.ship_count() == names.size())
	for i in names.size():
		_check("slot_%d" % (i + 1), ship.ship_name_at(i) == names[i])
		ship.swap_ship(i)
		var model: Node3D = ship.get("_mesh_root").get_child(0)
		_check("model_loaded_%d" % i, Styler.combined_aabb(model).size.length() > 0.0)
		if i == 1:
			for mi in Styler.gather_mesh_instances(model):
				if mi.mesh is not ArrayMesh:
					continue
				for si in mi.mesh.get_surface_count():
					var imported := mi.mesh.surface_get_material(si)
					if imported == null or not imported.resource_name.begins_with("booster_"):
						continue
					var active := mi.get_active_material(si) as BaseMaterial3D
					_check("engine_housing_remains_opaque", active != null and active.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED)
					_check("engine_glow_is_rear_only", active != null and active.next_pass is ShaderMaterial and active.next_pass.get_shader_parameter("rear_only") == true)
		if i == 3:
			var hull := model as MeshInstance3D
			_check("vanguard_eight_surfaces", hull != null and hull.mesh.get_surface_count() == 8)
			for si in hull.mesh.get_surface_count():
				var material := hull.get_active_material(si) as BaseMaterial3D
				_check("authored_albedo_preserved", material != null and material.albedo_texture == Styler.VANGUARD_DIFFUSE)
				_check("black_emissive_texels_stay_dark", material != null and material.emission_operator == BaseMaterial3D.EMISSION_OP_MULTIPLY)
			_check("single_vanguard_outlet", Styler.VANGUARD_BOOSTER_SOCKETS.size() == 1 and ship.get("_torch_materials").size() == 2)
	ship.swap_ship(2)
	_check("third_ship_survives_swaps", ship.get("_torch_materials").size() == 4)
	# Ships 3, 4 and 5 carry supplied PBR maps or a procedural hull shader, so they take
	# the hangar swatch inside their own styler instead of through color_authored_ship.
	# Two things have to hold for every one of them: the pick actually reaches the hull,
	# and it reaches NOTHING the propulsion owns.
	for idx in [2, 3, 4]:
		var paints := []
		var boosters := []
		for key in ["burgundy", "emerald"]:
			ship.swap_ship(idx)
			ship.set_ship_color("body", key)
			paints.append(_hull_paints(ship.get("_mesh_root").get_child(0)))
			boosters.append(_propulsion_signature(ship.get("_authored_propulsion")))
		_check("hull_takes_the_pick_%d" % (idx + 1),
			paints[0].size() > 0 and paints[0] != paints[1])
		_check("boosters_ignore_the_pick_%d" % (idx + 1),
			boosters[0].size() > 0 and boosters[0] == boosters[1])
	ship.queue_free()
	await get_tree().process_frame
	print("ship_roster: ", "OK" if failures == 0 else "FAIL %d" % failures)
	get_tree().quit(0 if failures == 0 else 1)

# Every hull colour the styler actually wrote: the albedo _apply_authored_hull_tint
# modulated over the supplied maps, and Selene's procedural hull_tint.
func _hull_paints(model: Node3D) -> Array:
	var out := []
	for mi in Styler.gather_mesh_instances(model):
		if mi.mesh == null:
			continue
		for si in mi.mesh.get_surface_count():
			var material := mi.get_active_material(si)
			if material is ShaderMaterial and material.shader == WEDGE_HULL:
				out.append(material.get_shader_parameter("hull_tint"))
			elif material is BaseMaterial3D:
				out.append((material as BaseMaterial3D).albedo_color)
	return out


# Every uniform on every driven propulsion material, so a paint pass that touched one
# by any route - plasma colour, gain, nozzle shape - shows up as a changed signature.
func _propulsion_signature(driven: Array) -> Array:
	var out := []
	for material in driven:
		var shader_material := material as ShaderMaterial
		var row := [shader_material.shader.resource_path]
		for uniform in RenderingServer.get_shader_parameter_list(shader_material.shader.get_rid()):
			row.append("%s=%s" % [uniform.name, shader_material.get_shader_parameter(uniform.name)])
		out.append(",".join(PackedStringArray(row)))
	return out


func _check(label: String, condition: bool) -> void:
	if not condition:
		failures += 1
		push_error("ship_roster: " + label)
