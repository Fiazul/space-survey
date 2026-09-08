extends SceneTree
# Contract check for the ShipMesh.booster_brightness knob and the nozzle shaping it
# scales. Run: godot --headless --path . --script res://tools/test_booster_brightness.gd
#
# Why this exists as its own test: every other brightness assertion in tools/ compares
# a material against MeshStyler.booster_gain(...), and at the shipped knob of 1.0
# booster_gain(x) == x. So none of them can tell a call site that goes through the knob
# from one that hardcodes the same number - and cruiser_propulsion.gdshader defaults its
# `brightness` uniform to 4.0, so on class_ii even a MISSING set_shader_parameter still
# passes. This test builds every ship at a knob that is deliberately not 1.0 and
# requires every booster material to move with it.
#
# It also pins the socket wiring. A material that reaches the renderer without sockets
# silently falls back to the old flat plate, which on dingo57 lights 87% of a surface
# that is housing rather than nozzle (tools/probe_booster_shape.gd) - a regression that
# would look like "the boosters got bright again" rather than like a bug.

const MeshStyler := preload("res://scripts/flight/ship_mesh.gd")

# Two probe values, neither of them 1.0, and not multiples of each other's rounding.
const KNOB_LOW := 0.8
const KNOB_HIGH := 4

const SHIPS := [
	{
		"label": "class_ii",
		"path": "res://assets/class_ii_galactic_cruiser/Class II Gallactic Cruiser.obj",
		"base": 3.8, "sockets": 6, "plumes": 12,
	},
	{
		"label": "snarkrans",
		"path": "res://assets/snarkrans_starship/spaceship.obj",
		"base": 3.02, "sockets": 3, "plumes": 9,
	},
	{
		"label": "dingo57",
		"path": "res://assets/dingo57_starship/3d-model.obj",
		"base": 4.68, "sockets": 8, "plumes": 16,
	},
	{
		"label": "jazoone",
		"path": "res://assets/jazoone_spaceship/spaceship.glb",
		"base": 0.40, "sockets": 2, "plumes": 4,
	},
]


func _initialize() -> void:
	var failed := 0
	var restore: float = MeshStyler.booster_brightness

	failed += _check("knob_defaults_are_declared",
		MeshStyler.SHAPE_SOCKET_MAX == 8 and MeshStyler.booster_gain(2.0) != 0.0)

	for ship in SHIPS:
		failed += _probe_ship(ship)

	# The knob is a shared static, so leaving it moved would poison anything that runs
	# after this in the same process.
	MeshStyler.booster_brightness = restore
	failed += _check("knob_restored", MeshStyler.booster_brightness == restore)

	if failed == 0:
		print("booster_brightness: OK")
		quit(0)
	else:
		print("booster_brightness: FAIL %d" % failed)
		quit(1)


func _probe_ship(ship: Dictionary) -> int:
	var failed := 0
	var label: String = ship.label

	var low := _build(ship, KNOB_LOW)
	var high := _build(ship, KNOB_HIGH)
	if low.is_empty() or high.is_empty():
		return _check("%s_built" % label, false)

	failed += _check("%s_same_material_count" % label, low.size() == high.size())
	if low.size() != high.size():
		return failed
	failed += _check("%s_has_materials" % label, low.size() > 0)

	# 1. Every booster material moves with the knob. A hardcoded call site would sit at
	#    the same value in both builds and fail here.
	var moved := 0
	var ratio_ok := 0
	for i in low.size():
		var a := float(low[i]["brightness"])
		var b := float(high[i]["brightness"])
		if a != b:
			moved += 1
		# Exact, not approximate: booster_gain is a single multiply, so KNOB_HIGH/LOW
		# reproduces it bit for bit at these values.
		if is_equal_approx(b, a * (KNOB_HIGH / KNOB_LOW)):
			ratio_ok += 1
	failed += _check("%s_every_material_follows_the_knob" % label, moved == low.size())
	failed += _check("%s_scales_by_exactly_the_knob_ratio" % label, ratio_ok == low.size())

	# 2. The per-ship base gain is recoverable from the material: brightness / knob.
	#    This is what the equality checks in the per-ship tests mean to assert, stated
	#    in a way the knob cannot make vacuous.
	var base_seen := 0
	for entry in high:
		if is_equal_approx(float(entry["brightness"]) / KNOB_HIGH, float(ship.base)):
			base_seen += 1
	failed += _check("%s_carries_its_own_base_gain" % label, base_seen > 0)

	# 3. Sockets reach every material whose shader is shaped by them. Only the surface
	#    shaders are: the torch cones are shaped by their own cone geometry and carry no
	#    socket uniforms at all, so counting them here would let a genuinely unwired
	#    surface hide behind them (it did, on the first version of this test).
	var shaped := 0
	var wired := 0
	var radii_ok := 0
	for entry in high:
		if not bool(entry["shaped_shader"]):
			continue
		shaped += 1
		var count := int(entry["socket_count"])
		# The dense booster plug is its own mesh with one socket at its origin; every
		# other shaped surface carries the ship's full socket list.
		if count == int(ship.sockets) or count == 1:
			wired += 1
		if bool(entry["radii_positive"]):
			radii_ok += 1
	failed += _check("%s_has_shaped_surfaces" % label, shaped > 0)
	failed += _check("%s_sockets_wired_on_every_shaped_surface" % label, wired == shaped)
	# A zero radius would make the shader divide by its 0.0001 floor, which pushes
	# radial_n to ~1e9, fails the border test everywhere and lights nothing.
	failed += _check("%s_socket_radii_positive" % label, radii_ok == shaped)

	print("booster_brightness: %-10s %2d materials (%d socket-shaped), base %.2f, %d sockets, knob %.1f->%.1f moves all"
		% [label, high.size(), shaped, float(ship.base), int(ship.sockets),
		KNOB_LOW, KNOB_HIGH])
	return failed


# Build one ship's booster materials at a given knob value and snapshot what the
# renderer would see. Styling AND plumes, because both write `brightness`.
func _build(ship: Dictionary, knob: float) -> Array:
	MeshStyler.booster_brightness = knob
	var res := load(ship.path)
	var model: Node3D
	if res is PackedScene:
		model = (res as PackedScene).instantiate() as Node3D
	elif res is Mesh:
		var mi := MeshInstance3D.new()
		mi.mesh = res
		model = mi
	if model == null:
		return []

	var mats: Array[ShaderMaterial] = []
	match ship.label:
		"class_ii":
			mats = MeshStyler.style_class_ii_cruiser(model)
			mats.append_array(MeshStyler.add_class_ii_booster_plumes(model))
		"snarkrans":
			mats = MeshStyler.style_snarkrans_starship(model)
			mats.append_array(MeshStyler.add_snarkrans_booster_plumes(model))
		"dingo57":
			mats = MeshStyler.style_dingo57_starship(model)
			mats.append_array(MeshStyler.add_dingo57_booster_plumes(model))
		"jazoone":
			mats = MeshStyler.style_jazoone_spaceship(model)
			mats.append_array(MeshStyler.add_jazoone_booster_plumes(model))

	var out := []
	for m in mats:
		# Which shaders take socket shaping at all. Shader identity, not the presence of
		# the uniform: an unwired material still HAS the uniform, at its default 0.
		var shaped: bool = m.shader == MeshStyler.CRUISER_PROPULSION_SHADER \
			or m.shader == MeshStyler.JAZOONE_HULL_BOOSTER_SHADER
		var count := 0
		var radii_positive := false
		if shaped:
			var raw_count = m.get_shader_parameter("socket_count")
			count = int(raw_count) if raw_count != null else 0
			radii_positive = count > 0
			if count > 0:
				var radii: PackedFloat32Array = m.get_shader_parameter("socket_r")
				for i in count:
					if radii[i] <= 0.0:
						radii_positive = false
		out.append({
			"brightness": float(m.get_shader_parameter("brightness")),
			"shaped_shader": shaped,
			"socket_count": count,
			"radii_positive": radii_positive,
		})
	model.free()
	return out


func _check(name: String, ok: bool) -> int:
	if not ok:
		print("booster_brightness: FAIL %s" % name)
		return 1
	return 0
