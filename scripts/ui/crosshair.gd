extends Control
## Fire-control pipper, separate from FlightVector's unchanged velocity circle.
const INK := Color(.83, .93, 1.0, .95)
const GOOD := Color(.48, 1.0, .72, 1)
const WARN := Color(1.0, .68, .32, 1)
var solution := {}
var _kick := 0.0
var _firing := false
var _target_point := Vector2.INF
var _lead_point := Vector2.INF

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func set_target(bloom: float, kick: float) -> void:
	_firing = bloom > .0
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
	for side in [-1.0, 1.0]:
		var x: float = side*11.0
		draw_line(c+Vector2(x, -6), c+Vector2(x, 6), col, 1.5, true)
		draw_line(c+Vector2(x, 0), c+Vector2(side*5, 0), col, 1.5, true)
	draw_line(c+Vector2(-2, 0), c+Vector2(2, 0), col, 2.0, true)
	draw_line(c+Vector2(0, -2), c+Vector2(0, 2), col, 2.0, true)
	if _firing:
		draw_line(c+Vector2(-5, 12), c+Vector2(5, 12), INK, 2.0, true)
	if _kick > 0:
		for s in [Vector2(-1,-1), Vector2(1,-1), Vector2(1,1), Vector2(-1,1)]:
			draw_line(c+s*15, c+s*20, Color(1,1,1,_kick), 2, true)
	var label := str(solution.get("state", "PLASMA"))
	var distance := float(solution.get("distance", 0))
	var target: Dictionary = solution.get("target", {})
	if not target.is_empty():
		distance = target.distance
	var range_text := "%.0f m" % (distance*1000) if distance < 1 else "%.2f km" % distance
	draw_string(ThemeDB.fallback_font, c+Vector2(-70, 49), range_text, HORIZONTAL_ALIGNMENT_CENTER, 140, 12, col)
	draw_string(ThemeDB.fallback_font, c+Vector2(-70, 33), label, HORIZONTAL_ALIGNMENT_CENTER, 140, 10, col)
	if _target_point != Vector2.INF:
		var p := _target_point
		for s in [Vector2(-1,-1), Vector2(1,-1), Vector2(1,1), Vector2(-1,1)]:
			var a: Vector2 = p+s*19
			draw_line(a, a-Vector2(s.x*7,0), WARN, 1, true)
			draw_line(a, a-Vector2(0,s.y*7), WARN, 1, true)
	if _lead_point != Vector2.INF and not target.is_empty() and target.in_range:
		var p := _lead_point
		if _target_point != Vector2.INF and p.distance_to(_target_point) > 25:
			draw_dashed_line(_target_point, p, Color(.75,.83,.9,.4), 1, 4, true)
		var diamond := PackedVector2Array([p+Vector2(0,-8), p+Vector2(8,0), p+Vector2(0,8), p+Vector2(-8,0), p+Vector2(0,-8)])
		draw_polyline(diamond, GOOD if solution.get("assisted",false) else INK, 1.5, true)
