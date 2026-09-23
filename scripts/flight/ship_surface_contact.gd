class_name ShipSurfaceContact
extends RefCounted
## Broad sphere only selects work. Actual support uses oriented hull probes and
## the rig's footpad corners. Buildings use the full projected hull volume.
const SKIN := .00025
const SLOP := .0001

static func hull_points(box: AABB) -> PackedVector3Array:
	var points := PackedVector3Array()
	for i in 8:
		points.append(box.get_endpoint(i))
	var center := box.get_center()
	for axis in 3:
		for side in [-1.0, 1.0]:
			var point := center
			point[axis] += box.size[axis] * .5 * side
			points.append(point)
	points.append(center)
	return points

static func resolve(sampler: TerrainSampler, from: Vector3, to: Vector3,
		velocity: Vector3, radius: float, basis: Basis, box: AABB,
		hull_probes: PackedVector3Array, feet: PackedVector3Array) -> Dictionary:
	var bound := 0.0
	for point in hull_probes:
		bound = maxf(bound, point.length())
	for point in feet:
		bound = maxf(bound, point.length())
	var broad := sampler.resolve_motion(from, to, velocity, radius, bound + SKIN)
	if not broad.hit:
		broad["gear_hit"] = false
		return broad
	var result := {"hit": false, "position": to, "velocity": velocity,
		"normal": Vector3.ZERO, "budget_limited": false, "gear_hit": false}
	var points := hull_probes.duplicate()
	points.append_array(feet)
	# Project onto all touched supports; footpad points are never substituted by
	# the old 90 m sphere. Queries share TerrainSampler's height and sweep logic.
	for i in points.size():
		var offset := basis * points[i]
		var hit := sampler._resolve_terrain_motion(from + offset, result.position + offset,
			result.velocity, radius, SKIN, SLOP)
		if hit.hit or hit.budget_limited:
			result.position = hit.position - offset
			result.velocity = hit.velocity
			result.hit = result.hit or hit.hit
			result.budget_limited = result.budget_limited or hit.budget_limited
			result.normal = hit.normal
			if hit.hit and i >= hull_probes.size():
				result.gear_hit = true
	# Cover the hull interior too: point probes alone can miss a narrow wall
	# between their sample locations. Padding is projected from oriented extents.
	var center := basis * box.get_center()
	var wall := sampler.resolve_structure_hull(from + center, result.position + center,
		result.velocity, radius, SKIN, basis, box.size*.5)
	if wall.hit or wall.budget_limited:
		result.position = wall.position - center
		result.velocity = wall.velocity
		result.hit = result.hit or wall.hit
		result.normal = wall.normal
		result.budget_limited = result.budget_limited or wall.budget_limited
	for point in feet:
		var offset := basis * point
		var hit := sampler.resolve_structure_hull(from + offset, result.position + offset,
			result.velocity, radius, SKIN, basis, Vector3.ZERO)
		if hit.hit or hit.budget_limited:
			result.position = hit.position - offset
			result.velocity = hit.velocity
			result.hit = result.hit or hit.hit
			result.normal = hit.normal
			result.budget_limited = result.budget_limited or hit.budget_limited
			result.gear_hit = result.gear_hit or hit.hit
	# A second, stationary query after flight is outside the separation skin.
	# Confirm support across that tiny gap without snapping a taking-off ship back.
	if not result.gear_hit and result.velocity.length() < .003 and velocity.dot(to.normalized()) <= 0.0:
		var down := -to.normalized() * .002
		for point in feet:
			var pad: Vector3 = result.position + basis * point
			var support := sampler.resolve_motion(pad, pad + down, Vector3.ZERO, radius, SKIN)
			if support.hit and support.normal.dot(to.normalized()) > .85:
				result.gear_hit = true
				result.normal = support.normal
				break
	return result
