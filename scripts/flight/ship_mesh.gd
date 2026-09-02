class_name ShipMesh
extends RefCounted
# Stateless mesh / material / FX helpers for the player ship. Pulled out of ship.gd
# to keep that file focused on flight + state. Everything here is a static function
# that operates only on its arguments (no ship state), so it's safe to call from
# anywhere and easy to reason about.

const CRUISER_LED_SHADER := preload("res://shaders/cruiser_led.gdshader")
const CRUISER_PROPULSION_SHADER := preload("res://shaders/cruiser_propulsion.gdshader")
const CRUISER_TORCH_SHADER := preload("res://shaders/cruiser_torch.gdshader")
const JAZOONE_HULL_BOOSTER_SHADER := preload("res://shaders/jazoone_hull_booster.gdshader")
const EXHAUST_HAZE_SHADER := preload("res://shaders/exhaust_haze.gdshader")
# Tileable turbulence for every torch/haze layer, baked by tools/gen_exhaust_noise.py.
# Four independent channels (fine / coarse / warp / filament), so it must stay a
# lossless import - block compression would correlate them into mush.
const EXHAUST_NOISE := preload("res://assets/fx/exhaust_noise.png")

# Exact centers and usable radii of the six disconnected patches in the Class II
# OBJ's authored `propulsion` object. These are asset sockets, not a random layout.
# Its nozzle planes face local -Z; the imported hull's 180-degree yaw then presents
# the exhaust correctly toward the chase camera behind the ship.
const CLASS_II_BOOSTER_SOCKETS := [
	{ "center": Vector3(60.12385, 81.96715, -107.8570), "radius": 8.59805 },
	{ "center": Vector3(46.55385, 66.84465, -94.2746), "radius": 8.59805 },
	{ "center": Vector3(40.99215, 83.45400, -100.9570), "radius": 5.16870 },
	{ "center": Vector3(-21.43830, 81.96715, -107.8570), "radius": 8.59805 },
	{ "center": Vector3(-7.86826, 66.84465, -94.2746), "radius": 8.59805 },
	{ "center": Vector3(-2.30657, 83.45400, -100.9570), "radius": 5.16870 },
]

# Exact rear centers of Snarkrans' authored .000 upper booster and the two circular
# sockets inside .005_...035. The source objects contain the housings, but their
# open centers need a luminous plug and exhaust volume to read as active engines.
const SNARKRANS_BOOSTER_SOCKETS := [
	{ "center": Vector3(0.0, 5.41215, -9.26658), "radius": 0.78 },
	{ "center": Vector3(-1.45544, 2.95375, -9.26658), "radius": 0.78 },
	{ "center": Vector3(1.45544, 2.95375, -9.26658), "radius": 0.78 },
]

# Rear faces of Dingo57's eight user-identified booster groups, in mesh space.
# 070/109 are the two halves of the center bell; the rest are separate nozzles.
const DINGO57_BOOSTER_SOCKETS := [
	{ "center": Vector3(2665.73732, 1136.39702, -5929.50100), "radius": 163.72170 },
	{ "center": Vector3(1846.15996, 1450.85740, -5644.81690), "radius": 106.41909 },
	{ "center": Vector3(1846.15996, 841.01493, -5644.81690), "radius": 106.41910 },
	{ "center": Vector3(907.14259, 1132.06181, -5929.50134), "radius": 131.95825 },
	{ "center": Vector3(1069.80060, 1137.55272, -5929.50100), "radius": 132.94885 },
	{ "center": Vector3(132.93594, 1448.01726, -5644.81720), "radius": 105.56892 },
	{ "center": Vector3(132.93594, 838.17486, -5644.81720), "radius": 105.56892 },
	{ "center": Vector3(-686.05422, 1132.02757, -5929.50135), "radius": 162.41372 },
]

# JazOone has no separate booster object - its engines exist only as emissive regions
# painted into spaceship_2.png. tools/probe_jazoone_sockets.gd gates every vertex on
# that mask (the same step(0.25) cut the hull shader uses) and clusters the survivors
# in 3D; these are the two clusters it finds. Mind the sign: this model imports with
# yaw 0, so its rear is +Z - the opposite of the other three ships.
# Mach-disk intensity on the inner core layers. The outer fog sheath passes 0.0.
const SHOCK_TRAIN := 2.6

const JAZOONE_BOOSTER_SOCKETS := [
	{ "center": Vector3(0.85526, -0.14978, 3.83112), "radius": 0.81380 },
	{ "center": Vector3(-1.19826, 0.69599, 3.69080), "radius": 0.82240 },
]

# --- AABB / fitting --------------------------------------------------------

static func gather_mesh_instances(node: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	if node is MeshInstance3D:
		out.append(node as MeshInstance3D)
	for c in node.get_children():
		out.append_array(gather_mesh_instances(c))
	return out


# Union of every child MeshInstance3D's AABB, expressed in `root`'s local space.
static func combined_aabb(root: Node3D) -> AABB:
	var out := AABB()
	var first := true
	var inv := root.global_transform.affine_inverse()
	for mi in gather_mesh_instances(root):
		if mi.mesh == null:
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



# Dedicated material pass for Herminio Nieves' Class II Galactic Cruiser. The OBJ
# imports as five material surfaces: cockpit glass, a1 window LEDs, propulsion,
# textured ship body, and engine covers. Matching by material/surface name keeps
# the treatment resilient; the ordinal checks cover importers that discard names.
# Returns the propulsion ShaderMaterials so ship.gd can drive them from live speed.
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
				propulsion.set_shader_parameter("brightness", 4.0)
				mi.set_surface_override_material(si, propulsion)
				propulsion_materials.append(propulsion)
			elif tag.contains("eng_covers") or tag.contains("eng covers") or ordinal == 4:
				var cover := StandardMaterial3D.new()
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


# Give every flat Class II propulsion patch a real, tapered exhaust volume. Two
# nested layers form each torch: a broad blue-white fog sheath and a shorter,
# near-solid white core. They are added after model fitting so their length does
# not shrink the hull, and both layers are returned for live throttle animation.
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
		# Outer haze: longer and wider, but dimmer and translucent at the edge.
		propulsion_materials.append(_add_torch_layer(
			plume_root, "BoosterFog%02d" % (i + 1), center, radius,
			radius * 9.5, 1.18, 0.18, 1.25, 0.55, 0.42, 0.0, -1.0, world_scale))
		propulsion_materials.append(_add_torch_layer(
			plume_root, "BoosterCore%02d" % (i + 1), center, radius,
			radius * 5.8, 0.58, 0.05, 3.40, 0.82, 0.995, SHOCK_TRAIN, -1.0, world_scale))
	_attach_socket_extras(model, CLASS_II_BOOSTER_SOCKETS, -1.0, world_scale, accent)
	return propulsion_materials


# `facing` is the model-space axis the exhaust travels along: -1.0 for the three
# yaw-180 ships, +1.0 for JazOone. `world_scale` is the fit_model factor, needed
# because the shader's depth fade is compared against view-space (world) depth while
# this mesh is authored in model space.
static func _add_torch_layer(parent: Node3D, layer_name: String,
		center: Vector3, socket_radius: float, length: float, base_ratio: float,
		tip_ratio: float, brightness: float, opacity: float,
		white_mix: float, shock_strength := 0.0, facing := -1.0,
		world_scale := 1.0) -> ShaderMaterial:
	var cone := CylinderMesh.new()
	cone.height = length
	cone.bottom_radius = socket_radius * base_ratio
	cone.top_radius = socket_radius * tip_ratio
	cone.radial_segments = 40
	cone.rings = 20
	cone.cap_bottom = false
	cone.cap_top = false

	var material := ShaderMaterial.new()
	material.shader = CRUISER_TORCH_SHADER
	material.set_shader_parameter("edge_color", Color(0.28, 0.70, 1.0))
	material.set_shader_parameter("brightness", brightness)
	material.set_shader_parameter("opacity", opacity)
	material.set_shader_parameter("white_mix", white_mix)
	material.set_shader_parameter("plume_length", length)
	material.set_shader_parameter("base_radius", socket_radius * base_ratio)
	material.set_shader_parameter("tip_radius", socket_radius * tip_ratio)
	material.set_shader_parameter("noise_tex", EXHAUST_NOISE)
	material.set_shader_parameter("cool_color", Color(1.0, 0.33, 0.06))
	# Only the tight inner core carries a shock train; a Mach disk in the outer fog
	# sheath would read as banding, not as a rocket.
	material.set_shader_parameter("shock_strength", shock_strength)
	material.set_shader_parameter("temperature", 1.0)
	material.set_shader_parameter("turbulence", 1.0)
	material.set_shader_parameter("length_scale", 1.0)
	material.set_shader_parameter("flare_scale", 1.0)
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
	plume.position = center + Vector3(0.0, 0.0, facing * (length * 0.5 + 0.12))
	# The vertex stage stretches this mesh up to length_scale past its authored AABB.
	# Without a cull margin Godot culls the whole plume the moment the un-stretched
	# box leaves the frustum, which pops the engines off at high throttle.
	plume.extra_cull_margin = minf(length * 1.5, 16384.0)
	parent.add_child(plume)
	return material


# Everything that hangs off a booster socket besides the torch cones themselves:
# a short-range nozzle light and a screen-space heat-haze shell.
# Called by all four per-ship plume builders so the ships cannot drift apart.
#
# These deliberately live in their OWN root rather than alongside the torch cones.
# The per-ship plume roots are a checked contract - "N sockets produce exactly 2N
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
		_add_nozzle_light(rig, "BoosterLight%02d" % (i + 1), center, radius, facing, accent)
		_add_heat_haze(rig, "BoosterHaze%02d" % (i + 1), center, radius,
			radius * 7.5, facing, world_scale)
	return rig


# The torch is emissive geometry, so by itself it cannot put a single photon on the
# hull. This is what actually makes the tail glow when the engines light up. Range is
# a few socket radii on purpose: a wide nozzle light bleaches the whole ship.
static func _add_nozzle_light(parent: Node3D, light_name: String, center: Vector3,
		socket_radius: float, facing: float, accent: Color) -> OmniLight3D:
	var light := OmniLight3D.new()
	light.name = light_name
	# Sit it just outside the nozzle plane so it rakes the hull around the engine
	# instead of being buried inside the housing.
	light.position = center + Vector3(0.0, 0.0, facing * socket_radius * 0.9)
	light.light_color = accent
	light.light_energy = 0.0        # ship.gd drives this from live throttle
	light.omni_range = socket_radius * 7.0
	light.omni_attenuation = 1.6
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


# Dedicated split for Snarkrans' ship. The four user-identified OBJ objects are
# assigned distinct booster materials, preserving them as independent Godot
# surfaces even though the supplied OBJ originally had no material library.
static func style_snarkrans_starship(model: Node3D) -> Array[ShaderMaterial]:
	var propulsion_materials: Array[ShaderMaterial] = []
	for mi in gather_mesh_instances(model):
		if mi.mesh == null:
			continue
		_prepare_legacy_obj(mi)
		for si in mi.mesh.get_surface_count():
			var orig := mi.get_active_material(si)
			var tag: String = mi.mesh.surface_get_name(si).to_lower()
			if orig != null:
				tag += " " + orig.resource_name.to_lower()
			if tag.contains("booster_tip") or tag.contains("booster_bottom") \
				or tag.contains("booster_upper_shell") or tag.contains("booster_lower_shell"):
				var propulsion := ShaderMaterial.new()
				propulsion.shader = CRUISER_PROPULSION_SHADER
				propulsion.set_shader_parameter("plasma_color", Color.WHITE)
				propulsion.set_shader_parameter("brightness", 4.0)
				mi.set_surface_override_material(si, propulsion)
				propulsion_materials.append(propulsion)
	return propulsion_materials


# Fill Snarkrans' three empty booster housings with a dense emissive plug, then
# attach the same fog-sheath + white-core torch used by the Class II cruiser.
# Socket coordinates come directly from the user-identified authored OBJ objects.
static func add_snarkrans_booster_plumes(model: Node3D,
		accent := Color(0.30, 0.62, 1.0)) -> Array[ShaderMaterial]:
	var propulsion_materials: Array[ShaderMaterial] = []
	var plume_root := Node3D.new()
	plume_root.name = "SnarkransAuthoredBoosterPlumes"
	model.add_child(plume_root)
	var world_scale: float = model.scale.x

	for i in SNARKRANS_BOOSTER_SOCKETS.size():
		var socket: Dictionary = SNARKRANS_BOOSTER_SOCKETS[i]
		var center: Vector3 = socket.center
		var radius: float = float(socket.radius)
		# First close the visibly empty center with a thick white-hot emitter face.
		propulsion_materials.append(_add_dense_booster_plug(
			plume_root, "BoosterFill%02d" % (i + 1), center, radius))
		propulsion_materials.append(_add_torch_layer(
			plume_root, "BoosterFog%02d" % (i + 1), center, radius,
			radius * 9.8, 1.22, 0.20, 1.30, 0.55, 0.42, 0.0, -1.0, world_scale))
		propulsion_materials.append(_add_torch_layer(
			plume_root, "BoosterCore%02d" % (i + 1), center, radius,
			radius * 6.0, 0.60, 0.05, 3.50, 0.82, 0.998, SHOCK_TRAIN, -1.0, world_scale))
	_attach_socket_extras(model, SNARKRANS_BOOSTER_SOCKETS, -1.0, world_scale, accent)
	return propulsion_materials


static func _add_dense_booster_plug(parent: Node3D, plug_name: String,
		center: Vector3, radius: float) -> ShaderMaterial:
	var plug_depth := radius * 0.24
	var plug_mesh := CylinderMesh.new()
	plug_mesh.height = plug_depth
	plug_mesh.bottom_radius = radius
	plug_mesh.top_radius = radius * 0.98
	plug_mesh.radial_segments = 40
	plug_mesh.rings = 1
	plug_mesh.cap_bottom = true
	plug_mesh.cap_top = true

	var material := ShaderMaterial.new()
	material.shader = CRUISER_PROPULSION_SHADER
	material.set_shader_parameter("plasma_color", Color.WHITE)
	material.set_shader_parameter("brightness", 4.0)

	var plug := MeshInstance3D.new()
	plug.name = plug_name
	plug.mesh = plug_mesh
	plug.material_override = material
	plug.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	plug.rotation = Vector3(deg_to_rad(-90.0), 0.0, 0.0)
	# Seat the inner cap on the authored rear plane and put its bright outer face
	# slightly behind the housing so the housing can still occlude the edges.
	plug.position = center + Vector3(0.0, 0.0, -plug_depth * 0.5 - 0.015)
	parent.add_child(plug)
	return material


static func add_dingo57_booster_plumes(model: Node3D,
		accent := Color(0.35, 0.68, 1.0)) -> Array[ShaderMaterial]:
	var propulsion_materials: Array[ShaderMaterial] = []
	var plume_root := Node3D.new()
	plume_root.name = "Dingo57AuthoredBoosterPlumes"
	model.add_child(plume_root)
	var world_scale: float = model.scale.x

	for i in DINGO57_BOOSTER_SOCKETS.size():
		var socket: Dictionary = DINGO57_BOOSTER_SOCKETS[i]
		var center: Vector3 = socket.center
		var radius: float = float(socket.radius)
		propulsion_materials.append(_add_torch_layer(
			plume_root, "BoosterFog%02d" % (i + 1), center, radius,
			radius * 9.2, 1.16, 0.18, 1.20, 0.55, 0.42, 0.0, -1.0, world_scale))
		propulsion_materials.append(_add_torch_layer(
			plume_root, "BoosterCore%02d" % (i + 1), center, radius,
			radius * 5.6, 0.56, 0.05, 3.20, 0.82, 0.995, SHOCK_TRAIN, -1.0, world_scale))
	_attach_socket_extras(model, DINGO57_BOOSTER_SOCKETS, -1.0, world_scale, accent)
	print("dingo57: attached %d torch layers + %d nozzle rigs on %d authored sockets" \
		% [propulsion_materials.size(), DINGO57_BOOSTER_SOCKETS.size(),
		DINGO57_BOOSTER_SOCKETS.size()])
	return propulsion_materials


# Dingo57's eight named booster groups were assigned unique materials during ingest,
# preserving them as independent surfaces. Their geometry stays untouched; only the
# surface becomes an extremely HDR-hot, fog-edged light source. Every other surface
# is forced opaque and double-sided so thin SketchUp chassis panels cannot vanish.
static func style_dingo57_starship(model: Node3D) -> Array[ShaderMaterial]:
	var propulsion_materials: Array[ShaderMaterial] = []
	for mi in gather_mesh_instances(model):
		if mi.mesh == null:
			continue
		_prepare_legacy_obj(mi)
		for si in mi.mesh.get_surface_count():
			var orig := mi.get_active_material(si)
			var tag: String = mi.mesh.surface_get_name(si).to_lower()
			if orig != null:
				tag += " " + orig.resource_name.to_lower()
			if tag.contains("booster_group_"):
				var propulsion := ShaderMaterial.new()
				propulsion.shader = CRUISER_PROPULSION_SHADER
				propulsion.set_shader_parameter("plasma_color", Color.WHITE)
				propulsion.set_shader_parameter("brightness", 4.0)
				mi.set_surface_override_material(si, propulsion)
				propulsion_materials.append(propulsion)
			else:
				mi.set_surface_override_material(si, _solid_dingo57_hull_material(orig))
	return propulsion_materials


static func _solid_dingo57_hull_material(source: Material) -> StandardMaterial3D:
	var hull: StandardMaterial3D
	if source is StandardMaterial3D:
		hull = (source as StandardMaterial3D).duplicate() as StandardMaterial3D
	else:
		hull = StandardMaterial3D.new()
	hull.resource_name = "dingo57_hull"
	hull.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
	hull.cull_mode = BaseMaterial3D.CULL_DISABLED
	hull.albedo_color.a = 1.0
	return hull


static func _is_solid_dingo57_hull(surface_tag: String) -> bool:
	return surface_tag == "hull_body" \
		or surface_tag.begins_with("hull_") \
		or surface_tag.begins_with("outer_chassis_group_") \
		or surface_tag.contains("dingo57_hull")


# JazOone SpaceShip: Sketchfab splits Layer_1 into five Layer_1_Material_0
# chunks of the whole hull. Keep the authored albedo on those chunks and put
# the existing HDR torch only on the two emissive engine discs.
static func style_jazoone_spaceship(model: Node3D) -> Array[ShaderMaterial]:
	var propulsion_materials: Array[ShaderMaterial] = []
	var albedo_tex := load("res://assets/jazoone_spaceship/spaceship_0.png") as Texture2D
	var orm_tex := load("res://assets/jazoone_spaceship/spaceship_1.png") as Texture2D
	var emissive_tex := load("res://assets/jazoone_spaceship/spaceship_2.png") as Texture2D
	var normal_tex := load("res://assets/jazoone_spaceship/spaceship_3.png") as Texture2D
	for mi in gather_mesh_instances(model):
		if mi.mesh == null:
			continue
		_prepare_legacy_obj(mi)
		var tag: String = mi.name.to_lower()
		tag += " " + String(mi.mesh.resource_name).to_lower()
		if not tag.contains("layer_1"):
			continue
		for si in mi.mesh.get_surface_count():
			var orig := mi.get_active_material(si)
			var hull := ShaderMaterial.new()
			hull.shader = JAZOONE_HULL_BOOSTER_SHADER
			if orig is BaseMaterial3D:
				var source := orig as BaseMaterial3D
				if source.albedo_texture != null:
					albedo_tex = source.albedo_texture
				if source.emission_texture != null:
					emissive_tex = source.emission_texture
				if source.metallic_texture != null:
					orm_tex = source.metallic_texture
				if source.normal_texture != null:
					normal_tex = source.normal_texture
			hull.set_shader_parameter("albedo_tex", albedo_tex)
			hull.set_shader_parameter("emissive_tex", emissive_tex)
			hull.set_shader_parameter("orm_tex", orm_tex)
			hull.set_shader_parameter("normal_tex", normal_tex)
			hull.set_shader_parameter("plasma_color", Color.WHITE)
			hull.set_shader_parameter("brightness", 4.0)
			mi.set_surface_override_material(si, hull)
			propulsion_materials.append(hull)
	print("jazoone: styled %d Layer_1 chunks with textured hull + two engine discs" \
		% propulsion_materials.size())
	return propulsion_materials


# JazOone shipped with no exhaust at all: its engines were two emissive texture discs
# and nothing more. Give them the same torch the other three ships get, seated on the
# sockets tools/probe_jazoone_sockets.gd recovered from the emissive mask.
# Plume proportions are scaled to this hull - it is a ~12-unit ship with 0.8-unit
# nozzles, so the Class II ratios would produce a flame two thirds the ship's length.
static func add_jazoone_booster_plumes(model: Node3D,
		accent := Color(0.32, 0.70, 1.0)) -> Array[ShaderMaterial]:
	var propulsion_materials: Array[ShaderMaterial] = []
	var plume_root := Node3D.new()
	plume_root.name = "JazOoneAuthoredBoosterPlumes"
	model.add_child(plume_root)
	var world_scale: float = model.scale.x

	for i in JAZOONE_BOOSTER_SOCKETS.size():
		var socket: Dictionary = JAZOONE_BOOSTER_SOCKETS[i]
		var center: Vector3 = socket.center
		var radius: float = float(socket.radius)
		propulsion_materials.append(_add_torch_layer(
			plume_root, "BoosterFog%02d" % (i + 1), center, radius,
			radius * 6.8, 1.10, 0.18, 1.22, 0.55, 0.42, 0.0, 1.0, world_scale))
		propulsion_materials.append(_add_torch_layer(
			plume_root, "BoosterCore%02d" % (i + 1), center, radius,
			radius * 4.2, 0.54, 0.05, 3.30, 0.82, 0.995, SHOCK_TRAIN, 1.0, world_scale))
	_attach_socket_extras(model, JAZOONE_BOOSTER_SOCKETS, 1.0, world_scale, accent)
	print("jazoone: attached %d torch layers + %d nozzle rigs on %d probed sockets" \
		% [propulsion_materials.size(), JAZOONE_BOOSTER_SOCKETS.size(),
		JAZOONE_BOOSTER_SOCKETS.size()])
	return propulsion_materials


# Apply the hangar colour to every authored surface except the exact propulsion
# shader surfaces. Shader identity is the exclusion boundary, so material names or
# import ordering cannot accidentally paint a booster. Class II's LED stays animated
# and receives a gentle tint through its own shader parameter.
static func color_authored_ship(model: Node3D, tint: Color, finish: String) -> int:
	var colored := 0
	for mi in gather_mesh_instances(model):
		if mi.mesh == null:
			continue
		for si in mi.mesh.get_surface_count():
			var active := mi.get_active_material(si)
			var surface_tag: String = mi.mesh.surface_get_name(si).to_lower()
			if active is ShaderMaterial:
				var shader_material := active as ShaderMaterial
				if shader_material.shader == CRUISER_PROPULSION_SHADER \
					or shader_material.shader == JAZOONE_HULL_BOOSTER_SHADER:
					continue
				if shader_material.shader == CRUISER_LED_SHADER:
					shader_material.set_shader_parameter("color_tint", tint)
					colored += 1
				continue

			var material: BaseMaterial3D
			var keep_solid := _is_solid_dingo57_hull(surface_tag) \
				or (active is BaseMaterial3D and (active as BaseMaterial3D).resource_name == "dingo57_hull")
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
				# Colour authored glass too, but do not turn a cockpit pane into metal.
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
			# Dingo57's hull is a thin one-sided SketchUp shell. Keep every non-booster
			# surface opaque and double-sided so backface culling or glassy finish
			# cannot hide chassis panels, including bottom groups 053/065/092/104.
			if keep_solid:
				material.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
				material.cull_mode = BaseMaterial3D.CULL_DISABLED
				material.albedo_color.a = 1.0
			mi.set_surface_override_material(si, material)
			colored += 1
	return colored


# Imported OBJ shadow meshes can contain geometry-only surfaces with null material
# RIDs. Duplicate per ship instance and remove that optional acceleration mesh before
# applying animated surface overrides; the visible source mesh remains unchanged.
static func _prepare_legacy_obj(mi: MeshInstance3D) -> void:
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if mi.mesh is ArrayMesh:
		var visual_mesh := mi.mesh.duplicate() as ArrayMesh
		visual_mesh.shadow_mesh = null
		mi.mesh = visual_mesh


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
