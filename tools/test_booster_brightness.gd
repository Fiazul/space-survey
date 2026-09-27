extends SceneTree
# Contract check for the ShipMesh.booster_brightness knob across the modular hulls.
# Run: godot --headless --path . --script res://tools/test_booster_brightness.gd
#
# At the shipped knob booster_gain(x) == x only when the knob is 1.0, so a call site
# that hardcodes a gain instead of going through the knob is invisible there. Every
# hull is built at two knob values that are not 1.0 and every booster material (nozzle
# pass, fog and core cones) must scale by exactly their ratio. It also pins the nozzle
# shaping: one socket per SOCKET_BOOSTER_n, each with a positive measured radius.

const KNOB_LOW := 0.8
const KNOB_HIGH := 4.0
const HULLS := {"kestrel": 2, "swift": 2, "harrier": 2, "osprey": 3, "condor": 4, "albatross": 4}


func _initialize() -> void:
	var failed := 0
	var restore: float = ShipMesh.booster_brightness
	failed += _check("knob_defaults_are_declared",
		ShipMesh.SHAPE_SOCKET_MAX == 8 and ShipMesh.booster_gain(2.0) != 0.0)
	for slug in HULLS:
		var low := _build(slug, KNOB_LOW)
		var high := _build(slug, KNOB_HIGH)
		var boosters: int = HULLS[slug]
		failed += _check("%s_material_count" % slug, low.size() == high.size() and low.size() == boosters * 2 + 1)
		if low.size() != high.size():
			continue
		var ratio_ok := 0
		var shaped := 0
		for i in low.size():
			if is_equal_approx(float(high[i].brightness), float(low[i].brightness) * (KNOB_HIGH / KNOB_LOW)):
				ratio_ok += 1
			if high[i].shaped:
				shaped += 1
				failed += _check("%s_sockets_wired" % slug, int(high[i].socket_count) == boosters and high[i].radii_positive)
		failed += _check("%s_every_material_follows_the_knob" % slug, ratio_ok == low.size())
		failed += _check("%s_has_shaped_nozzle" % slug, shaped >= 1)
		print("booster_brightness: %-10s %2d materials (%d socket-shaped), %d boosters" % [slug, high.size(), shaped, boosters])
	ShipMesh.booster_brightness = restore
	failed += _check("knob_restored", ShipMesh.booster_brightness == restore)
	if failed == 0:
		print("booster_brightness: OK")
		quit(0)
	else:
		print("booster_brightness: FAIL %d" % failed)
		quit(1)


func _build(slug: String, knob: float) -> Array:
	ShipMesh.booster_brightness = knob
	var model := (load("res://assets/ships/%s/%s.glb" % [slug, slug]) as PackedScene).instantiate() as Node3D
	var mats := ModularHull.style(model, Color.WHITE)
	mats.append_array(ModularHull.add_plumes(model))
	var out := []
	for m in mats:
		var shaped := m.shader == ShipMesh.CRUISER_PROPULSION_SHADER
		var radii_positive := true
		if shaped:
			var radii: PackedFloat32Array = m.get_shader_parameter("socket_r")
			for i in int(m.get_shader_parameter("socket_count")):
				radii_positive = radii_positive and radii[i] > 0.0
		out.append({"brightness": m.get_shader_parameter("brightness"), "shaped": shaped,
			"socket_count": m.get_shader_parameter("socket_count"), "radii_positive": radii_positive})
	model.free()
	return out


func _check(label: String, condition: bool) -> int:
	if condition:
		return 0
	push_error("booster_brightness: " + label)
	return 1
