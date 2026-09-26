extends Node3D
var failures := 0
func _ready() -> void:
	var main := (load("res://scenes/Main.tscn") as PackedScene).instantiate()
	add_child(main)
	main.set_process(false)
	await get_tree().process_frame
	for id in ["iss","tiangong"]:
		var entry := {"name":id,"body":"Earth","mode":"station","station_id":id}
		main.dev_sites.go(entry)
		var state: Dictionary = main.orbital_stations.state_for(id)
		check("rendezvous is near %s" % id,main.ship.anchor_off.distance_to(state.position)<.401)
		check("rendezvous inherits %s velocity" % id,main.ship.velocity.is_equal_approx(state.velocity))
		main.orbital_stations.update_for(main.ship,0)
		check("station mesh instantiated for %s" % id,main.orbital_stations._nodes.has(id))
		if main.orbital_stations._nodes.has(id):
			var node: Node3D = main.orbital_stations._nodes[id]
			check("floating origin position for %s" % id,node.position.length()<.401)
			check("dated station label visible",node.get_node("Name").text.contains("2026 ORBIT DATA"))
	main.queue_free()
	await get_tree().process_frame
	print("station_scene: ","OK" if failures==0 else "FAIL %d" % failures)
	get_tree().quit(0 if failures==0 else 1)
func check(label: String, ok: bool) -> void:
	if not ok:
		failures += 1
		push_error(label)
