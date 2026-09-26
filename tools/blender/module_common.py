"""Blender helpers for ship module GLBs (tools/blender/build_modules.py).

All coordinates are given in the Godot frame of docs/specs/2026-09-26-ship-roster-and-modules.md
(+X right, +Y up, -Z forward, metres). The glTF exporter maps Blender +Y to glTF/Godot -Z, so
g() converts Godot (x, y, z) to Blender (x, -z, y) and the file reads in contract terms.
"""
import math

import bmesh
import bpy
from mathutils import Matrix, Vector

MATERIALS = {
	"Hull_Paint": dict(color=(0.30, 0.34, 0.38), metallic=0.55, roughness=0.48),
	"Hull_Dark": dict(color=(0.022, 0.026, 0.030), metallic=0.55, roughness=0.62),
	"Hull_Steel": dict(color=(0.30, 0.32, 0.34), metallic=0.85, roughness=0.30),
	"Accent_Emit": dict(color=(0.10, 0.45, 0.60), metallic=0.0, roughness=0.35, emit=(0.15, 0.75, 1.0), strength=6.0),
	"Nozzle_Emit": dict(color=(0.35, 0.20, 0.12), metallic=0.3, roughness=0.4, emit=(1.0, 0.45, 0.15), strength=4.0),
}

AXIS_ROT = {
	"Y": Matrix.Identity(4),
	"Z": Matrix.Rotation(math.radians(90), 4, "X"),
	"X": Matrix.Rotation(math.radians(90), 4, "Y"),
}


def g(x, y, z):
	return Vector((x, -z, y))


def reset_scene():
	bpy.ops.wm.read_factory_settings(use_empty=True)
	for block in (bpy.data.meshes, bpy.data.materials, bpy.data.curves):
		for item in list(block):
			block.remove(item)


def material(name):
	existing = bpy.data.materials.get(name)
	if existing:
		return existing
	spec = MATERIALS[name]
	mat = bpy.data.materials.new(name)
	mat.use_nodes = True
	bsdf = mat.node_tree.nodes["Principled BSDF"]
	bsdf.inputs["Base Color"].default_value = (*spec["color"], 1.0)
	bsdf.inputs["Metallic"].default_value = spec["metallic"]
	bsdf.inputs["Roughness"].default_value = spec["roughness"]
	if "emit" in spec:
		bsdf.inputs["Emission Color"].default_value = (*spec["emit"], 1.0)
		bsdf.inputs["Emission Strength"].default_value = spec["strength"]
	return mat


def _object(name, bm, mat_name, bevel=0.0, segments=1, angle=30.0):
	mesh = bpy.data.meshes.new(name)
	bm.to_mesh(mesh)
	bm.free()
	obj = bpy.data.objects.new(name, mesh)
	bpy.context.scene.collection.objects.link(obj)
	mesh.materials.append(material(mat_name))
	if bevel > 0.0:
		mod = obj.modifiers.new("Bevel", "BEVEL")
		mod.width = bevel
		mod.segments = segments
		mod.limit_method = "ANGLE"
		mod.angle_limit = math.radians(angle)
		mod.harden_normals = False
	return obj


def _place(bm, center, axis="Y", rot=None):
	m = Matrix.Translation(g(*center)) @ (rot if rot is not None else Matrix.Identity(4)) @ AXIS_ROT[axis]
	bmesh.ops.transform(bm, matrix=m, verts=bm.verts)


def box(name, size, center, mat, bevel=0.0, rot=None):
	bm = bmesh.new()
	bmesh.ops.create_cube(bm, size=1.0)
	bmesh.ops.scale(bm, vec=Vector((size[0], size[2], size[1])), verts=bm.verts)
	_place(bm, center, rot=rot)
	return _object(name, bm, mat, bevel)


def cyl(name, r1, depth, center, mat, axis="Y", r2=None, segments=12, bevel=0.0, rot=None):
	"""r1 sits at the negative end of `axis`, r2 at the positive end."""
	bm = bmesh.new()
	bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=segments,
		radius1=r1, radius2=r1 if r2 is None else r2, depth=depth)
	_place(bm, center, axis, rot)
	return _object(name, bm, mat, bevel)


def span(name, r, a, b, mat, segments=10, bevel=0.0):
	a, b = g(*a), g(*b)
	bm = bmesh.new()
	bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=segments, radius1=r, radius2=r, depth=(b - a).length)
	rot = Vector((0, 0, 1)).rotation_difference((b - a).normalized()).to_matrix().to_4x4()
	bmesh.ops.transform(bm, matrix=Matrix.Translation((a + b) / 2) @ rot, verts=bm.verts)
	return _object(name, bm, mat, bevel)


def beam(name, width, depth, a, b, mat="Hull_Paint", bevel=.025):
	"""Rectangular structural link, with its length aligned between two pivots."""
	a, b = g(*a), g(*b)
	bm = bmesh.new()
	bmesh.ops.create_cube(bm, size=1)
	bmesh.ops.scale(bm, vec=Vector((width, depth, (b - a).length)), verts=bm.verts)
	rot = Vector((0, 0, 1)).rotation_difference((b - a).normalized()).to_matrix().to_4x4()
	bmesh.ops.transform(bm, matrix=Matrix.Translation((a + b) / 2) @ rot, verts=bm.verts)
	return _object(name, bm, mat, bevel)


OCTAGON = [(-.65, -1), (.65, -1), (1, -.65), (1, .65), (.65, 1), (-.65, 1), (-1, .65), (-1, -.65)]


def loft(name, stations, mat, offset=(0, 0, 0), bevel=0.0, profile=OCTAGON):
	"""stations: (half_width, half_height, z) along the Godot Z axis."""
	bm = bmesh.new()
	rings = []
	for hw, hh, z in stations:
		rings.append([bm.verts.new(g(offset[0] + px * hw, offset[1] + py * hh, offset[2] + z)) for px, py in profile])
	n = len(profile)
	for ra, rb in zip(rings, rings[1:]):
		for i in range(n):
			j = (i + 1) % n
			bm.faces.new((ra[i], ra[j], rb[j], rb[i]))
	bm.faces.new(rings[0])
	bm.faces.new(list(reversed(rings[-1])))
	bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
	return _object(name, bm, mat, bevel)


def pipe(name, points, radius, mat, resolution=3):
	curve = bpy.data.curves.new(name, "CURVE")
	curve.dimensions = "3D"
	curve.bevel_depth = radius
	curve.bevel_resolution = 1
	curve.resolution_u = resolution
	curve.use_fill_caps = True
	spline = curve.splines.new("BEZIER")
	spline.bezier_points.add(len(points) - 1)
	for bp, p in zip(spline.bezier_points, points):
		bp.co = g(*p)
		bp.handle_left_type = bp.handle_right_type = "AUTO"
	obj = bpy.data.objects.new(name, curve)
	bpy.context.scene.collection.objects.link(obj)
	curve.materials.append(material(mat))
	return obj


def mirror_x(obj):
	dup = obj.copy()
	dup.data = obj.data.copy()
	dup.name = obj.name + "_R"
	bpy.context.scene.collection.objects.link(dup)
	dup.data.transform(Matrix.Scale(-1, 4, Vector((1, 0, 0))))
	dup.data.flip_normals()
	return dup


def empty(name, center):
	obj = bpy.data.objects.new(name, None)
	obj.empty_display_type = "ARROWS"
	obj.empty_display_size = 0.3
	obj.location = g(*center)
	bpy.context.scene.collection.objects.link(obj)
	return obj


def finalize(name, smooth_angle=35.0):
	"""Applies modifiers, converts curves, joins every mesh into one object named `name`."""
	depsgraph = bpy.context.evaluated_depsgraph_get()
	parts = []
	for obj in list(bpy.context.scene.objects):
		if obj.type not in {"MESH", "CURVE"}:
			continue
		mesh = bpy.data.meshes.new_from_object(obj.evaluated_get(depsgraph))
		mesh.materials.clear()
		for slot in obj.material_slots:
			mesh.materials.append(slot.material)
		baked = bpy.data.objects.new(obj.name + "_baked", mesh)
		bpy.context.scene.collection.objects.link(baked)
		bpy.data.objects.remove(obj)
		parts.append(baked)
	bpy.ops.object.select_all(action="DESELECT")
	for obj in parts:
		obj.select_set(True)
	bpy.context.view_layer.objects.active = parts[0]
	bpy.ops.object.join()
	joined = bpy.context.view_layer.objects.active
	joined.name = joined.data.name = name
	bm = bmesh.new()
	bm.from_mesh(joined.data)
	bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
	bm.to_mesh(joined.data)
	bm.free()
	bpy.ops.object.shade_smooth_by_angle(angle=math.radians(smooth_angle), keep_sharp_edges=True)
	return joined


def tri_count(obj):
	obj.data.calc_loop_triangles()
	return len(obj.data.loop_triangles)


def export_glb(path):
	bpy.ops.object.select_all(action="DESELECT")
	bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=False, export_apply=True,
		export_yup=True, export_materials="EXPORT", export_extras=False, export_animations=False)


def yaw(obj, degrees):
	"""Rotates a part's mesh about the Godot +Y axis through the module origin."""
	obj.data.transform(Matrix.Rotation(math.radians(degrees), 4, "Z"))
	return obj


ROUND12 = [(math.cos(2 * math.pi * i / 12), math.sin(2 * math.pi * i / 12)) for i in range(12)]
