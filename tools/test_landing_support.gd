extends Node3D
class RisingGround extends TerrainSampler:
	func height_m(dir: Vector3, _detail: float = 0.0) -> float:
		return clampf(dir.x*6371.0-.05,0,1)*1000.0
	func max_height_km() -> float:
		return 1.0
var failures := 0
func _ready() -> void:
	var sampler := PlanetGenerator.terrain_sampler(PlanetGenerator.recipe_for({"name":"Earth"}))
	var xf: Transform3D = sampler.facilities[0].transform
	for unlock in 12: GameState.visited["test_system_%d" % unlock] = true # every tier swappable
	var ship := Ship.new()
	add_child(ship)
	ship._set_capture(false)
	ship.dev_speed = false
	ship.nearest_name = "Earth"
	ship.nearest_radius = 6371
	ship.nearest_dist = 6371
	ship.terrain = sampler
	for index in ship.ship_count():
		ship.swap_ship(index)
		ship.set_terrain_frame(Basis.IDENTITY)
		ship.transform.basis = xf.basis
		ship.anchor_off = xf*Vector3(0,.12,0)
		ship.velocity = Vector3.ZERO
		ship.systems.gear_target = true
		ship.systems.step(2)
		var before := ship.anchor_distance_km()
		for frame in 180: ship.fly(1.0/60)
		check("gravity hold hull %d" % index,absf(ship.anchor_distance_km()-before)<.0015 and ship.support_active)
		# The authored cruiser has no modular sockets; its outlets come from the rig.
		var modular: bool = ship.SHIP_MODELS[index].get("modular", false)
		var sockets: int = ModularHull.sockets(ship._mesh_root.get_child(0)).landjet.size()
		check("one outlet per landjet socket",(not modular or ship.systems.support.jets.size()==sockets) and ship.systems.support.jets.size()>=4)
		for jet in ship.systems.support.jets:
			check("underside angled outlets",jet.direction.y < -.9 and absf(jet.direction.x)>.2)
			check("hover actually fires outlets",jet.power>.1)
		check("hover is not a pad lock",ship.landing_site.is_empty())
	# An injected small sideways disturbance should settle without steering the nose.
	var heading := ship.terrain_basis.inverse()*ship.transform.basis
	ship.velocity = ship.transform.basis.x*.004
	for frame in 180: ship.fly(1.0/60)
	check("support arrests drift",ship.velocity.length()<.0002)
	check("support preserves heading",(ship.terrain_basis.inverse()*ship.transform.basis).is_equal_approx(heading))
	ship.touch_pitch = 1
	var before := ship.anchor_distance_km()
	for frame in 30: ship.fly(1.0/60)
	check("pilot can descend through hover hold",ship.anchor_distance_km()<before-.0003 and ship.velocity.dot(ship.anchor_off.normalized())<0)
	ship.touch_pitch = 0
	# Test exclusions directly, without conflating normal flight drag or gravity.
	# The assistant protects a low ship even when the landing gear is stowed.
	ship.systems.gear_target = false
	ship.systems.step(2)
	ship.anchor_off = xf*Vector3(.8,.035,0)
	ship.velocity = -xf.basis.y*.02
	ship.support_active = false
	ship.support_accel = Vector3.ZERO
	ship._apply_landing_support(1.0/60,Vector3.ZERO,Vector3.ZERO)
	check("gear-up terrain avoidance engages",ship.support_active and ship.support_accel.dot(xf.basis.y) > .009)
	# Outward flight and distant flight must release assistance automatically.
	for mode in ["outward","fast","high","inverted"]:
		ship.support_active = false
		ship.support_accel = Vector3.ZERO
		ship.systems.gear_target = false
		ship.anchor_off = xf*Vector3(0,1.0 if mode=="high" else .12,0)
		ship.transform.basis = xf.basis*(Basis(Vector3.FORWARD,PI) if mode=="inverted" else Basis.IDENTITY)
		ship.velocity = xf.basis.y*.2 if mode=="outward" else xf.basis.x*(1.0 if mode=="fast" else .001)
		var prior := ship.velocity
		ship._apply_landing_support(1.0/60,Vector3.ZERO,Vector3.ZERO)
		check("support leaves %s flight alone" % mode,ship.velocity==prior and not ship.support_active)
	ship.systems.support.command(Vector3.ZERO,1)
	for jet in ship.systems.support.jets: check("inactive jets go dark",jet.power==0)
	ship.anchor_off = xf*Vector3(0,5,0)
	ship.velocity = Vector3.ZERO
	ship.transform.basis = xf.basis*Basis(Vector3.FORWARD,.8)*Basis(Vector3.RIGHT,.4)
	var tilted_pose := ship.terrain_basis.inverse()*ship.transform.basis
	for frame in 299: ship.fly(1.0/60)
	check("planetary attitude waits five idle seconds",(ship.terrain_basis.inverse()*ship.transform.basis).is_equal_approx(tilted_pose))
	ship.touch_yaw = .4
	for frame in 60: ship.fly(1.0/60)
	check("touch steering resets the idle timer",ship._level_idle_s < .01)
	ship.touch_yaw = 0.0
	var steering_pose := ship.terrain_basis.inverse()*ship.transform.basis
	for frame in 299: ship.fly(1.0/60)
	var waiting_pose := ship.terrain_basis.inverse()*ship.transform.basis
	check("leveling waits again after touch steering",waiting_pose.y.dot(steering_pose.y)>.999999)
	var alignment_before := waiting_pose.y.dot(ship.anchor_off.normalized())
	var velocity_before_level := ship.velocity
	for frame in 120: ship.fly(1.0/60)
	var leveled_pose := ship.terrain_basis.inverse()*ship.transform.basis
	var level_angle := waiting_pose.get_rotation_quaternion().angle_to(leveled_pose.get_rotation_quaternion())
	check("idle leveling eases in at slow rate",level_angle > .005 and level_angle < .22)
	check("idle leveling moves toward local horizon",leveled_pose.y.dot(ship.anchor_off.normalized())>alignment_before+.005)
	check("leveling adds no velocity impulse",ship.velocity.distance_to(velocity_before_level) < .08)
	var manual_pose := xf.basis*Basis(Vector3.FORWARD,.6)
	ship.transform.basis = manual_pose
	ship._level_near_planet(1.0,true)
	check("manual roll overrides auto leveling",ship.transform.basis.is_equal_approx(manual_pose))
	ship._level_idle_s = 6.0
	var press := InputEventKey.new()
	press.keycode = KEY_B
	press.pressed = true
	ship._input(press)
	ship.fly(1.0/60)
	check("single key press restarts idle delay",ship._level_idle_s < .01)
	ship._level_idle_s = 6.0
	ship.touch_held = true
	ship.fly(1.0/60)
	check("held touch prevents idle leveling",ship._level_idle_s < .01)
	ship.touch_held = false
	ship.anchor_off = xf*Vector3(0,500,0)
	ship.transform.basis = xf.basis*Basis(Vector3.FORWARD,.8)
	var space_heading := ship.transform.basis
	for frame in 60: ship.fly(1.0/60)
	check("space flight keeps free attitude",ship.transform.basis.is_equal_approx(space_heading))
	var ridge := RisingGround.new({})
	ridge.surface = {"solid":true}
	ship.terrain = ridge
	ship.set_terrain_frame(Basis.IDENTITY)
	ship.transform.basis = Basis.IDENTITY
	ship.anchor_off = Vector3.UP*6371.2
	ship.velocity = Vector3.RIGHT*.08
	ship._apply_landing_support(1.0/60,Vector3.ZERO,Vector3.ZERO)
	check("horizontal mountain approach triggers predictive braking",ship.support_active and ship.support_accel.x<0)
	ship.queue_free()
	await get_tree().process_frame
	print("landing_support: ","OK" if failures==0 else "FAIL %d" % failures)
	get_tree().quit(0 if failures==0 else 1)
func check(label: String, value: bool) -> void:
	if not value:
		failures += 1
		push_error(label)
