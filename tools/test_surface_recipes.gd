extends SceneTree
const G := preload("res://scripts/world/planet_generator.gd")
const SurfaceRecipe := preload("res://scripts/world/surface_recipe.gd")
var failures := 0

# Named recipes carrying a real DEM (Mars, Moon as of 2026-09-09) suppress
# generic craters/mountains at/above the DEM's own texel scale - a mapped
# body's real topography owns that scale, not invented noise (see
# SurfaceRecipe.resolve()'s height_texel_km branch). Everything below this
# comment is testing the GENERIC no-map geology system itself (crater bowl
# shape, landmark non-overlap, crater-field density) via a body that carries
# the Moon's own radius/seed/WORLD_DEFAULTS but none of its new DEM fields -
# not the real (now DEM-equipped) "Moon" recipe main.gd actually flies over.
func _airless_moon_recipe() -> Dictionary:
	var r := G.recipe_for({"name": "Moon"}).duplicate()
	for key in ["height", "height_encoding", "height_datum", "height_m_per_unit",
			"height_max", "height_signed", "height_texel_km"]:
		r.erase(key)
	return r

func _initialize() -> void:
	# Removing the recipe binding must fail even if a shader has useful defaults.
	for row in [["Earth", 1.0, 0.0], ["Moon", 0.0, 0.0], ["Io", 0.0, 1.0], ["Europa", 0.0, 0.0]]:
		var mat := G.terrain_material(G.recipe_for({"name": row[0]}), {})
		check("%s_liquid_selection" % row[0], mat.get_shader_parameter("liquid_amount") == row[1])
		check("%s_lava_selection" % row[0], mat.get_shader_parameter("lava_amount") == row[2])
	var moon := G.terrain_sampler(_airless_moon_recipe())
	var profile = moon.get("surface")
	check("geology_profile_reaches_sampler", profile is Dictionary)
	if profile is Dictionary:
		var centre: Vector3 = profile.craters[0].direction
		var width: float = profile.craters[0].width
		var rim := centre.rotated(centre.cross(Vector3.UP).normalized(), width)
		check("crater_has_bowl_and_raised_rim", moon.geology_height_m(centre) < -100.0 and moon.geology_height_m(rim) > 20.0)
		check("lunar_crater_is_dry", moon.water01(centre) == 0.0)
		var io := G.terrain_sampler(G.recipe_for({"name": "Io"}))
		var vent: Vector3 = io.surface.volcanoes[0].direction
		var vw: float = io.surface.volcanoes[0].width
		var shoulder := vent.rotated(vent.cross(Vector3.UP).normalized(), vw * 0.25)
		check("volcano_has_caldera", io.geology_height_m(shoulder) > io.geology_height_m(vent) + 100.0)
		check("lava_is_local_to_vents", io.lava01(vent) > 0.5 and io.lava01(-vent) == 0.0)
		check("generated_volcano_is_collidable", io.swept_contact(shoulder * (io.ground_radius_km(shoulder, 1821.6) + 0.1), shoulder * (io.ground_radius_km(shoulder, 1821.6) - 0.01), 1821.6, 0.02))
		var again := G.terrain_sampler(G.recipe_for({"name": "Io"}))
		check("geology_is_repeatable", is_equal_approx(io.height_m(shoulder), again.height_m(shoulder)))
		for body in ["Sun", "Jupiter", "Uranus", "Neptune"]:
			check(body + "_does_not_spawn_ground", not G.has_surface(G.recipe_for({"name": body})))
			var s := G.terrain_sampler(G.recipe_for({"name": body}))
			check(body + "_has_no_ground_features", s.surface.craters.is_empty() and s.surface.volcanoes.is_empty() and s.surface.liquid_amount == 0.0 and s.geology_height_m(Vector3.RIGHT) == 0.0)
	for row in [["Sun", "granulation"], ["Jupiter", "storm_strength"]]:
		var painted := G.paint({"name": row[0]}, 10.0)
		check(str(row[0]) + "_recipe_drives_globe", painted.mat.get_shader_parameter(row[1]) == 1.0)
		painted.sphere.free()
	var ocean := G.terrain_sampler({"name": "Ocean probe", "kind": "rocky", "seed": 13.0, "land_amount": 0.0, "surface": {"liquid_amount": 1.0}})
	check("procedural_ocean_has_level_surface", absf(ocean.height_m(Vector3.RIGHT)) < 0.01 and absf(ocean.height_m(Vector3.UP)) < 0.01)
	var custom := G.recipe_for({"name": "Custom volcano", "kind": "rocky", "surface": {"lava_amount": 1.0, "volcano_count": 4}})
	check("invented_world_accepts_surface_recipe", G.terrain_sampler(custom).surface.volcanoes.size() == 4)
	var moon_s := G.terrain_sampler(_airless_moon_recipe())
	check("ice_profile_prevents_false_oceans", G.terrain_sampler(G.recipe_for({"name": "Europa"})).water01(Vector3.UP) == 0.0)
	for features in [moon_s.surface.craters, moon_s.surface.volcanoes]:
		for i in features.size():
			for j in range(i + 1, features.size()):
				check("landmark_supports_do_not_overlap", (features[i].direction as Vector3).distance_to(features[j].direction) >= 1.7 * (float(features[i].width) + float(features[j].width)))
	var forced_star := G.terrain_sampler(G.recipe_for({"name": "Sun", "surface": {"volcano_count": 12, "liquid_amount": 1.0}}))
	check("stellar_type_overrides_invalid_solid_features", forced_star.surface.volcanoes.is_empty() and forced_star.surface.liquid_amount == 0.0)
	for i in 100:
		var n := Vector3(sin(i * 2.1), cos(i * 3.1), sin(i * 1.7)).normalized()
		check("terrain_height_within_declared_bound", moon_s.height_m(n) <= moon_s.max_height_km() * 1000.0)
	var patch := preload("res://scripts/world/surface_patch.gd").new()
	patch.call("_ready")
	patch.bind_body(_airless_moon_recipe(), moon_s)
	var props: MultiMeshInstance3D = patch.get("_props")
	var arrays := props.multimesh.mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	check("rock_exterior_is_clockwise", (verts[1] - verts[0]).cross(verts[2] - verts[0]).dot(normals[0]) < 0.0)
	check("rock_side_normal_faces_out", normals[0].x > 0.0)
	var moon_color: Color = arrays[Mesh.ARRAY_COLOR][0]
	patch.bind_body(G.recipe_for({"name": "Mars"}), G.terrain_sampler(G.recipe_for({"name": "Mars"})))
	var mars_color: Color = props.multimesh.mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR][0]
	check("rock_color_follows_body_changes", moon_color != mars_color)
	patch.free()

	_check_crater_field_encounter(moon_s)
	_check_precull_equivalence()
	_check_max_offset_bound()

	print("surface_recipes: ", "OK" if failures == 0 else "FAIL %d" % failures)
	quit(0 if failures == 0 else 1)


# Category: multi-scale crater fields must be visible in a normal-sized flight
# patch, not just at the ~28 seeded landmark locations. 160x160 km at 1 km
# spacing around 3 random Moon spots, counting 4-connected depressions below
# -50 m; a flat/near-empty background would read as 0-a-few, not hundreds.
func _check_crater_field_encounter(moon_s: TerrainSampler) -> void:
	const MOON_R_KM := 1737.4
	const GRID_KM := 160.0
	const STEP_KM := 1.0
	const MIN_TOTAL_CRATERS := 500
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var n := int(GRID_KM / STEP_KM) + 1
	var total := 0
	for spot in 3:
		var y := rng.randf_range(-0.6, 0.6)
		var lon := rng.randf_range(-PI, PI)
		var center := Vector3(sqrt(1.0 - y * y) * cos(lon), y, sqrt(1.0 - y * y) * sin(lon))
		var east := center.cross(Vector3.UP).normalized()
		var north := east.cross(center).normalized()
		var mask := []
		mask.resize(n)
		for i in n:
			var row := PackedByteArray()
			row.resize(n)
			mask[i] = row
		for i in n:
			var dx := -GRID_KM * 0.5 + float(i) * STEP_KM
			for j in n:
				var dy := -GRID_KM * 0.5 + float(j) * STEP_KM
				var dir: Vector3 = (center + (east * dx + north * dy) / MOON_R_KM).normalized()
				mask[i][j] = 1 if moon_s.geology_height_m(dir) < -50.0 else 0
		var visited := []
		visited.resize(n)
		for i in n:
			var row := PackedByteArray()
			row.resize(n)
			visited[i] = row
		var comps := 0
		for i in n:
			for j in n:
				if mask[i][j] == 1 and visited[i][j] == 0:
					comps += 1
					var stack := [[i, j]]
					visited[i][j] = 1
					while stack.size() > 0:
						var cur: Array = stack.pop_back()
						for d in [[1, 0], [-1, 0], [0, 1], [0, -1]]:
							var ni: int = cur[0] + d[0]
							var nj: int = cur[1] + d[1]
							if ni >= 0 and ni < n and nj >= 0 and nj < n \
									and mask[ni][nj] == 1 and visited[ni][nj] == 0:
								visited[ni][nj] = 1
								stack.append([ni, nj])
		total += comps
	check("crater_field_reads_across_a_flight_patch", total >= MIN_TOTAL_CRATERS)
	print("surface_recipes: crater encounter  %d depressions < -50 m across 3x %.0fx%.0f km Moon patches"
		% [total, GRID_KM, GRID_KM])


# Category: the dot-product landmark pre-filter must be an EXACT optimization,
# not an approximation — same heights as testing every landmark unconditionally.
func _check_precull_equivalence() -> void:
	var p := SurfaceRecipe.resolve({"name": "Moon"})
	var rng := RandomNumberGenerator.new()
	rng.seed = 41
	var worst := 0.0
	for i in 1000:
		var d := Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)).normalized()
		var culled: float = SurfaceRecipe.height_offset_m(d, p)
		var brute := _brute_landmark_offset(d, p)
		worst = maxf(worst, absf(culled - brute))
	check("landmark_precull_matches_brute_force", worst < 1e-6)


func _brute_landmark_offset(dir: Vector3, p: Dictionary) -> float:
	var h := 0.0
	if p.mountain_m > 0.0:
		var ridge: FastNoiseLite = p.ridge_noise
		h += (0.55 - absf(ridge.get_noise_3dv(dir))) * float(p.mountain_m)
	if p.hills_m > 0.0:
		var hn: FastNoiseLite = p.hills_noise
		h += hn.get_noise_3dv(dir) * float(p.hills_m)
	for oct in p.crater_octaves:
		h += SurfaceRecipe.crater_octave_offset_m(dir, oct, float(p.crater_density))
	for crater in p.craters:
		var r: float = dir.distance_to(crater.direction) / float(crater.width)
		if r < 1.7:
			h += SurfaceRecipe.crater_shape(r) * float(p.crater_m)
	for volcano in p.volcanoes:
		var r: float = dir.distance_to(volcano.direction) / float(volcano.width)
		if r < 1.0:
			var cone := (1.0 - r) * (1.0 - smoothstep(0.8, 1.0, r))
			var caldera := 0.76 * exp(-pow(r / 0.16, 4.0))
			h += (cone - caldera) * float(p.volcano_m)
	return h


# Category: max_offset_m must include every new geology term (crater octaves,
# hills) or the band ceiling opens below terrain it doesn't know exists.
func _check_max_offset_bound() -> void:
	for name in ["Moon", "Mars", "Earth"]:
		var s := G.terrain_sampler(G.recipe_for({"name": name}))
		var bound := SurfaceRecipe.max_offset_m(s.surface)
		var rng := RandomNumberGenerator.new()
		rng.seed = 77
		var worst := -1e18
		for i in 5000:
			var d := Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)).normalized()
			worst = maxf(worst, s.geology_height_m(d))
		check(name + "_max_offset_bounds_observed_peak", bound >= worst)

func check(label: String, ok: bool) -> void:
	if not ok:
		failures += 1
		push_error("surface_recipes: " + label)
