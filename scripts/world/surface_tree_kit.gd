class_name SurfaceTreeKit
extends RefCounted
## Imported oak/pine detail levels, normalized to a 30 m base in kilometer units.
const FILES := ["pine_a", "oak_a", "pine_a_lod1", "oak_a_lod1", "pine_a_bb", "oak_a_bb"]
const FULL_MAX := 64
const MEDIUM_MAX := 512
const FULL_REACH := .12
const MEDIUM_REACH := .60
var materials: Array[ShaderMaterial] = []

func mesh(level_species: int) -> ArrayMesh:
	var scene: PackedScene = load("res://assets/nature/reclaimed/%s.glb" % FILES[level_species])
	var root := scene.instantiate()
	var pieces := []
	_collect(root, Transform3D.IDENTITY, pieces)
	var bounds := AABB()
	var first := true
	for piece in pieces:
		var box: AABB = piece[1] * piece[0].get_aabb()
		bounds = box if first else bounds.merge(box)
		first = false
	var factor := .03 / bounds.size.y
	var normalizer := Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * factor), Vector3(0, -bounds.position.y * factor, 0))
	var result := ArrayMesh.new()
	for piece in pieces:
		var source: Mesh = piece[0]
		for surface in source.get_surface_count():
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			st.append_from(source, surface, normalizer * piece[1])
			var original := source.surface_get_material(surface) as StandardMaterial3D
			var mat := ShaderMaterial.new()
			mat.shader = preload("res://shaders/surface_tree.gdshader")
			mat.set_shader_parameter("albedo_map", original.albedo_texture)
			mat.set_shader_parameter("tint", original.albedo_color)
			mat.set_shader_parameter("foliage", 1.0 if original.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED else 0.0)
			mat.set_shader_parameter("far_card", 1.0 if level_species >= 4 else 0.0)
			st.set_material(mat)
			st.commit(result)
			materials.append(mat)
	root.free()
	return result

func _collect(node: Node, parent: Transform3D, pieces: Array) -> void:
	var xf: Transform3D = parent * node.transform if node is Node3D else parent
	if node is MeshInstance3D and node.mesh != null:
		pieces.append([node.mesh, xf])
	for child in node.get_children():
		_collect(child, xf, pieces)

func set_parameter(key: String, value: Variant) -> void:
	for mat in materials:
		mat.set_shader_parameter(key, value)
