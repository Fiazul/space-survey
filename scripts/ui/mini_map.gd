class_name MiniMap
extends Control
# Corner radar / navigator assistant. Ship-relative top-down blips (heading = up):
# every body in the system, plus Earth/home (green), the nearest body (cyan ring)
# and surveyed bodies (gold). Far blips clamp to the rim, so each blip is also a
# "which way to turn" arrow. main feeds it ship basis + blip data each frame.

const R := 86.0
const PANEL := Vector2(196, 196)
const DIST_SCALE := 0.072       # units -> radar px (then clamped to the rim) — ÷10 for the spread

# roles
const BODY := 0
const SURVEYED := 4
const HOME := 1
const NEAREST := 2

var _blips := []                # [{ local: Vector3, dist: float, role: int, name: String }]


func _ready() -> void:
	size = PANEL
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func set_blips(blips: Array) -> void:
	_blips = blips
	queue_redraw()


func _draw() -> void:
	var c := PANEL * 0.5
	var font := ThemeDB.fallback_font

	# Backdrop + rim + crosshair.
	draw_circle(c, R + 8, Color(0.03, 0.05, 0.09, 0.72))
	draw_arc(c, R, 0, TAU, 56, Color(0.4, 0.7, 1.0, 0.55), 2.0)
	draw_arc(c, R * 0.5, 0, TAU, 40, Color(0.4, 0.7, 1.0, 0.18), 1.0)
	draw_line(c - Vector2(R, 0), c + Vector2(R, 0), Color(0.3, 0.5, 0.7, 0.18))
	draw_line(c - Vector2(0, R), c + Vector2(0, R), Color(0.3, 0.5, 0.7, 0.18))

	# Sort so important markers draw on top.
	var ordered := _blips.duplicate()
	ordered.sort_custom(func(a, b): return a.role < b.role)
	for blip in ordered:
		# Ship-local: x = right, z = forward(-). Map forward -> up on screen.
		var dir := Vector2(blip.local.x, blip.local.z)
		if dir.length() < 0.0001:
			continue
		var r_px: float = minf(blip.dist * DIST_SCALE, R - 4.0)
		var p: Vector2 = c + dir.normalized() * r_px
		match blip.role:
			HOME:
				draw_circle(p, 5.0, Color(0.4, 1.0, 0.55))
				draw_string(font, p + Vector2(7, 4), "Earth", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.5, 1.0, 0.6))
			NEAREST:
				draw_arc(p, 6.0, 0, TAU, 14, Color(0.5, 1.0, 1.0), 2.0)
				draw_string(font, p + Vector2(8, 4), blip.name, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.6, 1.0, 1.0))
			SURVEYED:
				draw_circle(p, 3.5, Color(1.0, 0.84, 0.3))
				draw_arc(p, 5.5, 0, TAU, 12, Color(1.0, 0.84, 0.3, 0.7), 1.5)
			_:
				draw_circle(p, 3.0, Color(0.8, 0.85, 0.95, 0.85))

	# Ship at center — a triangle pointing up (current heading).
	var tri := PackedVector2Array([c + Vector2(0, -9), c + Vector2(6, 7), c + Vector2(-6, 7)])
	draw_colored_polygon(tri, Color(0.7, 1.0, 0.9))
	draw_string(font, Vector2(8, 16), "RADAR", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.5, 0.7, 0.9, 0.8))
