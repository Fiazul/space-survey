extends Node3D
# Run: xvfb-run -a <godot> --path . res://tools/probe_live_scene.tscn
#      (SHOT_DIR=/tmp/x  FRAMES=120  THROTTLE=1)
#
# Loads the REAL scenes/Main.tscn and reports what is actually in the running scene:
# every Light3D with its energy/range/position, and the WorldEnvironment settings that
# are actually in effect. Then saves a frame.
#
# Why this exists: tools/render_thruster.tscn rebuilds a ship the way Ship does and
# mirrors main.gd's environment BY HAND. That mirror silently drifted - it had no sun
# and no fill DirectionalLight for its whole life, and fed the hull lights a bounding
# box that included the plumes. Its output stopped matching the game and several rounds
# of exhaust tuning were done against the wrong picture. Anything the render harness
# claims about brightness should be confirmed here first.

var _frames := 45
var _out_dir := "/tmp/live_probe"
var _main: Node = null


func _env_or(key: String, fallback: String) -> String:
	var v := OS.get_environment(key)
	return v if v != "" else fallback


func _ready() -> void:
	var env_dir := OS.get_environment("SHOT_DIR")
	if env_dir != "":
		_out_dir = env_dir
	var f := OS.get_environment("FRAMES")
	if f != "":
		_frames = int(f)
	DirAccess.make_dir_recursive_absolute(_out_dir)
	var w := int(_env_or("WIDTH", "640"))
	get_window().size = Vector2i(w, int(w * 9.0 / 16.0))

	var packed := load("res://scenes/Main.tscn") as PackedScene
	if packed == null:
		print("live: FAILED to load res://scenes/Main.tscn")
		get_tree().quit(1)
		return
	_main = packed.instantiate()
	add_child(_main)
	call_deferred("_run")


func _run() -> void:
	# Let main.gd finish its own async setup (ephemeris, props, ship build).
	for i in _frames:
		await get_tree().process_frame

	if OS.get_environment("THROTTLE") == "1":
		_hold_throttle()
		var spool := int(_env_or("SPOOL", "180"))
		for i in spool:
			await get_tree().process_frame

	_report_lights()
	_report_environment()
	_report_ship()

	# Layer isolation ON THE REAL SHIP. This is the only attribution that counts: the
	# offscreen harness reproduces the ship but not the scene, and its verdicts have
	# been wrong twice. Each pass hides one group and re-photographs the same frame.
	await _shot("all")
	var ship: Variant = _main.get("ship")
	if ship != null:
		var mesh_root: Node = ship.get_node_or_null("Node3D")
		if mesh_root == null:
			for c in ship.get_children():
				if c is Node3D and c.get_child_count() > 0:
					mesh_root = c
					break
		if mesh_root != null:
			var plume_roots := []
			var rigs := []
			_collect_groups(mesh_root, plume_roots, rigs)
			print("live: found %d plume root(s), %d nozzle rig(s)"
				% [plume_roots.size(), rigs.size()])
			_set_visible(plume_roots, false)
			await _shot("no_plumes")
			_set_visible(plume_roots, true)
			_set_visible(rigs, false)
			await _shot("no_rig")
			_set_visible(plume_roots, false)
			await _shot("hull_only")
			_set_visible(plume_roots, true)
			_set_visible(rigs, true)
			# The rig holds two very different things. Split them: the OmniLights, and
			# the screen-space heat-haze shells.
			var nozzle_lights := []
			var hazes := []
			for rig in rigs:
				for child in (rig as Node3D).get_children():
					if child is Light3D:
						nozzle_lights.append(child)
					elif String(child.name).begins_with("BoosterHaze"):
						hazes.append(child)
			print("live: rig holds %d light(s), %d haze shell(s)"
				% [nozzle_lights.size(), hazes.size()])
			_set_visible(nozzle_lights, false)
			await _shot("no_lights")
			_set_visible(nozzle_lights, true)
			_set_visible(hazes, false)
			await _shot("no_haze")
			_set_visible(hazes, true)
	get_tree().quit(0)


func _collect_groups(node: Node, plume_roots: Array, rigs: Array) -> void:
	for child in node.get_children():
		var n := String(child.name)
		if n.ends_with("AuthoredBoosterPlumes") and child is Node3D:
			plume_roots.append(child)
		elif n == "BoosterNozzleRig" and child is Node3D:
			rigs.append(child)
		_collect_groups(child, plume_roots, rigs)


func _set_visible(nodes: Array, on: bool) -> void:
	for n in nodes:
		(n as Node3D).visible = on


func _shot(label: String) -> void:
	for i in 6:
		await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	var path := "%s/%s.png" % [_out_dir, label]
	img.save_png(path)
	print("live: %s" % path)


# Drive the exhaust through the REAL code path. Ship reads raw physical keys, which
# cannot be faked, but `auto_cruise` is the hands-free equivalent of holding W+Shift -
# it feeds both forward thrust and boost. Setting _propulsion_power directly does not
# work: fly() lerps it back toward its own target every frame, so the frame came out
# showing an idling ship.
func _hold_throttle() -> void:
	var ship: Variant = _main.get("ship")
	if ship == null:
		print("live: no ship to throttle")
		return
	ship.set("auto_cruise", true)
	print("live: auto_cruise on (= W + Shift held)")


func _report_lights() -> void:
	var rows := []
	_walk_lights(_main, rows)
	print("\nlive: %d Light3D in the running scene" % rows.size())
	for r in rows:
		print("   %-34s %-20s energy %6.3f  range %10.3f  vis %s  at %s"
			% [r.path, r.type, r.energy, r.range, r.visible, r.pos])
	var total := 0.0
	for r in rows:
		if r.visible:
			total += float(r.energy)
	print("   -> summed energy of VISIBLE lights: %.3f" % total)


func _walk_lights(node: Node, rows: Array) -> void:
	for child in node.get_children():
		if child is Light3D:
			var l := child as Light3D
			rows.append({
				"path": String(l.name),
				"type": l.get_class(),
				"energy": l.light_energy,
				"range": (l as OmniLight3D).omni_range if l is OmniLight3D else 0.0,
				"visible": l.visible,
				"pos": l.global_position,
			})
		_walk_lights(child, rows)


func _report_environment() -> void:
	var we: WorldEnvironment = null
	for child in _main.get_children():
		if child is WorldEnvironment:
			we = child
			break
	if we == null or we.environment == null:
		print("\nlive: NO WorldEnvironment found in the running scene")
		return
	var e := we.environment
	var levels := []
	for i in range(1, 7):
		levels.append("%d:%.2f" % [i, e.get_glow_level(i)])
	print("\nlive: environment actually in effect")
	print("   glow_enabled %s  normalized %s  intensity %.2f  strength %.2f  bloom %.2f  hdr_threshold %.2f"
		% [e.glow_enabled, e.glow_normalized, e.glow_intensity, e.glow_strength,
		e.glow_bloom, e.glow_hdr_threshold])
	print("   glow levels %s" % " ".join(levels))
	print("   tonemap mode %d exposure %.3f white %.3f"
		% [e.tonemap_mode, e.tonemap_exposure, e.tonemap_white])
	print("   ambient source %d color %s energy %.3f"
		% [e.ambient_light_source, e.ambient_light_color, e.ambient_light_energy])


func _report_ship() -> void:
	var ship: Variant = _main.get("ship")
	if ship == null:
		print("\nlive: no `ship` on Main")
		return
	print("\nlive: ship state")
	print("   _propulsion_power %.3f  is_boosting %s  velocity %.1f"
		% [ship.get("_propulsion_power"), ship.get("is_boosting"),
		(ship.get("velocity") as Vector3).length()])
	var torches: Array = ship.get("_torch_materials")
	if torches != null and not torches.is_empty():
		var m: ShaderMaterial = torches[0]
		print("   torch power %.4f  brightness %.3f  opacity %.3f  temperature %.3f"
			% [m.get_shader_parameter("power"), m.get_shader_parameter("brightness"),
			m.get_shader_parameter("opacity"), m.get_shader_parameter("temperature")])
	var lights: Array = ship.get("_nozzle_lights")
	if lights != null and not lights.is_empty():
		print("   %d nozzle lights, first energy %.4f range %.4f"
			% [lights.size(), (lights[0] as OmniLight3D).light_energy,
			(lights[0] as OmniLight3D).omni_range])
