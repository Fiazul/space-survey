extends Control
## Fire-control pipper, separate from FlightVector's unchanged velocity circle.
const INK := Color(.83, .93, 1.0, .95)
const GOOD := Color(.48, 1.0, .72, 1)
const WARN := Color(1.0, .68, .32, 1)
var solution := {}
var _kick := 0.0
var _target_point := Vector2.INF
var _lead_point := Vector2.INF

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func set_target(_bloom: float, kick: float) -> void:
	_kick = kick
	queue_redraw()

func set_solution(value: Dictionary, camera: Camera3D) -> void:
	solution = value
	_target_point = Vector2.INF
	_lead_point = Vector2.INF
	if value.is_empty() or camera == null or camera.is_position_behind(value.point):
		visible = false
		return
	var screen := camera.unproject_position(value.point)
	visible = get_viewport_rect().grow(-12).has_point(screen)
	position = screen-size*.5
	var target: Dictionary = value.get("target", {})
	if not target.is_empty():
		if not camera.is_position_behind(target.position):
			_target_point = camera.unproject_position(target.position)-position
		if not camera.is_position_behind(target.lead):
			_lead_point = camera.unproject_position(target.lead)-position
	queue_redraw()

func _draw() -> void:
	if solution.is_empty():
		return
	var c := size*.5
	var col := GOOD if solution.get("assisted", false) else INK
	if solution.get("blocked", false) or not solution.get("ready", false) or solution.state == "OUT OF RANGE":
		col = WARN
	# Small open centre leaves the actual impact point visible.
	for axis in [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]:
		draw_line(c+axis*3, c+axis*7, col, 1.0, true)
	if _kick > 0:
		for s in [Vector2(-1,-1), Vector2(1,-1), Vector2(1,1), Vector2(-1,1)]:
			draw_line(c+s*9, c+s*12, Color(1,1,1,_kick), 1, true)
	var label := str(solution.get("state", "PLASMA"))
	var distance := float(solution.get("distance", 0))
	var target: Dictionary = solution.get("target", {})
	if not target.is_empty():
		distance = target.distance
	var range_text := "%.0f m" % (distance*1000) if distance < 1 else "%.2f km" % distance
	draw_string(ThemeDB.fallback_font, c+Vector2(-70, 39), range_text, HORIZONTAL_ALIGNMENT_CENTER, 140, 12, col)
	draw_string(ThemeDB.fallback_font, c+Vector2(-70, 24), label, HORIZONTAL_ALIGNMENT_CENTER, 140, 10, col)
	if _target_point != Vector2.INF:
		var p := _target_point
		for s in [Vector2(-1,-1), Vector2(1,-1), Vector2(1,1), Vector2(-1,1)]:
			var a: Vector2 = p+s*13
			draw_line(a, a-Vector2(s.x*4,0), WARN, 1, true)
			draw_line(a, a-Vector2(0,s.y*4), WARN, 1, true)
	if _lead_point != Vector2.INF and not target.is_empty() and target.in_range:
		var p := _lead_point
		if _target_point != Vector2.INF and p.distance_to(_target_point) > 25:
			draw_dashed_line(_target_point, p, Color(.75,.83,.9,.4), 1, 4, true)
		var diamond := PackedVector2Array([p+Vector2(0,-5), p+Vector2(5,0), p+Vector2(0,5), p+Vector2(-5,0), p+Vector2(0,-5)])
		draw_polyline(diamond, GOOD if solution.get("assisted",false) else INK, 1.0, true)
