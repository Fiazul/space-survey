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
#   • any finger NOT on a button -> drag to steer (ship.add_touch_look), with a
#     translucent joystick ring drawn at the finger's touch-down point so there's a
#     visible steer indicator (previously nothing was drawn there at all).
# Mouse-emulation stays ON globally so the menus/map/hangar still work by touch — only
# this flight overlay goes native. Buttons here are visual-only (mouse_filter = IGNORE).
#
# Layout: bug (Android) "hud buttons controller/joystick circle missing, everything
# messed up" traced to two defects in the ORIGINAL fixed-pixel-in-a-1280x720-canvas
# layout: (1) button rects overlapped hud.gd's own bottom-left (combat/KILLS + NAV/MAP/
# CODEX bar, hud.gd DEFAULT_LAYOUT "combat"/"buttons"/"cancel_nav") and bottom-right
# (TELEPORT EARTH / details button, DEFAULT_LAYOUT "teleport"/"details") widgets even at
# the reference resolution; (2) the project's canvas_items+expand stretch mode makes the
# EFFECTIVE canvas size at other aspect ratios wider or taller than 1280x720 (verified:
# 2400x1080 -> logical (1600, 720); a fixed x=1118 then sits well short of the true right
# edge). Fixed by computing every button's rect from the CURRENT viewport size each frame
# the viewport resizes, anchored to the true screen edges (left cluster from the left
# edge, right cluster from the right edge, both clusters a fixed distance up from the
# true bottom edge chosen to clear hud.gd's bottom widgets — see LEFT_BOTTOM_MARGIN /
# RIGHT_BOTTOM_MARGIN below) instead of one static Rect2 per button.

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

var _buttons: Array = []      # [{node, kind, code, tint, side, x_margin, w, h, bottom_off}]
var _finger := {}             # touch index -> button dict, or the string "steer"

# Bottom clearance (true-bottom-edge to cluster-bottom, in canvas units — see comment
# above; canvas units track hud.gd's own fixed-pixel positions 1:1 regardless of
# resolution/stretch, so these constants stay correct at every aspect ratio):
# hud.gd bottom-left hazard (combat "KILLS" panel / NAV·MAP·CODEX bar / cancel-nav
# button, DEFAULT_LAYOUT "combat"=628.67 "buttons"=680 "cancel_nav"=602) starts ~602.
const LEFT_BOTTOM_MARGIN := 135.0
# hud.gd bottom-right hazard (details button / TELEPORT EARTH, DEFAULT_LAYOUT
# "details"=636 "teleport"=674) starts ~636.
const RIGHT_BOTTOM_MARGIN := 94.0

# Steer joystick visual: a ring at the finger's touch-down point + a dot that follows
# the finger, clamped to RING_R — the previously-missing "joystick circle".
const RING_R := 64.0
const RING_DOT_R := 22.0
var _steer_ring: Control
var _steer_finger := -1
var _steer_origin := Vector2.ZERO
var _steer_now := Vector2.ZERO


func _ready() -> void:
	layer = 90                                  # above the HUD
	process_mode = Node.PROCESS_MODE_ALWAYS     # so MAP (M) still toggles while the map pauses
	_build()
	get_viewport().size_changed.connect(_layout)


func _build() -> void:
	# Left cluster (from the left edge, a fixed distance above the true bottom edge).
	_add("THRUST", 30.0, 132, 112, Color(0.4, 0.9, 0.6), K_TOGGLE_CRUISE, "L", 0.0)
	_add("BOOST",  30.0, 132, 104, Color(0.5, 0.8, 1.0), K_HOLD_KEY, "L", 130.0, KEY_SHIFT)
	# Right cluster (from the right edge, a fixed distance above the true bottom edge).
	_add("FIRE",     30.0,  132, 112, Color(1.0, 0.5, 0.35), K_HOLD_FIRE, "R", 0.0)
	_add("CAP",      178.0, 124, 112, Color(0.6, 1.0, 0.7), K_HOLD_KEY, "R", 0.0, KEY_V)
	_add("INTERACT", 30.0,  132, 104, Color(0.55, 0.85, 1.0), K_TAP_KEY, "R", 130.0, KEY_F)
	_add("MAP",      178.0, 124, 104, Color(0.7, 0.8, 1.0), K_TAP_KEY, "R", 130.0, KEY_M)
	_add("HOME",     30.0,  132, 96, Color(1.0, 0.7, 0.5), K_TAP_KEY, "R", 248.0, KEY_H)

	_steer_ring = Control.new()
	_steer_ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_steer_ring.set_anchors_preset(Control.PRESET_FULL_RECT)
	_steer_ring.visible = false
	_steer_ring.draw.connect(_draw_steer_ring)
	add_child(_steer_ring)

	_layout()


# Recompute every button's rect from the CURRENT viewport size — called once at boot
# and again on every resize/orientation change (get_viewport().size_changed).
func _layout() -> void:
	var size := get_viewport().get_visible_rect().size
	for b in _buttons:
		var x: float = b.x_margin if b.side == "L" else size.x - b.x_margin - b.w
		var bottom_margin: float = LEFT_BOTTOM_MARGIN if b.side == "L" else RIGHT_BOTTOM_MARGIN
		var cluster_bottom: float = size.y - bottom_margin
		var y: float = cluster_bottom - b.bottom_off - b.h
		b.node.position = Vector2(x, y)


# --- raw multi-touch input -------------------------------------------------
func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		_touch_at(event.index, event.position, event.pressed)
	elif event is InputEventScreenDrag:
		_drag(event.index, event.position, event.relative)
	elif _use_mouse and event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_touch_at(MOUSE_FINGER, event.position, event.pressed)
	elif _use_mouse and event is InputEventMouseMotion and (event.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
		_drag(MOUSE_FINGER, event.position, event.relative)


# A finger went down / up at pos.
func _touch_at(index: int, pos: Vector2, pressed: bool) -> void:
	if pressed:
		var hit: Variant = _button_at(pos)
		if hit != null:
			_finger[index] = hit
			_press(hit)
		else:
			_finger[index] = "steer"
			_steer_finger = index
			_steer_origin = pos
			_steer_now = pos
			_steer_ring.visible = true
			_steer_ring.queue_redraw()
	else:
		var was = _finger.get(index)
		if was != null and was != "steer":
			_release(was)
		_finger.erase(index)
		if index == _steer_finger:
			_steer_finger = -1
			_steer_ring.visible = false


# A finger moved; only steer-fingers turn the ship.
func _drag(index: int, pos: Vector2, rel: Vector2) -> void:
	if _finger.get(index) == "steer":
		if ship != null:
			ship.add_touch_look(rel * LOOK_SENS)
		if index == _steer_finger:
			_steer_now = pos
			_steer_ring.queue_redraw()


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
# x_margin/w/h/bottom_off are canvas units measured from the edge named by `side`
# ("L" = left edge, "R" = right edge) and from the true bottom edge (`_layout` turns
# these into an actual Rect2 against the current viewport size).
func _add(text: String, x_margin: float, w: float, h: float, tint: Color, kind: int,
		side: String, bottom_off: float, code: int = 0) -> void:
	var b := Button.new()
	b.text = text
	b.size = Vector2(w, h)
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE   # visual only — we read raw touches ourselves
	b.add_theme_font_size_override("font_size", 19)
	b.add_theme_color_override("font_color", Color(0.95, 0.98, 1.0))
	b.add_theme_stylebox_override("normal", _box(tint, 0.16))
	b.add_theme_stylebox_override("hover", _box(tint, 0.16))
	b.add_theme_stylebox_override("pressed", _box(tint, 0.16))
	b.add_theme_stylebox_override("disabled", _box(tint, 0.16))
	add_child(b)
	_buttons.append({"node": b, "kind": kind, "code": code, "tint": tint,
		"side": side, "x_margin": x_margin, "w": w, "h": h, "bottom_off": bottom_off})


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


func _draw_steer_ring() -> void:
	if not _steer_ring.visible:
		return
	var d: Vector2 = _steer_now - _steer_origin
	if d.length() > RING_R:
		d = d.normalized() * RING_R
	_steer_ring.draw_circle(_steer_origin, RING_R, Color(0.8, 0.9, 1.0, 0.12))
	_steer_ring.draw_arc(_steer_origin, RING_R, 0.0, TAU, 48, Color(0.8, 0.9, 1.0, 0.55), 2.0)
	_steer_ring.draw_circle(_steer_origin + d, RING_DOT_R, Color(0.8, 0.9, 1.0, 0.45))


# Synthesise a key the game already polls (both keycode and physical_keycode, for
# is_physical_key_pressed). Keys are NOT touch-emulated, so this is safe and multi-touch.
func _send(code: int, pressed: bool) -> void:
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.physical_keycode = code
	ev.pressed = pressed
	Input.parse_input_event(ev)
