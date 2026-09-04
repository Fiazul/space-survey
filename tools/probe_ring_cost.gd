extends SceneTree
# How long does a ring rebuild actually take, and how many sampler calls does it
# make? FPS 3 was reported at 15 km over Earth with the rings live.
const G := preload("res://scripts/world/planet_generator.gd")
const SP := preload("res://scripts/world/surface_patch.gd")

func _initialize() -> void:
	var earth := G.recipe_for({"name": "Earth"})
	var s: TerrainSampler = G.terrain_sampler(earth)
	var patch = SP.new()
	patch._ready()
	patch.bind_body(earth, s)
	var dir := Vector3(0.42, 0.31, 0.85).normalized()
	var pos: Vector3 = dir * (6371.0 + 15.0)
	var ceiling: float = G.band_ceiling_km(s)

	# Cold build of all four rings.
	var t0 := Time.get_ticks_usec()
	patch.update_for(pos, "Earth", true, 6371.0, 15.0, 0.02, ceiling, earth, s)
	var all_ms := float(Time.get_ticks_usec() - t0) / 1000.0
	print("probe_ring_cost: cold build of 4 rings = %.1f ms" % all_ms)

	# Ring 0 alone, which rebuilds every 50 m of travel.
	var quad: float = SP.ring_quad_km(0)
	var t1 := Time.get_ticks_usec()
	var moves := 5
	for i in moves:
		var p: Vector3 = (dir + Vector3(0.0, float(i + 1) * quad * 1.2 / 6371.0, 0.0)).normalized() * (6371.0 + 15.0)
		patch.update_for(p, "Earth", true, 6371.0, 15.0, 0.02, ceiling, earth, s)
	var per_ms := float(Time.get_ticks_usec() - t1) / 1000.0 / float(moves)
	print("probe_ring_cost: %.1f ms per ring-0 refresh (moving 60 m each step)" % per_ms)
	print("probe_ring_cost: that alone is %.1f fps if it happens once a frame" % (1000.0 / maxf(per_ms, 0.001)))

	# Raw sampler cost, since that is what the loop is made of.
	var n := 20000
	var t2 := Time.get_ticks_usec()
	for i in n:
		var d := Vector3(sin(float(i) * 0.001), 0.3, cos(float(i) * 0.001)).normalized()
		s.height_m(d)
	var h_us := float(Time.get_ticks_usec() - t2) / float(n)
	var t3 := Time.get_ticks_usec()
	for i in n:
		var d := Vector3(sin(float(i) * 0.001), 0.3, cos(float(i) * 0.001)).normalized()
		s.is_water(d)
	var w_us := float(Time.get_ticks_usec() - t3) / float(n)
	print("probe_ring_cost: height_m %.2f us, is_water %.2f us per call" % [h_us, w_us])

	# How many calls does one ring make?
	var quads: int = SP.RING_SEGS * SP.RING_SEGS
	print("probe_ring_cost: one ring = %d quads x 4 _vert calls = %d _vert" % [quads, quads * 4])
	print("probe_ring_cost:   but only %d UNIQUE grid points exist -> ~4x waste"
		% ((SP.RING_SEGS + 1) * (SP.RING_SEGS + 1)))
	print("probe_ring_cost: each _vert = height_m + is_water + colour = ~%.1f us -> %.0f ms per ring"
		% [h_us + w_us, (h_us + w_us) * float(quads * 4) / 1000.0])
	patch.free()
	quit(0)
