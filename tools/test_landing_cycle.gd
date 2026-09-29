extends Node3D
## Full Earth landing cycle against the real per-frame order in main: fly, advance
## the rotation clock, rebind the ephemeris surface basis, then main's contact pass.
const MainScript := preload("res://scripts/core/main.gd")
const HudScript := preload("res://scripts/ui/hud.gd")

class RisingGround extends TerrainSampler:
	func height_m(dir: Vector3, _detail: float = 0.0) -> float:
		return clampf(dir.x*6371.0-.05,0,1)*1000.0
	func max_height_km() -> float:
		return 1.0

class StubPlanets extends PlanetSystem:
	var ship_ref: Ship
	var sampler_ref: TerrainSampler
	func has_body(body: String) -> bool:
		return body == "Earth"
	func terrain_sampler_for(_body: String) -> TerrainSampler:
		return sampler_ref
	func surface_basis(body: String) -> Basis:
		return Ephemeris.surface_basis(body)
	func rel_of(_body: String) -> Vector3:
		return -ship_ref.anchor_off
	func refresh(_off: Vector3, _delta: float, _anchor := "", _vel: Vector3 = Vector3.ZERO) -> void:
		pass

# One float32 step of a coordinate at Earth radius (4096..8192 km). Anchored
# positions are stored on this grid; motion is carried below it (docs/adr/0002).
# Checks on stored or probe-sampled positions allow it, drift checks do not.
const ULP := .00049
var failures := 0
var ship: Ship
var main: Node
var planets: StubPlanets
var earth: TerrainSampler
var site: Dictionary
var xf: Transform3D
var verbose := OS.get_environment("LANDING_VERBOSE") != ""
var trace_on := OS.get_environment("LANDING_TRACE")
var only := OS.get_environment("LANDING_HULLS")
var trace_ref := Vector3.ZERO

func _ready() -> void:
	# Rotation phase changes float32 rounding. Default is a fixed phase; any run
	# can be replayed or randomised with LANDING_CLOCK=<unix_s>|wall.
	var clock := OS.get_environment("LANDING_CLOCK")
	if clock != "wall": Ephemeris.rotation_clock.unix_s = float(clock) if clock != "" else 1.8e9
	print("landing_cycle: clock unix_s=%.3f" % Ephemeris.rotation_clock.unix_s)
	earth = PlanetGenerator.terrain_sampler(PlanetGenerator.recipe_for({"name":"Earth"}))
	site = earth.facilities[0]
	xf = site.transform
	for unlock in 12: GameState.visited["test_system_%d" % unlock] = true
	ship = Ship.new()
	add_child(ship)
	ship._set_capture(false)
	ship.dev_speed = false
	planets = StubPlanets.new()
	planets.ship_ref = ship
	planets.sampler_ref = earth
	planets.nearest_name = "Earth"
	planets.nearest_radius = 6371.0
	main = MainScript.new()
	var hud := HudScript.new()
	hud.set("_flash", ColorRect.new())
	main.ship = ship
	main.planets = planets
	main.hud = hud
	var open := _open_site()
	for index in ship.ship_count():
		if not only.is_empty() and not str(index) in only.split(","): continue
		ship.swap_ship(index, true)
		for dt in [1.0/60.0, 1.0/20.0]:
			var tag := "%s@%dfps" % [ship.SHIP_MODELS[index].name, roundi(1.0/dt)]
			_pad_cycle(tag, dt)
			_open_rest(tag, dt, open)
			_thrust_into_ground(tag, dt, open)
			_slope_impact(tag, dt)
			_relocate_while_locked(tag, dt)
	main.free()
	hud.free()
	planets.free()
	ship.queue_free()
	await get_tree().process_frame
	print("landing_cycle: ", "OK" if failures == 0 else "FAIL %d" % failures)
	get_tree().quit(0 if failures == 0 else 1)

func _open_site() -> Vector3:
	for ring in range(3, 40):
		for k in 12:
			var local := xf.basis*Vector3(cos(k*TAU/12.0),0,sin(k*TAU/12.0))*float(ring)
			var dir := (xf.origin+local).normalized()
			if earth.is_water(dir) or SurfaceFacility.occupied(earth.facilities,dir,6371.0): continue
			if earth.normal_at(dir*earth.ground_radius_km(dir,6371.0),6371.0).dot(dir) < .995: continue
			return dir
	return xf.origin.normalized()

func _bind(sampler: TerrainSampler) -> void:
	planets.sampler_ref = sampler
	ship.terrain = sampler
	ship.set_terrain_frame(Ephemeris.surface_basis("Earth"), Ephemeris.surface_angle("Earth"))
	ship.nearest_name = "Earth"
	ship.nearest_radius = 6371.0
	main.set("_prev_body", "")

# One game frame in main's order.
func step(dt: float) -> void:
	ship.nearest_dist = ship.anchor_off.length()
	ship.nearest_dir = -ship.anchor_off.normalized()
	ship.fly(dt)
	Ephemeris.rotation_clock.advance(ship.simulation_delta)
	ship.set_terrain_frame(Ephemeris.surface_basis("Earth"), Ephemeris.surface_angle("Earth"))
	main.call("_update_skin_kill", dt)

func trace(what: String, frame: int, dt: float) -> void:
	if trace_on != what: return
	if frame == 0: trace_ref = local_pos()
	if frame % maxi(1,roundi(.25/dt)) != 0: return
	var up := ship.anchor_off.normalized()
	print("  %s t=%.2f d=%.5f lat=%.5f probe=%.5f agl=%.4f vr=%.4f vt=%.4f landed=%s site=%s sup=%s acc=%.4f" % [what,frame*dt,rel(trace_ref).length(),rel(trace_ref).slide(trace_ref.normalized()).length(),probe_alt(),agl(),ship.velocity.dot(up),ship.velocity.slide(up).length(),ship.landed,ship.landing_site,ship.support_active,ship.support_accel.dot(up)])

func key(code: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func release_inputs() -> void:
	for code in [KEY_SPACE, KEY_CTRL, KEY_A, KEY_D, KEY_W, KEY_S]: key(code, false)
	ship.touch_thrust = 0.0
	ship.touch_pitch = 0.0
	ship.touch_yaw = 0.0

# Body-frame position from the remainder-carrying double components, so float32
# rounding of the anchor offset is not mistaken for motion.
func local_pos() -> Vector3:
	return ship.terrain_local(ship.anchor_off, true)

# Body-frame offset from a nearby reference, differenced in double precision
# with the double spin angle, so sub-metre motion survives measurement.
func rel(origin: Vector3) -> Vector3:
	var remainder: Vector3 = ship._motion_remainder if ship._motion_is_continuous() else Vector3.ZERO
	var x := float(ship.anchor_off.x)+float(remainder.x)
	var y := float(ship.anchor_off.y)+float(remainder.y)
	var z := float(ship.anchor_off.z)+float(remainder.z)
	var a: float = ship._terrain_angle
	return Vector3(cos(a)*x-sin(a)*z-float(origin.x), y-float(origin.y), sin(a)*x+cos(a)*z-float(origin.z))

# Lowest hull/foot point above the ground, the quantity contact actually guards.
func probe_alt() -> float:
	var pose := ship.terrain_basis.inverse()*ship.transform.basis*ship._mesh_root.basis
	var points := ship._hull_probes.duplicate()
	points.append_array(ship.systems.foot_points())
	var lowest := INF
	for point in points:
		lowest = minf(lowest, ship.terrain.alt_above_ground_km(local_pos()+pose*point, 6371.0))
	return lowest

func agl() -> float:
	return ship.anchor_distance_km()-ship.terrain.ground_radius_km(local_pos().normalized(), 6371.0)

func place(local: Vector3, pose_local: Basis, gear: bool) -> void:
	release_inputs()
	ship.landing_site = ""
	ship.landing_site_id = ""
	ship.landed = false
	ship.locked = false
	ship.frozen = false
	ship.systems.gear_target = gear
	ship.systems.gear_fraction = 1.0 if gear else 0.0
	ship.systems.pose()
	ship.reset_mesh_pose()
	ship.transform.basis = ship.terrain_basis*pose_local
	ship.relocate(ship.terrain_basis*local)
	ship.velocity = Vector3.ZERO
	main.set("_prev_body", "")

func rest_height() -> float:
	return ship.surface_clearance_km()

func _pad_cycle(tag: String, dt: float) -> void:
	_bind(earth)
	var lowest := 0.0
	ship.systems.gear_target = true
	ship.systems.gear_fraction = 1.0
	ship.systems.pose()
	for foot in ship.systems.foot_points(): lowest = maxf(lowest,-foot.y)
	place(xf*Vector3(0,lowest+.06,0), xf.basis, true)
	# Descend on the mobile DOWN control until the pad takes the ship.
	ship.touch_pitch = 1.0
	var locked_at := -1.0
	var min_y := INF
	for frame in int(40.0/dt):
		step(dt)
		trace("descend",frame,dt)
		min_y = minf(min_y,(xf.basis.inverse()*rel(xf.origin)).y-lowest)
		if not ship.landing_site.is_empty():
			locked_at = frame*dt
			break
	ship.touch_pitch = 0.0
	check(tag+" pad locks", ship.landing_site == site.name)
	check(tag+" pad descent never embeds feet", min_y > -.001)
	if ship.landing_site.is_empty(): return
	if verbose: print("  seat gap=%.5f" % _deck_gap())
	check(tag+" pad lock seats feet on deck", absf(_deck_gap()-ShipSurfaceContact.SKIN) < ULP)
	var parked := rel(xf.origin)
	for frame in int(5.0/dt):
		step(dt)
		trace("hold",frame,dt)
	if verbose: print("  pad hold drift=%.6f" % rel(xf.origin).distance_to(parked))
	check(tag+" pad holds through rotation", rel(xf.origin).distance_to(parked) < .0001 and ship.landing_site == site.name)
	# Time warp while attached must not engage.
	key(KEY_PERIOD, true); key(KEY_PERIOD, false)
	step(dt)
	check(tag+" no time warp on pad", ship.time_rate == 1.0)
	# Departure: Space + strafe + main thrust at once.
	key(KEY_SPACE, true)
	key(KEY_D, true)
	ship.touch_thrust = 1.0
	var start_agl := agl()
	var peak_agl := start_agl
	var relocked := false
	var dropped := false
	var prev := agl()
	for frame in int(3.0/dt):
		step(dt)
		trace("depart",frame,dt)
		if not ship.landing_site.is_empty(): relocked = true
		peak_agl = maxf(peak_agl,agl())
		if frame*dt > .5 and agl() < prev-3*ULP: dropped = true
		prev = agl()
	var right := ship.transform.basis.x
	check(tag+" departure strafes while climbing", ship.velocity.dot(right) > .002)
	for frame in int(12.0/dt):
		step(dt)
		if not ship.landing_site.is_empty(): relocked = true
	release_inputs()
	check(tag+" departure releases pad", not relocked)
	check(tag+" departure climbs", peak_agl > start_agl+.02)
	check(tag+" departure never sinks back", not dropped)
	check(tag+" departure returns to free flight", not ship.support_active and not ship.landed and agl() > start_agl+.1)
	if verbose: print(tag," pad lock t=%.2f agl0=%.4f peak=%.4f" % [locked_at,start_agl,peak_agl])

func _open_rest(tag: String, dt: float, dir: Vector3) -> void:
	_bind(earth)
	var ground := earth.ground_radius_km(dir,6371.0)
	var right := dir.cross(Vector3.FORWARD).normalized() if absf(dir.dot(Vector3.FORWARD)) < .9 else dir.cross(Vector3.RIGHT).normalized()
	var upright := Basis(right, dir, right.cross(dir).normalized()).orthonormalized()
	# Gear down and upright over unapproved ground: the assistant holds a steady
	# hover instead of a lock, and must not bob in and out of its band.
	place(dir*ground, upright, true)
	place(dir*(ground+rest_height()+.001), upright, true)
	var r := _settle("open", dt, 12.0, 8.0)
	check(tag+" open terrain never sinks", r.min_probe >= -4*ULP)
	check(tag+" open terrain never locks", ship.landing_site.is_empty())
	check(tag+" open terrain hover settles (no bob)", r.hi-r.lo < 2*ULP and r.speed < .0005)
	if verbose: print(tag," open hover lo=%.4f hi=%.4f vmax=%.5f" % [r.lo,r.hi,r.speed])
	# Rolled past the support envelope, the hull itself rests on the ground.
	var rolled := Basis(upright.z, deg_to_rad(50.0))*upright
	place(dir*ground, rolled, false)
	place(dir*(ground+rest_height()+.001), rolled, false)
	ship.touch_held = true
	r = _settle("rest", dt, 8.0, 4.0)
	key(KEY_PERIOD, true); key(KEY_PERIOD, false)
	step(dt)
	check(tag+" no time warp in ground contact", ship.time_rate == 1.0)
	ship.touch_held = false
	check(tag+" hull rest never sinks", r.min_probe >= -4*ULP)
	check(tag+" hull rest stays in contact", r.max_probe < 5*ULP)
	check(tag+" hull rest does not bounce", r.hi-r.lo < 2*ULP and r.speed < .0005)
	check(tag+" hull rest does not creep", r.creep < ULP)
	if verbose: print(tag," hull rest probe=[%.5f,%.5f] agl=[%.4f,%.4f] vmax=%.5f creep=%.4f" % [r.min_probe,r.max_probe,r.lo,r.hi,r.speed,r.creep])

func _settle(what: String, dt: float, seconds: float, after: float) -> Dictionary:
	var r := {"lo":INF,"hi":-INF,"speed":0.0,"creep":0.0,"min_probe":INF,"max_probe":-INF}
	var start := Vector3.ZERO
	for frame in int(seconds/dt):
		step(dt)
		trace(what,frame,dt)
		r.min_probe = minf(r.min_probe,probe_alt())
		if frame*dt >= after:
			if start == Vector3.ZERO: start = local_pos()
			r.lo = minf(r.lo,agl())
			r.hi = maxf(r.hi,agl())
			r.max_probe = maxf(r.max_probe,probe_alt())
			r.speed = maxf(r.speed,ship.velocity.length())
			r.creep = maxf(r.creep,rel(start).slide(start.normalized()).length())
	return r

# Hold thrust into the ground well past contact; the ground must win.
func _press_into(what: String, dt: float, pose: Basis, dir: Vector3, start_alt: float, velocity_local: Vector3) -> Dictionary:
	var ground := ship.terrain.ground_radius_km(dir,6371.0)
	place(dir*ground, pose, false)
	place(dir*(ground+rest_height()+start_alt), pose, false)
	ship.velocity = ship.terrain_basis*velocity_local
	ship.touch_thrust = 1.0
	ship.touch_held = true
	var r := {"contact":-1.0,"contact_agl":INF,"peak":-INF,"min_probe":INF}
	for frame in int(6.0/dt):
		step(dt)
		trace(what,frame,dt)
		r.min_probe = minf(r.min_probe,probe_alt())
		if r.contact < 0.0 and probe_alt() < .003:
			r.contact = frame*dt
			r.contact_agl = agl()
		elif r.contact >= 0.0 and frame*dt > r.contact+.5:
			r.peak = maxf(r.peak,agl())
	release_inputs()
	ship.touch_held = false
	return r

func _thrust_into_ground(tag: String, dt: float, dir: Vector3) -> void:
	_bind(earth)
	var right := dir.cross(Vector3.FORWARD).normalized() if absf(dir.dot(Vector3.FORWARD)) < .9 else dir.cross(Vector3.RIGHT).normalized()
	var r := _press_into("press", dt, Basis(right, right.cross(dir).normalized(), dir), dir, .2, Vector3.ZERO)
	check(tag+" thrust into ground makes contact", r.contact >= 0.0)
	check(tag+" thrust into ground never gains AGL", r.peak < r.contact_agl+.002)
	check(tag+" thrust into ground never tunnels", r.min_probe >= -4*ULP)
	if verbose: print(tag," thrust contact=%.4f peak=%.4f probe=%.5f" % [r.contact_agl,r.peak,r.min_probe])

func _slope_impact(tag: String, dt: float) -> void:
	var slope := RisingGround.new({})
	slope.surface = {"solid": true}
	_bind(slope)
	var dir := Vector3(.3/6371.0,1,0).normalized()
	var normal := slope.normal_at(dir*slope.ground_radius_km(dir,6371.0),6371.0)
	var up_slope := (dir-normal*normal.dot(dir)).normalized()
	var pose := Basis(up_slope.cross(normal).normalized(), up_slope, normal).orthonormalized()
	# A 10 km/s vertical dive meets 45 degree rock at 45 degrees, nose into it.
	var r := _press_into("slope", dt, pose, dir, .5, (-normal-up_slope).normalized()*10.0)
	check(tag+" slope impact contacts", r.contact >= 0.0)
	check(tag+" slope impact never tunnels", r.min_probe >= -4*ULP)
	check(tag+" slope impact is not a launch", r.peak < r.contact_agl+.02)
	if verbose: print(tag," slope contact=%.4f peak=%.4f probe=%.5f v=%.4f" % [r.contact_agl,r.peak,r.min_probe,ship.velocity.length()])

func _relocate_while_locked(tag: String, dt: float) -> void:
	_pad_lock_now(tag, dt)
	if ship.landing_site.is_empty():
		check(tag+" relocate precondition lock", false)
		return
	ship.true_pos = Ephemeris.geo_start_pos()
	ship.velocity = Vector3.ZERO
	step(dt)
	check(tag+" relocation releases pad", ship.landing_site.is_empty() and not ship.landed)
	check(tag+" relocation is not snapped back", ship.anchor_off.distance_to(Ephemeris.geo_start_pos()) < 1.0)

func _deck_gap() -> float:
	var pose := ship.terrain_basis.inverse()*ship.transform.basis*ship._mesh_root.basis
	var lowest := INF
	for foot in ship.systems.foot_points():
		lowest = minf(lowest,(xf.basis.inverse()*(rel(xf.origin)+pose*foot)).y)
	return lowest

func _pad_lock_now(tag: String, dt: float) -> void:
	_bind(earth)
	ship.systems.gear_target = true
	ship.systems.gear_fraction = 1.0
	ship.systems.pose()
	var lowest := 0.0
	for foot in ship.systems.foot_points(): lowest = maxf(lowest,-foot.y)
	place(xf*Vector3(0,lowest+.0012,0), xf.basis, true)
	for frame in int(3.0/dt):
		step(dt)
		if not ship.landing_site.is_empty():
			if verbose: print("  seat gap=%.5f" % _deck_gap())
			check(tag+" hover inside support gap locks seated", absf(_deck_gap()-ShipSurfaceContact.SKIN) < ULP)
			return

func check(label: String, ok: bool) -> void:
	if not ok:
		failures += 1
		print("landing_cycle: FAIL ", label)
