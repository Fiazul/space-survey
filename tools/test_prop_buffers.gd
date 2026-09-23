class_name TestPropBuffers
extends SceneTree
# GPU buffer roundtrip requires a real GL/Vulkan renderer; dummy headless storage
# returns identity transforms for bulk uploads. Run under xvfb with compatibility.
func _initialize() -> void:
	if DisplayServer.get_name() == "headless":
		print("prop_buffers: SKIP GPU roundtrip (run xvfb-run -a godot --rendering-method gl_compatibility --script tools/test_prop_buffers.gd)")
		quit(0)
		return
	var expected := Transform3D(Basis(Vector3(0.2, 0.8, 0.3).normalized(), 0.7).scaled_local(Vector3(2, 3, 4)), Vector3(123.0, -45.0, 678.0))
	var packed := SurfacePatch.pack_prop_buffers([expected, expected], PackedByteArray([2, 3]), Vector3.ZERO, Vector3.RIGHT, Vector3.FORWARD, 2, "tree")
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = BoxMesh.new()
	mm.instance_count = 2
	mm.buffer = packed.buffers[2]
	var ok := mm.get_instance_transform(0).is_equal_approx(expected) and mm.get_instance_transform(1).is_equal_approx(expected)
	ok = ok and mm.get_instance_custom_data(0).r == 0.0 and mm.get_instance_custom_data(1).r == 1.0
	if not ok:
		print("expected ", expected, " got ", mm.get_instance_transform(0), " customs ", mm.get_instance_custom_data(0), " ", mm.get_instance_custom_data(1))
	print("prop_buffers: ", "OK" if ok else "FAIL")
	quit(0 if ok else 1)
