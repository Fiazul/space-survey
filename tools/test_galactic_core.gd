class_name TestGalacticCore
extends Node

var failures := 0

func check(label: String, ok: bool) -> void:
	if not ok:
		failures += 1
		push_error("galactic_core: " + label)

func _ready() -> void:
	ProfileDir.isolate("test_galactic_core")
	var row := SystemDB.star_row("sagittarius_a")
	check("Sagittarius A is a real destination", not row.is_empty())
	if row.is_empty():
		get_tree().quit(1)
		return
	check("core direction and distance", absf(SystemDB.coord("sagittarius_a").length() - 26673.0) < 1.0
		and absf(float(row.ra) - 266.41684) < .001 and absf(float(row.dec) + 29.00781) < .001)
	var main: Node = preload("res://scripts/core/main.gd").new()
	add_child(main)
	main.set_process(false)
	await get_tree().process_frame
	var panel: DevSitesPanel = main.dev_sites
	var key := InputEventKey.new()
	key.keycode = KEY_P
	key.ctrl_pressed = true
	key.pressed = true
	Input.parse_input_event(key)
	await get_tree().process_frame
	check("Ctrl+P opens the picker", panel._open)
	panel._filter.text = "galactic core"
	panel._refresh()
	await get_tree().process_frame
	var selected := false
	for button in panel._list.get_children():
		if button is Button and "Sagittarius" in button.text:
			button.pressed.emit()
			selected = true
			break
	check("real picker finds and reaches black hole", selected and main.current_system == "sagittarius_a")
	check("picker restores flight", not panel._open and not get_tree().paused)
	var ship: Ship = main.ship
	check("anchored to physical black hole", ship.anchor_name == "Sagittarius A*" and ship.nearest_name == "Sagittarius A*")
	var kerr: Dictionary = BlackHoleRecipe.resolve(row).stellar
	var a: float = kerr.spin
	var rg := 5.706634920774e17 / (BlackHoleRecipe.C_KM_S*BlackHoleRecipe.C_KM_S)
	var z1 := 1.0 + pow(1.0-a*a, 1.0/3.0)*(pow(1.0+a, 1.0/3.0) + pow(1.0-a, 1.0/3.0))
	var z2 := sqrt(3.0*a*a + z1*z1)
	check("Sgr A* spin a = 0.9", a == 0.9)
	check("gravitational radius GM/c^2", absf(kerr.gravitational_radius_km/rg - 1.0) < 1e-6)
	check("Kerr outer horizon", absf(kerr.horizon_km/(rg*(1.0 + sqrt(1.0-a*a))) - 1.0) < 1e-6)
	check("Bardeen prograde ISCO", absf(kerr.isco_km/(rg*(3.0 + z2 - sqrt((3.0-z1)*(3.0+z1+2.0*z2)))) - 1.0) < 1e-6
		and absf(kerr.isco_km/rg - 2.320883) < 1e-5)
	check("prograde photon orbit", absf(kerr.photon_sphere_km/(rg*2.0*(1.0 + cos(2.0/3.0*acos(-a)))) - 1.0) < 1e-6)
	check("retrograde photon orbit", absf(kerr.photon_orbit_retro_km/(rg*2.0*(1.0 + cos(2.0/3.0*acos(a)))) - 1.0) < 1e-6)
	check("marginally bound orbit", absf(kerr.marginally_bound_km/(rg*(2.0 - a + 2.0*sqrt(1.0-a))) - 1.0) < 1e-6)
	check("horizon angular velocity", absf(kerr.horizon_angular_velocity_rad_s/(a*BlackHoleRecipe.C_KM_S/(2.0*kerr.horizon_km)) - 1.0) < 1e-6)
	check("flow runs from the Kerr ISCO", absf(kerr.disk_inner_radii*rg/kerr.isco_km - 1.0) < 1e-6 and kerr.disk_outer_radii == 36.0)
	check("body radius is the Kerr horizon", absf(Ephemeris.body_radius_km(ship.anchor_name)/kerr.horizon_km - 1.0) < 1e-6)
	var hole_recipe := BlackHoleRecipe.resolve(row)
	var isco_period := TAU/BlackHoleRenderer.orbital_rate_rad_s(kerr, kerr.disk_inner_radii)
	check("ISCO lap at the true Kerr rate (~10 min)", isco_period > 540.0 and isco_period < 660.0
		and absf(isco_period/(TAU*(pow(kerr.disk_inner_radii, 1.5) + a)*rg/BlackHoleRecipe.C_KM_S) - 1.0) < 1e-9)
	var spots_now := BlackHoleRenderer.hotspots(hole_recipe, 1000.0, 0.0)
	var spots_later := BlackHoleRenderer.hotspots(hole_recipe, 1002.0, 0.0)
	check("hotspots are deterministic", spots_now == BlackHoleRenderer.hotspots(hole_recipe, 1000.0, 0.0))
	var lapping := false
	for i in spots_now.size():
		var spot: Vector4 = spots_now[i]
		var rate := fposmod(spots_later[i].y - spot.y, TAU)/2.0
		check("hotspot %d near the ISCO at its Kerr rate" % i, spot.x > kerr.disk_inner_radii and spot.x < 2.2*kerr.disk_inner_radii
			and absf(rate/BlackHoleRenderer.orbital_rate_rad_s(kerr, spot.x) - 1.0) < 1e-4)
		for other in spots_now:
			if other.x > spot.x + .5: lapping = true
	check("inner hotspots lap outer ones", lapping)
	var lapse := BlackHoleRenderer.TIME_LAPSE
	check("one sensor time-lapse keeps the ISCO lap at least 8 s on screen", isco_period/lapse >= 8.0)
	var first_flare := -1.0
	for second in range(0, 600):
		if BlackHoleRenderer.flare_level(hole_recipe, float(second)*lapse) > .5:
			first_flare = float(second)*lapse
			break
	print("galactic_core: first flare above half strength %.0f s after arrival on screen" % (first_flare/lapse))
	check("sensor-view flare within minutes of arrival", first_flare > 0.0 and first_flare/lapse < 300.0)
	check("flare lasts tens of minutes", BlackHoleRenderer.flare_level(hole_recipe, first_flare + 1200.0) > .1
		and BlackHoleRenderer.flare_level(hole_recipe, first_flare + 1800.0) > .05)
	var light_crossing := BlackHoleRenderer.light_crossing_s(kerr)
	var flicker := 0.0
	for step in 10:
		var t := first_flare + 300.0 + float(step)*light_crossing
		flicker = maxf(flicker, absf(BlackHoleRenderer.flare_level(hole_recipe, t + light_crossing) - BlackHoleRenderer.flare_level(hole_recipe, t)))
	check("flare varies on the GM/c^3 light-crossing scale", absf(light_crossing - 21.17) < .05 and flicker > .05)
	check("mass drives existing gravity", absf(Ephemeris.gm(ship.anchor_name) / 5.706634920774e17 - 1.0) < .0001)
	check("close view is 7.9 AU", absf(ship.anchor_off.length() / 149597870.7 - 7.9) < .001)
	check("orbital arrival", absf(ship.velocity.dot(ship.anchor_off.normalized())) < .01
		and ship.velocity.is_equal_approx(Ephemeris.circular_velocity(ship.anchor_name, ship.anchor_off, ship.velocity)))
	check("no invented planets around event horizon", Ephemeris.live_worlds().all(func(b): return b.get("star", false)))
	var recipe: Dictionary = main.planets.stellar_recipe_for("Sagittarius A*")
	check("black hole has no photosphere flux", recipe.stellar.type == "black_hole" and recipe.stellar.luminosity_solar == 0.0)
	check("horizon telemetry has no photosphere", StarRecipe.exposure(recipe, kerr.horizon_km*1.02, kerr.horizon_km).state == "EVENT HORIZON")
	main.planets.refresh(Vector3(kerr.horizon_km*1.02,0,0), 0.0, "Sagittarius A*")
	check("near-horizon warning outranks distant star flux", main.planets.stellar_hazard.name == "Sagittarius A*" and main.planets.stellar_hazard.state == "EVENT HORIZON")
	main.planets.refresh(ship.anchor_off, 0.0, ship.anchor_name)
	check("navigation sees black hole", "Sagittarius A*" in main.planets.targetables())
	var cluster: Dictionary = Ephemeris.live_worlds().filter(func(b): return b.name != "Sagittarius A*")[0]
	check("cluster stars are real navigation targets", cluster.name in main.planets.targetables() and Ephemeris.is_anchorable(cluster.name))
	check("cluster star shares stellar recipes", main.planets.stellar_recipe_for(cluster.name).stellar.temperature_k > 0.0)
	var info: PlanetInfo = main.planet_info
	info.open_for("Sagittarius A*")
	check("scan identifies event horizon", "Black Hole" in info._title.text)
	info._close()
	var hole_material: ShaderMaterial = main.planets._bodies.filter(func(b): return b.name == "Sagittarius A*")[0].mat
	var start_time := float(hole_material.get_shader_parameter("sim_time"))
	ship.systems.gear_target = false
	ship.systems.gear_fraction = 0.0
	ship._time_idx = 4
	ship.time_rate = 100.0
	main._process(.01)
	check("accretion rotation follows accelerated simulation time",float(hole_material.get_shader_parameter("sim_time"))-start_time > .9)
	ship._time_idx = 0
	ship.time_rate = 1.0
	var park := ship.anchor_off.length()
	var orbital_speed := ship.velocity.length()
	for i in 600: main._process(1.0 / 60.0)
	check("live inspection preserves orbital speed", absf(ship.velocity.length()/orbital_speed - 1.0) < .005)
	check("inspection orbit survives live physics", not main._skin_dying and absf(ship.anchor_off.length()/park - 1.0) < .005)
	main._save_profile()
	var cfg := ConfigFile.new()
	check("save records physical anchor", cfg.load(GameState.profile_path()) == OK
		and cfg.get_value("player", "anchor", "") == "Sagittarius A*")
	check("return to Sol works", panel.go_system("sol") and Ephemeris.system_id == "sol" and ship.anchor_name == "Sun")
	check("repeat visit works", panel.go_system("sagittarius_a"))
	main._anchor_ship(cluster.name)
	ship.relocate(Ephemeris.sweet_spot_off(cluster.name))
	main._process(0.0)
	check("flight can resolve a cluster star", main.planets.nearest_name == cluster.name and main.planets._bodies.any(func(b): return b.name == cluster.name and b.sphere.visible))
	panel.go_core({"au": 79.0, "polar": false})
	var saved_off := ship.anchor_off
	main._save_profile()
	main.queue_free()
	await get_tree().process_frame
	main = preload("res://scripts/core/main.gd").new()
	add_child(main)
	main.set_process(false)
	await get_tree().process_frame
	check("79 AU inspection restores exact anchor offset", main.ship.anchor_name == "Sagittarius A*" and main.ship.anchor_off.is_equal_approx(saved_off))
	main.dev_sites.go_core({"ly": 500.0, "polar": false})
	main._process(0.0)
	check("overview culls unresolved hole", not main.planets._bodies.filter(func(b): return b.name == "Sagittarius A*")[0].sphere.visible)
	check("overview suspends lens background", main.planets.black_hole_background == null or main.planets.black_hole_background.viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED)
	var points := GalacticCore.samples()
	var central := 0
	var outer := 0
	for position in points.positions:
		if position.length() < 1.0: central += 1
		if position.length() >= 1.0 and position.length() < 10.0: outer += 1
	check("stellar volume density rises inward", central > 50 and float(central) > float(outer)/999.0 * 10.0)
	main.dev_sites.go_core({"au": 7.9, "polar": false})
	var horizon := Ephemeris.body_radius_km("Sagittarius A*")
	main.ship.relocate(Vector3(horizon*1.01,0,0))
	main.ship.velocity = Vector3.ZERO
	main._process(0.0)
	check("outside horizon remains flyable", not main._skin_dying and main.black_hole_portal == null)
	main.ship.relocate(Vector3(horizon*.99,0,0))
	main._process(0.0)
	check("crossing horizon opens the arcade without losing the hull", main.black_hole_portal != null and not main._skin_dying and not main.ship.locked)
	main.dev_sites.go_core({"au": 79.0, "polar": false})
	check("Ctrl+P jump cancels the portal", main.black_hole_portal == null and not main._skin_dying and not main.ship.locked)
	main._process(3.0)
	check("a cancelled portal cannot overwrite a selected view", absf(main.ship.anchor_off.length()/Ephemeris.KM_PER_AU-79.0) < .01)
	main.dev_sites.go_system("sol")
	main.dev_sites.go_core({"au": 7.9, "polar": false})
	main.ship.relocate(Vector3(Ship.HOLE_CAPTURE_AU*Ephemeris.KM_PER_AU*1.1,0,0))
	main.ship.velocity = Ephemeris.circular_velocity("Sagittarius A*", main.ship.anchor_off, Vector3.UP)
	main.ship._newton_advance(100000.0/60.0)
	check("curved exterior substeps do not falsely cross horizon", not main.ship.horizon_crossed)
	main.ship.relocate(Vector3(horizon*3.0,0,0))
	main.ship.velocity = Vector3(-horizon*6.0,0,0)
	main._process(1.0)
	check("fast flight through horizon opens the portal even when ending outside", main.black_hole_portal != null and not main.ship.locked)
	if main.black_hole_portal != null:
		main.black_hole_portal.return_to_ship()
		check("arcade exit returns to a safe 2 AU orbital park", main.black_hole_portal == null and not main.ship.locked
			and absf(main.ship.anchor_off.length()/Ephemeris.KM_PER_AU - 2.0) < .00001 and main.ship.velocity.length() > 10000.0)
	main.queue_free()
	await get_tree().process_frame
	print("galactic_core: ", "OK" if failures == 0 else "FAIL %d" % failures)
	get_tree().quit(1 if failures else 0)
