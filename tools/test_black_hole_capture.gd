class_name TestBlackHoleCapture
extends Node

var failures := 0

func check(label: String, ok: bool) -> void:
	if not ok:
		failures += 1
		push_error("black_hole_capture: " + label)

func _ready() -> void:
	ProfileDir.isolate("test_black_hole_capture")
	var cfg := ConfigFile.new()
	cfg.set_value("player","system",SystemDB.SAGITTARIUS_A)
	cfg.save(GameState.profile_path())
	var main = load("res://scenes/Main.tscn").instantiate()
	add_child(main)
	main.set_process(false)
	var ship: Ship = main.ship
	var au := Ephemeris.KM_PER_AU
	for no_death in [false,true]:
		FlightMode.dev_no_death = no_death
		ship.dev_speed = true
		for motion in [Vector3(2.0e7,0,0),Vector3(-2.0e7,0,0),Vector3(0,2.0e7,0)]:
			main.dev_sites.go_core({"au":2.0,"polar":false})
			ship.relocate(Vector3(.585*au,0,0))
			ship.velocity = motion
			var before := ship.anchor_off.length()
			main._process(.1)
			check("screenshot distance forces inward flight regardless of velocity/no-death", ship.anchor_off.length() < before and ship.velocity.dot(ship.anchor_off) < 0.0)
			check("HUD makes forced capture explicit", "CORE CAPTURE — NO ESCAPE" in main.hud.hole_warnings(ship.hole_orbit))
			var frames := 0
			while main.black_hole_portal == null and frames < 60:
				# Repeated absurd outward thrust cannot override the capture.
				ship.velocity = ship.anchor_off.normalized()*1.0e10
				var previous := ship.anchor_off.length()
				main._process(.1)
				check("capture never moves outward", ship.anchor_off.length() <= previous)
				frames += 1
			check("forced capture reaches Humano within six seconds", main.black_hole_portal != null and not main._skin_dying)
			if main.black_hole_portal != null:
				main.black_hole_portal.return_to_ship()
				check("exit remains a safe 2 AU park", absf(ship.anchor_off.length()/au-2.0) < .00001)
	main.dev_sites.go_core({"au":2.0,"polar":false})
	ship.relocate(Vector3(au,0,0))
	ship.velocity = Vector3(-au*200.0,0,0)
	main._process(.01)
	check("a swept step cannot skip the whole capture region", main.black_hole_portal != null)
	if main.black_hole_portal != null: main.black_hole_portal.return_to_ship()
	ship.relocate(Vector3(au,.7*au,0))
	ship.velocity = Vector3(-au*200.0,0,0)
	main._process(.01)
	check("a fast flyby outside 0.6 AU stays free", main.black_hole_portal == null and not ship.horizon_crossed)
	FlightMode.dev_no_death = false
	ship.dev_speed = false
	main.free()
	print("black_hole_capture: ","OK" if failures == 0 else "FAIL %d" % failures)
	get_tree().quit(1 if failures else 0)
