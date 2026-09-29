class_name RenderStarBoot
extends Node3D
## Boots the real game, arrives in a generated system (STAR_SYSTEM, default
## proxima), turns the ship to face the primary star and captures it from the
## spawn point and from 3 star radii, printing the star body's material state.
## STAR_SHOT_DIR sets the output folder.

func _ready() -> void:
	ProfileDir.isolate("render_star_boot")
	get_window().size = Vector2i(1280, 720)
	var out := OS.get_environment("STAR_SHOT_DIR")
	if out.is_empty(): out = "/tmp/star-boot"
	var system := OS.get_environment("STAR_SYSTEM")
	if system.is_empty(): system = SystemDB.PROXIMA
	DirAccess.make_dir_recursive_absolute(out)
	var main: Node = load("res://scenes/Main.tscn").instantiate()
	add_child(main)
	for i in 30: await get_tree().process_frame
	main._arrive(system)
	for i in 10: await get_tree().process_frame
	var ship: Ship = main.ship
	ship._set_capture(false)
	var star: String = Ephemeris.primary_star
	print("star boot: system %s primary '%s' anchor %s" % [system, star, ship.anchor_name])
	for b in main.planets._bodies:
		if b.get("star", false):
			var m = b.get("mat")
			var info := "star boot: body '%s' r=%.0f sphere=%s mat=%s" % [b.name, float(b.radius), b.sphere != null, m]
			if m is ShaderMaterial:
				info += " kind=%s mode=%s color_a=%s brightness=%s" % [m.get_shader_parameter("kind"),
					m.get_shader_parameter("stellar_mode"), m.get_shader_parameter("color_a"), m.get_shader_parameter("stellar_brightness")]
			print(info)
	ship.velocity = Vector3.ZERO
	main._anchor_ship(star)
	var r := Ephemeris.body_radius_km(star)
	ship.relocate(Vector3(0, 0, r * 60.0))
	ship.face_toward(Vector3(0, 0, -1000.0))
	for i in 90: await get_tree().process_frame
	print("star boot: far view at %.0f km, sky impostor on: %s" % [ship.to_body(star).length(), Ephemeris.show_sky_impostor(ship.to_body(star).length(), r)])
	await _shot(out.path_join("far_disc.png"))
	ship.relocate(Vector3(0, 0, r * 3.0))
	ship.velocity = Vector3.ZERO
	ship.face_toward(Vector3(0, 0, -1000.0))
	for i in 90: await get_tree().process_frame
	await _shot(out.path_join("three_radii.png"))
	get_tree().quit(0)

func _shot(path: String) -> void:
	for i in 4: await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
	print("star boot: ", path)
