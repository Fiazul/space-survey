extends SceneTree
## Checks assets/modules/*.glb against docs/specs/2026-09-26-ship-roster-and-modules.md:
## the attach-convention empty on the right side of the origin, contract material names, tri budget.

const MATERIALS := ["Hull_Paint", "Hull_Dark", "Hull_Steel", "Glass", "Accent_Emit", "Nozzle_Emit"]
const MODULES := {
	"weapon_mk1": "MUZZLE", "weapon_mk2": "MUZZLE",
	"pad_mk1": "FOOT", "pad_mk2": "FOOT",
}
const TRI_BUDGET := 3000

var failures := 0

func _init() -> void:
	for module_name in MODULES:
		_check(module_name, MODULES[module_name])
	print("module_glbs: OK" if failures == 0 else "module_glbs: FAIL (%d)" % failures)
	quit(1 if failures else 0)

func _fail(message: String) -> void:
	failures += 1
	printerr("FAIL ", message)

func _check(module_name: String, empty_name: String) -> void:
	var path := "res://assets/modules/%s.glb" % module_name
	var packed := load(path) as PackedScene
	if packed == null:
		_fail("%s: not imported" % path)
		return
	var root := packed.instantiate() as Node3D
	var marker := root.find_child(empty_name, true, false) as Node3D
	if marker == null:
		_fail("%s: missing %s" % [module_name, empty_name])
	else:
		var at := _relative(marker, root).origin
		if empty_name == "MUZZLE" and not (at.z < 0.0):
			_fail("%s: MUZZLE z=%.3f, expected < 0" % [module_name, at.z])
		if empty_name == "FOOT" and not (at.y < 0.0):
			_fail("%s: FOOT y=%.3f, expected < 0" % [module_name, at.y])
		print("  %s %s at %s" % [module_name, empty_name, at])
	var tris := 0
	var used := {}
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var mesh := (mi as MeshInstance3D).mesh
		for s in mesh.get_surface_count():
			var arrays := mesh.surface_get_arrays(s)
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			tris += (indices.size() if indices.size() > 0 else (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()) / 3
			var material := mesh.surface_get_material(s)
			var material_name := material.resource_name if material else "<none>"
			used[material_name] = true
			if not material_name in MATERIALS:
				_fail("%s: material '%s' not in contract" % [module_name, material_name])
	if tris == 0 or tris > TRI_BUDGET:
		_fail("%s: %d tris (budget %d)" % [module_name, tris, TRI_BUDGET])
	print("  %s %d tris, materials %s" % [module_name, tris, ", ".join(PackedStringArray(used.keys()))])
	root.free()

func _relative(node: Node3D, root: Node3D) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var cursor: Node = node
	while cursor != root and cursor is Node3D:
		xf = (cursor as Node3D).transform * xf
		cursor = cursor.get_parent()
	return xf
