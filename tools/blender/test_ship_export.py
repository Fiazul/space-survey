import math
import os
import sys
import tempfile

import bpy

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import build_ships as fleet


def booster_gap():
	dg = bpy.context.evaluated_depsgraph_get()
	heights = []
	for ob in bpy.data.objects:
		if ob.type != "MESH":
			continue
		me = ob.evaluated_get(dg).to_mesh()
		for face in me.polygons:
			if me.materials[face.material_index].name == "Nozzle_Emit":
				heights.extend((ob.matrix_world @ me.vertices[i].co).z for i in face.vertices)
		ob.evaluated_get(dg).to_mesh_clear()
	boosters = [ob.matrix_world.translation.z for ob in bpy.data.objects if ob.name.startswith("SOCKET_BOOSTER_")]
	return (min(heights) + max(heights)) * .5 - sum(boosters) / len(boosters)


def run():
	with tempfile.TemporaryDirectory(prefix="astryx_ship_export_") as out:
		for case in ("rotated_canopy", "parented_engine"):
			bpy.ops.wm.open_mainfile(filepath=os.path.join(fleet.SOURCES, "kestrel.blend"))
			bpy.data.objects["Canopy"].rotation_euler.x = math.radians(20)
			if case == "parented_engine":
				assembly = bpy.data.objects.new("EngineAssembly", None)
				bpy.context.scene.collection.objects.link(assembly)
				assembly.location = (3, -2, 4)
				assembly.rotation_euler.z = .2
				bpy.data.objects["Engine"].parent = assembly
				for ob in bpy.data.objects:
					if ob.name.startswith("SOCKET_BOOSTER_"):
						ob.parent = assembly
			bpy.context.view_layer.update()
			assert abs(booster_gap()) < .0001, case + ": invalid source fixture"
			fleet.export_current(2, out)
			bpy.context.view_layer.update()
			gap = booster_gap()
			assert abs(gap) < .0001, "%s: boosters detached from nozzles by %.6f m" % (case, gap)
			hull = bpy.data.objects["Hull_Kestrel"]
			ys = [(hull.matrix_world @ v.co).y for v in hull.data.vertices]
			length = max(ys) - min(ys)
			assert abs(length - fleet.ROSTER[2]["length"]) < .001, "%s: exported hull length %.6f m" % (case, length)
			zs = [(hull.matrix_world @ v.co).z for v in hull.data.vertices]
			assert abs(min(ys) + max(ys)) < .001 and abs(min(zs) + max(zs)) < .001, case + ": hull not centred"
			print("ship_export: " + case + " OK")
	print("ship_export: OK")


if __name__ == "__main__":
	run()
