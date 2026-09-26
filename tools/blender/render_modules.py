"""Studio review renders of assets/modules/*.glb (3/4 + side per module, plus a same-scale contact sheet).

    blender -b --python tools/blender/render_modules.py [-- --out DIR]
"""
import argparse
import math
import os
import sys

import bpy
from mathutils import Vector

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..")
MODULES = ["weapon_mk1", "weapon_mk2", "pad_mk1", "pad_mk2"]


def setup_scene():
	bpy.ops.wm.read_factory_settings(use_empty=True)
	scene = bpy.context.scene
	scene.render.engine = "CYCLES"
	scene.cycles.device = "CPU"
	scene.cycles.samples = 48
	scene.cycles.use_denoising = True
	scene.render.resolution_x = scene.render.resolution_y = 800
	scene.render.film_transparent = False
	scene.view_settings.view_transform = "AgX"
	world = bpy.data.worlds.new("Studio")
	world.use_nodes = True
	world.node_tree.nodes["Background"].inputs["Color"].default_value = (.18, .18, .18, 1)
	world.node_tree.nodes["Background"].inputs["Strength"].default_value = .9
	scene.world = world
	for name, loc, energy, size in (("Key", (6, -8, 9), 2500, 5), ("Fill", (-9, -3, 3), 900, 8), ("Rim", (2, 10, 6), 1800, 4)):
		data = bpy.data.lights.new(name, "AREA")
		data.energy = energy
		data.size = size
		light = bpy.data.objects.new(name, data)
		light.location = loc
		light.rotation_euler = (Vector((0, 0, 0)) - Vector(loc)).to_track_quat("-Z", "Y").to_euler()
		scene.collection.objects.link(light)
	cam = bpy.data.objects.new("Cam", bpy.data.cameras.new("Cam"))
	scene.collection.objects.link(cam)
	scene.camera = cam
	return scene, cam


def import_module(name, offset=Vector()):
	before = set(bpy.context.scene.objects)
	bpy.ops.import_scene.gltf(filepath=os.path.abspath(os.path.join(ROOT, "assets", "modules", name + ".glb")))
	objs = [o for o in bpy.context.scene.objects if o not in before]
	for o in objs:
		if o.parent is None:
			o.location += offset
	return objs


def bounds(objs):
	bpy.context.view_layer.update()
	pts = [o.matrix_world @ Vector(c) for o in objs if o.type == "MESH" for c in o.bound_box]
	lo = Vector((min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts)))
	hi = Vector((max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts)))
	return (lo + hi) / 2, (hi - lo).length


def aim(cam, center, direction, distance, ortho_scale=None):
	cam.location = center + direction.normalized() * distance
	cam.rotation_euler = (center - cam.location).to_track_quat("-Z", "Y").to_euler()
	cam.data.clip_end = distance * 4
	if ortho_scale:
		cam.data.type = "ORTHO"
		cam.data.ortho_scale = ortho_scale
	else:
		cam.data.type = "PERSP"
		cam.data.lens = 70


def render(scene, path):
	scene.render.filepath = path
	bpy.ops.render.render(write_still=True)
	print("render:", path)


def main():
	argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
	parser = argparse.ArgumentParser()
	parser.add_argument("--out", default="/tmp/modules")
	out = parser.parse_args(argv).out
	os.makedirs(out, exist_ok=True)
	# Blender frame after glTF import: nose (Godot -Z) is Blender +Y, up is +Z.
	three_quarter = Vector((-1.0, 1.25, .75))
	side = Vector((1, 0, 0))
	for name in MODULES:
		scene, cam = setup_scene()
		center, diag = bounds(import_module(name))
		aim(cam, center, three_quarter, diag * 2.1)
		render(scene, os.path.join(out, name + "_3q.png"))
		aim(cam, center, side, diag * 3, ortho_scale=diag * 1.1)
		render(scene, os.path.join(out, name + "_side.png"))
	scene, cam = setup_scene()
	scene.render.resolution_x, scene.render.resolution_y = 1600, 600
	objs, cursor = [], 0.0
	for name in MODULES:
		part = import_module(name)
		bpy.context.view_layer.update()
		ys = [(o.matrix_world @ Vector(c)).y for o in part if o.type == "MESH" for c in o.bound_box]
		for o in part:
			if o.parent is None:
				o.location.y += cursor - min(ys)
		cursor += max(ys) - min(ys) + 2.0
		objs += part
	center, _ = bounds(objs)
	height = max((o.matrix_world @ Vector(c)).z for o in objs if o.type == "MESH" for c in o.bound_box) - \
		min((o.matrix_world @ Vector(c)).z for o in objs if o.type == "MESH" for c in o.bound_box)
	aim(cam, center, Vector((1, .3, .3)), cursor * 2, ortho_scale=max(cursor * 1.05, height * 1600 / 600 * 1.2))
	render(scene, os.path.join(out, "modules.png"))

main()
