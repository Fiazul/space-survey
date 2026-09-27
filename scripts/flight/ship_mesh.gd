class_name ShipMesh
extends RefCounted
# Stateless mesh / material / FX helpers for the player ship. Pulled out of ship.gd
# to keep that file focused on flight + state. Everything here is a static function
# that operates only on its arguments (no ship state), so it's safe to call from
# anywhere and easy to reason about.

const CRUISER_LED_SHADER := preload("res://shaders/cruiser_led.gdshader")
const CRUISER_PROPULSION_SHADER := preload("res://shaders/cruiser_propulsion.gdshader")
const CRUISER_TORCH_SHADER := preload("res://shaders/cruiser_torch.gdshader")
const EXHAUST_HAZE_SHADER := preload("res://shaders/exhaust_haze.gdshader")
# Tileable turbulence for every torch/haze layer, baked by tools/gen_exhaust_noise.py.
# Four independent channels (fine / coarse / warp / filament), so it must stay a
# lossless import - block compression would correlate them into mush.
const EXHAUST_NOISE := preload("res://assets/fx/exhaust_noise.png")

# --- THE booster brightness knob -------------------------------------------------
# Change this number, press F5, look at the ship. It is the single lever for how hot
# the exhaust reads, and it scales EVERY booster layer on every hull: the Nozzle_Emit
# propulsion pass and both torch cone layers (fog sheath + white core).
#
#   1.0 = as shipped   0.5 = half as hot   2.0 = twice as hot
#
# A static var rather than a const so a tool CAN sweep it in-process without editing
# this file - tools/test_booster_brightness.gd does exactly that, and restores it after.
# Nothing else assigns it today; render_thruster.gd has its own separate torch/prop
# sweep that applies on top. Read at BUILD time: the ship rebuilds on hangar change or
# restart, so F5 is the loop, not live in flight.
# KEEP THE DECIMAL POINT. `:= 20` infers an INT, and then every fractional value
# assigned to it truncates - 0.8 becomes 0, which silently kills the boosters.
static var booster_brightness := 2.0


# Every `brightness` handed to a booster shader goes through here. One place to look
# when a plume is the wrong intensity, and one place the knob has to apply.
static func booster_gain(base_gain: float) -> float:
	return base_gain * booster_brightness


# cruiser_propulsion.gdshader grades its energy against the same sockets that position
# the plumes, so the glow ends inside the housing instead of at the mesh boundary (see
# the shaping block in that shader for the measured reason). Must match the array size
# declared there.
const SHAPE_SOCKET_MAX := 8

const CLASS_II_BOOSTER_SOCKETS := [
	{ "center": Vector3(60.12385, 81.96715, -107.8570), "radius": 8.59805 },
	{ "center": Vector3(46.55385, 66.84465, -94.2746), "radius": 8.59805 },
	{ "center": Vector3(40.99215, 83.45400, -100.9570), "radius": 5.16870 },
	{ "center": Vector3(-21.43830, 81.96715, -107.8570), "radius": 8.59805 },
	{ "center": Vector3(-7.86826, 66.84465, -94.2746), "radius": 8.59805 },
	{ "center": Vector3(-2.30657, 83.45400, -100.9570), "radius": 5.16870 },
]

const CLASS_II_BOOSTER_GAIN := 3.8


# Hand a propulsion material the sockets its surface contains, in the SURFACE's own
# vertex space. `axis` is the local axis the exhaust runs along - model +/-Z for the
# authored hull surfaces, but +Y for _add_dense_booster_plug's own rotated cylinder.
static func _wire_nozzle_shape(material: ShaderMaterial, sockets: Array,
		to_local: Transform3D, axis: Vector3) -> void:
	var centres := PackedVector3Array()
	var radii := PackedFloat32Array()
	# A scaled mesh instance would otherwise get radii in the wrong space; the socket
	# constants are authored in model units. Uniform scale is assumed, as everywhere
	# else that converts through `world_scale`; non-uniform scale would need a radius
	# per axis, and no current asset has any.
	var scale: float = to_local.basis.get_scale().x
	for socket in sockets:
		if centres.size() >= SHAPE_SOCKET_MAX:
			break
		centres.append(to_local * (socket.center as Vector3))
		radii.append(float(socket.radius) * scale)
	# Pad to the declared array size. The shader only reads up to socket_count, but an
	# under-filled uniform array is left holding whatever the driver had there.
	while centres.size() < SHAPE_SOCKET_MAX:
		centres.append(Vector3.ZERO)
		radii.append(1.0)
	material.set_shader_parameter("socket_pos", centres)
	material.set_shader_parameter("socket_r", radii)
	material.set_shader_parameter("socket_count", mini(sockets.size(), SHAPE_SOCKET_MAX))
	# The AXIS needs converting too, not just the centres. JazOone's Layer_1 chunks sit
	# under a parent chain that both rotates and scales them (measured: socket radius
	# 0.81 -> 30.09, a factor of 36.96, with an axis swap), so model-space +Z is not
	# +Z in the chunk's vertex space. Passing the axis through unconverted graded the
	# discs along the wrong direction. Normalised because to_local carries the scale.
	material.set_shader_parameter("shape_axis", (to_local.basis * axis).normalized())


# Socket constants are authored in the MODEL's space. Every current ship loads as one
# MeshInstance3D so this is identity, but a nested asset would put the surface's vertex
# space somewhere else entirely and silently misplace every nozzle.
static func _model_to_surface_space(model: Node3D, mi: MeshInstance3D) -> Transform3D:
	var t := Transform3D.IDENTITY
	var node: Node = mi
	while node != null and node != model:
		if node is Node3D:
			t = (node as Node3D).transform * t
		node = node.get_parent()
	return t.affine_inverse()


# --- AABB / fitting --------------------------------------------------------

static func gather_mesh_instances(node: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	if node is MeshInstance3D:
		out.append(node as MeshInstance3D)
	for c in node.get_children():
		out.append_array(gather_mesh_instances(c))
	return out


# Union of child mesh bounds in root space. Authored FX can opt out with
# ship_bounds_exclude so throttle geometry never changes the fitted hull size.
static func combined_aabb(root: Node3D) -> AABB:
	var out := AABB()
	var first := true
	var inv := root.global_transform.affine_inverse()
	for mi in gather_mesh_instances(root):
		if mi.mesh == null or mi.get_meta("ship_bounds_exclude", false):
			continue
		var box := (inv * mi.global_transform) * mi.get_aabb()
		if first:
			out = box
			first = false
		else:
			out = out.merge(box)
	return out


# Scale `model` so its longest axis spans `target_len`, then recenter it. Measured in
# `mesh_root` space (the model's parent) so it accounts for the model's yaw/pitch.
static func fit_model(mesh_root: Node3D, model: Node3D, target_len: float) -> AABB:
	var box := combined_aabb(mesh_root)
	var size := box.size
	var longest := maxf(size.x, maxf(size.y, size.z))
	if longest <= 0.0001:
		return AABB(Vector3(-1, -1, -1), Vector3(2, 2, 2))
	var factor := target_len / longest
	model.scale = model.scale * factor
	var center := box.position + size * 0.5
	model.position -= center * factor
	return AABB(-size * factor * 0.5, size * factor)


static func style_class_ii_cruiser(model: Node3D) -> Array[ShaderMaterial]:
	var propulsion_materials: Array[ShaderMaterial] = []
	var ordinal := 0
	for mi in gather_mesh_instances(model):
		if mi.mesh == null:
			continue
		_prepare_legacy_obj(mi)
		for si in mi.mesh.get_surface_count():
			var orig := mi.get_active_material(si)
			var tag: String = mi.mesh.surface_get_name(si).to_lower()
			if orig != null:
				tag += " " + orig.resource_name.to_lower()
			var source_texture: Texture2D = null
			if orig is BaseMaterial3D:
				source_texture = (orig as BaseMaterial3D).albedo_texture
			if tag.contains("a1window") or ordinal == 1:
				var led := ShaderMaterial.new()
				led.shader = CRUISER_LED_SHADER
				if source_texture == null:
					source_texture = load("res://assets/class_ii_galactic_cruiser/Maps/wns1c.jpg") as Texture2D
				led.set_shader_parameter("led_mask", source_texture)
				mi.set_surface_override_material(si, led)
			elif tag.contains("propulsion") or ordinal == 2:
				var propulsion := ShaderMaterial.new()
				propulsion.shader = CRUISER_PROPULSION_SHADER
				propulsion.set_shader_parameter("plasma_color", Color.WHITE)
				propulsion.set_shader_parameter("brightness", booster_gain(CLASS_II_BOOSTER_GAIN))
				propulsion.set_shader_parameter("mirror_flow", true)
				propulsion.set_shader_parameter("symmetry_center_x", 19.342775)
				_wire_nozzle_shape(propulsion, CLASS_II_BOOSTER_SOCKETS,
					_model_to_surface_space(model, mi), Vector3(0.0, 0.0, 1.0))
				mi.set_surface_override_material(si, propulsion)
				propulsion_materials.append(propulsion)
			elif tag.contains("eng_covers") or tag.contains("eng covers") or ordinal == 4:
				var cover := StandardMaterial3D.new()
				cover.cull_mode = BaseMaterial3D.CULL_DISABLED
				cover.albedo_color = Color(0.10, 0.22, 0.34)
				cover.metallic = 0.82
				cover.metallic_specular = 0.88
				cover.roughness = 0.20
				cover.rim_enabled = true
				cover.rim = 0.28
				cover.rim_tint = 0.30
				cover.emission_enabled = true
				cover.emission = Color(0.025, 0.09, 0.16)
				cover.emission_energy_multiplier = 0.35
				mi.set_surface_override_material(si, cover)
			elif tag.contains("ship_body") or tag.contains("ship body") or ordinal == 3:
				var hull := StandardMaterial3D.new()
				hull.cull_mode = BaseMaterial3D.CULL_DISABLED
				hull.albedo_texture = source_texture
				hull.albedo_color = Color(0.92, 0.95, 1.0)
				hull.metallic = 0.42
				hull.metallic_specular = 0.72
				hull.roughness = 0.34
				hull.rim_enabled = true
				hull.rim = 0.16
				hull.rim_tint = 0.42
				mi.set_surface_override_material(si, hull)
			else:
				var glass := StandardMaterial3D.new()
				glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				glass.cull_mode = BaseMaterial3D.CULL_DISABLED
				glass.albedo_color = Color(0.12, 0.32, 0.48, 0.24)
				glass.metallic = 0.0
				glass.metallic_specular = 0.95
				glass.roughness = 0.035
				glass.rim_enabled = true
				glass.rim = 0.52
				glass.rim_tint = 0.18
				mi.set_surface_override_material(si, glass)
			ordinal += 1
	return propulsion_materials


static func add_class_ii_booster_plumes(model: Node3D,
		accent := Color(0.38, 0.72, 1.0)) -> Array[ShaderMaterial]:
	var propulsion_materials: Array[ShaderMaterial] = []
	var plume_root := Node3D.new()
	plume_root.name = "ClassIIAuthoredBoosterPlumes"
	model.add_child(plume_root)
	var world_scale: float = model.scale.x
	for i in CLASS_II_BOOSTER_SOCKETS.size():
		var socket: Dictionary = CLASS_II_BOOSTER_SOCKETS[i]
		var center: Vector3 = socket.center
		var radius: float = float(socket.radius)
		propulsion_materials.append(_add_torch_layer(
			plume_root, "BoosterFog%02d" % (i + 1), center, radius,
			radius * 6.0, 0.666667, 0.10, 1.20, 0.55, 0.42, false, -1.0, world_scale))
		propulsion_materials.append(_add_torch_layer(
			plume_root, "BoosterCore%02d" % (i + 1), center, radius,
			radius * 3.6, 0.58, 0.05, 3.20, 0.82, 0.995, true, -1.0, world_scale))
	_attach_socket_extras(model, CLASS_II_BOOSTER_SOCKETS, -1.0, world_scale, accent)
	return propulsion_materials


static func color_authored_ship(model: Node3D, tint: Color, finish: String) -> int:
	var colored := 0
	for mi in gather_mesh_instances(model):
		if mi.mesh == null:
			continue
		for si in mi.mesh.get_surface_count():
			var active := mi.get_active_material(si)
			if active is ShaderMaterial:
				var shader_material := active as ShaderMaterial
				if shader_material.shader == CRUISER_PROPULSION_SHADER:
					continue
				if shader_material.shader == CRUISER_LED_SHADER:
					shader_material.set_shader_parameter("color_tint", tint)
					colored += 1
				continue
			var material: BaseMaterial3D
			if active is BaseMaterial3D:
				material = (active as BaseMaterial3D).duplicate() as BaseMaterial3D
			else:
				material = StandardMaterial3D.new()
			material.resource_name = "customized_hull"
			var authored_alpha := material.albedo_color.a
			var authored_glass := material.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED
			material.albedo_color = Color(tint.r, tint.g, tint.b,
				authored_alpha if authored_glass else 1.0)
			material.emission_enabled = false
			if finish == "glassy":
				material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				material.cull_mode = BaseMaterial3D.CULL_DISABLED
				material.albedo_color.a = 0.38
				material.metallic = 0.0
				material.metallic_specular = 1.0
				material.roughness = 0.03
				material.clearcoat_enabled = true
				material.clearcoat = 1.0
				material.clearcoat_roughness = 0.02
				material.rim_enabled = true
				material.rim = 0.6
				material.rim_tint = 0.2
			elif authored_glass:
				material.metallic = 0.0
				material.metallic_specular = 1.0
				material.roughness = 0.03
				material.rim_enabled = true
				material.rim = 0.52
			else:
				material.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
				material.metallic = 0.58
				material.metallic_specular = 0.9
				material.roughness = 0.16
				material.clearcoat_enabled = false
				material.rim_enabled = true
				material.rim = 0.24
				material.rim_tint = 0.35
			mi.set_surface_override_material(si, material)
			colored += 1
	return colored


static func _prepare_legacy_obj(mi: MeshInstance3D) -> void:
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if mi.mesh is ArrayMesh:
		var visual_mesh := mi.mesh.duplicate() as ArrayMesh
		visual_mesh.shadow_mesh = null
		mi.mesh = visual_mesh


# `facing` is the model-space axis the exhaust travels along (+1.0 for the modular
# hulls, whose booster sockets exhaust along +Z). `world_scale` is the fit_model factor, needed
# because the shader's depth fade is compared against view-space (world) depth while
# this mesh is authored in model space.
static func _add_torch_layer(parent: Node3D, layer_name: String,
		center: Vector3, socket_radius: float, length: float, base_ratio: float,
		tip_ratio: float, brightness: float, opacity: float,
		white_mix: float, core_layer := false, facing := -1.0,
		world_scale := 1.0) -> ShaderMaterial:
	var cone := CylinderMesh.new()
	cone.height = length
	# A broad, faint sheath supplies local cyan glow without scene-wide bloom.
	if not core_layer:
		base_ratio *= 1.5
		tip_ratio *= 1.8
		brightness *= 0.45
		white_mix = 0.12
	cone.bottom_radius = socket_radius * base_ratio
	cone.top_radius = socket_radius * tip_ratio
	cone.radial_segments = 40
	cone.rings = 20
	cone.cap_bottom = false
	cone.cap_top = false

	var material := ShaderMaterial.new()
	material.shader = CRUISER_TORCH_SHADER
	material.set_shader_parameter("noise_tex", EXHAUST_NOISE)
	material.set_shader_parameter("shock_strength", 2.6 if core_layer else 0.0)
	material.set_shader_parameter("edge_color", Color(0.28, 0.70, 1.0))
	material.set_shader_parameter("brightness", booster_gain(brightness))
	material.set_shader_parameter("opacity", opacity)
	material.set_shader_parameter("white_mix", white_mix)
	material.set_shader_parameter("plume_length", length)
	material.set_shader_parameter("base_radius", socket_radius * base_ratio)
	material.set_shader_parameter("tip_radius", socket_radius * tip_ratio)
	material.set_shader_parameter("cool_color", Color(0.10, 0.38, 1.0))
	material.set_shader_parameter("temperature", 1.0)
	material.set_shader_parameter("turbulence", 1.0)
	material.set_shader_parameter("length_scale", 1.0)
	material.set_shader_parameter("flare_scale", 1.0)
	# Pin the width at the ROOT to the authored radius, fleet-wide. Without this the
	# turbulence billow swells the mouth of the cone, so the plume visibly overhangs
	# the nozzle it is supposed to be coming out of.
	material.set_shader_parameter("lock_nozzle_width", true)
	material.set_shader_parameter("depth_fade",
		socket_radius * base_ratio * world_scale * 0.85)

	var plume := MeshInstance3D.new()
	plume.name = layer_name
	plume.mesh = cone
	plume.material_override = material
	plume.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Cylinder +Y becomes local -Z (or +Z when facing is +1). Its base end sits
	# exactly behind the authored patch while the narrow tip extends away from the ship.
	plume.rotation = Vector3(deg_to_rad(90.0 * facing), 0.0, 0.0)
	# Seat the cone slightly INSIDE the nozzle, by a fraction of the nozzle itself.
	# An absolute offset shoves small-socket hulls' plumes out of their housing and
	# reads as a glow floating off the hull rather than something leaving the engine,
	# so this stays radius-relative instead.
	var seat: float = -socket_radius * 0.12
	plume.position = center + Vector3(0.0, 0.0, facing * (length * 0.5 + seat))
	# The vertex stage stretches this mesh up to length_scale past its authored AABB.
	# Without a cull margin Godot culls the whole plume the moment the un-stretched
	# box leaves the frustum, which pops the engines off at high throttle.
	plume.extra_cull_margin = minf(length * 1.5, 16384.0)
	parent.add_child(plume)
	return material


# Everything that hangs off a booster socket besides the torch cones themselves:
# a short-range nozzle light and a screen-space heat-haze shell.
# Called by ModularHull.add_plumes for every booster socket.
#
# These deliberately live in their OWN root rather than alongside the torch cones.
# The plume root is a checked contract - "N sockets produce exactly 2N
# CylinderMesh children" - and mixing lights and particles into them would break that
# for no benefit.
static func _attach_socket_extras(model: Node3D, sockets: Array, facing: float,
		world_scale: float, accent: Color) -> Node3D:
	var rig := Node3D.new()
	rig.name = "BoosterNozzleRig"
	model.add_child(rig)
	for i in sockets.size():
		var socket: Dictionary = sockets[i]
		var center: Vector3 = socket.center
		var radius: float = float(socket.radius)
		# NO nozzle light. Removed on request after it was measured, on the REAL ship
		# via tools/probe_live_scene.gd, as the whole blowout: hiding just these six
		# OmniLights took a frame's clipped-pixel count from 1717 to 192, while hiding
		# the heat haze moved it to 1645 and hiding the plume cones to 1677. Dropping
		# specular to 0 only got it to 885. _add_nozzle_light is kept below, unused, so
		# the reasoning survives; call it again only with a live-probe frame to show it.
		_add_heat_haze(rig, "BoosterHaze%02d" % (i + 1), center, radius,
			radius * 7.5, facing, world_scale)
	return rig


# The torch is emissive geometry, so by itself it cannot put a single photon on the
# hull. This is what actually makes the tail glow when the engines light up. Range is
# a few socket radii on purpose: a wide nozzle light bleaches the whole ship.
static func _add_nozzle_light(parent: Node3D, light_name: String, center: Vector3,
		socket_radius: float, facing: float, accent: Color,
		world_scale := 1.0) -> OmniLight3D:
	var light := OmniLight3D.new()
	light.name = light_name
	# Sit it just outside the nozzle plane so it rakes the hull around the engine
	# instead of being buried inside the housing.
	light.position = center + Vector3(0.0, 0.0, facing * socket_radius * 0.9)
	light.light_color = accent
	light.light_energy = 0.0        # ship.gd drives this from live throttle
	# `socket_radius` is in raw MODEL units, and omni_range is a plain distance - the
	# one number here that is NOT implicitly in the mesh's own space. Unconverted it
	# reaches hundreds of hull lengths out into the solar system and lights planets,
	# station props and the star shell. tools/probe_live_scene.gd prints these next to
	# the hull key light (range 0.9) if you need to see it again.
	#
	# _add_heat_haze below already converts its depth fade through `world_scale`; this
	# is the same conversion, and it was simply missing. Range now lands near the hull
	# lights' 0.48-0.9, which is what "a few socket radii" was always meant to mean.
	#
	# Separately measured: at the old range 7.0 / attenuation 1.6 these were the ENTIRE
	# blowout on the hulls tested - hiding the nozzle rig in the chase view dropped p99
	# luminance by 4-9x while the torch and propulsion shaders, zeroed, changed nothing.
	# 12x the socket radius, in WORLD units: enough to rake the aft third of the hull
	# and nothing beyond the ship.
	light.omni_range = socket_radius * 12.0 * world_scale
	light.omni_attenuation = 2.2
	# THE reason the engines blew out in-game while the offscreen harness looked fine.
	# These sit ~3 m off a polished metallic hull, and light_specular defaults to 1.0:
	# six point lights at point-blank range on low-roughness metal give six specular
	# hotspots that clip long before the diffuse term is anywhere near 1.0. Measured on
	# the REAL ship via tools/probe_live_scene.gd - hiding just these six lights took
	# the frame's clipped-pixel count from 1717 to 192, while hiding the heat haze
	# changed it to 1645 and hiding the plumes to 1677. This is a glow spill in the
	# engine bay, not a highlight source, so it has no business writing specular.
	light.light_specular = 0.0
	light.shadow_enabled = false
	parent.add_child(light)
	return light


# Refraction shell wrapped around the plume. render_priority keeps it BEFORE the
# torch in the transparent pass: it composites the refracted opaque frame with
# blend_mix, so drawing it after the additive plume would paint background over the
# flame and punch a hole straight through it.
static func _add_heat_haze(parent: Node3D, layer_name: String, center: Vector3,
		socket_radius: float, length: float, facing: float,
		world_scale: float) -> ShaderMaterial:
	var shell := CylinderMesh.new()
	shell.height = length
	shell.bottom_radius = socket_radius * 1.95
	shell.top_radius = socket_radius * 0.70
	shell.radial_segments = 24
	shell.rings = 6
	shell.cap_bottom = false
	shell.cap_top = false

	var material := ShaderMaterial.new()
	material.shader = EXHAUST_HAZE_SHADER
	material.set_shader_parameter("noise_tex", EXHAUST_NOISE)
	material.set_shader_parameter("plume_length", length)
	material.set_shader_parameter("strength", 0.016)
	material.set_shader_parameter("depth_fade", socket_radius * world_scale * 1.2)
	material.render_priority = -1

	var haze := MeshInstance3D.new()
	haze.name = layer_name
	haze.mesh = shell
	haze.material_override = material
	haze.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	haze.rotation = Vector3(deg_to_rad(90.0 * facing), 0.0, 0.0)
	haze.position = center + Vector3(0.0, 0.0, facing * (length * 0.5 + 0.10))
	parent.add_child(haze)
	return material


# NO ember particle layer. A GPUParticles3D spark stream was built here and then
# removed: with it in the scene the hull region washed out warm (a 960x540 frame went
# from 0.2% to 12.7% bright pixels), and shrinking the sparks ~8000x by converting
# their scale from model to world units barely moved that (12.0% -> 10.3%), so the
# cause is the emitter's presence, not the quad size. Not shipping a layer that
# degrades the image for a reason that is not understood. If you retry this, verify
# with tools/render_thruster.tscn ISOLATE=no_embers before keeping it.


# Nozzle lights are created inside the per-ship plume builders (they need the socket
# table), but ship.gd has to drive their energy every frame. Collect them by name so
# the plume builders can keep returning a plain Array[ShaderMaterial].
static func collect_nozzle_lights(model: Node3D) -> Array[OmniLight3D]:
	var out: Array[OmniLight3D] = []
	_collect_nozzle_lights(model, out)
	return out


static func _collect_nozzle_lights(node: Node, out: Array[OmniLight3D]) -> void:
	if node is OmniLight3D and String(node.name).begins_with("BoosterLight"):
		out.append(node as OmniLight3D)
	for c in node.get_children():
		_collect_nozzle_lights(c, out)


# Same idea for the refraction shells: ship.gd drives their power/flow_speed, but they
# must not inflate the plume builders' returned material count.
static func collect_haze_materials(model: Node3D) -> Array[ShaderMaterial]:
	var out: Array[ShaderMaterial] = []
	_collect_haze_materials(model, out)
	return out


static func _collect_haze_materials(node: Node, out: Array[ShaderMaterial]) -> void:
	if node is MeshInstance3D and String(node.name).begins_with("BoosterHaze"):
		var mat := (node as MeshInstance3D).material_override as ShaderMaterial
		if mat != null:
			out.append(mat)
	for c in node.get_children():
		_collect_haze_materials(c, out)


# Visual layer the hull is tagged with so ONE light can be aimed at the ship and
# nothing else. Everything in the game otherwise sits on layer 1, so a light whose
# cull mask is only this bit touches the ship and neither the planets, the station,
# nor the props. See Ship.HULL_FILL_* for the light that uses it.
const SHIP_FILL_LAYER := 2   # bit 2 (value 2), layer 1 stays set so the sun still lights us


# OR the ship-fill layer onto every piece of geometry under `model`, so the chase
# fill light can find the hull. Additive/unshaded plume layers are tagged too, which
# is harmless - they skip lighting entirely - and keeps the walk dumb and total.
static func tag_fill_layer(model: Node) -> int:
	var tagged := 0
	if model is VisualInstance3D:
		var vi := model as VisualInstance3D
		vi.layers = vi.layers | SHIP_FILL_LAYER
		tagged += 1
	for child in model.get_children():
		tagged += tag_fill_layer(child)
	return tagged


# A small key + fill + core light rig parented to the hull (travels with the ship).
# The scene has no Light3D otherwise — these are what let the lit pink-crystal
# material (toon diffuse, rim aura, sharp low-poly highlights) actually show. Range
# is kept to a few hull-lengths so they light the ship, not the wider scene.
# `accent` tints the fill + core lights (HaniStar = pink). `energy` scales the whole
# rig — metallic hulls (Lyra) need it low or they blow out into a bloom blob.
static func add_hull_lights(parent: Node3D, box: AABB, accent := Color(1.0, 0.70, 0.84), energy := 1.0) -> void:
	var s := box.size
	var reach: float = maxf(s.length(), 0.3)
	# Key: warm near-white, up/front/right — carves the faceted highlights.
	var key := OmniLight3D.new()
	key.position = Vector3(reach * 0.9, reach * 1.1, reach * 0.9)
	key.light_color = Color(1.0, 0.90, 0.93)
	key.light_energy = 1.3 * energy
	key.omni_range = reach * 3.0
	key.shadow_enabled = false
	parent.add_child(key)
	# Fill: accent-tinted, down/back/left — lifts the shadow side.
	var fill := OmniLight3D.new()
	fill.position = Vector3(-reach * 0.9, -reach * 0.7, -reach * 0.9)
	fill.light_color = accent
	fill.light_energy = 0.8 * energy
	fill.omni_range = reach * 3.0
	fill.shadow_enabled = false
	parent.add_child(fill)
	# Core: a soft accent glow at the hull centre to fill recessed panels.
	var core := OmniLight3D.new()
	core.position = Vector3(0.0, reach * 0.05, 0.0)
	core.light_color = accent
	core.light_energy = 1.1 * energy
	core.omni_range = reach * 1.6
	core.shadow_enabled = false
	parent.add_child(core)
