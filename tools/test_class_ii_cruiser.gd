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
	print("class_ii_cruiser: propulsion energy %.2f..%.2f x brightness %.2f = %.1f..%.1f  (booster_brightness knob %.2f)"
		% [idle_energy, full_energy, gain, idle_energy * gain, full_energy * gain,
		MeshStyler.booster_brightness])
	failed += _check("propulsion_energy_ramps_with_throttle",
		hit != null and idle_energy > 0.0 and full_energy > idle_energy)
	failed += _check("propulsion_hdr_is_on_albedo_not_emission",
		drive != null and drive.shader.code.contains("ALBEDO = white_core * energy")
		and drive.shader.code.contains("EMISSION = vec3(0.0)"))
	# Ceiling guards on ShipMesh.booster_brightness. Turn the knob far enough up and the
	# plume stops resolving anything and becomes a featureless slab under FILMIC +
	# glow_hdr_threshold 1.0. These failing means you went too far, not that they are
	# stale - the knob's value is printed above so the number is in the output.
	#
	# Two thresholds, because the shader is no longer a uniform plate. The BROAD value
	# is what most of the lit surface gets and has to stay off the slab; the small core
	# at the inner edge is allowed above 1.0, because a clipped core surrounded by
	# falloff is what reads as a hot throat rather than a white patch.
	var core_boost := float(drive.get_shader_parameter("core_boost")) \
		if drive != null and drive.get_shader_parameter("core_boost") != null else 1.5
	#
	# Split into two checks on purpose. The CALIBRATION contract uses the knob-free
	# base constant, so it stays meaningful and testable whatever the knob is parked
	# at - it is the shipped look that must be off the slab. The knob's own product is
	# a separate check, and its name is the message: if only that one fails, the code
	# is fine and the value in ship_mesh.gd is too high.
	var base := MeshStyler.CLASS_II_BOOSTER_GAIN
	failed += _check("propulsion_calibration_stays_off_the_slab",
		full_energy * base <= 1.5)
	failed += _check("propulsion_calibration_core_bounded",
		full_energy * base * core_boost <= 3.0)
	failed += _check("booster_brightness_knob_within_safe_window",
		full_energy * gain * core_boost <= 3.0)
	# The shaping itself, structurally. class_ii is the ship the border does NOT change
	# much - 100% of its authored patch area is already within 1.0 r of a nozzle axis
	# (tools/probe_booster_shape.gd), so what it gains here is the core gradient, while
	# dingo57 had 87% of its lit area outside the nozzle. Assert the code path and the
	# wiring anyway: this is the shader all three OBJ ships share, and a material that
	# loses its sockets silently reverts to the flat plate.
	failed += _check("propulsion_has_a_nozzle_border", drive != null \
		and drive.shader.code.contains("smoothstep(border_start, border_end, radial_n)") \
		and drive.shader.code.contains("visibility * shape"))
	failed += _check("propulsion_sockets_wired", drive != null \
		and int(drive.get_shader_parameter("socket_count")) \
			== MeshStyler.CLASS_II_BOOSTER_SOCKETS.size())
	failed += _check("propulsion_temperature_ramp", drive != null \
		and drive.shader.code.contains("cool_color") \
		and drive.shader.code.contains("temperature"))
	failed += _check("propulsion_never_angle_invisible", drive != null \
		and drive.shader.code.contains("mix(0.58, 1.0, edge_softness)"))
	failed += _check("propulsion_ultimate_white", drive != null \
		and drive.get_shader_parameter("plasma_color") == Color.WHITE \
		and float(drive.get_shader_parameter("brightness"))
			== MeshStyler.booster_gain(MeshStyler.CLASS_II_BOOSTER_GAIN))

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
				and torch_mat.shader.code.contains("tip_fade") \
				and torch_mat.shader.code.contains("wispy") \
				and torch_mat.shader.code.contains("billow") \
				and torch_mat.shader.code.contains("VERTEX.x")
	failed += _check("tapered_torch_geometry", torch_meshes_ok)
	failed += _check("open_plasma_cones", open_cones)
	failed += _check("torch_hdr_edge_fade", torch_shaders_ok)
	failed += _check("torch_video_flow", torch_shaders_ok)

	# This used to assert the literal "1920.0" was in the torch shader, which is how a
	# core "energy" of 6528 survived several rounds of "the booster is too bright" - it
	# was never reaching a pixel at all. `render_mode unshaded` DISCARDS EMISSION in
	# Godot 4, so an unshaded additive pass shows ALBEDO * ALPHA and nothing else.
	# Both properties below exist to stop that trap being re-set:
	#
	#   1. The HDR value must be on ALBEDO. If someone moves it back to EMISSION the
	#      plume goes invisible and no amount of tuning the constant brings it back.
	#   2. Its top must stay inside the range where a hot core still resolves instead
	#      of summing, across a dozen overlapping cone layers, into a white slab.
	var torch_code := MeshStyler.CRUISER_TORCH_SHADER.code
	failed += _check("torch_hdr_is_on_albedo_not_emission",
		torch_code.contains("ALBEDO = torch_color * energy")
		and torch_code.contains("EMISSION = vec3(0.0)"))
	var tramp := RegEx.new()
	tramp.compile("mix\\(([0-9.]+), *([0-9.]+), *pow\\(power")
	var thit: RegExMatch = tramp.search(torch_code)
	var t_idle := float(thit.get_string(1)) if thit != null else -1.0
	var t_full := float(thit.get_string(2)) if thit != null else -1.0
	# This used to multiply by a literal 3.4, described as "the hottest brightness any
	# ship hands the core layer". It was not - snarkrans passes 3.50 (ship_mesh.gd) -
	# and being a literal it also ignored ShipMesh.booster_brightness entirely, so the
	# torch ceiling could never fire however far the knob went. Read the built core
	# layer instead: add_class_ii_booster_plumes returns fog/core in pairs, and the
	# core is the hotter of each pair. 0.82 is the core layer's opacity.
	var core_brightness := 0.0
	for m in plume_materials:
		core_brightness = maxf(core_brightness,
			float(m.get_shader_parameter("brightness")))
	print("class_ii_cruiser: torch energy %.3f..%.3f x core brightness %.2f x opacity 0.82 -> peak %.2f"
		% [t_idle, t_full, core_brightness, t_full * core_brightness * 0.82])
	failed += _check("torch_energy_ramps_with_throttle",
		thit != null and t_idle > 0.0 and t_full > t_idle)
	failed += _check("torch_core_is_the_hotter_layer",
		core_brightness == MeshStyler.booster_gain(3.40))
	failed += _check("torch_calibration_stays_off_the_slab",
		t_full * 3.40 * 0.82 <= 1.5)
	failed += _check("torch_knob_within_safe_window",
		t_full * core_brightness * 0.82 <= 1.5)

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
