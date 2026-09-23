class_name FlightVector
extends Control
## Independent nose and motion cues for third-person flight. Positions are projected
## through the actual chase camera; no fake heading or screen-centred aim indicator.
var ship: Node3D
var show_nose := true
const INK := Color(0.91, 0.95, 0.93, 0.85)
const MOTION := Color(0.56, 0.86, 0.76, 0.95)

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)

func _draw() -> void:
	if ship == null or ship.camera == null or ship.frozen or ship.transiting:
		return
	var cam: Camera3D = ship.camera
	var nose: Vector3 = -ship.global_basis.z * 1000.0
	if show_nose and not cam.is_position_behind(nose):
		var p := cam.unproject_position(nose)
		draw_line(p + Vector2(-7, 3), p, INK, 1.5, true)
		draw_line(p, p + Vector2(7, 3), INK, 1.5, true)
	if ship.velocity.length() < 0.001:
		return
	var point: Vector3 = ship.velocity.normalized() * 1000.0
	var vp := get_viewport_rect().size
	var screen := cam.unproject_position(point)
	var behind := cam.is_position_behind(point)
	if behind or not Rect2(Vector2(48, 100), vp - Vector2(96, 250)).has_point(screen):
		# Put the direction cue on a compact ellipse, never over edge instruments.
		var local: Vector3 = cam.global_basis.inverse() * point
		var dir := Vector2(local.x, -local.y).normalized()
		if dir.length_squared() < 0.1:
			dir = Vector2.DOWN
		screen = vp * 0.5 + dir * Vector2(vp.x * 0.23, vp.y * 0.20)
		draw_string(ThemeDB.fallback_font, screen + Vector2(14, 5),
			"VELOCITY AFT" if behind else "VELOCITY", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, MOTION)
	draw_circle(screen, 6.0, MOTION, false, 1.5, true)
	draw_line(screen + Vector2(-13, 0), screen + Vector2(-7, 0), MOTION, 1.5, true)
	draw_line(screen + Vector2(7, 0), screen + Vector2(13, 0), MOTION, 1.5, true)
	draw_line(screen + Vector2(0, -12), screen + Vector2(0, -7), MOTION, 1.5, true)
