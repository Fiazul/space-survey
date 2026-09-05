extends Node3D
# Offscreen contact sheet for the booster work. Builds each authored ship exactly the
# way Ship._build_ship_model does (style -> fit -> plumes -> nozzle rig), mirrors
# main.gd's WorldEnvironment so glow/tonemap match the real game, then photographs
# every ship at three throttle settings.
#
# Must run as a real SCENE under a GL-capable display, not with --script: a SceneTree
# script never pumps render frames, so the capture comes back blank.
#   SHOT_DIR=/tmp/shots xvfb-run -a <godot> --path <copy> res://tools/render_thruster.tscn
# SHIP=class_ii filters the roster; VIEW=rear gives a centred Class II nozzle comparison.

const ShipMesh := preload("res://scripts/flight/ship_mesh.gd")
const WedgeDesign := preload("res://scripts/flight/wedge_fighter.gd")

# `accent` / `light_energy` are copied from Ship.SHIP_MODELS, and `swatch` from the
# palette each ship defaults to, so add_hull_lights and color_authored_ship get what the
# real ship gets. A generic grey hull under a generic cool key light is NOT the game.
const SHIPS := [
	{ "label": "class_ii", "path": "res://assets/class_ii_galactic_cruiser/Class II Gallactic Cruiser.obj",
		"yaw": 180.0, "kind": "class_ii",
		"accent": Color(0.72, 0.85, 1.00), "swatch": Color(0.42, 0.60, 0.95),
		"light_energy": 0.42, "finish": "metal" },
	{ "label": "snarkrans", "path": "res://assets/snarkrans_starship/spaceship.obj",
		"yaw": 180.0, "kind": "snarkrans",
		"accent": Color(0.85, 0.90, 1.00), "swatch": Color(0.30, 0.31, 0.34),
		"light_energy": 0.38, "finish": "metal" },
	{ "label": "dingo57", "path": "res://assets/dingo57_starship/3d-model.obj",
		"yaw": 180.0, "kind": "dingo57",
		"accent": Color(0.92, 0.95, 1.00), "swatch": Color(0.74, 0.76, 0.80),
		"light_energy": 0.34, "finish": "metal" },
	{ "label": "jazoone", "path": "res://assets/jazoone_spaceship/spaceship.glb",
		"yaw": 0.0, "kind": "jazoone",
		"accent": Color(0.90, 0.93, 1.00), "swatch": Color(0.82, 0.84, 0.88),
		"light_energy": 0.36, "finish": "metal" },
	{ "label": "wedge", "path": "res://assets/wedge_fighter/wedge_fighter.glb",
		"yaw": 180.0, "kind": "wedge", "accent": Color(0.16, 0.70, 1.0),
		"swatch": Color(0.8, 0.85, 0.9), "light_energy": 0.35, "finish": "metal" },
]

# power, surge - the two values Ship._update_authored_propulsion feeds the shaders.
# The three states worth looking at, in Ship._propulsion_power terms:
#   rest    engines lit but idle
#   cruise  ordinary sublight flight with no Shift - 550 / (SUBLIGHT_MAX * BOOST_MULT)
#   boost   Shift held; Ship clamps _propulsion_power up to 0.82
const SHOTS := [
	{ "label": "rest", "power": 0.0, "surge": 0.0 },
	{ "label": "cruise", "power": 0.33, "surge": 0.0 },
	{ "label": "boost", "power": 0.82, "surge": 0.30 },
]

var _camera: Camera3D
var _out_dir := "/tmp/thruster_shots"
# DETAIL=1 renders a tight, heavily under-exposed close-up on one nozzle instead of the
# whole-ship sheet. At game exposure the plume core clips to flat white, so the shock
# train and filament structure are only inspectable with the exposure pulled down.
var _detail := false
var _isolate := ""
var _env: Environment
# VIEW=chase reproduces the ACTUAL in-game framing (Ship._update_camera): the camera
# sits CAM_OFFSET hull-lengths behind/above the hull and looks straight down the ship's
# forward axis, so the plumes point at the lens. The default 3/4 side view flatters the
# thruster; "too bright" is a complaint about the chase view, so tune against this one.
var _view := ""
# Mirrors of Ship's camera constants, overridable per run so a candidate rig can be
# photographed without editing ship.gd first.
var _cam_back := 2.6      # CAM_OFFSET.z, in hull lengths
var _cam_up := 0.5        # CAM_OFFSET.y, in hull lengths
var _cam_pitch := 0.0     # CAM_VIEW_PITCH_DEG
var _cam_fov := 70.0      # FOV_BASE
# Brightness sweep. TORCH_GAIN scales the torch cones' `brightness`, PROP_GAIN the
# authored propulsion / JazOone hull discs. Lets a candidate exposure be photographed
# without editing the shaders, so the shipped constants are picked from measurements.
var _torch_gain := 1.0
var _prop_gain := 1.0
# Glow chain overrides. The HALO RADIUS around a hot pixel is set here, not by the
# shader: level 5 is a 1/32-resolution blur, so whatever weight it carries is painted
# over an enormous area. GLOW_L* are the per-level weights, GLOW_THRESHOLD the HDR
# value a pixel must exceed to bloom at all.
var _glow := {1: 0.8, 2: 0.4, 3: 0.15, 4: 0.0, 5: 0.0}
var _glow_on := false   # matches main.gd; GLOW_ON=1 to compare against glow enabled
var _glow_threshold := 1.0
var _glow_intensity := 0.9
var _glow_strength := 0.85
var _glow_bloom := 0.05


func _ready() -> void:
	var env_dir := OS.get_environment("SHOT_DIR")
	if env_dir != "":
		_out_dir = env_dir
	_detail = OS.get_environment("DETAIL") == "1"
	# ISOLATE=no_rig|no_plumes|hull_only hides layers so an unexplained bright shape
	# can be attributed to the layer that actually draws it.
	_isolate = OS.get_environment("ISOLATE")
	_view = OS.get_environment("VIEW")
	_cam_back = _envf("CAM_BACK", _cam_back)
	_cam_up = _envf("CAM_UP", _cam_up)
	_cam_pitch = _envf("CAM_PITCH", _cam_pitch)
	_cam_fov = _envf("CAM_FOV", _cam_fov)
	_torch_gain = _envf("TORCH_GAIN", _torch_gain)
	_prop_gain = _envf("PROP_GAIN", _prop_gain)
	for lvl in _glow.keys():
		_glow[lvl] = _envf("GLOW_L%d" % lvl, _glow[lvl])
	_glow_threshold = _envf("GLOW_THRESHOLD", _glow_threshold)
	_glow_intensity = _envf("GLOW_INTENSITY", _glow_intensity)
	_glow_strength = _envf("GLOW_STRENGTH", _glow_strength)
	_glow_bloom = _envf("GLOW_BLOOM", _glow_bloom)
	DirAccess.make_dir_recursive_absolute(_out_dir)
	get_window().size = Vector2i(960, 540)
	_build_environment()
	_build_starfield()
	_build_scene_lights()
	_camera = Camera3D.new()
	_camera.far = 4000.0
	add_child(_camera)
	call_deferred("_run")


func _envf(key: String, fallback: float) -> float:
	var raw := OS.get_environment(key)
	return float(raw) if raw != "" else fallback


func _build_environment() -> void:
	# Copied from main.gd so the sheet shows the same glow/tonemap the game uses.
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.01, 0.01, 0.03)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.22, 0.25, 0.34)
	env.ambient_light_energy = 0.2
	env.glow_enabled = OS.get_environment("GLOW_ON") == "1" or _glow_on
	env.glow_normalized = true
	env.glow_hdr_threshold = _glow_threshold
	env.glow_intensity = _glow_intensity
	env.glow_strength = _glow_strength
	env.glow_bloom = _glow_bloom
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	for lvl in _glow.keys():
		env.set_glow_level(int(lvl), float(_glow[lvl]))
	print("render: glow levels %s threshold %.2f intensity %.2f strength %.2f bloom %.2f"
		% [_glow, _glow_threshold, _glow_intensity, _glow_strength, _glow_bloom])
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


# main.gd puts a DirectionalLight3D sun (energy 1.05) and a cool counter-fill (0.35) in
# the scene. This harness had NEITHER for its whole life, which is why its output stopped
# matching the game: in-game the hull is lit, its specular can cross the glow threshold
# on its own, and the plume is judged against a lit hull rather than a black one. SUN_YAW
# rotates the key so a given ship can be checked with the light behind or beside it.
func _build_scene_lights() -> void:
	var yaw := deg_to_rad(_envf("SUN_YAW", -55.0))
	var pitch := deg_to_rad(_envf("SUN_PITCH", -22.0))
	var dir := (Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, pitch)) * Vector3.FORWARD

	var sun := DirectionalLight3D.new()
	sun.light_energy = 1.05
	sun.light_color = Color(1.0, 0.96, 0.88)
	sun.shadow_enabled = false
	add_child(sun)
	sun.look_at(dir, Vector3.UP)

	var fill := DirectionalLight3D.new()
	fill.light_energy = 0.35
	fill.light_color = Color(0.6, 0.72, 1.0)
	fill.shadow_enabled = false
	add_child(fill)
	fill.look_at(-dir + Vector3(0.0, -0.6, 0.0), Vector3.UP)
	print("render: scene lights sun 1.05 + fill 0.35, sun_yaw %.0f pitch %.0f"
		% [rad_to_deg(yaw), rad_to_deg(pitch)])


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
		if OS.get_environment("SHIP") != "" and OS.get_environment("SHIP") != ship.label:
			continue
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
		"wedge": driven.append_array(WedgeDesign.style(model))
	holder.add_child(model)
	model.rotation = Vector3(0.0, deg_to_rad(float(ship.yaw)), 0.0)
	# Ship._build_ship_model lights the hull off the AABB fit_model RETURNS - the hull
	# alone. This harness used to call combined_aabb AFTER building the plumes, so the
	# key/fill/core reach was computed from a box several times too big.
	var hull_box := ShipMesh.fit_model(holder, model, 4.0)

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
	if ship.kind != "wedge":
		ShipMesh.color_authored_ship(model, ship.swatch, String(ship.finish))
	# Ship._build_ship_model no longer adds ANY ship-attached lights - the scene sun +
	# fill light the hull. Adding them here would put this harness back out of step
	# with the game, which is the mistake that made its earlier output worthless.
	var _unused_box := hull_box

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
	_camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	_camera.fov = 75.0
	if _view == "chase":
		# hull_len is the fit_model target below, not `reach` (which includes the plumes).
		var hull_len := 4.0
		var chase := Basis(Vector3.RIGHT, deg_to_rad(_cam_pitch))
		_camera.fov = _cam_fov
		_camera.global_transform = Transform3D(
			chase, chase * (Vector3(0.0, _cam_up, _cam_back) * hull_len))
		print("render: VIEW=chase fov=%.1f back=%.2f up=%.2f pitch=%.1f"
			% [_cam_fov, _cam_back, _cam_up, _cam_pitch])
	elif _view == "rear" and ship.kind == "class_ii":
		# Orthographic engine-centred comparison removes perspective as a variable.
		var sockets: Array = ShipMesh.CLASS_II_BOOSTER_SOCKETS
		var engine_centre := Vector3.ZERO
		for socket in sockets:
			engine_centre += model.to_global(socket.center)
		engine_centre /= float(sockets.size())
		_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		_camera.size = 2.4
		_camera.position = engine_centre + Vector3(0.0, 0.0, 6.0)
		_camera.look_at(engine_centre, Vector3.UP)
	elif _detail:
		# Frame the exhaust column itself, not the ship: push aft of the hull and
		# close in, so one plume spans the frame.
		var aft := centre + Vector3(0.0, 0.0, full.size.z * 0.42)
		_camera.position = aft + Vector3(1.0, 0.16, 0.10).normalized() * reach * 0.34
		_camera.look_at(aft, Vector3.UP)
	else:
		_camera.look_at(centre, Vector3.UP)
	if _torch_gain != 1.0 or _prop_gain != 1.0:
		for m in driven:
			var is_torch := m.shader == ShipMesh.CRUISER_TORCH_SHADER
			var b = m.get_shader_parameter("brightness")
			if b == null:
				continue
			m.set_shader_parameter("brightness",
				float(b) * (_torch_gain if is_torch else _prop_gain))
		print("render: gains torch=%.3f prop=%.3f" % [_torch_gain, _prop_gain])
	print("render: built %s  aabb=%s  lights=%d torches=%d driven=%d"
		% [ship.label, full.size, lights.size(), torches.size(), driven.size()])
	return { "model": holder, "torches": torches, "driven": driven, "lights": lights }


# Mirrors Ship._update_authored_propulsion so the sheet shows exactly what the game does.
func _apply_power(rig: Dictionary, p: float, surge: float) -> void:
	var heat := clampf(p * 1.12 + surge * 0.25, 0.0, 1.0)
	for m in rig.driven:
		m.set_shader_parameter("power", p * 0.75)   # Ship.POWER_CEIL
		m.set_shader_parameter("flow_speed", lerpf(0.8, 3.1, p))
		m.set_shader_parameter("temperature", heat)
	for m in rig.torches:
		m.set_shader_parameter("length_scale", lerpf(0.52, 1.30, p) + surge * 0.42)
		m.set_shader_parameter("flare_scale", lerpf(0.80, 1.06, p) + surge * 0.10)
		m.set_shader_parameter("turbulence", lerpf(0.55, 1.35, p))
	var lit := Color(1.0, 0.33, 0.06).lerp(Color(0.35, 0.70, 1.0), smoothstep(0.12, 0.78, heat))
	var share := sqrt(2.0 / maxf(float(rig.lights.size()), 1.0))
	for l in rig.lights:
		l.light_color = lit
		l.light_energy = (lerpf(0.015, 0.20, p) + surge * 0.09) * share
