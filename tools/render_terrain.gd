extends Node
# Render the ground tile offscreen so its artifacts can actually be LOOKED at.
# Run: godot --headless --path . res://tools/render_terrain.tscn
#
# Reported three times: "cubes / boxes on Earth". Guessing from a description was
# not working, so this builds the real rings with the real materials and saves a
# PNG per viewpoint.

const G := preload("res://scripts/world/planet_generator.gd")
const SP := preload("res://scripts/world/surface_patch.gd")

const OUT := "user://terrain_%s.png"
const EARTH_R := 6371.0

var _cam: Camera3D
var _shots := []
var _i := 0
var _wait := 0


func _ready() -> void:
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
		# The conditions in the reported screenshots: over water and over a coast.
		[20.5, -17.0, 12.0, 60.0, "coast_12km"],
		[20.5, -17.0, 6.0, 40.0, "coast_6km"],
		[20.5, -17.0, 2.0, 14.0, "coast_2km"],
		# Above the Himalaya rather than inside it - the ground there is 7626 m.
		[27.95, 86.80, 12.0, 40.0, "himalaya_12km"],
		[27.95, 86.80, 9.0, 18.0, "himalaya_9km"],
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
	var lat := deg_to_rad(float(shot[0]))
	var lon := deg_to_rad(float(shot[1]))
	var dir := Vector3(cos(lat) * cos(lon), sin(lat), cos(lat) * sin(lon)).normalized()
	var alt := float(shot[2])
	var body: String = str(shot[5]) if shot.size() > 5 else "Earth"
	var radii := {"Moon": 1737.4, "Io": 1821.6, "Mars": 3389.5, "Europa": 1560.8, "Sun": 696340.0, "Jupiter": 69911.0}
	var radius: float = radii.get(body, EARTH_R)
	var earth := G.recipe_for({"name": body})
	var s: TerrainSampler = G.terrain_sampler(earth)
	var ceiling: float = G.band_ceiling_km(s)
	var landmark_dir := Vector3.ZERO
	if shot.size() > 6:
		var landmarks: Array = s.surface.craters if str(shot[6]) == "crater" else s.surface.volcanoes
		var feature: Dictionary = landmarks[0]
		landmark_dir = feature.direction
		var axis := landmark_dir.cross(Vector3.UP).normalized()
		dir = landmark_dir.rotated(axis, float(feature.width) * 1.4)

	var patch = SP.new()
	add_child(patch)
	patch.bind_body(earth, s)
	var ship: Vector3 = dir * (s.ground_radius_km(dir, radius) + alt)
	for _k in SP.RING_COUNT + 1:
		patch.update_for(ship, body, true, radius, alt, 0.02, ceiling, earth, s)
	# Floating origin, exactly as PlanetSystem does it.
	patch.position = -ship
	var to_sun: Vector3 = (dir * 0.48 + dir.cross(Vector3.UP).normalized() * 0.88).normalized()
	patch.set_view(to_sun, alt, 100.0 if body == "Earth" else 0.0)

	# The body's own globe, so its facets show up here too if they are the culprit.
	var painted: Dictionary = G.paint({"name": body, "physical": true,
		"color": Color(0.169, 0.510, 0.788)}, radius)
	var globe: MeshInstance3D = painted.sphere
	globe.visible = not patch.visible
	globe.position = -ship
	G.apply_view(painted.mat, to_sun, 1.0)
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

	# Camera at the origin (floating origin). Aim at a DEFINITE point on the
	# ground a stated distance ahead, rather than composing a basis by hand - a
	# hand-rolled basis is one sign error away from rendering a view that does not
	# exist, and then the artifact being chased is the probe's.
	var up: Vector3 = dir
	var east: Vector3 = up.cross(Vector3.UP).normalized()
	var north: Vector3 = east.cross(up).normalized()
	var look_km := float(shot[3])
	var target_dir: Vector3 = (dir * radius + north * look_km).normalized()
	if landmark_dir != Vector3.ZERO:
		target_dir = landmark_dir
	var target: Vector3 = target_dir * s.ground_radius_km(target_dir, radius) - ship
	var camera_up := north if absf(target.normalized().dot(up)) > 0.99 else up
	_cam.look_at_from_position(Vector3.ZERO, target, camera_up)
	print("render_terrain:   aiming %.0f km ahead, target %.1f km away, ground below %.0f m"
		% [look_km, target.length(), s.height_m(dir)])
