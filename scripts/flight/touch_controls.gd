class_name TouchControls
extends CanvasLayer
# On-screen controls for touch / mobile — MULTI-TOUCH NATIVE.
#
# Why not plain Buttons: Godot's emulate_mouse_from_touch is SINGLE-pointer, so the GUI
# can only track one finger — you can't hold THRUST + steer + FIRE at once (the whole
# point of a flight game). And it turned every touch into a left-click, so the screen
# fired everywhere. So this overlay reads the RAW per-finger touch stream itself
# (InputEventScreenTouch/Drag, keyed by event.index) and drives the game directly:
#   • FIRE  -> ship.touch_fire flag (main reads it on touch builds; NOT the mouse)
#   • BOOST/CAP -> hold a synthesised key (Shift / V) — keys aren't touch-emulated
#   • INTERACT/MAP/HOME -> a one-shot key tap (F / M / H)
#   • THRUST -> toggles ship.auto_cruise
#   • any finger NOT on a button -> drag to steer (ship.add_touch_look)
# Mouse-emulation stays ON globally so the menus/map/hangar still work by touch — only
# this flight overlay goes native. Buttons here are visual-only (mouse_filter = IGNORE).
#
# Layout reference 1280×720 (scaled by the project's canvas_items + expand stretch):
#   left  — THRUST (toggle), BOOST (hold)
#   right — FIRE (hold), CAP (hold), INTERACT/F, MAP/M, HOME/H

var ship: Node
var main: Node

const LOOK_SENS := 0.6        # touch-drag → look multiplier (tune on device)

# On desktop we test with `--touch` using the mouse as a single finger. On a real phone
# (OS "mobile") we IGNORE mouse events — emulate_mouse_from_touch would otherwise echo
# every finger as a mouse event and double-count. Touch events drive the device.
var _use_mouse := not OS.has_feature("mobile")
const MOUSE_FINGER := -7      # synthetic finger index for the desktop test mouse

# kinds
enum { K_TOGGLE_CRUISE, K_HOLD_KEY, K_HOLD_FIRE, K_TAP_KEY }

var _buttons: Array = []      # [{node, rect, kind, code, tint}]
var _finger := {}             # touch index -> button dict, or the string "steer"


func _ready() -> void:
	layer = 90                                  # above the HUD
	process_mode = Node.PROCESS_MODE_ALWAYS     # so MAP (M) still toggles while the map pauses
	_build()


func _build() -> void:
	# Left cluster.
	_add("THRUST", Rect2(30, 558, 132, 112), Color(0.4, 0.9, 0.6), K_TOGGLE_CRUISE)
	_add("BOOST",  Rect2(30, 436, 132, 104), Color(0.5, 0.8, 1.0), K_HOLD_KEY, KEY_SHIFT)
	# Right cluster.
	_add("FIRE",     Rect2(1118, 558, 132, 112), Color(1.0, 0.5, 0.35), K_HOLD_FIRE)
	_add("CAP",      Rect2(978, 558, 124, 112), Color(0.6, 1.0, 0.7), K_HOLD_KEY, KEY_V)
	_add("INTERACT", Rect2(1118, 436, 132, 104), Color(0.55, 0.85, 1.0), K_TAP_KEY, KEY_F)
	_add("MAP",      Rect2(978, 436, 124, 104), Color(0.7, 0.8, 1.0), K_TAP_KEY, KEY_M)
	_add("HOME",     Rect2(1118, 326, 132, 96), Color(1.0, 0.7, 0.5), K_TAP_KEY, KEY_H)


# --- raw multi-touch input -------------------------------------------------
func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		_touch_at(event.index, event.position, event.pressed)
	elif event is InputEventScreenDrag:
		_drag(event.index, event.relative)
	elif _use_mouse and event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_touch_at(MOUSE_FINGER, event.position, event.pressed)
	elif _use_mouse and event is InputEventMouseMotion and (event.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
		_drag(MOUSE_FINGER, event.relative)


# A finger went down / up at pos.
func _touch_at(index: int, pos: Vector2, pressed: bool) -> void:
	if pressed:
		var hit: Variant = _button_at(pos)
		if hit != null:
			_finger[index] = hit
			_press(hit)
		else:
			_finger[index] = "steer"
	else:
		var was = _finger.get(index)
		if was != null and was != "steer":
			_release(was)
		_finger.erase(index)


# A finger moved; only steer-fingers turn the ship.
func _drag(index: int, rel: Vector2) -> void:
	if _finger.get(index) == "steer" and ship != null:
		ship.add_touch_look(rel * LOOK_SENS)


func _button_at(pos: Vector2):
	for b in _buttons:
		if b.node.get_global_rect().has_point(pos):
			return b
	return null


func _press(b: Dictionary) -> void:
	match b.kind:
		K_TOGGLE_CRUISE:
			if ship != null:
				ship.auto_cruise = not ship.auto_cruise
				_highlight(b, ship.auto_cruise)
		K_HOLD_KEY:
			_send(b.code, true); _highlight(b, true)
		K_HOLD_FIRE:
			if ship != null: ship.touch_fire = true
			_highlight(b, true)
		K_TAP_KEY:
			_send(b.code, true); _send(b.code, false); _flash(b)


func _release(b: Dictionary) -> void:
	match b.kind:
		K_HOLD_KEY:
			_send(b.code, false); _highlight(b, false)
		K_HOLD_FIRE:
			if ship != null: ship.touch_fire = false
			_highlight(b, false)
		# toggle keeps its state; tap already fired on press.


# --- visuals ---------------------------------------------------------------
func _add(text: String, rect: Rect2, tint: Color, kind: int, code: int = 0) -> void:
	var b := Button.new()
	b.text = text
	b.position = rect.position
	b.size = rect.size
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE   # visual only — we read raw touches ourselves
	b.add_theme_font_size_override("font_size", 19)
	b.add_theme_color_override("font_color", Color(0.95, 0.98, 1.0))
	b.add_theme_stylebox_override("normal", _box(tint, 0.16))
	b.add_theme_stylebox_override("hover", _box(tint, 0.16))
	b.add_theme_stylebox_override("pressed", _box(tint, 0.16))
	b.add_theme_stylebox_override("disabled", _box(tint, 0.16))
	add_child(b)
	_buttons.append({"node": b, "rect": rect, "kind": kind, "code": code, "tint": tint})


func _highlight(b: Dictionary, on: bool) -> void:
	var fill := 0.5 if on else 0.16
	b.node.add_theme_stylebox_override("normal", _box(b.tint, fill))


func _flash(b: Dictionary) -> void:
	_highlight(b, true)
	get_tree().create_timer(0.12).timeout.connect(func(): _highlight(b, false))


func _box(tint: Color, fill: float) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(tint.r, tint.g, tint.b, fill)
	sb.border_color = Color(tint.r, tint.g, tint.b, 0.85)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(14)
	return sb


# Synthesise a key the game already polls (both keycode and physical_keycode, for
# is_physical_key_pressed). Keys are NOT touch-emulated, so this is safe and multi-touch.
func _send(code: int, pressed: bool) -> void:
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.physical_keycode = code
	ev.pressed = pressed
	Input.parse_input_event(ev)
