extends Node
# Render the ground tile offscreen so its artifacts can actually be LOOKED at.
# Run: xvfb-run -a godot --path . res://tools/render_terrain.tscn (needs a real GL
# context — plain --headless never delivers a frame, so save_png never runs).
#
# Reported three times: "cubes / boxes on Earth". Guessing from a description was
# not working, so this builds the real rings with the real materials and saves a
# PNG per viewpoint.

const G := preload("res://scripts/world/planet_generator.gd")
const SP := preload("res://scripts/world/surface_patch.gd")
const CL := preload("res://scripts/world/cloud_layer.gd")
const DS := preload("res://scripts/world/dev_sites.gd")

const OUT := "user://terrain_%s.png"
const EARTH_R := 6371.0

# CLOUD_QUALITY env (capture-only instrumentation, PlanetSystem's brief for
# the cloud-quality fix): mirrors PlanetSystem.CLOUD_QUALITY_MULT — this scene
# runs under a real scene tree (not `--script`), so the GameState autoload IS
# registered here, unlike the SceneTree-based test_*.gd files.
const CLOUD_QUALITY_MULT := [0.0, 0.5, 1.0]

var _cam: Camera3D
var _shots := []
var _i := 0
var _wait := 0


func _ready() -> void:
	var cq_env := OS.get_environment("CLOUD_QUALITY")
	if not cq_env.is_empty():
		GameState.cloud_quality = clampi(int(cq_env), 0, CLOUD_QUALITY_MULT.size() - 1)
	get_viewport().transparent_bg = false
	_cam = Camera3D.new()
	_cam.far = 900000.0
	_cam.near = 0.05
	_cam.fov = 70.0
	add_child(_cam)
	var sun := DirectionalLight3D.new()
	add_child(sun)
	# lat, lon, altitude km, pitch down degrees, label
	# lat, lon, altitude km, LOOK-AHEAD km, label
	_shots = [
		[10.0, 20.0, 0.08, 0.25, "moon_rocks", "Moon"],
		[10.0, 20.0, 10.0, 0.0, "moon_crater", "Moon", "crater"],
		[10.0, 20.0, 6.0, 0.0, "io_volcano", "Io", "volcano"],
		[10.0, 20.0, 3.0, 0.0, "mars_volcano", "Mars", "volcano"],
		[10.0, 20.0, 0.3, 1.5, "europa_ice", "Europa"],
		[27.95, 86.80, 1.2, 5.0, "earth_mountains", "Earth"],
		[20.5, -17.0, 0.4, 2.0, "earth_water", "Earth"],
		[10.0, 20.0, 500000.0, 0.0, "sun_plasma", "Sun"],
		[10.0, 20.0, 80000.0, 0.0, "jupiter_storms", "Jupiter"],
		[20.5, -17.0, 20.0, 60.0, "earth_20km"],
		[20.5, -17.0, 7.0, 25.0, "earth_7km"],
		[10.0, 20.0, 20.0, 40.0, "moon_20km", "Moon"],
		[10.0, 20.0, 7.0, 15.0, "moon_7km", "Moon"],
		[10.0, 20.0, 0.2, 0.6, "moon_200m", "Moon"],
		[10.0, 20.0, 0.2, 0.6, "moon_200m_lowsun", "Moon", {"sun_elev_deg": 15.0}],
		# Ring-defect review (2026-09-09): small craters judged from nearly
		# straight down, where a grazing low-altitude view foreshortens a
		# 45-90 m bowl to almost nothing regardless of how well-formed it is.
		[10.0, 20.0, 1.0, 1.0, "moon_1km_nadir_lowsun", "Moon", {"pitch_deg": -80.0, "sun_elev_deg": 15.0}],
		# Horizon-shadow review (2026-09-09): a real ~240 m-diameter, ~63 m-deep
		# crater bowl found by scanning TerrainSampler.height_m() directly (the
		# "crater" landmark flag other rows use is empty on Moon now that a real
		# DEM suppresses SurfaceRecipe's named/seeded crater list - see
		# PLANET_GENERATOR.md). Camera sits 250 m south of the bowl centre at
		# 300 m altitude looking north into it, sun low (12 deg) and to the east
		# (roughly camera-left looking north) so the near/anti-sun wall should
		# cast a real shadow across the floor.
		[-5.43838, 74.57700, 0.3, 0.25, "moon_crater_300m_lowsun", "Moon", {"sun_elev_deg": 12.0}],
		# The conditions in the reported screenshots: over water and over a coast.
		[20.5, -17.0, 12.0, 60.0, "coast_12km"],
		[20.5, -17.0, 6.0, 40.0, "coast_6km"],
		[20.5, -17.0, 2.0, 14.0, "coast_2km"],
		# Above the Himalaya rather than inside it - the ground there is 7626 m.
		[27.95, 86.80, 12.0, 40.0, "himalaya_12km"],
		[27.95, 86.80, 9.0, 18.0, "himalaya_9km"],
		# 2026-09-09 8k rg16 re-wiring review: Everest's own argmax texel
		# (27.99N, 86.93E, assets/planets/SOURCES.txt/tools/test_dem_calibration.gd),
		# 3 km above whatever height_m() samples there (not a fixed absolute
		# altitude - the summit itself decodes to ~7.2 km on this map, not the
		# real ~8.85 km, expected: 4.89 km/px area-averages the peak down).
		[27.99, 86.93, 3.0, 9.0, "everest_3km"],
		# Mariana Trench (11.35N, 142.2E) - real bathymetry is carried
		# (base_height_m() ~ -10 km here) but height_m() clamps it to the
		# liquid datum, so this must look like flat open sea, not a canyon.
		[11.35, 142.2, 2.0, 6.0, "mariana_2km"],
		# Ring-defect review (2026-09-08): poles, ring-boundary stitch lines, band ceiling.
		[89.0, 0.0, 2.0, 10.0, "arctic_2km"],
		[-89.0, 0.0, 5.0, 20.0, "antarctic_5km"],
		[90.0, 0.0, 2.0, 10.0, "north_pole_exact_2km"],
		[20.5, -17.0, 1.0, 2.56, "ring_boundary_r0r1"],
		[20.5, -17.0, 5.0, 20.48, "seam_horizon_r1r2"],
		[20.5, -17.0, 34.0, 100.0, "earth_34km"],
		# Ice-is-not-water regression: Ross Ice Shelf reads mask=water, albedo=bright.
		[-79.0, -175.0, 2.0, 14.0, "antarctica_2km"],
		[75.0, -20.0, 2.0, 14.0, "greenland_coast_2km"],
		# Cloud-deck review (dense real cover, 35.9N 75.3W): free-space pitch/yaw
		# aim instead of a ground target, so the deck itself fills the frame.
		[35.9, -75.3, 2.0, 14.0, "clouds_below_2km", "Earth", {"pitch_deg": 25.0}],
		[35.9, -75.3, 9.0, 20.0, "clouds_through_9km", "Earth", {"pitch_deg": 0.0}],
		[35.9, -75.3, 20.0, 80.0, "clouds_above_20km", "Earth", {"pitch_deg": -12.0}],
		[35.9, -75.3, 34.0, 120.0, "clouds_handoff_34km", "Earth", {"pitch_deg": -15.0}],
		[35.9, -75.3, 20.0, 60.0, "clouds_nadir_gapcheck", "Earth"],
		[35.9, -75.3, 20.0, 60.0, "clouds_drift_t0", "Earth", {"sim_time_s": 0.0}],
		[35.9, -75.3, 20.0, 60.0, "clouds_drift_t120", "Earth", {"sim_time_s": 120.0}],
		# Scanned (dbg_scan_grid one-off, 2026-09-09): 50N 130E window averages
		# coverage_from_raw=0.491 (std=0.471, highest variance of any 0.3-0.5-mean
		# window found) — scattered mid coverage, not a single front. Window
		# average alone can still land the camera on a clear texel (confirmed:
		# the window-centre shots showed no cloud at all), so dbg_find_point
		# picked the actual edge inside it: 50.27N 132.36E, raw=0.404, a 6 px
		# (~20 km) neighbourhood spanning raw 0 to 0.73 — a real scattered edge.
		[50.27, 132.36, 20.0, 40.0, "clouds_nadir_scatter_20km_r4", "Earth", {"pitch_deg": -12.0}],
		[50.27, 132.36, 2.0, 14.0, "clouds_under_scatter_2km_r4", "Earth", {"pitch_deg": 25.0}],
		# Sub-texel detail review (2026-09-09): a steeper-than-usual down look
		# at the same dense site the r3/r4 shots used, to judge puff/cell
		# structure from above. 12 km (the deck's own alt+half-thickness is
		# 10.5 km) leaves almost no clearance — pitching down at all just
		# looks past the deck's own thin grazing-horizon band onto bare ocean
		# beyond it (confirmed empirically, re-shot twice); 16 km gives enough
		# margin for a -25 deg pitch to still catch the deck in frame. Also a
		# cell-bottom shading check from underneath (2 km, pitch +30, same
		# convention as clouds_below_2km).
		[35.9, -75.3, 16.0, 40.0, "clouds_nadir_dense_16km", "Earth", {"pitch_deg": -25.0}],
		[35.9, -75.3, 2.0, 14.0, "clouds_under_dense_2km", "Earth", {"pitch_deg": 30.0}],
		# Globe-vs-ring colour parity probe (2026-09-09): nadir (look_km 0), same
		# lat/lon pair at 45 km (ring gated off, BAND_CEILING_MIN_KM=35) and 25 km
		# (ring on), same sun direction per site since `dir` only depends on
		# lat/lon. Three sites: open ocean, green land, desert.
		[0.0, -30.0, 45.0, 0.0, "parity_atlantic_45km", "Earth"],
		[0.0, -30.0, 25.0, 0.0, "parity_atlantic_25km", "Earth"],
		[-3.0, -60.0, 45.0, 0.0, "parity_amazon_45km", "Earth"],
		[-3.0, -60.0, 25.0, 0.0, "parity_amazon_25km", "Earth"],
		[23.0, 10.0, 45.0, 0.0, "parity_sahara_45km", "Earth"],
		[23.0, 10.0, 25.0, 0.0, "parity_sahara_25km", "Earth"],
		# DEM ingest review (2026-09-09, docs/research/2026-09-09-dem-ingest.md):
		# Olympus Mons (18.65N, 226.2E, same convention as SOURCES.txt/the raw
		# PDS files, verified against tools/test_dem_calibration.gd) should read
		# as a broad shield with a raised rim, not a spike or a flat plain. Yaw
		# west off the due-north baseline aim toward the rest of the Tharsis rise.
		# 38 km, not the round "50 km" the name implies: Mars's real DEM relief
		# (24.22 km max_height_km, tools/test_dem_calibration.gd) pushes its band
		# ceiling to ~41.2 km (BAND_CEILING_MULT * max_height_km); above that the
		# local terrain patch is not shown at all (should_show()) and this shot
		# would just be the bare procedural globe. Kept the shot's original name.
		[18.65, 226.2, 38.0, 120.0, "mars_olympus_50km", "Mars", {"yaw_deg": -40.0}],
		[18.65, 226.2, 5.0, 15.0, "mars_olympus_5km", "Mars"],
		# Hellas Planitia floor (42.4S, 70.5E) - a real basin now, not the old
		# procedural crater-octave field. "Rim" framing from altitude/look-ahead
		# alone; the DEM has no separately-tagged rim coordinate.
		[-42.4, 70.5, 10.0, 40.0, "mars_hellas_rim_10km", "Mars"],
		# Tycho (43.3S, 11.4W == 348.6E) is sub-texel at 4 ppd (SOURCES.txt: ~11 px
		# wide at native res before the 2048x1024 resample) - expect at most the
		# DEM-scale basin/highland shape, not the crater itself.
		[-43.3, -11.4, 20.0, 60.0, "moon_tycho_20km", "Moon"],
	]
	var selected := OS.get_environment("TERRAIN_SHOTS")
	if not selected.is_empty():
		_shots = _shots.filter(func(shot: Array) -> bool: return str(shot[4]) in selected.split(","))


func _process(_dt: float) -> void:
	if _i >= _shots.size():
		get_tree().quit(0)
		return
	if _wait == 0:
		_setup(_shots[_i])
	_wait += 1
	if _wait > 6:
		var img := get_viewport().get_texture().get_image()
		var path: String = OUT % str(_shots[_i][4])
		img.save_png(path)
		print("render_terrain: %s -> %s" % [str(_shots[_i][4]), ProjectSettings.globalize_path(path)])
		_i += 1
		_wait = 0


func _setup(shot: Array) -> void:
	for c in get_children():
		if c is Node3D and c != _cam and not (c is DirectionalLight3D):
			c.queue_free()
	var dir := DS.dir_for(float(shot[0]), float(shot[1]))
	var alt := float(shot[2])
	# Optional trailing Dictionary anywhere in the row: {"pitch_deg": .., "yaw_deg": ..}
	# for the cloud-deck review shots below, without disturbing the body/feature
	# positional slots the ring worker's rows already use.
	var opts: Dictionary = {}
	for item in shot:
		if item is Dictionary:
			opts = item
			break
	var body: String = "Earth"
	for item in shot.slice(5):
		if item is String:
			body = item
			break
	var radii := {"Moon": 1737.4, "Io": 1821.6, "Mars": 3389.5, "Europa": 1560.8, "Sun": 696340.0, "Jupiter": 69911.0}
	var radius: float = radii.get(body, EARTH_R)
	var earth := G.recipe_for({"name": body})
	var s: TerrainSampler = G.terrain_sampler(earth)
	var ceiling: float = G.band_ceiling_km(s)
	var landmark_dir := Vector3.ZERO
	if shot.size() > 6 and shot[6] is String:
		var tag := str(shot[6])
		var landmarks: Array = s.surface.craters if tag == "crater" else s.surface.volcanoes
		if landmarks.is_empty():
			print("render_terrain: %s -> no '%s' landmarks on %s (DEM-suppressed recipe list?), falling back to row's lat/lon" % [str(shot[4]), tag, body])
		else:
			var feature: Dictionary = landmarks[0]
			landmark_dir = feature.direction
			var axis := landmark_dir.cross(Vector3.UP).normalized()
			dir = landmark_dir.rotated(axis, float(feature.width) * 1.4)

	var patch = SP.new()
	add_child(patch)
	patch.bind_body(earth, s)
	var ship: Vector3 = dir * (s.ground_radius_km(dir, radius) + alt)
	patch.update_for(ship, body, true, radius, alt, 0.02, ceiling, earth, s)
	patch.force_ready()
	# Floating origin, exactly as PlanetSystem does it.
	patch.position = -ship
	# Default sun elevation (~28.7 deg, the fixed 0.48/0.88 mix) reads fine for
	# broad relief; a crater 45-90 m across near the ship (moon_200m) casts a
	# shadow this high sun makes too short to notice. `sun_elev_deg` (opts)
	# lets one shot ask for a grazing sun instead, without moving every other
	# shot's numbers.
	var east: Vector3 = dir.cross(Vector3.UP).normalized()
	var to_sun: Vector3 = (dir * 0.48 + east * 0.88).normalized()
	if opts.has("sun_elev_deg"):
		var elev := deg_to_rad(float(opts.sun_elev_deg))
		to_sun = (dir * sin(elev) + east * cos(elev)).normalized()
	patch.set_view(to_sun, alt, 100.0 if body == "Earth" else 0.0)

	# The body's own globe, so its facets show up here too if they are the culprit.
	var painted: Dictionary = G.paint({"name": body, "physical": true,
		"color": Color(0.169, 0.510, 0.788)}, radius)
	var globe: MeshInstance3D = painted.sphere
	globe.visible = not patch.visible
	globe.position = -ship
	# Real gameplay binds clouds/night/height/specular/normal the first frame
	# close_enough() (dist < 80000 km) goes true — true for every shot here — and
	# scales `detail` by altitude via close_detail(), not a flat 1.0. A probe that
	# skips both makes the globe measure a procedural full-cloud fallback (Earth's
	# cloud_amount is 1.0) instead of the real map, and forces close-up hill/water
	# shading at any distance — neither matches what the player actually sees.
	G.ensure_close_maps(painted.mat, earth, false)
	var atmo_top_km: float = 100.0 if body == "Earth" else 0.0
	G.apply_view(painted.mat, to_sun, G.close_detail(alt), alt, atmo_top_km)
	# Cloud-quality instrumentation (CLOUD_QUALITY env, set in _ready): mirrors
	# planet_system.gd's refresh — same scaled amount reaches the globe
	# (PlanetGenerator.set_cloud_amount) and the deck recipe below
	# (CL.update_for), so a Light/Full comparison capture actually differs.
	var quality_idx: int = clampi(GameState.cloud_quality, 0, CLOUD_QUALITY_MULT.size() - 1)
	var cloud_mult: float = CLOUD_QUALITY_MULT[quality_idx]
	var deck_earth: Dictionary = earth.duplicate()
	deck_earth["cloud_amount"] = float(earth.get("cloud_amount", 0.0)) * cloud_mult
	G.set_cloud_amount(painted.mat, float(deck_earth.cloud_amount))
	# Globe-vs-ring colour parity shots ("parity_*") isolate the GROUND colour
	# law this probe measures. Clouds are a separate, currently-broken axis
	# (reported: planet_cook.gdshader's cloud/albedo UV does not match the
	# equirect _dir_uv() the ring/CloudLayer use, out of scope here — another
	# worker owns it) that only the globe bakes into its own ALBEDO; the ring
	# never does. Left uncontrolled, real average cloud cover over these sites
	# would swing the globe's measured colour by however wrong that unrelated
	# bug currently is, contaminating THIS category's measurement.
	if str(shot[4]).begins_with("parity_"):
		painted.mat.set_shader_parameter("cloud_amount", 0.0)
	add_child(globe)
	# Include the same atmosphere shell as the live renderer, not black sky on Earth.
	if body == "Earth":
		var sky := MeshInstance3D.new()
		var shell := SphereMesh.new()
		shell.radius = 200000.0
		shell.height = 400000.0
		sky.mesh = shell
		var sky_mat := G.air_shell_material(earth, {"spectral": "G"})
		sky_mat.set_shader_parameter("opacity", G.air_shell_opacity(alt, 100.0, float(earth.get("air_amount", 0.0))))
		sky_mat.set_shader_parameter("sun_dir", to_sun)
		sky_mat.set_shader_parameter("up_dir", dir)
		sky.material_override = sky_mat
		add_child(sky)

	# Same gate as the live renderer: alive exactly while the ring (`patch`) is.
	# `sim_time_s` (opts) drives the deterministic drift/morph — clouds_drift_check
	# captures the same camera at two sim-time values to prove the deck moves.
	var sim_time_s := float(opts.get("sim_time_s", 0.0))
	var cloud := CL.new()
	add_child(cloud)
	cloud.update_for(-ship, body, true, radius, alt, 0.02, ceiling, deck_earth, to_sun, sim_time_s)
	if str(shot[4]).begins_with("parity_"):
		cloud.visible = false

	# Camera at the origin (floating origin). Aim at a DEFINITE point on the
	# ground a stated distance ahead, rather than composing a basis by hand - a
	# hand-rolled basis is one sign error away from rendering a view that does not
	# exist, and then the artifact being chased is the probe's.
	var up: Vector3 = dir
	var frame := DS.surface_frame(dir)
	var north: Vector3 = frame.north
	var look_km := float(shot[3])
	var target_dir: Vector3 = (dir * radius + north * look_km).normalized()
	if landmark_dir != Vector3.ZERO:
		target_dir = landmark_dir
	var target: Vector3 = target_dir * s.ground_radius_km(target_dir, radius) - ship
	var camera_up := north if absf(target.normalized().dot(up)) > 0.99 else up
	_cam.look_at_from_position(Vector3.ZERO, target, camera_up)
	# Cloud-deck review: pitch/yaw OFF the ground-aimed baseline above, rotating
	# the camera in place rather than re-deriving a free-space target point — a
	# hand-picked distance in empty air is one bad guess away from aiming at
	# nothing (proven: -30 deg/20 km from 34 km up never reached the shell or the
	# ground). Pivoting off a target we already know is real keeps the shot
	# grounded in the same geometry the un-pitched shots use.
	var pitch_deg := float(opts.get("pitch_deg", 0.0))
	var yaw_deg := float(opts.get("yaw_deg", 0.0))
	if pitch_deg != 0.0:
		_cam.rotate_object_local(Vector3.RIGHT, deg_to_rad(pitch_deg))
	if yaw_deg != 0.0:
		_cam.rotate_object_local(Vector3.UP, deg_to_rad(yaw_deg))
	print("render_terrain:   aiming %.0f km ahead, target %.1f km away, ground below %.0f m"
		% [look_km, target.length(), s.height_m(dir)])
