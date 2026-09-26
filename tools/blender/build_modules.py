"""Builds the swappable ship modules (weapons, landing pads) as GLBs in assets/modules/.

Contract: docs/specs/2026-09-26-ship-roster-and-modules.md. Weapons hang below their top
saddle (origin = hull attach point, barrel -Z, MUZZLE at the emitter). Pads hang below their
mount plate (origin = hull skin, deployed pose along -Y, FOOT at ground contact).

    blender -b --python tools/blender/build_modules.py [-- --module weapon_mk1]
"""
import argparse
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import module_common as mc  # noqa: E402

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "assets", "modules")
TRI_BUDGET = 3000


def muzzle(name, x, y, z0, z1, r_back, r_front, r_bore, recess):
	"""Hollow emitter shroud from z0 back to z1 front; the bore folds back `recess` metres."""
	mc.loft(name, [(r_back, r_back, z0), (r_front, r_front, z1), (r_bore, r_bore, z1), (r_bore * .92, r_bore * .92, z1 + recess)],
		"Hull_Steel", offset=(x, y, 0), profile=mc.ROUND12)
	mc.cyl(name + "_emitter", r_bore * .85, .03, (x, y, z1 + recess - .02), "Accent_Emit", axis="Z", segments=12)


def weapon_mk1():
	y = -.85
	mc.box("saddle", (.8, .3, 2.0), (0, -.15, .2), "Hull_Steel", bevel=.04)
	for z in (.95, -.55):
		mc.box("clamp", (1.1, .12, .3), (0, -.34, z), "Hull_Dark", bevel=.02)
	mc.loft("receiver", [(.45, .38, 1.5), (.62, .5, 1.0), (.62, .5, -.9), (.48, .4, -1.5)], "Hull_Dark", offset=(0, y, 0), bevel=.03)
	cheek = mc.loft("cheek", [(.10, .30, 1.25), (.16, .46, .8), (.16, .46, -.8), (.09, .28, -1.45)], "Hull_Paint", offset=(.6, y, 0), bevel=.02)
	mc.mirror_x(cheek)
	for i in range(4):
		mc.mirror_x(mc.box("fin", (.05, .62, .12), (.8, y, .45 - .28 * i), "Hull_Steel"))
	mc.box("capacitor_cover", (.7, .16, 1.8), (0, -1.38, .1), "Hull_Paint", bevel=.03)
	mc.box("pump", (.6, .3, .4), (0, -1.3, 1.35), "Hull_Steel", bevel=.03)
	mc.cyl("heatsink", .34, .25, (0, y, 1.62), "Hull_Steel", axis="Z", r2=.3, bevel=.02)
	mc.cyl("breech_collar", .46, .3, (0, y, -1.6), "Hull_Steel", axis="Z", r2=.40, bevel=.02)
	mc.cyl("barrel", .26, 2.3, (0, y, -2.9), "Hull_Dark", axis="Z")
	for z in (-2.5, -3.3):
		mc.cyl("barrel_collar", .34, .14, (0, y, z), "Hull_Steel", axis="Z")
	muzzle("muzzle", 0, y, -4.0, -4.5, .40, .36, .22, .2)
	for side in (-1, 1):
		mc.pipe("coolant", [(side * .3, -1.3, 1.35), (side * .8, -1.28, .9), (side * .82, -1.26, -.6), (side * .55, -1.1, -1.7), (side * .3, -1.0, -2.5)], .08, "Hull_Steel")
	for side in (-1, 1):
		mc.loft("accelerator_cheek", [(.10, .26, -1.5), (.14, .30, -2.0), (.09, .18, -3.95)],
			"Hull_Paint", offset=(side * .34, y, 0), bevel=.02)
		for z in (-2.1, -2.55, -3.0):
			mc.box("cooling_slot", (.025, .14, .22), (side * .48, y, z), "Hull_Dark")
	mc.box("sight_spine", (.16, .12, 2.5), (0, y + .33, -2.55), "Hull_Steel", bevel=.015)
	mc.empty("MUZZLE", (0, y, -4.5))


def weapon_mk2():
	y = -.9
	mc.box("saddle", (.9, .3, 2.4), (0, -.15, .3), "Hull_Steel", bevel=.04)
	for z in (1.25, .1, -.8):
		mc.box("clamp", (1.2, .12, .28), (0, -.34, z), "Hull_Dark", bevel=.02)
	mc.loft("receiver", [(.5, .42, 1.9), (.72, .55, 1.3), (.78, .58, -.6), (.7, .5, -1.6), (.55, .42, -2.0)], "Hull_Dark", offset=(0, y, 0), bevel=.03)
	cheek = mc.loft("cheek", [(.10, .32, 1.6), (.2, .52, 1.1), (.2, .52, -1.3), (.1, .3, -2.1)], "Hull_Paint", offset=(.72, y, 0), bevel=.02)
	mc.mirror_x(cheek)
	for i in range(6):
		mc.mirror_x(mc.box("fin", (.05, .72, .11), (.97, y, 1.35 - .25 * i), "Hull_Steel"))
	for dy in (-.14, .14):
		mc.mirror_x(mc.box("charge_strip", (.03, .05, 1.3), (.93, y + dy, -.75), "Accent_Emit"))
	mc.box("capacitor_bank", (.85, .26, 2.6), (0, -1.55, .25), "Hull_Paint", bevel=.03)
	for i in range(4):
		mc.box("vent_fin", (.95, .12, .05), (0, -1.74, 1.2 - .3 * i), "Hull_Steel")
	mc.box("pump", (.7, .3, .45), (0, -1.45, 1.75), "Hull_Steel", bevel=.03)
	mc.cyl("heatsink", .38, .28, (0, y, 2.02), "Hull_Steel", axis="Z", r2=.34, bevel=.02)
	mc.loft("barrel_block", [(.62, .36, -1.9), (.6, .34, -2.7)], "Hull_Paint", offset=(0, y, 0), bevel=.03)
	for side in (-1, 1):
		mc.cyl("barrel", .19, 3.0, (side * .3, y, -4.2), "Hull_Dark", axis="Z")
		muzzle("muzzle", side * .3, y, -5.4, -5.9, .27, .25, .15, .18)
	mc.box("spine", (.18, .18, 2.8), (0, y, -4.0), "Hull_Steel")
	for i, z in enumerate((-3.05, -3.65, -4.25)):
		mc.loft("cap_ring", [(.62, .34, z + .1), (.62, .34, z - .1)], "Hull_Steel", offset=(0, y, 0), bevel=.02)
		mc.loft("cap_inset", [(.56, .3, z - .1), (.56, .3, z - .18)], "Hull_Dark", offset=(0, y, 0))
	mc.box("muzzle_bridge", (.42, .14, .5), (0, y, -5.5), "Hull_Paint", bevel=.02)
	for side in (-1, 1):
		mc.pipe("coolant_a", [(side * .35, -1.45, 1.75), (side * .8, -1.45, .6), (side * .72, -1.3, -1.3), (side * .55, -1.1, -2.95)], .05, "Hull_Steel")
		mc.pipe("coolant_b", [(side * .2, -1.6, 1.6), (side * .5, -1.72, .0), (side * .5, -1.4, -1.8), (side * .45, -1.15, -3.55)], .04, "Hull_Steel")
	for side in (-1, 1):
		mc.loft("swept_accelerator_shroud", [(.13, .35, -2.0), (.18, .32, -3.0), (.1, .15, -5.45)],
			"Hull_Paint", offset=(side * .58, y, 0), bevel=.02)
		mc.box("energy_rail", (.04, .055, 2.1), (side * .50, y + .27, -3.8), "Accent_Emit")
	mc.empty("MUZZLE", (0, y, -5.9))


def landing_gear(heavy=False):
	"""Trailing-link aerospace gear: paired arms, exposed piston and a broad skid."""
	w = 1.0 if heavy else .78
	foot_y = -4.73 if heavy else -4.62
	mc.box("recessed_mount", (w * 1.9, .18, 1.6), (0, -.09, 0), "Hull_Dark", bevel=.035)
	mc.loft("mount_fairing", [(w * .92, .18, .7), (w, .22, .2), (w * .65, .16, -.8)],
		"Hull_Paint", offset=(0, -.25, 0), bevel=.035)
	mc.cyl("main_hinge", .27, w * 1.9, (0, -.52, .0), "Hull_Steel", axis="X", segments=12)
	# Two box-section arms carry the load, with the shock absorber between them.
	for side in (-1, 1):
		x = side * w * .56
		mc.beam("upper_link", .22 if heavy else .18, .46, (x, -.55, 0), (x, -2.4, .52))
		mc.beam("trailing_link", .20, .38, (x, -2.4, .52), (x * .75, -4.15, -.12), "Hull_Dark")
		mc.cyl("knee_pin", .23, .12, (x + side * .13, -2.4, .52), "Hull_Steel", axis="X", segments=10)
		mc.beam("torque_scissor", .10, .15, (x * .75, -2.7, .62), (x * .8, -3.2, .95), "Hull_Steel", .01)
		mc.beam("torque_scissor", .10, .15, (x * .8, -3.2, .95), (x * .75, -3.8, .2), "Hull_Steel", .01)
	mc.span("shock_housing", .24 if heavy else .20, (0, -.75, -.12), (0, -2.65, -.30), "Hull_Dark", segments=12)
	mc.span("polished_piston", .12, (0, -2.50, -.29), (0, -4.06, -.15), "Hull_Steel", segments=12)
	mc.loft("aerodynamic_leg_cover", [(w * .56, .35, -.45), (w * .50, .35, .25)],
		"Hull_Paint", offset=(0, -1.25, 0), bevel=.035)
	mc.cyl("ankle_axle", .23, w * 1.35, (0, -4.08, -.12), "Hull_Steel", axis="X", segments=12)
	for side in (-1, 1):
		mc.box("ankle_clevis", (.16, .44, .5), (side * w * .46, -4.18, -.12), "Hull_Paint", bevel=.025)
	# Long chamfered snowshoe distributes load; ground contact remains at FOOT.
	mc.loft("load_spreading_foot", [(w * .55, .13, 1.02), (w * .95, .20, .65),
		(w * .95, .20, -.85), (w * .62, .12, -1.3)], "Hull_Paint", offset=(0, foot_y + .29, 0), bevel=.03)
	for side in (-1, 1):
		mc.box("contact_sole", (w * .70, .10, 1.75), (side * w * .50, foot_y + .05, -.1), "Hull_Dark", bevel=.018)
		for z in (-.65, -.1, .45):
			mc.box("sole_groove", (.04, .09, .15), (side * w * .86, foot_y + .06, z), "Hull_Steel")
	mc.pipe("protected_hydraulic", [(.16, -.5, .28), (.20, -1.5, .5), (.18, -2.4, .7), (.1, -2.85, .6)], .04, "Hull_Dark")
	if heavy:
		for side in (-1, 1):
			mc.span("auxiliary_damper", .10, (side * .8, -.5, .3), (side * .55, -2.38, .52), "Hull_Steel", segments=8)
		mc.box("approach_light_housing", (.45, .25, .12), (0, -1.25, -.83), "Hull_Dark", bevel=.02)
		mc.box("approach_light", (.29, .08, .03), (0, -1.25, -.90), "Accent_Emit")
	mc.empty("FOOT", (0, foot_y, 0))


def pad_mk1():
	landing_gear(False)


def pad_mk2():
	landing_gear(True)


MODULES = {"weapon_mk1": weapon_mk1, "weapon_mk2": weapon_mk2, "pad_mk1": pad_mk1, "pad_mk2": pad_mk2}


def build(name):
	mc.reset_scene()
	MODULES[name]()
	obj = mc.finalize(name)
	tris = mc.tri_count(obj)
	path = os.path.abspath(os.path.join(OUT, name + ".glb"))
	if tris > TRI_BUDGET:
		raise SystemExit("module %s over budget: %d > %d" % (name, tris, TRI_BUDGET))
	mc.export_glb(path)
	print("module %s: %d tris -> %s" % (name, tris, path))


def main():
	argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
	parser = argparse.ArgumentParser()
	parser.add_argument("--module", choices=sorted(MODULES))
	args = parser.parse_args(argv)
	os.makedirs(OUT, exist_ok=True)
	for name in [args.module] if args.module else MODULES:
		build(name)


main()
