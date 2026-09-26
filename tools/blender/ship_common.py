"""Shared Blender 4.2 helpers for the Astryx hull roster (build_ships.py, render_ships.py).

Authoring frame: nose +Y, up +Z, right +X, 1 unit = 1 m. The glTF exporter maps Blender
(x, y, z) to glTF (x, z, -y), so Blender +Y becomes Godot -Z (verified by importing into
Godot 4.6.3). The spec's "Blender -Y" note would put the nose at Godot +Z.
"""
import math
import random

import bmesh
import bpy
from mathutils import Matrix, Vector

MAT_DEFS = {
	"Hull_Paint": dict(color=(0.26, 0.36, 0.48), metallic=0.55, rough=0.3),
	"Hull_Dark": dict(color=(0.03, 0.035, 0.042), metallic=0.5, rough=0.45),
	"Hull_Steel": dict(color=(0.42, 0.45, 0.46), metallic=0.85, rough=0.32),
	"Glass": dict(color=(0.04, 0.09, 0.13), metallic=0.3, rough=0.05, coat=1.0),
	"Accent_Emit": dict(color=(0.12, 0.65, 0.80), metallic=0.0, rough=0.4, emit=(0.15, 0.75, 1.0), strength=6.0),
	"Nozzle_Emit": dict(color=(1.0, 0.45, 0.15), metallic=0.0, rough=0.4, emit=(1.0, 0.5, 0.18), strength=12.0),
}

SOCKET_KINDS = ("WEAPON", "BOOSTER", "RCS", "PAD", "LANDJET")


def reset():
	bpy.ops.wm.read_factory_settings(use_empty=True)
	for name in MAT_DEFS:
		mat(name)


def mat(name):
	m = bpy.data.materials.get(name)
	if m:
		return m
	d = MAT_DEFS[name]
	m = bpy.data.materials.new(name)
	m.use_nodes = True
	p = m.node_tree.nodes["Principled BSDF"]
	p.inputs["Base Color"].default_value = (*d["color"], 1.0)
	p.inputs["Metallic"].default_value = d["metallic"]
	p.inputs["Roughness"].default_value = d["rough"]
	if "coat" in d:
		p.inputs["Coat Weight"].default_value = d["coat"]
		p.inputs["Coat Roughness"].default_value = 0.03
	if "emit" in d:
		p.inputs["Emission Color"].default_value = (*d["emit"], 1.0)
		p.inputs["Emission Strength"].default_value = d["strength"]
	return m


def _link(name, bm, mats):
	me = bpy.data.meshes.new(name)
	bm.to_mesh(me)
	bm.free()
	for m in mats:
		me.materials.append(mat(m) if isinstance(m, str) else m)
	ob = bpy.data.objects.new(name, me)
	bpy.context.scene.collection.objects.link(ob)
	return ob


def loft(name, sections, mats, band=None, caps=(0, 0), face_fn=None):
	"""sections: list of point rings (same count, or a single apex point).
	band: material index per band between rings; face_fn(centre) overrides it."""
	if isinstance(mats, str):
		mats = [mats]
	bm = bmesh.new()
	rings = [[bm.verts.new(Vector(p)) for p in ring] for ring in sections]
	for i in range(len(rings) - 1):
		a, b = rings[i], rings[i + 1]
		mi = band[i] if band else 0
		quads = []
		if len(a) == 1:
			quads = [(a[0], b[j], b[(j + 1) % len(b)]) for j in range(len(b))]
		elif len(b) == 1:
			quads = [(a[j], a[(j + 1) % len(a)], b[0]) for j in range(len(a))]
		else:
			n = len(a)
			quads = [(a[j], a[(j + 1) % n], b[(j + 1) % n], b[j]) for j in range(n)]
		for q in quads:
			f = bm.faces.new(q)
			f.material_index = mi
	for ring, mi in ((rings[0], caps[0]), (rings[-1], caps[1])):
		if len(ring) > 2 and mi is not None:
			f = bm.faces.new(ring)
			f.material_index = mi
	if face_fn:
		for f in bm.faces:
			r = face_fn(f.calc_center_median())
			if r is not None:
				f.material_index = r
	bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
	return _link(name, bm, mats)


def circle(center, axis, r, seg, phase=0.0, sx=1.0, sz=1.0):
	c, a = Vector(center), Vector(axis).normalized()
	if abs(a.y) > 0.99:
		u, v = Vector((1, 0, 0)), Vector((0, 0, 1))
	else:
		u = a.cross(Vector((0, 1, 0))).normalized()
		v = a.cross(u).normalized()
	return [c + u * (r * sx * math.cos(phase + 2 * math.pi * i / seg)) + v * (r * sz * math.sin(phase + 2 * math.pi * i / seg)) for i in range(seg)]


def cyl(name, p0, p1, r0, r1, seg, mats, caps=(0, 0)):
	a = Vector(p1) - Vector(p0)
	return loft(name, [circle(p0, a, r0, seg), circle(p1, a, r1, seg)], mats, caps=caps)


HULL_HALF = ((0.0, "t"), (0.42, "t"), (0.82, "s"), (1.0, "c"), (0.84, "l"), (0.48, "b"), (0.0, "b"))


def hull_ring(y, w, zt, zb, zc, x0=0.0):
	zs = zc + 0.62 * (zt - zc)
	zl = zc - 0.5 * (zc - zb)
	z = {"t": zt, "s": zs, "c": zc, "l": zl, "b": zb}
	half = [(fx * w, z[k]) for fx, k in HULL_HALF]
	full = half + [(-x, zz) for x, zz in reversed(half[1:-1])]
	return [(x0 + x, y, zz) for x, zz in full]


def resample(stations, step):
	out = [stations[0]]
	for a, b in zip(stations, stations[1:]):
		n = max(1, int(math.ceil(abs(a[0] - b[0]) / step)))
		for k in range(1, n + 1):
			t = k / n
			out.append(tuple(a[i] * (1 - t) + b[i] * t for i in range(len(a))))
	return out


def hull(name, stations, step, x0=0.0, belly_dark=True, mirror_x=False):
	"""stations: (y, half_width, z_top, z_bottom, z_chine), nose first. Belly below the chine is Hull_Dark."""
	stations = resample(stations, step)
	rings = [hull_ring(*s, x0=x0) for s in stations]
	chine = {round(s[0], 4): s[4] for s in stations}
	ys = sorted(chine)

	def chine_at(y):
		for i in range(len(ys) - 1):
			if ys[i] <= y <= ys[i + 1]:
				t = (y - ys[i]) / max(ys[i + 1] - ys[i], 1e-6)
				return chine[ys[i]] * (1 - t) + chine[ys[i + 1]] * t
		return chine[ys[0]] if y < ys[0] else chine[ys[-1]]

	fn = (lambda c: 1 if c.z < chine_at(c.y) - 0.01 else None) if belly_dark else None
	ob = loft(name, rings, ["Hull_Paint", "Hull_Dark"], caps=(0, 1), face_fn=fn)
	if mirror_x:
		mirror(ob)
	return ob


WING_PROFILE = ((0.0, 0.0), (0.16, 0.5), (0.38, 0.5), (0.6, 0.5), (0.82, 0.5), (1.0, 0.12),
	(1.0, -0.12), (0.82, -0.5), (0.6, -0.5), (0.38, -0.5), (0.16, -0.5))


def wing(name, stations, normal=(0, 0, 1), mats="Hull_Paint", mirror_x=True, face_fn=None, spans=2):
	"""stations: (leading_edge_point, chord, thickness[, normal]); chord runs toward -Y.
	Each span is split so panel lines have a grid to follow."""
	d = Vector((0, -1, 0))
	st = [(Vector(s[0]), s[1], s[2], Vector(s[3] if len(s) > 3 else normal).normalized()) for s in stations]
	dense = [st[0]]
	for a, b in zip(st, st[1:]):
		for k in range(1, spans + 1):
			t = k / spans
			dense.append((a[0].lerp(b[0], t), a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t, a[3].lerp(b[3], t).normalized()))
	rings = [[p + d * (u * chord) + n * (v * t) for u, v in WING_PROFILE] for p, chord, t, n in dense]
	ob = loft(name, rings, mats if isinstance(mats, list) else [mats], face_fn=face_fn)
	if mirror_x:
		mirror(ob)
	return ob


class Boxes:
	"""Batches many boxes (greebles, lights, frames) into one object."""

	def __init__(self, name, mats, mirror_x=True):
		self.name, self.mats, self.mirror_x = name, mats, mirror_x
		self.bm = bmesh.new()

	def add(self, center, size, mi=0, rot_z=0.0, rot_x=0.0):
		m = Matrix.Translation(Vector(center)) @ Matrix.Rotation(rot_z, 4, "Z") @ Matrix.Rotation(rot_x, 4, "X") @ Matrix.Diagonal((*size, 1.0))
		r = bmesh.ops.create_cube(self.bm, size=1.0, matrix=m)
		faces = {f for v in r["verts"] for f in v.link_faces}
		for f in faces:
			f.material_index = mi

	def build(self, bevel_w=0.0):
		if not self.bm.faces:
			self.bm.free()
			return None
		ob = _link(self.name, self.bm, self.mats)
		if self.mirror_x:
			mirror(ob)
		if bevel_w > 0:
			bevel(ob, bevel_w, seg=1)
		return ob


def mirror(ob):
	m = ob.modifiers.new("Mirror", "MIRROR")
	m.use_axis = (True, False, False)
	m.use_mirror_merge = True
	m.merge_threshold = 0.001
	return m


def bevel(ob, width, seg=2, angle=30.0):
	m = ob.modifiers.new("Bevel", "BEVEL")
	m.width = width
	m.segments = seg
	m.limit_method = "ANGLE"
	m.angle_limit = math.radians(angle)
	m.use_clamp_overlap = True
	return m


def boolean(ob, cutter, op="DIFFERENCE"):
	m = ob.modifiers.new("Bool_" + cutter.name, "BOOLEAN")
	m.operation = op
	m.object = cutter
	m.solver = "EXACT"
	m.material_mode = "TRANSFER"
	cutter.display_type = "WIRE"
	cutter.hide_render = True
	cutter["cutter"] = True
	return m


def apply_mods(ob):
	if not ob.modifiers:
		return ob
	dg = bpy.context.evaluated_depsgraph_get()
	me = bpy.data.meshes.new_from_object(ob.evaluated_get(dg), preserve_all_data_layers=True, depsgraph=dg)
	old = ob.data
	ob.modifiers.clear()
	ob.data = me
	if old.users == 0:
		bpy.data.meshes.remove(old)
	return ob


def panels(ob, seed, width, depth, min_edge, frac=0.55, mats=("Hull_Paint", "Hull_Dark")):
	"""Recessed panel lines: insets a symmetric, seeded subset of large faces."""
	apply_mods(ob)
	allowed = {i for i, m in enumerate(ob.data.materials) if m and m.name in mats}
	bm = bmesh.new()
	bm.from_mesh(ob.data)
	sel = []
	for f in bm.faces:
		if f.material_index not in allowed or len(f.verts) != 4:
			continue
		if min(e.calc_length() for e in f.edges) < min_edge:
			continue
		c = f.calc_center_median()
		key = "%s|%.2f|%.2f|%.2f" % (seed, abs(c.x), c.y, c.z)
		if random.Random(key).random() < frac:
			sel.append(f)
	if sel:
		bmesh.ops.inset_individual(bm, faces=sel, thickness=width, depth=-depth, use_even_offset=True)
	bm.to_mesh(ob.data)
	bm.free()
	return len(sel)


def surface(origin, direction):
	dg = bpy.context.evaluated_depsgraph_get()
	ok, loc, _n, _i, _ob, _m = bpy.context.scene.ray_cast(dg, Vector(origin), Vector(direction).normalized())
	if not ok:
		raise RuntimeError("surface ray missed hull: %s -> %s" % (tuple(origin), tuple(direction)))
	return loc


def socket(kind, idx, loc, exhaust=None, size=1.0):
	"""Godot local +Z == Blender local -Y. Default orientation (identity) gives
	-Z forward (weapons), +Z aft (boosters) and -Y down (pads, landjets)."""
	e = bpy.data.objects.new("SOCKET_%s_%d" % (kind, idx), None)
	e.empty_display_type = "SINGLE_ARROW"
	e.empty_display_size = size
	e.location = Vector(loc)
	if exhaust is not None:
		d = Vector(exhaust).normalized()
		e.rotation_mode = "QUATERNION"
		e.rotation_quaternion = d.to_track_quat("-Y", "X" if abs(d.z) > 0.9 else "Z")
	bpy.context.scene.collection.objects.link(e)
	return e


def finalize(name="Hull", smooth_angle=35.0):
	meshes = [o for o in bpy.data.objects if o.type == "MESH" and not o.get("cutter")]
	for ob in meshes:
		apply_mods(ob)
	for ob in [o for o in bpy.data.objects if o.get("cutter")]:
		bpy.data.objects.remove(ob, do_unlink=True)
	for ob in bpy.data.objects:
		ob.select_set(ob in meshes)
	bpy.context.view_layer.objects.active = meshes[0]
	bpy.ops.object.join()
	hull_ob = bpy.context.view_layer.objects.active
	hull_ob.name = name
	hull_ob.data.name = name
	bpy.ops.object.shade_smooth_by_angle(angle=math.radians(smooth_angle), keep_sharp_edges=True)
	return hull_ob


def recentre(hull_ob):
	bb = [Vector(c) for c in hull_ob.bound_box]
	lo = Vector((min(v[i] for v in bb) for i in range(3)))
	hi = Vector((max(v[i] for v in bb) for i in range(3)))
	c = (lo + hi) * 0.5
	c.x = 0.0
	hull_ob.data.transform(Matrix.Translation(-c))
	for ob in bpy.data.objects:
		if ob.type == "EMPTY":
			ob.location -= c
	hull_ob.data.update()
	return hi - lo


def tri_count(ob):
	return sum(len(p.vertices) - 2 for p in ob.data.polygons)


def sockets():
	return sorted(o.name for o in bpy.data.objects if o.type == "EMPTY" and o.name.startswith("SOCKET_"))


def export_glb(path):
	for ob in bpy.data.objects:
		ob.select_set(True)
	bpy.ops.export_scene.gltf(
		filepath=path,
		export_format="GLB",
		use_selection=False,
		export_apply=True,
		export_yup=True,
		export_cameras=False,
		export_lights=False,
		export_materials="EXPORT",
	)
