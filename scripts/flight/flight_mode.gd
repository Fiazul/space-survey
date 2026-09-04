class_name FlightMode
extends RefCounted
# Zone is where. Mode is how. Exclusion is the no-cruise bubble (Elite EZ, real size).

const CRUISE := "CRUISE"
const LOCAL := "LOCAL"
const AIR := "AIR"


const STAR_CHROMOSPHERE_KM := 2500.0   # real chromosphere; corona is visual, not a cruise wall
const AIRLESS_EZ_KM := 10.0            # dump before the skin; vacuum has no 25% fake air


# --- Skin-band speed cap ---
# Contact kill compares the hull against terrain every frame. Unbounded, MAX_SPEED
# is 10,000 units/s and 1 unit = 1 km, so 10,000 km/s - at 60 fps that is 166 km
# per frame, and the hull steps over whole mountain ranges between samples. The cap
# is therefore a CORRECTNESS requirement of contact kill, not flight polish.
#
# Read it as: the closer you are to rock, the less you may move per frame.
# Presented in-world as an atmospheric flight limit, not an invisible wall.
const BAND_CAP_ANCHORS := [
	[100.0, 2000.0],
	[15.0, 600.0],
	[5.0, 300.0],
	[1.0, 150.0],
	[0.2, 60.0],
]
# The frame time the anti-tunnelling bound is PROVEN against. 20 fps, not 60: the
# bound has to hold when the frame rate dips, which is exactly the moment a
# point-sampled contact test would miss a mountain.
const WORST_FRAME_S := 0.05


# Speed ceiling in METRES PER SECOND at this height above LOCAL GROUND.
static func band_speed_cap_ms(alt_above_ground_km: float) -> float:
	var a: Array = BAND_CAP_ANCHORS
	var last: int = a.size() - 1
	if alt_above_ground_km >= float(a[0][0]):
		return float(a[0][1])
	if alt_above_ground_km <= float(a[last][0]):
		return float(a[last][1])
	for i in range(last):
		var hi: Array = a[i]
		var lo: Array = a[i + 1]
		if alt_above_ground_km <= float(hi[0]) and alt_above_ground_km >= float(lo[0]):
			var t: float = (alt_above_ground_km - float(lo[0])) / (float(hi[0]) - float(lo[0]))
			return lerpf(float(lo[1]), float(hi[1]), t)
	return float(a[last][1])


# The same cap in UNITS PER SECOND, which is what ship.speed_limit consumes.
#
# THIS DIVISION IS THE WHOLE POINT OF THIS FUNCTION EXISTING. 1 unit = 1 km in
# Sol, so a 600 m/s cap is 0.6. Handing 600.0 to speed_limit means 600 km/s: every
# "the cap is applied" assertion still passes and the anti-tunnelling guarantee is
# silently void. Convert here and nowhere else.
static func band_speed_cap_units(alt_above_ground_km: float) -> float:
	return band_speed_cap_ms(alt_above_ground_km) / 1000.0


static func exclusion_from_center(radius: float, air_top: float, is_star: bool) -> float:
	if is_star:
		return radius + STAR_CHROMOSPHERE_KM
	if air_top > 0.0:
		return radius + air_top
	return radius + AIRLESS_EZ_KM


static func can_cruise(zone: String, dist: float, exclusion: float) -> bool:
	if zone != "SPACE":
		return false
	return dist > exclusion


static func of(zone: String, time_rate: float, cruise_ok: bool) -> String:
	if zone == "AIR":
		return AIR
	if zone == "SPACE":
		if time_rate > 1.001 and cruise_ok:
			return CRUISE
		return LOCAL
	return zone


static func must_drop(zone: String, time_rate: float, dist: float, exclusion: float) -> bool:
	return time_rate > 1.001 and not can_cruise(zone, dist, exclusion)


# If a step starts outside EZ and would enter or punch through, sit on the shell
# and dump speed. Already inside: leave it (air drag / skin kill own that).
#
# `dump_speed` (units/s) is what you keep, along your existing heading. It used to
# be a hard zero, which stopped you dead on the shell every single approach. That
# read as hitting a wall rather than entering atmosphere, and it got worse once the
# band became somewhere you want to fly: the Moon's shell is at 10 km and its band
# ceiling is 5.27 km, so you would come to a full stop and then have to
# re-accelerate into a capped band. Pass the band cap for that altitude instead.
# Zero is still accepted, and still means a dead stop.
static func break_at_exclusion(pos: Vector3, vel: Vector3, dt: float, center: Vector3,
		ez: float, dump_speed: float) -> Dictionary:
	var miss := { "pos": pos, "vel": vel, "dropped": false }
	if dt <= 0.0 or ez <= 0.0:
		return miss
	var w: Vector3 = pos - center
	var r0 := w.length()
	if r0 <= ez:
		return miss
	var a := vel.length_squared()
	if a < 1.0e-16:
		return miss
	var b := 2.0 * vel.dot(w)
	var c := r0 * r0 - ez * ez
	var disc := b * b - 4.0 * a * c
	var t := -1.0
	if disc >= 0.0:
		t = (-b - sqrt(disc)) / (2.0 * a)
	var end: Vector3 = pos + vel * dt
	var ends_inside := (end - center).length() <= ez
	if t <= 0.0 or t > dt:
		if not ends_inside:
			return miss
		t = clampf((-b) / (2.0 * a), 0.00001, dt)
	var hit: Vector3 = pos + vel * t
	var n: Vector3 = hit - center
	if n.length_squared() < 1.0e-12:
		n = w
	n = n.normalized()
	# Keep the heading, clamp the magnitude. Never speed anyone UP: a ship already
	# slower than the cap keeps its own speed.
	var kept := Vector3.ZERO
	if dump_speed > 0.0 and vel.length_squared() > 1.0e-16:
		kept = vel.normalized() * minf(vel.length(), dump_speed)
	return { "pos": center + n * ez, "vel": kept, "dropped": true }
