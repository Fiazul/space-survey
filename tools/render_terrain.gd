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
		# The conditions in the reported screenshots: over water and over a coast.
		[10.0, -35.0, 6.0, 40.0, "ocean_6km"],
		[20.5, -17.0, 6.0, 40.0, "coast_6km"],
		[20.5, -17.0, 15.0, 90.0, "coast_15km"],
		# Above the Himalaya rather than inside it - the ground there is 7626 m.
		[27.95, 86.80, 12.0, 40.0, "himalaya_12km"],
		[27.95, 86.80, 9.0, 18.0, "himalaya_9km"],
	]


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
	var earth := G.recipe_for({"name": "Earth"})
	var s: TerrainSampler = G.terrain_sampler(earth)
	var ceiling: float = G.band_ceiling_km(s)

	var patch = SP.new()
	add_child(patch)
	patch.bind_body(earth, s)
	var ship: Vector3 = dir * (EARTH_R + alt)
	for _k in SP.RING_COUNT + 1:
		patch.update_for(ship, "Earth", true, EARTH_R, alt, 0.02, ceiling, earth, s)
	# Floating origin, exactly as PlanetSystem does it.
	patch.position = -ship
	var to_sun: Vector3 = Vector3(0.45, 0.30, 0.84).normalized()
	patch.set_view(to_sun, alt, 100.0)

	# The body's own globe, so its facets show up here too if they are the culprit.
	var painted: Dictionary = G.paint({"name": "Earth", "physical": true,
		"color": Color(0.169, 0.510, 0.788)}, EARTH_R)
	var globe: MeshInstance3D = painted.sphere
	globe.visible = true
	globe.position = -ship
	G.apply_view(painted.mat, to_sun, 1.0)
	add_child(globe)

	# Camera at the origin (floating origin). Aim at a DEFINITE point on the
	# ground a stated distance ahead, rather than composing a basis by hand - a
	# hand-rolled basis is one sign error away from rendering a view that does not
	# exist, and then the artifact being chased is the probe's.
	var up: Vector3 = dir
	var east: Vector3 = up.cross(Vector3.UP).normalized()
	var north: Vector3 = east.cross(up).normalized()
	var look_km := float(shot[3])
	var target_dir: Vector3 = (dir * EARTH_R + north * look_km).normalized()
	var target: Vector3 = target_dir * s.ground_radius_km(target_dir, EARTH_R) - ship
	_cam.look_at_from_position(Vector3.ZERO, target, up)
	print("render_terrain:   aiming %.0f km ahead, target %.1f km away, ground below %.0f m"
		% [look_km, target.length(), s.height_m(dir)])
