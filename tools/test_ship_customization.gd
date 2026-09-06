extends SceneTree
# Headless contract for saved ship coloring. Every non-booster surface must accept
# the chosen tint while the exact authored propulsion ShaderMaterials remain intact.

const MeshStyler := preload("res://scripts/flight/ship_mesh.gd")
const TEST_TINT := Color(0.10, 0.66, 0.66)
const SHIPS := [
	{"key": "class", "path": "res://assets/class_ii_galactic_cruiser/Class II Gallactic Cruiser.obj", "surfaces": 5, "boosters": 1, "base": MeshStyler.CLASS_II_BOOSTER_GAIN},
	{"key": "snarkrans", "path": "res://assets/snarkrans_starship/spaceship.obj", "surfaces": 77, "boosters": 4, "base": MeshStyler.SNARKRANS_BOOSTER_GAIN},
	{"key": "dingo57", "path": "res://assets/dingo57_starship/3d-model.obj", "surfaces": 9, "boosters": 8, "base": MeshStyler.DINGO57_BOOSTER_GAIN},
]


func _initialize() -> void:
	var failed := 0
	for spec in SHIPS:
		var mesh := load(spec.path) as Mesh
		failed += _check("%s_imported" % spec.key, mesh != null)
		if mesh == null:
			continue
		var model := MeshInstance3D.new()
		model.mesh = mesh
		var propulsion: Array[ShaderMaterial]
		match String(spec.key):
			"class":
				propulsion = MeshStyler.style_class_ii_cruiser(model)
			"snarkrans":
				propulsion = MeshStyler.style_snarkrans_starship(model)
			"dingo57":
				propulsion = MeshStyler.style_dingo57_starship(model)

		var colored := MeshStyler.color_authored_ship(model, TEST_TINT, "metallic")
		failed += _check("%s_every_non_booster_colored" % spec.key,
			colored == int(spec.surfaces) - int(spec.boosters))
		failed += _check("%s_booster_count" % spec.key,
			propulsion.size() == int(spec.boosters))
		var propulsion_ids := {}
		for drive in propulsion:
			propulsion_ids[drive.get_instance_id()] = true

		var seen_boosters := 0
		var seen_leds := 0
		for si in model.mesh.get_surface_count():
			var material := model.get_surface_override_material(si)
			if material != null and propulsion_ids.has(material.get_instance_id()):
				seen_boosters += 1
				var drive := material as ShaderMaterial
				# This test's job is that the hull PAINT pass never repaints a booster
				# surface, so it checks plasma_color is still white and the HDR gain is
				# still set. Assert the ship's OWN base gain rather than a range: a
				# range ceiling scaled by the knob (the previous version) would pass a
				# paint bug that wrote any value under it, and a fixed 4.0 ceiling broke
				# the moment the gains were re-derived from effective area (dingo57 is
				# 4.68 now). Dividing the material value back out by the knob is exact -
				# booster_gain is a single multiply.
				var gain := float(drive.get_shader_parameter("brightness")) if drive != null else -1.0
				var base := gain / maxf(MeshStyler.booster_brightness, 0.0001)
				failed += _check("%s_booster_%d_still_white" % [spec.key, si],
					drive != null \
					and drive.get_shader_parameter("plasma_color") == Color.WHITE \
					and gain > 0.0 and is_equal_approx(base, float(spec.base)))
			elif material is ShaderMaterial:
				seen_leds += 1
				failed += _check("%s_led_%d_tinted_not_replaced" % [spec.key, si],
					(material as ShaderMaterial).get_shader_parameter("color_tint") == TEST_TINT)
			else:
				failed += _check("%s_hull_%d_colored" % [spec.key, si],
					material is BaseMaterial3D \
					and (material as BaseMaterial3D).resource_name == "customized_hull" \
					and _rgb_equal((material as BaseMaterial3D).albedo_color, TEST_TINT))
		failed += _check("%s_all_boosters_preserved" % spec.key,
			seen_boosters == int(spec.boosters))
		failed += _check("%s_led_count" % spec.key,
			seen_leds == (1 if String(spec.key) == "class" else 0))

		MeshStyler.color_authored_ship(model, TEST_TINT, "glassy")
		for si in model.mesh.get_surface_count():
			var material := model.get_surface_override_material(si)
			if (material != null and propulsion_ids.has(material.get_instance_id())) \
				or material is ShaderMaterial:
				continue
			var surface_name: String = model.mesh.surface_get_name(si).to_lower()
			# Dingo57 is a thin-shell SketchUp hull. Glassy finish may polish it,
			# but it must stay fully opaque and double-sided or panels vanish.
			if String(spec.key) == "dingo57" or surface_name.begins_with("outer_chassis_group_") \
				or surface_name == "hull_body" or surface_name.begins_with("hull_"):
				failed += _check("%s_repaired_hull_%d_stays_opaque" % [spec.key, si],
					material is BaseMaterial3D \
					and (material as BaseMaterial3D).transparency == BaseMaterial3D.TRANSPARENCY_DISABLED \
					and is_equal_approx((material as BaseMaterial3D).albedo_color.a, 1.0) \
					and (material as BaseMaterial3D).cull_mode == BaseMaterial3D.CULL_DISABLED)
				continue
			failed += _check("%s_hull_%d_glassy" % [spec.key, si],
				material is BaseMaterial3D \
				and (material as BaseMaterial3D).transparency == BaseMaterial3D.TRANSPARENCY_ALPHA \
				and is_equal_approx((material as BaseMaterial3D).albedo_color.a, 0.38))

		propulsion.clear()
		for si in model.mesh.get_surface_count():
			model.set_surface_override_material(si, null)
		model.mesh = null
		model.free()

	var ship_source := FileAccess.get_file_as_string("res://scripts/flight/ship.gd")
	var main_source := FileAccess.get_file_as_string("res://scripts/core/main.gd")
	var hud_source := FileAccess.get_file_as_string("res://scripts/ui/hud.gd")
	var state_source := FileAccess.get_file_as_string("res://scripts/core/game_state.gd")
	failed += _check("two_customizable_ships", ship_source.count("\"color_pick\": true") == 2)
	failed += _check("saved_customization_api", ship_source.contains("func customization_state()") \
		and ship_source.contains("func load_customization(saved: Dictionary)"))
	failed += _check("profile_persistence_restored", state_source.contains("var customization := {}") \
		and main_source.contains("GameState.customization = ship.customization_state()"))
	failed += _check("hangar_controls_restored", hud_source.contains("signal ship_color_selected") \
		and hud_source.contains("signal ship_finish_selected"))
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
	state.customization = {"Class II Galactic Cruiser": {"color": "teal", "finish": "glassy"}}
	state.save_into(cfg)
	state.customization = {}
	state.load_from(cfg)
	failed += _check("customization_round_trip",
		state.customization == {"Class II Galactic Cruiser": {"color": "teal", "finish": "glassy"}})
	state.free()

	if failed == 0:
		print("ship_customization: OK")
		quit(0)
	else:
		print("ship_customization: FAIL %d" % failed)
		quit(1)


func _rgb_equal(a: Color, b: Color) -> bool:
	return is_equal_approx(a.r, b.r) and is_equal_approx(a.g, b.g) and is_equal_approx(a.b, b.b)


func _check(name: String, ok: bool) -> int:
	if not ok:
		print("ship_customization: FAIL %s" % name)
		return 1
	return 0
