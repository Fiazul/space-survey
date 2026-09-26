extends SceneTree
# Maneuvering exhaust must oppose commanded acceleration, remain proportional,
# and never fire opposing jets simply because the brake key is held.
var failures := 0

func _init() -> void:
	var model := (load("res://assets/ships/wren/wren.glb") as PackedScene).instantiate() as Node3D
	var puffs := ModularHull.add_rcs_puffs(model)
	ModularHull.drive_rcs(puffs, Vector3.ZERO, false, 1)
	check("idle jets off", puffs.all(func(p): return not p.node.visible))
	ModularHull.drive_rcs(puffs, Vector3.RIGHT * .2, false, 1)
	for p in puffs:
		if p.axis.x < -.9:
			check("partial input gives partial exhaust", p.level > .1 and p.level < .3)
		else:
			check("jets cannot push against pilot input", is_zero_approx(p.level))
	ModularHull.drive_rcs(puffs, Vector3.ZERO, true, 1)
	check("brake at rest does not fire opposing jets", puffs.all(func(p): return not p.node.visible))
	ModularHull.drive_rcs(puffs, Vector3.LEFT, true, 1)
	for p in puffs:
		check("braking fires only the useful side", p.node.visible == (p.axis.x > .9))
	ModularHull.drive_rcs(puffs, Vector3.ZERO, false, 1)
	check("exhaust decays to zero", puffs.all(func(p): return not p.node.visible))
	model.free()
	print("rcs: ", "OK" if failures == 0 else "FAIL %d" % failures)
	quit(0 if failures == 0 else 1)

func check(label: String, ok: bool) -> void:
	if not ok:
		failures += 1
		printerr("FAIL ", label)
