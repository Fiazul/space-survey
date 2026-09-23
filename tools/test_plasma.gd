extends Node3D
var failures := 0
class FlatLand extends TerrainSampler:
	func height_m(_dir: Vector3, _detail: float = 0.0) -> float:
		return 0.0
	func max_height_km() -> float:
		return 0.0
	func is_water(_dir: Vector3) -> bool:
		return false
	func ice01(_dir: Vector3) -> float:
		return 0.0

func _ready() -> void:
	var ship := Ship.new()
	add_child(ship)
	ship.newton = true
	ship.anchor_off = Vector3.UP * 6471.0
	ship.toggle_hardpoints()
	ship.prepare_weapons()
	check("atmosphere boundary locks deployment", not ship.systems.weapons_target and not ship.weapons_ready())
	ship.anchor_off = Vector3.UP * 6470.99
	ship.toggle_hardpoints()
	check("inside atmosphere deploys", ship.systems.weapons_target)
	ship.systems.step(.5)
	check("part-deployed guns cannot fire", not ship.weapons_ready())
	ship.systems.step(.5)
	check("fully deployed guns can fire", ship.weapons_ready())
	ship.anchor_name = "Moon"
	ship.anchor_off = Vector3.UP * 1738.0
	ship.update_weapon_environment()
	check("airless body locks and stows", not ship.weapons_ready() and not ship.systems.weapons_target)
	ship.anchor_name = "Mars"
	ship.anchor_off = Vector3.UP * (Ephemeris.body_radius_km("Mars") + 79.0)
	check("other atmosphere uses its own boundary", ship.weapons_in_atmosphere())
	ship.anchor_off += Vector3.UP * 2.0
	check("Mars atmosphere exit locks", not ship.weapons_in_atmosphere())
	ship.anchor_name = "Earth"
	ship.anchor_off = Vector3.UP * 6372.0
	ship.newton = false
	check("interstellar frame stays locked", not ship.weapons_in_atmosphere())
	ship.newton = true
	var combat := Combat.new()
	add_child(combat)
	for index in ship.ship_count():
		ship.swap_ship(index)
		ship.systems.weapons_target = false
		ship.systems.step(1.0)
		combat.reset()
		combat._cool = 0.0
		ship.velocity = Vector3.RIGHT * .04
		ship.prepare_weapons()
		combat.update(ship, true, .01)
		check("fire waits for deployment hull %d" % index, combat.plasma.shots.is_empty())
		ship.systems.step(1)
		for slot in 2:
			combat._cool = 0
			combat.update(ship, true, .01)
			var shot: Dictionary = combat.plasma.shots.back()
			check("shot born at live muzzle hull %d slot %d" % [index, slot], shot.pos.distance_to(ship.muzzle_off(slot)) < .00001)
			check("shot follows barrel and inherits momentum", shot.vel.is_equal_approx(ship.velocity + ship.barrel_direction(slot)*combat.plasma.muzzle_speed()))
			check("compact pulse geometry", shot.node.mesh.get_aabb().size.length() < .005)
			check("flash belongs to firing muzzle", combat.plasma.flashes.back().node.get_parent() == ship.systems.muzzle_node(slot))
		ship.anchor_off = Vector3.UP * 6471.1
		var before := combat.energy
		combat._cool = 0
		combat.update(ship, true, .01)
		check("exit stows immediately and consumes no firing energy", not ship.systems.weapons_target and not ship.weapons_ready() and combat.energy >= before)
		ship.anchor_off = Vector3.UP * 6372.0
	combat.reset()
	var pulses := combat.plasma
	var near := {"alive": true, "pos": Vector3(0, 0, -.2), "size": .02}
	var far := {"alive": true, "pos": Vector3(0, 0, -.4), "size": .02}
	pulses.emit(Vector3.ZERO, Vector3.ZERO, Vector3.FORWARD, 2, Vector3.ZERO)
	var hits := pulses.advance(.5, Vector3.ZERO, [far, near])
	check("sweep hits closest target despite large frame step", hits.size() == 1 and hits[0].target == near and pulses.shots.is_empty())
	var flat := FlatLand.new({})
	flat.surface = {"solid": true}
	var buried := {"alive": true, "pos": Vector3.UP * 6370.9, "size": .01}
	pulses.emit(Vector3.UP * 6371.1, Vector3.ZERO, Vector3.DOWN, 2, Vector3.ZERO)
	hits = pulses.advance(.3, Vector3.ZERO, [buried], flat, Vector3.ZERO, Basis.IDENTITY, 6371)
	check("terrain blocks shots before buried targets", hits.is_empty() and pulses.shots.is_empty())
	check("solid contact produces impact flare", not pulses.bursts.is_empty())
	var district := FlatLand.new({"kind": "rocky", "surface": {"settlements": [{"name": "Test", "lat_deg": 0, "lon_deg": 0, "density": 1.0, "seed": 42}]}})
	var tower := {}
	for x in range(1, 8):
		for z in range(1, 8):
			var item := SurfaceSettlement.cell(district, district.settlements[0], x, z, 6371)
			if not item.is_empty() and item.variant == 0:
				tower = item
	check("building fixture exists", not tower.is_empty())
	if not tower.is_empty():
		var xf: Transform3D = tower.transform
		var start := xf * Vector3(-.10, .04, 0)
		var target := {"alive": true, "pos": xf * Vector3(.08, .04, 0), "size": .01}
		pulses.emit(start, Vector3.ZERO, xf.basis.x.normalized(), 1, Vector3.ZERO)
		hits = pulses.advance(.25, Vector3.ZERO, [target], district, Vector3.ZERO, Basis.IDENTITY, 6371)
		check("ruin wall blocks shots before targets", hits.is_empty() and pulses.shots.is_empty())
	pulses.emit(Vector3(2, 3, 4), Vector3.RIGHT, Vector3.FORWARD, 2, Vector3.ZERO)
	pulses.shift_frame(Vector3(1, 2, 3))
	check("reanchoring preserves shot placement", pulses.shots[0].pos == Vector3.ONE)
	pulses.advance(.1, Vector3.ZERO, [])
	check("pulse travels independently after firing", pulses.shots[0].pos.distance_to(Vector3(1.1, 1, 1.0-.1*pulses.muzzle_speed())) < .00001)
	pulses.advance(4, Vector3.ZERO, [])
	check("shots expire at finite range", pulses.shots.is_empty())
	for i in 60:
		pulses.emit(Vector3.ZERO, Vector3.ZERO, Vector3.FORWARD, 1, Vector3.ZERO)
	check("shot population remains bounded", pulses.shots.size() == PlasmaProjectiles.MAX_SHOTS)
	pulses.clear()
	var muzzle := Node3D.new()
	add_child(muzzle)
	pulses.emit(Vector3.ZERO, Vector3.ZERO, Vector3.FORWARD, 1, Vector3.ZERO, muzzle)
	pulses.advance(PlasmaProjectiles.FLASH_TIME+.01, Vector3.ZERO, [])
	check("muzzle flash is brief while projectile continues", pulses.flashes.is_empty() and pulses.shots.size() == 1)
	check("wake is bounded behind projectile", absf(pulses.shots[0].wake.position.y) <= PlasmaProjectiles.WAKE_LENGTH*.5 + .000001)
	pulses.clear()
	muzzle.queue_free()
	ship.queue_free()
	combat.queue_free()
	await get_tree().process_frame
	print("plasma: ", "OK" if failures == 0 else "FAIL %d" % failures)
	get_tree().quit(1 if failures else 0)

func check(label: String, ok: bool) -> void:
	if not ok:
		failures += 1
		push_error(label)
