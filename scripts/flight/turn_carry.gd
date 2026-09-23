class_name TurnCarry
extends RefCounted
# Sol steering assist carries forward flight, never a backwards fall or side-slip.
const FORWARD_CONE_COS := 0.8660254 # 30 degrees


static func apply(vel: Vector3, old_b: Basis, new_b: Basis) -> Vector3:
	if vel.length_squared() < 1e-12 or vel.normalized().dot(-old_b.z) < FORWARD_CONE_COS:
		return vel
	return new_b * (old_b.inverse() * vel)
