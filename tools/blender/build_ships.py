"""Builds the Astryx modular hulls (contract: docs/specs/2026-09-26-ship-roster-and-modules.md).

  blender -b --python tools/blender/build_ships.py -- [--ship <tier>] [--out <dir>] [--blend-out <dir>]

Family language: analytic lofted hull with a knife chine (Hull_Paint above, Hull_Dark below), a
blade strake riding the chine with an Accent_Emit strip along it, raised armour plates with steel
edges, a slim faceted canopy with dark rails, blade wings/fins that each carry a tip light, and
dark engine housings ending in recessed Nozzle_Emit bells.
"""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import ship_common as C  # noqa: E402
import sleek as S  # noqa: E402
from mathutils import Matrix, Vector  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(os.path.dirname(os.path.dirname(HERE)), "assets", "ships")
SOURCES = os.path.join(HERE, "sources")

ROSTER = {
	1: dict(slug="wren", name="Wren", length=60, BOOSTER=1, RCS=4, WEAPON=2, PAD=3, LANDJET=4),
	2: dict(slug="kestrel", name="Kestrel", length=70, BOOSTER=2, RCS=4, WEAPON=2, PAD=3, LANDJET=4),
	3: dict(slug="swift", name="Swift", length=80, BOOSTER=2, RCS=6, WEAPON=2, PAD=4, LANDJET=4),
	4: dict(slug="harrier", name="Harrier", length=95, BOOSTER=2, RCS=6, WEAPON=4, PAD=4, LANDJET=6),
	5: dict(slug="osprey", name="Osprey", length=120, BOOSTER=3, RCS=8, WEAPON=4, PAD=4, LANDJET=6),
	6: dict(slug="condor", name="Condor", length=150, BOOSTER=4, RCS=8, WEAPON=6, PAD=6, LANDJET=8),
	7: dict(slug="albatross", name="Albatross", length=200, BOOSTER=4, RCS=8, WEAPON=6, PAD=6, LANDJET=8),
	8: dict(slug="sovereign", name="Sovereign", length=240, BOOSTER=4, RCS=8, WEAPON=8, PAD=6, LANDJET=8, tri_budget=30000),
}

X, UP, DOWN = Vector((1, 0, 0)), Vector((0, 0, 1)), Vector((0, 0, -1))


class Kit:
	def __init__(self, length):
		self.L = length
		self.s = length / 60.0
		self.bw = length * 0.0022
		self.count = {k: 0 for k in C.SOCKET_KINDS}

	def hull(self, name, body, stations=60, bevel=True, **kw):
		ob = body.build(name, stations=stations, **kw)
		if bevel:
			C.bevel(ob, self.bw, seg=2, angle=28)
		return ob

	def blade(self, name, stations, **kw):
		ob = S.blade(name, stations, **kw)
		C.bevel(ob, self.bw * 0.35, seg=1, angle=50)
		return ob

	def fin(self, name, stations, **kw):
		return self.blade(name, stations, mats=("Hull_Paint", "Hull_Paint"), **kw)

	def armor_panel(self, name, points):
		lower = [Vector(p) for p in points]
		upper = [p + UP * .20 * self.s for p in lower]
		ob = C.loft(name, [lower, upper], ["Hull_Paint", "Hull_Steel"], band=[1])
		C.mirror(ob)
		C.bevel(ob, .08 * self.s, seg=1)
		return ob

	def fairing(self, name, x, z, yf, yr, r, sx=1.0, sz=1.0, nose=0.3, open_front=False):
		ln = yf - yr
		w0 = r * sx * 1.02 if open_front else 0.0
		keys = [(yf, w0, z + (r * sz * 1.04 if open_front else 0.0), z, z - (r * sz * 1.0 if open_front else 0.0)),
			(yf - nose * ln, r * sx * 1.1, z + r * sz * 1.14, z, z - r * sz * 1.06),
			(yr + 0.12 * ln, r * sx * 1.12, z + r * sz * 1.14, z, z - r * sz * 1.06), (yr, r * sx * 1.04, z + r * sz * 1.06, z, z - r * sz * 1.0)]
		b = S.Body(keys, a=2.0, b=0.5, a2=2.0, b2=0.6, nu=10, nl=6, x0=x)
		self.hull(name, b, stations=28, nose_bias=1.0, tail_cap=None, open_front=open_front)
		return b

	def chine(self, body, y0, y1, lip, thick=None, strip_u=0.9):
		thick = thick or 0.12 * self.s
		S.strake("Strake", body, y0, y1, lip, thick)
		S.chine_strip("ChineLight", body, y0 - .18 * (y0 - y1), y1 + .42 * (y0 - y1), strip_u, .16 * self.s, .035 * self.s)

	def engine_deck(self, body, yf, yr, width, z, height):
		length = yf - yr
		deck = S.Body([
			(yf, 0.0, z, z, z),
			(yf - length * .23, width * .10, z + height * .28, z, z - height * .2),
			(yf - length * .6, width * .12, z + height * .3, z, z - height * .2),
			(yr, width * .09, z + height * .2, z, z - height * .18)],
			a=3.0, b=.5, a2=3.0, b2=.6, nu=4, nl=3)
		self.hull("EngineKeel", deck, stations=12)
		shoulder_keys = []
		for t, spread in ((0, 0.0), (.18, .65), (.43, 1.0), (.82, .92), (1, .72)):
			y = yf - length * t
			upper = body.prof(y)[1] * .82 + .55 * self.s
			shoulder_keys.append((y, width * .42 * spread, upper, z + height * .30, z + height * .06))
		shoulder = S.Body(shoulder_keys, a=3.8, b=.35, a2=2.8, b2=.5, nu=4, nl=3, x0=width * .48)
		self.hull("EngineShoulder", shoulder, stations=16)
		for i, (front, rear) in enumerate(((.22, .41), (.45, .64), (.68, .88))):
			S.plate("ShoulderArmor%d" % i, shoulder, yf - length * front, yf - length * rear,
				(.12, .2), (.83, .9), .20 * self.s, ny=3, nu=2, bevel_w=.05 * self.s,
				mat="Hull_Dark" if i == 1 else "Hull_Paint")
		vent_y = [yf - length * (.49 + .032 * i) for i in range(6)]
		self.vents(shoulder, vent_y, .57, (1.2, .35, .16), name="ShoulderRadiators")
		S.chine_strip("EngineShoulderLight", shoulder, yf - length * .28, yr + length * .16, .98, .12 * self.s, .035 * self.s, n=14)
		return deck

	def canopy(self, body, yf, yb, w, h):
		S.canopy("Canopy", yf, yb, lambda y: body.up(y, 0.0).z, w, h, 0.18 * self.s)

	def plates(self, body, specs, lift=None):
		lift = lift or 0.16 * self.s
		for i, (y0, y1, u0, u1) in enumerate(specs):
			S.plate("Plate%d" % i, body, y0, y1, u0, u1, lift, ny=8, nu=4, bevel_w=lift * 0.4)

	def seams(self, body, lines):
		for i, pts in enumerate(lines):
			S.seam("Seam%d" % i, body, pts, 0.07 * self.s, 0.035 * self.s, mirror=pts[0][1] > 0.001 or pts[-1][1] > 0.001)

	def vents(self, body, ys, u, size, name="Vents", mirror=True):
		cs = [body.up(y, u) for y in ys]
		S.slots(name, cs, lambda c: body.normal_up(c.y, u), tuple(v * self.s for v in size), mat=1, mirror=mirror)

	def sock(self, kind, loc, exhaust=None):
		i = self.count[kind]
		self.count[kind] += 1
		if kind == "RCS":
			axis = Vector(exhaust).normalized()
			p = Vector(loc)
			r = self.L * 0.0055
			rings = [C.circle(p + axis * d, axis, radius, 12) for d, radius in
				((-r * 0.6, r * 1.2), (r * 0.25, r * 1.05), (r * 0.25, r * 0.72), (-r * 0.3, r * 0.6))]
			C.loft("RcsNozzle", rings, ["Hull_Dark", "Hull_Steel"], band=[0, 1, 0], caps=(0, 0))
			loc = p + axis * r * 0.25
		return C.socket(kind, i, loc, exhaust, size=2.0 * self.s)

	def belly(self, x, y):
		return C.surface((x, y, -400), UP)

	def top(self, x, y):
		return C.surface((x, y, 400), DOWN)

	def side(self, sign, y, z):
		return C.surface((sign * 400, y, z), (-sign, 0, 0))

	def pair(self, kind, finder, exhaust=None):
		for sign in (-1, 1):
			ex = X * sign if exhaust == "lateral" else exhaust
			self.sock(kind, finder(sign), ex)


def wren(k):
	b = S.Body([
		(30, 0.0, 0.0, 0.0, 0.0), (28, 1.0, 0.5, 0.0, -0.35), (22, 3.2, 1.9, 0.1, -1.3),
		(14, 5.0, 3.2, 0.2, -2.1), (4, 6.2, 3.8, 0.25, -2.5), (-8, 6.6, 3.6, 0.25, -2.5),
		(-18, 5.6, 3.1, 0.25, -2.2), (-25, 4.0, 2.6, 0.25, -1.8)], a=2.0, b=0.55, b2=0.8)
	k.hull("Hull", b)
	k.chine(b, 25, -12, lambda y: 0.4 + 1.3 * max(0.0, (12 - y) / 24))
	k.canopy(b, 18.5, 5, 2.0, 1.5)
	boost = S.engine("Engine", 0, 0.5, -6, -30, 2.5, seg=28, sx=1.3, sz=0.95)
	k.fairing("Pod", 0, 0.5, 4, -27.5, 2.5, sx=1.3, sz=0.95, nose=0.35)
	k.blade("Wing", [((5.5, 6, 0.1), 24, 1.0), ((13, -8, 0.3), 12, 0.55), ((20, -17, 0.55), 4.0, 0.24)])
	cant = Vector((1, 0, 0.32)).normalized()
	k.fin("Fin", [((3.0, -12, 2.9), 12.0, 0.45, cant), ((7.4, -22, 8.6), 3.8, 0.2, cant)], spans=4)
	k.plates(b, [(4, -4, (0.0, 0.0), (0.4, 0.46)), (-6, -21, (0.0, 0.0), (0.46, 0.36)),
		(2, -16, (0.52, 0.5), (0.8, 0.74)), (21, 13, (0.42, 0.5), (0.8, 0.84))])
	k.seams(b, [[(24, 0.3), (19, 0.62), (8, 0.62), (2, 0.9)], [(12, 0.0), (8, 0.3)]])
	k.vents(b, [-6 - 1.3 * i for i in range(5)], 0.9, (1.0, 0.45, 0.12))
	k.sock("BOOSTER", boost)
	k.pair("RCS", lambda s: k.side(s, 21, 0.1), "lateral")
	k.pair("RCS", lambda s: k.side(s, -20, 0.2), "lateral")
	k.pair("WEAPON", lambda s: k.belly(9.0 * s, -6))
	k.pair("PAD", lambda s: k.belly(4.4 * s, -14))
	k.sock("PAD", k.belly(0, 17))
	k.pair("LANDJET", lambda s: k.belly(2.8 * s, 8))
	k.pair("LANDJET", lambda s: k.belly(3.4 * s, -19))


def kestrel(k):
	b = S.Body([
		(35, 0.0, 0.2, 0.2, 0.2), (33, .6, .7, .2, 0.0), (26, 2.4, 1.8, .2, -1.0),
		(16, 4.8, 3.0, .3, -1.6), (6, 6.0, 3.8, .35, -2.0), (-6, 6.4, 3.6, .35, -2.1),
		(-16, 6.6, 3.2, .35, -1.9), (-28, 4.8, 2.4, .3, -1.6), (-35, 3.2, 1.9, .3, -.5)], a=2.4, b=.55, b2=.8)
	k.hull("Hull", b, stations=64)
	k.chine(b, 31, -10, lambda y: 0.25 + 1.5 * max(0.0, (31 - y) / 41))
	k.canopy(b, 16, 2, 2.0, 1.4)
	k.engine_deck(b, 4, -27, 4.25, -2.8, 2.7)
	boost = S.engine("Engine", 2.05, -2.8, -8, -31, 1.8, seg=24)
	k.fairing("Pod", 2.05, -2.8, 2, -28.5, 1.8, nose=0.4)
	k.blade("Wing", [((5.5, 2, .3), 25, 1.15), ((19.5, -16, .1), 9, .45)], spans=4)
	k.armor_panel("WingArmor", [(6.5, 0, .92), (10, -1, .85), (17, -13, .6), (18, -18, .5), (13, -20, .64), (7.5, -9, .95)])
	cant = Vector((1, 0, .35)).normalized()
	k.fin("Fin", [((5.2, -16, 2.8), 12, .5, cant), ((7.2, -25, 6.4), 4, .2, cant)], spans=3)
	vn = Vector((0.85, 0, 0.53))
	k.fin("Ventral", [((2.3, -19, -1.4), 9, 0.35, vn), ((4.0, -25, -4.0), 3.5, 0.16, vn)], mirror=True, spans=2)
	k.plates(b, [(0, -14, (0.0, 0.0), (0.38, 0.3)), (-15, -27, (0.0, 0.0), (0.35, 0.3)),
		(10, -12, (0.5, 0.5), (0.82, 0.78)), (28, 17, (0.35, 0.3), (0.8, 0.8))])
	k.seams(b, [[(30, 0.2), (22, 0.5), (15, 0.5)], [(-2, 0.45), (-14, 0.9)]])
	k.vents(b, [-14 - 1.2 * i for i in range(5)], 0.72, (0.9, 0.4, 0.12))
	k.pair("BOOSTER", lambda s: Vector((2.05 * s, boost.y, boost.z)))
	k.pair("RCS", lambda s: k.side(s, 25, 0.15), "lateral")
	k.pair("RCS", lambda s: k.side(s, -21, 0.2), "lateral")
	k.pair("WEAPON", lambda s: k.belly(6.0 * s, -12))
	k.pair("PAD", lambda s: k.belly(3.0 * s, -16))
	k.sock("PAD", k.belly(0, 18))
	k.pair("LANDJET", lambda s: k.belly(1.5 * s, 8))
	k.pair("LANDJET", lambda s: k.belly(1.2 * s, -22))


def swift(k):
	b = S.Body([
		(40, 0.0, 0.1, 0.1, 0.1), (37, 1.6, 0.8, 0.1, -0.35), (30, 4.8, 1.8, 0.1, -1.0),
		(20, 8.5, 2.8, 0.15, -1.7), (8, 12, 3.3, 0.15, -2.0), (-6, 14, 3.2, 0.15, -2.0),
		(-20, 12.5, 2.8, 0.15, -1.8), (-32, 9, 2.2, 0.15, -1.4), (-40, 7, 1.9, 0.15, -.7)],
		a=1.6, b=1.25, a2=1.8, b2=1.2, nu=14, nl=8)
	k.hull("Hull", b, stations=60)
	k.chine(b, 34, -30, lambda y: 0.3 + 0.5 * max(0.0, (34 - y) / 64), strip_u=0.86)
	k.canopy(b, 27, 14, 1.8, 1.4)
	k.engine_deck(b, 0, -29, 6.65, -2.8, 2.8)
	boost = S.engine("Engine", 3.6, -2.8, -12, -34, 1.65, seg=24, sx=1.35, sz=0.8)
	k.fairing("Pod", 3.6, -2.8, -4, -31.5, 1.65, sx=1.35, sz=0.8, nose=0.4)
	k.blade("Wing", [((11, 4, 0.12), 30, 1.2), ((22, -12, 0.35), 16, 0.6), ((30, -22, 0.8), 6, 0.25)])
	k.armor_panel("WingArmor", [(14, -2, .9), (18, -4, .88), (26, -19, 1.05), (27, -24, 1.02), (22, -25, .85), (15, -14, .86)])
	cant = Vector((1, 0, 0.45)).normalized()
	k.fin("Fin", [((7.5, -22, 1.8), 12, 0.4, cant), ((11.5, -32, 7.5), 4, 0.18, cant)], spans=3)
	k.plates(b, [(12, -4, (0.0, 0.0), (0.18, 0.2)), (-6, -30, (0.0, 0.0), (0.2, 0.24)),
		(10, -16, (0.32, 0.34), (0.62, 0.6)), (26, 15, (0.3, 0.28), (0.55, 0.6))])
	k.seams(b, [[(32, 0.25), (20, 0.45), (-10, 0.45), (-22, 0.7)], [(4, 0.62), (-12, 0.9)]])
	k.vents(b, [-8 - 1.4 * i for i in range(6)], 0.28, (1.2, 0.5, 0.12))
	k.pair("BOOSTER", lambda s: Vector((3.6 * s, boost.y, boost.z)))
	k.pair("RCS", lambda s: k.side(s, 28, 0.1), "lateral")
	k.pair("RCS", lambda s: k.side(s, -25, 0.8), "lateral")
	k.pair("RCS", lambda s: k.top(6 * s, -30), UP)
	k.pair("WEAPON", lambda s: k.belly(16 * s, -8))
	k.pair("PAD", lambda s: k.belly(5 * s, 20))
	k.pair("PAD", lambda s: k.belly(8 * s, -20))
	k.pair("LANDJET", lambda s: k.belly(3 * s, 8))
	k.pair("LANDJET", lambda s: k.belly(5 * s, -28))


def harrier(k):
	b = S.Body([
		(47.5, 0.0, 0.3, 0.3, 0.3), (45, 0.6, 0.8, 0.3, -0.2), (38, 2.2, 2.2, 0.3, -1.2),
		(28, 3.6, 3.5, 0.4, -2.1), (16, 4.4, 4.2, 0.5, -2.5), (0, 4.8, 4.0, 0.5, -2.5),
		(-20, 4.6, 3.4, 0.5, -2.3), (-36, 3.2, 2.6, 0.5, -1.7), (-47.5, 1.8, 2.0, 0.5, -1.2)], a=2.0, b=0.6, b2=0.8)
	k.hull("Hull", b, stations=64)
	k.chine(b, 44, 12, lambda y: 0.4 + 1.8 * max(0.0, (44 - y) / 32) ** 1.5)
	S.strake("Glove", b, 30, -38, lambda y: min(0.4 + 6.0 * max(0.0, (30 - y) / 16), 7.2 - b.prof(y)[0]), 0.35)
	k.canopy(b, 36.5, 22, 2.2, 1.7)
	k.engine_deck(b, 17, -33, 9.0, -4.5, 4.5)
	boost = S.engine("Engine", 5.5, -4.5, 14, -37, 2.4, seg=28, sz=1.1)
	k.fairing("Nacelle", 5.5, -4.5, 12.5, -34.5, 2.4, sz=1.1, nose=0.12, open_front=True)
	k.blade("Wing", [((4, 4, 0.9), 30, 1.4), ((16, -8, 0.8), 17, 0.8), ((27, -17, 0.5), 7, 0.3)])
	k.armor_panel("WingArmor", [(10, -1, 1.8), (14, -3, 1.6), (24, -16, .91), (25, -20, .85), (19, -23, 1.0), (11, -15, 1.5)])
	k.blade("Canard", [((3.5, 28, 1.4), 9, 0.5), ((12.5, 22.5, 1.9), 3.5, 0.2)], spans=2)
	cant = Vector((1, 0, 0.25)).normalized()
	k.fin("Tail", [((7.6, -27, 3.4), 15, 0.5, cant), ((11, -39, 13), 5.5, 0.2, cant)], spans=4)
	k.plates(b, [(20, 4, (0.0, 0.0), (0.4, 0.45)), (2, -18, (0.0, 0.0), (0.45, 0.42)),
		(-20, -38, (0.0, 0.0), (0.5, 0.4)), (41, 31, (0.35, 0.35), (0.85, 0.85))])
	k.seams(b, [[(44, 0.2), (38, 0.6), (26, 0.6)], [(10, 0.5), (-6, 0.5), (-14, 0.9)]])
	k.vents(b, [-20 - 1.6 * i for i in range(5)], 0.62, (1.3, 0.5, 0.14))
	k.pair("BOOSTER", lambda s: Vector((5.5 * s, boost.y, boost.z)))
	k.pair("RCS", lambda s: k.side(s, 38, 0.3), "lateral")
	k.pair("RCS", lambda s: k.side(s, -20.5, 0.5), "lateral")
	k.pair("RCS", lambda s: k.top(5.0 * s, -30), UP)
	k.pair("WEAPON", lambda s: k.belly(13 * s, -9))
	k.pair("WEAPON", lambda s: k.belly(21 * s, -15))
	k.pair("PAD", lambda s: k.belly(7.2 * s, 8))
	k.pair("PAD", lambda s: k.belly(7.2 * s, -30))
	k.pair("LANDJET", lambda s: k.belly(2.5 * s, 30))
	k.pair("LANDJET", lambda s: k.belly(2.5 * s, 0))
	k.pair("LANDJET", lambda s: k.belly(2.5 * s, -30))


def osprey(k):
	b = S.Body([
		(60, 0.0, -0.5, -0.5, -0.5), (57, 1.6, 0.5, -0.5, -1.8), (48, 4.2, 2.4, -0.3, -3.9),
		(32, 6.6, 3.8, 0.0, -5.6), (10, 7.8, 4.4, 0.0, -6.2), (-16, 8.2, 4.4, 0.0, -6.2),
		(-40, 7.6, 4.0, 0.0, -5.8), (-60, 6.6, 3.6, 0.0, -5.2)], a=2.0, b=0.55, b2=0.7, nu=14, nl=8)
	k.hull("Hull", b, stations=60)
	sp = S.Body([
		(40, 0.0, 3.2, 3.2, 3.2), (32, 1.6, 6.8, 3.8, 1.5), (16, 3.0, 10.5, 4.0, 1.5),
		(-10, 3.4, 12.0, 4.0, 1.5), (-40, 3.2, 11.2, 4.0, 1.5), (-57, 2.6, 9.6, 3.8, 1.5)], a=2.4, b=0.4, nu=10, nl=4)
	k.hull("Spine", sp, stations=44)
	k.chine(b, 54, 0, lambda y: 0.5 + 1.7 * max(0.0, (54 - y) / 54))
	k.canopy(sp, 32, 18, 2.2, 1.6)
	k.fin("Keel", [((0, 36, -5.4), 78, 1.4, X), ((0, 22, -10.5), 62, 0.6, X)], mirror=False, spans=2, light_scale=0.4)
	k.fin("Dorsal", [((0, -36, 11.0), 15, 0.6, X), ((0, -49, 16.5), 5, 0.22, X)], mirror=False, spans=3)
	k.engine_deck(b, 1, -43, 9.1, -7.8, 5.2)
	side = S.engine("Engine", 5.8, -7.8, -24, -48, 2.9, seg=28)
	k.fairing("Pod", 5.8, -7.8, -4, -45.5, 2.9, nose=0.35)
	mid = S.engine("EngineC", 0, -7.8, -26, -54, 2.5, seg=24, mirror=False)
	an = Vector((0.3, 0, 1)).normalized()
	k.blade("Stab", [((6, -28, -1.5), 20, 1.0, an), ((17, -44, -4.8), 6, 0.3, an)], spans=4)
	k.plates(b, [(40, 10, (0.45, 0.42), (0.85, 0.85)), (6, -24, (0.45, 0.45), (0.86, 0.84))])
	k.plates(sp, [(14, -8, (0.0, 0.0), (0.6, 0.6)), (-12, -36, (0.0, 0.0), (0.6, 0.6)), (-38, -55, (0.0, 0.0), (0.55, 0.5))])
	k.seams(b, [[(52, 0.3), (44, 0.6), (20, 0.6), (12, 0.9)], [(-4, 0.5), (-30, 0.5)]])
	k.vents(sp, [-40 - 2 * i for i in range(6)], 0.8, (1.6, 0.6, 0.16))
	k.pair("BOOSTER", lambda s: Vector((5.8 * s, side.y, side.z)))
	k.sock("BOOSTER", mid)
	k.pair("RCS", lambda s: k.side(s, 46, 0.0), "lateral")
	k.pair("RCS", lambda s: k.top(2.0 * s, 46), UP)
	k.pair("RCS", lambda s: k.side(s, -48, 0.0), "lateral")
	k.pair("RCS", lambda s: k.belly(5 * s, -50), DOWN)
	k.pair("WEAPON", lambda s: k.belly(4.5 * s, 40))
	k.pair("WEAPON", lambda s: k.belly(11 * s, -40))
	k.pair("PAD", lambda s: k.belly(5.5 * s, 30))
	k.pair("PAD", lambda s: k.belly(5.5 * s, -24))
	k.pair("LANDJET", lambda s: k.belly(3 * s, 44))
	k.pair("LANDJET", lambda s: k.belly(3.5 * s, 0))
	k.pair("LANDJET", lambda s: k.belly(3.5 * s, -44))


def condor(k):
	b = S.Body([
		(75, 0.0, 0.0, 0.0, 0.0), (71, 3.0, 1.2, 0.0, -1.2), (58, 9.0, 3.6, 0.2, -3.4),
		(36, 15.0, 5.6, 0.3, -5.2), (10, 17.0, 6.4, 0.3, -6.0), (-20, 17.0, 6.4, 0.3, -6.0),
		(-44, 15.0, 6.0, 0.3, -5.6), (-60, 10.0, 5.0, 0.3, -4.2)], a=1.1, b=1.0, a2=2.0, b2=0.7, nu=14, nl=8)
	k.hull("Hull", b, stations=50)
	blk = S.Body([(-28, 0.0, 5.8, 5.8, 5.8), (-34, 6.0, 9.5, 5.6, 2.0), (-44, 9.5, 11.0, 5.6, 2.0), (-75, 10.0, 10.6, 5.6, 2.0)],
		a=5.0, b=0.35, nu=10, nl=4)
	k.hull("Block", blk, stations=30, nose_bias=1.0)
	tw = S.Body([(20, 0.0, 6.4, 6.4, 6.4), (14, 3.0, 10.0, 6.4, 4.0), (-8, 3.6, 10.6, 6.4, 4.0), (-22, 3.0, 9.8, 6.4, 4.0)], a=2.5, b=0.4, nu=8, nl=3)
	k.hull("Tower", tw, stations=26)
	k.chine(b, 70, -10, lambda y: 0.6 + 2.2 * max(0.0, (70 - y) / 80))
	k.canopy(tw, 17, 6, 2.6, 1.6)
	k.engine_deck(b, -12, -63, 14.2, -8.2, 6.2)
	up = S.engine("EngineU", 4.4, -8.2, -46, -68, 3.2, seg=28)
	lo = S.engine("EngineL", 10.7, -8.6, -40, -67, 3.0, seg=28)
	k.fairing("PodL", 10.7, -8.6, -18, -64.5, 3.0, nose=0.35)
	k.blade("Wing", [((14, -4, -0.5), 36, 2.0), ((36, -30, -1.5), 12, 0.6)], spans=4, tip_light=False)
	k.armor_panel("WingArmor", [(18, -11, .72), (24, -16, .36), (33, -31, -.82), (32, -36, -.65), (26, -35, -.35), (19, -26, .35)])
	k.fin("WingFin", [((35.6, -29, -1.0), 11, 0.5, X), ((36.4, -36, 6.0), 5, 0.22, X)], spans=2)
	k.plates(b, [(56, 26, (0.0, 0.0), (0.28, 0.32)), (54, 20, (0.4, 0.4), (0.8, 0.82)), (16, -18, (0.4, 0.4), (0.85, 0.85)), (-20, -42, (0.35, 0.35), (0.8, 0.8))])
	k.plates(blk, [(-36, -68, (0.0, 0.0), (0.42, 0.42)), (-38, -68, (0.52, 0.52), (0.9, 0.9))])
	k.seams(b, [[(68, 0.3), (50, 0.34), (30, 0.34), (22, 0.9)], [(-2, 0.3), (-26, 0.3)]])
	k.vents(blk, [-40 - 2.2 * i for i in range(7)], 0.47, (2.0, 0.7, 0.18))
	k.pair("BOOSTER", lambda s: Vector((4.4 * s, up.y, up.z)))
	k.pair("BOOSTER", lambda s: Vector((10.7 * s, lo.y, lo.z)))
	k.pair("RCS", lambda s: k.side(s, 60, 0.0), "lateral")
	k.pair("RCS", lambda s: k.top(3 * s, 60), UP)
	k.pair("RCS", lambda s: k.side(s, -58, -2.5), "lateral")
	k.pair("RCS", lambda s: k.belly(8 * s, -56), DOWN)
	k.pair("WEAPON", lambda s: k.belly(6 * s, 48))
	k.pair("WEAPON", lambda s: k.belly(22 * s, -20))
	k.pair("WEAPON", lambda s: k.belly(30 * s, -30))
	k.pair("PAD", lambda s: k.belly(7 * s, 44))
	k.pair("PAD", lambda s: k.belly(11 * s, 0))
	k.pair("PAD", lambda s: k.belly(9 * s, -40))
	k.pair("LANDJET", lambda s: k.belly(4 * s, 56))
	k.pair("LANDJET", lambda s: k.belly(5 * s, 20))
	k.pair("LANDJET", lambda s: k.belly(5 * s, -16))
	k.pair("LANDJET", lambda s: k.belly(5 * s, -50))


def albatross(k):
	b = S.Body([
		(100, 0.0, 0.3, 0.3, 0.3), (99, 4.0, 1.2, 0.3, -1.0), (93, 23, 2.8, 0.4, -2.4), (89, 25, 3.4, 0.4, -3.0),
		(85, 14, 4.6, 0.4, -4.2), (78, 10.5, 5.6, 0.4, -5.0), (68, 10.5, 6.0, 0.4, -5.4), (52, 11.5, 6.6, 0.4, -6.0), (24, 18, 7.6, 0.4, -7.0),
		(-16, 22, 8.2, 0.4, -7.6), (-56, 21, 8.0, 0.4, -7.4), (-78, 17, 7.2, 0.4, -6.8)], a=2.6, b=0.5, a2=2.4, b2=0.7, nu=14, nl=8)
	k.hull("Hull", b, stations=50, nose_bias=1.15)
	d1 = S.Body([(48, 0.0, 7.0, 6.6, 6.6), (40, 8, 12.5, 6.8, 3), (10, 13, 13.6, 7.2, 3), (-50, 14, 13.6, 7.4, 3), (-100, 11, 12.4, 7.2, 3)], a=3.4, b=.45, nu=10, nl=4)
	d2 = S.Body([(22, 0.0, 12.5, 12.5, 12.5), (14, 6.5, 17.5, 12.8, 9), (-30, 9, 18.2, 13, 9), (-66, 8, 17.4, 13, 9)], a=5.0, b=0.3, nu=10, nl=4)
	d3 = S.Body([(-16, 0.0, 17.5, 17.5, 17.5), (-22, 4, 23, 18, 15), (-44, 5, 23.6, 18.2, 15), (-58, 4, 22.4, 18, 15)], a=3.0, b=0.35, nu=8, nl=3)
	for nm, d in (("Deck1", d1), ("Deck2", d2), ("Deck3", d3)):
		k.hull(nm, d, stations=22, nose_bias=1.0)
	k.chine(b, 96, -40, lambda y: 0.6 + 2.6 * max(0.0, (96 - y) / 136))
	k.canopy(d3, -17.5, -39, 4.5, 2.8)
	k.engine_deck(b, -28, -79, 21.5, -10.5, 9.0)
	inner = S.engine("EngineI", 6.7, -10.5, -52, -84, 5.0, seg=32)
	outer = S.engine("EngineO", 16.5, -11.2, -50, -83, 4.4, seg=28)
	k.blade("Wing", [((20, -14, -0.5), 52, 2.6), ((50, -52, -2.5), 14, 0.7)], spans=5, tip_light=False)
	k.armor_panel("WingArmor", [(25, -22, 1.0), (31, -26, .6), (44, -45, -1.0), (47, -51, -1.1), (40, -55, -.8), (27, -41, .5)])
	k.fin("WingFin", [((49.5, -50, -2.0), 13, 0.6, X), ((50.5, -60, 8.0), 6, 0.25, X)], spans=2)
	k.fin("ProwFin", [((22, 91.5, 0.4), 7, 0.5, X), ((23, 88, 5.0), 4, 0.22, X)], spans=2)
	k.plates(b, [(60, 30, (0.5, 0.5), (0.9, 0.9)), (22, -10, (0.6, 0.6), (0.9, 0.9)), (-14, -50, (0.62, 0.62), (0.9, 0.9)),
		(95, 80, (0.0, 0.0), (0.35, 0.5)), (95, 81, (0.45, 0.55), (0.85, 0.9))])
	k.plates(d1, [(38, 14, (0.0, 0.0), (0.45, 0.45)), (36, -6, (0.55, 0.55), (0.92, 0.92))])
	k.plates(d2, [(8, -24, (0.0, 0.0), (0.4, 0.4)), (-34, -62, (0.0, 0.0), (0.4, 0.4))])
	k.seams(b, [[(90, 0.3), (80, 0.3), (70, 0.6), (40, 0.6)], [(-20, 0.5), (-70, 0.5)]])
	k.vents(d1, [-54 - 2.4 * i for i in range(7)], 0.7, (2.4, 0.8, 0.2))
	k.pair("BOOSTER", lambda s: Vector((6.7 * s, inner.y, inner.z)))
	k.pair("BOOSTER", lambda s: Vector((16.5 * s, outer.y, outer.z)))
	k.pair("RCS", lambda s: k.side(s, 88, -1.0), "lateral")
	k.pair("RCS", lambda s: k.top(10 * s, 90), UP)
	k.pair("RCS", lambda s: k.side(s, -70, 0.0), "lateral")
	k.pair("RCS", lambda s: k.belly(12 * s, -74), DOWN)
	k.pair("WEAPON", lambda s: k.belly(14 * s, 88))
	k.pair("WEAPON", lambda s: k.belly(32 * s, -34))
	k.pair("WEAPON", lambda s: k.belly(42 * s, -48))
	k.pair("PAD", lambda s: k.belly(10 * s, 60))
	k.pair("PAD", lambda s: k.belly(16 * s, 0))
	k.pair("PAD", lambda s: k.belly(14 * s, -56))
	k.pair("LANDJET", lambda s: k.belly(6 * s, 80))
	k.pair("LANDJET", lambda s: k.belly(7 * s, 40))
	k.pair("LANDJET", lambda s: k.belly(8 * s, -10))
	k.pair("LANDJET", lambda s: k.belly(8 * s, -54))


def sovereign(k):
	from sovereign import build as build_sovereign
	build_sovereign(k)

BUILDERS = {1: wren, 2: kestrel, 3: swift, 4: harrier, 5: osprey, 6: condor, 7: albatross, 8: sovereign}


def build(tier, out_dir, blend_dir=SOURCES):
	spec = ROSTER[tier]
	C.reset()
	k = Kit(spec["length"])
	BUILDERS[tier](k)
	for kind in C.SOCKET_KINDS:
		if k.count[kind] != spec[kind]:
			raise RuntimeError("%s: %s sockets %d, contract %d" % (spec["slug"], kind, k.count[kind], spec[kind]))
	if blend_dir:
		os.makedirs(blend_dir, exist_ok=True)
		bpy.context.preferences.filepaths.save_version = 0
		bpy.context.scene["ship_slug"] = spec["slug"]
		bpy.context.scene["ship_length_m"] = spec["length"]
		bpy.ops.wm.save_as_mainfile(filepath=os.path.join(blend_dir, spec["slug"] + ".blend"), compress=True)
	export_current(tier, out_dir)


def export_current(tier, out_dir):
	spec = ROSTER[tier]
	if os.environ.get("ASTRYX_TRIS"):
		dg = bpy.context.evaluated_depsgraph_get()
		per = {}
		for ob in bpy.data.objects:
			if ob.type == "MESH" and not ob.get("cutter"):
				me = ob.evaluated_get(dg).to_mesh()
				key = ob.name.rstrip("0123456789.")
				per[key] = per.get(key, 0) + sum(len(p.vertices) - 2 for p in me.polygons)
		print("TRIS", sorted(per.items(), key=lambda kv: -kv[1]))
	bpy.context.view_layer.update()
	empty_transforms = {ob: ob.matrix_world.copy() for ob in bpy.data.objects if ob.type == "EMPTY"}
	hull_ob = C.finalize("Hull_" + spec["name"], smooth_angle=28.0 if tier == 8 else 32.0)
	if tier == 8:
		from sovereign import polish_export
		polish_export(hull_ob)
	# Manual object edits and parented sockets must share scene space before centring.
	hull_ob.data.transform(hull_ob.matrix_world)
	hull_ob.parent = None
	hull_ob.matrix_world = Matrix.Identity(4)
	for ob, transform in empty_transforms.items():
		ob.parent = None
		ob.matrix_world = transform
	hull_ob.data.update()
	bpy.context.view_layer.update()
	ext = C.recentre(hull_ob)
	f = spec["length"] / ext.y
	hull_ob.data.transform(Matrix.Scale(f, 4))
	for ob in bpy.data.objects:
		if ob.type == "EMPTY":
			ob.location *= f
	hull_ob.data.update()
	ext *= f
	tris = C.tri_count(hull_ob)
	if tris > spec.get("tri_budget", 25000):
		raise RuntimeError("%s: %d tris over budget" % (spec["slug"], tris))
	out = os.path.join(out_dir, spec["slug"], spec["slug"] + ".glb")
	os.makedirs(os.path.dirname(out), exist_ok=True)
	C.export_glb(out)
	print("SHIP tier=%d slug=%s length=%.1f span=%.1f height=%.1f tris=%d sockets=%d mats=%s" % (
		tier, spec["slug"], ext.y, ext.x, ext.z, tris, len(C.sockets()), ",".join(sorted(m.name for m in hull_ob.data.materials))))


import bpy  # noqa: E402


def main():
	argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
	out = argv[argv.index("--out") + 1] if "--out" in argv else OUT
	if "--export-current" in argv:
		slug = bpy.context.scene.get("ship_slug", "")
		tier = next((t for t, spec in ROSTER.items() if spec["slug"] == slug), None)
		if tier is None:
			raise RuntimeError("Open a ship source .blend with ship_slug metadata before exporting")
		export_current(tier, out)
		return
	tiers = sorted(BUILDERS)
	if "--ship" in argv:
		tiers = [int(argv[argv.index("--ship") + 1])]
	blend_out = argv[argv.index("--blend-out") + 1] if "--blend-out" in argv else SOURCES
	for t in tiers:
		build(t, out, blend_out)


if __name__ == "__main__":
	main()
