"""Sovereign's layered armor and exposed drive assemblies; nose +Y, up +Z."""
import math

import bpy
import numpy as np

from mathutils import Vector

import ship_common as C
import sleek as S


def finish_materials():
	rng = np.random.default_rng(81)
	n = 512
	y, x = np.mgrid[:n, :n] / n
	brush = np.sin(2 * math.pi * (y * 128 + .12 * np.sin(x * 2 * math.pi)))
	normal = np.ones((n, n, 4), dtype=np.float32)
	normal[:, :, 0] = .5 + rng.normal(0, .002, (n, n))
	normal[:, :, 1] = .5 + .016 * brush + rng.normal(0, .002, (n, n))
	normal[:, :, 2] = 1
	image = bpy.data.images.new("Sovereign_BrushedNormal", n, n, alpha=False)
	image.colorspace_settings.name = "Non-Color"
	image.pixels.foreach_set(normal.ravel())
	image.pack()
	for name, roughness, metallic in [("Hull_Paint", .36, .62), ("Hull_Dark", .52, .24), ("Hull_Steel", .26, .92)]:
		material = C.mat(name)
		nt = material.node_tree
		bsdf = nt.nodes["Principled BSDF"]
		grain = rng.normal(0, .013, (256, 256))
		grain = sum(np.roll(grain, i, axis=1) for i in range(-2, 3)) / 5
		bands = np.sin(np.arange(256)[:, None] * 2 * math.pi / 16) * .015
		mr = np.ones((256, 256, 4), dtype=np.float32)
		mr[:, :, 1] = np.clip(roughness + grain + bands, 0, 1)
		mr[:, :, 2] = metallic
		packed = bpy.data.images.new("Sovereign_" + name + "_MR", 256, 256, alpha=False)
		packed.colorspace_settings.name = "Non-Color"
		packed.pixels.foreach_set(mr.ravel())
		packed.pack()
		tex = nt.nodes.new("ShaderNodeTexImage")
		tex.image = packed
		separate = nt.nodes.new("ShaderNodeSeparateRGB")
		nt.links.new(tex.outputs["Color"], separate.inputs[0])
		nt.links.new(separate.outputs["G"], bsdf.inputs["Roughness"])
		nt.links.new(separate.outputs["B"], bsdf.inputs["Metallic"])
		norm_tex = nt.nodes.new("ShaderNodeTexImage")
		norm_tex.image = image
		norm = nt.nodes.new("ShaderNodeNormalMap")
		norm.inputs["Strength"].default_value = .32
		nt.links.new(norm_tex.outputs["Color"], norm.inputs["Color"])
		nt.links.new(norm.outputs["Normal"], bsdf.inputs["Normal"])
	C.mat("Hull_Dark").node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (.023, .028, .034, 1)
	C.mat("Hull_Steel").node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (.48, .51, .56, 1)


def armor_uv(ob):
	uv = ob.data.uv_layers.get("ArmorUV") or ob.data.uv_layers.new(name="ArmorUV")
	for face in ob.data.polygons:
		axis = max(range(3), key=lambda i: abs(face.normal[i]))
		a, b = [(1, 2), (0, 2), (0, 1)][axis]
		for loop in face.loop_indices:
			p = ob.data.vertices[ob.data.loops[loop].vertex_index].co
			uv.data[loop].uv = (p[a] / 16, p[b] / 16)


def polish_export(ob):
	armor_uv(ob)
	normals = ob.modifiers.new("ArmorWeightedNormals", "WEIGHTED_NORMAL")
	normals.keep_sharp = True
	normals.weight = 50
	C.apply_mods(ob)


class ArmorBody(S.Body):
	def __init__(self, keys, **kw):
		super().__init__(keys, **kw)
		self.keys = sorted(keys)
		self.nu, self.nl = 3, 3

	def prof(self, y):
		for a, b in zip(self.keys, self.keys[1:]):
			if a[0] <= y <= b[0]:
				t = (y - a[0]) / (b[0] - a[0])
				return tuple(a[i] * (1 - t) + b[i] * t for i in range(1, 5))
		return tuple((self.keys[0] if y < self.keys[0][0] else self.keys[-1])[1:])

	def build(self, name, **kw):
		sections = []
		for y, w, _, zc, _ in reversed(self.keys):
			sections.append(self.ring(y) if w > 0 else [Vector((self.x0, y, zc))])
		ob = C.loft(name, sections, ["Hull_Paint", "Hull_Dark"],
			face_fn=lambda p: 0 if p.z > self.prof(p.y)[2] + .01 else 1, caps=(0, 1))
		if self.x0:
			C.mirror(ob)
		ob.data.materials.append(C.mat("Hull_Steel"))
		bevel = C.bevel(ob, .24, seg=2, angle=14)
		bevel.material = 2
		bevel.harden_normals = True
		bevel.mark_sharp = True
		return ob

	def up(self, y, u):
		w, zt, zc, _ = self.prof(y)
		sign = -1 if u < 0 else 1
		u = min(abs(u), 1)
		h = 1 if u <= .55 else (1 - .55 * (u - .55) / .31 if u <= .86 else .45 * (1 - u) / .14)
		return Vector((self.x0 + sign * w * u, y, zc + (zt - zc) * h))

	def lo(self, y, u):
		w, _, zc, zb = self.prof(y)
		u = min(max(u, 0), 1)
		h = 1 if u <= .48 else (1 - .5 * (u - .48) / .36 if u <= .84 else .5 * (1 - u) / .16)
		return Vector((self.x0 + w * u, y, zc - (zc - zb) * h))

	def half(self, y):
		return [self.up(y, u) for u in (0, .55, .86, 1)] + [self.lo(y, u) for u in (.84, .48, 0)]


def slab(name, points, thick=.35, paint="Hull_Paint", mirrored=True):
	bottom = [Vector(p) for p in points]
	xy = np.array([(p.x, p.y, 1) for p in bottom])
	z = np.array([p.z for p in bottom])
	plane = xy @ np.linalg.lstsq(xy, z, rcond=None)[0]
	clearance = max(z - plane)
	for p, height in zip(bottom, plane):
		p.z = float(height + clearance)
	top = [p + Vector((0, 0, thick)) for p in bottom]
	ob = C.loft(name, [bottom, top], [paint, "Hull_Steel", "Hull_Dark"], band=[1], caps=(2, 0))
	if mirrored:
		C.mirror(ob)
	C.bevel(ob, .12, seg=2, angle=25)
	return ob


def ray(body, name, yf, yr, uf, ur, width):
	S.plate(name, body, yf, yr, (uf - .003, ur - width * .5),
		(uf + .003, ur + width * .5), .065, ny=12, nu=1,
		mat="Hull_Dark", wall="Hull_Dark")


def path(name, points, width=.25, height=.16, mat="Hull_Dark", mirror=True):
	S.tube(name, [Vector(p) for p in points], [Vector((0, 0, 1))] * len(points),
		width, height, mat, mirror=mirror, sink=0)


def drive(name, x, z, radius):
	axis = Vector((0, -1, 0))
	profile = [(-78, 1.00, 0), (-100, 1.00, 0), (-104, 1.14, 1), (-109, 1.14, 0),
		(-112, 1.08, 1), (-117, 1.08, 0), (-120, 1.02, 1), (-120, .83, 1),
		(-117, .77, 0), (-111, .64, 2), (-106, .50, 2)]
	rings = [C.circle((x, y, z), axis, radius * scale, 8, phase=math.pi/8) for y, scale, _ in profile]
	ob = C.loft(name, rings, ["Hull_Dark", "Hull_Steel", "Nozzle_Emit"],
		band=[p[2] for p in profile[:-1]], caps=(0, 2))
	C.mirror(ob)
	C.bevel(ob, .18, seg=2, angle=30)
	for i in range(8):
		a = math.pi/8 + i * math.pi/4
		p = Vector((x + radius * 1.13 * math.cos(a), -116, z + radius * 1.13 * math.sin(a)))
		C.mirror(C.cyl(name + "CollarRib", p, p + Vector((0, 9, 0)), .22, .22, 6, "Hull_Steel"))
	return Vector((x, -120, z))


def stern_cuff(name, x, z, radius, upper):
	sign = 1 if upper else -1
	angles = [0, math.pi/8, 3*math.pi/8, 5*math.pi/8, 7*math.pi/8, math.pi]
	sections = []
	for y, outside in [(-79, 1.26), (-92, 1.40), (-100, 1.58), (-110, 1.52), (-116, 1.36)]:
		outer = [Vector((x + radius * outside * math.cos(a), y, z + sign * radius * outside * math.sin(a))) for a in angles]
		inner = [Vector((x + radius * 1.23 * math.cos(a), y, z + sign * radius * 1.23 * math.sin(a))) for a in reversed(angles)]
		sections.append(outer + inner)
	ob = C.loft(name, sections, ["Hull_Paint", "Hull_Dark", "Hull_Steel"],
		caps=(2, 2), face_fn=lambda p: 1 if math.hypot(p.x - x, p.z - z) < radius * 1.19 else 0)
	C.mirror(ob)
	C.bevel(ob, .16, seg=2, angle=25)
	# A separate lip reveals the recessed joint without covering the exhaust mouth.
	lip_rings = []
	for y in [-111.5, -114.0]:
		outer = [Vector((x + radius * 1.57 * math.cos(a), y, z + sign * radius * 1.57 * math.sin(a))) for a in angles]
		inner = [Vector((x + radius * 1.51 * math.cos(a), y, z + sign * radius * 1.51 * math.sin(a))) for a in reversed(angles)]
		lip_rings.append(outer + inner)
	lip = C.loft(name + "EdgeLip", lip_rings, ["Hull_Steel", "Hull_Dark"], caps=(1, 0))
	C.mirror(lip)
	for i in [1, 4]:
		a = angles[i]
		p0 = Vector((x + radius * 1.59 * math.cos(a), -113.0, z + sign * radius * 1.59 * math.sin(a)))
		p1 = Vector((x + radius * 1.59 * math.cos(angles[i+1]), -113.0, z + sign * radius * 1.59 * math.sin(angles[i+1])))
		path(name + "Nav", [p0, p1], .14, .10, mat="Accent_Emit")


def ventilator(x, yf=0):
	outline = [(-1, -.68), (-.73, -1), (.73, -1), (1, -.68),
		(1, .68), (.73, 1), (-.73, 1), (-1, .68)]
	def ring(y, width, height):
		return [Vector((x + u * width, y, 5.1 + v * height)) for u, v in outline]
	frame = C.loft("OuterVentilatorFrame", [ring(yf - 13, 7.5, 5.3), ring(yf - 1, 8.4, 5.8),
		ring(yf, 8.1, 5.5), ring(yf, 6.6, 4.0), ring(yf - 5, 6.1, 3.6)],
		["Hull_Paint", "Hull_Steel", "Hull_Dark"], band=[0, 1, 1, 2], caps=(0, 2))
	C.mirror(frame)
	C.bevel(frame, .16, seg=2)
	for i, z in enumerate([2.8, 5.1, 7.4]):
		front = [(x - 5.8, yf - 1.2, z - .38), (x - 5.0, yf - .8, z + .35),
			(x + 5.8, yf - .8, z + .35), (x + 5.0, yf - 1.2, z - .38)]
		rear = [(px, py - 1.9, pz - .65) for px, py, pz in front]
		vane = C.loft("VentilatorSweptVane%d" % i, [front, rear], ["Hull_Steel", "Hull_Dark"], caps=(0, 1), band=[1])
		C.mirror(vane)
		C.bevel(vane, .06, seg=1)
	path("VentilatorStatus", [(x - 4.5, yf + .18, 9.4), (x + 4.5, yf + .18, 9.4)],
		.12, .10, mat="Accent_Emit")


def build(k):
	finish_materials()
	paint = C.mat("Hull_Paint").node_tree.nodes["Principled BSDF"]
	paint.inputs["Base Color"].default_value = (.55, .58, .64, 1)
	paint.inputs["Metallic"].default_value = .65
	nozzle = C.mat("Nozzle_Emit").node_tree.nodes["Principled BSDF"]
	nozzle.inputs["Emission Color"].default_value = (.12, .65, 1, 1)
	nozzle.inputs["Emission Strength"].default_value = 3

	b = ArmorBody([(120, 0, 1, 1, 1), (109, 1.2, 2, .3, -1), (77, 3.4, 3.5, .3, -2),
		(42, 6, 5, .3, -3.7), (8, 14, 6.8, .3, -5.5), (-34, 20, 7.5, .3, -7),
		(-74, 20, 7.2, .3, -7), (-101, 18, 5.8, .3, -6)], x0=0)
	prong = ArmorBody([(113, 0, 1.2, 1.2, 1.2), (101, 2.8, 3, 0, -2),
		(69, 5.2, 5.4, 0, -3), (35, 6.5, 7, 0, -3.8), (4, 7.5, 8.5, .3, -4.5),
		(-30, 8, 9.2, .5, -5.7), (-61, 7, 8.5, .5, -5.7)], x0=17)
	shoulder = ArmorBody([(-4, 7, 10.4, 4.8, -.5), (-20, 8, 10.5, .5, -4),
		(-40, 11, 11.8, .5, -7), (-63, 13.5, 12.5, .5, -8),
		(-86, 13.5, 12, .5, -8.5), (-105, 11.5, 9.6, .5, -8.5)], x0=34)
	deck = ArmorBody([(33, 0, 5, 5, 5), (16, 6, 8.5, 5, 3.5), (-6, 11, 12, 6, 4),
		(-37, 12, 13, 6.5, 4), (-69, 11, 11.7, 6, 4), (-104, 7.5, 8.7, 4, 3)], x0=0)
	for name, body, stations in [("GraphiteKeel", b, 32), ("ProwStructure", prong, 26),
		("DriveStructure", shoulder, 24), ("CommandStructure", deck, 24)]:
		k.hull(name, body, stations=stations, paint=1, dark=1, bevel=False)
	ventilator(34)

	ray(b, "SpearBlackRay", 107, 12, .1, .7, .2)
	ray(prong, "ProwSweptRay", 99, -53, -.15, .55, .28)
	ray(prong, "ProwInnerRay", 74, -48, -.45, -.74, .17)
	ray(shoulder, "ShoulderMainRay", -10, -100, .48, -.4, .28)
	ray(shoulder, "ShoulderOuterRay", -26, -100, .80, .38, .15)
	ray(shoulder, "ShoulderInnerRay", -26, -98, .02, -.76, .12)
	ray(deck, "CommandRay", 12, -99, .12, .75, .20)

	k.blade("MantleStructure", [((23, 2, -1), 84, 4), ((46, -32, -1), 59, 3),
		((61, -88, -2), 17, .7)], spans=3, tip_light=False, mats=("Hull_Dark", "Hull_Dark"))
	slab("SweptWingArmor", [(27, -11, 4), (39, -20, 3.2), (51, -43, 1.8),
		(60, -89, -.7), (56, -98, -.4), (39, -95, 2.9), (32, -38, 4)], thick=1.1)
	slab("WingSweptRay", [(39, -32, 4.35), (42, -35, 4.1),
		(55, -85, 1), (53, -86, 1.2)], thick=.07, paint="Hull_Dark")

	bridge_outline = [(0, -4), (8, -13), (10.4, -23), (10.4, -39), (6.5, -50),
		(-6.5, -50), (-10.4, -39), (-10.4, -23), (-8, -13)]
	rings = [[(x * scale, y, z) for x, y in bridge_outline] for z, scale in [(11.5, 1.18), (13.3, 1), (15.8, .92), (16.4, .91)]]
	bridge = C.loft("PanoramicBridge", rings, ["Hull_Paint", "Hull_Steel", "Glass"], band=[0, 2, 1], caps=(0, 0))
	C.bevel(bridge, .20, seg=2)
	slab("BridgeRoof", [(x * .92, y, 16.45) for x, y in bridge_outline], thick=.55, mirrored=False)
	slab("BridgeForeApron", [(0, 8, 9.8), (8.6, -12, 12.7), (0, -5, 13.5)], thick=.35)
	slab("BridgeAftApron", [(0, -45, 14.3), (7, -46, 13.6), (9, -60, 11.9), (0, -69, 11.8)], thick=.45)
	window_frames = C.Boxes("BridgeMullions", ["Hull_Steel"], mirror_x=True)
	for y in [-23, -31, -39]:
		window_frames.add((10.0, y, 14.6), (.20, .20, 2.6), rot_x=-.08)
	window_frames.build(bevel_w=.06)

	inner = drive("InnerDrive", 10, -2.2, 5.5)
	outer = drive("OuterDrive", 34, -3.2, 8.4)
	handoff = ArmorBody([(-54, 0, 10.3, 10.3, 10.3), (-66, 6, 11.9, 8.5, 7.8),
		(-82, 8.4, 11.2, 6.9, 5.8), (-100, 7.1, 8.7, 5.1, 4.2),
		(-108, 4.7, 7.9, 4.3, 3.8)], x0=10)
	handoff.build("InnerDriveTransition")
	ray(handoff, "HoodSweptRay", -65, -105, -.18, .46, .16)
	for name, x, z, radius in [("Outer", 34, -3.2, 8.4), ("Inner", 10, -2.2, 5.5)]:
		stern_cuff(name + "UpperDeck", x, z, radius, True)
		stern_cuff(name + "LowerCradle", x, z, radius, False)

	for x, z in [(23, 8.5), (28, 7.2)]:
		C.mirror(C.cyl("ChannelConduit", (x, -5, z), (x, -100, z), .38, .38, 8, "Hull_Steel"))
	S.chine_strip("ProwNav", prong, 89, -43, .99, .22, .12, n=18)
	S.chine_strip("DriveNav", shoulder, -35, -93, .99, .24, .12, n=18)

	k.pair("BOOSTER", lambda s: Vector((10 * s, inner.y, inner.z)))
	k.pair("BOOSTER", lambda s: Vector((34 * s, outer.y, outer.z)))
	k.pair("RCS", lambda s: k.side(s, 88, .2), "lateral")
	k.pair("RCS", lambda s: k.top(17 * s, 70), Vector((0, 0, 1)))
	k.pair("RCS", lambda s: k.side(s, -91, .2), "lateral")
	k.pair("RCS", lambda s: k.belly(34 * s, -83), Vector((0, 0, -1)))
	for x, y in [(17, 68), (21, 14), (40, -29), (51, -75)]:
		k.pair("WEAPON", lambda s, x=x, y=y: k.belly(x * s, y))
	for x, y in [(17, 55), (24, -12), (34, -82)]:
		k.pair("PAD", lambda s, x=x, y=y: k.belly(x * s, y))
	for x, y in [(17, 81), (17, 28), (26, -34), (34, -86)]:
		k.pair("LANDJET", lambda s, x=x, y=y: k.belly(x * s, y))
	for ob in bpy.data.objects:
		if ob.type == "MESH":
			armor_uv(ob)
