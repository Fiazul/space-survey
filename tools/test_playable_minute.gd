class_name TestPlayableMinute
extends Node3D
## The playable minute (docs/plans/2026-09-29-playable-minute.md) at dt 1/60 in
## main's per-frame order: berth on LC-39A, lift off, boost through the skin,
## coast past 300 km, return burn, re-enter, re-lock on the same pad.
## LANDING_CLOCK=<unix_s>|wall replays another rotation phase; MINUTE_VERBOSE=1 traces.
const MainScript := preload("res://scripts/core/main.gd")
const HudScript := preload("res://scripts/ui/hud.gd")
const PAD_ID := "kennedy_lc39a"
const DT := 1.0/60.0

class StubPlanets extends PlanetSystem:
	var ship_ref: Ship
	var sampler_ref: TerrainSampler
	func is_physical(body: String) -> bool:
		return body == "Earth"
	func terrain_sampler_for(_body: String) -> TerrainSampler:
		return sampler_ref
	func surface_basis(body: String) -> Basis:
		return Ephemeris.surface_basis(body)
	func surface_angle(body: String) -> float:
		return Ephemeris.surface_angle(body)
	func rel_of(_body: String) -> Vector3:
		return -ship_ref.anchor_off
	func refresh(_off: Vector3, _delta: float, _anchor := "", _vel: Vector3 = Vector3.ZERO) -> void:
		pass

var failures := 0
var ship: Ship
var main: Node
var planets: StubPlanets
var earth: TerrainSampler
var site: Dictionary
var verbose := OS.get_environment("MINUTE_VERBOSE") != ""

func _ready() -> void:
	ProfileDir.isolate("test_playable_minute")
	var clock := OS.get_environment("LANDING_CLOCK")
	if clock != "wall": Ephemeris.rotation_clock.unix_s = float(clock) if clock != "" else 1.8e9
	earth = PlanetGenerator.terrain_sampler(PlanetGenerator.recipe_for({"name":"Earth"}))
	for s in earth.facilities:
		if s.id == PAD_ID: site = s
	check("LC-39A exists in the Earth recipe", not site.is_empty())
	ship = Ship.new()
	add_child(ship)
	ship._set_capture(false)
	ship.newton = true
	ship.dev_speed = false
	ship.set_anchor("Earth")
	ship.terrain = earth
	ship.nearest_name = "Earth"
	ship.nearest_radius = 6371.0
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
	if not site.is_empty(): _fly()
	main.free()
	hud.free()
	planets.free()
	ship.queue_free()
	await get_tree().process_frame
	print("playable_minute: ", "OK" if failures == 0 else "FAIL %d" % failures)
	get_tree().quit(0 if failures == 0 else 1)

func _fly() -> void:
	var booted := ship.berth_on_pad(PAD_ID, earth, Ephemeris.surface_basis("Earth"), Ephemeris.surface_angle("Earth"))
	check("boot berths on LC-39A", booted and ship.landing_site_id == PAD_ID and ship.landed)
	check("boot gear is down", ship.systems.gear_target and ship.systems.gear_fraction >= .999)
	for i in 30: step()
	check("pad lock holds at boot", ship.landing_site_id == PAD_ID and ship.velocity.length() < 1e-6)
	if ship.landing_site.is_empty(): return
	var pilot := MinutePilot.new(ship, site)
	var frames := 0
	var sim_s := 0.0
	var max_alt := 0.0
	var left_skin := false
	var returned := false
	var load_at_entry := -1.0
	var load_peak := 0.0
	while frames < int(180.0/DT) and not pilot.done():
		pilot.drive(DT)
		var before := pilot.altitude()
		step()
		frames += 1
		sim_s += ship.simulation_delta
		var alt := pilot.altitude()
		left_skin = left_skin or alt > MinutePilot.SKIN_KM
		if left_skin: max_alt = maxf(max_alt, alt)
		if left_skin and before >= MinutePilot.SKIN_KM and alt < MinutePilot.SKIN_KM: returned = true
		if returned:
			if load_at_entry < 0.0: load_at_entry = ship.air_load
			load_peak = maxf(load_peak, ship.air_load)
		if verbose and frames % 120 == 0:
			var e := pilot.pad_error()
			print("  t=%5.1f sim=%6.1f %-6s alt=%8.3f vr=%+.4f v=%.4f load=%.6f mach=%.2f warp=%.0f pad_h=%.3f pad_v=%.3f sup=%s" % [frames*DT, sim_s, pilot.phase, alt, ship.velocity.dot(ship.anchor_off.normalized()), ship.velocity.length(), ship.air_load, ship.mach_number, ship.time_rate, e.h, e.v, ship.support_active])
	pilot.release()
	print("playable_minute: flight %.1f s at dt 1/60 (%d frames), %.1f s simulated, apogee %.1f km, re-entry air load %.6f -> peak %.6f" % [frames*DT, frames, sim_s, max_alt, load_at_entry, load_peak])
	check("leaves the skin above 100 km", left_skin)
	check("apogee at least 300 km", max_alt >= 300.0)
	check("comes back inside 100 km", returned)
	check("air load rises on re-entry past 0.3", load_peak >= 0.3 and load_peak > load_at_entry)
	check("re-locks on LC-39A", ship.landing_site_id == PAD_ID)
	check("loop under 3 min at dt 1/60", frames*DT < 180.0)

# One game frame in main's order.
func step() -> void:
	ship.nearest_dist = ship.anchor_off.length()
	ship.nearest_dir = -ship.anchor_off.normalized()
	ship.fly(DT)
	Ephemeris.rotation_clock.advance(ship.simulation_delta)
	ship.set_terrain_frame(Ephemeris.surface_basis("Earth"), Ephemeris.surface_angle("Earth"))
	main.call("_update_skin_kill", DT)

func check(label: String, ok: bool) -> void:
	if not ok:
		failures += 1
		print("playable_minute: FAIL ", label)
