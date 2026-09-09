extends Node
# Headless contract for the third-person chase rig and the ship-only fill light.
# Run: godot --headless --path . res://tools/test_chase_rig.tscn
#
# A SCENE, not a --script test, unlike the rest of tools/. It preloads ship.gd to read
# the rig constants, and ship.gd touches the Ephemeris autoload at parse time - which a
# --script run does not register, so the whole file fails to compile there.
#
# Two things here are one sign flip away from being useless, and neither shows up in
# any other test:
#   1. CAM_VIEW_PITCH_DEG. Positive orbits the rig BELOW the ship. The whole point of
#      the angle is to look DOWN the spine and see the dorsal hull instead of a flat
#      tail plate, so the elevation and the aim direction are asserted, not the number.
#   2. The fill light's cull mask. If it ever picks up layer 1 it stops being a ship
#      light and becomes a second sun over the planets, the station and the props.

const MeshStyler := preload("res://scripts/flight/ship_mesh.gd")
const ShipScript := preload("res://scripts/flight/ship.gd")

const SHIPS := [
	"res://assets/class_ii_galactic_cruiser/Class II Gallactic Cruiser.obj",
	"res://assets/snarkrans_starship/spaceship.obj",
	"res://assets/dingo57_starship/3d-model.obj",
	"res://assets/jazoone_spaceship/spaceship.glb",
]


func _ready() -> void:
	var failed := 0
	failed += _camera_angle()
	failed += _fill_light()
	failed += _layer_tagging()
	failed += _boost_no_hop()
	failed += _free_look_no_flip()
	if failed == 0:
		print("chase_rig: OK")
		get_tree().quit(0)
	else:
		print("chase_rig: FAIL %d" % failed)
		get_tree().quit(1)


# Rebuild the rig transform exactly as Ship._update_camera does at rest (no free-look,
# no zoom, ship level) and check where the eye ends up and where it looks.
func _camera_angle() -> int:
	var failed := 0
	var basis := Basis(Vector3.RIGHT, deg_to_rad(ShipScript.CAM_VIEW_PITCH_DEG))
	var eye: Vector3 = basis * ShipScript.CAM_OFFSET
	var aim: Vector3 = basis * Vector3.FORWARD   # camera looks down its local -Z

	# Above and behind the hull. CAM_OFFSET is in hull lengths, so these are ratios.
	failed += _check("eye_is_behind_the_ship", eye.z > 0.5)
	failed += _check("eye_is_above_the_ship", eye.y > 0.0)
	# The old rig sat at 0 deg: the eye was up but the AIM was dead level, so the top
	# of the hull stayed edge-on. The aim must now tip downward.
	failed += _check("aim_tips_downward", aim.y < -0.05)
	# ...but not so far that the plumes leave the frame. Anything past ~45 deg total
	# elevation is an overhead map view, not a chase cam.
	var elevation := rad_to_deg(atan2(eye.y, eye.z))
	failed += _check("elevation_is_a_chase_view_not_an_overhead", elevation > 8.0 and elevation < 45.0)
	failed += _check("no_sideways_drift", is_zero_approx(eye.x))
	print("chase_rig: view pitch %.1f deg -> eye (%.2f, %.2f, %.2f) hull-lengths, %.1f deg elevation, aim.y %.3f"
		% [ShipScript.CAM_VIEW_PITCH_DEG, eye.x, eye.y, eye.z, elevation, aim.y])
	return failed


func _fill_light() -> int:
	var failed := 0
	# The layer bit must NOT include layer 1 (value 1). Everything else in the game
	# sits on layer 1 alone, and that is the only reason a cull mask of this bit
	# reaches the hull and nothing else.
	failed += _check("fill_layer_excludes_the_default_layer",
		(MeshStyler.SHIP_FILL_LAYER & 1) == 0 and MeshStyler.SHIP_FILL_LAYER != 0)
	failed += _check("fill_lifts_the_shadow_side", ShipScript.HULL_FILL_ENERGY > 0.0)
	# Point lights at this range clipped their own specular on polished metal and blew
	# the engine bay white (see the note in Ship._build_ship_model). This light is
	# directional AND keeps its specular contribution near zero, so only diffuse lifts.
	failed += _check("fill_specular_stays_out_of_the_way",
		ShipScript.HULL_FILL_SPECULAR >= 0.0 and ShipScript.HULL_FILL_SPECULAR <= 0.3)
	# Off-axis, or it is a flat frontal light that erases the panel detail it exists
	# to reveal. Signs matter: pitch must come from ABOVE (negative).
	failed += _check("fill_comes_from_above", ShipScript.HULL_FILL_PITCH_DEG < -5.0)
	failed += _check("fill_is_off_axis", absf(ShipScript.HULL_FILL_YAW_DEG) > 10.0)
	# Rebuild its direction the way the node does, and confirm it shines downward onto
	# the ship rather than up from underneath.
	var rot := Basis.from_euler(Vector3(
		deg_to_rad(ShipScript.HULL_FILL_PITCH_DEG), deg_to_rad(ShipScript.HULL_FILL_YAW_DEG), 0.0))
	var ray: Vector3 = rot * Vector3.FORWARD
	failed += _check("fill_rays_travel_downward", ray.y < 0.0)
	print("chase_rig: fill %.2f energy, spec %.2f, cull bit %d, rays (%.2f, %.2f, %.2f)"
		% [ShipScript.HULL_FILL_ENERGY, ShipScript.HULL_FILL_SPECULAR,
		MeshStyler.SHIP_FILL_LAYER, ray.x, ray.y, ray.z])
	return failed


# Every mesh on every hull must carry the fill bit, and must KEEP layer 1 so the
# scene sun and counter-fill still reach it.
func _layer_tagging() -> int:
	var failed := 0
	for path in SHIPS:
		var label: String = path.get_file()
		var res := load(path)
		var model: Node3D
		if res is PackedScene:
			model = (res as PackedScene).instantiate() as Node3D
		elif res is Mesh:
			var mi := MeshInstance3D.new()
			mi.mesh = res
			model = mi
		if model == null:
			failed += _check("%s_loaded" % label, false)
			continue

		var tagged := MeshStyler.tag_fill_layer(model)
		var counts := _audit_counts(model)
		failed += _check("%s_tagged_every_mesh" % label, tagged == counts.total and counts.total > 0)
		failed += _check("%s_no_mesh_left_untagged" % label, counts.missing == 0)
		failed += _check("%s_still_lit_by_the_scene_sun" % label, counts.lost_default == 0)
		print("chase_rig: %-24s %d meshes tagged" % [label, counts.total])
		model.free()
	return failed


func _audit_counts(node: Node) -> Dictionary:
	var out := {"total": 0, "missing": 0, "lost_default": 0}
	if node is VisualInstance3D:
		var layers: int = (node as VisualInstance3D).layers
		out.total += 1
		if (layers & MeshStyler.SHIP_FILL_LAYER) == 0:
			out.missing += 1
		if (layers & 1) == 0:
			out.lost_default += 1
	for child in node.get_children():
		var sub := _audit_counts(child)
		out.total += sub.total
		out.missing += sub.missing
		out.lost_default += sub.lost_default
	return out


# Reported bug (pre-2026-09-09): pressing Shift (boost) made the camera "hop" via
# a camera g-sag term reading last_thrust_accel with no smoothing. The whole g-sag/
# buffet visual layer was removed 2026-09-09 as unreachable in controlled flight
# (see NEEDS-YOUR-EYES.md #6) — _update_camera no longer reads last_thrust_accel at
# all, so stepping it (exactly as ship.gd's boost multiply does) must produce ZERO
# camera movement now. Kept as a regression guard against that coupling coming back.
func _boost_no_hop() -> int:
	var failed := 0
	var ship := ShipScript.new()
	add_child(ship)
	ship.camera = Camera3D.new()
	add_child(ship.camera)
	ship._hull_km = 0.08
	var dt := 1.0 / 60.0
	var base_accel := Vector3(0.0, 0.0, -0.01962)   # ~2g NEWTON_THRUST
	ship.last_newton_g = Vector3(0.0, -0.0098, 0.0)  # ~1g, constant throughout
	ship.last_thrust_accel = base_accel
	ship.air_load = 0.0
	for _priming in 60:   # let the low-pass fully settle before measuring
		ship._update_camera(dt)
	var prev_pos := ship.camera.global_position
	var max_delta := 0.0
	for _frame in 60:
		ship.last_thrust_accel = base_accel * ShipScript.BOOST_MULT   # the exact step ship.gd takes
		ship._update_camera(dt)
		var pos: Vector3 = ship.camera.global_position
		max_delta = maxf(max_delta, pos.distance_to(prev_pos))
		prev_pos = pos
	failed += _check("boost_toggle_no_camera_hop", max_delta < 0.003)
	print("chase_rig: boost toggle max per-frame camera delta %.6f km" % max_delta)
	ship.queue_free()
	return failed


# Reported bug: free-look "flicked to the opposite angle" while T was still held.
# _look_yaw had no ceiling AND no per-call step limit, so a mouse-delta backlog (a
# hitch queuing several frames' worth of relative motion before the next _process,
# or a capture blip) could swing it by any amount in one call. Now yaw is UNBOUNDED
# (never clamped) and the per-call step is rate-limited (rad/s), not a flat per-frame
# cap — a 60 fps and a 30 fps sweep must move at the same angular speed, and a
# backlog spike must still be bounded to at most LOOK_MAX_RATE_RAD_S * delta.
func _free_look_no_flip() -> int:
	var failed := 0
	var ship := ShipScript.new()
	add_child(ship)
	# A full 360-degree sweep at 60 fps and at 30 fps: both must cover the same
	# angular distance per second (i.e. the rate limit, not a flat frame-count cap).
	# _look_yaw wraps into [-PI, PI] (never clamped), so raw before/after subtraction
	# spuriously reads a huge jump every time the sweep crosses the wrap boundary —
	# wrapf the DIFFERENCE itself back into [-PI, PI] to read the true per-call step.
	var dt60 := 1.0 / 60.0
	var deg_per_s_60 := 0.0
	for _f in 720:
		var before: float = ship._look_yaw
		ship._apply_free_look(Vector2(400.0, 0.0), dt60)
		var step := wrapf(ship._look_yaw - before, -PI, PI)
		deg_per_s_60 = maxf(deg_per_s_60, rad_to_deg(absf(step)) / dt60)
	ship._look_yaw = 0.0
	var dt30 := 1.0 / 30.0
	var deg_per_s_30 := 0.0
	for _f in 360:
		var before2: float = ship._look_yaw
		ship._apply_free_look(Vector2(400.0, 0.0), dt30)
		var step2 := wrapf(ship._look_yaw - before2, -PI, PI)
		deg_per_s_30 = maxf(deg_per_s_30, rad_to_deg(absf(step2)) / dt30)
	failed += _check("free_look_60fps_30fps_same_deg_per_s",
		absf(deg_per_s_60 - deg_per_s_30) < 1.0)
	failed += _check("free_look_rate_at_cap",
		absf(deg_per_s_60 - rad_to_deg(ShipScript.LOOK_MAX_RATE_RAD_S)) < 1.0)
	# A 4000 px spike at dt=1/60 (a hitch-sized backlog in one call) must be bounded
	# to at most LOOK_MAX_RATE_RAD_S/60 rad, not presented all at once.
	ship._look_yaw = 0.0
	var before_yaw: float = ship._look_yaw
	ship._apply_free_look(Vector2(4000.0, 0.0), dt60)
	var spike_step := absf(ship._look_yaw - before_yaw)
	var cap_step := ShipScript.LOOK_MAX_RATE_RAD_S * dt60
	failed += _check("free_look_spike_bounded_to_rate_cap", spike_step <= cap_step + 1.0e-6)
	print("chase_rig: free-look 60fps %.2f deg/s, 30fps %.2f deg/s, spike step %.5f rad (cap %.5f rad)"
		% [deg_per_s_60, deg_per_s_30, spike_step, cap_step])
	# Reported bug: orbiting past +-180 deg spun the CAMERA a full turn. _look_yaw
	# itself was already rate-limited above; the flip was in _update_camera's
	# SMOOTHING (_look_yaw_s = lerpf(...)), which has no notion of the wrap — when
	# the target crossed from +179 to -179 deg the smoothed value eased the LONG
	# way through 0 (a ~358 deg swing over a few frames). Drive the target steadily
	# across the wrap boundary (several times) while calling _update_camera and
	# assert the SMOOTHED yaw's own per-frame step never blows past the same rate
	# cap the target itself is held to.
	ship.camera = Camera3D.new()
	add_child(ship.camera)
	ship._look_yaw = 0.0
	ship._look_yaw_s = 0.0
	for _f in 30:                     # let the smoother settle at rest first
		ship._update_camera(dt60)
	var max_cam_step := 0.0
	for _f in 120:
		ship._apply_free_look(Vector2(-10000.0, 0.0), dt60)   # saturates the rate cap every frame
		var before_s: float = ship._look_yaw_s
		ship._update_camera(dt60)
		var cam_step := absf(wrapf(ship._look_yaw_s - before_s, -PI, PI))
		max_cam_step = maxf(max_cam_step, cam_step)
	failed += _check("free_look_camera_yaw_never_exceeds_rate_cap_across_wrap",
		max_cam_step <= ShipScript.LOOK_MAX_RATE_RAD_S * dt60 + 1.0e-3)
	print("chase_rig: free-look camera yaw max per-frame step across wrap %.5f rad (cap %.5f rad)"
		% [max_cam_step, ShipScript.LOOK_MAX_RATE_RAD_S * dt60 + 1.0e-3])
	# Releasing from near the boundary (T key up snaps the TARGET straight to 0,
	# main.gd's various `_look_yaw = 0.0` resets) is not itself a wrap crossing —
	# the short way from +-170 deg to 0 is <=170 deg total, same as a plain lerp
	# would take. Regression guard on lerp_angle picking the same short arc here.
	for start_deg in [170.0, -170.0]:
		ship._look_yaw = 0.0
		ship._look_yaw_s = deg_to_rad(start_deg)
		var traveled := 0.0
		var prev: float = ship._look_yaw_s
		for _f in 200:
			ship._update_camera(dt60)
			traveled += absf(wrapf(ship._look_yaw_s - prev, -PI, PI))
			prev = ship._look_yaw_s
			if absf(ship._look_yaw_s) < 0.0005:
				break
		failed += _check("free_look_release_from_%d_deg_takes_short_path" % int(start_deg),
			rad_to_deg(traveled) <= 170.5)
	ship.queue_free()
	return failed


func _check(name: String, ok: bool) -> int:
	if not ok:
		print("chase_rig: FAIL %s" % name)
		return 1
	return 0
