class_name TouchControls
extends CanvasLayer
# Native multi-touch flight controls leave flight clear: FIRE and THRUST stay in the
# bottom-right and MENU opens the remaining actions.

var ship: Node
var main: Node
const LOOK_SENS := 0.6
const MOUSE_FINGER := -7
const EDGE := 16.0
const GAP := 12.0
const FONT := 19
const JOY_ZONE_FRACTION := 0.45
const RING_R := 64.0
const ACTIONS := ["HOME", "MAP", "ARMS", "INTERACT", "GEAR", "BOOST", "UP", "DOWN", "ZOOM−", "ZOOM+", "TELEPORT", "SYSTEMS", "DEV"]
enum { CRUISE, HOLD_KEY, FIRE, TAP_KEY, PITCH, ZOOM, TELEPORT, SYSTEMS, DEV, MENU }
var _use_mouse := not OS.has_feature("mobile")
var _buttons: Array = []
var _finger := {}
var _menu_open := false
var _scale := 1.0
var _insets := {"left": 0.0, "top": 0.0, "right": 0.0, "bottom": 0.0}
var _cruise: Dictionary
var _joy: Control
var _joy_finger := -1
var _joy_origin := Vector2.ZERO
var _joy_now := Vector2.ZERO
var _look_idx: Array = []
var _finger_pos := {}
var _pinch_start_zoom := 1.0
var _pinch_start_dist := 0.0
var _pitch := {}

func _ready() -> void:
	layer = 90
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	get_viewport().size_changed.connect(_layout)

func _build() -> void:
	_add("FIRE", FIRE)
	_cruise = _add("THRUST", CRUISE)
	_add("MENU", MENU)
	_add("HOME", TAP_KEY, KEY_H, true)
	_add("MAP", TAP_KEY, KEY_M, true)
	_add("ARMS", TAP_KEY, KEY_R, true)
	_add("INTERACT", TAP_KEY, KEY_F, true)
	_add("GEAR", TAP_KEY, KEY_B, true)
	_add("BOOST", HOLD_KEY, KEY_SHIFT, true)
	_add("UP", PITCH, -1, true)
	_add("DOWN", PITCH, 1, true)
	_add("ZOOM−", ZOOM, -1, true)
	_add("ZOOM+", ZOOM, 1, true)
	_add("TELEPORT", TELEPORT, 0, true)
	_add("SYSTEMS", SYSTEMS, 0, true)
	_add("DEV", DEV, 0, true)
	var close := _add("×", MENU, 0, true)
	close.node.set_meta("close", true)
	_joy = Control.new()
	_joy.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_joy.set_anchors_preset(Control.PRESET_FULL_RECT)
	_joy.visible = false
	_joy.draw.connect(_draw_joy)
	add_child(_joy)
	_layout()

func _add(text: String, kind: int, code: int = 0, menu := false) -> Dictionary:
	var node := Button.new()
	node.text = text
	node.focus_mode = Control.FOCUS_NONE
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	node.add_theme_font_size_override("font_size", FONT)
	node.add_theme_color_override("font_color", Color(0.95, 0.98, 1.0))
	for state in ["normal", "hover", "pressed"]:
		node.add_theme_stylebox_override(state, _box(_tint(text), 0.45 if state != "pressed" else 0.9))
	add_child(node)
	var button := {"node": node, "kind": kind, "code": code, "menu": menu, "tint": _tint(text)}
	_buttons.append(button)
	return button

func _tint(text: String) -> Color:
	if text == "FIRE":
		return Color(1.0, 0.5, 0.35)
	if text == "THRUST":
		return Color(0.4, 0.9, 0.6)
	if text == "DEV":
		return Color(1.0, 0.85, 0.3)
	return Color(0.55, 0.85, 1.0)

func _layout() -> void:
	var size := get_viewport().get_visible_rect().size
	_insets = HudScale.safe_insets(size)
	_scale = overlay_scale(size, HudScale.touch_scale(), _insets)
	var rects := button_rects(size, _scale, _insets)
	rects.merge(menu_rects(size, _scale, _insets), true)
	for button in _buttons:
		var rect: Rect2 = rects.get(button.node.text, Rect2())
		button.node.position = rect.position
		button.node.size = rect.size
		button.node.add_theme_font_size_override("font_size", roundi(FONT * _scale))

static func overlay_scale(size: Vector2, desired: float, insets: Dictionary) -> float:
	return minf(HudScale.fit_scale(desired, 270.0, size.x * 0.30 - float(insets.right)), HudScale.fit_scale(desired, 160.0, size.y - float(insets.top) - float(insets.bottom)))

static func button_rects(size: Vector2, scale: float, insets: Dictionary) -> Dictionary:
	var right := size.x - float(insets.right) - EDGE * scale
	var bottom := size.y - float(insets.bottom) - EDGE * scale
	var large := Vector2(120, 120) * scale
	var fire := Rect2(Vector2(right - large.x, bottom - large.y), large)
	return {"FIRE": fire, "THRUST": Rect2(Vector2(fire.position.x - GAP * scale - large.x, fire.position.y), large), "MENU": Rect2(Vector2(right - 76.0 * scale, float(insets.top) + EDGE * scale), Vector2(76, 34) * scale)}

static func menu_rects(size: Vector2, scale: float, insets: Dictionary) -> Dictionary:
	var cell := Vector2(118, 46) * scale
	var gap := 8.0 * scale
	var rows := ceili(float(ACTIONS.size()) / 3.0)
	var panel := Vector2(cell.x * 3.0 + gap * 2.0, cell.y * rows + gap * (rows - 1))
	var origin := (size - panel) * 0.5
	origin.x = clampf(origin.x, float(insets.left) + EDGE, size.x - float(insets.right) - panel.x - EDGE)
	origin.y = clampf(origin.y, float(insets.top) + EDGE + 38.0 * scale, size.y - float(insets.bottom) - panel.y - EDGE)
	var out := {"×": Rect2(Vector2(origin.x + panel.x - 30.0 * scale, origin.y - 36.0 * scale), Vector2(30, 30) * scale)}
	for i in ACTIONS.size():
		out[ACTIONS[i]] = Rect2(origin + Vector2((i % 3) * (cell.x + gap), (i / 3) * (cell.y + gap)), cell)
	return out

static func visible_flight_buttons() -> PackedStringArray:
	return PackedStringArray(["FIRE", "THRUST", "MENU"])


static func menu_action_names() -> PackedStringArray:
	return PackedStringArray(ACTIONS)


static func toggled_menu(open: bool) -> bool:
	return not open


func is_menu_open() -> bool:
	return _menu_open


func set_menu_open(open: bool) -> void:
	_menu_open = open
	_reset()

func _process(_delta: float) -> void:
	if ship == null:
		return
	var blocked: bool = main != null and main.hud != null and main.hud.is_systems_open()
	var docked: bool = main != null and main.docked
	for b in _buttons:
		b.node.visible = not docked and ((_menu_open and b.menu and (b.node.text != "DEV" or ship.dev_speed)) or (not _menu_open and not blocked and not b.menu))
	if _menu_open or blocked:
		_reset()
		return
	_highlight(_cruise, ship.auto_cruise)

func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		_touch(event.index, _canvas_position(event.position), event.pressed)
	elif event is InputEventScreenDrag:
		_drag(event.index, _canvas_position(event.position), _canvas_relative(event.position, event.relative))
	elif _use_mouse and event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		var _m = null
		for b in _buttons:
			if b.node.text == "MENU": _m = b.node.get_global_rect()
		print("TOUCHDBG raw=", event.position, " conv=", _canvas_position(event.position), " vis=", get_viewport().get_visible_rect(), " ft=", get_viewport().get_final_transform(), " menu=", _m, " layer=", get_parent().get_class(), " win=", get_window().size)
		_touch(MOUSE_FINGER, _canvas_position(event.position), event.pressed)
	elif _use_mouse and event is InputEventMouseMotion and event.button_mask & MOUSE_BUTTON_MASK_LEFT:
		_drag(MOUSE_FINGER, _canvas_position(event.position), _canvas_relative(event.position, event.relative))
	if ship != null:
		ship.touch_held = not _finger.is_empty()


func _canvas_position(position: Vector2) -> Vector2:
	return event_to_canvas(position, get_viewport().get_final_transform())


func _canvas_relative(position: Vector2, relative: Vector2) -> Vector2:
	return _canvas_position(position + relative) - _canvas_position(position)


static func event_to_canvas(position: Vector2, final_transform: Transform2D) -> Vector2:
	return final_transform.affine_inverse() * position

func _touch(index: int, pos: Vector2, pressed: bool) -> void:
	if pressed:
		var hit = _button_at(pos)
		if hit != null:
			_finger[index] = hit
			_press(hit)
			return
		if _menu_open:
			_menu_open = false
			_reset()
			_finger[index] = "dead"
			return
		if main != null and main.hud != null and main.hud.blocks_flight_touch(pos):
			_finger[index] = "dead"
			return
		if pos.x <= get_viewport().get_visible_rect().size.x * JOY_ZONE_FRACTION and _joy_finger == -1:
			_finger[index] = "joy"
			_joy_finger = index
			_joy_origin = pos
			_joy_now = pos
			_joy.visible = true
			_joy.queue_redraw()
		else:
			_finger[index] = "look"
			_look_idx.append(index)
			_finger_pos[index] = pos
			_pinch_base()
	else:
		var was = _finger.get(index)
		if was is Dictionary:
			_release(was)
		elif was == "joy":
			_joy_finger = -1
			_joy.visible = false
			ship.touch_thrust = 0.0
			ship.touch_yaw = 0.0
			ship.touch_brake = false
		elif was == "look":
			_look_idx.erase(index)
			_finger_pos.erase(index)
			_pinch_base()
		_finger.erase(index)

func _button_at(pos: Vector2):
	for b in _buttons:
		if b.node.visible and b.node.get_global_rect().has_point(pos):
			return b
	return null

func _press(b: Dictionary) -> void:
	match b.kind:
		MENU:
			_menu_open = not _menu_open
			_reset()
		CRUISE:
			ship.auto_cruise = not ship.auto_cruise
		FIRE:
			ship.touch_fire = true
			_highlight(b, true)
		HOLD_KEY:
			_send(b.code, true)
			_highlight(b, true)
		TAP_KEY:
			_send(b.code, true)
			_send(b.code, false)
			_flash(b)
		PITCH:
			_pitch[b.code] = true
			_pitch_apply()
			_highlight(b, true)
		ZOOM:
			ship._cam_zoom = zoom_step(ship._cam_zoom, b.code, 0.12, ship.ZOOM_MIN, ship.ZOOM_MAX)
		TELEPORT:
			_menu_open = false
			main.hud.teleport_sites_button.pressed.emit()
		SYSTEMS:
			_menu_open = false
			main.hud.toggle_systems()
		DEV:
			ship._debug_toggle_dev_speed()

func _release(b: Dictionary) -> void:
	if b.kind == FIRE:
		ship.touch_fire = false
		_highlight(b, false)
	elif b.kind == HOLD_KEY:
		_send(b.code, false)
		_highlight(b, false)
	elif b.kind == PITCH:
		_pitch.erase(b.code)
		_pitch_apply()
		_highlight(b, false)


func _pitch_apply() -> void:
	var sum := 0.0
	for key in _pitch:
		sum += key
	ship.touch_pitch = clampf(sum, -1.0, 1.0)

func _reset() -> void:
	for value in _finger.values():
		if value is Dictionary:
			_release(value)
	_finger.clear()
	_look_idx.clear()
	_finger_pos.clear()
	_pitch.clear()
	_joy_finger = -1
	_joy.visible = false
	if ship != null:
		ship.touch_thrust = 0.0
		ship.touch_yaw = 0.0
		ship.touch_brake = false
		ship.touch_pitch = 0.0
		ship.touch_fire = false
		ship.touch_held = false

func _drag(index: int, pos: Vector2, rel: Vector2) -> void:
	var kind = _finger.get(index)
	if kind == "joy":
		_joy_now = pos
		_joy.queue_redraw()
		var v := (_joy_now - _joy_origin) / RING_R
		if v.length() > 1.0:
			v = v.normalized()
		var cmd := stick_to_cmd(v)
		ship.touch_thrust = cmd.thrust
		ship.touch_yaw = cmd.yaw
		ship.touch_brake = cmd.brake
	elif kind == "look":
		_finger_pos[index] = pos
		if _look_idx.size() == 2:
			ship._cam_zoom = pinch_zoom(_pinch_start_zoom, _pinch_start_dist, _finger_pos[_look_idx[0]].distance_to(_finger_pos[_look_idx[1]]), ship.ZOOM_MIN, ship.ZOOM_MAX)
		elif _look_idx.size() == 1:
			ship.add_touch_look(rel * LOOK_SENS)


func _pinch_base() -> void:
	if _look_idx.size() == 2:
		_pinch_start_zoom = ship._cam_zoom
		_pinch_start_dist = _finger_pos[_look_idx[0]].distance_to(_finger_pos[_look_idx[1]])

static func stick_to_cmd(v: Vector2) -> Dictionary:
	var mag := v.length()
	if mag < 0.15:
		return {"thrust": 0.0, "yaw": 0.0, "brake": false}
	if mag > 1.0:
		v /= mag
		mag = 1.0
	var angle := rad_to_deg(acos(clampf(v.dot(Vector2.UP) / mag, -1.0, 1.0)))
	if angle >= 149.999:
		return {"thrust": 0.0, "yaw": 0.0, "brake": true}
	if angle <= 15.0:
		return {"thrust": mag, "yaw": 0.0, "brake": false}
	return {"thrust": mag * maxf(0.0, cos(deg_to_rad(angle))), "yaw": signf(v.x) * smoothstep(0.0, 1.0, clampf((angle - 15.0) / 75.0, 0.0, 1.0)), "brake": false}


static func pinch_zoom(start_zoom: float, start_dist: float, cur_dist: float, zmin: float, zmax: float) -> float:
	return clampf(start_zoom if cur_dist < 0.001 or start_dist < 0.001 else start_zoom * start_dist / cur_dist, zmin, zmax)


static func zoom_step(cur: float, dir: int, amount: float, zmin: float, zmax: float) -> float:
	return clampf(cur * exp(dir * amount), zmin, zmax)


func _highlight(b: Dictionary, on: bool) -> void:
	if b.get("lit", null) == on:
		return
	b.lit = on
	b.node.add_theme_stylebox_override("normal", _box(b.tint, 0.9 if on else 0.45))


func _flash(b: Dictionary) -> void:
	_highlight(b, true)
	get_tree().create_timer(0.12).timeout.connect(func(): _highlight(b, false))


func _box(tint: Color, fill: float) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = Color(tint.r, tint.g, tint.b, fill)
	box.border_color = Color(tint.r, tint.g, tint.b, 0.85)
	box.set_border_width_all(2)
	box.set_corner_radius_all(999)
	return box


func _draw_joy() -> void:
	var delta := _joy_now - _joy_origin
	if delta.length() > RING_R:
		delta = delta.normalized() * RING_R
	_joy.draw_circle(_joy_origin, RING_R, Color(0.8, 0.9, 1.0, 0.12))
	_joy.draw_arc(_joy_origin, RING_R, 0.0, TAU, 48, Color(0.8, 0.9, 1.0, 0.55), 2.0)
	_joy.draw_circle(_joy_origin + delta, 22.0, Color(0.8, 0.9, 1.0, 0.45))


func _send(code: int, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)
