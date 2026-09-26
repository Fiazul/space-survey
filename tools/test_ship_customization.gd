extends SceneTree
# Headless contract for saved ship colouring on the modular hulls. Hull_Paint takes the
# chosen tint and finish; Hull_Dark / Hull_Steel stay authored; Nozzle_Emit keeps its
# white, gain-scaled propulsion pass with one shaping socket per booster.

const TEST_TINT := Color(0.10, 0.66, 0.66)
const HULLS := {"wren": 1, "kestrel": 2, "swift": 2, "harrier": 2, "osprey": 3, "condor": 4, "albatross": 4}


func _initialize() -> void:
	var failed := 0
	for slug in HULLS:
		var scene := load("res://assets/ships/%s/%s.glb" % [slug, slug]) as PackedScene
		failed += _check("%s_imported" % slug, scene != null)
		if scene == null:
			continue
		var model := scene.instantiate() as Node3D
		var drives := ModularHull.style(model, TEST_TINT, "metallic")
		failed += _check("%s_one_drive_per_nozzle_surface" % slug, drives.size() >= 1)
		var painted := 0
		for mi in ShipMesh.gather_mesh_instances(model):
			for si in mi.mesh.get_surface_count():
				var source := mi.mesh.surface_get_material(si)
				var active := mi.get_surface_override_material(si)
				match source.resource_name:
					"Hull_Paint":
						painted += 1
						failed += _check("%s_paint_tinted" % slug, active is StandardMaterial3D \
							and _rgb_equal((active as StandardMaterial3D).albedo_color, TEST_TINT) \
							and not (active as StandardMaterial3D).clearcoat_enabled)
					"Hull_Dark", "Hull_Steel":
						failed += _check("%s_%s_authored" % [slug, source.resource_name], active == null)
					"Nozzle_Emit":
						var drive := active.next_pass as ShaderMaterial if active != null else null
						var gain := float(drive.get_shader_parameter("brightness")) if drive != null else -1.0
						failed += _check("%s_nozzle_still_white" % slug, drive != null and drives.has(drive) \
							and drive.get_shader_parameter("plasma_color") == Color.WHITE \
							and is_equal_approx(gain, ShipMesh.booster_gain(ModularHull.BOOSTER_GAIN)) \
							and int(drive.get_shader_parameter("socket_count")) == int(HULLS[slug]))
					"Accent_Emit":
						failed += _check("%s_accent_emits" % slug, active is StandardMaterial3D \
							and (active as StandardMaterial3D).emission_enabled)
		failed += _check("%s_has_paint" % slug, painted > 0)
		var sockets := ModularHull.booster_sockets(model)
		failed += _check("%s_booster_radii_measured" % slug, sockets.size() == int(HULLS[slug]) \
			and sockets.all(func(s): return float(s.radius) > 0.1 and float(s.radius) < 15.0))
		ModularHull.style(model, TEST_TINT, "glassy")
		for mi in ShipMesh.gather_mesh_instances(model):
			for si in mi.mesh.get_surface_count():
				var active := mi.get_surface_override_material(si)
				if active != null and active.resource_name == "Hull_Paint":
					failed += _check("%s_glassy_lacquer_opaque" % slug,
						(active as StandardMaterial3D).clearcoat_enabled \
						and (active as StandardMaterial3D).transparency == BaseMaterial3D.TRANSPARENCY_DISABLED)
		model.free()

	var ship_source := FileAccess.get_file_as_string("res://scripts/flight/ship.gd")
	var main_source := FileAccess.get_file_as_string("res://scripts/core/main.gd")
	var hud_source := FileAccess.get_file_as_string("res://scripts/ui/hud.gd")
	var state_source := FileAccess.get_file_as_string("res://scripts/core/game_state.gd")
	failed += _check("whole_roster_is_colorable",
		ship_source.count("\"color_pick\": true") == 7 \
		and ship_source.count("\"color_pick\": false") == 0)
	failed += _check("whole_roster_offers_finish",
		ship_source.count("\"finish_pick\": true") == 7 \
		and ship_source.contains("func current_has_finish_pick()") \
		and hud_source.contains("var has_finish: bool"))
	failed += _check("saved_customization_api", ship_source.contains("func customization_state()") \
		and ship_source.contains("func load_customization(saved: Dictionary)"))
	failed += _check("profile_persistence_restored", state_source.contains("var customization := {}") \
		and main_source.contains("GameState.customization = ship.customization_state()"))
	failed += _check("hangar_controls_restored", hud_source.contains("signal ship_color_selected") \
		and hud_source.contains("signal ship_finish_selected") and hud_source.contains("signal ship_module_selected"))
	failed += _check("procedural_boosters_still_absent", not ship_source.contains("_build_boosters") \
		and not ship_source.contains("BOOSTER_LAYOUTS") and not hud_source.contains("ship_bell_toggled"))
	failed += _check("customization_scripts_compile",
		load("res://scripts/flight/ship.gd") is Script \
		and load("res://scripts/ui/hud.gd") is Script \
		and load("res://scripts/core/main.gd") is Script \
		and load("res://scripts/core/game_state.gd") is Script)

	var state_script := load("res://scripts/core/game_state.gd") as Script
	var state = state_script.new()
	var cfg := ConfigFile.new()
	state.customization = {"color": {"Wren": "teal"}, "finish": {"Wren": "glassy"}}
	state.weapon_set = "mk2"
	state.pad_set = "mk2"
	state.save_into(cfg)
	state.reset()
	failed += _check("reset_restores_mk1", state.weapon_set == "mk1" and state.pad_set == "mk1")
	state.load_from(cfg)
	failed += _check("customization_round_trip",
		state.customization == {"color": {"Wren": "teal"}, "finish": {"Wren": "glassy"}} \
		and state.weapon_set == "mk2" and state.pad_set == "mk2")
	state.customization = {"color": {"Kestrel": "#c0331f"}}
	state.save_into(cfg)
	state.customization = {}
	state.load_from(cfg)
	failed += _check("manual_hex_round_trip",
		state.customization == {"color": {"Kestrel": "#c0331f"}})
	state.free()

	failed += _check("hangar_offers_manual_picker",
		hud_source.contains("ColorPickerButton") and hud_source.contains("_on_manual_color") \
		and hud_source.contains("_picker_popup_open"))
	failed += _check("manual_hex_keys_parsed",
		ship_source.contains("func color_from_key") and ship_source.contains("html_is_valid"))

	if failed == 0:
		print("ship_customization: OK")
		quit(0)
	else:
		print("ship_customization: FAIL %d" % failed)
		quit(1)


func _rgb_equal(a: Color, b: Color) -> bool:
	return is_equal_approx(a.r, b.r) and is_equal_approx(a.g, b.g) and is_equal_approx(a.b, b.b)


func _check(label: String, condition: bool) -> int:
	if condition:
		return 0
	push_error("ship_customization: " + label)
	return 1
