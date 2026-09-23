class_name SurfaceBiome
extends RefCounted
## Shared climate rules. Recipe values are art/gameplay controls, not a climate simulation.

static func snow_line_m(profile: Dictionary, dir: Vector3) -> float:
	var equator := float(profile.get("snow_line_m", 0.0))
	if equator <= 0.0:
		return INF
	return maxf(0.0, equator - float(profile.get("snow_polar_drop_m", 0.0)) * pow(absf(dir.y), 2.0))

static func vegetation(profile: Dictionary, dir: Vector3, height_km: float, color: Color) -> float:
	var density := float(profile.get("vegetation_density", 0.0))
	if density <= 0.0 or height_km < 0.0 or float(profile.get("ice_surface", 0.0)) >= 0.5:
		return 0.0
	var tree_line := minf(float(profile.get("tree_line_m", 3500.0)), snow_line_m(profile, dir) - 500.0)
	var altitude := 1.0 - smoothstep(maxf(0.0, tree_line - 500.0), maxf(1.0, tree_line), height_km * 1000.0)
	var latitude := 1.0 - smoothstep(0.85, 0.96, absf(dir.y))
	# Optional map biome mask: green land qualifies; desert, rock and ice do not.
	var mask := 1.0
	if bool(profile.get("vegetation_from_albedo", false)):
		mask = smoothstep(0.0, 0.045, color.g - maxf(color.r, color.b) * 1.05)
	return density * mask * altitude * latitude

static func forest_budget(agl_km: float) -> int:
	# Individual 20–40 m crowns cease to be useful from high altitude.
	return 4096 if agl_km < 2.0 else (1536 if agl_km < 4.0 else 0)
