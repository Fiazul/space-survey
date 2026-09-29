class_name MinutePilot
extends RefCounted
## Scripted pilot for the playable minute (docs/plans/2026-09-29-playable-minute.md),
## shared by tools/test_playable_minute and tools/render_playable_minute. It turns
## the hull directly (a perfect stick) and flies only through the ship's own
## inputs: touch thrust, Shift boost, Space lift, gear, time-warp keys.
## Above the skin the ship is inertial while the pad rides the planet east
## (~0.41 km/s at LC-39A), so in vacuum the pilot holds station over the pad.
const G := .00980665
const TURN_RATE := deg_to_rad(90.0)
const APOGEE_AIM_KM := 320.0
const SKIN_KM := 100.0
const HOLD_KM := .12
const WARP := 50.0
const BRAKE_G := 7.0
const RETURN_VR_KMS := -.5

var ship: Ship
var site: Dictionary
var phase := "lift"
var t_phase := 0.0

func _init(pilot_ship: Ship, pad_site: Dictionary) -> void:
	ship = pilot_ship
	site = pad_site

func done() -> bool:
	return phase == "land" and not ship.landing_site.is_empty()

func drive(dt: float) -> void:
	var alt := altitude()
	var up := ship.anchor_off.normalized()
	var vr := ship.velocity.dot(up)
	t_phase += dt
	match phase:
		"lift":
			key(KEY_SPACE, true)
			if t_phase > 1.5 and ship.landing_site.is_empty():
				key(KEY_SPACE, false)
				ship.toggle_gear()
				_next("ascent")
		"ascent":
			aim(up, dt)
			ship.touch_thrust = 1.0
			key(KEY_SHIFT, alt > .5)
			if vr > .5 and ballistic(alt, vr).apo >= APOGEE_AIM_KM:
				_cut()
				_next("coast")
		"coast":
			if not _hold_station(alt, dt): aim(up if alt < SKIN_KM+20.0 else -up, dt)
			if vr < 0.0: _next("return")
		"return":
			aim(-up, dt)
			ship.touch_thrust = 1.0 if ship.transform.basis.z.dot(up) > .99 else 0.0
			key(KEY_SHIFT, ship.touch_thrust > 0.0)
			if vr <= RETURN_VR_KMS or t_phase > 20.0:
				_cut()
				_next("fall")
		"fall":
			if not _hold_station(alt, dt): aim(-up, dt)
			if alt < SKIN_KM: _next("brake")
		"brake":
			var a := guidance(HOLD_KM)
			aim(a.normalized(), dt)
			var mag := a.length()
			key(KEY_SHIFT, mag > 3.0*G)
			ship.touch_thrust = clampf(mag/(9.0*G if mag > 3.0*G else 3.0*G), 0.0, 1.0)
			var e := pad_error()
			if e.h < .03 and absf(e.v-HOLD_KM) < .04 and rel_velocity().length() < .008:
				_cut()
				ship.toggle_gear()
				_next("land")
		"land":
			var pad_basis: Basis = ship.terrain_basis*site.transform.basis
			aim_basis(pad_basis, dt)
			var level := ship.transform.basis.y.dot(pad_basis.y) > .995
			ship.touch_pitch = 1.0 if level and ship.systems.gear_fraction >= .999 and ship.landing_site.is_empty() else 0.0

func _next(name: String) -> void:
	phase = name
	t_phase = 0.0

func _cut() -> void:
	ship.touch_thrust = 0.0
	key(KEY_SHIFT, false)

func altitude() -> float:
	return ship.anchor_distance_km()-6371.0

# Radial free flight under gravity alone: the apogee from here.
func ballistic(alt: float, vr: float) -> Dictionary:
	var mu := G*6371.0*6371.0
	var r := 6371.0+alt
	var out := {"apo": alt}
	for i in 3000:
		vr -= mu/(r*r)
		r += vr
		out.apo = maxf(out.apo, r-6371.0)
		if vr < 0.0: break
	return out

# Above the skin, burn off horizontal drift against the pad (closing on it slowly)
# before warping; true while a correction burn is under way.
func _hold_station(alt: float, dt: float) -> bool:
	if alt <= SKIN_KM+1.0:
		_cut()
		return false
	var n := pad_point().normalized()
	var h_err: Vector3 = (pad_error().d as Vector3).slide(n)
	var want := -h_err.normalized()*minf(h_err.length()*.01, .3) if h_err.length() > .01 else Vector3.ZERO
	var dv := want-rel_velocity().slide(n)
	if dv.length() < .01:
		_cut()
		if ship.time_rate < WARP: tap(KEY_PERIOD)
		return false
	aim(dv.normalized(), dt)
	# Ship ignores thrust under 0.01 km/s^2 (its g_thrusting floor), so never ask for less.
	ship.touch_thrust = clampf(dv.length()/.03, .4, 1.0) if (-ship.transform.basis.z).dot(dv.normalized()) > .98 else 0.0
	key(KEY_SHIFT, ship.touch_thrust > 0.0 and dv.length() > .1)
	return true

func pad_point() -> Vector3:
	var xf: Transform3D = site.transform
	return ship.terrain_basis*xf.origin

# Velocity over the ground: inside the air the ship already rides the planet.
func rel_velocity() -> Vector3:
	if altitude() < Ephemeris.atmo_top_km("Earth"): return ship.velocity
	return ship.velocity-Vector3.UP.cross(pad_point())*Ephemeris.scene_spin_rad_s("Earth")

func pad_error() -> Dictionary:
	var pad := pad_point()
	var d := ship.anchor_off-pad
	var n := pad.normalized()
	return {"h": d.slide(n).length(), "v": d.dot(n), "d": d}

# Thrust wanted (gravity included) to arrive `hold_km` above the pad on a
# BRAKE_G braking curve, leaving margin under the 9 g boost.
func guidance(hold_km: float) -> Vector3:
	var e := pad_error()
	var n := pad_point().normalized()
	var h_err: Vector3 = (e.d as Vector3).slide(n)
	var above := float(e.v)-hold_km
	var vh_des := -h_err.normalized()*minf(h_err.length()*.08, 1.5) if h_err.length() > .001 else Vector3.ZERO
	var vv_des := clampf(-signf(above)*sqrt(2.0*BRAKE_G*G*absf(above)), -3.0, 3.0)
	if absf(above) < .05: vv_des = -above*.5
	return (vh_des+n*vv_des-rel_velocity())/1.5+n*G

func aim(dir: Vector3, dt: float) -> void:
	var nose := -ship.transform.basis.z
	var axis := nose.cross(dir)
	var ang := nose.angle_to(dir)
	if axis.length() < 1e-6 or ang < 1e-5: return
	ship.transform.basis = (Basis(axis.normalized(), minf(ang, TURN_RATE*dt))*ship.transform.basis).orthonormalized()

func aim_basis(target: Basis, dt: float) -> void:
	var q := Quaternion(ship.transform.basis.orthonormalized())
	var to := Quaternion(target.orthonormalized())
	var ang := q.angle_to(to)
	if ang < 1e-6: return
	ship.transform.basis = Basis(q.slerp(to, minf(1.0, TURN_RATE*dt/ang)))

func key(code: Key, pressed: bool) -> void:
	if Input.is_physical_key_pressed(code) == pressed: return
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func tap(code: Key) -> void:
	key(code, true)
	key(code, false)

func release() -> void:
	for code in [KEY_SPACE, KEY_CTRL, KEY_SHIFT, KEY_W, KEY_S]: key(code, false)
	ship.touch_thrust = 0.0
	ship.touch_pitch = 0.0
