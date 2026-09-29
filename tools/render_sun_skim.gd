class_name RenderSunSkim
extends Node3D
## Boots the real game and parks the ship 916,780 km from the Sun's centre looking
## along the limb (the 2026-09-29 19:16 screenshot). Captures the view at the game
## far plane, at a huge far plane, and with the corona hidden, so a straight cut in
## the glow can be attributed. SUN_SKIM_DIR sets the output folder.

func _ready() -> void:
	ProfileDir.isolate("render_sun_skim")
	get_window().size = Vector2i(1280, 720)
	var out := OS.get_environment("SUN_SKIM_DIR")
	if out.is_empty(): out = "/tmp/sun-skim"
	DirAccess.make_dir_recursive_absolute(out)
	var main: Node = load("res://scenes/Main.tscn").instantiate()
	add_child(main)
	for i in 30: await get_tree().process_frame
	var ship: Ship = main.ship
	ship._set_capture(false)
	main._anchor_ship("Sun")
	ship.relocate(Vector3(916780.0, 0.0, 0.0))
	ship.velocity = Vector3.ZERO
	var view := Vector3(-sin(deg_to_rad(20.0)), 0.0, cos(deg_to_rad(20.0)))
	ship.face_toward(view * 1000.0)
	for i in 150: await get_tree().process_frame
	var far_game: float = ship.camera.far
	print("sun skim: camera near %.3f far %.0f fov %.1f anchor %s alt %.0f" % [
		ship.camera.near, far_game, ship.camera.fov, ship.anchor_name, ship.anchor_off.length() - Ephemeris.SUN_RADIUS_KM])
	await _shot(out.path_join("game_far.png"))
	var coronas := _find_coronas(main)
	for c in coronas:
		var m: ShaderMaterial = c.material_override
		print("sun skim: corona %s visible %s scale %s parent_scale %s strength %s extent %s" % [
			c.get_parent().name, c.is_visible_in_tree(), c.scale, c.get_parent().scale,
			m.get_shader_parameter("strength"), m.get_shader_parameter("extent")])
	for c in coronas:
		var m: ShaderMaterial = c.material_override
		m.set_shader_parameter("strength", float(m.get_shader_parameter("strength")) * 8.0)
	await _shot(out.path_join("strength_x8.png"))
	for c in coronas:
		var m: ShaderMaterial = c.material_override
		m.set_shader_parameter("strength", float(m.get_shader_parameter("strength")) / 8.0)
	var hidden := []
	for n in main.find_children("*", "GeometryInstance3D", true, false):
		if n in coronas or (n is MeshInstance3D and coronas.any(func(c): return c.get_parent() == n)):
			continue
		if (n as Node3D).visible:
			n.visible = false
			hidden.append(n)
	await _shot(out.path_join("sun_only.png"))
	for n in hidden: n.visible = true
	print("sun skim: hid %d other geometry nodes" % hidden.size())
	for c in coronas: c.visible = false
	await _shot(out.path_join("no_corona.png"))
	for c in coronas: c.visible = true
	print("sun skim: coronas hidden %d" % coronas.size())
	# 0.016 AU: the ball is off and the sky-disc impostor carries the Sun.
	ship.relocate(Vector3(2.4e6, 0.0, 0.0))
	ship.velocity = Vector3.ZERO
	ship.face_toward(Vector3(-1000.0, 0.0, 0.0))
	for i in 120: await get_tree().process_frame
	await _shot(out.path_join("impostor_0016au.png"))
	get_tree().quit(0)

func _shot(path: String) -> void:
	for i in 4: await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
	print("sun skim: ", path)

func _find_coronas(root: Node) -> Array:
	var found := []
	for n in root.find_children("*", "MeshInstance3D", true, false):
		var m := (n as MeshInstance3D).material_override
		if m is ShaderMaterial and (m as ShaderMaterial).shader != null \
				and (m as ShaderMaterial).shader.resource_path.ends_with("stellar_corona.gdshader"):
			found.append(n)
	return found
