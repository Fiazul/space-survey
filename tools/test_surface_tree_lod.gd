extends SceneTree
const SP := preload("res://scripts/world/surface_patch.gd")
var failures := 0

func _initialize() -> void:
	var xforms := []
	var variants := PackedByteArray()
	for i in 1000:
		xforms.append(Transform3D(Basis.IDENTITY, Vector3(float(i) * .0005, 0, 0)))
		variants.append(i % 2)
	var data: Dictionary = SP.pack_prop_buffers(xforms, variants, Vector3.ZERO, Vector3.RIGHT, Vector3.BACK, 1000, "tree")
	check("three detail levels and ground-prop batch", data.buffers.size() == 7)
	if data.buffers.size() == 7:
		var counts := []
		for slot in 7:
			counts.append(data.buffers[slot].size() / (16 if slot == 2 else 12))
		check("full tree cap", counts[0] + counts[1] == 64)
		check("medium tree cap", counts[3] + counts[4] == 512)
		check("remaining trees use far cards", counts[5] + counts[6] == 424)
		var positions := {}
		for slot in [0, 1, 3, 4, 5, 6]:
			var buffer: PackedFloat32Array = data.buffers[slot]
			for i in buffer.size() / 12:
				positions[buffer[i * 12 + 3]] = true
		check("no tree lost or duplicated between levels", positions.size() == 1000)
		check("nearest tree receives full detail", data.buffers[0][3] == 0.0)
	var patch := SP.new()
	patch._ready()
	patch.bind_recipe(PlanetGenerator.recipe_for({"name": "Earth"}))
	check("imported tree crown and trunk surfaces", patch._prop_nodes[0].multimesh.mesh.get_surface_count() == 2)
	patch.free()
	print("surface_tree_lod: ", "OK" if failures == 0 else "FAIL %d" % failures)
	quit(0 if failures == 0 else 1)

func check(label: String, condition: bool) -> void:
	if not condition:
		failures += 1
		printerr("FAIL: ", label)
