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


func _check(name: String, ok: bool) -> int:
	if not ok:
		print("chase_rig: FAIL %s" % name)
		return 1
	return 0
