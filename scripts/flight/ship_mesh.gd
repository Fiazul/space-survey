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
# Per-ship gain for the additive booster shader, compensating for how much of each hull
# it lights: gain = 4.0 * sqrt(class_ii_area / own_area), so a ship with ten times the
# emissive area does not come out ten times as washed, and ship size cancels because
# the areas are fractions of hull.
#
# These are derived from EFFECTIVE area now, not raw surface area, because
# cruiser_propulsion.gdshader grades its energy against the nozzle sockets and fades to
# zero before the mesh ends. tools/probe_propulsion_area.gd integrates that falloff over
# the triangles and prints the whole table:
#
#     ship        raw %   effective %   kept   gain
#     class_ii     0.64          0.68   108%   4.00  (anchor)
#     dingo57      4.30          0.50    12%   4.68
#     snarkrans    6.69          1.20    18%   3.02
#
# The housings and shells are what dropped out - snarkrans' upper/lower shells now
# integrate to 0.00% - so the old 1.6 and 1.3 were mostly compensating for area that is
# no longer lit at all. Deriving from raw area after the border landed would have
# over-compensated all over again in the opposite direction.
#
# What this costs: dingo57 and snarkrans now emit ~34% and ~42% of the total light they
# used to, which is the excess that came from lighting their housings. class_ii, the
# anchor, is unchanged at 106%.
const CLASS_II_BOOSTER_GAIN := 4.0
const DINGO57_BOOSTER_GAIN := 4.68
const SNARKRANS_BOOSTER_GAIN := 3.02
# JazOone's two engine discs are far larger relative to its hull than the other ships'
# booster patches (~10% of hull length in radius, each), so the energy that reads as a
# hot throat on them buries this ship in bloom. Measured in the chase view: at 4.0 the
# glow covered 44% of the frame at cruise and the hull was invisible; 0.40 leaves two
# hot bells and a hull.
#
# Unchanged by the border work, deliberately. This ship never had the housing problem
# the other three did: its emissive region IS the throat (measured 2.52% of the hull
# raw, 2.63% effective - it keeps 104% of its area, where dingo57 keeps 12%). So the
# socket falloff here redistributes the SAME total energy into a hot centre and a
# 50%-value rim instead of a flat disc, which is what this ship needed, and its total
# light does not move - no risk of re-running the blowout this number was measured
# against. Peak at full boost: 1.29 broad, 1.94 at the very centre.
const JAZOONE_BOOSTER_GAIN := 0.40

const JAZOONE_BOOSTER_SOCKETS := [
	{ "center": Vector3(0.85526, -0.14978, 3.83112), "radius": 0.81380 },
	{ "center": Vector3(-1.19826, 0.69599, 3.69080), "radius": 0.82240 },
]

# --- THE booster brightness knob -------------------------------------------------
# Change this number, press F5, look at the ship. It is the single lever for how hot
# the exhaust reads, and it scales EVERY booster layer on all four ships: the authored
# propulsion surfaces, both torch cone layers (fog sheath + white core), Snarkrans'
# nozzle plugs and JazOone's engine discs. The per-ship gains above are area
# compensation, not taste - leave them alone and turn this instead, so the fleet keeps
# its relative balance.
#
#   1.0 = as shipped   0.5 = half as hot   2.0 = twice as hot
#
# The last booster pass left the plume very subtle (with glow off it measures within
# 2 px of hiding it entirely), so up is the interesting direction. Watch for the ships
# with the widest emissive area - snarkrans and JazOone slab out first.
#
# A static var rather than a const so a tool CAN sweep it in-process without editing
# this file - tools/test_booster_brightness.gd does exactly that, and restores it after.
# Nothing else assigns it today; render_thruster.gd has its own separate torch/prop
# sweep that applies on top. Read at BUILD time: the ship rebuilds on hangar change or
# restart, so F5 is the loop, not live in flight.
# KEEP THE DECIMAL POINT. `:= 20` infers an INT, and then every fractional value
# assigned to it truncates - 0.8 becomes 0, which silently kills the boosters.
static var booster_brightness := 18.0


# Every `brightness` handed to a booster shader goes through here. One place to look
# when a plume is the wrong intensity, and one place the knob has to apply.
static func booster_gain(base_gain: float) -> float:
	return base_gain * booster_brightness


# cruiser_propulsion.gdshader grades its energy against the same sockets that position
# the plumes, so the glow ends inside the housing instead of at the mesh boundary (see
# the shaping block in that shader for the measured reason). Must match the array size
# declared there.
const SHAPE_SOCKET_MAX := 8


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
				# Brightness comes from the gain knob, not the old literal 4.0: the
				# per-ship gains are derived from effective emissive area.
				propulsion.set_shader_parameter("brightness",
					booster_gain(CLASS_II_BOOSTER_GAIN))
				# The two banks are mirrored, so the flow noise is folded about the
				# hull centre line to run outward on both sides. This folds the flow
				# varying only - see the merge note in cruiser_propulsion.gdshader.
				propulsion.set_shader_parameter("mirror_flow", true)
				propulsion.set_shader_parameter("symmetry_center_x", 19.342775)
				# All six patches live in this one surface, so the material carries all
				# six sockets and each fragment grades against its nearest.
				_wire_nozzle_shape(propulsion, CLASS_II_BOOSTER_SOCKETS,
					_model_to_surface_space(model, mi), Vector3(0.0, 0.0, 1.0))
				mi.set_surface_override_material(si, propulsion)
				propulsion_materials.append(propulsion)
			elif tag.contains("eng_covers") or tag.contains("eng covers") or ordinal == 4:
				var cover := StandardMaterial3D.new()
				# Mirrored OBJ shells have opposite winding on the two banks.
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
				# Keep both nozzle rims opaque: backface culling otherwise exposes
				# the full emitter disc through just one mirrored housing.
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
			radius * 9.5, 1.18, 0.18, 1.25, 0.55, 0.42, false, -1.0, world_scale))
		propulsion_materials.append(_add_torch_layer(
			plume_root, "BoosterCore%02d" % (i + 1), center, radius,
			radius * 5.8, 0.58, 0.05, 3.40, 0.82, 0.995, true, -1.0, world_scale))
	_attach_socket_extras(model, CLASS_II_BOOSTER_SOCKETS, -1.0, world_scale, accent)
	return propulsion_materials


# `facing` is the model-space axis the exhaust travels along: -1.0 for the three
# yaw-180 ships, +1.0 for JazOone. `world_scale` is the fit_model factor, needed
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
	# came out as 34 for class_ii and 652 for dingo57 against a 0.12 km hull, i.e. a
	# light reaching hundreds of hull lengths out into the solar system and lighting
	# planets, station props and the star shell. tools/probe_live_scene.gd prints these
	# next to the hull key light (range 0.9) if you need to see it again.
	#
	# _add_heat_haze below already converts its depth fade through `world_scale`; this
	# is the same conversion, and it was simply missing. Range now lands near the hull
	# lights' 0.48-0.9, which is what "a few socket radii" was always meant to mean.
	#
	# Separately measured: at the old range 7.0 / attenuation 1.6 these were the ENTIRE
	# blowout on class_ii, dingo57 and snarkrans - hiding the nozzle rig in the chase
	# view dropped p99 luminance 0.081 -> 0.017 (class_ii) and 0.289 -> 0.033 (dingo57)
	# while the torch and propulsion shaders, zeroed, changed nothing.
	# 12x the socket radius, in WORLD units: enough to rake the aft third of the hull
	# (39 m of a 122 m Class II, 21 m of a 128 m Dingo57) and nothing beyond the ship.
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
				# Area-compensated, NOT a taste value. tools/probe_propulsion_area.gd
				# measures how much of each hull the additive booster shader covers:
				# class_ii 0.64%, dingo57 4.30%, snarkrans 6.69%. These layers ADD, so
				# a flat brightness makes the ship with ten times the emissive area ten
				# times as washed - which is exactly what ate snarkrans' mid-hull.
				# Scaled by sqrt(class_ii_area / this_area), same reasoning as the
				# per-nozzle light share in ship.gd.
				propulsion.set_shader_parameter("brightness",
					booster_gain(SNARKRANS_BOOSTER_GAIN))
				# The tip/bottom/shell surfaces each span more than one housing, and
				# the three sockets sit within a radius of each other, so every surface
				# gets all three rather than a guessed one-to-one mapping.
				_wire_nozzle_shape(propulsion, SNARKRANS_BOOSTER_SOCKETS,
					_model_to_surface_space(model, mi), Vector3(0.0, 0.0, 1.0))
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
			radius * 9.8, 1.22, 0.20, 1.30, 0.55, 0.42, false, -1.0, world_scale))
		propulsion_materials.append(_add_torch_layer(
			plume_root, "BoosterCore%02d" % (i + 1), center, radius,
			radius * 6.0, 0.60, 0.05, 3.50, 0.82, 0.998, true, -1.0, world_scale))
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
	# Snarkrans-only, and it sits right on top of the booster faces above.
	material.set_shader_parameter("brightness", booster_gain(SNARKRANS_BOOSTER_GAIN))
	# The plug IS the throat, so it keeps the core boost and only loses its outer rim.
	# CylinderMesh runs along +Y and this node is rotated, not the mesh, so the shaping
	# axis is Y in the plug's own vertex space and the socket sits at its origin.
	_wire_nozzle_shape(material, [{ "center": Vector3.ZERO, "radius": radius }],
		Transform3D.IDENTITY, Vector3(0.0, 1.0, 0.0))

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
			radius * 9.2, 1.16, 0.18, 1.20, 0.55, 0.42, false, -1.0, world_scale))
		propulsion_materials.append(_add_torch_layer(
			plume_root, "BoosterCore%02d" % (i + 1), center, radius,
			radius * 5.6, 0.56, 0.05, 3.20, 0.82, 0.995, true, -1.0, world_scale))
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
				# See SNARKRANS_BOOSTER_GAIN: eight emissive groups, 4.30% of the hull.
				propulsion.set_shader_parameter("brightness",
					booster_gain(DINGO57_BOOSTER_GAIN))
				# Eight groups and eight sockets, but nothing in the asset maps
				# booster_group_NNN to a socket index - 070/109 are two halves of one
				# bell. Pass all eight and let the nearest-socket search sort it out.
				_wire_nozzle_shape(propulsion, DINGO57_BOOSTER_SOCKETS,
					_model_to_surface_space(model, mi), Vector3(0.0, 0.0, 1.0))
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
			# See JAZOONE_BOOSTER_GAIN for why this ship's discs run so much cooler
			# than the other three ships' booster patches.
			hull.set_shader_parameter("brightness", booster_gain(JAZOONE_BOOSTER_GAIN))
			# The emissive mask says WHICH texels are engine; the sockets say how the
			# energy is graded across them. Without this the disc is a hard-rimmed
			# plate - the mask is saturated, so it carries no gradient of its own.
			# JazOone imports with yaw 0: its exhaust runs +Z like its plumes.
			_wire_nozzle_shape(hull, JAZOONE_BOOSTER_SOCKETS,
				_model_to_surface_space(model, mi), Vector3(0.0, 0.0, 1.0))
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
			radius * 6.8, 1.10, 0.18, 1.22, 0.55, 0.42, false, 1.0, world_scale))
		propulsion_materials.append(_add_torch_layer(
			plume_root, "BoosterCore%02d" % (i + 1), center, radius,
			radius * 4.2, 0.54, 0.05, 3.30, 0.82, 0.995, true, 1.0, world_scale))
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
			# Primitive meshes have no surface_get_name. The game colours the hull
			# before the plumes exist, but the render harness builds them first and the
			# raw call aborted this whole loop on the first CylinderMesh it reached,
			# leaving part of the hull uncoloured.
			var surface_tag := ""
			if mi.mesh.has_method("surface_get_name"):
				surface_tag = String(mi.mesh.surface_get_name(si)).to_lower()
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
