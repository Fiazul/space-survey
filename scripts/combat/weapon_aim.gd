class_name WeaponAim
extends RefCounted
## Constant-velocity intercept in the same anchor frame as projectiles.
const ACQUIRE_DEG := 8.0
const ASSIST_DEG := 2.5

static func intercept(origin: Vector3, inherited: Vector3, target: Vector3,
		velocity: Vector3, speed: float, preferred_direction := Vector3.ZERO) -> Dictionary:
	var r := target-origin
	var v := velocity-inherited
	var a := v.length_squared()-speed*speed
	var b := 2.0*r.dot(v)
	var c := r.length_squared()
	var t := INF
	var roots: Array[float] = []
	if c < 1e-12:
		return {}
	if absf(a) < 1e-8:
		if absf(b) > 1e-8:
			roots.append(-c/b)
	else:
		var discriminant := b*b-4.0*a*c
		if discriminant >= 0:
			var root := sqrt(discriminant)
			roots.assign([(-b-root)/(2.0*a), (-b+root)/(2.0*a)])
	var score := -INF
	for value in roots:
		if not is_finite(value) or value <= 0:
			continue
		# At drift speeds above muzzle speed there can be TWO positive times.
		# Free-aim convergence must preserve the selected firing direction rather
		# than swinging the guns around to use the fastest backwards solution.
		var rank := -value if preferred_direction == Vector3.ZERO else (r+v*value).normalized().dot(preferred_direction.normalized())
		if rank > score:
			score = rank
			t = value
	if not is_finite(t) or t <= 0:
		return {}
	return {"time": t, "direction": (r+v*t).normalized(), "point": target+velocity*t}

static func acquire(origin: Vector3, inherited: Vector3, forward: Vector3,
		targets: Array, speed: float, preferred: Variant = null) -> Dictionary:
	var best := {}
	var score := INF
	for target in targets:
		if not target.get("alive", false):
			continue
		var offset: Vector3 = target.pos-origin
		var distance := offset.length()
		if distance > PlasmaProjectiles.RANGE*2.0 or distance < .00001:
			continue
		var angle := forward.angle_to(offset/distance)
		if angle > deg_to_rad(ACQUIRE_DEG):
			continue
		var rank := angle - (deg_to_rad(.8) if target == preferred else 0.0)
		if rank >= score:
			continue
		var solution := intercept(origin, inherited, target.pos, target.get("vel", Vector3.ZERO), speed)
		var in_range: bool = not solution.is_empty() and float(solution.time) <= PlasmaProjectiles.RANGE/speed
		best = {"target": target, "distance": distance, "intercept": solution,
			"in_range": in_range, "assist": in_range and forward.angle_to(solution.direction) <= deg_to_rad(ASSIST_DEG)}
		score = rank
	return best
