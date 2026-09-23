extends Node3D
var failures := 0

func check(label: String, ok: bool) -> void:
	if not ok:
		failures += 1
		push_error(label)

func _ready() -> void:
	var ship := Ship.new()
	add_child(ship)
	ship._set_capture(false)
	ship.newton = true
	var combat := Combat.new()
	add_child(combat)
	var saved_cycle: float = Ephemeris.rotation_clock.cycle_minutes
	Ephemeris.rotation_clock.cycle_minutes = 8.0
	for speed in [0.5,32.0,132.0,256.0]:
		for heading in [0.0,90.0,180.0,270.0]:
			combat.reset()
			combat.plasma.speed_multiplier = speed
			ship.anchor_off = Vector3.RIGHT*6372
			ship.velocity = Vector3.ZERO
			ship.terrain_basis = Basis.IDENTITY
			ship.transform.basis = Basis.looking_at(Vector3.FORWARD.rotated(Vector3.RIGHT,deg_to_rad(heading)),Vector3.RIGHT)
			ship.systems.weapons_target = true
			ship.systems.step(1)
			combat._cool = 0
			combat.update(ship,true,0)
			var shot: Dictionary = combat.plasma.shots[0]
			var origin: Vector3 = shot.pos
			var velocity: Vector3 = shot.vel
			var dt := minf(1.0/60.0,shot.life*.5)
			var rotation := Basis(Vector3.UP,Ephemeris.scene_spin_rad_s("Earth")*dt)
			ship._newton_corotate(dt)
			combat.update(ship,false,dt)
			var expected := rotation*(origin+velocity*dt)
			check("shot follows rotating atmosphere at %sx heading %s" % [speed,heading], shot.pos.distance_to(expected) < .003)
			var ray: Vector3 = shot.pos-rotation*origin
			check("shot leaves in the barrel direction instead of planetary drift", ray.normalized().dot((rotation*velocity).normalized()) > .99)
			if speed == 32.0 and heading == 0.0:
				var old_velocity: Vector3 = shot.vel
				ship.rotate_y(PI*.5)
				combat.update(ship,false,dt)
				check("turning the nose cannot steer an already-fired shot", shot.vel.is_equal_approx(old_velocity))
				combat._cool = 0.0
				combat.update(ship,true,0.0)
				check("next shot follows the newly turned nose", combat.plasma.shots.back().vel.normalized().dot(ship.weapon_direction()) > .99)
	# A ship can drift faster than its muzzle speed. Converging on our own
	# free-aim endpoint must not choose the faster, backwards-facing intercept.
	combat.reset()
	ship.anchor_off = Vector3.RIGHT*6372
	ship.terrain_basis = Basis.IDENTITY
	ship.transform.basis = Basis.IDENTITY
	ship.velocity = Vector3.BACK*200
	combat.plasma.speed_multiplier = 32.0
	combat.update_aim(ship)
	for slot in ship.systems.mounts.size():
		check("free aim cannot swing guns away from the nose during fast drift",ship.barrel_direction(slot).dot(ship.weapon_direction()) > .99)
	var pulses := combat.plasma
	pulses.clear()
	pulses.sync_surface_frame("Earth",Vector3.ZERO,Basis.IDENTITY)
	pulses.emit(Vector3.RIGHT*6372,Vector3.ZERO,Vector3.FORWARD,1,Vector3.ZERO)
	pulses.advance(.2,Vector3.ZERO,[])
	var end: Vector3 = pulses.traces[0].pos
	var turn := Basis(Vector3.UP,.1)
	pulses.sync_surface_frame("Earth",Vector3.ZERO,turn)
	check("resolved traces stay with the same terrain",pulses.traces[0].pos.distance_to(turn*end) < .002)
	var shift := Vector3(10,20,30)
	pulses.shift_frame(shift)
	var shifted: Vector3 = pulses.traces[0].pos
	pulses.sync_surface_frame("Earth",-shift,turn)
	check("reanchoring cannot apply a second frame translation",pulses.traces[0].pos.is_equal_approx(shifted))
	Ephemeris.rotation_clock.cycle_minutes = saved_cycle
	combat.queue_free()
	ship.queue_free()
	await get_tree().process_frame
	print("plasma_frame: ","OK" if failures == 0 else "FAIL %d" % failures)
	get_tree().quit(1 if failures else 0)
