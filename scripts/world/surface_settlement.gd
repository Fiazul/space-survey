class_name SurfaceSettlement
extends RefCounted
## Seeded abandoned districts. Layouts are fictional, geography stays recognizable.
## The exact same boxes define rendering and swept ship collision.
const STEP := 0.12 # km; streets occupy the gaps between plots
const DRAW_REACH := 2.8
const DRAW_BUDGET := 1800
const MAX_HEIGHT := 0.26
const EARTH_DISTRICTS := [
	["London remains", 51.51, -0.12, 5.0, 11],
	["Paris remains", 48.86, 2.35, 5.0, 19],
	["Cairo remains", 30.04, 31.24, 5.0, 23],
	["Lagos remains", 6.52, 3.38, 4.0, 29],
	["Nairobi remains", -1.29, 36.82, 4.0, 31],
	["Johannesburg remains", -26.20, 28.04, 4.0, 37],
	["Delhi remains", 28.61, 77.21, 6.0, 41],
	["Dhaka remains", 23.81, 90.41, 5.0, 43],
	["Beijing remains", 39.90, 116.40, 6.0, 47],
	["Tokyo remains", 35.68, 139.69, 6.0, 53],
	["Sydney remains", -33.87, 151.21, 4.0, 59],
	["New York remains", 40.73, -73.99, 5.0, 61],
	["Mexico City remains", 19.43, -99.13, 6.0, 67],
	["Los Angeles remains", 34.05, -118.24, 5.0, 71],
	["Sao Paulo remains", -23.55, -46.63, 6.0, 73],
	["Buenos Aires remains", -34.60, -58.38, 5.0, 79],
]

static func resolve(recipe: Dictionary) -> Array:
	var config: Dictionary = recipe.get("surface", {})
	var authored: Array = config.get("settlements", [])
	if not config.has("settlements") and config.get("settlement_preset", "") == "earth_graveyard":
		for row in EARTH_DISTRICTS:
			authored.append({"name": row[0], "lat_deg": row[1], "lon_deg": row[2], "radius_km": row[3], "seed": row[4]})
	var result := []
	for item in authored:
		var dir := DevSites.dir_for(float(item.get("lat_deg", 0)), float(item.get("lon_deg", 0)))
		var frame := DevSites.surface_frame(dir)
		result.append({"name": str(item.get("name", "Abandoned district")), "dir": dir,
			"basis": Basis(frame.east, dir, frame.north),
			"radius": clampf(float(item.get("radius_km", 3)), 0.3, 12.0),
			"density": clampf(float(item.get("density", 0.78)), 0.0, 1.0),
			"seed": int(item.get("seed", 1)),
			"materials": item.get("materials", recipe.get("materials", {}).get("salvage", [])).duplicate()})
	return result

static func occupied(regions: Array, dir: Vector3, radius: float) -> bool:
	for region in regions:
		if dir.distance_squared_to(region.dir) * radius * radius < pow(float(region.radius), 2):
			return true
	return false

# Boxes are in km, with bottom below the plot to embed foundations. Missing
# floors/walls are real gaps, not transparent textures on solid cube colliders.
static func parts(variant: int) -> Array[AABB]:
	match variant:
		0: # broken office stack, setback upper floors
			return [AABB(Vector3(-.025, -.014, -.022), Vector3(.05, .084, .044)),
				AABB(Vector3(-.025, .07, -.022), Vector3(.032, .032, .044)),
				AABB(Vector3(-.025, .102, -.022), Vector3(.008, .018, .025)),
				AABB(Vector3(.008, -.004, .024), Vector3(.023, .009, .012))]
		1: # roofless industrial hall with surviving roof and columns
			return [AABB(Vector3(-.037, -.014, -.029), Vector3(.074, .017, .058)),
				AABB(Vector3(-.037, .003, -.029), Vector3(.006, .025, .058)),
				AABB(Vector3(-.037, .003, -.029), Vector3(.074, .020, .006)),
				AABB(Vector3(.031, .003, -.029), Vector3(.006, .028, .012)),
				AABB(Vector3(.031, .003, .019), Vector3(.006, .023, .01)),
				AABB(Vector3(-.037, .025, -.029), Vector3(.038, .003, .058))]
		_: # collapsed housing, surviving wall segments and rubble
			return [AABB(Vector3(-.028, -.014, -.025), Vector3(.056, .018, .05)),
				AABB(Vector3(-.028, .004, -.025), Vector3(.005, .02, .05)),
				AABB(Vector3(-.028, .004, -.025), Vector3(.034, .016, .005)),
				AABB(Vector3(-.01, .004, -.006), Vector3(.025, .006, .023)),
				AABB(Vector3(.008, .004, .011), Vector3(.027, .009, .014))]

static func cell(sampler, region: Dictionary, x: int, z: int, radius: float) -> Dictionary:
	var p := Vector2(x + 0.5, z + 0.5) * STEP
	if p.length() > float(region.radius):
		return {}
	var seed_value := float(region.seed)
	var h := SurfaceForest.cell_hash(x, z, 0, seed_value)
	if h > float(region.density) or posmod(x, 9) == 0 or posmod(z, 11) == 0:
		return {} # wider avenues and empty plots
	var rb: Basis = region.basis
	var dir: Vector3 = (region.dir * radius + rb.x * p.x + rb.z * p.y).normalized()
	if sampler.is_water(dir) or sampler.ice01(dir) > 0.5:
		return {}
	var gr: float = sampler.ground_radius_km(dir, radius)
	var east := rb.x.slide(dir).normalized()
	var basis := Basis(east, dir, east.cross(dir))
	var h2 := SurfaceForest.cell_hash(x, z, 1, seed_value)
	basis = basis.rotated(dir, float(int(h2 * 4)) * PI * .5)
	# Reject steep plots; foundation embeds all corners without floating walls.
	var low := gr
	var high := gr
	for dx in [-.055, .055]:
		for dz in [-.055, .055]:
			var corner: Vector3 = (dir * gr + basis.x * dx + basis.z * dz).normalized()
			if sampler.is_water(corner):
				return {}
			var height: float = sampler.ground_radius_km(corner, radius)
			low = minf(low, height)
			high = maxf(high, height)
	if high - low > .007:
		return {}
	var variant := 0 if h2 > .68 else (1 if h2 > .37 else 2)
	var scale := Vector3(0.85 + h2 * .3, .65 + h * 1.25, .85 + h2 * .3)
	return {"transform": Transform3D(basis.scaled_local(scale), dir * high), "variant": variant,
		"id": "%s:%d:%d" % [region.name, x, z], "materials": region.materials}

# Returns segment entry and outward normal; also separates an already embedded
# hull along its nearest face. Callers expand boxes by clearance and hull extents.
static func box_contact(from: Vector3, to: Vector3, box: AABB) -> Dictionary:
	var d := to - from
	var t0 := 0.0
	var t1 := 1.0
	var normal := Vector3.ZERO
	if box.has_point(from):
		var nearest := INF
		for axis in 3:
			for side in [-1.0, 1.0]:
				var gap := from[axis] - box.position[axis] if side < 0 else box.end[axis] - from[axis]
				if gap < nearest:
					nearest = gap
					normal = Vector3.ZERO
					normal[axis] = side
		return {"t": 0.0, "normal": normal, "push": nearest + .001}
	for axis in 3:
		if absf(d[axis]) < 1e-9:
			if from[axis] < box.position[axis] or from[axis] > box.end[axis]:
				return {}
			continue
		var a := (box.position[axis] - from[axis]) / d[axis]
		var b := (box.end[axis] - from[axis]) / d[axis]
		var entry := minf(a, b)
		if entry > t0:
			t0 = entry
			normal = Vector3.ZERO
			normal[axis] = -signf(d[axis])
		t1 = minf(t1, maxf(a, b))
		if t0 > t1:
			return {}
	if normal == Vector3.ZERO:
		return {}
	return {"t": t0, "normal": normal, "push": .001}

static func collide(sampler, from: Vector3, to: Vector3, velocity: Vector3,
		radius: float, clearance: float, cache: Dictionary, hull_basis: Basis = Basis.IDENTITY, hull_half: Vector3 = Vector3.ZERO) -> Dictionary:
	var best := {"hit": false, "position": to, "velocity": velocity, "normal": Vector3.ZERO, "budget_limited": false}
	if sampler.settlements.is_empty():
		return best
	# Cheap globe-envelope rejection; still test segments that cross the surface.
	var broad_clearance := clearance + hull_half.length()
	var segment := to - from
	var near_t := clampf(-from.dot(segment) / maxf(segment.length_squared(), 1e-12), 0.0, 1.0)
	if from.lerp(to, near_t).length() > radius + sampler.max_height_km() + MAX_HEIGHT + broad_clearance:
		return best
	if cache.size() > 4096:
		cache.clear()
	var best_t := 2.0
	for index in sampler.settlements.size():
		var region: Dictionary = sampler.settlements[index]
		var rb: Basis = region.basis
		var center: Vector3 = region.dir * radius
		var a := rb.transposed() * (from - center)
		var b := rb.transposed() * (to - center)
		var reach := float(region.radius) + broad_clearance + STEP
		var region_box := AABB(Vector3(-reach, -1.0, -reach), Vector3(reach * 2, sampler.max_height_km() + 2.0, reach * 2))
		if box_contact(a, b, region_box).is_empty():
			continue
		# Terrain already limits huge surface steps; keep pathological teleports
		# bounded too, stopping at the last checked point instead of tunnelling.
		var lo := Vector2(minf(a.x, b.x), minf(a.z, b.z)) - Vector2.ONE * (broad_clearance + STEP)
		var hi := Vector2(maxf(a.x, b.x), maxf(a.z, b.z)) + Vector2.ONE * (broad_clearance + STEP)
		var limit := int(ceil(reach / STEP))
		var x0 := clampi(int(floor(lo.x / STEP)), -limit, limit)
		var x1 := clampi(int(floor(hi.x / STEP)), -limit, limit)
		var z0 := clampi(int(floor(lo.y / STEP)), -limit, limit)
		var z1 := clampi(int(floor(hi.y / STEP)), -limit, limit)
		if (x1-x0+1) * (z1-z0+1) > 1024:
			best.position = from
			best.velocity = Vector3.ZERO
			best.budget_limited = true
			return best
		for z in range(z0, z1+1):
			for x in range(x0, x1+1):
				var key := Vector3i(x, z, index)
				if not cache.has(key):
					cache[key] = cell(sampler, region, x, z, radius)
				var item: Dictionary = cache[key]
				if item.is_empty():
					continue
				var xf: Transform3D = item.transform
				var inv := xf.affine_inverse()
				var local_from := inv * from
				var local_to := inv * to
				var scales := xf.basis.get_scale()
				var relative_basis := inv.basis * hull_basis
				var padding := Vector3.ONE * clearance / scales + relative_basis.x.abs() * hull_half.x + relative_basis.y.abs() * hull_half.y + relative_basis.z.abs() * hull_half.z
				for part in parts(item.variant):
					var expanded := AABB(part.position - padding, part.size + padding * 2.0)
					var contact := box_contact(local_from, local_to, expanded)
					if contact.is_empty() or float(contact.t) >= best_t:
						continue
					best_t = contact.t
					var normal: Vector3 = (xf.basis.orthonormalized() * contact.normal).normalized()
					best.hit = true
					best.normal = normal
					best.position = xf * (local_from.lerp(local_to, best_t) + contact.normal * float(contact.push))
					var inward := velocity.dot(normal)
					if inward < 0.0:
						var bounce := minf(-inward * .08, .005) if -inward > .003 else 0.0
						best.velocity = (velocity - normal * inward).limit_length(.02) + normal * bounce
	return best
