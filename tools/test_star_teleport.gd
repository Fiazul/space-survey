class_name TestStarTeleport
extends Node

var failures := 0

func check(label: String, ok: bool) -> void:
	if not ok:
		failures += 1
		push_error("star_teleport: "+label)

func _ready() -> void:
	ProfileDir.isolate("test_star_teleport")
	var main: Node = preload("res://scripts/core/main.gd").new()
	add_child(main)
	main.set_process(false)
	await get_tree().process_frame
	var panel: DevSitesPanel = main.dev_sites
	var ship: Ship = main.ship
	check("picker includes every catalogue destination", panel.system_ids().size() == SystemDB.all().size())
	# Use the real picker button for the reported Proxima failure.
	panel._open_panel()
	panel._filter.text = "proxima"
	panel._refresh()
	await get_tree().process_frame
	var selected := false
	for row in panel._list.get_children():
		if row is Button:
			row.pressed.emit()
			selected = true
			break
	check("Proxima button selected", selected)
	check("picker closes after arrival", not panel._open and not get_tree().paused)
	check("Proxima button arrives at star", ship.anchor_name == "Proxima Centauri" and ship.nearest_name == "Proxima Centauri")
	for id in panel.system_ids():
		ship.velocity = Vector3(10,20,30)
		ship.time_rate = 100.0
		ship.auto_cruise = true
		check("jump accepted "+id, panel.go_system(id))
		var star := Ephemeris.primary_star
		var radius := Ephemeris.body_radius_km(star)
		check("system read-back "+id, main.current_system == id and Ephemeris.system_id == id)
		check("anchor is primary star "+id, ship.anchor_name == star and Ephemeris.is_star(ship.anchor_name))
		check("nearest read-back is star "+id, ship.nearest_name == star and main.planets.nearest_name == star)
		check("safe stellar park "+id, is_equal_approx(ship.anchor_off.length()/radius, 4.0))
		check("camera faces star "+id, (-ship.basis.z).dot(ship.to_body(star).normalized()) > .999)
		check("arrival velocity is circular orbit "+id, absf(ship.velocity.dot(ship.anchor_off.normalized())) < .001
			and is_equal_approx(ship.velocity.length_squared(),Ephemeris.gm(star)/ship.anchor_off.length()))
		check("old flight state cleared "+id, ship.time_rate == 1.0 and not ship.auto_cruise and not ship.autopilot)
		var recipe: Dictionary = main.planets.stellar_recipe_for(star)
		check("stellar recipe loaded "+id, not recipe.is_empty() and recipe.name == star)
		var visible_star: MeshInstance3D = main.planets._sun_sky
		for body in main.planets._bodies:
			if body.name == star and body.sphere.visible:
				visible_star = body.sphere
		check("star renderer visible "+id, visible_star.visible)
		var material: ShaderMaterial = visible_star.material_override
		check("visible renderer uses selected recipe "+id,
			is_equal_approx(float(material.get_shader_parameter("seed")), float(recipe.seed))
			and is_equal_approx(float(material.get_shader_parameter("stellar_temperature_k")), float(recipe.stellar.temperature_k)))
		var saved := ConfigFile.new()
		saved.load(GameState.profile_path())
		check("save records star park "+id, str(saved.get_value("player","anchor","")) == star
			and (saved.get_value("player","off",Vector3.ZERO) as Vector3).distance_to(ship.anchor_off) < .1)
		print("star_teleport: checked ", id, " -> ", star)
	panel.go_system("gliese_440")
	var park_radius := ship.anchor_off.length()
	for i in 1800: main._process(1.0/60.0)
	check("white dwarf arrival stays outside photosphere during live flight", ship.anchor_name == "Gliese 440"
		and absf(ship.anchor_off.length()/park_radius-1.0) < .02)
	var final_id: String = main.current_system
	check("current star can be revisited", panel.go_system(final_id))
	main._set_docked(true)
	check("same-system star jump undocks", panel.go_system(final_id) and not main.docked and not ship.frozen)
	main.start_teleport(SystemDB.SOL,"test pending return",100.0)
	check("star jump cancels pending ritual", panel.go_system(final_id) and not main._tp_active and not ship.frozen)
	var before := ship.anchor_off
	check("unknown star is refused without moving", not panel.go_system("unknown-star") and ship.anchor_off == before and main.current_system == final_id)
	panel._open_panel()
	panel._filter.text = SystemDB.display_name(final_id)
	panel._refresh()
	await get_tree().process_frame
	for row in panel._list.get_children():
		if row is Button: check("current star row remains enabled", not row.disabled)
	panel._close()
	main.queue_free()
	await get_tree().process_frame
	main = preload("res://scripts/core/main.gd").new()
	add_child(main)
	main.set_process(false)
	await get_tree().process_frame
	ship = main.ship
	check("stellar save restores orbital velocity", ship.anchor_name == "Gliese 440"
		and is_equal_approx(ship.velocity.length_squared(),Ephemeris.gm("Gliese 440")/ship.anchor_off.length()))
	park_radius = ship.anchor_off.length()
	for i in 1800: main._process(1.0/60.0)
	check("restored white dwarf orbit stays outside photosphere", ship.anchor_name == "Gliese 440"
		and absf(ship.anchor_off.length()/park_radius-1.0) < .02)
	main.queue_free()
	await get_tree().process_frame
	print("star_teleport: ", "OK" if failures == 0 else "FAIL %d" % failures)
	get_tree().quit(1 if failures else 0)
