extends Node3D
var failures := 0
func _ready() -> void:
	var sampler := PlanetGenerator.terrain_sampler(PlanetGenerator.recipe_for({"name":"Earth"}))
	check("US and Chinese facilities exist",sampler.facilities.size() == 2)
	if sampler.facilities.is_empty():
		get_tree().quit(1)
		return
	var site: Dictionary = sampler.facilities[0]
	var xf: Transform3D = site.transform
	check("real NASA coordinate preserved", absf(site.lat_deg-28.608402) < 1e-7 and absf(site.lon_deg+80.604201) < 1e-7)
	check("facility clears vegetation",SurfaceFacility.occupied(sampler.facilities,site.dir,6371))
	check("distant forests unaffected",not SurfaceFacility.occupied(sampler.facilities,Vector3.UP,6371))
	var collision := sampler.resolve_motion(xf*Vector3(0,.3,0),xf*Vector3(0,-.1,0),xf.basis*Vector3.DOWN,6371,.001)
	check("physical pad stops crossing",collision.hit and (xf.affine_inverse()*collision.position).y > 0)
	for unlock in 12: GameState.visited["test_system_%d" % unlock] = true # every tier swappable
	var ship := Ship.new()
	add_child(ship)
	ship._set_capture(false)
	ship.dev_speed = false
	ship.terrain = sampler
	ship.nearest_name = "Earth"
	ship.nearest_radius = 6371
	ship.nearest_dist = 6371
	for index in ship.ship_count():
		ship.swap_ship(index)
		ship.set_terrain_frame(Basis.IDENTITY)
		ship.transform.basis = xf.basis
		ship.reset_mesh_pose()
		ship.systems.gear_target = true
		ship.systems.step(2)
		var approach := sampler.resolve_structure_hull(xf*Vector3(.35,.07,-.35),xf*Vector3(0,.07,0),Vector3.ZERO,6371,.00025,xf.basis,ship._hull_box.size*.5)
		check("diagonal approach avoids service tower hull %d" % index,not approach.hit)
		# Keep the entire approach volume clear, including hull overhang at pad edges.
		for yaw in [0.0, PI*.25, PI*.5]:
			var pose := xf.basis*Basis(Vector3.UP,yaw)
			for x in [-.08,0.0,.08]:
				for z in [-.08,0.0,.08]:
					var center := xf*Vector3(x,.07,z)
					var wall_check := sampler.resolve_structure_hull(center+pose*ship._hull_box.get_center(),center+pose*ship._hull_box.get_center(),Vector3.ZERO,6371,.00025,pose,ship._hull_box.size*.5)
					check("clear pad approach hull %d yaw %.2f offset %.2f %.2f" % [index,yaw,x,z],not wall_check.hit)
		# Being several metres above the pad is still airborne, not a lock. The margin
		# must clear the 2 m stationary support probe plus float32 rounding at Earth
		# radius (~0.5 m), or small hulls lock by quantisation luck.
		var lowest := 0.0
		for foot in ship.systems.foot_points(): lowest = maxf(lowest,-foot.y)
		var hovering := xf*Vector3(0,lowest+.005,0)
		ship.resolve_surface_motion(sampler,hovering,hovering,Vector3.ZERO,6371,Basis.IDENTITY)
		check("hovering above pad never locks",ship.landing_site.is_empty())
		ship.landing_site = ""
		ship.resolve_surface_motion(sampler,xf*Vector3(0,.25,0),xf*Vector3(0,-.1,0),xf.basis*Vector3.DOWN*2,6371,Basis.IDENTITY)
		check("hard impact is not a safe arrival",ship.landing_site.is_empty())
		var hit := ship.resolve_surface_motion(sampler,xf*Vector3(0,.25,0),xf*Vector3(0,-.1,0),xf.basis*Vector3.DOWN*.001,6371,Basis.IDENTITY)
		ship.anchor_off = hit.position
		ship.velocity = hit.velocity
		check("pad locks hull %d" % index,ship.landing_site == site.name)
		check("feet contact visible pad",hit.gear_hit and (xf.affine_inverse()*hit.position).y > lowest-.001)
		var parked: Vector3 = hit.position
		var attitude := ship.transform.basis
		ship.touch_thrust = 1
		ship.touch_yaw = 1
		for frame in 180:
			ship._mouse_delta = Vector2(30,20)
			ship.fly(1.0/60)
			ship._newton_ground()
		check("pad stays attached through planet rotation", (ship.terrain_basis.inverse()*ship.anchor_off).distance_to(parked)<.002)
		check("pad locks heading",(ship.terrain_basis.inverse()*ship.transform.basis).is_equal_approx(attitude))
		check("pad ignores ground thrust",ship.velocity.is_zero_approx())
		# A saved attachment is validated against the current pad and gear at
		# a different planetary angle, rather than trusting a stale world point.
		ship.landing_site = ""
		ship.set_terrain_frame(Basis(Vector3.UP,.6))
		ship.anchor_off = ship.terrain_basis*parked
		ship.transform.basis = ship.terrain_basis*attitude
		check("restores berth after offline rotation",ship.restore_facility_attachment(site.id,sampler,ship.terrain_basis))
		ship.touch_thrust = 0
		ship.touch_yaw = 0
		ship.touch_pitch = -1
		ship.fly(1.0/60)
		ship.touch_pitch = 0
		for frame in 90: ship.fly(1.0/60)
		check("lift releases berth",ship.landing_site.is_empty())
		check("takeoff actually gains clearance",(xf.affine_inverse()*(ship.terrain_basis.inverse()*ship.anchor_off)).y > (xf.affine_inverse()*parked).y+.003)
		# Hull must remain clear of solid structures; no sphere-based 90 m floor.
		check("takeoff has outward motion",ship.velocity.dot(ship.anchor_off.normalized()) > .001)
		# Teleport must not leave an attachment to the old facility.
		ship.landing_site = site.name
		ship.surface_position_revision += 1
		ship.anchor_off = Vector3.UP*6470
		ship.fly(1.0/60)
		check("teleport clears pad lock",ship.landing_site.is_empty())
		print("facility: hull ",index," pad contact and departure checked")
	var feet := ship.systems.foot_points()
	check("off-site saved berth rejected",not ship.restore_facility_attachment(site.id,sampler,Basis.IDENTITY))
	check("off-pad contact cannot claim facility",SurfaceFacility.pad_at(sampler.facilities,xf*Vector3(.2,.03,0),xf.basis,feet).is_empty())
	check("tilted unsupported feet cannot lock",SurfaceFacility.pad_at(sampler.facilities,xf*Vector3(0,.03,0),xf.basis*Basis(Vector3.FORWARD,.2),feet).is_empty())
	var wall := sampler.resolve_structure_hull(xf*Vector3(.4,.06,-.53),xf*Vector3(.6,.06,-.53),xf.basis*Vector3.RIGHT*10,6371,.001,xf.basis,Vector3.ONE*.01)
	check("fast hull sweep stops at relocated tower",wall.hit and (xf.affine_inverse()*wall.position).x < .52)
	var rig := SurfaceFacilities.build(site)
	add_child(rig)
	check("facility rendering bounded",rig.get_child_count() == 6)
	rig.queue_free()
	for other in sampler.facilities:
		if other.id == site.id: continue
		var other_xf: Transform3D = other.transform
		for index in ship.ship_count():
			ship.swap_ship(index)
			ship.landing_site = ""
			ship._pad_release = 0.0
			ship.transform.basis = other_xf.basis
			ship.reset_mesh_pose()
			ship.systems.gear_target = true
			ship.systems.step(2)
			ship.resolve_surface_motion(sampler,other_xf*Vector3(0,.25,0),other_xf*Vector3(0,-.1,0),-other_xf.basis.y*.001,6371,Basis.IDENTITY)
			check("%s accepts hull %d" % [other.id,index],ship.landing_site_id == other.id and not ship.landing_site.is_empty())
	ship.queue_free()
	await get_tree().process_frame
	print("surface_facility: ","OK" if failures == 0 else "FAIL %d" % failures)
	get_tree().quit(0 if failures == 0 else 1)
func check(label: String, value: bool) -> void:
	if not value:
		failures += 1
		push_error(label)
