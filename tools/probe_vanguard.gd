extends SceneTree
# Build the ship the way Ship._build_ship_model does and report what each surface
# actually ends up with. Texture bindings alone cannot establish correct shading;
# the render harness also checks the visible hull and exhaust.
const SM := preload("res://scripts/flight/ship_mesh.gd")
const PATH := "res://assets/vanguard/vanguard.obj"


func _initialize() -> void:
	print("probe_vanguard: preloaded diffuse = %s" % SM.VANGUARD_DIFFUSE)
	print("probe_vanguard: diffuse size = %s" % str(SM.VANGUARD_DIFFUSE.get_size()))
	var mesh := load(PATH) as Mesh
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	var model: Node3D = mi
	var driven := SM.style_vanguard(model)
	print("probe_vanguard: style_vanguard returned %d propulsion materials" % driven.size())
	for si in mesh.get_surface_count():
		var m := mi.get_surface_override_material(si)
		var name: String = mesh.surface_get_name(si)
		if m == null:
			print("probe_vanguard: surface %d '%s' -> NO OVERRIDE" % [si, name])
			continue
		var std := m as StandardMaterial3D
		if std == null:
			print("probe_vanguard: surface %d '%s' -> %s" % [si, name, m.get_class()])
			continue
		print("probe_vanguard: surface %d '%s' -> albedo_tex %s  metallic %.2f  metal_tex %s  rough_tex %s  emis %s  next_pass %s"
			% [si, name,
			"SET" if std.albedo_texture != null else "NULL",
			std.metallic,
			"SET" if std.metallic_texture != null else "NULL",
			"SET" if std.roughness_texture != null else "NULL",
			"SET" if std.emission_texture != null else "NULL",
			"yes" if std.next_pass != null else "no"])
	model.free()
	quit(0)
