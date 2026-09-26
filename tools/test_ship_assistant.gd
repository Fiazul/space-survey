extends SceneTree
const Assistant := preload("res://scripts/flight/ship_assistant.gd")
var failures := 0
func _initialize() -> void:
	for up in [Vector3.UP,Vector3.RIGHT,Vector3(1,2,3).normalized()]:
		for gravity in [.00162,.00371,.00981]:
			var force := Assistant.correction(.015,up,-up*.01,-up*gravity,Vector3.ZERO,false,1.0/60)
			check("hazard correction counters local gravity",force.dot(up)>gravity)
			check("assistant thrust stays bounded",force.length()<=.025001)
			check("distant flight needs no support",Assistant.correction(1,up,Vector3.ZERO,-up*gravity,Vector3.ZERO,false,1.0/60)==Vector3.ZERO)
			check("outward flight releases",Assistant.correction(.05,up,up*.03,-up*gravity,Vector3.ZERO,false,1.0/60)==Vector3.ZERO)
	var hold := Assistant.correction(.1,Vector3.UP,Vector3.ZERO,Vector3.DOWN*.00981,Vector3.ZERO,true,1.0/60)
	check("pad approach counters gravity without lifting",hold.is_equal_approx(Vector3.UP*.00981))
	var drift := Assistant.correction(.1,Vector3.UP,Vector3.RIGHT*.01,Vector3.ZERO,Vector3.ZERO,true,1.0/60)
	check("moving berth relative drift settles",drift.x<0 and absf(drift.y)<.00001)
	var banked := Basis(Vector3.FORWARD,.8)*Basis(Vector3.RIGHT,.4)
	var before_level := banked
	check("zero ease holds attitude",Assistant.level(banked,Vector3.UP,1.0/60,0.0).is_equal_approx(banked))
	banked = Assistant.level(banked,Vector3.UP,1.0/60,1.0)
	var first_step := before_level.get_rotation_quaternion().angle_to(banked.get_rotation_quaternion())
	check("assistant leveling caps angular step",first_step > 0 and first_step <= deg_to_rad(6.0)/60.0+.00001)
	for i in 700: banked = Assistant.level(banked,Vector3.UP,1.0/60,1.0)
	check("idle attitude returns parallel to surface",banked.y.dot(Vector3.UP)>.999)
	var pole := Basis(Vector3.RIGHT,PI*.5)
	for i in 1000: pole = Assistant.level(pole,Vector3.UP,1.0/60,1.0)
	check("vertical entry levels without degenerate basis",pole.is_finite() and pole.y.dot(Vector3.UP)>.999)
	print("ship_assistant: ","OK" if failures==0 else "FAIL %d" % failures)
	quit(0 if failures==0 else 1)
func check(label: String, ok: bool) -> void:
	if not ok:
		failures += 1
		push_error(label)
