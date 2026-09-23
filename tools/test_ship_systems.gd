extends Node3D

class FlatWorld extends TerrainSampler:
	func height_m(_dir: Vector3, _detail: float = 0.0) -> float:
		return 0.0
	func max_height_km() -> float:
		return 0.0
	func is_water(_dir: Vector3) -> bool:
		return false

var failures := 0

func _ready() -> void:
	var ship := Ship.new()
	add_child(ship)
	ship.newton = true
	var flat := FlatWorld.new({})
	flat.surface = {"solid": true}
	for index in ship.ship_count():
		ship.swap_ship(index)
		ship.transform.basis = Basis.IDENTITY
		ship.anchor_off = Vector3.UP * 6371.3
		ship.reset_mesh_pose()
		var rig := ship.systems
		check("hull %d has feet and mounts" % index, rig.legs.size() >= 3 and rig.mounts.size() >= 2)
		check("stowed feet do not collide", rig.foot_points().is_empty())
		ship.toggle_gear()
		rig.step(1.0)
		check("gear animates through intermediate pose", rig.gear_fraction > 0 and rig.gear_fraction < 1)
		rig.step(1.0)
		var feet := rig.foot_points()
		for foot in feet:
			check("feet extend below entire hull", foot.y < ship._hull_box.position.y)
		var pos := Vector3.UP * 6371.3
		var velocity := Vector3.DOWN * .002
		var hit := ship.resolve_surface_motion(flat, pos, Vector3.UP * 6370.9, velocity, 6371.0, Basis.IDENTITY)
		check("feet stop descent", hit.hit and hit.gear_hit)
		check("gentle landing is recognized", ship.landed)
		var expected := -feet[0].y
		check("center altitude follows feet, not enclosing sphere", absf(hit.position.y - 6371.0 - expected) < .003)
		pos = hit.position
		for frame in 120:
			velocity = Vector3.DOWN * .00981 / 60.0
			hit = ship.resolve_surface_motion(flat, pos, pos + velocity / 60.0, velocity, 6371.0, Basis.IDENTITY)
			pos = hit.position
		check("resting feet remain stable", absf(pos.y - 6371.0 - expected) < .003 and hit.velocity.length() < .001)
		ship.resolve_surface_motion(flat, pos, pos, hit.velocity, 6371.0, Basis.IDENTITY)
		check("post-flight contact check preserves landed status", ship.landed)
		ship.toggle_gear()
		check("grounded gear cannot retract", rig.gear_target)
		var takeoff := ship.resolve_surface_motion(flat, pos, pos + Vector3.UP * .02, Vector3.UP * .02, 6371.0, Basis.IDENTITY)
		check("takeoff clears support", takeoff.position.y > pos.y + .019 and not ship.landed)
		ship.toggle_gear()
		rig.step(2.0)
		ship.toggle_hardpoints()
		rig.step(1.0)
		check("hardpoints deploy after gear stows", rig.weapons_ready())
		check("muzzle is finite", rig.muzzle_local().is_finite())
		# Nose-first contact must still stop the long axis entering terrain.
		ship.transform.basis = Basis(Vector3.RIGHT, -PI*.5)
		var nose := ship.resolve_surface_motion(flat, Vector3.UP * 6371.3, Vector3.UP * 6370.9, Vector3.DOWN, 6371.0, Basis.IDENTITY)
		check("pitched hull remains solid", nose.hit and nose.position.y - 6371.0 >= -ship._hull_box.position.z - .002)
		var up := DevSites.dir_for(23.81, 90.41)
		ship.transform.basis = Basis.looking_at(DevSites.heading_forward(up, 30), up)
		rig.gear_target = true
		rig.weapons_target = false
		rig.step(2)
		var diagonal := ship.resolve_surface_motion(flat, up * 6371.3, up * 6370.9, -up*.002, 6371.0, Basis.IDENTITY)
		check("landing works away from coordinate axes", ship.landed)
		var depart := ship.resolve_surface_motion(flat, diagonal.position, diagonal.position + up*.02, up*.02, 6371.0, Basis.IDENTITY)
		check("takeoff works away from coordinate axes", depart.position.distance_to(diagonal.position) > .019)
		print("ship systems: ", ship.ship_name_at(index), " landing center AGL=", snappedf((pos.y-6371.0)*1000.0, .1), " m")
	ship.queue_free()
	await get_tree().process_frame
	print("ship_systems: ", "OK" if failures == 0 else "FAIL %d" % failures)
	get_tree().quit(0 if failures == 0 else 1)

func check(label: String, ok: bool) -> void:
	if not ok:
		failures += 1
		push_error(label)
