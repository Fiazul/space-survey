extends Node
# Diagnostic: "there is a visible ring over Earth and Moon, like a bridge or
# something around the globe" — reported at BOTH bodies, so an Earth-only
# shell (CloudLayer, air shell) is unlikely; suspects are whatever is drawn
# for EVERY physical body: the far-distance sky impostor (_place_body_sky in
# planet_system.gd), the SurfacePatch ring/skirt, or the coarse globe's own
# facets. This does not fix anything — it only captures evidence.
#
# Run (needs a real GL context — see render_terrain.gd, same caveat):
#   SHOT_DIR=<dir> SHELLS=all|nosky|nosurface|noclouds \
#     xvfb-run -a godot --path . res://tools/render_approach.tscn
#
# SHOT_DIR: directory PNGs are written to (created if missing).
# SHELLS: which shell(s) stay visible this run — "all" (default) draws sky
# impostor + SurfacePatch + CloudLayer; the other three hide ONE each so a
# diff between runs shows which node the ring belongs to.

const G := preload("res://scripts/world/planet_generator.gd")
const SP := preload("res://scripts/world/surface_patch.gd")
const CL := preload("res://scripts/world/cloud_layer.gd")

const RADII := {"Moon": 1737.4, "Earth": 6371.0}
# ship.gd CAM_VIEW_PITCH_DEG (chase rig looks down at the ship this many degrees
# below level so the dorsal hull reads) — the closest real-game analogue this
# tool has to "how far below horizontal does the player's view sit" at a normal
# altitude approach.
const CHASE_PITCH_DEG := -14.0

var _cam: Camera3D
var _shots := []
var _i := 0
var _wait := 0
var _shells := "all"
var _shot_dir := "/tmp"


func _ready() -> void:
	get_viewport().transparent_bg = false
	_shells = OS.get_environment("SHELLS")
	if _shells.is_empty():
		_shells = "all"
	_shot_dir = OS.get_environment("SHOT_DIR")
	if _shot_dir.is_empty():
		_shot_dir = "/tmp"
	DirAccess.make_dir_recursive_absolute(_shot_dir)

	_cam = Camera3D.new()
	_cam.far = 900000.0
	_cam.near = 0.05
	_cam.fov = 70.0
	add_child(_cam)
	var sun := DirectionalLight3D.new()
	add_child(sun)

	# distance shots (multiples of body radius R, looking at the body centre
	# from far enough out that the whole limb sits in frame) + altitude shots
	# (km above ground, looking along the horizon so the limb is in frame).
	var full_toggles := ["all", "nosky"]
	var all_toggles := ["all", "nosky", "nosurface", "noclouds"]
	var alt_by_body := {"Moon": [60.0, 40.0, 30.0, 25.0, 15.0], "Earth": [60.0, 40.0, 25.0]}
	for body in ["Moon", "Earth"]:
		for r_mult in [30.0, 8.0, 3.0, 1.5]:
			var toggles: Array = all_toggles if r_mult == 1.5 else full_toggles
			_shots.append({"body": body, "kind": "dist", "value": r_mult,
				"label": "%s_dist_%sR" % [body.to_lower(), str(r_mult).replace(".0", "")],
				"toggles": toggles})
		for alt_km in alt_by_body[body]:
			# Ring-defect review (2026-09-09): approach altitude sweep, real
			# hide rule (globe hidden iff patch.visible, matching
			# planet_system.gd's own `_surface.visible and _surface.has_ground()`
			# gate) checked against `all` and `nosurface` at every altitude.
			_shots.append({"body": body, "kind": "alt", "value": alt_km,
				"label": "%s_alt_%dkm" % [body.to_lower(), int(alt_km)],
				"toggles": ["all", "nosurface"]})
	_shots = _shots.filter(func(s: Dictionary) -> bool: return _shells in s.toggles)
	var only := OS.get_environment("APPROACH_SHOTS")
	if not only.is_empty():
		_shots = _shots.filter(func(s: Dictionary) -> bool: return str(s.label) in only.split(","))


func _process(_dt: float) -> void:
	if _i >= _shots.size():
		get_tree().quit(0)
		return
	if _wait == 0:
		_setup(_shots[_i])
	_wait += 1
	if _wait > 6:
		var img := get_viewport().get_texture().get_image()
		var path := "%s/%s_%s.png" % [_shot_dir, _shots[_i].label, _shells]
		img.save_png(path)
		print("render_approach: %s -> %s" % [_shots[_i].label, path])
		_i += 1
		_wait = 0


func _setup(shot: Dictionary) -> void:
	for c in get_children():
		if c is Node3D and c != _cam and not (c is DirectionalLight3D):
			c.queue_free()

	var body: String = shot.body
	var radius: float = RADII[body]
	var lat := deg_to_rad(10.0)
	var lon := deg_to_rad(20.0)
	var dir := Vector3(cos(lat) * cos(lon), sin(lat), cos(lat) * sin(lon)).normalized()

	var recipe := G.recipe_for({"name": body})
	var s: TerrainSampler = G.terrain_sampler(recipe)
	var ceiling: float = G.band_ceiling_km(s)

	var ship: Vector3
	var target: Vector3
	var up: Vector3 = dir
	if shot.kind == "dist":
		ship = dir * (radius * float(shot.value))
		target = -ship  # body true centre is 0; ship is at `ship`; relative vector to centre
	else:
		var alt: float = shot.value
		ship = dir * (s.ground_radius_km(dir, radius) + alt)
		var cam_east: Vector3 = up.cross(Vector3.UP).normalized()
		var north: Vector3 = cam_east.cross(up).normalized()
		var look_km: float = sqrt(2.0 * radius * alt) * 1.6
		var target_dir: Vector3 = (dir * radius + north * look_km).normalized()
		target = target_dir * s.ground_radius_km(target_dir, radius) - ship

	# --- SurfacePatch (the "_surface" node in planet_system.gd) ---
	var patch := SP.new()
	add_child(patch)
	patch.bind_body(recipe, s)
	var alt_for_patch: float = (ship.length() - radius) if shot.kind == "dist" else float(shot.value)
	patch.update_for(ship, body, true, radius, alt_for_patch, 0.02, ceiling, recipe, s)
	patch.force_ready()
	patch.position = -ship
	var east: Vector3 = dir.cross(Vector3.UP).normalized()
	var to_sun: Vector3 = (dir * 0.48 + east * 0.88).normalized()
	patch.set_view(to_sun, alt_for_patch, 100.0 if body == "Earth" else 0.0)
	patch.visible = patch.visible and _shells != "nosurface"

	# --- The body's own coarse globe (candidate: its own facet/rim) ---
	var painted: Dictionary = G.paint({"name": body, "physical": true,
		"color": Color(0.169, 0.510, 0.788)}, radius)
	var globe: MeshInstance3D = painted.sphere
	globe.position = -ship
	G.ensure_close_maps(painted.mat, recipe, false)
	# alt_km/atmo_top_km (100.0 for Earth, matching this file's existing
	# air_shell_opacity/set_view calls just below) feed the limb-width
	# altitude falloff added to planet_cook.gdshader (the "60 km glowing
	# wall" fix) — without these two trailing args this capture would render
	# the OLD unmodified curve and the fix would be invisible in the shots
	# this brief asks for. render_approach.gd is not in this brief's owned
	# file list; flagging this one-line, default-safe addition for review.
	G.apply_view(painted.mat, to_sun, G.close_detail(alt_for_patch), alt_for_patch,
		100.0 if body == "Earth" else 0.0)
	# planet_system.gd:750-753 hides the body's own coarse globe whenever the
	# ring is up AND has ground (`_surface.visible and _surface.has_ground()`) —
	# `patch.visible` above already IS `in_band and has_ground()` (surface_patch.gd
	# update_for/_finish_rebuild), so `not patch.visible` reproduces that gate
	# exactly (same pattern render_terrain.gd uses). The earlier `true` here never
	# hid the globe at all, so its own coarse facets always sat under/through the
	# ring — the leading suspect for the reported flat quadrilateral patches.
	globe.visible = not patch.visible
	add_child(globe)

	# --- Sky impostor, same construction as planet_system._make_body_sky /
	# _place_body_sky. At the distances/altitudes probed here (<= 30 R, always
	# far under Ephemeris.CAM_FAR_SOL * 0.85), physical_too_far() is expected
	# to read false — i.e. the impostor should NEVER be the culprit in this
	# probe's range. Built anyway so a SHELLS=nosky run gives an empirical
	# answer instead of an assumption.
	var dist: float = ship.length()
	var too_far: bool = Ephemeris.physical_too_far(dist, radius)
	if too_far and _shells != "nosky":
		var mi := MeshInstance3D.new()
		var mesh := SphereMesh.new()
		mesh.radius = 1.0
		mesh.height = 2.0
		mesh.radial_segments = 24
		mesh.rings = 12
		mi.mesh = mesh
		var sky_mat: Material = G.make_material(recipe, {"name": body, "physical": true})
		if sky_mat is StandardMaterial3D:
			var sm := sky_mat as StandardMaterial3D
			sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			sm.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_OPAQUE_ONLY
			G.apply_sky(sm, recipe, {"name": body, "physical": true})
		mi.material_override = sky_mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var shell: float = Ephemeris.sky_impostor_km(dist)
		var ang := asin(clampf(radius / dist, 0.0, 0.999))
		var r: float = maxf(shell * tan(ang), 2.0)
		mi.scale = Vector3.ONE * r
		mi.position = (-ship / dist) * shell
		add_child(mi)
		print("render_approach:   sky impostor ACTIVE for %s (dist=%.0f km, too_far=true)" % [shot.label, dist])

	# --- CloudLayer (Earth only has real cover; built for every body the same
	# way planet_system.gd does, so its own gating speaks for itself) ---
	var cloud := CL.new()
	add_child(cloud)
	cloud.update_for(-ship, body, true, radius, alt_for_patch, 0.02, ceiling, recipe, to_sun, 0.0)
	cloud.visible = cloud.visible and _shells != "noclouds"

	if body == "Earth":
		var sky_shell := MeshInstance3D.new()
		var shell_mesh := SphereMesh.new()
		shell_mesh.radius = 200000.0
		shell_mesh.height = 400000.0
		sky_shell.mesh = shell_mesh
		var air_mat := G.air_shell_material(recipe, {"spectral": "G"})
		air_mat.set_shader_parameter("opacity", G.air_shell_opacity(alt_for_patch, 100.0, float(recipe.get("air_amount", 0.0))))
		air_mat.set_shader_parameter("sun_dir", to_sun)
		air_mat.set_shader_parameter("up_dir", dir)
		sky_shell.material_override = air_mat
		add_child(sky_shell)

	_cam.look_at_from_position(Vector3.ZERO, target, Vector3.UP if shot.kind == "dist" else dir)
	if shot.kind == "alt":
		_cam.rotate_object_local(Vector3.RIGHT, deg_to_rad(CHASE_PITCH_DEG))
	print("render_approach: %s (%s) shells=%s patch_vis=%s cloud_vis=%s too_far=%s dist=%.0f km"
		% [shot.label, body, _shells, patch.visible, cloud.visible, too_far, dist])
