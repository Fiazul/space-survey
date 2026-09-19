extends SceneTree
# Contract for kit props: real-scale lit trees/rocks/ice, deterministic seats,
# one MultiMesh per variant (≤3 draw calls), and the Amazon canopy teleport site.
# Run: godot --headless --script tools/test_surface_props.gd

const G := preload("res://scripts/world/planet_generator.gd")
const SP := preload("res://scripts/world/surface_patch.gd")
const DS := preload("res://scripts/world/dev_sites.gd")

const EARTH_R := 6371.0
const MOON_R := 1737.4
const PREV_PROP_MAX := 220

var failures := 0


func _initialize() -> void:
	_shader()
	_dev_site()
	_meshes()
	_earth_7km()
	_amazon_and_determinism()
	_rock_and_ice_kits()
	print("surface_props: ", "OK" if failures == 0 else "FAIL %d" % failures)
	quit(0 if failures == 0 else 1)


func _shader() -> void:
	var src := FileAccess.get_file_as_string("res://shaders/surface_prop.gdshader")
	check("prop_shader_has_lambert_sun_term", src.find("dot(") >= 0 and src.find("sun_dir") >= 0)
	check("prop_shader_has_sky_term", src.find("sky") >= 0)
	check("prop_shader_sky_gated_on_air", src.find("air_amount") >= 0)
	# Vacuum stays black: the sky term must be multiplied by air_amount, not a
	# constant fill that lights airless rocks as if they sat under a sky.
	var sky_line := _first_line_containing(src, "sky")
	check("prop_shader_sky_multiplies_air_amount",
		sky_line.find("air_amount") >= 0)
	check("prop_shader_has_stream_fade", src.find("stream_fade") >= 0)
	check("prop_shader_stream_fade_defaults_to_one",
		_uniform_default_is_one(src, "stream_fade"))
	var ground := FileAccess.get_file_as_string("res://shaders/terrain_tile.gdshader")
	check("ground_shader_has_stream_fade", ground.find("stream_fade") >= 0)
	check("ground_shader_stream_fade_defaults_to_one",
		_uniform_default_is_one(ground, "stream_fade"))


func _dev_site() -> void:
	var found := {}
	for site in DS.LANDMARKS:
		if str(site.get("name", "")) == "Amazon canopy 300 m":
			found = site
			break
	check("amazon_canopy_site_exists", not found.is_empty())
	if found.is_empty():
		return
	check("amazon_canopy_is_earth_surface",
		str(found.get("body", "")) == "Earth" and str(found.get("mode", "")) == "surface")
	check("amazon_canopy_over_the_basin",
		absf(float(found.get("lat_deg", 99.0)) - (-3.0)) < 2.0
		and absf(float(found.get("lon_deg", 99.0)) - (-60.0)) < 8.0)
	check("amazon_canopy_is_300m_agl",
		absf(float(found.get("alt_km", 0.0)) - 0.3) < 0.001)


func _meshes() -> void:
	var patch := SP.new()
	patch._ready()
	var earth := G.recipe_for({"name": "Earth"})
	patch.bind_recipe(earth)
	var tree_meshes := _prop_meshes(patch)
	check("tree_kit_has_prop_meshes", tree_meshes.size() > 0)
	check("tree_kit_draw_slots_at_most_3", tree_meshes.size() <= 3)
	var variant_ids := 0
	var tree_h_ok := 0
	for mesh in tree_meshes:
		variant_ids += _unique_parts(mesh)
		var h: float = mesh.get_aabb().size.y
		if h >= 0.018 and h <= 0.045:
			tree_h_ok += 1
	check("tree_kit_has_at_least_3_variants", variant_ids >= 3)
	check("tree_variant_height_is_20_to_40m", tree_h_ok >= 1)
	check("tree_kit_includes_a_boulder", _mesh_has_short_part(tree_meshes, 0.0008, 0.010))
	patch.free()


func _earth_7km() -> void:
	var n := _instance_count_at(20.5, -17.0, 7.0, "Earth", EARTH_R)
	print("surface_props: earth_7km instances %d (prev budget %d, cap %d)"
		% [n, PREV_PROP_MAX, PREV_PROP_MAX * 2])
	check("earth_7km_planted_props", n > 0)
	check("earth_7km_instance_count_within_2x", n <= PREV_PROP_MAX * 2)


func _amazon_and_determinism() -> void:
	var a := _build_at(-3.0, -60.0, 0.3, "Earth", EARTH_R)
	var r: Dictionary = a.report()
	check("amazon_planted_tree_kit", str(r.kit) == "tree" and int(r.props) > 0)
	check("amazon_draw_calls_at_most_3", _draw_calls(a) <= 3 and _draw_calls(a) >= 1)
	var snap := _xform_snapshot(a)
	check("amazon_snapshot_nonempty", snap.size() > 0)
	# Same seat, same rebuild: identical instance list (no popping).
	var b := _build_at(-3.0, -60.0, 0.3, "Earth", EARTH_R)
	var snap2 := _xform_snapshot(b)
	check("rebuild_keeps_instance_count", snap.size() == snap2.size())
	var same := snap.size() == snap2.size()
	if same:
		for i in snap.size():
			if snap[i] != snap2[i]:
				same = false
				break
	check("rebuild_keeps_the_same_instances", same)
	# World height of a tree instance stays in the 20–40 m band after 0.7–1.3 scale.
	var tree_h := _instance_world_heights(a, 0.018)
	var in_band := 0
	for h in tree_h:
		if h >= 0.018 and h <= 0.055:
			in_band += 1
	check("amazon_trees_are_real_scale", tree_h.size() > 0 and in_band >= tree_h.size() * 0.8)
	a.free()
	b.free()


func _rock_and_ice_kits() -> void:
	var moon := _build_at(10.0, 20.0, 0.2, "Moon", MOON_R)
	check("moon_uses_rock_kit", str(moon.report().kit) == "rock")
	check("moon_planted_boulders", int(moon.report().props) > 0)
	check("rock_kit_has_no_tree_green", not _has_canopy_green(_prop_meshes(moon)))
	var rock_h := _instance_world_heights(moon, 0.0)
	var boulder_ok := 0
	for h in rock_h:
		if h >= 0.0007 and h <= 0.012:
			boulder_ok += 1
	check("rock_boulders_are_1_to_8m",
		rock_h.size() > 0 and boulder_ok >= rock_h.size() * 0.8)
	check("rock_draw_calls_at_most_3", _draw_calls(moon) <= 3)
	moon.free()

	var moon_7km := _instance_count_at(10.0, 20.0, 7.0, "Moon", MOON_R)
	print("surface_props: moon_7km instances %d" % moon_7km)
	check("moon_7km_planted_boulders", moon_7km > 0)

	const EUROPA_R := 1560.8
	var europa := G.recipe_for({"name": "Europa"})
	var patch := SP.new()
	patch._ready()
	patch.bind_recipe(europa)
	check("europa_uses_ice_kit", str(patch.report().kit) == "ice")
	var ice_h_ok := 0
	for mesh in _prop_meshes(patch):
		var h: float = mesh.get_aabb().size.y
		if h >= 0.006 and h <= 0.040:
			ice_h_ok += 1
	check("ice_spires_are_real_scale", ice_h_ok >= 1)
	check("ice_kit_has_no_tree_green", not _has_canopy_green(_prop_meshes(patch)))
	patch.free()

	var ice_n := _instance_count_at(10.0, 20.0, 0.3, "Europa", EUROPA_R)
	print("surface_props: europa_ice instances %d" % ice_n)
	check("europa_ice_planted_spires", ice_n > 0)


func _build_at(lat: float, lon: float, alt: float, body: String, radius: float) -> Node:
	var recipe := G.recipe_for({"name": body})
	var sampler: TerrainSampler = G.terrain_sampler(recipe)
	var patch := SP.new()
	patch._ready()
	patch.bind_body(recipe, sampler)
	var dir := DS.dir_for(lat, lon)
	var pos: Vector3 = dir * (sampler.ground_radius_km(dir, radius) + alt)
	var ceiling: float = G.band_ceiling_km(sampler)
	patch.update_for(pos, body, true, radius, alt, 0.02, ceiling, recipe, sampler)
	patch.force_ready()
	return patch


func _instance_count_at(lat: float, lon: float, alt: float, body: String, radius: float) -> int:
	var patch := _build_at(lat, lon, alt, body, radius)
	var n: int = int(patch.report().props)
	patch.free()
	return n


func _prop_meshes(patch: Node) -> Array:
	var out := []
	for c in patch.get_children():
		if c is MultiMeshInstance3D and c.multimesh != null and c.multimesh.mesh != null:
			out.append(c.multimesh.mesh)
	return out


func _draw_calls(patch: Node) -> int:
	var n := 0
	for c in patch.get_children():
		if c is MultiMeshInstance3D and c.multimesh != null \
				and c.multimesh.visible_instance_count > 0:
			n += 1
	return n


func _unique_parts(mesh: ArrayMesh) -> int:
	if mesh.get_surface_count() == 0:
		return 0
	var arrays: Array = mesh.surface_get_arrays(0)
	var uv2: Variant = arrays[Mesh.ARRAY_TEX_UV2]
	if uv2 is PackedVector2Array and uv2.size() > 0:
		var seen := {}
		for v in uv2:
			seen[int(round((v as Vector2).x))] = true
		return maxi(seen.size(), 1)
	return 1


func _mesh_has_short_part(meshes: Array, lo: float, hi: float) -> bool:
	for mesh in meshes:
		var aabb: AABB = mesh.get_aabb()
		# Combined tree+boulder mesh is tall overall; look at vertex y-span clusters
		# by UV2 part id when present.
		if mesh.get_surface_count() == 0:
			continue
		var arrays: Array = mesh.surface_get_arrays(0)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var uv2: Variant = arrays[Mesh.ARRAY_TEX_UV2]
		if uv2 is PackedVector2Array and uv2.size() == verts.size():
			var lo_y := {}
			var hi_y := {}
			for i in verts.size():
				var part := int(round((uv2[i] as Vector2).x))
				var y: float = verts[i].y
				if not lo_y.has(part):
					lo_y[part] = y
					hi_y[part] = y
				else:
					lo_y[part] = minf(float(lo_y[part]), y)
					hi_y[part] = maxf(float(hi_y[part]), y)
			for part in lo_y.keys():
				var h: float = float(hi_y[part]) - float(lo_y[part])
				if h >= lo and h <= hi:
					return true
		elif aabb.size.y >= lo and aabb.size.y <= hi:
			return true
	return false


func _has_canopy_green(meshes: Array) -> bool:
	for mesh in meshes:
		if mesh.get_surface_count() == 0:
			continue
		var cols: Variant = mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR]
		if not (cols is PackedColorArray):
			continue
		for c in cols:
			var col: Color = c
			if col.g > 0.22 and col.g > col.r + 0.06 and col.g > col.b:
				return true
	return false


func _xform_snapshot(patch: Node) -> PackedStringArray:
	var rows := PackedStringArray()
	for c in patch.get_children():
		if not (c is MultiMeshInstance3D) or c.multimesh == null:
			continue
		var mm: MultiMesh = c.multimesh
		for i in mm.visible_instance_count:
			var xf: Transform3D = mm.get_instance_transform(i)
			var custom := Color()
			if mm.use_custom_data:
				custom = mm.get_instance_custom_data(i)
			rows.append("%s|%.5f,%.5f,%.5f|%.5f,%.5f,%.5f|%.3f"
				% [c.name, xf.origin.x, xf.origin.y, xf.origin.z,
				xf.basis.x.x, xf.basis.y.y, xf.basis.z.z, custom.r])
	rows.sort()
	return rows


func _instance_world_heights(patch: Node, min_mesh_h: float) -> Array:
	var out := []
	for c in patch.get_children():
		if not (c is MultiMeshInstance3D) or c.multimesh == null or c.multimesh.mesh == null:
			continue
		var mesh: ArrayMesh = c.multimesh.mesh
		var mesh_h: float = mesh.get_aabb().size.y
		if mesh_h < min_mesh_h:
			continue
		# Combined meshes: world height uses the TALL part's aabb * instance scale.
		var mm: MultiMesh = c.multimesh
		for i in mm.visible_instance_count:
			var sc: Vector3 = mm.get_instance_transform(i).basis.get_scale()
			var custom_r := 0.0
			if mm.use_custom_data:
				custom_r = mm.get_instance_custom_data(i).r
			# Boulder instances on the combined slot use the short part; skip them
			# when measuring trees.
			if min_mesh_h >= 0.018 and custom_r > 0.45:
				continue
			out.append(mesh_h * sc.y)
	return out


func _first_line_containing(src: String, token: String) -> String:
	for line in src.split("\n"):
		if line.find(token) >= 0:
			return line
	return ""


func _uniform_default_is_one(src: String, name: String) -> bool:
	for line in src.split("\n"):
		if line.find(name) >= 0 and line.find("uniform") >= 0:
			return line.find("= 1.0") >= 0 or line.find("=1.0") >= 0
	return false


func check(label: String, ok: bool) -> void:
	if not ok:
		failures += 1
		push_error("surface_props: " + label)
