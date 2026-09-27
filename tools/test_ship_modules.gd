extends Node3D
# Swapping the weapon / pad set rebuilds the modules under every socket in place:
# the scene changes, MUZZLE and FOOT move, gear state survives, and the choice
# persists through GameState's profile round trip.

var failures := 0

func _ready() -> void:
	var saved := [GameState.visited.duplicate(), GameState.weapon_set, GameState.pad_set]
	for i in 12:
		GameState.visited["test_system_%d" % i] = true
	GameState.weapon_set = "mk1"
	GameState.pad_set = "mk1"
	var ship := Ship.new()
	add_child(ship)
	for index in [1, 3, 6]:
		ship.swap_ship(index)
		ship.set_weapon_set("mk1")
		ship.set_pad_set("mk1")
		var rig := ship.systems
		rig.gear_target = true
		rig.step(2.0)
		_check("hull %d starts on mk1 weapons" % index, _scenes(rig.mounts, "weapon_mk1.glb"))
		_check("hull %d starts on mk1 pads" % index, _scenes(rig.legs, "pad_mk1.glb"))
		var muzzles := _muzzles(rig)
		var feet := rig.foot_points()

		ship.set_weapon_set("mk2")
		var armed := ship.systems
		_check("hull %d weapon swap rebuilds in place" % index, armed != rig and rig.is_queued_for_deletion() \
			and armed.get_parent() == ship.get("_mesh_root"))
		_check("hull %d gear state carried" % index, armed.gear_target and armed.gear_fraction == 1.0)
		_check("hull %d weapons now mk2" % index, _scenes(armed.mounts, "weapon_mk2.glb"))
		_check("hull %d pads untouched by weapon swap" % index, _scenes(armed.legs, "pad_mk1.glb"))
		var moved := _muzzles(armed)
		for slot in muzzles.size():
			_check("hull %d muzzle %d moved" % [index, slot], moved[slot].distance_to(muzzles[slot]) > 1e-6)
			_check("hull %d muzzle node %d is the rebuilt marker" % [index, slot],
				armed.muzzle_node(slot) != null and armed.muzzle_node(slot).get_parent() == armed.mounts[slot].carriage)
		_check("hull %d feet unchanged by weapon swap" % index, _same(feet, armed.foot_points()))

		ship.set_pad_set("mk2")
		var padded := ship.systems
		_check("hull %d pads now mk2" % index, _scenes(padded.legs, "pad_mk2.glb"))
		_check("hull %d weapons kept mk2" % index, _scenes(padded.mounts, "weapon_mk2.glb"))
		var new_feet := padded.foot_points()
		_check("hull %d one foot per pad" % index, new_feet.size() == feet.size() and not feet.is_empty())
		for f in new_feet.size():
			_check("hull %d foot %d moved" % [index, f], new_feet[f].distance_to(feet[f]) > 1e-6)
			_check("hull %d foot %d below hull" % [index, f], new_feet[f].y < ship._hull_box.position.y)
		_check("hull %d feet share one plane" % index, _level(new_feet))

	ship.set_weapon_set("mk9")
	_check("unknown set ignored", GameState.weapon_set == "mk2")
	var cfg := ConfigFile.new()
	GameState.save_into(cfg)
	GameState.weapon_set = "mk1"
	GameState.pad_set = "mk1"
	GameState.load_from(cfg)
	_check("sets persist", GameState.weapon_set == "mk2" and GameState.pad_set == "mk2")
	GameState.visited = {SystemDB.SOL: true}
	_check("locked tier refused", not ship.swap_ship(1))

	GameState.visited = saved[0]
	GameState.weapon_set = saved[1]
	GameState.pad_set = saved[2]
	ship.queue_free()
	await get_tree().process_frame
	print("ship_modules: ", "OK" if failures == 0 else "FAIL %d" % failures)
	get_tree().quit(0 if failures == 0 else 1)


func _scenes(parts: Array, file: String) -> bool:
	if parts.is_empty():
		return false
	for part in parts:
		if not String((part.module as Node).scene_file_path).ends_with(file):
			return false
	return true


func _muzzles(rig: ShipSystems) -> Array:
	var out := []
	for slot in rig.mounts.size():
		out.append(rig.muzzle_local(slot))
	return out


func _same(a: PackedVector3Array, b: PackedVector3Array) -> bool:
	if a.size() != b.size():
		return false
	for i in a.size():
		if a[i].distance_to(b[i]) > 1e-7:
			return false
	return true


func _level(points: PackedVector3Array) -> bool:
	for p in points:
		if absf(p.y - points[0].y) > 1e-6:
			return false
	return true


func _check(label: String, ok: bool) -> void:
	if not ok:
		failures += 1
		push_error("ship_modules: " + label)
