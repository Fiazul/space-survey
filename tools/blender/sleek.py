"""Smooth-surface kit for the v2 fleet: analytic lofted bodies with a knife chine, blade
wings/fins, recessed-bell engines, faceted canopies, raised armour plates and accent strips.
Blender frame: nose +Y, up +Z. Every builder is deterministic (no RNG).
"""
import math

import bmesh
import bpy
from mathutils import Matrix, Vector

import ship_common as C


def pchip(keys):
	keys = sorted(keys)
	xs = [k[0] for k in keys]
	ys = [k[1] for k in keys]
	n = len(xs)
	if n == 1:
		return lambda x: ys[0]
	h = [xs[i + 1] - xs[i] for i in range(n - 1)]
	d = [(ys[i + 1] - ys[i]) / h[i] for i in range(n - 1)]
	m = [0.0] * n
	m[0], m[-1] = d[0], d[-1]
	for i in range(1, n - 1):
		if d[i - 1] * d[i] <= 0:
			m[i] = 0.0
		else:
			w1, w2 = 2 * h[i] + h[i - 1], h[i] + 2 * h[i - 1]
			m[i] = (w1 + w2) / (w1 / d[i - 1] + w2 / d[i])

	def f(x):
		if x <= xs[0]:
			return ys[0]
		if x >= xs[-1]:
			return ys[-1]
		i = max(j for j in range(n - 1) if xs[j] <= x)
		t = (x - xs[i]) / h[i]
		t2, t3 = t * t, t * t * t
		return ((2 * t3 - 3 * t2 + 1) * ys[i] + (t3 - 2 * t2 + t) * h[i] * m[i]
			+ (-2 * t3 + 3 * t2) * ys[i + 1] + (t3 - t2) * h[i] * m[i + 1])
	return f


def link(name, bm, mats, sharp_all=False):
	if sharp_all:
		for e in bm.edges:
			e.smooth = False
	bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
	return C._link(name, bm, mats)


def grid(bm, rings, closed, mat_fn, apex0=None, apex1=None, cap0=None, cap1=None):
	vr = [[bm.verts.new(Vector(p)) for p in r] for r in rings]
	n = len(vr[0])
	span = n if closed else n - 1
	for i in range(len(vr) - 1):
		for j in range(span):
			f = bm.faces.new((vr[i][j], vr[i][(j + 1) % n], vr[i + 1][(j + 1) % n], vr[i + 1][j]))
			f.material_index = mat_fn(i, j)
	for apex, ring, mi in ((apex0, vr[0], 0), (apex1, vr[-1], 1)):
		if apex is None:
			continue
		a = bm.verts.new(Vector(apex[0]))
		for j in range(span):
			f = bm.faces.new((ring[j], ring[(j + 1) % n], a))
			f.material_index = apex[1] if isinstance(apex[1], int) else apex[1](j)
	for cap, ring in ((cap0, vr[0]), (cap1, vr[-1])):
		if cap is not None:
			f = bm.faces.new(ring)
			f.material_index = cap
	return vr


class Body:
	"""Centreline hull. keys: (y, half_width, z_top, z_chine, z_keel), any order.
	Upper skin z = zc + (zt-zc)(1-u^a)^b, lower mirrors it with (a2, b2); b<1 bulges, b>1 pinches
	toward a knife chine."""

	def __init__(self, keys, a=2.0, b=0.7, a2=2.0, b2=0.9, nu=12, nl=7, x0=0.0):
		ks = sorted(keys)
		self.y0, self.y1 = ks[0][0], ks[-1][0]
		self.f = [pchip([(k[0], k[i]) for k in ks]) for i in range(1, 5)]
		self.a, self.b, self.a2, self.b2, self.nu, self.nl, self.x0 = a, b, a2, b2, nu, nl, x0

	def prof(self, y):
		w, zt, zc, zb = (f(y) for f in self.f)
		return max(w, 0.0), zt, zc, zb

	def up(self, y, u):
		w, zt, zc, _ = self.prof(y)
		u = min(max(u, 0.0), 1.0)
		return Vector((self.x0 + w * u, y, zc + (zt - zc) * max(1 - u ** self.a, 0.0) ** self.b))

	def lo(self, y, v):
		w, _, zc, zb = self.prof(y)
		v = min(max(v, 0.0), 1.0)
		return Vector((self.x0 + w * v, y, zc - (zc - zb) * max(1 - v ** self.a2, 0.0) ** self.b2))

	def normal_up(self, y, u):
		e = 1e-3
		p = self.up(y, u)
		du = self.up(y, min(u + e, 1.0)) - self.up(y, max(u - e, 0.0))
		dy = self.up(y + e * 10, u) - self.up(y - e * 10, u)
		n = dy.cross(du)
		if du.length < 1e-9:
			n = Vector((0, 0, 1))
		n.normalize()
		if n.dot(p - Vector((self.x0, y, self.prof(y)[2] - 1.0))) < 0:
			n = -n
		return n

	def half(self, y):
		us = [math.sin(0.5 * math.pi * i / self.nu) for i in range(self.nu + 1)]
		vs = [math.sin(0.5 * math.pi * i / self.nl) for i in range(self.nl)]
		return [self.up(y, u) for u in us] + [self.lo(y, v) for v in reversed(vs)]

	def ring(self, y):
		h = self.half(y)
		return h + [Vector((2 * self.x0 - p.x, p.y, p.z)) for p in reversed(h[1:-1])]

	def build(self, name, stations=60, nose_bias=1.35, tail_cap=1, paint=0, dark=1, y_cut=None, open_front=False):
		ye = self.y0 if y_cut is None else y_cut
		ys = [self.y1 - (self.y1 - ye) * (i / stations) ** nose_bias for i in range(0 if open_front else 1, stations + 1)]
		rings = [self.ring(y) for y in ys]
		nu = self.nu
		m = len(rings[0])

		def mat(i, j):
			return paint if j < nu or j >= m - nu else dark
		bm = bmesh.new()
		apex = (Vector((self.x0, self.y1, self.prof(self.y1)[2])), lambda j: mat(0, j))
		grid(bm, rings, True, mat, apex0=None if open_front else apex, cap1=tail_cap)
		ob = link(name, bm, ["Hull_Paint", "Hull_Dark", "Hull_Steel"])
		if abs(self.x0) > 1e-4:
			C.mirror(ob)
		return ob


def airfoil(n=7):
	cs = [(1 - math.cos(math.pi * i / n)) / 2 for i in range(n + 1)]
	hs = [(c ** 0.6) * (1 - c) ** 0.85 for c in cs]
	k = 0.5 / max(hs)
	return [(c, h * k) for c, h in zip(cs, hs)]


def blade(name, stations, mats=("Hull_Paint", "Hull_Dark"), mirror=True, spans=3, n=7, chord_dir=(0, -1, 0), tip_light=True, light_scale=1.0):
	"""stations: (leading_edge, chord, thickness, thickness_axis). Knife leading/trailing edges."""
	cd = Vector(chord_dir).normalized()
	st = [(Vector(s[0]), s[1], s[2], Vector(s[3] if len(s) > 3 else (0, 0, 1)).normalized()) for s in stations]
	dense = [st[0]]
	for a, b in zip(st, st[1:]):
		for k in range(1, spans + 1):
			t = k / spans
			dense.append((a[0].lerp(b[0], t), a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t, a[3].lerp(b[3], t).normalized()))
	af = airfoil(n)
	rings = []
	for p, chord, th, nrm in dense:
		upper = [p + cd * (c * chord) + nrm * (h * th) for c, h in af]
		lower = [p + cd * (c * chord) - nrm * (h * th) for c, h in reversed(af[1:-1])]
		rings.append(upper + lower)
	bm = bmesh.new()
	grid(bm, rings, True, lambda i, j: 0 if j < n else 1, cap0=1, cap1=1)
	ob = link(name, bm, list(mats))
	if mirror:
		C.mirror(ob)
	if tip_light:
		p, chord, th, nrm = dense[-1]
		prev = dense[-2][0]
		out = (p - prev)
		out = (out - out.project(cd)).normalized()
		lb = bmesh.new()
		ctr = p + cd * (chord * 0.3) + out * (0.18 * th + 0.05)
		box(lb, ctr, cd, out, nrm, (chord * 0.42 * light_scale, 0.22 * th + 0.12, th * 0.55 + 0.05))
		lo = link(name + "_Tip", lb, ["Accent_Emit"])
		if mirror:
			C.mirror(lo)
	return ob


def box(bm, ctr, ax, ay, az, size):
	ax, ay, az = Vector(ax).normalized(), Vector(ay).normalized(), Vector(az).normalized()
	m = Matrix((
		(ax.x * size[0], ay.x * size[1], az.x * size[2], ctr[0]),
		(ax.y * size[0], ay.y * size[1], az.y * size[2], ctr[1]),
		(ax.z * size[0], ay.z * size[1], az.z * size[2], ctr[2]),
		(0, 0, 0, 1)))
	return bmesh.ops.create_cube(bm, size=1.0, matrix=m)


def boxes(name, items, mats, mirror=True, bevel_w=0.0):
	bm = bmesh.new()
	for ctr, ax, ay, az, size, mi in items:
		r = box(bm, ctr, ax, ay, az, size)
		for f in {f for v in r["verts"] for f in v.link_faces}:
			f.material_index = mi
	ob = link(name, bm, list(mats))
	if mirror:
		C.mirror(ob)
	if bevel_w:
		C.bevel(ob, bevel_w, seg=1)
	return ob


def engine(name, x, z, yf, yr, r, seg=24, sx=1.0, sz=1.0, mirror=None, cowl="Hull_Dark", depth=None):
	"""Nacelle with dark intake, steel collar and a recessed Nozzle_Emit bell. Returns mouth centre."""
	ln = yf - yr
	d = depth if depth is not None else min(0.14 * ln, 1.6 * r)
	prof = [
		(yf - 0.05 * ln, 0.55, 1), (yf, 0.8, 1), (yf - 0.02 * ln, 0.97, 0), (yf - 0.1 * ln, 1.0, 0),
		(yr + 0.2 * ln, 1.0, 2), (yr + 0.17 * ln, 0.95, 0), (yr + 0.08 * ln, 0.95, 2), (yr + 0.02 * ln, 0.9, 2),
		(yr, 0.86, 2), (yr, 0.76, 2), (yr + 0.35 * d, 0.7, 3), (yr + d, 0.5, 3),
	]
	rings = [[Vector((x + r * f * sx * math.cos(2 * math.pi * (j + 0.5) / seg), y, z + r * f * sz * math.sin(2 * math.pi * (j + 0.5) / seg))) for j in range(seg)] for y, f, _ in prof]
	bands = [p[2] for p in prof]
	bm = bmesh.new()
	grid(bm, rings, True, lambda i, j: bands[i], cap0=1, cap1=3)
	ob = link(name, bm, [cowl, "Hull_Dark", "Hull_Steel", "Nozzle_Emit"])
	if mirror if mirror is not None else x > 0.01:
		C.mirror(ob)
	return Vector((x, yr, z))


def tube(name, path, ups, width, height, mat, mirror=True, sharp=True, sink=0.35):
	bm = bmesh.new()
	rings = []
	for i, p in enumerate(path):
		p = Vector(p)
		a = Vector(path[max(i - 1, 0)])
		b = Vector(path[min(i + 1, len(path) - 1)])
		t = (b - a).normalized()
		n = Vector(ups[i]).normalized()
		s = t.cross(n).normalized()
		w = width[i] if isinstance(width, (list, tuple)) else width
		h = height[i] if isinstance(height, (list, tuple)) else height
		rings.append([p + s * (-w / 2) - n * (h * sink), p + s * (w / 2) - n * (h * sink), p + s * (w / 2) + n * h, p + s * (-w / 2) + n * h])
	grid(bm, rings, True, lambda i, j: 0, cap0=0, cap1=0)
	ob = link(name, bm, [mat], sharp_all=sharp)
	if mirror:
		C.mirror(ob)
	return ob


def chine_strip(name, body, y0, y1, u, width, height, n=24, mat="Accent_Emit"):
	ys = [y0 + (y1 - y0) * i / n for i in range(n + 1)]
	path = [body.up(y, u) for y in ys]
	ups = [body.normal_up(y, u) for y in ys]
	return tube(name, path, ups, width, height, mat)


def strake(name, body, y0, y1, lip, thick, n=24):
	"""Knife flange riding the body chine; lip may be a function of y."""
	bm = bmesh.new()
	rings = []
	for i in range(n + 1):
		y = y0 + (y1 - y0) * i / n
		w, zt, zc, zb = body.prof(y)
		L = lip(y) if callable(lip) else lip
		inner = body.x0 + w * 0.8
		rings.append([Vector((inner, y, zc + thick)), Vector((body.x0 + w + L * 0.55, y, zc + thick * 0.45)), Vector((body.x0 + w + L, y, zc)),
			Vector((body.x0 + w + L * 0.55, y, zc - thick * 0.45)), Vector((inner, y, zc - thick))])
	grid(bm, rings, True, lambda i, j: 0 if j < 2 else 1, cap0=1, cap1=1)
	ob = link(name, bm, ["Hull_Paint", "Hull_Dark"])
	C.mirror(ob)
	return ob


def plate(name, body, y0, y1, u0, u1, lift, ny=10, nu=6, mat="Hull_Paint", wall="Hull_Steel", bevel_w=None, lower=False):
	"""Raised armour plate following the skin. u0/u1: scalar or (front, back) for angled edges."""
	u0f, u0b = (u0, u0) if not isinstance(u0, tuple) else u0
	u1f, u1b = (u1, u1) if not isinstance(u1, tuple) else u1
	centre = u0f == 0 and u0b == 0

	def pt(i, j, off):
		t = i / ny
		y = y0 + (y1 - y0) * t
		a = u0f + (u0b - u0f) * t
		b = u1f + (u1b - u1f) * t
		u = a + (b - a) * j / nu
		p = body.up(y, u)
		return p + body.normal_up(y, u) * off
	bm = bmesh.new()
	top = [[bm.verts.new(pt(i, j, lift)) for j in range(nu + 1)] for i in range(ny + 1)]
	bot = [[bm.verts.new(pt(i, j, -lift * 0.6)) for j in range(nu + 1)] for i in range(ny + 1)]
	for i in range(ny):
		for j in range(nu):
			bm.faces.new((top[i][j], top[i][j + 1], top[i + 1][j + 1], top[i + 1][j])).material_index = 0
	border = [(i, 0) for i in range(ny + 1)] if not centre else []
	edges = []
	for j in range(nu):
		edges.append(((0, j), (0, j + 1)))
		edges.append(((ny, j + 1), (ny, j)))
	for i in range(ny):
		edges.append(((i, nu), (i + 1, nu)))
		if not centre:
			edges.append(((i + 1, 0), (i, 0)))
	for (a, b) in edges:
		bm.faces.new((top[a[0]][a[1]], top[b[0]][b[1]], bot[b[0]][b[1]], bot[a[0]][a[1]])).material_index = 1
	bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context="VERTS")
	ob = link(name, bm, [mat, wall])
	C.mirror(ob)
	if bevel_w:
		C.bevel(ob, bevel_w, seg=1, angle=40)
	return ob


def canopy(name, yf, yb, zfn, w, h, frame_w, bars=True):
	"""Family canopy: slim faceted glass blister with dark frame rails and a forward hoop."""
	half = [(1.0, 0.0), (0.86, 0.45), (0.5, 0.86), (0.0, 1.0)]
	keys = [(0.0, 0.05, 0.05), (0.1, 0.4, 0.38), (0.3, 0.82, 0.8), (0.55, 1.0, 1.0), (0.8, 0.9, 0.82), (1.0, 0.5, 0.3)]
	rings = []
	for t, sw, sh in keys:
		y = yf + (yb - yf) * t
		zb = zfn(y) - 0.25 * h
		pts = [(x * w * sw, zb + z * (h * sh + 0.25 * h)) for x, z in half]
		full = pts + [(-x, z) for x, z in reversed(pts[:-1])]
		rings.append([Vector((x, y, z)) for x, z in full])
	bm = bmesh.new()
	grid(bm, rings, True, lambda i, j: 0, cap0=0, cap1=0)
	link(name, bm, ["Glass"], sharp_all=True)
	if not bars:
		return
	for k, nm in ((1, "Rail"), (2, "Rail2")):
		path = [r[k] for r in rings[1:]]
		ups = [(Vector((r[k].x, 0, r[k].z - r[0].z)).normalized()) for r in rings[1:]]
		tube(name + nm, path, ups, frame_w, frame_w * 0.5, "Hull_Dark", mirror=True)
	path = [r[3] for r in rings[1:]]
	tube(name + "Spine", path, [(0, 0, 1)] * len(path), frame_w * 0.8, frame_w * 0.45, "Hull_Dark", mirror=False)
	hoop = rings[2]
	hy = hoop[0].y
	pts = [Vector((p.x * 1.03, hy, rings[2][0].z + (p.z - rings[2][0].z) * 1.04)) for p in hoop[:4]] + [Vector((-p.x * 1.03, hy, rings[2][0].z + (p.z - rings[2][0].z) * 1.04)) for p in reversed(hoop[:3])]
	c = Vector((0, hy, rings[2][0].z))
	ups = [(p - c).normalized() for p in pts]
	tube(name + "Hoop", pts, ups, frame_w * 1.2, frame_w * 0.55, "Hull_Dark", mirror=False)


def slots(name, centres, normal_fn, size, pitch_axis=(0, 1, 0), mat=1, mirror=True):
	items = []
	for c in centres:
		n = normal_fn(c)
		ay = Vector(pitch_axis)
		ax = ay.cross(n)
		items.append((c, ax, ay, n, size, mat))
	return boxes(name, items, ["Hull_Steel", "Hull_Dark", "Accent_Emit"], mirror=mirror)


def seam(name, body, pts, width, height, n=None, mirror=True, mat="Hull_Dark"):
	"""Panel seam drawn on the upper skin through (y, u) waypoints."""
	path, ups = [], []
	for (ya, ua), (yb, ub) in zip(pts, pts[1:]):
		k = n or max(2, int(abs(ya - yb) / 1.5) + 2)
		for i in range(k):
			t = i / k
			y, u = ya + (yb - ya) * t, ua + (ub - ua) * t
			path.append(body.up(y, u))
			ups.append(body.normal_up(y, u))
	path.append(body.up(*pts[-1]))
	ups.append(body.normal_up(*pts[-1]))
	return tube(name, path, ups, width, height, mat, mirror=mirror, sink=1.0)
