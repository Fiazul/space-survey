extends SceneTree
# A giant tan blade across the screen is ONE enormous triangle. Find it.
const G := preload("res://scripts/world/planet_generator.gd")
const SP := preload("res://scripts/world/surface_patch.gd")
const R := 6371.0
func _initialize() -> void:
	var earth := G.recipe_for({"name": "Earth"})
	var s: TerrainSampler = G.terrain_sampler(earth)
	var ceiling: float = G.band_ceiling_km(s)
	var patch = SP.new(); patch._ready()
	var lat := deg_to_rad(20.5); var lon := deg_to_rad(-17.0)
	var dir := Vector3(cos(lat)*cos(lon), sin(lat), cos(lat)*sin(lon)).normalized()
	var alt := 13.0
	patch.update_for(dir * (R + alt), "Earth", true, R, alt, 0.02, ceiling, earth, s)
	var rep: Dictionary = patch.report()
	print("_bigtri: alt %.0f km, base %.0f m, ring quads %.2f/%.2f/%.2f/%.2f km"
		% [alt, float(rep.base_quad_km)*1000.0,
		SP.ring_quad_km(0,float(rep.base_quad_km)), SP.ring_quad_km(1,float(rep.base_quad_km)),
		SP.ring_quad_km(2,float(rep.base_quad_km)), SP.ring_quad_km(3,float(rep.base_quad_km))])
	for name in ["land", "skirt"]:
		for ring in SP.RING_COUNT:
			var mi: MeshInstance3D = patch.mesh_for(name, ring)
			if mi == null or mi.mesh == null or mi.mesh.get_surface_count() == 0:
				continue
			var v: PackedVector3Array = mi.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
			var worst := 0.0
			var expect: float = SP.ring_quad_km(ring, float(rep.base_quad_km))
			var over := 0
			for i in range(0, v.size() - 2, 3):
				var e := maxf(v[i].distance_to(v[i+1]),
					maxf(v[i+1].distance_to(v[i+2]), v[i+2].distance_to(v[i])))
				worst = maxf(worst, e)
				if e > expect * 3.0:
					over += 1
			print("_bigtri: %-5s ring %d: %d tris, quad %.2f km, LONGEST EDGE %.2f km, %d tris over 3x quad"
				% [name, ring, v.size() / 3, expect, worst, over])
	patch.free(); quit(0)
