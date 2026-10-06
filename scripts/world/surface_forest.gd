class_name SurfaceForest
extends RefCounted
## Deterministic cube-face cells, independent of terrain tessellation.
## Produces data on a terrain worker; never allocates rendering resources.
const Biome := preload("res://scripts/world/surface_biome.gd")

static func scatter(sampler: TerrainSampler, hit: Vector3, radius: float, budget: int, canopy: bool = false, cache: Dictionary = {}, face: int = -1, stream_stride: int = 1) -> Dictionary:
	var transforms: Array = []
	var variants := PackedByteArray()
	var profile := sampler.surface
	if budget <= 0 or float(profile.vegetation_density) <= 0.0:
		return {"xforms": transforms, "variants": variants}
	var up := hit.normalized()
	var axis := up.abs().max_axis_index() if face < 0 else face
	if face < 0:
		var margin := float(profile.tree_spacing_m) / 1000.0 * stream_stride * (180.0 if canopy else 45.0) / radius * 3.0
		var faces: Array[int] = []
		for candidate in 3:
			if absf(up[candidate]) >= up.abs()[axis] - margin:
				faces.append(candidate)
		if faces.size() > 1:
			for candidate in faces:
				var part := scatter(sampler, hit, radius, budget, canopy, cache, candidate, stream_stride)
				transforms.append_array(part.xforms)
				variants.append_array(part.variants)
			if transforms.size() > budget:
				transforms.resize(budget)
				variants.resize(budget)
			return {"xforms": transforms, "variants": variants}
	var a := (axis + 1) % 3
	var b := (axis + 2) % 3
	var sign_axis := signf(up[axis])
	var step := float(profile.tree_spacing_m) / 1000.0
	var stride := stream_stride * (4 if canopy else 1)
	# Cube projection stretches near face corners. Compensate spacing while
	# preserving a fixed grid per face, never a grid centred on the camera.
	var center := Vector2(up[a], up[b]) / absf(up[axis]) * radius
	var cx := int(floor(center.x / (step * stride))) * stride
	var cy := int(floor(center.y / (step * stride))) * stride
	var reach := mini(44, int(sqrt(float(budget)) * 0.5))
	var extent := step * float(reach) * stride
	for y in range(cy - reach * stride, cy + reach * stride, stride):
		for x in range(cx - reach * stride, cx + reach * stride, stride):
			var h := cell_hash(x, y, axis, float(profile.seed))
			var h2 := cell_hash(x, y, axis, float(profile.seed) + 71.0)
			var uv := Vector2(float(x) + 0.15 + h * 0.7, float(y) + 0.15 + h2 * 0.7) * step
			var distance := uv.distance_to(center)
			if canopy and distance <= step * float(reach) * stream_stride:
				continue
			if distance > extent:
				continue
			var key := Vector3i(x, y, axis + (3 if sign_axis < 0.0 else 0))
			if cache.has(key):
				var cached: Variant = cache[key]
				if cached != null:
					transforms.append(cached[0])
					variants.append(cached[1])
				continue
			cache[key] = null
			var cube := Vector3.ZERO
			cube[axis] = sign_axis * radius
			cube[a] = uv.x
			cube[b] = uv.y
			var dir := cube.normalized()
			# Never duplicate cells belonging to an adjacent cube face.
			if dir.abs().max_axis_index() != axis:
				continue
			if SurfaceSettlement.vegetation_occupied(sampler, dir, radius) or SurfaceFacility.occupied(sampler.facilities, dir, radius):
				continue
			if sampler.is_water(dir) or sampler.ice01(dir) > 0.5:
				continue
			var height := sampler.height_m(dir) / 1000.0
			var density := Biome.vegetation(profile, dir, height, sampler.albedo_color(dir))
			if height * 1000.0 < float(profile.tree_line_m):
				density = maxf(density, .72 * SurfaceSettlement.reclamation_at(sampler.settlements, dir, radius))
			var grove := grove_weight(uv / .65, axis, float(profile.seed))
			density *= lerpf(1.0, smoothstep(.22, .68, grove), float(profile.get("grove_clearings", 0.0)))
			if h > density:
				continue
			var pos := dir * (radius + height)
			var normal := sampler.normal_at(pos, radius)
			if normal.dot(dir) < 0.78:
				continue
			var east := dir.cross(Vector3.UP)
			if east.length_squared() < 0.001:
				east = dir.cross(Vector3.RIGHT)
			east = east.normalized()
			var basis := Basis(east, dir, east.cross(dir)).rotated(dir, h2 * TAU)
			var scale := (0.72 + h2 * 0.56) * float(profile.tree_height_m) / 30.0
			var age := cell_hash(x, y, axis, float(profile.seed) + 179.0)
			if age < float(profile.get("giant_tree_fraction", 0.0)):
				scale *= 3.1
			transforms.append(Transform3D(basis.scaled_local(Vector3.ONE * scale), pos - dir * .002))
			# Broad crowns in warm latitudes, conifers toward the poles.
			var conifer := smoothstep(0.65, 0.94, absf(dir.y))
			variants.append(0 if h2 < conifer else 1)
			cache[key] = [transforms[-1], variants[-1]]
	return {"xforms": transforms, "variants": variants}

static func grove_weight(uv: Vector2, face: int, seed: float) -> float:
	var x := int(floor(uv.x))
	var y := int(floor(uv.y))
	var u := smoothstep(0.0, 1.0, uv.x - x)
	var v := smoothstep(0.0, 1.0, uv.y - y)
	return lerpf(lerpf(cell_hash(x, y, face, seed + 211), cell_hash(x + 1, y, face, seed + 211), u),
		lerpf(cell_hash(x, y + 1, face, seed + 211), cell_hash(x + 1, y + 1, face, seed + 211), u), v)

static func streaming_stride(speed: float, latency: float, spacing_m: float, budget: int) -> int:
	var reach := spacing_m / 1000.0 * minf(44, sqrt(float(maxi(budget, 1))) * .5)
	var required := maxf(1.0, speed * (latency + .35) * 2.0 / maxf(reach, .1))
	return clampi(int(pow(2, ceil(log(required) / log(2.0)))), 1, 8)

static func cell_hash(x: int, y: int, face: int, seed: float) -> float:
	# Integer mixing avoids float32 world-position hashing jitter.
	var value := (x * 73856093) ^ (y * 19349663) ^ (face * 83492791) ^ int(seed * 1009.0)
	value = ((value ^ (value >> 13)) * 1274126177) & 0x7fffffff
	return float(value) / 2147483647.0
