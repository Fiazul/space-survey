class_name ShipAssistant
extends RefCounted
## Frame-independent control: callers supply clearance, surface normal and
## velocity relative to the support. Works for terrain and moving berths.
const SAFE_CLEARANCE := .035
const WATCH_CLEARANCE := .08
const MAX_ACCEL := .025
const MAX_LEVEL_RATE := deg_to_rad(6.0) # gentle attitude motion, never a force

static func correction(clearance: float, normal: Vector3, relative_velocity: Vector3,
		gravity: Vector3, pilot_accel: Vector3, landing_approach: bool, delta: float) -> Vector3:
	var closing := maxf(0.0,-relative_velocity.dot(normal))
	var outward := relative_velocity.dot(normal)
	var net_brake := maxf(.003,MAX_ACCEL+gravity.dot(normal))
	var stopping := closing*closing/(2.0*net_brake)
	if not landing_approach and (outward > .015 or clearance > WATCH_CLEARANCE+stopping):
		return Vector3.ZERO
	if landing_approach and (clearance > .3 or relative_velocity.length() > .06):
		return Vector3.ZERO
	var acceleration := -gravity
	if landing_approach:
		# Uncommanded drift settles; Ctrl/Space retains vertical authority over a pad.
		if absf(pilot_accel.dot(normal)) < .0001:
			acceleration -= normal*relative_velocity.dot(normal)*1.8
	else:
		var desired := clampf((SAFE_CLEARANCE-clearance)*1.5,0.0,.025)
		var hold := (desired-outward)*2.5
		# Without vertical intent the hold works both ways. Push-only output just
		# cancels gravity, so the hull coasts out of the band, drops and bobs.
		if absf(pilot_accel.dot(normal)) >= .0001: hold = maxf(0.0,hold)
		acceleration += normal*hold
		# A held descend command cannot push through unapproved ground.
		acceleration -= normal*minf(0.0,pilot_accel.dot(normal))
	var drift := relative_velocity.slide(normal)
	if pilot_accel.slide(normal).length() < .0001:
		acceleration -= drift*minf(1.8,1.0/maxf(delta,.001))
	return acceleration.limit_length(MAX_ACCEL)

static func level(pose: Basis, up: Vector3, delta: float, ease: float) -> Basis:
	var forward := (-pose.z).slide(up)
	if forward.length_squared() < .0001 or absf(forward.normalized().dot(up)) > .999:
		forward = pose.x.cross(up)
	forward = forward.normalized()
	var right := forward.cross(up).normalized()
	var target := Basis(right,right.cross(forward).normalized(),-forward)
	var current := pose.orthonormalized()
	var angle := current.get_rotation_quaternion().angle_to(target.get_rotation_quaternion())
	if angle < .000001: return target
	var step := MAX_LEVEL_RATE*maxf(0.0,ease)*maxf(0.0,delta)
	return current.slerp(target,minf(1.0,step/angle)).orthonormalized()
