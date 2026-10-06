extends Node3D
# Scene contract for the seven modular hulls: roster order, per-hull socket-driven
# rigs (plumes, pads, weapons, belly jets, RCS), stat escalation, the tier unlock gate
# and the hangar rows that mirror it.

const ShipScript := preload("res://scripts/flight/ship.gd")
const HudScript := preload("res://scripts/ui/hud.gd")
const ROSTER := [
	{"name": "Class II Galactic Cruiser", "metres": 122.6667, "boosters": 6},
	{"name": "Kestrel", "metres": 70.0, "boosters": 2, "rcs": 4, "weapons": 2, "pads": 3, "landjets": 4},
	{"name": "Swift", "metres": 80.0, "boosters": 2, "rcs": 6, "weapons": 2, "pads": 4, "landjets": 4},
	{"name": "Harrier", "metres": 94.5, "boosters": 2, "rcs": 6, "weapons": 4, "pads": 4, "landjets": 6},
	{"name": "Osprey", "metres": 120.0, "boosters": 3, "rcs": 8, "weapons": 4, "pads": 4, "landjets": 6},
	{"name": "Condor", "metres": 150.0, "boosters": 4, "rcs": 8, "weapons": 6, "pads": 6, "landjets": 8},
	{"name": "Albatross", "metres": 200.0, "boosters": 4, "rcs": 8, "weapons": 6, "pads": 6, "landjets": 8},
	{"name": "Sovereign", "metres": 240.0, "boosters": 4, "rcs": 8, "weapons": 8, "pads": 6, "landjets": 8},
]
var failures := 0

func _ready() -> void:
	var saved_visited: Dictionary = GameState.visited.duplicate()
	GameState.visited = {SystemDB.SOL: true}
	var ship := ShipScript.new()
	add_child(ship)
	_check("playable_roster", ship.ship_count() == ROSTER.size())

	_check("tier_1_always_unlocked", GameState.ship_unlocked(1) and ship.ship_lock_text(0) == "")
	var cruiser_systems := ship.systems
	ship.set_weapon_set("mk2")
	ship.set_pad_set("mk2")
	_check("cruiser_module_toggles_do_not_rebuild", ship.systems == cruiser_systems and not ship.systems.modular)
	ship.set_weapon_set("mk1")
	ship.set_pad_set("mk1")
	for tier in range(2, ROSTER.size() + 1):
		_check("tier_%d_locked_on_fresh_profile" % tier, not GameState.ship_unlocked(tier))
	_check("sol_does_not_count", GameState.systems_reached() == 0)
	_check("locked_swap_refused", not ship.swap_ship(1) and ship.current_index() == 0)
	_check("lock_text_names_threshold", ship.ship_lock_text(1) == "Locked: reach 1 systems" \
		and ship.ship_lock_text(6) == "Locked: reach 12 systems" \
		and ship.ship_lock_text(7) == "Locked: reach 16 systems")
	GameState.visited["alpha_centauri"] = true
	_check("one_system_unlocks_tier_2", GameState.ship_unlocked(2) and not GameState.ship_unlocked(3))
	_check("unlocked_swap_allowed", ship.swap_ship(1) and ship.current_index() == 1)
	_check("higher_tier_still_refused", not ship.swap_ship(3) and ship.current_index() == 1)
	ship.swap_ship(0)

	for i in 14:
		GameState.visited["test_system_%d" % i] = true
	_check("tier_8_locked_before_threshold", not GameState.ship_unlocked(8))
	GameState.visited["test_system_14"] = true
	_check("tier_8_unlocks_at_16_systems", GameState.ship_unlocked(8))
	var previous := {}
	for i in ROSTER.size():
		var spec: Dictionary = ROSTER[i]
		_check("slot_%d_name" % (i + 1), ship.ship_name_at(i) == spec.name)
		if i > 0:
			_check("swap_%d" % i, ship.swap_ship(i))
		var info: Dictionary = ShipScript.SHIP_MODELS[i]
		var model: Node3D = ship.get("_mesh_root").get_child(0)
		_check("model_loaded_%d" % i, ShipMesh.combined_aabb(model).size.length() > 0.0)
		if i == 0:
			_check("cruiser_is_non_modular", not info.get("modular", false) and not ship.current_is_modular())
			_check("cruiser_has_authored_torches", ship.get("_torch_materials").size() == 2 * int(spec.boosters))
			_check("cruiser_has_no_rcs_puffs", ship.get("_rcs_puffs").is_empty())
			_check("cruiser_has_no_module_glbs", not ship.systems.modular)
			continue
		_check("modular_%d" % i, info.get("modular", false) and ship.current_is_modular())
		var hull_km: float = ship.get("_hull_km")
		_check("fleet_scale_%d" % i, absf(hull_km * 1000.0 - float(spec.metres)) < float(spec.metres) * .02)
		var found := ModularHull.sockets(model)
		for kind in ["weapon", "booster", "rcs", "pad", "landjet"]:
			var want: int = spec[kind + "s"] if spec.has(kind + "s") else spec[kind]
			_check("socket_%s_%d" % [kind, i], (found[kind] as Array).size() == want)
		_check("two_cones_per_booster_%d" % i, ship.get("_torch_materials").size() == 2 * int(spec.boosters))
		_check("haze_per_booster_%d" % i, ShipMesh.collect_haze_materials(model).size() == int(spec.boosters))
		_check("rcs_puffs_%d" % i, ship.get("_rcs_puffs").size() == int(spec.rcs))
		var puffs: Array = ship.get("_rcs_puffs")
		ModularHull.drive_rcs(puffs, Vector3.RIGHT, false, .016)
		var lit := puffs.filter(func(p): return p.node.visible)
		_check("strafe_fires_opposing_rcs_%d" % i, not lit.is_empty() and lit.size() < puffs.size() \
			and lit.all(func(p): return p.axis.x < -.5))
		ModularHull.drive_rcs(puffs, Vector3.ZERO, false, 1.0)
		_check("rcs_puffs_are_short_lived_%d" % i, puffs.all(func(p): return not p.node.visible))
		ModularHull.drive_rcs(puffs, Vector3.ZERO, true, .016)
		_check("brake_at_rest_fires_nothing_%d" % i, puffs.all(func(p): return not p.node.visible))
		var rig: ShipSystems = ship.systems
		_check("pads_%d" % i, rig.legs.size() == int(spec.pads))
		_check("weapons_%d" % i, rig.mounts.size() == int(spec.weapons))
		_check("landjets_%d" % i, rig.support.jets.size() == int(spec.landjets))
		_check("muzzle_node_%d" % i, rig.muzzle_node(0) != null)
		_check("stowed_gear_has_no_feet_%d" % i, rig.foot_points().is_empty())
		rig.gear_target = true
		rig.step(2.0)
		_check("foot_per_pad_%d" % i, rig.foot_points().size() == int(spec.pads))
		_check("nozzles_throttle_driven_%d" % i, _nozzle_drives(model) == ship.get("_authored_propulsion").filter(
			func(m): return m.shader == ShipMesh.CRUISER_PROPULSION_SHADER).size() and _nozzle_drives(model) > 0)
		if i > 1:
			_check("stats_escalate_%d" % i, int(info.hp) > int(previous.hp) and int(info.dmg) >= int(previous.dmg) \
				and float(info.fire_cd) < float(previous.fire_cd) and float(info.energy_max) > float(previous.energy_max))
			# warp escalation dropped 2026-09-29: per-hull warp is gone with the arcade drive.
		previous = info
		rig.gear_target = false
		rig.step(2.0)

	# Tint reaches Hull_Paint and nothing the propulsion owns.
	var paints := []
	var boosters := []
	for key in ["burgundy", "emerald"]:
		ship.set_ship_color("body", key)
		var model: Node3D = ship.get("_mesh_root").get_child(0)
		paints.append(_paint_colors(model))
		boosters.append(_propulsion_signature(ship.get("_authored_propulsion")))
	_check("hull_takes_the_pick", paints[0].size() > 0 and paints[0] != paints[1] \
		and paints[1][0].is_equal_approx(Ship.color_from_key("emerald")))
	_check("boosters_ignore_the_pick", boosters[0].size() > 0 and boosters[0] == boosters[1])
	ship.set_ship_color("body", "#c0331f")
	_check("manual_hex_accepted", ship.current_body_color() == "#c0331f")

	var ballistic: float = ShipScript.NEWTON_BALLISTIC
	_check("newton_ballistic_finite", is_finite(ballistic))
	_check("newton_ballistic_positive", ballistic > 0.0)
	_check("newton_ballistic_matches_live_derivation", is_equal_approx(ballistic,
		FlightMode.air_ballistic(ShipScript.NEWTON_THRUST, ShipScript.BOOST_MULT, Ephemeris.RHO0)))

	var hud := HudScript.new()
	add_child(hud)
	hud.ship = ship
	ship.swap_ship(2)
	var hangar_names := PackedStringArray()
	for i in ship.ship_count():
		hangar_names.append(ship.ship_name_at(i))
	ship.set_ship_color("body", "burgundy")
	hud.set_hangar(true, hangar_names, 2, "Test Dock")
	_check("hangar_offers_module_sets", _labels(hud).has("WEAPONS") and _labels(hud).has("LANDING PADS"))
	var picker: ColorPickerButton = hud.get("_color_picker")
	_check("hangar_has_picker", picker != null and is_instance_valid(picker))
	if picker != null:
		var picker_id := picker.get_instance_id()
		ship.set_ship_color("body", "#1f4cc0")
		hud.set_hangar(true, hangar_names, 2, "Test Dock")
		var after: ColorPickerButton = hud.get("_color_picker")
		_check("picker_survives_color_only_refresh",
			after != null and after.get_instance_id() == picker_id)
		if after != null:
			var popup := after.get_popup()
			if popup != null:
				popup.popup()
			ship.set_ship_color("body", "#33c07a")
			hud.set_hangar(true, hangar_names, 2, "Test Dock")
			var still: ColorPickerButton = hud.get("_color_picker")
			_check("picker_survives_refresh_while_popup_open",
				still != null and still.get_instance_id() == picker_id)
			_check("picker_popup_still_open",
				still != null and still.get_popup() != null and still.get_popup().visible)
	GameState.visited = {SystemDB.SOL: true, "alpha_centauri": true}
	hud.set_hangar(true, hangar_names, 2, "Test Dock")
	await get_tree().process_frame
	var labels := _labels(hud)
	_check("hangar_shows_lock", labels.has("Locked: reach 12 systems") and labels.has("Locked: reach 4 systems") \
		and not labels.has("Locked: reach 1 systems"))
	hud.queue_free()

	GameState.visited = saved_visited
	ship.queue_free()
	await get_tree().process_frame
	print("ship_roster: ", "OK" if failures == 0 else "FAIL %d" % failures)
	get_tree().quit(0 if failures == 0 else 1)


func _labels(hud: Node) -> PackedStringArray:
	var out := PackedStringArray()
	var stack: Array[Node] = [hud.get("_hangar_rows")]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node.is_queued_for_deletion():
			continue
		if node is Label:
			out.append((node as Label).text)
		stack.append_array(node.get_children())
	return out


func _nozzle_drives(model: Node3D) -> int:
	var count := 0
	for mi in ShipMesh.gather_mesh_instances(model):
		for si in mi.get_surface_override_material_count():
			var material := mi.get_surface_override_material(si)
			if material != null and material.resource_name == "Nozzle_Emit" and material.next_pass is ShaderMaterial \
					and (material.next_pass as ShaderMaterial).shader == ShipMesh.CRUISER_PROPULSION_SHADER:
				count += 1
	return count


func _paint_colors(model: Node3D) -> Array:
	var out := []
	for mi in ShipMesh.gather_mesh_instances(model):
		for si in mi.get_surface_override_material_count():
			var material := mi.get_surface_override_material(si)
			if material is StandardMaterial3D and material.resource_name == "Hull_Paint":
				out.append((material as StandardMaterial3D).albedo_color)
	return out


func _propulsion_signature(driven: Array) -> Array:
	var out := []
	for material in driven:
		var shader_material := material as ShaderMaterial
		if shader_material == null:
			continue
		var row := [shader_material.shader.resource_path]
		for uniform in RenderingServer.get_shader_parameter_list(shader_material.shader.get_rid()):
			row.append("%s=%s" % [uniform.name, shader_material.get_shader_parameter(uniform.name)])
		out.append(",".join(PackedStringArray(row)))
	return out


func _check(label: String, condition: bool) -> void:
	if not condition:
		failures += 1
		push_error("ship_roster: " + label)
