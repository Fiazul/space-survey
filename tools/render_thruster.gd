extends Node3D
# Offscreen contact sheet for the booster work. Builds each authored ship exactly the
# way Ship._build_ship_model does (style -> fit -> plumes -> nozzle rig), mirrors
# main.gd's WorldEnvironment so glow/tonemap match the real game, then photographs
# every ship at three throttle settings.
#
# Must run as a real SCENE under a GL-capable display, not with --script: a SceneTree
# script never pumps render frames, so the capture comes back blank.
#   SHOT_DIR=/tmp/shots xvfb-run -a <godot> --path <copy> res://tools/render_thruster.tscn

const ShipMesh := preload("res://scripts/flight/ship_mesh.gd")

const SHIPS := [
	{ "label": "class_ii", "path": "res://assets/class_ii_galactic_cruiser/Class II Gallactic Cruiser.obj",
		"yaw": 180.0, "kind": "class_ii" },
	{ "label": "snarkrans", "path": "res://assets/snarkrans_starship/spaceship.obj",
		"yaw": 180.0, "kind": "snarkrans" },
	{ "label": "dingo57", "path": "res://assets/dingo57_starship/3d-model.obj",
		"yaw": 180.0, "kind": "dingo57" },
	{ "label": "jazoone", "path": "res://assets/jazoone_spaceship/spaceship.glb",
		"yaw": 0.0, "kind": "jazoone" },
]

# power, surge - the two values Ship._update_authored_propulsion feeds the shaders.
const SHOTS := [
	{ "label": "idle", "power": 0.0, "surge": 0.0 },
	{ "label": "cruise", "power": 0.45, "surge": 0.0 },
	{ "label": "burn", "power": 1.0, "surge": 0.55 },
]

var _camera: Camera3D
var _out_dir := "/tmp/thruster_shots"
# DETAIL=1 renders a tight, heavily under-exposed close-up on one nozzle instead of the
# whole-ship sheet. At game exposure the plume core clips to flat white, so the shock
# train and filament structure are only inspectable with the exposure pulled down.
var _detail := false
var _isolate := ""
var _env: Environment


func _ready() -> void:
	var env_dir := OS.get_environment("SHOT_DIR")
	if env_dir != "":
		_out_dir = env_dir
	_detail = OS.get_environment("DETAIL") == "1"
	# ISOLATE=no_rig|no_plumes|hull_only hides layers so an unexplained bright shape
	# can be attributed to the layer that actually draws it.
	_isolate = OS.get_environment("ISOLATE")
	DirAccess.make_dir_recursive_absolute(_out_dir)
	get_window().size = Vector2i(960, 540)
	_build_environment()
	_build_starfield()
	_camera = Camera3D.new()
	_camera.far = 4000.0
	add_child(_camera)
	call_deferred("_run")


func _build_environment() -> void:
	# Copied from main.gd so the sheet shows the same glow/tonemap the game uses.
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.01, 0.01, 0.03)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.22, 0.25, 0.34)
	env.ambient_light_energy = 0.2
	env.glow_enabled = true
	env.glow_normalized = true
	env.glow_intensity = 0.9
	env.glow_bloom = 0.15
	env.glow_strength = 0.85
	env.glow_hdr_threshold = 1.0
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	env.set_glow_level(1, 0.2)
	env.set_glow_level(3, 0.4)
	env.set_glow_level(5, 0.7)
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 0.7
	if _detail:
		# Show the HDR content instead of the clipped result: no glow, linear tonemap,
		# exposure far down. This is a diagnostic view, not what the game looks like.
		env.glow_enabled = false
		env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
		env.tonemap_exposure = 0.0016
		env.ambient_light_energy = 0.05
	_env = env
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)


# Something has to sit behind the plume or the heat-haze refraction is invisible.
func _build_starfield() -> void:
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.emission_enabled = true
	mat.emission = Color(1.0, 1.0, 1.0)
	mat.emission_energy_multiplier = 3.0
	quad.material = mat

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = quad
	mm.instance_count = 700
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	for i in mm.instance_count:
		var dir := Vector3(rng.randfn(), rng.randfn(), rng.randfn()).normalized()
		var s := rng.randf_range(0.35, 1.5)
		var xf := Transform3D(Basis().scaled(Vector3(s, s, s)), dir * rng.randf_range(120.0, 300.0))
		mm.set_instance_transform(i, xf)
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	add_child(mmi)


func _run() -> void:
	for ship in SHIPS:
		var rig = await _build_ship(ship)
		if rig == null:
			print("render: SKIP %s (model failed to load)" % ship.label)
			continue
		for shot in SHOTS:
			_apply_power(rig, float(shot.power), float(shot.surge))
			# TAA/glow need a few frames to settle before the grab.
			for i in 8:
				await get_tree().process_frame
			var img := get_viewport().get_texture().get_image()
			var path := "%s/%s_%s.png" % [_out_dir, ship.label, shot.label]
			img.save_png(path)
			print("render: %s" % path)
		rig.model.queue_free()
		await get_tree().process_frame
	print("render: done")
	get_tree().quit(0)


func _build_ship(ship: Dictionary):
	var res := load(ship.path)
	var model: Node3D
	if res is PackedScene:
		model = (res as PackedScene).instantiate() as Node3D
	elif res is Mesh:
		var mi := MeshInstance3D.new()
		mi.mesh = res
		model = mi
	if model == null:
		return null

	var holder := Node3D.new()
	add_child(holder)
	var torches: Array[ShaderMaterial] = []
	var driven: Array[ShaderMaterial] = []
	match ship.kind:
		"class_ii": driven.append_array(ShipMesh.style_class_ii_cruiser(model))
		"snarkrans": driven.append_array(ShipMesh.style_snarkrans_starship(model))
		"dingo57": driven.append_array(ShipMesh.style_dingo57_starship(model))
		"jazoone": driven.append_array(ShipMesh.style_jazoone_spaceship(model))
	holder.add_child(model)
	model.rotation = Vector3(0.0, deg_to_rad(float(ship.yaw)), 0.0)
	ShipMesh.fit_model(holder, model, 4.0)

	var plumes: Array[ShaderMaterial] = []
	match ship.kind:
		"class_ii": plumes = ShipMesh.add_class_ii_booster_plumes(model)
		"snarkrans": plumes = ShipMesh.add_snarkrans_booster_plumes(model)
		"dingo57": plumes = ShipMesh.add_dingo57_booster_plumes(model)
		"jazoone": plumes = ShipMesh.add_jazoone_booster_plumes(model)
	for m in plumes:
		if m.shader == ShipMesh.CRUISER_TORCH_SHADER:
			torches.append(m)
	driven.append_array(plumes)
	driven.append_array(ShipMesh.collect_haze_materials(model))
	var lights := ShipMesh.collect_nozzle_lights(model)
	# The game recolours every non-propulsion surface before lighting it; without this
	# the raw imported materials render nothing like the shipped ship.
	ShipMesh.color_authored_ship(model, Color(0.62, 0.66, 0.74), "metal")
	var box := ShipMesh.combined_aabb(holder)
	# Match the roster's light_energy band (0.34-0.42). Higher blows metallic hulls
	# into a featureless bloom blob.
	ShipMesh.add_hull_lights(holder, box, Color(0.9, 0.92, 1.0), 0.40)

	# Finer-grained: hide one rig layer at a time.
	var rig := model.get_node_or_null("BoosterNozzleRig")
	if rig != null and _isolate != "":
		for child in rig.get_children():
			var n := String(child.name)
			var hide := (_isolate == "no_lights" and child is OmniLight3D) \
				or (_isolate == "no_haze" and n.begins_with("BoosterHaze")) \
				or (_isolate == "no_embers" and child is GPUParticles3D) \
				or (_isolate == "embers_only" and not (child is GPUParticles3D))
			if hide and child is Node3D:
				(child as Node3D).visible = false
			if child is GPUParticles3D:
				var e := child as GPUParticles3D
				var pmm := e.process_material as ParticleProcessMaterial
				var qm := e.draw_pass_1 as QuadMesh
				print("render: embers node_scale=%s quad=%s scale_min=%.4f scale_max=%.4f -> world spark %.5f..%.5f"
					% [e.global_transform.basis.get_scale(), qm.size, pmm.scale_min, pmm.scale_max,
					qm.size.x * pmm.scale_min * e.global_transform.basis.get_scale().x,
					qm.size.x * pmm.scale_max * e.global_transform.basis.get_scale().x])
	if _isolate == "no_rig" or _isolate == "hull_only":
		var rig_node := model.get_node_or_null("BoosterNozzleRig")
		if rig_node != null:
			(rig_node as Node3D).visible = false
	if _isolate == "no_plumes" or _isolate == "hull_only" or _isolate == "embers_only":
		for child in model.get_children():
			if String(child.name).ends_with("AuthoredBoosterPlumes") and child is Node3D:
				(child as Node3D).visible = false
	if _isolate != "":
		print("render: ISOLATE=%s applied" % _isolate)

	await get_tree().process_frame
	# Frame the whole thing INCLUDING the plumes, which extend well past the hull.
	var full := ShipMesh.combined_aabb(holder)
	var centre := full.position + full.size * 0.5
	var reach: float = maxf(full.size.length(), 1.0)
	# Exhaust leaves along world +Z for every ship (the yaw-180 models point their
	# model -Z aft). Sitting ON the +Z axis means staring straight down the nozzle,
	# which just shows a saturated end-cap - so weight the camera to the SIDE and
	# only slightly aft, to see the plume across its length.
	_camera.position = centre + Vector3(1.0, 0.30, 0.58).normalized() * reach * 0.95
	if _detail:
		# Frame the exhaust column itself, not the ship: push aft of the hull and
		# close in, so one plume spans the frame.
		var aft := centre + Vector3(0.0, 0.0, full.size.z * 0.42)
		_camera.position = aft + Vector3(1.0, 0.16, 0.10).normalized() * reach * 0.34
		_camera.look_at(aft, Vector3.UP)
	else:
		_camera.look_at(centre, Vector3.UP)
	print("render: built %s  aabb=%s  lights=%d torches=%d driven=%d"
		% [ship.label, full.size, lights.size(), torches.size(), driven.size()])
	return { "model": holder, "torches": torches, "driven": driven, "lights": lights }


# Mirrors Ship._update_authored_propulsion so the sheet shows exactly what the game does.
func _apply_power(rig: Dictionary, p: float, surge: float) -> void:
	var heat := clampf(p * 1.12 + surge * 0.25, 0.0, 1.0)
	for m in rig.driven:
		m.set_shader_parameter("power", lerpf(0.42, 1.0, p))
		m.set_shader_parameter("flow_speed", lerpf(0.8, 3.1, p))
		m.set_shader_parameter("temperature", heat)
	for m in rig.torches:
		m.set_shader_parameter("length_scale", lerpf(0.52, 1.30, p) + surge * 0.42)
		m.set_shader_parameter("flare_scale", lerpf(0.80, 1.06, p) + surge * 0.10)
		m.set_shader_parameter("turbulence", lerpf(0.55, 1.35, p))
	var lit := Color(1.0, 0.33, 0.06).lerp(Color(0.35, 0.70, 1.0), smoothstep(0.12, 0.78, heat))
	for l in rig.lights:
		l.light_color = lit
		l.light_energy = lerpf(0.10, 1.45, p) + surge * 0.55
