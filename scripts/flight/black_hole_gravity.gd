class_name BlackHoleGravity
extends RefCounted
# Ship gravity near a black hole: the Artemova, Björnsson & Novikov (1996, ApJ 461,
# 565) pseudo-Newtonian force F = GM / (r^(2-β) (r - r_H)^β), β = r_ISCO/r_H - 1.
# By construction it puts the innermost stable circular orbit exactly at Kerr's
# equatorial ISCO (Bardeen, Press & Teukolsky 1972) and diverges exactly at the
# horizon for every spin; at a = 0 it is Paczyński–Wiita (1980). Its marginally bound
# orbit lands within 2 % of Kerr's at a = 0.9 (Mukhopadhyay 2002 misses by 5 % and
# diverges outside the horizon for retrograde orbits, so it was not used).
# Spin enters through the ship's own orbit, a_eff = a cos i, i = tilt of the orbital
# angular momentum from SPIN_AXIS: exact for prograde and retrograde equatorial
# orbits, an interpolation in between. Frame dragging is unmodeled: the force is
# central, so tilted orbits do not Lense–Thirring precess; a gravitomagnetic term on
# top would double-count the spin already folded into β.

const C_KM_S := 299792.458
# black_hole.gdshader moves plasma along (-z, 0, x): the disk, and the prograde spin
# it shares, turn about -Y.
const SPIN_AXIS := Vector3.DOWN
# Orbital phase one integrator substep may cover near a hole (≈1260 substeps/orbit;
# the semi-implicit Euler orbit then wobbles about ±0.25 % in radius).
const STEP_RAD := 0.005
const SAMPLES := 48


static func isco_rg(a: float) -> float:
	var z1 := 1.0 + pow(1.0 - a*a, 1.0/3.0) * (pow(1.0 + a, 1.0/3.0) + pow(1.0 - a, 1.0/3.0))
	var z2 := sqrt(3.0*a*a + z1*z1)
	return 3.0 + z2 - signf(a) * sqrt(maxf((3.0 - z1) * (3.0 + z1 + 2.0*z2), 0.0))


static func photon_rg(a: float) -> float:
	return 2.0 * (1.0 + cos(2.0/3.0 * acos(clampf(-a, -1.0, 1.0))))


static func marginally_bound_rg(a: float) -> float:
	return 2.0 - a + 2.0 * sqrt(1.0 - a)


static func horizon_rg(a: float) -> float:
	return 1.0 + sqrt(1.0 - a*a)


# `recipe` is the hole's resolved stellar recipe (BlackHoleRecipe); missing Kerr
# fields fall back to the same closed forms. radius_km is the kill radius, so the
# force diverges exactly where the ship is lost.
static func params(hole_name: String, gm: float, radius_km: float, recipe: Dictionary) -> Dictionary:
	var a := clampf(float(recipe.get("spin", 0.0)), -0.998, 0.998)
	var r_g := float(recipe.get("gravitational_radius_km", gm / (C_KM_S * C_KM_S)))
	var horizon := radius_km if radius_km > 0.0 else float(recipe.get("horizon_km", horizon_rg(a) * r_g))
	return {"name": hole_name, "gm": gm, "spin": a, "r_g": r_g, "horizon_km": horizon,
		"isco_km": float(recipe.get("isco_km", isco_rg(a) * r_g)),
		"photon_km": float(recipe.get("photon_sphere_km", photon_rg(a) * r_g)),
		"photon_retro_km": float(recipe.get("photon_orbit_retro_km", photon_rg(-a) * r_g)),
		"marginally_bound_km": float(recipe.get("marginally_bound_km", marginally_bound_rg(a) * r_g))}


# Signed spin felt by an orbit: + prograde, - retrograde. The 1 km/s floor keeps a
# radial fall (no orbital plane) from picking a random sign.
static func effective_spin(h: Dictionary, rel: Vector3, vel: Vector3) -> float:
	var l := rel.cross(vel)
	var floor_l := rel.length()
	return float(h.spin) * l.dot(SPIN_AXIS) / sqrt(l.length_squared() + floor_l * floor_l)


static func orbit_spin(h: Dictionary, rel: Vector3, direction: Vector3) -> float:
	var l := rel.cross(direction)
	return float(h.spin) * l.dot(SPIN_AXIS) / l.length() if l.length_squared() > 0.0 else 0.0


static func beta(h: Dictionary, a: float) -> float:
	return isco_rg(a) * float(h.r_g) / float(h.horizon_km) - 1.0


static func pull(h: Dictionary, r: float, a: float) -> float:
	var rr := maxf(r, 1.0)
	var rh: float = h.horizon_km
	return float(h.gm) / (rr * rr) * pow(rr / maxf(rr - rh, rh * 1.0e-3), beta(h, a))


# Closed form of -∫ F dr from r to infinity (substitute u = r_H / r).
static func potential(h: Dictionary, r: float, a: float) -> float:
	var rh: float = h.horizon_km
	var b := beta(h, a)
	var u := clampf(1.0 - rh / maxf(r, rh), 1.0e-9, 1.0)
	if absf(1.0 - b) < 1.0e-6:
		return float(h.gm) / rh * log(u)
	return -float(h.gm) / rh * (1.0 - pow(u, 1.0 - b)) / (1.0 - b)


static func circular_speed(h: Dictionary, rel: Vector3, direction: Vector3) -> float:
	var r := rel.length()
	return sqrt(pull(h, r, orbit_spin(h, rel, direction)) * r)


# Kerr equatorial Keplerian frequency, Ω = √GM / (r^1.5 + a r_g^1.5).
static func kepler_hz(h: Dictionary, r: float, a: float) -> float:
	var r_g: float = h.r_g
	return sqrt(float(h.gm)) / (pow(maxf(r, float(h.horizon_km)), 1.5) + a * pow(r_g, 1.5)) / TAU


# dτ/dt from the Kerr equatorial metric (Boyer–Lindquist) at the ship's measured r,
# radial speed and orbital angular speed. The pseudo-Newtonian path is not a
# geodesic, so a state the metric forbids reads 0 rather than NaN.
static func clock_rate(h: Dictionary, r: float, v_radial: float, v_orbital: float, a: float) -> float:
	var x := r / float(h.r_g)
	var br := v_radial / C_KM_S
	var om := v_orbital / C_KM_S / x
	var delta := maxf(x*x - 2.0*x + a*a, 1.0e-9)
	var f := (1.0 - 2.0/x) + 4.0*a/x*om - x*x/delta*br*br - (x*x + a*a + 2.0*a*a/x)*om*om
	return sqrt(maxf(f, 0.0))


static func _v_eff(h: Dictionary, a: float, l: float, r: float) -> float:
	return potential(h, r, a) + l*l / (2.0*r*r)


# Highest point of the effective potential between the horizon and r: an inbound
# orbit with more energy than this has no periapsis left.
static func _barrier(h: Dictionary, a: float, l: float, r: float) -> float:
	var rh: float = h.horizon_km
	var top := _v_eff(h, a, l, r)
	var hi := log(r - rh)
	var lo := log(rh * 1.0e-4)
	for i in SAMPLES:
		top = maxf(top, _v_eff(h, a, l, rh + exp(lerpf(hi, lo, float(i + 1) / SAMPLES))))
	return top


static func _turns_back_out(h: Dictionary, a: float, l: float, e: float, r: float) -> bool:
	if e < 0.0:
		return true
	var rr := r
	for i in 40:
		rr *= 1.25
		if _v_eff(h, a, l, rr) >= e:
			return true
	return false


# Radial travel time between r_from and r_to, substituting s = √|r - r_turn| so a
# turning point (a braked ship at rest, an apoapsis) does not blow up the 1/v_r.
static func _travel_s(h: Dictionary, a: float, l: float, e: float, r_turn: float, r_far: float) -> float:
	var span := sqrt(absf(r_far - r_turn))
	var sign := signf(r_far - r_turn)
	var n := SAMPLES * 2
	var t := 0.0
	for i in n:
		var q := span * (float(i) + 0.5) / n
		var speed := sqrt(maxf(2.0 * (e - _v_eff(h, a, l, r_turn + sign * q * q)), 1.0))
		t += 2.0 * q * span / n / speed
	return t


static func _inbound_s(h: Dictionary, a: float, l: float, e: float, r: float) -> float:
	return _travel_s(h, a, l, e, r, float(h.horizon_km))


static func _outbound_s(h: Dictionary, a: float, l: float, e: float, r: float) -> float:
	var hi := r
	for i in 40:
		hi *= 1.25
		if _v_eff(h, a, l, hi) >= e:
			break
	var lo := hi / 1.25
	for i in 40:
		var mid := (lo + hi) * 0.5
		if _v_eff(h, a, l, mid) >= e:
			hi = mid
		else:
			lo = mid
	return _travel_s(h, a, l, e, lo, r)


static func _plunges(h: Dictionary, a: float, l: float, e: float, r: float, v_radial: float) -> bool:
	var returns := v_radial <= 0.0 or _turns_back_out(h, a, l, e, r)
	return returns and e >= _barrier(h, a, l, r)


# [r, radial speed, orbital speed] in 64-bit scalars. Vector3 math is float32 here:
# a braked ship's inbound kinetic energy (~15 km²/s²) is far below the float32
# rounding of v² at orbital speeds and decided whether it plunged (ADR-0002).
static func _split(rel: Vector3, vel: Vector3) -> PackedFloat64Array:
	var x := float(rel.x)
	var y := float(rel.y)
	var z := float(rel.z)
	var r := sqrt(x*x + y*y + z*z)
	var vx := float(vel.x)
	var vy := float(vel.y)
	var vz := float(vel.z)
	var vr := (x*vx + y*vy + z*vz) / r
	var tx := vx - x / r * vr
	var ty := vy - y / r * vr
	var tz := vz - z / r * vr
	return PackedFloat64Array([r, vr, sqrt(tx*tx + ty*ty + tz*tz)])


static func plunges(h: Dictionary, rel: Vector3, vel: Vector3) -> bool:
	var s := _split(rel, vel)
	if s[0] <= float(h.horizon_km):
		return true
	var a := effective_spin(h, rel, vel)
	return _plunges(h, a, s[0] * s[2], 0.5 * (s[1]*s[1] + s[2]*s[2]) + potential(h, s[0], a), s[0], s[1])


# Cheapest single impulse (km/s vector) after which plunges() is false. Burns lie in
# the plane of the radius and the orbital (at rest: prograde) direction: BURN_DIRS
# headings, then the best one refined to 1/8 of the spacing. Every candidate is re-run
# through the full plunge test, so cancelling the inward speed alone never counts —
# with no angular momentum that still falls. The residual heading error costs under
# 0.1 %; BURN_MARGIN keeps the reported burn off the knife-edge orbit that just grazes
# the barrier. Vector3.ZERO when nothing under c escapes.
const BURN_DIRS := 16
const BURN_MARGIN := 1.02

static func escape_burn(h: Dictionary, rel: Vector3, vel: Vector3) -> Vector3:
	var radial := rel.normalized()
	var along := vel - radial * vel.dot(radial)
	if along.length() < 1.0e-3:
		along = SPIN_AXIS.cross(radial)
		if along.length_squared() < 1.0e-6:
			along = radial.cross(Vector3.RIGHT if absf(radial.x) < .9 else Vector3.FORWARD)
	along = along.normalized()
	var found := [INF, 0.0]
	var spacing := TAU / BURN_DIRS
	for k in BURN_DIRS:
		_try_heading(h, rel, vel, radial, along, PI * .5 + spacing * k, found)
	var width := spacing
	for i in 3:
		width *= .5
		var centre: float = found[1]
		_try_heading(h, rel, vel, radial, along, centre - width, found)
		_try_heading(h, rel, vel, radial, along, centre + width, found)
	if found[0] == INF:
		return Vector3.ZERO
	return (radial * cos(found[1]) + along * sin(found[1])) * found[0] * BURN_MARGIN


# found = [best magnitude, its heading]; a heading that still plunges at the best
# magnitude so far costs one test.
static func _try_heading(h: Dictionary, rel: Vector3, vel: Vector3, radial: Vector3,
		along: Vector3, heading: float, found: Array) -> void:
	var dir := radial * cos(heading) + along * sin(heading)
	var best: float = found[0]
	var hi := 0.0
	if best < INF:
		if plunges(h, rel, vel + dir * best):
			return
		hi = best
	else:
		var step := 1.0
		while step < C_KM_S:
			if not plunges(h, rel, vel + dir * step):
				hi = step
				break
			step *= 2.0
		if hi == 0.0:
			return
	var lo := 0.0
	for i in 14:
		var mid := (lo + hi) * 0.5
		if plunges(h, rel, vel + dir * mid):
			lo = mid
		else:
			hi = mid
	found[0] = hi
	found[1] = heading


static func orbit_state(h: Dictionary, rel: Vector3, vel: Vector3) -> Dictionary:
	var split := _split(rel, vel)
	var r := split[0]
	var a := effective_spin(h, rel, vel)
	var r_g: float = h.r_g
	var out := {"r": r, "spin": a, "isco_km": isco_rg(a) * r_g, "photon_km": photon_rg(a) * r_g,
		"plunging": false,
		"clock_rate": 0.0, "kepler_hz": kepler_hz(h, r, a)}
	if r <= float(h.horizon_km):
		out.plunging = true
		return out
	var vr := split[1]
	var vt := split[2]
	out.clock_rate = clock_rate(h, r, vr, vt, a)
	var l := r * vt
	var e := 0.5 * (vr*vr + vt*vt) + potential(h, r, a)
	if not _plunges(h, a, l, e, r, vr):
		return out
	out.plunging = true
	return out


# What the ship's orbit does with engines off, and the burn that would stop a plunge
# (escape_burn). `thrust` is the ship's best sustained acceleration; no_escape means
# even that, held all the way to the horizon, delivers less Δv than the burn needs.
static func orbit(h: Dictionary, rel: Vector3, vel: Vector3, thrust: float) -> Dictionary:
	var out := orbit_state(h, rel, vel)
	out.merge({"no_escape": false, "dv_kms": 0.0, "burn": Vector3.ZERO, "fall_s": INF})
	if float(out.r) <= float(h.horizon_km):
		out.no_escape = true
		return out
	if not out.plunging: return out
	var split := _split(rel, vel)
	var r: float = out.r
	var a: float = out.spin
	var vr := split[1]
	var vt := split[2]
	var l := r * vt
	var e := 0.5 * (vr*vr + vt*vt) + potential(h, r, a)
	var fall := _inbound_s(h, a, l, e, r)
	if vr > 0.0:
		fall += 2.0 * _outbound_s(h, a, l, e, r)
	out.fall_s = fall
	var burn := escape_burn(h, rel, vel)
	out.burn = burn
	out.dv_kms = burn.length() if burn != Vector3.ZERO else INF
	out.no_escape = thrust * fall < out.dv_kms
	return out


# 0 at `reach` ISCO radii (for this orbit's spin), 1 at the horizon, log in between.
static func proximity(h: Dictionary, r: float, a: float, reach: float) -> float:
	var rh: float = h.horizon_km
	var outer := reach * isco_rg(a) * float(h.r_g)
	if r >= outer:
		return 0.0
	return clampf(log(outer / maxf(r, rh)) / log(outer / rh), 0.0, 1.0)
