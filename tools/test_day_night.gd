extends Node3D
var failures := 0
class EarthWorld extends PlanetSystem:
	func _ready() -> void:
		_dot_tex = _make_dot_texture()
		var spec: Dictionary = Ephemeris.PLANETS.filter(func(p): return p.name == "Earth")[0].duplicate(true)
		spec.physical = true
		load_system([spec])
class Controller extends "res://scripts/core/main.gd":
	func _ready() -> void:
		pass
	func _save_profile() -> void:
		pass # This regression must not touch the player's real save.

func check(label: String, ok: bool) -> void:
	if not ok:
		failures += 1
		push_error(label)

func _ready() -> void:
	var saved_time: float = Ephemeris.rotation_clock.unix_s
	var saved_cycle: float = Ephemeris.rotation_clock.cycle_minutes
	Ephemeris.rotation_clock.cycle_minutes = 8.0
	var utc := float(Time.get_unix_time_from_datetime_string("2026-09-23T00:00:00"))
	var amazon := DevSites.dir_for(-3,-60)
	var sun := Vector3.LEFT # autumn equinox, RA 12h, scene equatorial frame
	var spin: float = Ephemeris.spin_rad_s("Earth")
	check("J2000 Greenwich meridian has known sidereal phase", absf(rad_to_deg(CelestialRotation.earth_angle(CelestialRotation.J2000_UNIX))-280.4606) < .001)
	var morning := CelestialRotation.basis_at("Earth",spin,utc+10*3600)*amazon
	var later := CelestialRotation.basis_at("Earth",spin,utc+11*3600)*amazon
	check("Amazon sunrise advances eastward", later.dot(sun) > morning.dot(sun)+.2)
	check("Amazon is daylight near local noon", (CelestialRotation.basis_at("Earth",spin,utc+16*3600)*amazon).dot(sun) > .98)
	check("Amazon is dark near local midnight", (CelestialRotation.basis_at("Earth",spin,utc+4*3600)*amazon).dot(sun) < -.98)
	var day_samples := 0
	for hour in 24:
		if (CelestialRotation.basis_at("Earth",spin,utc+hour*3600)*amazon).dot(sun) > 0:
			day_samples += 1
	check("Amazon experiences both halves of the day", day_samples >= 11 and day_samples <= 13)
	var clock := CelestialRotation.new()
	clock.cycle_minutes = 8.0
	clock.load_from(ConfigFile.new(),utc)
	var start := CelestialRotation.earth_angle(clock.unix_s)
	clock.advance(240)
	check("four real minutes is half a rotation", absf(absf(angle_difference(start,CelestialRotation.earth_angle(clock.unix_s)))-PI) < .00001)
	clock.advance(240)
	check("eight real minutes completes the cycle", absf(angle_difference(start,CelestialRotation.earth_angle(clock.unix_s))) < .00001)
	var short_rate := clock.rate
	clock.cycle_minutes = 24.0
	check("cycle duration is configurable without moving the phase", is_equal_approx(clock.rate*3,short_rate) and absf(angle_difference(start,CelestialRotation.earth_angle(clock.unix_s))) < .00001)
	clock.cycle_minutes = -1.0
	check("invalid duration falls back to eight minutes", clock.cycle_minutes == 8.0)
	clock.cycle_minutes = NAN
	check("nonfinite duration falls back to eight minutes", clock.cycle_minutes == 8.0)
	clock.advance(6*3600)
	var cfg := ConfigFile.new()
	clock.save_into(cfg,utc+100)
	var resumed := CelestialRotation.new()
	resumed.load_from(cfg,utc+100)
	check("immediate restart preserves phase", resumed.unix_s == clock.unix_s)
	resumed.load_from(cfg,utc+100+12*3600)
	check("offline elapsed time uses saved cycle rate", is_equal_approx(resumed.unix_s,clock.unix_s+12*3600*clock.rate))
	resumed.load_from(cfg,utc-100)
	check("wall clock rollback cannot rewind saved world", resumed.unix_s == clock.unix_s)
	resumed.cycle_minutes = 24.0
	resumed.load_from(cfg,utc+160)
	check("changing duration preserves offline interval at previous rate", absf(resumed.unix_s-clock.unix_s-60*clock.rate) < .001)
	cfg.erase_section_key("world_clock","rate")
	resumed.load_from(cfg,utc+160)
	check("old real-time saves retain their phase on upgrade", absf(resumed.unix_s-clock.unix_s-60) < .001)
	Ephemeris.rotation_clock.unix_s = utc+16*3600
	var noon_solar := Ephemeris.solar_state("Earth",amazon)
	var first := EarthWorld.new()
	add_child(first)
	var noon := first.surface_basis("Earth")
	check("mesh initialized at current clock", first._bodies[0].sphere.basis.is_equal_approx(noon))
	Ephemeris.rotation_clock.advance(240)
	var night_solar := Ephemeris.solar_state("Earth",amazon)
	check("destination solar clock advances twelve hours", absf(fposmod(night_solar.hour-noon_solar.hour,24)-12) < .05)
	check("destination solar elevation changes sign", noon_solar.elevation*night_solar.elevation < 0)
	first.refresh(Vector3.RIGHT*42157,0,"Earth")
	check("a zero-delta refresh uses current world time", (first.surface_basis("Earth")*amazon).dot(sun) < -.98)
	var second := EarthWorld.new()
	add_child(second)
	check("rebuilding world cannot reset rotation", second.surface_basis("Earth").is_equal_approx(first.surface_basis("Earth")))
	check("rendered globe matches terrain basis", first._bodies[0].sphere.basis.is_equal_approx(first.surface_basis("Earth")))
	var ship := Ship.new()
	add_child(ship)
	ship.newton = true
	ship.anchor_off = first.surface_basis("Earth")*amazon*6372
	var local_before := first.surface_basis("Earth").inverse()*ship.anchor_off
	ship._newton_corotate(60)
	Ephemeris.rotation_clock.advance(60)
	var local_after := first.surface_basis("Earth").inverse()*ship.anchor_off
	check("ship co-rotation keeps its terrain longitude", local_before.distance_to(local_after) < .002)
	ship.anchor_name = "Moon"
	ship.landed = true
	ship.anchor_off = Ephemeris.surface_basis("Moon")*amazon*1738
	local_before = Ephemeris.surface_basis("Moon").inverse()*ship.anchor_off
	ship._newton_corotate(60)
	Ephemeris.rotation_clock.advance(60)
	local_after = Ephemeris.surface_basis("Moon").inverse()*ship.anchor_off
	check("landed ship follows airless Moon surface", local_before.distance_to(local_after) < .002)
	ship.anchor_name = "Earth"
	ship.landed = false
	# Changing the rotation clock cannot change gravity integration in vacuum.
	ship.anchor_off = Vector3.RIGHT*100000
	ship.velocity = Vector3.ZERO
	ship._newton_advance(1.0)
	var fast_off := ship.anchor_off
	var fast_velocity := ship.velocity
	Ephemeris.rotation_clock.cycle_minutes = CelestialRotation.EARTH_ROTATION_DAY/60.0
	ship.anchor_off = Vector3.RIGHT*100000
	ship.velocity = Vector3.ZERO
	ship._newton_advance(1.0)
	check("day duration does not speed up ship physics", ship.anchor_off.is_equal_approx(fast_off) and ship.velocity.is_equal_approx(fast_velocity))
	Ephemeris.rotation_clock.cycle_minutes = 8.0
	# The frame hands the world the SAME accelerated time the ship integrated.
	ship.anchor_off = Vector3.RIGHT*100000
	ship._time_idx = 4
	ship.time_rate = 100
	ship._set_capture(false)
	ship.fly(.01)
	check("time warp publishes simulated seconds", ship.simulation_delta > .01)
	# Restoring a surface save retains both its landmark and heading after night passes.
	var controller := Controller.new()
	add_child(controller)
	controller.set_process(false)
	controller.ship = ship
	controller.combat = Combat.new()
	controller.add_child(controller.combat)
	controller._saved_anchor = "Earth"
	controller._saved_off = noon*amazon*6372
	controller._saved_surface_off = amazon*6372
	controller._saved_surface_basis = Basis.looking_at(DevSites.heading_forward(amazon,0),amazon)
	controller._restore_location()
	check("surface save stays at Amazon instead of jumping to GEO", (Ephemeris.surface_basis("Earth").inverse()*ship.anchor_off).distance_to(amazon*6372) < .002)
	check("surface save preserves local attitude", ship.transform.basis.y.dot(ship.anchor_off.normalized()) > .9999)
	# Horizon marching samples local terrain while shader lighting uses world axes.
	var patch := SurfacePatch.new()
	add_child(patch)
	var recipe := PlanetGenerator.recipe_for({"name":"Moon"})
	patch.bind_body(recipe,TerrainSampler.new(recipe))
	patch.basis = noon
	patch.set_view(sun,1,100)
	check("terrain shadow sun is body-local", patch._sun_dir.distance_to(noon.inverse()*sun) < .00001)
	check("terrain shader sun remains world-space", (patch._land_mat.get_shader_parameter("sun_dir") as Vector3).distance_to(sun) < .00001)
	Ephemeris.rotation_clock.unix_s = saved_time
	Ephemeris.rotation_clock.cycle_minutes = saved_cycle
	patch.queue_free()
	ship.queue_free()
	controller.queue_free()
	first.queue_free()
	second.queue_free()
	await get_tree().process_frame
	print("day_night: ", "OK" if failures == 0 else "FAIL %d" % failures)
	get_tree().quit(1 if failures else 0)
