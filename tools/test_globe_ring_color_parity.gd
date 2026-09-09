extends SceneTree
# Contract: the globe (planet_cook.gdshader) and the surface ring
# (terrain_tile.gdshader) must receive IDENTICAL values for every GDScript-side
# uniform that both shaders' shared colour rule (shaders/planet_color.gdshaderinc)
# depends on — a mismatched default or a forgotten set_shader_parameter call
# reproduces the globe/ring colour jump even when the shader math itself agrees.
# Run: godot --headless --script res://tools/test_globe_ring_color_parity.gd
const G := preload("res://scripts/world/planet_generator.gd")
var failures := 0


func _initialize() -> void:
	for name in ["Earth", "Moon", "Mars", "Europa"]:
		var recipe := G.recipe_for({"name": name})
		var spec := {"spectral": "G"}
		var cook: ShaderMaterial = G.make_material(recipe, spec) as ShaderMaterial
		var tile: ShaderMaterial = G.terrain_material(recipe, spec)
		check(name + "_cook_material_exists", cook != null)
		check(name + "_tile_material_exists", tile != null)
		if cook == null or tile == null:
			continue

		var c_ocean: Vector3 = cook.get_shader_parameter("color_ocean")
		var t_ocean: Vector3 = tile.get_shader_parameter("color_ocean")
		check(name + "_shares_color_ocean", c_ocean.is_equal_approx(t_ocean))

		var c_kind: int = int(cook.get_shader_parameter("kind"))
		var t_kind: int = int(tile.get_shader_parameter("kind"))
		check(name + "_shares_kind", c_kind == t_kind)

		var c_night: float = float(cook.get_shader_parameter("night_fill"))
		var t_night: float = float(tile.get_shader_parameter("night_fill"))
		check(name + "_shares_night_fill",
			is_equal_approx(c_night, t_night) and is_equal_approx(c_night, G.NIGHT_FILL))

	# A recipe that never sets color_ocean must still agree between the two
	# materials — the bug this guards was two DIFFERENT hardcoded defaults, not
	# just two different lookups of the same field.
	var bare := {"name": "Bare probe", "kind": "rocky"}
	var cook_bare: ShaderMaterial = G.make_material(bare, {}) as ShaderMaterial
	var tile_bare: ShaderMaterial = G.terrain_material(bare, {})
	var sampler_bare := G.terrain_sampler(bare)
	check("default_color_ocean_matches_cook",
		(cook_bare.get_shader_parameter("color_ocean") as Vector3).is_equal_approx(
			Vector3(G.DEFAULT_COLOR_OCEAN.r, G.DEFAULT_COLOR_OCEAN.g, G.DEFAULT_COLOR_OCEAN.b)))
	check("default_color_ocean_matches_tile",
		(tile_bare.get_shader_parameter("color_ocean") as Vector3).is_equal_approx(
			Vector3(G.DEFAULT_COLOR_OCEAN.r, G.DEFAULT_COLOR_OCEAN.g, G.DEFAULT_COLOR_OCEAN.b)))
	check("default_color_ocean_matches_cpu_bake", sampler_bare._ocean_color.is_equal_approx(G.DEFAULT_COLOR_OCEAN))

	# Earth explicitly sets color_ocean — confirm the CPU-side bake used by
	# ring vertex colours agrees with the GDScript value handed to both
	# shaders, not a hardcoded palette colour of its own.
	var earth := G.recipe_for({"name": "Earth"})
	var earth_sampler := G.terrain_sampler(earth)
	var earth_ocean: Color = earth.get("color_ocean")
	check("earth_cpu_bake_uses_recipe_color_ocean",
		earth_sampler._ocean_color.is_equal_approx(earth_ocean))

	if failures == 0:
		print("globe_ring_color_parity: OK")
		quit(0)
	else:
		print("globe_ring_color_parity: FAIL %d" % failures)
		quit(1)


func check(label: String, ok: bool) -> void:
	if not ok:
		failures += 1
		push_error("globe_ring_color_parity: " + label)
