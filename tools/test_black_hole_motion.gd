class_name TestBlackHoleMotion
extends Node3D

func _ready() -> void:
	ProfileDir.isolate("test_black_hole_motion")
	get_window().mode = Window.MODE_WINDOWED
	get_window().size = Vector2i(1280,720)
	var cfg := ConfigFile.new()
	cfg.set_value("player","system",SystemDB.SAGITTARIUS_A)
	cfg.save(GameState.profile_path())
	var main: Node = load("res://scenes/Main.tscn").instantiate()
	add_child(main)
	main.set_process(false)
	main.onboarding.set_process(false)
	main.dev_sites.go_core({"au":2.0,"polar":false})
	main.ship._set_capture(false)
	main.ship.velocity = Vector3.ZERO
	main._process(0.0)
	var observer: Vector3 = main.ship.anchor_off
	var output := OS.get_environment("MOTION_SHOT_DIR")
	if output.is_empty(): output = "/tmp/astryx-black-hole-motion"
	DirAccess.make_dir_recursive_absolute(output)
	for i in 5: await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var previous := get_viewport().get_texture().get_image()
	previous.save_png(output.path_join("motion_0.png"))
	var samples := 0
	var failures := 0
	for sample in 4:
		# Use the real per-frame update at normal speed, holding only the observer
		# fixed so measured plasma changes cannot come from camera movement.
		for frame in 10:
			main.ship.relocate(observer)
			main.ship.velocity = Vector3.ZERO
			main._process(1.0/20.0)
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var current := get_viewport().get_texture().get_image()
		current.save_png(output.path_join("motion_%d.png" % (sample+1)))
		var plasma := 0
		var changing := 0
		var variation := 0.0
		for y in range(100,340):
			for x in range(200,1080):
				var a := previous.get_pixel(x,y)
				var b := current.get_pixel(x,y)
				if a.r < .15 or a.r < a.b*1.5: continue
				plasma += 1
				var change := (absf(a.r-b.r)+absf(a.g-b.g)+absf(a.b-b.b))/3.0
				variation += change
				if change > .025: changing += 1
		var mean := variation/maxi(plasma,1)
		print("black_hole_motion: %.1fs normal playback, %d/%d moving pixels, mean change %.5f" % [float(sample+1)*.5,changing,plasma,mean])
		if plasma < 1000 or changing < plasma*.10 or mean < .01:
			push_error("Normal-speed plasma looks frozen at %.1fs" % (float(sample+1)*.5))
			failures += 1
		previous = current
		samples += 1
	var hole: ShaderMaterial = main.planets._bodies.filter(func(b): return b.name == "Sagittarius A*")[0].mat
	var start := await hotspot_centroid(main,hole,observer,output,"hotspots_0s")
	for frame in 40:
		main.ship.relocate(observer)
		main.ship.velocity = Vector3.ZERO
		main._process(1.0/20.0)
	var moved := await hotspot_centroid(main,hole,observer,output,"hotspots_2s")
	var shift: float = start.distance_to(moved)
	print("black_hole_motion: hotspot light centroid moved %.3f px in 2 s at 1x (%s -> %s)" % [shift,start,moved])
	# True Kerr motion near the ISCO is ~0.25-0.5 px/s at 2 AU; the sensor view
	# multiplies it by TIME_LAPSE and nothing else.
	if shift < 1.0 or shift > 4.0*BlackHoleRenderer.TIME_LAPSE:
		push_error("Hotspot centroid shift %.3f px over 2 s is outside the physical range" % shift)
		failures += 1
	var elapsed := 2
	for seconds in [30, 60, 120]:
		for step in seconds - elapsed:
			main.ship.relocate(observer)
			main.ship.velocity = Vector3.ZERO
			main._process(1.0)
		elapsed = seconds
		await hotspot_centroid(main,hole,observer,output,"hotspots_%ds" % seconds)
	failures += await along_disk(main, output)
	print("black_hole_motion: ","OK" if failures == 0 and samples == 4 else "FAIL")
	main.queue_free()
	await get_tree().process_frame
	get_tree().quit(1 if failures else 0)

# Light from the hotspots alone: the same frame with and without them.
func hotspot_centroid(main: Node, hole: ShaderMaterial, observer: Vector3, output: String, label: String) -> Vector2:
	main.ship.relocate(observer)
	main.ship.velocity = Vector3.ZERO
	main._process(0.0)
	for i in 3: await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var lit := get_viewport().get_texture().get_image()
	var spots: Array = hole.get_shader_parameter("hotspots")
	hole.set_shader_parameter("hotspots", spots.map(func(v): return Vector4(v.x, v.y, v.z, 0.0)))
	for i in 3: await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var dark := get_viewport().get_texture().get_image()
	hole.set_shader_parameter("hotspots", spots)
	lit.save_png(output.path_join(label+".png"))
	var weight := 0.0
	var sum := Vector2.ZERO
	var only := Image.create(lit.get_width(), lit.get_height(), false, Image.FORMAT_RGB8)
	for y in lit.get_height():
		for x in lit.get_width():
			var a := lit.get_pixel(x,y)
			var b := dark.get_pixel(x,y)
			var w := maxf(a.r-b.r+a.g-b.g+a.b-b.b, 0.0)
			only.set_pixel(x,y,Color(w,w,w))
			weight += w
			sum += Vector2(x,y)*w
	only.save_png(output.path_join(label+"_only.png"))
	return sum/maxf(weight,.000001)

# From ~1.2 AU looking along the disk, the flow filling the view must visibly
# move within 2.5 s at 1x. The clock alone advances, so the camera cannot.
func along_disk(main: Node, output: String) -> int:
	main.dev_sites.go_core({"au":1.2,"polar":false})
	main.ship._set_capture(false)
	main.ship.velocity = Vector3.ZERO
	main._process(0.0)
	var before := await still_frame(main, output, "along_disk_0s")
	var control := await still_frame(main, output, "along_disk_0s_again")
	Ephemeris.rotation_clock.advance(2.5)
	var after := await still_frame(main, output, "along_disk_2_5s")
	var moving := moving_fraction(before, after)
	var still := moving_fraction(before, control)
	print("black_hole_motion: 1.2 AU along the disk, %.1f%% of flow pixels change in 2.5 s at 1x (%.2f%% with the clock held)" % [moving*100.0, still*100.0])
	if moving < .1 or still > .01:
		push_error("Flow seen from 1.2 AU does not visibly move within 2.5 s")
		return 1
	return 0

func still_frame(main: Node, output: String, label: String) -> Image:
	main._process(0.0)
	for i in 3: await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var shot := get_viewport().get_texture().get_image()
	shot.save_png(output.path_join(label+".png"))
	return shot

func moving_fraction(a: Image, b: Image) -> float:
	var plasma := 0
	var changing := 0
	for y in range(80, 600, 2):
		for x in range(40, 1240, 2):
			var p := a.get_pixel(x,y)
			if p.r < .15 or p.r < p.b*1.5: continue
			plasma += 1
			var q := b.get_pixel(x,y)
			if (absf(p.r-q.r)+absf(p.g-q.g)+absf(p.b-q.b))/3.0 > .025: changing += 1
	return float(changing)/maxf(plasma, 1.0)
