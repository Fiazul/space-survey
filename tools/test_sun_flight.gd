extends Node3D
var failures := 0

class SunWorld extends PlanetSystem:
	func _ready() -> void:
		_dot_tex = _make_dot_texture()
		load_system([{"name":"Sun","star":true,"physical":true,"live":true,
			"radius":695700.0,"color":Color.WHITE}])

class Controller extends Node3D:
	var ship: Ship
	var planets: PlanetSystem
	func _anchor_ship(body: String) -> void:
		ship.set_anchor(body)

func _ready() -> void:
	var controller := Controller.new()
	add_child(controller)
	var ship := Ship.new()
	controller.ship = ship
	controller.add_child(ship)
	ship.set_physics_process(false)
	ship.newton = true
	ship._set_capture(false)
	var planets := SunWorld.new()
	controller.planets = planets
	controller.add_child(planets)
	var panel := DevSitesPanel.new()
	panel.ship = ship
	panel.main = controller
	controller.add_child(panel)
	ship.nearest_name = "Earth"
	ship.nearest_dist = 6372
	ship._time_idx = 4
	ship.time_rate = 100
	ship.autopilot = true
	ship.auto_cruise = true
	panel.go({"name":"Sun park","body":"Sun","mode":"park"})
	check("jump immediately publishes Sun frame", ship.anchor_name == "Sun" and ship.nearest_name == "Sun")
	check("jump clears old flight assists", not ship.autopilot and not ship.auto_cruise and ship._time_idx == 0 and ship.time_rate == 1)
	check("jump discards solid-ground contact", ship.terrain != null and not ship.terrain.surface.solid)
	check("park outside photosphere and exclusion shell", ship.anchor_off.length() > Ephemeris.SUN_RADIUS_KM*1.2)
	check("ordinary engines can overcome park gravity", ship._newton_g().length() < Ship.NEWTON_THRUST)
	ship.face_toward(ship.anchor_off)
	ship.touch_thrust = 1
	var initial := ship.anchor_distance_km()
	for i in 600:
		var previous := ship.anchor_distance_km()
		ship.fly(1.0/60)
		check("outward burn increases distance %d" % i, ship.anchor_distance_km() >= previous-.00001)
	check("outward travel isn't rounded away", ship.anchor_distance_km()-initial > .5)
	check("outward burn produces outward velocity", ship.velocity.dot(ship.anchor_off.normalized()) > 0)
	ship.velocity = Vector3.ZERO
	ship.face_toward(-ship.anchor_off)
	initial = ship.anchor_distance_km()
	for i in 600:
		var previous := ship.anchor_distance_km()
		ship.fly(1.0/60)
		check("inward burn decreases distance %d" % i, ship.anchor_distance_km() <= previous+.00001)
	check("inward travel isn't rounded away", initial-ship.anchor_distance_km() > 1)
	# Tiny per-frame translations remain cumulative, at both solar and larger radii.
	for radius in [695820.0,2782800.0,10000000.0]:
		ship.anchor_off = Vector3.RIGHT*radius
		ship.surface_position_revision += 1
		for i in 1000: ship._advance_anchor(Vector3.RIGHT*.001)
		check("sub-ULP metres accumulate at %.0f km" % radius, absf(ship.anchor_distance_km()-radius-1.0) < .001)
	ship.anchor_off = Vector3.RIGHT*695820.0
	ship.surface_position_revision += 1
	ship._advance_anchor(Vector3.RIGHT*.001)
	ship.surface_position_revision += 1 # discontinuity even at the same rounded position
	check("teleport clears old fractional travel", absf(ship.anchor_distance_km()-695820.0) < .0000001)
	# The original location remains a high-gravity zone; do not secretly weaken the Sun.
	check("near-photosphere gravity remains stronger than thrust", ship._newton_g().length() > Ship.NEWTON_THRUST*9)
	planets.refresh(ship.anchor_off,0,ship.anchor_name)
	ship.nearest_dir = planets.nearest_dir
	ship.velocity = Vector3.LEFT
	ship.last_thrust_accel = Vector3.RIGHT*Ship.NEWTON_THRUST
	ship.last_newton_g = ship._newton_g()
	var hud := HUD.new()
	controller.add_child(hud)
	hud.ship = ship
	hud.planets = planets
	hud.refresh()
	check("Sun HUD references photosphere rather than ground", "PHOTO ALT" in hud._tape_label.text and not "AGL" in hud._tape_label.text)
	check("HUD explains an underpowered outward fall", "RADIAL  IN" in hud._tape_label.text and "THRUST BELOW GRAVITY" in hud._tape_label.text)
	controller.queue_free()
	await get_tree().process_frame
	print("sun_flight: ","OK" if failures == 0 else "FAIL %d" % failures)
	get_tree().quit(1 if failures else 0)

func check(label: String, ok: bool) -> void:
	if not ok:
		failures += 1
		push_error(label)
