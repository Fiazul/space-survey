"""Concept-sheet renders of the exported v2 hull GLBs (visual gate, not pass/fail).

  blender -b --python fleet_v2/blender/render_ships.py -- [--ship <slug>|roster|fleet] [--samples N] [--res N] [--views 3q,side,top,rear]

Writes renders/<slug>_{3q,side,top,rear}.png, roster.png (side profiles, one scale, labelled) and
fleet_3q.png (the seven 3/4 views tiled). Renders the GLB, so what is judged is what Godot imports.
Hull_Paint is shown as mid steel-blue; the game tints it per hangar swatch.
"""
import math
import os
import sys

import bpy
import numpy as np
from mathutils import Matrix, Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from build_ships import OUT as SHIPS, ROSTER  # noqa: E402

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []


def arg(name, default):
	return argv[argv.index(name) + 1] if name in argv else default


REN = os.path.join(os.path.dirname(SHIPS), "renders")
SAMPLES = int(arg("--samples", "96"))
RES = int(arg("--res", "1000"))
VIEWS = arg("--views", "3q,side,top,rear").split(",")

LOOK = {
	"Hull_Paint": dict(color=(0.09, 0.19, 0.36), metallic=0.3, rough=0.45, coat=0.1),
	"Hull_Dark": dict(color=(0.018, 0.021, 0.026), metallic=0.6, rough=0.38),
	"Hull_Steel": dict(color=(0.55, 0.57, 0.6), metallic=1.0, rough=0.22),
}


def node(nt, kind, x=0, **inputs):
	n = nt.nodes.new(kind)
	n.location = (x, 0)
	for k, v in inputs.items():
		n.inputs[k].default_value = v
	return n


def scene_setup(rx, ry):
	bpy.ops.wm.read_factory_settings(use_empty=True)
	sc = bpy.context.scene
	sc.render.engine = "CYCLES"
	sc.cycles.device = "CPU"
	sc.cycles.samples = SAMPLES
	sc.cycles.use_denoising = True
	sc.cycles.max_bounces = 6
	sc.render.resolution_x, sc.render.resolution_y = rx, ry
	sc.render.resolution_percentage = 100
	sc.render.image_settings.file_format = "PNG"
	sc.view_settings.view_transform = "AgX"
	sc.view_settings.look = "AgX - Medium High Contrast"
	w = bpy.data.worlds.new("Void")
	w.use_nodes = True
	nt = w.node_tree
	for n in list(nt.nodes):
		nt.nodes.remove(n)
	out = nt.nodes.new("ShaderNodeOutputWorld")
	tc = nt.nodes.new("ShaderNodeTexCoord")
	win = nt.nodes.new("ShaderNodeSeparateXYZ")
	nt.links.new(tc.outputs["Window"], win.inputs[0])
	ramp = nt.nodes.new("ShaderNodeValToRGB")
	ramp.color_ramp.elements[0].position = 0.0
	ramp.color_ramp.elements[0].color = (0.004, 0.005, 0.008, 1)
	ramp.color_ramp.elements[1].position = 1.0
	ramp.color_ramp.elements[1].color = (0.035, 0.045, 0.065, 1)
	nt.links.new(win.outputs["Y"], ramp.inputs[0])
	env_sep = nt.nodes.new("ShaderNodeSeparateXYZ")
	nt.links.new(tc.outputs["Generated"], env_sep.inputs[0])
	env = nt.nodes.new("ShaderNodeValToRGB")
	env.color_ramp.elements[0].position = 0.35
	env.color_ramp.elements[0].color = (0.004, 0.004, 0.006, 1)
	env.color_ramp.elements[1].position = 1.0
	env.color_ramp.elements[1].color = (0.16, 0.19, 0.24, 1)
	nt.links.new(env_sep.outputs["Z"], env.inputs[0])
	bg_cam = nt.nodes.new("ShaderNodeBackground")
	nt.links.new(ramp.outputs[0], bg_cam.inputs["Color"])
	bg_env = nt.nodes.new("ShaderNodeBackground")
	bg_env.inputs["Strength"].default_value = 1.0
	nt.links.new(env.outputs[0], bg_env.inputs["Color"])
	lp = nt.nodes.new("ShaderNodeLightPath")
	mix = nt.nodes.new("ShaderNodeMixShader")
	nt.links.new(lp.outputs["Is Camera Ray"], mix.inputs[0])
	nt.links.new(bg_env.outputs[0], mix.inputs[1])
	nt.links.new(bg_cam.outputs[0], mix.inputs[2])
	nt.links.new(mix.outputs[0], out.inputs[0])
	sc.world = w
	sc.use_nodes = True
	ct = sc.node_tree
	for n in list(ct.nodes):
		ct.nodes.remove(n)
	rl = ct.nodes.new("CompositorNodeRLayers")
	gl = ct.nodes.new("CompositorNodeGlare")
	gl.glare_type = "FOG_GLOW"
	gl.quality = "HIGH"
	gl.threshold = 1.2
	gl.size = 7
	gl.mix = -0.55
	comp = ct.nodes.new("CompositorNodeComposite")
	ct.links.new(rl.outputs["Image"], gl.inputs["Image"])
	ct.links.new(gl.outputs["Image"], comp.inputs["Image"])
	cd = bpy.data.cameras.new("Cam")
	cam = bpy.data.objects.new("Cam", cd)
	cd.clip_end = 20000
	sc.collection.objects.link(cam)
	sc.camera = cam
	return sc, cam


def lights(sc, scale):
	for name, d, color, energy, ang in (
		("Key", (-1.0, -0.15, 0.75), (1.0, 0.8, 0.6), 1.6, 3),
		("Rim", (0.7, -0.9, 0.35), (0.45, 0.68, 1.0), 4.0, 2),
		("Kick", (0.9, 0.6, -0.15), (0.55, 0.75, 1.0), 1.4, 6),
		("Under", (-0.3, 0.2, -1.0), (0.3, 0.45, 0.8), 0.35, 20),
	):
		ld = bpy.data.lights.new(name, "SUN")
		ld.energy = energy
		ld.color = color
		ld.angle = math.radians(ang)
		lo = bpy.data.objects.new(name, ld)
		lo.rotation_mode = "QUATERNION"
		lo.rotation_quaternion = (-Vector(d)).to_track_quat("-Z", "Y")
		sc.collection.objects.link(lo)
	ad = bpy.data.lights.new("Softbox", "AREA")
	ad.shape = "RECTANGLE"
	ad.size, ad.size_y = 3 * scale, 1.2 * scale
	ad.energy = 1.0 * scale * scale
	ad.color = (0.85, 0.9, 1.0)
	ao = bpy.data.objects.new("Softbox", ad)
	ao.location = (0, 0, 2.2 * scale)
	sc.collection.objects.link(ao)


def restyle():
	for m in bpy.data.materials:
		d = LOOK.get(m.name)
		if not d or not m.use_nodes:
			continue
		p = next((n for n in m.node_tree.nodes if n.type == "BSDF_PRINCIPLED"), None)
		if p is None:
			continue
		p.inputs["Base Color"].default_value = (*d["color"], 1)
		p.inputs["Metallic"].default_value = d["metallic"]
		p.inputs["Roughness"].default_value = d["rough"]
		if "coat" in d:
			p.inputs["Coat Weight"].default_value = d["coat"]
			p.inputs["Coat Roughness"].default_value = 0.08


def import_ship(slug):
	before = set(bpy.data.objects)
	bpy.ops.import_scene.gltf(filepath=os.path.join(SHIPS, slug, slug + ".glb"))
	new = [o for o in bpy.data.objects if o not in before]
	for o in new:
		if o.type == "EMPTY":
			o.hide_render = True
	restyle()
	bpy.context.view_layer.update()
	return new


def bounds(objs):
	pts = []
	for o in objs:
		if o.type == "MESH":
			vs = o.data.vertices
			step = max(1, len(vs) // 4000)
			pts += [o.matrix_world @ vs[i].co for i in range(0, len(vs), step)]
	lo = Vector((min(p[i] for p in pts) for i in range(3)))
	hi = Vector((max(p[i] for p in pts) for i in range(3)))
	box = [o.matrix_world @ Vector(c) for o in objs if o.type == "MESH" for c in o.bound_box]
	lo = Vector((min(p[i] for p in box) for i in range(3)))
	hi = Vector((max(p[i] for p in box) for i in range(3)))
	return lo, hi, pts


def look_at(cam, loc, target, up=(0, 0, 1)):
	f = (Vector(target) - Vector(loc)).normalized()
	r = f.cross(Vector(up)).normalized()
	u = r.cross(f)
	m = Matrix((r, u, -f)).transposed().to_4x4()
	m.translation = Vector(loc)
	cam.matrix_world = m


def frame(sc, cam, pts, c, d, up=(0, 0, 1), fill=0.86):
	"""Place camera along d from centre c so projected points fill `fill` of the frame."""
	aspect = sc.render.resolution_x / sc.render.resolution_y
	if cam.data.type == "ORTHO":
		look_at(cam, c + d * 3000, c, up)
		inv = cam.matrix_world.inverted()
		loc = [inv @ p for p in pts]
		xs, ys = [p.x for p in loc], [p.y for p in loc]
		cx, cy = (max(xs) + min(xs)) / 2, (max(ys) + min(ys)) / 2
		w, h = max(xs) - min(xs), max(ys) - min(ys)
		cam.data.ortho_scale = max(w, h * aspect) / fill if aspect >= 1 else max(w / aspect, h) / fill
		cam.matrix_world.translation = cam.matrix_world @ Vector((cx, cy, 0))
		return
	dist = (max((p - c).length for p in pts)) * 3.0
	for _ in range(4):
		look_at(cam, c + d * dist, c, up)
		bpy.context.view_layer.update()
		inv = cam.matrix_world.inverted()
		half = math.tan(cam.data.angle / 2)
		ext = 0
		for p in pts:
			q = inv @ p
			ext = max(ext, abs(q.x / -q.z) / half, abs(q.y / -q.z) / half * aspect)
		dist *= ext / fill


def shoot(sc, path):
	sc.render.filepath = path
	bpy.ops.render.render(write_still=True)


VIEW_DIRS = {
	"3q": (Vector((-0.95, 1.0, 0.45)), "PERSP"),
	"rear": (Vector((0.55, -1.0, 0.42)), "PERSP"),
	"side": (Vector((1, 0, 0)), "ORTHO"),
	"top": (Vector((0, 0, 1)), "ORTHO"),
}


def render_ship(slug):
	sc, cam = scene_setup(RES, RES)
	lo, hi, pts = bounds(import_ship(slug))
	c = (lo + hi) * 0.5
	lights(sc, (hi - lo).length)
	for v in VIEWS:
		d, kind = VIEW_DIRS[v]
		cam.data.type = kind
		cam.data.lens = 55
		frame(sc, cam, pts, c, d.normalized(), up=(-1, 0, 0) if v == "top" else (0, 0, 1), fill=0.84 if kind == "PERSP" else 0.9)
		shoot(sc, os.path.join(REN, "%s_%s.png" % (slug, v)))


def render_roster():
	sc, cam = scene_setup(3600, 760)
	gap, cursor = 14.0, 0.0
	items, allpts = [], []
	for tier in sorted(ROSTER):
		spec = ROSTER[tier]
		objs = import_ship(spec["slug"])
		lo, hi, _ = bounds(objs)
		off = Vector((0, cursor - lo.y, -lo.z))
		for o in objs:
			if o.parent is None:
				o.location += off
		bpy.context.view_layer.update()
		lo, hi, pts = bounds(objs)
		allpts += pts
		items.append(((lo.y + hi.y) * 0.5, tier, spec, hi.y - lo.y))
		cursor = hi.y + gap
	span = cursor - gap
	lights(sc, span * 0.3)
	tm = bpy.data.materials.new("Label")
	tm.use_nodes = True
	em = tm.node_tree.nodes.new("ShaderNodeEmission")
	em.inputs["Color"].default_value = (0.55, 0.72, 0.9, 1)
	em.inputs["Strength"].default_value = 1.1
	tm.node_tree.links.new(em.outputs[0], tm.node_tree.nodes["Material Output"].inputs["Surface"])
	for y, tier, spec, ln in items:
		for body, size, dz in (("T%d  %s" % (tier, spec["name"].upper()), 7.0, -12.0), ("%d m" % round(ln), 5.0, -20.0)):
			td = bpy.data.curves.new("T", "FONT")
			td.body = body
			td.align_x = "CENTER"
			td.size = size
			td.materials.append(tm)
			to = bpy.data.objects.new("T", td)
			to.location = (60, y, dz)
			to.rotation_euler = (math.radians(90), 0, math.radians(90))
			sc.collection.objects.link(to)
			bpy.context.view_layer.update()
			allpts += [to.matrix_world @ Vector(cc) for cc in to.bound_box]
	cam.data.type = "ORTHO"
	lo = Vector((min(p[i] for p in allpts) for i in range(3)))
	hi = Vector((max(p[i] for p in allpts) for i in range(3)))
	frame(sc, cam, allpts, (lo + hi) * 0.5, Vector((1, 0, 0)), fill=0.94)
	shoot(sc, os.path.join(REN, "roster.png"))


def tile_fleet(tile=640):
	imgs = []
	for tier in sorted(ROSTER):
		im = bpy.data.images.load(os.path.join(REN, "%s_3q.png" % ROSTER[tier]["slug"]))
		im.scale(tile, tile)
		a = np.array(im.pixels[:], dtype=np.float32).reshape(tile, tile, 4)
		imgs.append(a)
	row = np.concatenate(imgs, axis=1)
	out = bpy.data.images.new("fleet", row.shape[1], row.shape[0], alpha=True)
	out.pixels.foreach_set(row.ravel())
	out.filepath_raw = os.path.join(REN, "fleet_3q.png")
	out.file_format = "PNG"
	out.save()


def main():
	os.makedirs(REN, exist_ok=True)
	only = arg("--ship", None)
	for tier in sorted(ROSTER):
		slug = ROSTER[tier]["slug"]
		if only in (None, slug, str(tier)) and os.path.exists(os.path.join(SHIPS, slug, slug + ".glb")):
			render_ship(slug)
	if only in (None, "roster"):
		render_roster()
	if only in (None, "fleet", "roster"):
		tile_fleet()


main()
