class_name Navigator
extends Control
# Two things, both fed by main each frame:
#  1) A 3D orientation gizmo (world X/Y/Z axes) so you always know up/down/
#     forward/back in space — it tumbles as you pitch/roll/yaw.
#  2) A waypoint marker for the current Tab target: a diamond + label when it's
#     on screen, or an arrow pinned to the screen edge pointing toward it.

const COL := Color(0.62, 1.0, 0.82)   # light silvery-teal (normal/Tab waypoint)
const LOCK_COL := Color(1.0, 0.6, 0.15)   # orange — a LOCKED map waypoint
const MARKER_FONT := 12               # smaller, designed marker label
const EDGE_MARGIN := 46.0
const GIZMO_POS := Vector2(1208, 486)
const GIZMO_LEN := 42.0

var _cam: Camera3D
# Every active waypoint at once. Each entry: { rel: Vector3, name, dist, color }.
# main rebuilds this list each frame (quest + up to 3 X marks + Tab + locked guide).
var _markers: Array = []


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


# Replace the whole marker set. Pass [] for gizmo-only (transit / nav off).
func set_markers(cam: Camera3D, markers: Array) -> void:
	_cam = cam
	_markers = markers
	queue_redraw()


func _draw() -> void:
	if _cam == null:
		return
	# World-axis developer gizmo retired; HUD shows projected nose and motion.
	for m in _markers:
		_draw_marker(m.rel, String(m.name), String(m.dist), m.color, bool(m.get("drop", false)))


# --- 3D orientation gizmo ---------------------------------------------------
func _draw_gizmo() -> void:
	var font := ThemeDB.fallback_font
	var inv := _cam.global_transform.basis.inverse()
	# world axis -> (screen dir, depth, color, label)
	var axes := [
		{ "v": Vector3.UP,       "c": Color(0.5, 1.0, 0.6), "l": "UP" },
		{ "v": Vector3.DOWN,     "c": Color(0.3, 0.55, 0.4), "l": "" },
		{ "v": Vector3.RIGHT,    "c": Color(1.0, 0.5, 0.5), "l": "X" },
		{ "v": Vector3.FORWARD,  "c": Color(0.5, 0.7, 1.0), "l": "Z" },
		{ "v": Vector3.BACK,     "c": Color(0.35, 0.5, 0.7), "l": "" },
	]
	# Draw far axes first so near ones overlay them.
	axes.sort_custom(func(a, b): return (inv * a.v).z > (inv * b.v).z)
	draw_circle(GIZMO_POS, 4.0, Color(0.8, 0.9, 1.0, 0.9))
	for ax in axes:
		var local: Vector3 = inv * ax.v
		var dir := Vector2(local.x, -local.y)
		var tip: Vector2 = GIZMO_POS + dir * GIZMO_LEN
		var fade: float = 1.0 if local.z < 0.0 else 0.5      # behind = dimmer
		var col: Color = ax.c
		col.a = fade
		draw_line(GIZMO_POS, tip, col, 2.0, true)
		if ax.l != "":
			draw_string(font, tip + Vector2(-5, 5), ax.l, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, col)


# --- waypoint marker --------------------------------------------------------
func _draw_marker(wrel: Vector3, mname: String, dist: String, col: Color, drop := false) -> void:
	var font := ThemeDB.fallback_font
	var vp := get_viewport_rect().size
	var center := vp * 0.5
	var local: Vector3 = _cam.global_transform.affine_inverse() * wrel
	var in_front := local.z < 0.0
	var screen := _cam.unproject_position(wrel)
	var on_screen := in_front and Rect2(Vector2.ZERO, vp).has_point(screen)

	if on_screen:
		_draw_diamond(screen, 9.0, col)
		if drop:
			_draw_drop(screen + Vector2(0, -17), col)   # "already marked" badge above the diamond
		var txt := "%s   %s" % [mname, dist]
		var w := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, MARKER_FONT).x
		_draw_label(font, screen + Vector2(-w * 0.5, 24), txt, col)
	else:
		var dir := screen - center
		if not in_front:
			dir = -dir
		if dir.length() < 0.001:
			dir = Vector2(0, -1)
		var edge := _edge_point(center, dir.normalized(), vp)
		_draw_arrow(edge, dir.angle(), col)
		var txt := "%s  %s" % [mname, dist]
		var tw := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, MARKER_FONT).x
		var tx := clampf(edge.x - tw * 0.5, 8.0, vp.x - tw - 8.0)
		var ty := clampf(edge.y + 30.0, 24.0, vp.y - 10.0)
		_draw_label(font, Vector2(tx, ty), txt, col)


# Designed marker text: a soft dark drop-shadow behind a bright top layer reads as
# crisp, slightly metallic lettering (draw_string can't gradient, so this fakes depth).
func _draw_label(font: Font, pos: Vector2, txt: String, col: Color) -> void:
	draw_string(font, pos + Vector2(1, 1), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, MARKER_FONT, Color(0.02, 0.04, 0.02, 0.85))
	draw_string(font, pos, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, MARKER_FONT, col)


# A small water-drop badge (round base, pointed top) drawn above a marker to say
# "this target is already marked" — a visual flag, not a text overlay.
func _draw_drop(c: Vector2, col: Color) -> void:
	draw_circle(c, 3.6, col)
	var tri := PackedVector2Array([c + Vector2(0, -8.5), c + Vector2(-3.3, -1.2), c + Vector2(3.3, -1.2)])
	draw_colored_polygon(tri, col)
	draw_circle(c + Vector2(-1.0, -0.6), 1.0, Color(1, 1, 1, 0.7))   # tiny glint


func _draw_diamond(c: Vector2, r: float, col: Color) -> void:
	var pts := PackedVector2Array([
		c + Vector2(0, -r), c + Vector2(r, 0), c + Vector2(0, r), c + Vector2(-r, 0), c + Vector2(0, -r)])
	draw_polyline(pts, col, 2.0, true)

func _draw_arrow(tip: Vector2, ang: float, col: Color) -> void:
	var d := Vector2(cos(ang), sin(ang))
	var n := Vector2(-d.y, d.x)
	var p := PackedVector2Array([tip, tip - d * 22 + n * 11, tip - d * 22 - n * 11])
	draw_colored_polygon(p, col)

func _edge_point(center: Vector2, dir: Vector2, vp: Vector2) -> Vector2:
	var half := vp * 0.5 - Vector2(EDGE_MARGIN, EDGE_MARGIN)
	var sx := half.x / maxf(absf(dir.x), 0.0001)
	var sy := half.y / maxf(absf(dir.y), 0.0001)
	return center + dir * minf(sx, sy)
