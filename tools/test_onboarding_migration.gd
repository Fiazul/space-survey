class_name TestOnboardingMigration
extends Node
## A saved onboarding_step indexes the step list that shipped when it was written;
## Onboarding._ready must re-derive it from the completed-id set.
const OLD_IDS := ["thrust", "scan", "claim", "map", "log", "wormhole", "dock", "teleport_net", "fire", "swarm", "boss"]

func _ready() -> void:
	var failed := 0
	failed += _case("old index past new length completes", 11, OLD_IDS, 6, "")
	failed += _case("old mid-list index resumes at first unfinished id", 5, OLD_IDS.slice(0, 5), 3, "dock")
	failed += _case("old claim step resumes at log", 2, ["thrust", "scan"], 2, "log")
	failed += _case("fresh game starts at thrust", 0, [], 0, "thrust")
	GameState.reset()
	print("onboarding_migration: ", "OK" if failed == 0 else "FAIL (%d)" % failed)
	get_tree().quit(0 if failed == 0 else 1)

func _case(label: String, old_step: int, done: Array, want_step: int, want_id: String) -> int:
	GameState.onboarding_step = old_step
	GameState.onboarding_done = {}
	for id in done:
		GameState.onboarding_done[id] = true
	var ob := Onboarding.new()
	add_child(ob)
	var st: Dictionary = ob.state()
	var ok: bool = GameState.onboarding_step == want_step and ob.current_step_id() == want_id \
		and st.complete == (want_id == "") and ob._ob_done_toast == (want_id == "")
	print("  %s %s (step %d, id '%s')" % ["PASS" if ok else "FAIL", label, GameState.onboarding_step, ob.current_step_id()])
	ob.queue_free()
	return 0 if ok else 1
