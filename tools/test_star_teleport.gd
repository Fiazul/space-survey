class_name TestStarTeleport
extends Node

var failures := 0
const AUTHORED_STARS := {
	"arcturus": ["Arcturus", "giant", 25.4 * 695700.0, 4286.0, 1.08],
	"aldebaran": ["Aldebaran", "giant", 44.0 * 695700.0, 3900.0, 1.2],
	"vela_pulsar": ["Vela Pulsar", "pulsar", 12.0, 600000.0, 1.4],
	"crab_pulsar": ["Crab Pulsar", "pulsar", 12.0, 600000.0, 1.4],
}

func check(label: String, ok: bool) -> void:
	if not ok:
		failures += 1
		push_error("star_teleport: "+label)

func _ready() -> void:
	ProfileDir.isolate("test_star_teleport")
	_metadata_boundaries()
	var main: Node = preload("res://scripts/core/main.gd").new()
	add_child(main)
	main.set_process(false)
	await get_tree().process_frame
	var panel: DevSitesPanel = main.dev_sites
	var ship: Ship = main.ship
	check("picker includes every catalogue destination", panel.system_ids().size() == SystemDB.all().size())
	for id in AUTHORED_STARS:
		check("authored destination available "+id, id in panel.system_ids())
	for query in ["red giant", "neutron", "pulsar", "arcturus", "vela_pulsar"]:
		panel._open_panel()
		panel._filter.text = query
		panel._refresh()
		await get_tree().process_frame
		var names := []
		for row in panel._list.get_children():
			if row is Button: names.append(row.text)
		var expected: Array = ["Arcturus", "Aldebaran"] if query == "red giant" else ["Vela Pulsar", "Crab Pulsar"]
		if query == "arcturus": expected = ["Arcturus"]
		if query == "vela_pulsar": expected = ["Vela Pulsar"]
		for name in expected:
			check("picker filter %s includes %s" % [query, name], names.any(func(label): return name in label))
		if query == "red giant": check("red giant excludes dwarfs", not names.any(func(label): return "Sun" in label or "Proxima" in label))
		var pressed := false
		for row in panel._list.get_children():
			if row is Button:
				row.pressed.emit()
				pressed = true
				break
		check("filtered star button arrives "+query, pressed and ship.anchor_name in expected and not panel._open and not get_tree().paused)
		panel._close()
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
		var expected_park := maxf(4.0 * radius, pow(Ephemeris.gm(star) * pow(60.0 / TAU, 2.0), 1.0 / 3.0))
		check("safe stellar park "+id, is_equal_approx(ship.anchor_off.length(), expected_park))
		if id in ["sol", "proxima", "gliese_440"]:
			check("ordinary and white dwarf arrival retain four radii "+id, is_equal_approx(ship.anchor_off.length()/radius, 4.0))
		check("camera faces star "+id, (-ship.basis.z).dot(ship.to_body(star).normalized()) > .999)
		check("arrival velocity is circular orbit "+id, absf(ship.velocity.dot(ship.anchor_off.normalized())) < .001
			and is_equal_approx(ship.velocity.length_squared(),Ephemeris.gm(star)/ship.anchor_off.length()))
		check("old flight state cleared "+id, ship.time_rate == 1.0 and not ship.auto_cruise and not ship.autopilot)
		var recipe: Dictionary = main.planets.stellar_recipe_for(star)
		check("stellar recipe loaded "+id, not recipe.is_empty() and recipe.name == star)
		var visible_star: MeshInstance3D = main.planets._sun_sky
		var primary_body: Dictionary = {}
		for body in main.planets._bodies:
			if body.name == star:
				primary_body = body
				if body.sphere.visible: visible_star = body.sphere
		check("resolved stellar park has no point glare "+id,
			atan(radius / ship.anchor_off.length()) < .001 or not primary_body.dot.visible)
		if id in ["vela_pulsar", "crab_pulsar"]:
			check("unresolved neutron park has point glare "+id, primary_body.dot.visible)
			check("point glare keeps depth occlusion "+id, not primary_body.dot.no_depth_test)
			check("point glare retains physical sphere radius "+id, is_equal_approx(primary_body.sphere.mesh.radius, radius))
		check("star renderer visible "+id, visible_star.visible)
		var material: ShaderMaterial = visible_star.material_override
		check("visible renderer uses selected recipe "+id,
			is_equal_approx(float(material.get_shader_parameter("seed")), float(recipe.seed))
			and is_equal_approx(float(material.get_shader_parameter("stellar_temperature_k")), float(recipe.stellar.temperature_k)))
		if AUTHORED_STARS.has(id):
			var expected: Array = AUTHORED_STARS[id]
			var specs := SystemDB.bodies(id)
			var star_spec: Dictionary = specs.filter(func(body): return body.name == star)[0]
			var spec_recipe := PlanetGenerator.recipe_for(star_spec)
			check("body spec matches live authored recipe "+id, spec_recipe.stellar == recipe.stellar)
			check("authored metadata retained in body spec "+id, star_spec.get("stellar", {}) == SystemDB.star_row(id).get("stellar", {}) and star_spec.get("stellar_type", "") == SystemDB.star_row(id).get("stellar_type", ""))
			check("authored live family "+id, recipe.stellar.type == expected[1])
			check("authored physical radius "+id, is_equal_approx(radius, expected[2]) and is_equal_approx(recipe.stellar.radius_km, expected[2]))
			check("authored temperature "+id, is_equal_approx(recipe.stellar.temperature_k, expected[3]))
			check("authored gravity mass "+id, is_equal_approx(Ephemeris.gm(star), expected[4] * 132712440018.0))
			check("authored visible material temperature "+id, is_equal_approx(float(material.get_shader_parameter("stellar_temperature_k")), expected[3]))
			if expected[1] == "pulsar":
				check("neutron surface reaches material "+id, recipe.stellar.mode == 3 and int(material.get_shader_parameter("stellar_mode")) == 3)
				check("bare visible neutron core "+id, recipe.stellar.visual.sensor_mode == "visible" and not recipe.stellar.visual.wind_nebula)
		var saved := ConfigFile.new()
		check("stellar profile readable "+id, saved.load(GameState.profile_path()) == OK)
		check("save records star park "+id, str(saved.get_value("player","anchor","")) == star
			and (saved.get_value("player","off",Vector3.ZERO) as Vector3).distance_to(ship.anchor_off) < .1)
		check("save records orbital velocity "+id, (saved.get_value("player", "star_velocity", Vector3.ZERO) as Vector3).is_equal_approx(ship.velocity))
		print("star_teleport: checked ", id, " -> ", star)
	_glare_boundaries(main)
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
	for id in ["vela_pulsar", "crab_pulsar"]:
		if SystemDB.star_row(id).is_empty(): continue
		for fps in [60, 4]:
			check("neutron jump accepted "+id, main.dev_sites.go_system(id))
			_fly_orbit(main, id, fps)
			ship = main.ship
			var saved_off: Vector3 = ship.anchor_off
			var saved_velocity: Vector3 = ship.velocity
			main._save_profile()
			var saved := ConfigFile.new()
			check("neutron profile readable", saved.load(GameState.profile_path()) == OK)
			check("neutron saved anchor "+id, saved.get_value("player", "anchor", "") == AUTHORED_STARS[id][0])
			check("neutron saved position "+id, (saved.get_value("player", "off", Vector3.ZERO) as Vector3).is_equal_approx(saved_off))
			check("neutron saved velocity "+id, (saved.get_value("player", "star_velocity", Vector3.ZERO) as Vector3).is_equal_approx(saved_velocity))
			main.queue_free()
			await get_tree().process_frame
			main = preload("res://scripts/core/main.gd").new()
			add_child(main)
			main.set_process(false)
			await get_tree().process_frame
			ship = main.ship
			check("neutron reload system "+id, main.current_system == id and ship.anchor_name == AUTHORED_STARS[id][0])
			check("neutron reload position and velocity "+id, ship.anchor_off.is_equal_approx(saved_off) and ship.velocity.is_equal_approx(saved_velocity))
			check("neutron reload circular velocity "+id, absf(ship.velocity.length_squared() / (Ephemeris.gm(ship.anchor_name)/ship.anchor_off.length()) - 1.0) < .02)
			_fly_orbit(main, id, fps)
	main.queue_free()
	await get_tree().process_frame
	print("star_teleport: ", "OK" if failures == 0 else "FAIL %d" % failures)
	get_tree().quit(1 if failures else 0)


func _glare_boundaries(main: Node) -> void:
	main.dev_sites.go_system("vela_pulsar")
	var planets: PlanetSystem = main.planets
	var body: Dictionary = planets._bodies.filter(func(b): return b.name == "Vela Pulsar")[0]
	var radius: float = body.radius
	var recipe: Dictionary = body.recipe
	var original_recipe := recipe.duplicate(true)
	planets.refresh(Vector3(0, 0, radius * 500.0), 0.0, body.name)
	check("resolved core disables point glare", not body.dot.visible)
	planets.refresh(Vector3(0, 0, radius * 2000.0), 0.0, body.name)
	check("unresolved core enables point glare", body.dot.visible)
	var diameter: float = body.dot.pixel_size * body.dot.texture.get_width() / body.dot.position.length()
	check("point glare has small angular diameter", diameter >= .008 and diameter <= .012)
	planets.refresh(Vector3(0, 0, radius * 4000.0), 0.0, body.name)
	check("point glare preserves angle as distance changes", is_equal_approx(
		body.dot.pixel_size * body.dot.texture.get_width() / body.dot.position.length(), diameter))
	var far_distance := Ephemeris.CAM_FAR_SOL * 2.0
	planets.refresh(Vector3(0, 0, far_distance), 0.0, body.name)
	check("far point glare uses the shared sky shell", body.dot.visible
		and is_equal_approx(body.dot.position.length(), Ephemeris.sky_impostor_km(far_distance)))
	check("far point glare preserves angle", is_equal_approx(
		body.dot.pixel_size * body.dot.texture.get_width() / body.dot.position.length(), diameter))
	check("point glare keeps recipe and true radius", body.recipe == original_recipe
		and body.radius == radius and is_equal_approx(body.sphere.mesh.radius, radius))
	for option in ["wind_nebula", "debris_disk"]:
		body.recipe = recipe.duplicate(true)
		body.recipe.stellar.visual[option] = true
		planets.refresh(Vector3(0, 0, far_distance), 0.0, body.name)
		check("authored "+option+" excludes point fallback", not body.dot.visible)
	body.recipe = recipe


func _fly_orbit(main: Node, id: String, fps: int) -> void:
	var ship: Ship = main.ship
	var star: String = AUTHORED_STARS[id][0]
	var park_radius := ship.anchor_off.length()
	var max_error := 0.0
	var stayed_alive := true
	var stayed_anchored := true
	for i in 30 * fps:
		main._process(1.0 / fps)
		max_error = maxf(max_error, absf(ship.anchor_off.length()/park_radius - 1.0))
		stayed_alive = stayed_alive and not main._skin_dying and not ship.locked
		stayed_anchored = stayed_anchored and ship.anchor_name == star and ship.nearest_name == star
	check("neutron 30s flight alive %s at %dfps" % [id, fps], stayed_alive)
	check("neutron 30s flight no reanchor %s at %dfps" % [id, fps], stayed_anchored)
	check("neutron orbit stays within 2pct %s at %dfps" % [id, fps], max_error < .02)
	print("star_teleport: %s 30s at %dfps max orbit error %.4f%%" % [id, fps, max_error * 100.0])


func _metadata_boundaries() -> void:
	var rows := SystemDB._rows()
	for fixture in [{"spectral": "B2III"}, {"spectral": "C5"}, {"spectral": "G2V"}, {"spectral": "K3III", "stellar": {"temperature_k": 9000.0}}]:
		rows["family_label_fixture"] = fixture
		check("hot giants, carbon stars and dwarfs are not red giants "+str(fixture), SystemDB.family_label("family_label_fixture") != "Red Giant")
	rows.erase("family_label_fixture")
	# Both boundaries must retain optional authored visuals without aliasing the catalog.
	var row := {"name": "Metadata fixture", "spectral": "REMNANT", "stellar_type": "pulsar",
		"stellar": {"temperature_k": 700000.0, "visual": {"sensor_mode": "xray", "wind_nebula": true, "wind_extent_radii": 1000.0}}}
	var generated := GeneratedEphemeris.build("metadata_fixture", row, 1.8e9)
	var star: Dictionary = generated.live_worlds()[0]
	check("generated preserves stellar_type", star.get("stellar_type", "") == "pulsar")
	var generated_metadata: Dictionary = star.get("stellar", {})
	check("generated preserves nested authored visuals", generated_metadata == row.stellar)
	var specs := SystemDB.sol_from(generated.live_worlds())
	var spec: Dictionary = specs[0]
	check("body spec preserves stellar_type", spec.get("stellar_type", "") == "pulsar")
	check("body spec preserves nested authored visuals", spec.get("stellar", {}) == row.stellar)
	var recipe := PlanetGenerator.recipe_for(spec)
	check("authored visual reaches shared recipe", recipe.stellar.type == "pulsar" and recipe.stellar.visual.sensor_mode == "xray" and recipe.stellar.visual.wind_nebula)
	if spec.has("stellar") and spec.stellar.has("visual"):
		spec.stellar.visual.sensor_mode = "visible"
		check("body metadata is independently mutable", generated_metadata.visual.sensor_mode == "xray")
	if generated_metadata.has("visual"):
		generated_metadata.visual.sensor_mode = "uv"
		check("generated metadata is independently mutable", row.stellar.visual.sensor_mode == "xray")
	row.stellar.temperature_k = 800000.0
	check("builder snapshots nested authored metadata", generated.star_row.stellar.temperature_k == 700000.0)
