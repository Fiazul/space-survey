class_name TouchControls
extends CanvasLayer
# On-screen controls for touch / mobile — MULTI-TOUCH NATIVE, landscape, two-thumb.
#
# Why not plain Buttons: Godot's emulate_mouse_from_touch is SINGLE-pointer, so the GUI
# can only track one finger — you can't hold THRUST + steer + FIRE at once (the whole
# point of a flight game). So this overlay reads the RAW per-finger touch stream itself
# (InputEventScreenTouch/Drag, keyed by event.index) and drives the game directly.
#
# Layout (PUBG/COD style, landscape, `window/handheld/orientation` forced landscape):
#   LEFT thumb  — nothing but a fixed movement-joystick zone (left ~45% of the screen,
#                 above hud.gd's bottom-left hazard). Forward + turn only — the ship has
#                 no reverse thrust outside a brake, so there is no "backward" stick
#                 direction; pushing the stick into the back cone brakes instead.
#                 `stick_to_cmd()` is a pure static function (unit-tested in
#                 tools/test_touch_controls.gd) mapping the stick vector to
#                 {thrust, yaw, brake}, fed into Ship as analog `touch_thrust`/`touch_yaw`/
#                 `touch_brake` fields (never synthesised W/A/D keys — those are digital,
#                 the stick is analog).
#   RIGHT thumb — FIRE (ship.touch_fire) and stacked UP/DOWN nose-pitch hold buttons
#                 (ship.touch_pitch) where a shooter puts its fire buttons, plus the
#                 smaller BOOST/CAP/THRUST/INTERACT/MAP/HOME buttons along the right
#                 edge. A drag anywhere in the right zone that isn't on a button is the
#                 aim-look drag (ship.add_touch_look), same as before.
#   TOP-RIGHT   — a small DEV tap button (ship._debug_toggle_dev_speed); while dev mode
#                 is on it reveals NODEATH/FASTAIR tap buttons next to it.
# BOOST/CAP still hold a synthesised key (Shift/V) — keys aren't touch-emulated.
# INTERACT/MAP/HOME still tap a one-shot key (F/M/H). THRUST still toggles
# ship.auto_cruise. Mouse-emulation stays ON globally so menus/map/hangar work by touch —
# only this flight overlay goes native. Buttons here are visual-only (mouse_filter =
# IGNORE); button rects are computed from the CURRENT viewport size every resize
# (anchored to true screen edges, clearing hud.gd's own bottom-left/bottom-right widgets
# via LEFT_BOTTOM_MARGIN/RIGHT_BOTTOM_MARGIN, and its top-right radar via TOP_MARGIN) —
# a fixed-pixel layout broke at other aspect ratios/stretch modes (see git history).

var ship: Node
var main: Node

const LOOK_SENS := 0.6        # touch-drag → look multiplier (tune on device)

# On desktop we test with `--touch` using the mouse as a single finger. On a real phone
# (OS "mobile") we IGNORE mouse events — emulate_mouse_from_touch would otherwise echo
# every finger as a mouse event and double-count. Touch events drive the device.
var _use_mouse := not OS.has_feature("mobile")
const MOUSE_FINGER := -7      # synthetic finger index for the desktop test mouse

# kinds
enum { K_TOGGLE_CRUISE, K_HOLD_KEY, K_HOLD_FIRE, K_TAP_KEY, K_HOLD_PITCH, K_TAP_DEV, K_TAP_DEBUG_SUB }

var _buttons: Array = []      # [{node, kind, code, tint, side, x_margin, w, h, bottom_off}]
var _finger := {}             # touch index -> button dict, or the string "joystick"/"look"
var _dev_btn: Dictionary
var _nodeath_btn: Dictionary
var _fastair_btn: Dictionary
var _cruise_btn: Dictionary

# Bottom clearance (true-bottom-edge to cluster-bottom, in canvas units — canvas units
# track hud.gd's own fixed-pixel positions 1:1 regardless of resolution/stretch, so these
# constants stay correct at canvas height 720 (16:9 and wider)):
# hud.gd bottom-left hazard (combat "KILLS" panel / NAV·MAP·CODEX bar / cancel-nav
# button, DEFAULT_LAYOUT "combat"=628.67 "buttons"=680 "cancel_nav"=602) starts ~602.
const LEFT_BOTTOM_MARGIN := 135.0
# hud.gd bottom-right hazard (details button / TELEPORT EARTH, DEFAULT_LAYOUT
# "details"=636 "teleport"=674) starts ~636.
const RIGHT_BOTTOM_MARGIN := 94.0
# hud.gd's own widgets sit at FIXED canvas-unit positions from the reference 720-tall
# canvas — they do NOT move down when the effective canvas is taller (16:10/4:3
# tablets, see class comment re: canvas_items+expand). Our clusters anchor to the TRUE
# bottom edge, though, so at a taller canvas they'd drift down past the hazard line
# instead of stopping at it. Clamp so the cluster bottom never passes REFERENCE_HEIGHT
# minus its margin (e.g. right: 720-94=626, left: 720-135=585) regardless of size.y.
const REFERENCE_HEIGHT := 720.0
# hud.gd top-right hazard (corner radar, DEFAULT_LAYOUT "radar"=(1129.33, 11.33), panel
# MiniMap.PANEL=196x196 at scale 0.76 -> bottom edge 11.33 + 196*0.76 ≈ 160) — the DEV
# cluster sits below it.
const TOP_MARGIN := 165.0

const JOY_ZONE_FRACTION := 0.45   # left screen fraction reserved for the movement joystick

# Movement joystick visual: a ring at the finger's touch-down point + a dot that follows
# the finger, clamped to RING_R.
const RING_R := 64.0
const RING_DOT_R := 22.0
var _joy_ring: Control
var _joy_finger := -1
var _joy_origin := Vector2.ZERO
var _joy_now := Vector2.ZERO
var _prev_brake := false

var _pitch_held := {}   # b.code (-1/1) -> true, while its UP/DOWN button is held

# Assumption (orchestrator brief): UP/DOWN drive nose PITCH, not a Space/Ctrl lift
# strafe. Flip to false + swap the two touch_pitch signs below to switch to lift.
const UPDOWN_IS_PITCH := true


func _ready() -> void:
	layer = 90                                  # above the HUD
	process_mode = Node.PROCESS_MODE_ALWAYS     # so MAP (M) still toggles while the map pauses
	_build()
	get_viewport().size_changed.connect(_layout)


func _build() -> void:
	# Right cluster, PUBG/COD layout — FIRE + UP/DOWN big and thumb-reachable, everything
	# else small along the right edge. Left side carries nothing but the joystick zone.
	_add("FIRE", 20.0, 140, 140, Color(1.0, 0.5, 0.35), K_HOLD_FIRE, "R", 20.0)
	_add("UP",   170.0, 110, 90, Color(0.55, 0.85, 1.0), K_HOLD_PITCH, "R", 110.0, -1)
	_add("DOWN", 170.0, 110, 90, Color(0.55, 0.85, 1.0), K_HOLD_PITCH, "R", 10.0, 1)
	# x_margin=340 keeps this column's right edge (940) clear of the TR dev cluster's
	# leftmost button (FASTAIR, left edge 956) even at HOME's top (the tallest stack
	# offset) — see CLAUDE.md-style layout note above; checked at reference 1280x720.
	_cruise_btn = _add("THRUST", 340.0, 110, 64, Color(0.4, 0.9, 0.6), K_TOGGLE_CRUISE, "R", 10.0)
	_add("BOOST",    340.0, 110, 64, Color(0.5, 0.8, 1.0), K_HOLD_KEY, "R", 84.0, KEY_SHIFT)
	_add("CAP",      340.0, 110, 64, Color(0.6, 1.0, 0.7), K_HOLD_KEY, "R", 158.0, KEY_V)
	_add("INTERACT", 340.0, 110, 64, Color(0.55, 0.85, 1.0), K_TAP_KEY, "R", 232.0, KEY_F)
	_add("MAP",      340.0, 110, 64, Color(0.7, 0.8, 1.0), K_TAP_KEY, "R", 306.0, KEY_M)
	_add("HOME",     340.0, 110, 64, Color(1.0, 0.7, 0.5), K_TAP_KEY, "R", 380.0, KEY_H)

	_dev_btn = _add("DEV", 14.0, 90, 40, Color(1.0, 0.85, 0.3), K_TAP_DEV, "TR", 0.0)
	_nodeath_btn = _add("NODEATH", 114.0, 100, 40, Color(1.0, 0.4, 0.4), K_TAP_DEBUG_SUB, "TR", 0.0, 0)
	_fastair_btn = _add("FASTAIR", 224.0, 100, 40, Color(0.4, 1.0, 0.9), K_TAP_DEBUG_SUB, "TR", 0.0, 1)

	_joy_ring = Control.new()
	_joy_ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_joy_ring.set_anchors_preset(Control.PRESET_FULL_RECT)
	_joy_ring.visible = false
	_joy_ring.draw.connect(_draw_joy_ring)
	add_child(_joy_ring)

	_layout()


# Recompute every button's rect from the CURRENT viewport size — called once at boot
# and again on every resize/orientation change (get_viewport().size_changed).
func _layout() -> void:
	var size := get_viewport().get_visible_rect().size
	for b in _buttons:
		if b.side == "TR":
			b.node.position = Vector2(size.x - b.x_margin - b.w, TOP_MARGIN + b.bottom_off)
		else:
			var x: float = b.x_margin if b.side == "L" else size.x - b.x_margin - b.w
			var base_margin: float = LEFT_BOTTOM_MARGIN if b.side == "L" else RIGHT_BOTTOM_MARGIN
			var cluster_bottom: float = size.y - _clamped_bottom_margin(size.y, base_margin)
			b.node.position = Vector2(x, cluster_bottom - b.bottom_off - b.h)


# hud.gd's hazard line sits at a fixed REFERENCE_HEIGHT - base_margin from the top; past
# REFERENCE_HEIGHT tall, growing size.y would otherwise push the true-bottom-anchored
# margin (and so the cluster) down past that fixed line instead of stopping at it.
func _clamped_bottom_margin(size_y: float, base_margin: float) -> float:
	return maxf(base_margin, size_y - (REFERENCE_HEIGHT - base_margin))


func _process(_delta: float) -> void:
	if ship == null:
		return
	# auto_cruise can also be dropped by the touch-brake rising edge, main.gd's Num Lock
	# toggle, or its S-tap handler — none of which go through _press, so the THRUST
	# button's highlight has to be polled here rather than set only on press.
	_highlight(_cruise_btn, ship.auto_cruise)
	_highlight(_dev_btn, ship.dev_speed)
	_nodeath_btn.node.visible = ship.dev_speed
	_fastair_btn.node.visible = ship.dev_speed
	if ship.dev_speed:
		_highlight(_nodeath_btn, ship._FM.dev_no_death)
		_highlight(_fastair_btn, ship._FM.dev_fast_air)


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
			return
		match _zone_at(pos):
			"joystick":
				if _joy_finger != -1:
					_finger[index] = "dead"   # a joystick finger is already down — only one at a time
				else:
					_finger[index] = "joystick"
					_joy_finger = index
					_joy_origin = pos
					_joy_now = pos
					_joy_ring.visible = true
					_joy_ring.queue_redraw()
			"look":
				_finger[index] = "look"
			_:
				pass   # bottom-margin hazard strip — leave it to hud.gd's own mouse-emulated widgets
	else:
		var was: Variant = _finger.get(index)
		if was is Dictionary:
			_release(was)
		elif was == "joystick":
			_joy_finger = -1
			_joy_ring.visible = false
			if ship != null:
				ship.touch_thrust = 0.0
				ship.touch_yaw = 0.0
				ship.touch_brake = false
			_prev_brake = false
		_finger.erase(index)


# A finger moved; joystick fingers drive the stick, look fingers orbit the camera.
func _drag(index: int, pos: Vector2, rel: Vector2) -> void:
	var kind: Variant = _finger.get(index)
	if kind == "joystick":
		_joy_now = pos
		_joy_ring.queue_redraw()
		if ship != null:
			var v: Vector2 = (_joy_now - _joy_origin) / RING_R
			if v.length() > 1.0:
				v = v.normalized()
			var cmd := stick_to_cmd(v)
			ship.touch_thrust = cmd.thrust
			ship.touch_yaw = cmd.yaw
			ship.touch_brake = cmd.brake
			if cmd.brake and not _prev_brake and ship.auto_cruise:
				ship.auto_cruise = false
				if main != null and main.hud != null:
					main.hud.toast = "AUTO-CRUISE  OFF"
					main.hud.toast_t = 2.0
			_prev_brake = cmd.brake
	elif kind == "look":
		if ship != null:
			ship.add_touch_look(rel * LOOK_SENS)


const BRAKE_EPS := 0.001   # acos/float rounding can land a true 150° a hair under — brake anyway

# Pure — no ship/autoload access — so tools/test_touch_controls.gd can unit-test the
# mapping headless. Screen y is down: forward = v.y < 0. Dead zone < 0.15. Angle from
# straight-ahead: <=15° pure forward, 15°-150° blends a forward component (0 at 90°+)
# with a yaw ramp (0 at 15° -> 1.0 at 90°, held at 90°-150°), >=150° (behind the ship) is
# a hard brake instead of a reverse thrust — the ship has none.
static func stick_to_cmd(v: Vector2) -> Dictionary:
	var mag := v.length()
	if mag < 0.15:
		return {"thrust": 0.0, "yaw": 0.0, "brake": false}
	if mag > 1.0:
		v /= mag
		mag = 1.0
	var fwd_dot := clampf(v.dot(Vector2(0.0, -1.0)) / mag, -1.0, 1.0)
	var theta_deg := rad_to_deg(acos(fwd_dot))
	var side := signf(v.x)
	if theta_deg <= 15.0:
		return {"thrust": mag, "yaw": 0.0, "brake": false}
	if theta_deg >= 150.0 - BRAKE_EPS:
		return {"thrust": 0.0, "yaw": 0.0, "brake": true}
	var thrust := mag * maxf(0.0, cos(deg_to_rad(theta_deg)))
	var ramp := smoothstep(0.0, 1.0, clampf((theta_deg - 15.0) / 75.0, 0.0, 1.0))
	return {"thrust": thrust, "yaw": side * ramp, "brake": false}


func _zone_at(pos: Vector2) -> String:
	var size := get_viewport().get_visible_rect().size
	if pos.x <= size.x * JOY_ZONE_FRACTION:
		var cut: float = size.y - _clamped_bottom_margin(size.y, LEFT_BOTTOM_MARGIN)
		return "joystick" if pos.y <= cut else "dead"
	var cut: float = size.y - _clamped_bottom_margin(size.y, RIGHT_BOTTOM_MARGIN)
	return "look" if pos.y <= cut else "dead"


func _button_at(pos: Vector2):
	for b in _buttons:
		if b.node.visible and b.node.get_global_rect().has_point(pos):
			return b
	return null


func _press(b: Dictionary) -> void:
	match b.kind:
		K_TOGGLE_CRUISE:
			if ship != null:
				ship.auto_cruise = not ship.auto_cruise
				# _process polls ship.auto_cruise every frame — no highlight call needed here.
		K_HOLD_KEY:
			_send(b.code, true); _highlight(b, true)
		K_HOLD_FIRE:
			if ship != null: ship.touch_fire = true
			_highlight(b, true)
		K_TAP_KEY:
			_send(b.code, true); _send(b.code, false); _flash(b)
		K_HOLD_PITCH:
			_pitch_held[b.code] = true
			_recompute_pitch()
			_highlight(b, true)
		K_TAP_DEV:
			# No _flash — _process polls ship.dev_speed every frame; a flash would fight it.
			if ship != null: ship._debug_toggle_dev_speed()
		K_TAP_DEBUG_SUB:
			if ship != null:
				if b.code == 0: ship._debug_toggle_dev_no_death()
				else: ship._debug_toggle_dev_fast_air()


func _release(b: Dictionary) -> void:
	match b.kind:
		K_HOLD_KEY:
			_send(b.code, false); _highlight(b, false)
		K_HOLD_FIRE:
			if ship != null: ship.touch_fire = false
			_highlight(b, false)
		K_HOLD_PITCH:
			_pitch_held.erase(b.code)
			_recompute_pitch()
			_highlight(b, false)
		# toggle/tap/dev buttons keep or already flashed their state.


func _recompute_pitch() -> void:
	if ship == null:
		return
	var total := 0.0
	for code in _pitch_held:
		total += code
	ship.touch_pitch = clampf(total, -1.0, 1.0)


# --- visuals ---------------------------------------------------------------
# x_margin/w/h/bottom_off are canvas units measured from the edge named by `side`
# ("L" = left edge + true bottom, "R" = right edge + true bottom, "TR" = right edge +
# TOP_MARGIN, `bottom_off` reused as a top offset there) — `_layout` turns these into an
# actual Rect2 against the current viewport size.
func _add(text: String, x_margin: float, w: float, h: float, tint: Color, kind: int,
		side: String, bottom_off: float, code: int = 0) -> Dictionary:
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
	var d := {"node": b, "kind": kind, "code": code, "tint": tint,
		"side": side, "x_margin": x_margin, "w": w, "h": h, "bottom_off": bottom_off}
	_buttons.append(d)
	return d


func _highlight(b: Dictionary, on: bool) -> void:
	if b.get("hl_on", null) == on:
		return   # already in this state — don't rebuild the StyleBoxFlat every frame
	b.hl_on = on
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


func _draw_joy_ring() -> void:
	var d: Vector2 = _joy_now - _joy_origin
	if d.length() > RING_R:
		d = d.normalized() * RING_R
	_joy_ring.draw_circle(_joy_origin, RING_R, Color(0.8, 0.9, 1.0, 0.12))
	_joy_ring.draw_arc(_joy_origin, RING_R, 0.0, TAU, 48, Color(0.8, 0.9, 1.0, 0.55), 2.0)
	_joy_ring.draw_circle(_joy_origin + d, RING_DOT_R, Color(0.8, 0.9, 1.0, 0.45))


# Synthesise a key the game already polls (both keycode and physical_keycode, for
# is_physical_key_pressed). Keys are NOT touch-emulated, so this is safe and multi-touch.
func _send(code: int, pressed: bool) -> void:
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.physical_keycode = code
	ev.pressed = pressed
	Input.parse_input_event(ev)
