class_name BlackHoleRenderer
extends RefCounted
# Camera-facing bounds only; every fragment follows a Kerr null geodesic.
# Lensing, redshift and beaming are real time. The plasma display (flow,
# hotspots after GRAVITY 2018, A&A 618, L10, flares, turbulence) runs on one
# sensor clock, TIME_LAPSE x the simulation clock, so Kepler ratios stay real.
# TIME_LAPSE: the ISCO lap (~590 s) stays >= 8 s on screen (N <= 73), while
# the outer flow seen from ~1.2 AU moves tens of pixels within 2-3 s (N >= ~10).
const SHADER := preload("res://shaders/black_hole.gdshader")
const C_KM_S := 299792.458
const HOTSPOTS := 4
const TRACE_MARGIN_RG := 10.0
const TIME_LAPSE := 40.0
# Flow-map cycle: each texture phase advects for FLOW_CYCLE_S, then restarts
# under the other's crossfade, so differential rotation never winds it up.
const FLOW_CYCLE_S := 160.0
# Sgr A* NIR flares recur several times a day (Genzel et al. 2003, Nature 425, 934).
const FLARE_CYCLE_S := 21600.0
const FLARE_RISE_S := 180.0
const FLARE_DECAY_S := 900.0
const WAKE_COOLING_S := 150.0

static func paint(recipe: Dictionary) -> Dictionary:
	var mi := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(2.0, 2.0)
	mi.mesh = quad
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.extra_cull_margin = 1100000.0
	var material := ShaderMaterial.new()
	material.shader = SHADER
	material.render_priority = -100
	var stellar: Dictionary = recipe.stellar
	material.set_shader_parameter("seed", recipe.seed)
	material.set_shader_parameter("spin", stellar.spin)
	material.set_shader_parameter("rg_km", stellar.gravitational_radius_km)
	material.set_shader_parameter("horizon_rg", stellar.horizon_km / stellar.gravitational_radius_km)
	material.set_shader_parameter("disk_inner", stellar.disk_inner_radii)
	material.set_shader_parameter("disk_outer", stellar.disk_outer_radii)
	material.set_shader_parameter("trace_radius", trace_radius_rg(stellar))
	mi.material_override = material
	mi.set_meta("stellar_recipe", recipe)
	return {"sphere": mi, "mat": material, "recipe": recipe}

static func trace_radius_rg(stellar: Dictionary) -> float:
	return float(stellar.disk_outer_radii) + TRACE_MARGIN_RG

static func update(mi: MeshInstance3D, rel: Vector3, radius: float, time_s: float) -> void:
	var recipe: Dictionary = mi.get_meta("stellar_recipe")
	var stellar: Dictionary = recipe.stellar
	var rg: float = stellar.gravitational_radius_km
	var distance := rel.length()
	var outer_km := rg * trace_radius_rg(stellar)
	# Subpixel holes cost no fragments; they never acquire a fake stellar glare.
	mi.visible = distance > radius and outer_km / maxf(distance, 1.0) > .0003
	if not mi.visible: return
	var render_distance := minf(distance, 480000.0)
	var ratio := minf(outer_km/distance, .995)
	var bound := minf(ratio/sqrt(1.0-ratio*ratio), 3.0)*render_distance
	mi.position = rel * (render_distance / distance)
	var material := mi.material_override as ShaderMaterial
	var extent := Vector2.ONE*bound
	var offset := Vector2.ZERO
	var full_screen := outer_km/distance > .45
	var camera := mi.get_viewport().get_camera_3d()
	if camera != null and not full_screen:
		var center: Vector3 = camera.global_transform.affine_inverse()*mi.global_position
		var z := -center.z
		var r := outer_km/distance*render_distance
		if z < -r:
			mi.visible = false
			return
		if z <= r:
			full_screen = true
		else:
			# Exact projected sphere bounds include the off-axis centre shift.
			var denominator := z*z-r*r
			offset = Vector2(center.x,center.y)*r*r/denominator
			extent = Vector2(sqrt(center.x*center.x+denominator),sqrt(center.y*center.y+denominator))*r*z/denominator
	if not mi.has_meta("arrival_s"): mi.set_meta("arrival_s", time_s)
	var sensor_s := time_s * TIME_LAPSE
	var flare_now := flare_level(recipe, (time_s - float(mi.get_meta("arrival_s"))) * TIME_LAPSE)
	var flow := fposmod(sensor_s / FLOW_CYCLE_S, 1.0)
	var cycle := floorf(sensor_s / FLOW_CYCLE_S)
	material.set_shader_parameter("observer_rg", -rel / rg)
	material.set_shader_parameter("render_extent", extent)
	material.set_shader_parameter("render_offset", offset)
	material.set_shader_parameter("full_screen", full_screen)
	material.set_shader_parameter("sim_time", sensor_s)
	material.set_shader_parameter("flow_age", Vector2(flow, fposmod(flow + .5, 1.0)) * FLOW_CYCLE_S)
	material.set_shader_parameter("flow_cycle", Vector2(fposmod(cycle, 64.0), fposmod(floorf(sensor_s / FLOW_CYCLE_S + .5), 64.0)))
	material.set_shader_parameter("flow_cycle_s", FLOW_CYCLE_S)
	material.set_shader_parameter("flare", flare_now)
	material.set_shader_parameter("hotspots", hotspots(recipe, sensor_s, flare_now))

# Kerr prograde circular-orbit angular velocity (Bardeen et al. 1972), r in r_g.
static func orbital_rate_rad_s(stellar: Dictionary, r: float) -> float:
	return C_KM_S / float(stellar.gravitational_radius_km) / (pow(r, 1.5) + float(stellar.spin))

static func light_crossing_s(stellar: Dictionary) -> float:
	return float(stellar.gravitational_radius_km) / C_KM_S

static func _hash(x: float) -> float:
	return fposmod(sin(x) * 43758.5453, 1.0)

static func _wobble(salt: float, t: float) -> float:
	var i := floorf(t)
	var f := t - i
	f = f*f*(3.0 - 2.0*f)
	return lerpf(_hash(i*12.9898 + salt), _hash((i + 1.0)*12.9898 + salt), f)

# Each hotspot is a compact plasmoid, as in GRAVITY's orbiting-hotspot fits:
# born near the ISCO, it orbits at its own Kerr rate for one cycle, so inner
# spots lap outer ones. Behind it trails a synchrotron-cooling wake, WAKE_COOLING_S
# being the NIR cooling time for B ~ 100 G.
static func hotspots(recipe: Dictionary, sensor_s: float, flare_now: float) -> Array[Vector4]:
	var stellar: Dictionary = recipe.stellar
	var isco: float = stellar.disk_inner_radii
	var t_g := light_crossing_s(stellar)
	var seed: float = recipe.seed
	var spots: Array[Vector4] = []
	for k in HOTSPOTS:
		var cycle := 900.0 + 300.0*k
		var clock := sensor_s + cycle*(_hash(seed + 3.1*k) + .25*k)
		var n := floorf(clock / cycle)
		var age := clock - n*cycle
		var salt := seed + 7.3*k + 19.1*n
		var r := isco * (1.2 + .9*_hash(salt))
		var omega := orbital_rate_rad_s(stellar, r)
		var azimuth := fposmod(TAU*_hash(salt + 1.7) + omega*age, TAU)
		var wake := omega * minf(age, WAKE_COOLING_S)
		var life := smoothstep(0.0, 60.0, age) * (1.0 - smoothstep(cycle*.7, cycle, age))
		var flicker := .75 + .5*_wobble(salt + 5.0, sensor_s / (6.0*t_g))
		spots.append(Vector4(r, azimuth, wake, (14.0 + 8.0*_hash(salt + 2.9)) * life * flicker * (1.0 + 3.0*flare_now)))
	return spots

# Flares rise in minutes and decay over tens of minutes (sensor seconds). The
# first is scheduled shortly after arrival so a visit always shows one.
static func flare_level(recipe: Dictionary, since_arrival_s: float) -> float:
	var t_g := light_crossing_s(recipe.stellar)
	var seed: float = recipe.seed
	var level := 0.0
	var n := floorf(since_arrival_s / FLARE_CYCLE_S)
	for episode in [n - 2.0, n - 1.0, n]:
		if episode < 0.0: continue
		var onset: float = episode*FLARE_CYCLE_S + (3000.0 + 2400.0*_hash(seed + 41.0) if episode == 0.0 else 7200.0*_hash(seed + 13.7*episode))
		var age := since_arrival_s - onset
		if age <= 0.0: continue
		var envelope := smoothstep(0.0, FLARE_RISE_S, age) * exp(-maxf(age - FLARE_RISE_S, 0.0) / FLARE_DECAY_S)
		level += envelope * (.7 + .6*_hash(seed + 5.3*episode))
	var variability := .55 + .6*_wobble(seed + 77.0, since_arrival_s / (3.0*t_g)) + .3*_wobble(seed + 91.0, since_arrival_s / (12.0*t_g))
	return level * variability
