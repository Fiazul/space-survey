class_name SurfaceStreamingTest
extends Node3D

const PS := preload("res://scripts/world/planet_system.gd")
var failures := 0


func _ready() -> void:
	var planets := PS.new()
	add_child(planets)
	for body in ["Earth", "Moon"]:
		var radius: float = 6371.0 if body == "Earth" else 1737.4
		var patch: Node3D = planets.get("_surface")
		var off := Vector3.RIGHT * (radius + 13.49)
		planets.refresh(off, 0.0, body)
		patch.force_ready()
		planets.refresh(off, 0.0, body)
		_check("%s_initial_ground" % body, _ground_covers_ship(planets, patch, body))
		# Advance during each real worker batch, then collect via the live poll path.
		# Waiting here fixes completion order without relying on machine speed.
		for step in range(1, 4):
			var previous_anchor: Vector3 = patch.get("_ring_anchor")[0]
			off = Vector3.RIGHT.rotated(Vector3.UP, float(step) * 400.0 / radius) * (radius + 13.49)
			planets.refresh(off, 0.0, body)
			_check("%s_ground_while_building_%d" % [body, step],
				_ground_covers_ship(planets, patch, body))
			_check("%s_in_band_stays_visible_while_building_%d" % [body, step],
				_in_band_ground_is_visible(patch))
			if patch.get("_thread_pending"):
				while not WorkerThreadPool.is_group_task_completed(patch.get("_thread_group_id")):
					OS.delay_msec(1)
			var moved := off.rotated(Vector3.UP, 78.6 * 0.25 / radius)
			var vel: Vector3 = (moved - off) / 0.25
			planets.refresh(moved, 0.0, body, vel)
			_check("%s_ground_during_fast_flight_%d" % [body, step],
				_ground_covers_ship(planets, patch, body))
			_check("%s_in_band_stays_visible_during_fast_flight_%d" % [body, step],
				_in_band_ground_is_visible(patch))
			_check("%s_warm_rings_stay_lit_%d" % [body, step],
				_warm_rings_stay_lit(patch))
			_check("%s_new_ground_commits_%d" % [body, step],
				previous_anchor.distance_to(patch.get("_ring_anchor")[0]) > 1.0)
			var commit_frames := 0
			var max_one_frame := 0
			for _drain in range(6):
				planets.refresh(moved, 0.0, body, vel)
				_check("%s_in_band_stays_visible_drain_%d_%d" % [body, step, _drain],
					_in_band_ground_is_visible(patch))
				var n: int = patch.rings_committed_this_update()
				max_one_frame = maxi(max_one_frame, n)
				if n > 0:
					commit_frames += 1
			_check("%s_rings_commit_at_most_one_per_frame_%d" % [body, step], max_one_frame <= 1)
			_check("%s_rings_commit_across_frames_%d" % [body, step], commit_frames >= 2)
			print("streaming: %s step %d terrain lag %.1f km lead %.1f km" % [body, step,
				(planets.surface_basis(body).inverse() * moved.normalized() * radius).distance_to(patch.get("_ring_anchor")[0]),
				float(patch.get("_thread_lead"))])
			off = moved
		# One more dispatch with velocity so lead is measurable on a drained tile.
		var further := off.rotated(Vector3.UP, 120.0 / radius)
		var v_lead: Vector3 = (further - off) / 0.25
		planets.refresh(further, 0.0, body, v_lead)
		_check("%s_dispatch_uses_velocity_lead" % body, float(patch.get("_thread_lead")) > 1.0)
		patch.force_ready()
		planets.refresh(further, 0.0, body)
		_check("%s_detail_returns_after_stopping" % body, patch.visible)
		_check("%s_stopped_ground_coverage" % body, _ground_covers_ship(planets, patch, body))
		_check("%s_in_band_stays_visible_after_stop" % body, _in_band_ground_is_visible(patch))
	planets.queue_free()
	await get_tree().process_frame
	print("surface_streaming: ", "OK" if failures == 0 else "FAIL %d" % failures)
	get_tree().quit(0 if failures == 0 else 1)


func _in_band_ground_is_visible(patch: Node3D) -> bool:
	if not bool(patch.get("_last_in_band")) or not patch.has_ground():
		return true
	return patch.visible


func _warm_rings_stay_lit(patch: Node3D) -> bool:
	if not patch.has_ground():
		return true
	var fades: Array = patch.get("_ring_fade")
	for i in fades.size():
		if patch.get("_ring_land")[i].mesh == null:
			continue
		if float(fades[i]) < 0.99:
			return false
	return true


func _ground_covers_ship(planets: Node3D, patch: Node3D, body: String) -> bool:
	for row in planets.get("_bodies"):
		if row.name == body and row.sphere.visible:
			return true
	if not patch.visible:
		return false
	var origin: Vector3 = patch.to_local(Vector3.ZERO)
	var direction := -origin.normalized()
	for ring in patch.get("_ring_land"):
		if ring.mesh == null:
			continue
		var vertices: PackedVector3Array = ring.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		for i in range(0, vertices.size(), 3):
			if Geometry3D.ray_intersects_triangle(origin, direction,
					vertices[i], vertices[i + 1], vertices[i + 2]) != null:
				return true
	return false


func _check(label: String, condition: bool) -> void:
	if not condition:
		failures += 1
		push_error("surface_streaming: " + label)
