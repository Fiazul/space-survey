extends Node3D
var failures := 0
class FlatLand extends TerrainSampler:
	var traces := 0
	func resolve_motion(from: Vector3, to: Vector3, velocity: Vector3, radius: float, clearance: float) -> Dictionary:
		traces += 1
		return super.resolve_motion(from,to,velocity,radius,clearance)
	func height_m(_dir: Vector3, _detail: float = 0.0) -> float:
		return 0.0
	func max_height_km() -> float:
		return 0.0

func _ready() -> void:
	for speed in [1.2, 4.8, 9.6, 19.2]:
		var origin := Vector3(.02,.03,0)
		var inherited := Vector3(.4,.1,0)
		var target := Vector3(.1,.2,-2)
		var velocity := Vector3(.8,-.1,.2)
		var aim := WeaponAim.intercept(origin,inherited,target,velocity,speed)
		check("intercept exists", not aim.is_empty())
		check("lead accounts for both velocities", (origin+(inherited+aim.direction*speed)*aim.time).distance_to(target+velocity*aim.time) < .0001)
	check("unreachable target has no false solution", WeaponAim.intercept(Vector3.ZERO, Vector3.ZERO, Vector3.FORWARD, Vector3.FORWARD*20, 9.6).is_empty())
	var ship := Ship.new()
	add_child(ship)
	ship.newton = true
	ship.anchor_off = Vector3.UP*6372
	ship.velocity = Vector3.RIGHT*.04
	ship.prepare_weapons()
	ship.systems.step(1)
	var combat := Combat.new()
	add_child(combat)
	check("default speed is 32x", is_equal_approx(combat.plasma.muzzle_speed(), 38.4))
	var target := {"alive": true, "pos": ship.muzzle_off()+Vector3(.004,0,-1), "vel": Vector3(.1,0,0), "size": .01, "name": "Test drone"}
	combat._aliens = [target]
	combat.update_aim(ship)
	check("near aim acquires assistance", combat.aim_solution.assisted)
	for slot in ship.systems.mounts.size():
		var aim := WeaponAim.intercept(ship.muzzle_off(slot),ship.velocity,target.pos,target.vel,combat.plasma.muzzle_speed())
		var predicted: Vector3 = ship.muzzle_off(slot)+(ship.velocity+ship.barrel_direction(slot)*combat.plasma.muzzle_speed())*aim.time
		check("actual barrel points at intercept", predicted.distance_to(target.pos+target.vel*aim.time) < .001)
	var stable: Vector3 = combat.aim_solution.point
	for shot in 12:
		combat._next_mount = shot % ship.systems.mounts.size()
		combat.update_aim(ship)
		check("alternating guns keeps assisted sight stable", combat.aim_solution.point.distance_to(stable) < .00001)
	combat._aliens.clear()
	combat.update_aim(ship)
	stable = combat.aim_solution.point
	for shot in 12:
		combat._next_mount = shot % ship.systems.mounts.size()
		combat.update_aim(ship)
		check("alternating guns keeps free sight stable", combat.aim_solution.point.distance_to(stable) < .00001)
	for slot in ship.systems.mounts.size():
		var goal := stable+ship.anchor_off
		var aim := WeaponAim.intercept(ship.muzzle_off(slot), ship.velocity, goal, Vector3.ZERO, combat.plasma.muzzle_speed())
		var predicted := ship.muzzle_off(slot)+(ship.velocity+ship.barrel_direction(slot)*combat.plasma.muzzle_speed())*float(aim.time)
		check("all guns converge at free sight including inherited velocity", predicted.distance_to(goal) < .001)
	combat._aliens = [target]
	combat.update_aim(ship)
	var before: Vector3 = combat.aim_solution.point
	combat.plasma.speed_multiplier = 2
	combat.update_aim(ship)
	check("changing multiplier recomputes lead", before.distance_to(combat.aim_solution.point) > .005)
	target.pos = ship.anchor_off+Vector3(.6,0,-1)
	combat.update_aim(ship)
	check("assistance cannot lock far off boresight", combat.aim_solution.target.is_empty() and not combat.aim_solution.assisted)
	target.pos = ship.anchor_off+Vector3(0,0,-4)
	combat.update_aim(ship)
	check("out of range is explicit", combat.aim_solution.state == "OUT OF RANGE")
	combat._aliens.clear()
	ship.transform.basis = Basis(Vector3.RIGHT,-PI*.25)
	ship.terrain = FlatLand.new({})
	ship.terrain.surface = {"solid": true}
	combat.update_aim(ship)
	check("pipper traces surface instead of infinity", combat.aim_solution.state == "SURFACE" and combat.aim_solution.distance < 2)
	target.pos = ship.muzzle_off()+ship.weapon_direction()*2.0
	target.vel = Vector3.ZERO
	combat._aliens = [target]
	combat.update_aim(ship)
	check("terrain blocks a target firing solution", combat.aim_solution.blocked and not combat.aim_solution.assisted and combat.aim_solution.state == "OBSTRUCTED")
	var count: int = ship.terrain.traces
	combat.update_aim(ship,.016)
	check("unchanged preview reuses terrain trace", ship.terrain.traces == count)
	combat.update_aim(ship,.05)
	check("preview refreshes within 50 ms", ship.terrain.traces == count+1)
	ship.anchor_off += Vector3.UP*.02
	combat.update_aim(ship,.001)
	check("movement invalidates cached preview", ship.terrain.traces == count+2)
	combat.plasma.emit(ship.muzzle_off(),ship.velocity,ship.barrel_direction(),1,ship.anchor_off)
	var snapshot: Vector3 = combat.plasma.shots[0].vel
	combat.plasma.speed_multiplier = 12
	check("live tuning doesn't accelerate existing bullets", combat.plasma.shots[0].vel == snapshot)
	# Every hull, including the four-gun battery, shares one ground impact point.
	combat._aliens.clear()
	ship.velocity = Vector3.ZERO
	for model in ship.ship_count():
		ship.swap_ship(model)
		ship.newton = true
		ship.systems.weapons_target = true
		ship.systems.step(1)
		combat.update_aim(ship)
		var ground_point: Vector3 = combat.aim_solution.point+ship.anchor_off
		for slot in ship.systems.mounts.size():
			combat._next_mount = slot
			combat.update_aim(ship)
			check("ground sight stable on hull %d slot %d" % [model,slot], (combat.aim_solution.point+ship.anchor_off).distance_to(ground_point) < .00001)
			var offset := ground_point-ship.muzzle_off(slot)
			var closest := ship.muzzle_off(slot)+ship.barrel_direction(slot)*offset.dot(ship.barrel_direction(slot))
			check("ground convergence on hull %d slot %d" % [model,slot], closest.distance_to(ground_point) < .001)
	combat._aliens.clear()
	combat.queue_free()
	ship.queue_free()
	await get_tree().process_frame
	print("weapon_aim: ", "OK" if failures == 0 else "FAIL %d" % failures)
	get_tree().quit(1 if failures else 0)

func check(label: String, ok: bool) -> void:
	if not ok:
		failures += 1
		push_error(label)
