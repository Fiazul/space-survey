extends SceneTree

func _initialize() -> void:
	var structures := SurfaceStructures.new()
	var completion := {"done": false}
	structures.set("_pending", true)
	structures.set("_task", WorkerThreadPool.add_task(func():
		OS.delay_msec(25)
		completion.done = true))
	structures.free()
	if not completion.done:
		printerr("scenery_worker_lifetime: FAIL detached ruins worker survived its owner")
		quit(1)
		return
	print("scenery_worker_lifetime: OK")
	quit()
