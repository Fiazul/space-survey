class_name TestHumanoRunner
extends Node

var failures := 0

func check(label: String, ok: bool) -> void:
	if not ok:
		failures += 1
		push_error("humano_runner: " + label)

func _ready() -> void:
	var script := load("res://scripts/ui/humano_runner.gd") as Script
	check("runner exists", script != null)
	if script == null:
		get_tree().quit(1)
		return
	var runner = script.new()
	add_child(runner)
	runner.set_process(false)
	check("starts waiting for a jump", not runner.running and not runner.crashed)
	runner.jump()
	runner.advance(.1)
	check("jump starts the game and lifts the human", runner.running and runner.player_y > 0.0)
	var speed: float = runner.vertical_speed
	runner.jump()
	check("no second jump while airborne", runner.vertical_speed == speed)
	for frame in 120: runner.advance(1.0/120.0)
	check("lands without falling through the floor", runner.player_y == 0.0 and runner.vertical_speed == 0.0)
	check("running earns a score", runner.distance > 0.0 and runner.score > 0)
	runner.obstacles.append({"x":110.0, "width":24.0, "height":38.0})
	runner.advance(.01)
	check("ground obstacle ends the run", runner.crashed and not runner.running)
	var best: int = runner.best
	runner.jump()
	check("jump restarts after a collision", runner.running and not runner.crashed and runner.best == best)
	runner.advance(.1)
	runner.obstacles.append({"x":110.0, "width":24.0, "height":24.0})
	runner.advance(.01)
	check("a high jump clears the obstacle", not runner.crashed)
	runner.advance(20.0)
	check("large deltas keep finite bounded motion", is_finite(runner.player_y) and runner.player_y >= 0.0)
	runner.reset_run()
	check("reset clears obstacles and preserves best", runner.obstacles.is_empty() and runner.distance == 0.0 and runner.best == best)
	runner.free()
	print("humano_runner: ", "OK" if failures == 0 else "FAIL %d" % failures)
	get_tree().quit(1 if failures else 0)
