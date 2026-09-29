class_name HUD
extends Node3D
# Flight instruments stay compact and frameless; secondary actions live in Systems.
#
# Layout is authored against the 1280x720 reference (project stretch = canvas_items),
# so it scales to fullscreen. refresh() is called by main.gd each frame.

# Scale conversions for the readouts. Must match Ephemeris.AU_TO_UNITS (1 unit = 1 km).
const AU_PER_UNIT := 1.0 / 149597870.7
const LY_PER_AU := 1.0 / 63241.077

# --- palette -----------------------------------------------------------------
const C_ACCENT := Color(0.56, 0.86, 0.76)     # cyan UI accent / edges
const C_TEXT := Color(0.91, 0.95, 0.93)       # primary readout text
const C_DIM := Color(0.67, 0.74, 0.72)       # secondary / labels
const C_GREEN := Color(0.56, 0.86, 0.76)      # discovery / scan
const C_WARN := Color(0.95, 0.49, 0.45)       # boss / danger

# Shared right margin (1280 reference width − 16px). The combat readout and the
# MAP/CODEX/?/⚙ bar below it both align their right edge here.
const RIGHT_EDGE := 1264.0

# Metallic gradient shader for glyph fills (see hud_text.gdshader). Each label gets
# its own ShaderMaterial so the gradient hue/height can match that label.
var _text_shader := load("res://shaders/hud_text.gdshader") as Shader

signal ship_selected(index: int)   # emitted when a hangar row is clicked
signal ship_color_selected(part: String, key: String)
signal ship_finish_selected(key: String)
signal ship_module_selected(kind: String, key: String)
signal open_teleport_sites() # visible TELEPORT shortcut, including Android
signal open_teleport_map()   # clicked the dock's "TELEPORT NETWORK" button -> open the map

var ship: Ship
var planets: PlanetSystem
var combat: Combat           # for HP / kills readout
@onready var codex := Codex   # autoload; discovery progress
var origin_name := "Earth"   # what the distance readout measures from (per system)
var physical_system_name := "SOL"   # physical systems name their star

var toast := ""              # transient "✓ discovered" message
var toast_t := 0.0

var _canvas: CanvasLayer
var _dist_label: Label
var _speed_label: Label
var _tape_label: Label
var _near_label: Label
var _prompt: Label    # "Press F to dock" near the station
var _menu: Label      # centered overlay text (teleport / death)
var _flash: ColorRect # full-screen colour flash (core damage / death kick); alpha eased down
var _death: ColorRect # skin-kill overlay — must be obvious, not a silent hitch
var _death_label: Label
var _flash_a := 0.0   # current flash strength 0..1 (decays each frame in refresh)
var _tip: Label       # first-run onboarding tip line (just under the crosshair)
var _debug_label: Label   # F3 perf readout (object/RAM/render counters)
var _quest_label: Label   # active-quest tracker (top-center)
var _lore: PanelContainer   # arrival lore card (shown once, on first reaching a system)
var _lore_label: Label
var lore_t := 0.0     # seconds the lore card stays up (main counts it down; refresh fades it)
# Hangar: the styled, bordered, gradient-backed ship-pickup table (top-right).
var _hangar: PanelContainer
var _hangar_bg: TextureRect
var _hangar_title: Label
var _hangar_rows: VBoxContainer
var _hangar_sig := ""   # rebuild the rows only when the contents actually change
var _hangar_color_key := ""
var _color_picker: ColorPickerButton
var _color_swatch_buttons: Array[Button] = []
var _combat_label: Label
var _hull_label: Label       # "HULL  170 / 220" sitting over the hull bar
var _hull_fill: ColorRect    # the coloured fill of the player hull bar (top-left)
var _hull_bar_w := 0.0       # inner (fillable) width of the hull bar
var _energy_fill: ColorRect  # weapon-energy bar fill (shooting)
var _energy_bar_w := 0.0
var _boost_fill: ColorRect   # boost-energy bar fill (Shift)
var _boost_bar_w := 0.0
var _reticle: Control   # dynamic crosshair (crosshair.gd)
var _lock_ring: Control # radial progress arc drawn around the crosshair while holding X
var _lock_frac := 0.0   # 0..1 hold progress (set by main from the X-hold timer)
var firing := false     # set by main each frame — fire-control activity tick
var _hitmarker: Label   # flashes on the crosshair when a shot lands
var _codex_label: Label # "Discovered N/M"
var _objective_label: Label # "→ <star> <dist>" — the Survey guide line
var _toast_label: Label # "✓ X discovered" pop
var _controls: PanelContainer   # the controls cheat-sheet menu (toggled by ?)
var teleport_sites_button: Button
var teleport_button: Button   # connected by main -> teleport_home()
var _tp_net_button: Button    # bottom-centre "TELEPORT NETWORK" → open_teleport_map (while docked)
var tp_cancel_button: Button  # shown only during a teleport ritual -> main.cancel_teleport()
var details_button: Button    # connected by main -> PlanetInfo.open_for_nearest()
var map_button: Button        # -> StarMap.toggle()
var log_button: Button        # -> QuestLog.toggle()
var codex_button: Button      # -> CodexPanel.toggle()
var settings_button: Button   # -> SettingsMenu.toggle()
var controls_button: Button   # toggles the controls cheat-sheet
var nav_button: Button        # -> main.toggle_nav() (stop/resume the Survey guide)
var cancel_nav_button: Button # -> cancels a locked (paid) map waypoint; shown only then
var _cancel_nav_was_visible := false   # remembers its real state while the editor force-shows it
var _detail_range := 600.0    # show the Details button within this of a body (×10 spread)

# --- HUD layout editor -------------------------------------------------------
# Each movable widget is tracked by a stable id; positions are saved to disk and
# re-applied on launch. Edit mode (opened from Settings) lets you drag them.
# Versioned layout: preserve the old file, never reinterpret its overlapping positions.
const LAYOUT_FILE := "hud_layout_v3.cfg"
# The shipped DEFAULT layout (the hand-tuned "best" arrangement). Used as each
# widget's built-in position/scale, so fresh installs and Reset land here. A saved
# user layout still overrides it.
const DEFAULT_LAYOUT := {
 "nav": Vector2(28, 582), "combat": Vector2(28, 108), "hull": Vector2(1080, 655),
 "teleport": Vector2(0, 252), "buttons": Vector2(1024, 62),
 "details": Vector2(1068, 612), "radar": Vector2(1150, 75),
 "cancel_nav": Vector2(1068, 516), "destination": Vector2(1068, 555),
}
const DEFAULT_SCALE := {
	"nav": 1.0, "combat": 1.0, "hull": 1.0, "teleport": 1.0,
	"buttons": 1.0, "details": 1.0, "radar": 0.5, "cancel_nav": 1.0,
}
var _flight_vector: Control
var _mode_label: Label
var _combat_panel: Control
var ship_ref: Ship                 # set by main, used to free/recapture the cursor in edit mode
var _movable: Array = []           # [{ id, node, def }]
var _saved := {}                   # id -> Vector2 position loaded from disk
var _saved_scale := {}             # id -> float scale loaded from disk
var _edit := false
var _drag: Control = null          # widget currently being dragged
var _drag_grab := Vector2.ZERO     # mouse offset within the dragged widget
var _systems_scrim: Control
var _systems_button: Button
var _systems_recapture := false
var _btn_bar: Control              # container wrapping the MAP/CODEX/?/⚙ buttons
var _edit_ui: Control              # dim scrim + banner + Save/Reset/Done toolbar
var _edit_toolbar: Control         # the toolbar rect (clicks here aren't drags)
var _edit_banner: Label
# Touch layout (phone/tablet or desktop `--touch`): widgets re-dock to the real canvas edges
# every resize (_touch_layout) and hangar targets grow by _hs. Desktop never takes this path.
var _touch := HudScale.is_touch()
var _hs := 1.0
var _hangar_scroll: ScrollContainer
var _hangar_opts: VBoxContainer
const HANGAR_TOUCH_MAX := 1.35


func _ready() -> void:
	# ALWAYS so the layout editor still receives input while the game is paused.
	process_mode = Node.PROCESS_MODE_ALWAYS
	if _touch:
		_hs = minf(HudScale.touch_scale(), HANGAR_TOUCH_MAX)
	_canvas = CanvasLayer.new()
	add_child(_canvas)
	_load_layout()

	_dist_label = _make_label(Vector2(28, 24), 14, C_TEXT)
	_dist_label.size = Vector2(540, 28)

	var nav := _flight_instrument(236.0)
	_canvas.add_child(nav.panel)
	_track("nav", nav.panel)
	_mode_label = _add_line(nav.body, 11, C_ACCENT)
	_speed_label = _add_line(nav.body, 24, C_TEXT)
	_tape_label = _add_line(nav.body, 12, C_TEXT)
	var destination := _flight_instrument(180.0)
	_canvas.add_child(destination.panel)
	_track("destination", destination.panel)
	var target_title := _add_line(destination.body, 12, C_DIM)
	target_title.text = "REFERENCE"
	target_title.visible = false
	_near_label = _add_line(destination.body, 13, C_TEXT)
	_near_label.custom_minimum_size.x = 180
	_near_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_codex_label = _add_line(destination.body, 11, C_DIM)
	_codex_label.visible = false
	_objective_label = _add_line(destination.body, 11, C_ACCENT)
	_objective_label.custom_minimum_size.x = 180
	_objective_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_flight_vector = preload("res://scripts/ui/flight_vector.gd").new()
	_canvas.add_child(_flight_vector)

	# Scan prompt/progress (center, below the crosshair) + discovery toast (center).
	# Declutter: feedback moves OFF the centre to the free right side (x ≈ 980), left-aligned,
	# so the play area around the crosshair stays clean. (A proper right-side rail/box is next.)
	# Touch moves the column to a top-centre band (_touch_layout) — x=28 sat in the joystick zone.
	var rx := 1000.0
	var feed_font := 16 if _touch else 14
	var feed_align := HORIZONTAL_ALIGNMENT_CENTER if _touch else HORIZONTAL_ALIGNMENT_LEFT
	_toast_label = _make_label(Vector2(rx, 450), feed_font, C_GREEN)
	_toast_label.size = Vector2(288, 60)
	_toast_label.horizontal_alignment = feed_align
	_toast_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_toast_label.modulate.a = 0.0

	# Contextual prompt ("Press F to …") — right side, under the toast, left-aligned.
	_prompt = _make_label(Vector2(rx, 535), feed_font, C_TEXT)
	_prompt.size = Vector2(288, 44)
	_prompt.horizontal_alignment = feed_align
	_prompt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	# Centered overlay text — teleport ritual and death screen.
	_menu = _make_label(Vector2(0, 210), 15, C_TEXT)
	_menu.size = Vector2(1280, 300)
	_menu.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_menu.visible = false

	# Full-screen colour flash — driven by the galactic core's damage + death kick. Sits over
	# the play area (under the panels would be fine too, but on top makes the hit read harder).
	_flash = ColorRect.new()
	_flash.color = Color(1.0, 0.12, 0.10, 0.0)
	_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE   # never eat clicks
	_canvas.add_child(_flash)

	_death = ColorRect.new()
	_death.color = Color(0.18, 0.02, 0.03, 0.72)
	_death.set_anchors_preset(Control.PRESET_FULL_RECT)
	_death.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_death.visible = false
	_canvas.add_child(_death)
	_death_label = Label.new()
	_death_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_death_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_death_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_death_label.add_theme_font_size_override("font_size", 36)
	_death_label.add_theme_color_override("font_color", Color(1.0, 0.82, 0.78))
	_death_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_death_label.add_theme_constant_override("outline_size", 8)
	_death_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_death.add_child(_death_label)

	# Cancel button shown only during a teleport ritual (main toggles + connects it).
	tp_cancel_button = Button.new()
	tp_cancel_button.text = "✕  CANCEL TELEPORT"
	tp_cancel_button.size = Vector2(200, 36)
	tp_cancel_button.position = Vector2((1280 - 200) * 0.5, 470)
	tp_cancel_button.focus_mode = Control.FOCUS_NONE
	tp_cancel_button.add_theme_font_size_override("font_size", 14)
	tp_cancel_button.add_theme_color_override("font_color", Color(1.0, 0.7, 0.7))
	tp_cancel_button.add_theme_color_override("font_hover_color", Color(1, 1, 1))
	tp_cancel_button.add_theme_stylebox_override("normal", _metal_box(Color(1.0, 0.45, 0.45), 0.5))
	tp_cancel_button.add_theme_stylebox_override("hover", _metal_box(Color(1.0, 0.55, 0.55), 0.9))
	tp_cancel_button.add_theme_stylebox_override("pressed", _metal_box(Color(1.0, 0.7, 0.7), 1.0))
	tp_cancel_button.visible = false
	_canvas.add_child(tp_cancel_button)

	# First-run onboarding tip — small, crisp warm-white, centered near the top (clear of
	# the crosshair cluster at y≈416 and the bottom _prompt). Kept deliberately compact:
	# small text reads fine on a PC monitor and doesn't bloat the view.
	_tip = _make_label(Vector2(0, 88), 14, Color(1.0, 0.97, 0.9))
	_tip.size = Vector2(1280, 20)
	_tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_tip.visible = false

	# Active-quest tracker (top-center, small gold): "✦ QUEST · <title>  (n/target)".
	_quest_label = _make_label(Vector2(0, 84), 12, Color(1.0, 0.86, 0.4))
	_quest_label.size = Vector2(1280, 18)
	_quest_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_quest_label.visible = false

	# Debug perf readout (top-center, hidden until F3). Monospace-ish small text: object
	# count / orphans / static RAM / render objects / FPS — to catch leaks during play.
	_debug_label = _make_label(Vector2(0, 40), 11, Color(0.6, 1.0, 0.7))
	_debug_label.size = Vector2(1280, 18)
	_debug_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_debug_label.visible = false

	# Arrival lore card — a framed panel that fades up on first reaching a system.
	_build_lore_card(_canvas)

	# Styled ship-pickup table (top-right, shown while docked).
	_build_hangar(_canvas)

	# Combat readout (top-right, frosted panel) + a center aiming reticle.
	# Wide enough that "HULL 100% · KILLS 188" never clips; its right edge sits at
	# RIGHT_EDGE so it lines up with the button bar below.
	var cw := 182.0
	var cstat := _glass_panel(Vector2(RIGHT_EDGE - cw, 14), cw, C_ACCENT)
	cstat.panel.position.x = RIGHT_EDGE - cw
	_canvas.add_child(cstat.panel)
	_track("combat", cstat.panel)
	_combat_panel = cstat.panel
	_combat_label = _add_line(cstat.body, 14, C_TEXT)
	_combat_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_combat_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	# Player hull bar (top-left, under the nav panel). A real coloured bar; the
	# top-right box keeps just the kill count. Draggable/resizable in the HUD editor.
	_build_hull_bar(_canvas)

	# Fire-control pipper: actual shot path, target lead and confirmed hits.
	_reticle = load("res://scripts/ui/crosshair.gd").new()
	_reticle.size = Vector2(80, 80)
	_reticle.position = Vector2(640.0 - 40.0, 360.0 - 40.0)
	_canvas.add_child(_reticle)

	# Hold-X lock ring — a radial progress arc that fills around the crosshair while you hold X.
	_lock_ring = Control.new()
	_lock_ring.set_anchors_preset(Control.PRESET_FULL_RECT)
	_lock_ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_lock_ring.draw.connect(_draw_lock_ring)
	_canvas.add_child(_lock_ring)

	# Hitmarker — a bright ✕ that pops over the crosshair when a shot connects.
	_hitmarker = _make_label(Vector2(0, 344), 23, Color(1, 1, 1, 0))
	_hitmarker.size = Vector2(1280, 36)
	_hitmarker.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hitmarker.text = "✕"

	_build_teleport_button(_canvas)
	_build_teleport_net_button(_canvas)
	_build_button_bar(_canvas)
	_build_controls_menu(_canvas)
	# Bottom help line removed in the declutter pass (verbs live in the ? controls panel).

	# "Details" button — appears (bottom-right, above Teleport) when you're near a planet,
	# so it never blocks the centre of the view.
	details_button = Button.new()
	details_button.position = Vector2(1088, 636)
	details_button.size = Vector2(180, 26)
	details_button.focus_mode = Control.FOCUS_NONE
	details_button.add_theme_font_size_override("font_size", 11)
	details_button.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	details_button.add_theme_color_override("font_color", C_TEXT)

	details_button.add_theme_stylebox_override("hover", _metal_box(Color(0.7, 0.95, 1.0), 0.9))
	details_button.add_theme_stylebox_override("pressed", _metal_box(Color(0.8, 1.0, 1.0), 1.0))
	details_button.visible = false
	_canvas.add_child(details_button)
	_track("details", details_button)

	_build_edit_ui(_canvas)
	if _touch:
		get_viewport().size_changed.connect(_touch_layout)
		_touch_layout()


# Touch only: every widget authored against the 1280x720 base re-docks onto the CURRENT
# canvas (wider phones, taller tablets) inset by the display cutout — edge widgets keep
# their edge gap, centre-band text re-centres, the feed column moves to the top-centre band
# clear of TouchControls' DEV strip. Base positions are cached on first call (meta
# "base_pos") so repeated resizes don't accumulate.
func _touch_layout() -> void:
	var size := get_viewport().get_visible_rect().size
	var ins := HudScale.safe_insets(size)
	var cx := size.x * 0.5
	var dy := (size.y - SCREEN.y) * 0.5
	for item in _movable:
		_dock_movable(item, size, ins)
	_dist_label.position = _base_pos(_dist_label) + Vector2(ins.left, ins.top)
	for l in [_tip, _quest_label, _debug_label]:
		l.position = Vector2(0.0, _base_pos(l).y + ins.top)
		l.size.x = size.x
	for l in [_menu, _hitmarker]:
		l.position = Vector2(0.0, _base_pos(l).y + dy)
		l.size.x = size.x
	_lore.position = Vector2(cx - _lore.size.x * 0.5, _base_pos(_lore).y + ins.top)
	tp_cancel_button.position = Vector2(cx - tp_cancel_button.size.x * 0.5, _base_pos(tp_cancel_button).y + dy)
	_edit_banner.size.x = size.x
	_edit_toolbar.position = Vector2(cx - 170.0, size.y - ins.bottom - 60.0)

	var feed_w: float = clampf(size.x * 0.42, 280.0, 560.0)
	var feed_x := cx - feed_w * 0.5
	_toast_label.position = Vector2(feed_x, 132.0 + ins.top)
	_toast_label.size = Vector2(feed_w, 60)
	_prompt.position = Vector2(feed_x, 222.0 + ins.top)
	_prompt.size = Vector2(feed_w, 44)

	teleport_sites_button.offset_left = -256.0 - ins.right
	teleport_sites_button.offset_right = -180.0 - ins.right
	teleport_sites_button.offset_top = 12.0 + ins.top
	teleport_sites_button.offset_bottom = 42.0 + ins.top
	_systems_button.offset_left = -172.0 - ins.right
	_systems_button.offset_right = -84.0 - ins.right
	_systems_button.offset_top = 12.0 + ins.top
	_systems_button.offset_bottom = 42.0 + ins.top
	teleport_sites_button.visible = false
	_systems_button.visible = false

	_tp_net_button.size = Vector2(268.0, 44.0) * _hs
	_tp_net_button.position = Vector2(cx - _tp_net_button.size.x * 0.5,
		size.y - ins.bottom - 16.0 - _tp_net_button.size.y)
	_fit_hangar()


func _base_pos(node: Control) -> Vector2:
	if not node.has_meta("base_pos"):
		node.set_meta("base_pos", node.position)
	return node.get_meta("base_pos")


func _dock_movable(item: Dictionary, size: Vector2, ins: Dictionary) -> void:
	if _saved.has(item.id):
		return
	var node: Control = item.node
	node.position = HudScale.dock_pos(item.def, node.size * item.defs, size, ins)


# Touch hangar: right-docked under the top buttons down to the bottom edge; the scroll box
# takes the content's height until that runs out. TELEPORT NETWORK then centres in the free
# bottom strip between the bottom-left speed/hull stack and the hangar, or — when that
# strip is too narrow (16:9 at 1.35x) — stacks just above the bottom-left widgets.
func _fit_hangar() -> void:
	if not _touch or _hangar == null:
		return
	var size := get_viewport().get_visible_rect().size
	var ins := HudScale.safe_insets(size)
	var top: float = 72.0 + ins.top
	var bottom: float = size.y - ins.bottom - 12.0
	var content: Vector2 = _hangar_scroll.get_child(0).get_combined_minimum_size()
	var chrome := _hangar.get_combined_minimum_size().y - _hangar_scroll.custom_minimum_size.y
	_hangar_scroll.custom_minimum_size = Vector2(content.x, minf(content.y, maxf(80.0, bottom - top - chrome)))
	_hangar.size = Vector2.ZERO
	_hangar.position = Vector2(size.x - ins.right - 16.0 - _hangar.get_combined_minimum_size().x, top)
	var stack := Rect2()
	for item in _movable:
		if item.id in ["nav", "hull"]:
			var r := Rect2(item.node.position, item.node.size * item.node.scale)
			stack = stack.merge(r) if stack.has_area() else r
	var w: float = _tp_net_button.size.x
	var free_l: float = stack.end.x + 12.0
	var free_r: float = _hangar.position.x - 12.0
	if free_r - free_l >= w:
		_tp_net_button.position = Vector2((free_l + free_r - w) * 0.5, size.y - ins.bottom - 16.0 - _tp_net_button.size.y)
	else:
		_tp_net_button.position = Vector2(stack.position.x, stack.position.y - 12.0 - _tp_net_button.size.y)


func _tap_key(code: int) -> void:
	for pressed in [true, false]:
		var ev := InputEventKey.new()
		ev.keycode = code
		ev.physical_keycode = code
		ev.pressed = pressed
		Input.parse_input_event(ev)


# Squared, brushed-metal, cyan-glow sci-fi button: "⌖ TELEPORT EARTH".
func _build_teleport_button(canvas: CanvasLayer) -> void:
	teleport_button = Button.new()
	teleport_button.text = "RETURN TO EARTH"
	teleport_button.size = Vector2(176, 32)
	teleport_button.position = Vector2(RIGHT_EDGE - 176.0, 674)
	teleport_button.focus_mode = Control.FOCUS_NONE
	teleport_button.add_theme_font_size_override("font_size", 12)
	teleport_button.add_theme_color_override("font_color", C_TEXT)
	teleport_button.add_theme_color_override("font_hover_color", Color(1, 1, 1))
	teleport_button.add_theme_stylebox_override("normal", _metal_box(Color(0.40, 0.85, 1.0), 0.45))
	teleport_button.add_theme_stylebox_override("hover", _metal_box(Color(0.55, 0.95, 1.0), 0.85))
	teleport_button.add_theme_stylebox_override("pressed", _metal_box(Color(0.7, 1.0, 1.0), 1.0))
	canvas.add_child(teleport_button)


# Bottom-centre "TELEPORT NETWORK" button — appears while docked at a platform (set_hangar
# toggles it), opens the platform fast-travel console. Disabled-looking when nothing's unlocked.
func _build_teleport_net_button(canvas: CanvasLayer) -> void:
	_tp_net_button = Button.new()
	_tp_net_button.text = "⌖  TELEPORT NETWORK"
	_tp_net_button.size = Vector2(268, 36)
	_tp_net_button.position = Vector2(640 - 134, 660)   # design-space bottom-centre
	_tp_net_button.focus_mode = Control.FOCUS_NONE
	_tp_net_button.add_theme_font_size_override("font_size", roundi(13 * _hs))
	_tp_net_button.add_theme_color_override("font_color", C_TEXT)
	_tp_net_button.add_theme_color_override("font_hover_color", Color(1, 1, 1))
	_tp_net_button.add_theme_stylebox_override("normal", _metal_box(Color(0.40, 1.0, 0.85), 0.5))
	_tp_net_button.add_theme_stylebox_override("hover", _metal_box(Color(0.55, 1.0, 0.9), 0.9))
	_tp_net_button.add_theme_stylebox_override("pressed", _metal_box(Color(0.7, 1.0, 0.95), 1.0))
	_tp_net_button.add_theme_stylebox_override("disabled", _metal_box(Color(0.4, 0.45, 0.5), 0.3))
	_tp_net_button.visible = false
	_tp_net_button.pressed.connect(func(): open_teleport_map.emit())
	canvas.add_child(_tp_net_button)


# A bar widget: dark frame + a coloured fill that we resize to the value ratio.
# Returns { root, fill, inner_w }. The caller positions/sizes/adds `root`.
func _build_bar(width: float, height: float, fill: Color) -> Dictionary:
	var root := Control.new()
	root.custom_minimum_size = Vector2(width, height)
	root.size = Vector2(width, height)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var frame := Panel.new()
	frame.set_anchors_preset(Control.PRESET_FULL_RECT)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.04, 0.06, 0.10, 0.72)
	sb.set_border_width_all(1)
	sb.border_color = Color(C_ACCENT.r, C_ACCENT.g, C_ACCENT.b, 0.7)
	sb.set_corner_radius_all(0)
	frame.add_theme_stylebox_override("panel", sb)
	root.add_child(frame)
	var bar := ColorRect.new()
	bar.color = fill
	bar.position = Vector2(2, 2)
	bar.size = Vector2(width - 4, height - 4)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(bar)
	return { "root": root, "fill": bar, "inner_w": width - 4 }


# Player hull bar (top-left) — green→amber→red as the hull falls.
func _build_hull_bar(canvas: CanvasLayer) -> void:
	var holder := Control.new()
	holder.position = Vector2(16, 96)
	holder.size = Vector2(184, 26)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hull_label = _new_label(10, C_TEXT)
	_hull_label.position = Vector2(1, 0)
	holder.add_child(_hull_label)
	var bar := _build_bar(156, 7, C_GREEN)
	bar.root.position = Vector2(0, 16)
	holder.add_child(bar.root)
	_hull_fill = bar.fill
	_hull_bar_w = bar.inner_w
	# Weapon-energy bar (thin, cyan) — drained by shooting.
	var ebar := _build_bar(156, 5, Color(0.4, 0.85, 1.0))
	ebar.root.position = Vector2(0, 26)
	holder.add_child(ebar.root)
	_energy_fill = ebar.fill
	_energy_bar_w = ebar.inner_w
	# Boost-energy bar (thin, orange) — drained by Shift boost.
	var bbar := _build_bar(156, 5, Color(1.0, 0.65, 0.25))
	bbar.root.position = Vector2(0, 34)
	holder.add_child(bbar.root)
	_boost_fill = bbar.fill
	_boost_bar_w = bbar.inner_w
	holder.size = Vector2(184, 52)
	canvas.add_child(holder)
	_track("hull", holder)


# Styled top-right control bar: open the map / codex / controls / settings by click.
func _build_button_bar(canvas: CanvasLayer) -> void:
	var systems_layer := CanvasLayer.new()
	systems_layer.layer = 100
	add_child(systems_layer)
	_systems_scrim = Control.new()
	_systems_scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	systems_layer.add_child(_systems_scrim)
	_systems_scrim.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.pressed:
			_systems_scrim.accept_event()
			_set_systems_open(false))
	_systems_button = _icon_button(systems_layer, "SYSTEMS  [F1]", Vector2(1136, 22), 112, C_ACCENT)
	_systems_button.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_systems_button.offset_left = -144
	_systems_button.offset_right = -24
	_systems_button.offset_top = 18
	_systems_button.offset_bottom = 62
	teleport_sites_button = _icon_button(systems_layer, "TELEPORT", Vector2.ZERO, 116, C_ACCENT)
	teleport_sites_button.tooltip_text = "Choose a planet or landmark · Ctrl+P"
	teleport_sites_button.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	teleport_sites_button.offset_left = -272
	teleport_sites_button.offset_right = -156
	teleport_sites_button.offset_top = 18
	teleport_sites_button.offset_bottom = 62
	teleport_sites_button.pressed.connect(func():
		_set_systems_open(false)
		open_teleport_sites.emit())
	_btn_bar = Panel.new()
	_btn_bar.size = Vector2(224, 300)
	var background := _metal_box(C_ACCENT, 0.35)
	background.bg_color = Color(0.025, 0.035, 0.045, 0.98)
	_btn_bar.add_theme_stylebox_override("panel", background)
	systems_layer.add_child(_btn_bar)
	_track("buttons", _btn_bar)
	_btn_bar.position.x += get_viewport().get_visible_rect().size.x - 1280.0
	nav_button = _icon_button(_btn_bar, "NAVIGATION MARKERS", Vector2(12, 12), 200, C_ACCENT)
	map_button = _icon_button(_btn_bar, "Navigation chart     [M]", Vector2(12, 48), 200, C_ACCENT)
	log_button = _icon_button(_btn_bar, "Mission log                 [J]", Vector2(12, 84), 200, C_ACCENT)
	codex_button = _icon_button(_btn_bar, "Survey archive           [L]", Vector2(12, 120), 200, C_ACCENT)
	controls_button = _icon_button(_btn_bar, "Flight controls", Vector2(12, 156), 200, C_ACCENT)
	settings_button = _icon_button(_btn_bar, "Settings", Vector2(12, 192), 200, C_ACCENT)
	teleport_button.reparent(_btn_bar)
	teleport_button.position = Vector2(12, 252)
	teleport_button.size = Vector2(200, 32)
	for button in [nav_button, map_button, log_button, codex_button, controls_button, settings_button, teleport_button]:
		button.size.y = 32
		button.pressed.connect(func(): _set_systems_open(false))
	controls_button.pressed.connect(toggle_controls)
	_systems_button.pressed.connect(func(): _set_systems_open(not _btn_bar.visible))
	_set_systems_open(false)

	# Cancel-Nav button: only shown while a LOCKED (paid) map waypoint is active.
	cancel_nav_button = Button.new()
	cancel_nav_button.text = "✖ CANCEL NAV"
	cancel_nav_button.position = Vector2(12, 602)   # default placement (also in DEFAULT_LAYOUT/SCALE; editor-movable)
	cancel_nav_button.scale = Vector2(0.7, 0.7)
	cancel_nav_button.size = Vector2(160, 26)
	cancel_nav_button.focus_mode = Control.FOCUS_NONE
	cancel_nav_button.add_theme_font_size_override("font_size", 12)
	cancel_nav_button.add_theme_color_override("font_color", Color(1.0, 0.7, 0.4))
	cancel_nav_button.add_theme_stylebox_override("normal", _metal_box(Color(1.0, 0.6, 0.15), 0.5))
	cancel_nav_button.add_theme_stylebox_override("hover", _metal_box(Color(1.0, 0.7, 0.3), 0.9))
	cancel_nav_button.add_theme_stylebox_override("pressed", _metal_box(Color(1.0, 0.8, 0.4), 1.0))
	cancel_nav_button.visible = false
	canvas.add_child(cancel_nav_button)
	# Make it a drag-placeable HUD widget: position persists in the layout editor.
	register_movable("cancel_nav", cancel_nav_button)


# Reflect nav on/off in the button label so it's clear what tapping it does.
func set_nav_stopped(stopped: bool) -> void:
	if nav_button != null:
		nav_button.text = "Navigation markers: OFF" if stopped else "Navigation markers: ON"

# Show/hide the Cancel-Nav button (main calls this while a locked waypoint is active).
func set_cancel_nav_visible(v: bool) -> void:
	if cancel_nav_button != null:
		cancel_nav_button.visible = v

func is_systems_open() -> bool:
	return _btn_bar != null and _btn_bar.visible

func toggle_systems() -> void:
	_set_systems_open(not is_systems_open())

# Every tappable hud widget the raw-touch overlay would otherwise also act on underneath.
func blocks_flight_touch(pos: Vector2) -> bool:
	if is_systems_open():
		return true
	for c in [_systems_button, teleport_sites_button, _hangar, _tp_net_button, details_button,
			cancel_nav_button, tp_cancel_button]:
		if c != null and c.is_visible_in_tree() and c.get_global_rect().has_point(pos):
			return true
	return false

func _set_systems_open(open: bool) -> void:
	if open and not is_systems_open():
		_systems_recapture = Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED
		if ship_ref != null:
			ship_ref._set_capture(false)
	elif not open and is_systems_open() and _systems_recapture:
		if ship_ref != null and not ship_ref.frozen and not ship_ref.transiting:
			ship_ref._set_capture(true)
		_systems_recapture = false
	_btn_bar.visible = open
	_systems_scrim.visible = open
	_systems_button.text = "CLOSE  [F1]" if open else "SYSTEMS  [F1]"

func _icon_button(parent: Node, text: String, pos: Vector2, w: float, edge: Color) -> Button:
	var b := Button.new()
	b.text = text
	b.position = pos
	b.size = Vector2(w, 26)
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 11)
	b.add_theme_color_override("font_color", C_TEXT)
	b.add_theme_color_override("font_hover_color", Color(1, 1, 1))
	b.add_theme_stylebox_override("normal", _metal_box(edge, 0.4))
	b.add_theme_stylebox_override("hover", _metal_box(edge.lightened(0.2), 0.85))
	b.add_theme_stylebox_override("pressed", _metal_box(edge.lightened(0.4), 1.0))
	parent.add_child(b)
	return b


# --- HUD layout editor ---------------------------------------------------------
# Register a movable widget under a stable id, remembering its built-in position
# as the "default", and snap it to any saved position. Called for the built-in
# widgets in _ready, and by main for external ones (e.g. the radar).
func _track(id: String, node: Control) -> void:
	# Built-in default = the shipped tuned layout (falls back to the node's own
	# code position/scale if this id isn't in the default tables).
	var def_pos: Vector2 = DEFAULT_LAYOUT.get(id, node.position)
	var touch := OS.has_feature("mobile") or "--touch" in OS.get_cmdline_user_args()
	if touch:
		def_pos = {"destination": Vector2(28, 55), "details": Vector2(28, 85),
			"hull": Vector2(28, 535), "cancel_nav": Vector2(28, 120), "radar": Vector2(1170, 76)}.get(id, def_pos)
	var def_scl := node.scale
	if DEFAULT_SCALE.has(id):
		var ds: float = DEFAULT_SCALE[id]
		def_scl = Vector2(ds, ds)
	if touch and id == "radar":
		def_scl = Vector2(0.45, 0.45)
	node.position = def_pos
	node.scale = def_scl
	_movable.append({ "id": id, "node": node, "def": def_pos, "defs": def_scl })
	if touch and is_inside_tree():
		var canvas := get_viewport().get_visible_rect().size
		_dock_movable(_movable[-1], canvas, HudScale.safe_insets(canvas))
	# A saved user layout still wins over the default.
	if _saved.has(id):
		node.position = _saved[id]
	if _saved_scale.has(id):
		var s: float = _saved_scale[id]
		node.scale = Vector2(s, s)

func register_movable(id: String, node: Control) -> void:
	_track(id, node)

# Reference resolution: 1280×720 (project stretch base) — clamp drags to it.
const SCREEN := Vector2(1280, 720)
const HUD_SCALE_MIN := 0.5
const HUD_SCALE_MAX := 1.4

func _load_layout() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(ProfileDir.path(LAYOUT_FILE)) != OK:
		return
	if cfg.has_section("layout"):
		for id in cfg.get_section_keys("layout"):
			_saved[id] = cfg.get_value("layout", id)
	if cfg.has_section("scale"):
		for id in cfg.get_section_keys("scale"):
			_saved_scale[id] = cfg.get_value("scale", id)

func _save_layout() -> void:
	var cfg := ConfigFile.new()
	for item in _movable:
		cfg.set_value("layout", item.id, item.node.position)
		cfg.set_value("scale", item.id, item.node.scale.x)
		_saved[item.id] = item.node.position       # keep the cancel-baseline in sync
		_saved_scale[item.id] = item.node.scale.x
	cfg.save(ProfileDir.path(LAYOUT_FILE))

func _reset_layout() -> void:
	for item in _movable:
		item.node.position = item.def
		item.node.scale = item.defs
	_saved.clear()
	_saved_scale.clear()
	var cfg := ConfigFile.new()   # write an empty file so the reset persists
	cfg.save(ProfileDir.path(LAYOUT_FILE))
	if _touch:
		_touch_layout()


# Dim scrim + banner + Save/Reset/Done toolbar. Hidden until enter_edit().
func _build_edit_ui(canvas: CanvasLayer) -> void:
	_edit_ui = Control.new()
	_edit_ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	_edit_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE   # drags are handled in _input
	_edit_ui.visible = false

	var scrim := ColorRect.new()
	scrim.color = Color(0.02, 0.05, 0.10, 0.45)
	scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_edit_ui.add_child(scrim)

	var banner := _new_label(15, C_ACCENT)
	_edit_banner = banner
	banner.text = "◇  HUD LAYOUT  —  drag to move  ·  scroll to resize"
	banner.position = Vector2(0, 24)
	banner.size = Vector2(SCREEN.x, 24)
	banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_edit_ui.add_child(banner)

	# Bottom-center toolbar. Clicks inside its rect are NOT treated as drags.
	_edit_toolbar = HBoxContainer.new()
	_edit_toolbar.add_theme_constant_override("separation", 10)
	_edit_toolbar.position = Vector2(SCREEN.x * 0.5 - 170, SCREEN.y - 60)
	_edit_toolbar.add_child(_edit_btn("✓  SAVE", C_GREEN, func(): _exit_edit(true)))
	_edit_toolbar.add_child(_edit_btn("↺  RESET", C_WARN, _reset_layout))
	_edit_toolbar.add_child(_edit_btn("✕  CANCEL", C_ACCENT, func(): _exit_edit(false)))
	_edit_ui.add_child(_edit_toolbar)

	canvas.add_child(_edit_ui)

func _edit_btn(text: String, edge: Color, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.size = Vector2(110, 34)
	b.custom_minimum_size = Vector2(110, 34)
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 13)
	b.add_theme_color_override("font_color", C_TEXT)
	b.add_theme_stylebox_override("normal", _metal_box(edge, 0.5))
	b.add_theme_stylebox_override("hover", _metal_box(edge.lightened(0.2), 0.9))
	b.add_theme_stylebox_override("pressed", _metal_box(edge.lightened(0.4), 1.0))
	b.pressed.connect(cb)
	return b


# Open/close the editor. Pauses flight and frees the cursor so panels can be dragged.
func enter_edit() -> void:
	if _edit:
		return
	_edit = true
	_edit_ui.visible = true
	# Force-show the Cancel-Nav button so it can be grabbed even when no waypoint is active.
	if cancel_nav_button != null:
		_cancel_nav_was_visible = cancel_nav_button.visible
		cancel_nav_button.visible = true
	get_tree().paused = true
	if ship_ref != null:
		ship_ref._set_capture(false)

func _exit_edit(save: bool) -> void:
	if save:
		_save_layout()
	else:
		# Cancel: restore whatever was on disk (or defaults) before this session.
		for item in _movable:
			item.node.position = _saved.get(item.id, item.def)
			var s: float = _saved_scale.get(item.id, item.defs.x)
			item.node.scale = Vector2(s, s)
	_edit = false
	_edit_ui.visible = false
	# Restore the Cancel-Nav button's real visibility (only shown with a live waypoint).
	if cancel_nav_button != null:
		cancel_nav_button.visible = _cancel_nav_was_visible
	get_tree().paused = false
	if ship_ref != null and not ship_ref.frozen:
		ship_ref._set_capture(true)


# Drag the movable widgets while in edit mode. Handled here (not via each widget's
# gui_input) so the click is consumed before buttons fire, while toolbar clicks
# still fall through to the toolbar.
func _input(event: InputEvent) -> void:
	if not _edit:
		return
	var mpos := _edit_ui.get_global_mouse_position()
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			if _edit_toolbar.get_global_rect().has_point(mpos):
				return   # let the toolbar buttons handle their own click
			for item in _movable:
				var node: Control = item.node
				if node.visible and node.get_global_rect().has_point(mpos):
					_drag = node
					_drag_grab = mpos - node.position
					get_viewport().set_input_as_handled()
					break
		elif _drag != null:
			_drag = null
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and _drag != null:
		var sz := _drag.get_global_rect().size
		var bounds := get_viewport().get_visible_rect().size if _touch else SCREEN
		_drag.position = Vector2(
			clampf(mpos.x - _drag_grab.x, 0.0, bounds.x - sz.x),
			clampf(mpos.y - _drag_grab.y, 0.0, bounds.y - sz.y))
		get_viewport().set_input_as_handled()
	# Scroll the wheel over a widget to resize it (HUD scale, persisted with position).
	elif event is InputEventMouseButton and event.pressed \
			and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		for item in _movable:
			var node: Control = item.node
			if node.visible and node.get_global_rect().has_point(mpos):
				var step := 0.06 if event.button_index == MOUSE_BUTTON_WHEEL_UP else -0.06
				var s := clampf(node.scale.x + step, HUD_SCALE_MIN, HUD_SCALE_MAX)
				node.scale = Vector2(s, s)
				get_viewport().set_input_as_handled()
				break


func _metal_box(edge: Color, glow: float) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.11, 0.16, 0.92)   # dark brushed steel
	sb.set_border_width_all(1)
	sb.border_color = Color(C_ACCENT.r, C_ACCENT.g, C_ACCENT.b, 0.2 + 0.4 * glow)
	sb.set_corner_radius_all(4)                    # softly rounded
	sb.set_content_margin_all(7)
	sb.shadow_color = Color(edge.r, edge.g, edge.b, 0.45 * glow)
	sb.shadow_size = 0
	return sb


# Declutter pass: the centered Survey-guide line is gone — guidance is the nav arrow now
# (a side notification/rail is coming). Kept as a no-op so callers don't need touching.
func set_objective(_text: String) -> void:
	if _objective_label != null and _objective_label.text != "":
		_objective_label.text = ""

# Top-center quest tracker removed — quests live in the J log (a right-side quest box is next).
func set_quest(_text: String) -> void:
	if _quest_label != null and _quest_label.visible:
		_quest_label.visible = false

func set_prompt(text: String) -> void:
	_prompt.text = text
	_prompt.visible = text != ""

func set_menu(text: String) -> void:
	_menu.text = text
	_menu.visible = text != ""   # hide the centered overlay when there's nothing to show


func set_death(on: bool, text: String = "") -> void:
	if _death == null:
		return
	_death.visible = on
	if _death_label != null:
		_death_label.text = text

# F3 perf overlay. "" hides it; any text shows it (main feeds the counters each frame).
func set_debug(text: String) -> void:
	_debug_label.visible = text != ""
	if text != "":
		_debug_label.text = text


# First-run onboarding tip line (warm-white, near the top). "" hides it. Called every
# frame, so skip the work when the text hasn't changed (reassigning Label.text re-lays
# out the text server even for an identical string). A new tip fades + drifts up gently.
func set_tip(_text: String) -> void:
	# Centered onboarding tip removed in the declutter pass (will return as a side notification).
	if _tip != null and _tip.visible:
		_tip.visible = false


# Pop the arrival lore card up for a few seconds (fades out in refresh()). Called by
# main on the FIRST arrival into a system.
const LORE_SHOW := 9.0   # seconds the lore card stays up (fades in/out at the ends)

func show_lore(text: String) -> void:
	if _lore == null:
		return
	_lore_label.text = text
	_lore.visible = true
	lore_t = LORE_SHOW


# Compact frosted lore card, centered. Small body text (PC-readable) with a thin glowing
# edge — informative without taking over the screen. Fades in/out via lore_t in refresh().
func _build_lore_card(canvas: CanvasLayer) -> void:
	var w := 470.0
	_lore = PanelContainer.new()
	_lore.size = Vector2(w, 150)
	_lore.position = Vector2((1280 - w) * 0.5, 150)
	var frame := StyleBoxFlat.new()
	frame.bg_color = Color(0.04, 0.06, 0.11, 0.88)
	frame.set_border_width_all(1)
	frame.border_color = Color(0.6, 1.0, 0.95, 0.8)
	frame.set_corner_radius_all(7)
	frame.set_content_margin_all(15)
	frame.shadow_color = Color(0.3, 0.7, 1.0, 0.3)
	frame.shadow_size = 12
	_lore.add_theme_stylebox_override("panel", frame)
	_lore_label = Label.new()
	_lore_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_lore_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_lore_label.add_theme_font_size_override("font_size", 12)
	_lore_label.add_theme_color_override("font_color", C_TEXT)
	_lore_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
	_lore_label.add_theme_constant_override("shadow_offset_y", 1)
	_lore.add_child(_lore_label)
	_lore.visible = false
	canvas.add_child(_lore)


# --- Controls cheat-sheet menu --------------------------------------------------
# All the key bindings, folded out of the play screen into a frosted panel you
# pop open with the [?] button (keeps the flight view clean).
const CONTROLS := [
	["WASD", "Thrust / strafe"],
	["Q / E", "Roll"],
	["Spc/Ctrl", "Climb / dive"],
	["Shift", "Boost"],
	["Num Lk", "Auto-cruise toggle"],
	["L-Click", "Fire weapons"],
	["B", "Landing gear"],
	["R", "Deploy / stow hardpoints"],
	["T / RMB", "Free-look (hold)"],
	["Tab", "Cycle target"],
	["X hold", "Lock nav target"],
	["N", "Stop / resume nav"],
	["G", "Planet details"],
	["L", "Codex log"],
	["J", "Mission log"],
	["M", "Star map"],
	["F", "Dock"],
	["1–5", "Swap ship (docked)"],
	["H", "Teleport home"],
	["F11", "Fullscreen"],
	["Esc", "Release cursor / back"],
]

# System explainers shown under the controls grid in the ? panel — always available, so a
# player past the beginner tips can still look up exactly how each mechanic works.
const GUIDE := [
	["TAB TARGETING",
	 "Aim down the crosshair and press Tab to lock the object your aim ray passes nearest to. Tab steps through the up-to-4 closest (1st → 2nd → 3rd → 4th → loop); move the cursor to re-rank. Unscanned objects read \"Unknown\" until you scan them. Hold X for 1s to LOCK the target as an orange waypoint — it sticks through aim changes and further Tabs until you press ✖ Cancel Nav."],
	["TELEPORT  (H)",
	 "Press H anywhere for an emergency jump straight home to Earth: a light-ball wraps the ship, shrinks to a bead, and you arrive."],
	["PLATFORMS & STATIONS",
	 "Every charted system has a dockable platform; Earth has the home station. Press F nearby to dock, then swap among the five ships (1–5) and open the TELEPORT NETWORK. From the network you can jump to any platform you have already reached and arrive right beside it. All platforms share the same ship roster and the same network."],
	["LANDING & HARDPOINTS",
	 "After five seconds without flight input, the ship assistant slowly levels the hull with the planet; steering, thrust, Q/E, and touch input stop it. Terrain protection stays automatic. Press B to lower the landing gear. Approach a designated pad slowly; Ctrl descends and Space lifts. PAD LOCKED requires supported feet on the pad. Ordinary ground never grants a pad lock. Lift off before retracting the gear. Inside atmosphere, R deploys or stows the weapon mounts; holding fire also deploys them. Firing waits for full deployment. Gear down or leaving atmosphere locks weapons; atmosphere exit automatically stows them. On touch screens use GEAR and ARMS; UP/DOWN provides vertical thrust with gear down."],
	["FLIGHT",
	 "WASD thrusts, Shift boosts (drains the boost bar), Q/E roll, Space/Ctrl climb and dive. Num Lock toggles hands-free auto-cruise."],
	["COMBAT & DISCOVERY",
	 "Hold left-click inside atmosphere to fire short plasma pulses from deployed weapons. Shots take time to travel and stop on terrain and buildings. Flying close to a body surveys it automatically — that fills the Codex (L), the details panel (G), and completes its survey mission."],
]

func _build_controls_menu(canvas: CanvasLayer) -> void:
	# Dim full-screen scrim so the panel reads as a modal overlay.
	_controls = PanelContainer.new()
	_controls.position = Vector2(348, 92)
	_controls.custom_minimum_size = Vector2(600, 0)
	_controls.add_theme_stylebox_override("panel", _frame_box(C_ACCENT))

	var bg := TextureRect.new()
	bg.texture = _linear_gradient(
		Color(0.06, 0.11, 0.19, 0.97), Color(0.01, 0.02, 0.05, 0.97))
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_controls.add_child(bg)

	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 18)
	_controls.add_child(margin)

	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 10)
	margin.add_child(outer)

	var title := _new_label(16, Color(0.7, 0.95, 1.0))
	title.text = "◆  GUIDE  —  CONTROLS & SYSTEMS"
	outer.add_child(title)

	# Scrollable body so the full reference always fits on screen.
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(560, 430)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	outer.add_child(scroll)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 11)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(col)

	var ctl_head := _new_label(13, C_ACCENT)
	ctl_head.text = "CONTROLS"
	col.add_child(ctl_head)

	# Two-column grid of keycap + action.
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 7)
	col.add_child(grid)
	for row in CONTROLS:
		grid.add_child(_keycap(row[0]))
		var desc := _new_label(11, C_TEXT)
		desc.text = row[1]
		desc.custom_minimum_size = Vector2(150, 0)
		grid.add_child(desc)

	# System explainers: how targeting / teleport / platforms / combat work.
	for sec in GUIDE:
		var sh := _new_label(13, C_ACCENT)
		sh.text = "◈  " + sec[0]
		col.add_child(sh)
		var body := _new_label(11, C_TEXT)
		body.text = sec[1]
		body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		body.custom_minimum_size = Vector2(520, 0)
		col.add_child(body)

	var close := Button.new()
	close.text = "CLOSE  [ ? ]"
	close.focus_mode = Control.FOCUS_NONE
	close.add_theme_font_size_override("font_size", 11)
	close.add_theme_color_override("font_color", C_TEXT)
	close.add_theme_stylebox_override("normal", _metal_box(C_ACCENT, 0.4))
	close.add_theme_stylebox_override("hover", _metal_box(C_ACCENT.lightened(0.2), 0.85))
	close.add_theme_stylebox_override("pressed", _metal_box(C_ACCENT.lightened(0.4), 1.0))
	close.pressed.connect(toggle_controls)
	outer.add_child(close)

	_controls.visible = false
	canvas.add_child(_controls)

func toggle_controls() -> void:
	_controls.visible = not _controls.visible


# A little dark "keycap" chip with a glowing edge — the key you press.
func _keycap(text: String) -> PanelContainer:
	var cap := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.12, 0.18, 0.27, 0.95)
	sb.set_border_width_all(1)
	sb.border_color = C_ACCENT
	sb.set_corner_radius_all(4)
	sb.set_content_margin_all(5)
	sb.content_margin_left = 9
	sb.content_margin_right = 9
	cap.add_theme_stylebox_override("panel", sb)
	cap.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var l := _new_label(11, Color(0.75, 0.95, 1.0))
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cap.add_child(l)
	return cap


# --- Hangar (ship-pickup table) -------------------------------------------------
const HANGAR_W := 320.0
const HANGAR_X := 1280.0 - HANGAR_W - 16.0   # top-right, clear of the screen edge
const HANGAR_Y := 132.0                       # below the MAP/CODEX/⚙ button bar

# A bordered, gradient-backed panel in the top-right. Built once; set_hangar()
# fills/clears the rows and shows or hides it.
func _build_hangar(canvas: CanvasLayer) -> void:
	_hangar = PanelContainer.new()
	_hangar.position = Vector2(HANGAR_X, HANGAR_Y)
	_hangar.custom_minimum_size = Vector2(HANGAR_W, 0)
	_hangar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hangar.add_theme_stylebox_override("panel", _frame_box(C_ACCENT))

	# Linear-gradient backdrop, stretched to fill the panel (drawn behind content).
	_hangar_bg = TextureRect.new()
	_hangar_bg.texture = _linear_gradient(
		Color(0.07, 0.12, 0.20, 0.96), Color(0.01, 0.02, 0.05, 0.96))
	_hangar_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_hangar_bg.stretch_mode = TextureRect.STRETCH_SCALE
	_hangar_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hangar.add_child(_hangar_bg)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	_hangar.add_child(margin)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 7)
	margin.add_child(col)
	if _touch:
		_build_hangar_touch(col)
		_hangar.visible = false
		canvas.add_child(_hangar)
		return

	_hangar_title = _new_label(13, Color(0.7, 0.95, 1.0))
	col.add_child(_hangar_title)

	var sub := _new_label(10, C_DIM)
	sub.text = "SELECT A SHIP  ·  PRESS A NUMBER"
	col.add_child(sub)

	_hangar_rows = VBoxContainer.new()
	_hangar_rows.add_theme_constant_override("separation", 0)   # rows touch -> a table grid
	col.add_child(_hangar_rows)

	var footer := _new_label(10, C_DIM)
	footer.text = "[ F ]   Undock"
	col.add_child(footer)

	_hangar.visible = false
	canvas.add_child(_hangar)


# Touch hangar: title + UNDOCK button (no F key on a phone) over a scroll box holding two
# columns — ship rows left, colour/finish/module pickers right — so 7 ships plus pickers fit
# a 720-tall canvas at finger size.
func _build_hangar_touch(col: VBoxContainer) -> void:
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", roundi(10 * _hs))
	col.add_child(head)
	_hangar_title = _new_label(roundi(13 * _hs), Color(0.7, 0.95, 1.0))
	_hangar_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_hangar_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	head.add_child(_hangar_title)
	var undock := Button.new()
	undock.text = "UNDOCK"
	undock.custom_minimum_size = Vector2(120, 48) * _hs
	undock.focus_mode = Control.FOCUS_NONE
	undock.add_theme_font_size_override("font_size", roundi(13 * _hs))
	undock.add_theme_color_override("font_color", C_TEXT)
	undock.add_theme_stylebox_override("normal", _metal_box(C_ACCENT, 0.5))
	undock.add_theme_stylebox_override("hover", _metal_box(C_ACCENT, 0.5))
	undock.add_theme_stylebox_override("pressed", _metal_box(C_ACCENT.lightened(0.3), 1.0))
	undock.pressed.connect(_tap_key.bind(KEY_F))
	head.add_child(undock)

	_hangar_scroll = ScrollContainer.new()
	_hangar_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(_hangar_scroll)
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", roundi(14 * _hs))
	_hangar_scroll.add_child(cols)
	_hangar_rows = VBoxContainer.new()
	_hangar_rows.add_theme_constant_override("separation", roundi(4 * _hs))
	_hangar_rows.custom_minimum_size.x = 240 * _hs
	cols.add_child(_hangar_rows)
	_hangar_opts = VBoxContainer.new()
	_hangar_opts.add_theme_constant_override("separation", roundi(6 * _hs))
	cols.add_child(_hangar_opts)


# Outer frame stylebox: transparent fill (so a gradient TextureRect shows through),
# glowing cyan edge + soft halo. Shared by the hangar and controls panels.
func _frame_box(edge: Color) -> StyleBoxFlat:
	var frame := StyleBoxFlat.new()
	frame.bg_color = Color(0, 0, 0, 0)
	frame.set_border_width_all(1)
	frame.border_color = Color(edge.r, edge.g, edge.b, 0.20)
	frame.set_corner_radius_all(2)
	frame.shadow_color = Color(edge.r, edge.g, edge.b, 0.35)
	frame.shadow_size = 0
	return frame


# A frosted-glass info panel: gradient backdrop + glowing edge + a VBox body you
# pour styled lines into. Returns { panel, body }.
func _flight_instrument(width: float) -> Dictionary:
	var panel := PanelContainer.new()
	panel.custom_minimum_size.x = width
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 3)
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(body)
	return {"panel": panel, "body": body}

func _glass_panel(pos: Vector2, min_w: float, edge: Color) -> Dictionary:
	var panel := PanelContainer.new()
	panel.position = pos
	panel.custom_minimum_size = Vector2(min_w, 0)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel", _frame_box(edge))

	var bg := TextureRect.new()
	bg.texture = _linear_gradient(
		Color(0.035, 0.055, 0.065, 0.88), Color(0.035, 0.055, 0.065, 0.88))
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(bg)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_top", 7)
	margin.add_theme_constant_override("margin_bottom", 7)
	panel.add_child(margin)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(col)
	return { "panel": panel, "body": col }


# A top->bottom linear gradient as a texture (for the panel backdrops / row fills).
func _linear_gradient(top: Color, bottom: Color) -> GradientTexture2D:
	var g := Gradient.new()
	g.set_color(0, top)
	g.set_color(1, bottom)
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill = GradientTexture2D.FILL_LINEAR
	tex.fill_from = Vector2(0, 0)
	tex.fill_to = Vector2(0, 1)
	tex.width = 8
	tex.height = 64
	return tex


# Show/refresh the ship-pickup table. Rebuilds rows only when the contents change
# (ship set, current selection, or station name), so it's cheap to call per frame.
func set_hangar(open: bool, names: PackedStringArray, current: int, station: String, teleports := []) -> void:
	var has_color: bool = open and ship != null and ship.current_has_color_pick()
	var has_finish: bool = has_color and ship.current_has_finish_pick()
	var body_key: String = ship.current_body_color() if has_color else ""
	var finish: String = ship.current_finish() if has_finish else ""
	var tp_sig := ""
	for t in teleports:
		tp_sig += String(t.id) + ","
	# Colour is NOT in this sig. A pick (or a drag on the RGB tab) used to
	# change body_key, rebuild the rows, and queue_free the ColorPickerButton
	# popup — that's the RGB tab vanishing. Layout changes still rebuild.
	var modules: bool = open and ship != null and ship.current_is_modular()
	var locks := ""
	if open and ship != null:
		for i in names.size():
			locks += ship.ship_lock_text(i) + ","
	var module_sig: String = "%s/%s" % [ship.current_weapon_set(), ship.current_pad_set()] if modules else ""
	var sig := ("%d|%s|%s|%s|%s|%s|%s" % [current, station, ",".join(names), finish, tp_sig, locks, module_sig]) if open else ""
	if sig == _hangar_sig:
		if open and has_color:
			_sync_hangar_color(body_key)
		return
	_hangar_sig = sig
	_hangar_color_key = body_key
	_hangar.visible = open
	if _touch:
		for item in _movable:
			if item.id == "radar":
				item.node.visible = not open
	# Bottom-centre network button rides with the dock state.
	_tp_net_button.visible = open
	if open:
		var n: int = teleports.size()
		_tp_net_button.disabled = n == 0
		_tp_net_button.text = ("⌖  TELEPORT NETWORK  ·  %d station%s" % [n, "" if n == 1 else "s"]) \
			if n > 0 else "⌖  TELEPORT NETWORK  ·  none unlocked yet"
	if not open:
		return
	_hangar_title.text = "HANGAR · %s" % station
	_color_swatch_buttons.clear()
	_color_picker = null
	var opts: VBoxContainer = _hangar_opts if _touch else _hangar_rows
	if _touch:
		for c in _hangar_rows.get_children() + _hangar_opts.get_children():
			c.get_parent().remove_child(c)
			c.queue_free()
	for c in _hangar_rows.get_children():
		c.queue_free()
	for i in names.size():
		_hangar_rows.add_child(_make_hangar_row_touch(names[i], i, i == current) if _touch \
			else _make_hangar_row(names[i], i, i == current))
	if has_color:
		opts.add_child(_make_color_swatches("SHIP COLOUR", body_key))
	if has_finish:
		opts.add_child(_make_choice_row("FINISH",
			[{"key": "metallic", "label": "METALLIC"}, {"key": "glassy", "label": "GLASSY"}],
			finish, _on_finish_choice))
	if modules:
		var sets := [{"key": "mk1", "label": "MK1"}, {"key": "mk2", "label": "MK2"}]
		opts.add_child(_make_choice_row("WEAPONS", sets, ship.current_weapon_set(),
			func(key: String) -> void: ship_module_selected.emit("weapon", key)))
		opts.add_child(_make_choice_row("LANDING PADS", sets, ship.current_pad_set(),
			func(key: String) -> void: ship_module_selected.emit("pad", key)))
	if _touch:
		_fit_hangar.call_deferred()
	# (Teleport-network button now lives bottom-centre — see _build_teleport_net_button.)


# One bordered table row: ◈ icon · ship name · number key. Current ship is lit up.
func _make_hangar_row(ship_name: String, idx: int, is_current: bool) -> PanelContainer:
	var row := PanelContainer.new()
	var box := StyleBoxFlat.new()
	box.set_border_width_all(1)
	box.set_content_margin_all(8)
	if is_current:
		box.bg_color = Color(0.18, 0.45, 0.70, 0.45)
		box.border_color = Color(0.6, 0.95, 1.0, 0.95)
	else:
		box.bg_color = Color(0.10, 0.16, 0.24, 0.30)
		box.border_color = Color(0.35, 0.60, 0.80, 0.50)
	row.add_theme_stylebox_override("panel", box)
	# Clickable: pick this ship on left-click (number keys still work too).
	row.mouse_filter = Control.MOUSE_FILTER_STOP
	row.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	row.gui_input.connect(_on_hangar_row_input.bind(idx))

	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE   # let clicks fall through to the row
	row.add_child(h)

	var icon := _new_label(13, Color(0.7, 1.0, 1.0) if is_current else Color(0.5, 0.75, 0.95))
	icon.text = "◈"
	h.add_child(icon)

	var lock: String = ship.ship_lock_text(idx) if ship != null else ""
	var nm := _new_label(13, Color(1, 1, 1) if is_current else (C_DIM if lock != "" else C_TEXT))
	nm.text = ship_name
	nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(nm)

	var key := _new_label(11, Color(0.7, 1.0, 1.0) if is_current else C_DIM)
	key.text = ("◄ %d" % (idx + 1)) if is_current else (lock if lock != "" else str(idx + 1))
	h.add_child(key)

	return row


# Touch row: >=48 canvas px tall at scale 1, lock reason on its own readable line, locked
# rows visibly dimmed (dark fill, dim name, amber lock line).
func _make_hangar_row_touch(ship_name: String, idx: int, is_current: bool) -> PanelContainer:
	var lock: String = ship.ship_lock_text(idx) if ship != null else ""
	var row := PanelContainer.new()
	row.custom_minimum_size.y = 48 * _hs
	var box := StyleBoxFlat.new()
	box.set_border_width_all(2 if is_current else 1)
	box.set_corner_radius_all(roundi(4 * _hs))
	box.content_margin_left = 10 * _hs
	box.content_margin_right = 10 * _hs
	box.content_margin_top = 4 * _hs
	box.content_margin_bottom = 4 * _hs
	if is_current:
		box.bg_color = Color(0.18, 0.45, 0.70, 0.55)
		box.border_color = Color(0.6, 0.95, 1.0, 0.95)
	elif lock != "":
		box.bg_color = Color(0.04, 0.05, 0.07, 0.70)
		box.border_color = Color(0.30, 0.34, 0.40, 0.45)
	else:
		box.bg_color = Color(0.10, 0.16, 0.24, 0.45)
		box.border_color = Color(0.35, 0.60, 0.80, 0.60)
	row.add_theme_stylebox_override("panel", box)
	row.mouse_filter = Control.MOUSE_FILTER_STOP
	row.gui_input.connect(_on_hangar_row_input.bind(idx))

	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", roundi(8 * _hs))
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(h)
	var text := VBoxContainer.new()
	text.add_theme_constant_override("separation", 0)
	text.alignment = BoxContainer.ALIGNMENT_CENTER
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(text)
	var nm := _new_label(roundi(14 * _hs), Color(1, 1, 1) if is_current else (Color(0.55, 0.58, 0.62) if lock != "" else C_TEXT))
	nm.text = ship_name
	text.add_child(nm)
	if lock != "":
		var lk := _new_label(roundi(11 * _hs), Color(1.0, 0.74, 0.40))
		lk.text = "LOCKED · " + lock.trim_prefix("Locked: ")
		text.add_child(lk)
	if is_current:
		var tag := _new_label(roundi(11 * _hs), Color(0.7, 1.0, 1.0))
		tag.text = "ACTIVE"
		tag.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		tag.size_flags_vertical = Control.SIZE_EXPAND_FILL
		h.add_child(tag)
	return row


func _on_hangar_row_input(event: InputEvent, idx: int) -> void:
	if event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT:
		ship_selected.emit(idx)


func _make_color_swatches(title: String, current_key: String) -> Control:
	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_top", 6)
	var wrap := VBoxContainer.new()
	wrap.add_theme_constant_override("separation", 4)
	pad.add_child(wrap)
	var label := _new_label(roundi(11 * _hs) if _touch else 10, Color(0.7, 0.95, 1.0))
	label.text = title
	wrap.add_child(label)
	var grid := GridContainer.new()
	grid.columns = 5 if _touch else 7
	var gap := roundi(8 * _hs) if _touch else 5
	var swatch := Vector2(40, 40) * _hs if _touch else Vector2(24, 24)
	grid.add_theme_constant_override("h_separation", gap)
	grid.add_theme_constant_override("v_separation", gap)
	wrap.add_child(grid)
	_color_swatch_buttons.clear()
	for palette in Ship.SHIP_PALETTES:
		var selected: bool = String(palette.key) == current_key
		var button := Button.new()
		button.custom_minimum_size = swatch
		button.tooltip_text = String(palette.name)
		button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		var style := StyleBoxFlat.new()
		style.bg_color = palette.swatch
		style.set_border_width_all(3 if selected else 1)
		style.border_color = Color(1, 1, 1, 0.95) if selected else Color(0.35, 0.5, 0.65, 0.8)
		style.set_corner_radius_all(4)
		for state in ["normal", "hover", "pressed", "focus", "disabled"]:
			button.add_theme_stylebox_override(state, style)
		button.set_meta("palette_key", String(palette.key))
		button.set_meta("swatch_color", palette.swatch)
		button.pressed.connect(_on_swatch_pressed.bind(String(palette.key)))
		_color_swatch_buttons.append(button)
		grid.add_child(button)
	var picker := ColorPickerButton.new()
	picker.custom_minimum_size = swatch
	picker.tooltip_text = "Custom colour"
	picker.edit_alpha = false
	picker.color = Ship.color_from_key(current_key)
	picker.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	if current_key.begins_with("#"):
		var picked := StyleBoxFlat.new()
		picked.bg_color = picker.color
		picked.set_border_width_all(3)
		picked.border_color = Color(1, 1, 1, 0.95)
		picked.set_corner_radius_all(4)
		for state in ["normal", "hover", "pressed", "focus"]:
			picker.add_theme_stylebox_override(state, picked)
	picker.color_changed.connect(_on_manual_color)
	_color_picker = picker
	grid.add_child(picker)
	return pad


func _picker_popup_open() -> bool:
	if _color_picker == null or not is_instance_valid(_color_picker):
		return false
	var popup := _color_picker.get_popup()
	return popup != null and popup.visible


func _sync_hangar_color(body_key: String) -> void:
	if body_key == _hangar_color_key:
		return
	_hangar_color_key = body_key
	for button in _color_swatch_buttons:
		if not is_instance_valid(button):
			continue
		var selected: bool = String(button.get_meta("palette_key")) == body_key
		var style := StyleBoxFlat.new()
		style.bg_color = button.get_meta("swatch_color")
		style.set_border_width_all(3 if selected else 1)
		style.border_color = Color(1, 1, 1, 0.95) if selected else Color(0.35, 0.5, 0.65, 0.8)
		style.set_corner_radius_all(4)
		for state in ["normal", "hover", "pressed", "focus", "disabled"]:
			button.add_theme_stylebox_override(state, style)
	if _color_picker == null or not is_instance_valid(_color_picker):
		return
	# Don't write picker.color while the RGB tab is open — that fights the drag.
	if not _picker_popup_open():
		_color_picker.color = Ship.color_from_key(body_key)
	if body_key.begins_with("#"):
		var picked := StyleBoxFlat.new()
		picked.bg_color = Ship.color_from_key(body_key)
		picked.set_border_width_all(3)
		picked.border_color = Color(1, 1, 1, 0.95)
		picked.set_corner_radius_all(4)
		for state in ["normal", "hover", "pressed", "focus"]:
			_color_picker.add_theme_stylebox_override(state, picked)
	else:
		for state in ["normal", "hover", "pressed", "focus"]:
			_color_picker.remove_theme_stylebox_override(state)


func _on_manual_color(c: Color) -> void:
	var key := "#" + c.to_html(false)
	if ship != null and ship.current_body_color() == key:
		return
	ship_color_selected.emit("body", key)


func _on_swatch_pressed(key: String) -> void:
	ship_color_selected.emit("body", key)


func _make_choice_row(title: String, options: Array, current_key: String, callback: Callable) -> Control:
	if _touch:
		return _make_segmented_row(title, options, current_key, callback)
	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_top", 6)
	var wrap := VBoxContainer.new()
	wrap.add_theme_constant_override("separation", 3)
	pad.add_child(wrap)
	var label := _new_label(10, Color(0.7, 0.95, 1.0))
	label.text = title
	wrap.add_child(label)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	wrap.add_child(row)
	for option in options:
		var selected: bool = String(option.key) == current_key
		var button := Button.new()
		button.text = String(option.label)
		button.add_theme_font_size_override("font_size", 9)
		button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.18, 0.45, 0.70, 0.55) if selected else Color(0.10, 0.16, 0.24, 0.40)
		style.border_color = Color(0.6, 0.95, 1.0, 0.95) if selected else Color(0.35, 0.5, 0.65, 0.6)
		style.set_border_width_all(1)
		style.set_corner_radius_all(3)
		for state in ["normal", "hover", "pressed", "focus"]:
			button.add_theme_stylebox_override(state, style)
		button.pressed.connect(callback.bind(String(option.key)))
		row.add_child(button)
	return pad


# Touch: a segmented toggle — joined >=44-tall buttons, the active one filled bright with a
# check mark, the other dark with dim text.
func _make_segmented_row(title: String, options: Array, current_key: String, callback: Callable) -> Control:
	var wrap := VBoxContainer.new()
	wrap.add_theme_constant_override("separation", roundi(3 * _hs))
	var label := _new_label(roundi(11 * _hs), Color(0.7, 0.95, 1.0))
	label.text = title
	wrap.add_child(label)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 0)
	wrap.add_child(row)
	var r := roundi(6 * _hs)
	for i in options.size():
		var option: Dictionary = options[i]
		var selected: bool = String(option.key) == current_key
		var button := Button.new()
		button.text = ("✓ " if selected else "") + String(option.label)
		button.custom_minimum_size = Vector2(92, 44) * _hs
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.focus_mode = Control.FOCUS_NONE
		button.add_theme_font_size_override("font_size", roundi(13 * _hs))
		button.add_theme_color_override("font_color", Color(1, 1, 1) if selected else C_DIM)
		button.add_theme_color_override("font_pressed_color", Color(1, 1, 1))
		button.add_theme_color_override("font_hover_color", Color(1, 1, 1) if selected else C_DIM)
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.22, 0.60, 0.92, 0.90) if selected else Color(0.05, 0.08, 0.12, 0.70)
		style.border_color = Color(0.7, 0.97, 1.0, 1.0) if selected else Color(0.35, 0.5, 0.65, 0.7)
		style.set_border_width_all(2 if selected else 1)
		if i == 0:
			style.corner_radius_top_left = r
			style.corner_radius_bottom_left = r
		if i == options.size() - 1:
			style.corner_radius_top_right = r
			style.corner_radius_bottom_right = r
		for state in ["normal", "hover", "pressed", "focus"]:
			button.add_theme_stylebox_override(state, style)
		button.pressed.connect(callback.bind(String(option.key)))
		row.add_child(button)
	return wrap


func _on_finish_choice(key: String) -> void:
	ship_finish_selected.emit(key)



# Hold-X lock progress (0..1), fed by main each frame; redraws the ring around the crosshair.
func set_lock_progress(f: float) -> void:
	f = clampf(f, 0.0, 1.0)
	if f != _lock_frac:
		_lock_frac = f
		if _lock_ring != null:
			_lock_ring.queue_redraw()


func _draw_lock_ring() -> void:
	if _lock_frac <= 0.0:
		return
	var c: Vector2 = _reticle.position + _reticle.size * 0.5   # centre on the crosshair
	var r := 30.0
	_lock_ring.draw_arc(c, r, 0.0, TAU, 40, Color(0.5, 0.7, 1.0, 0.22), 3.0, true)   # track
	# Filling arc from the top, clockwise — orange (it locks an orange waypoint).
	var col := Color(1.0, 0.72, 0.30, 0.95)
	_lock_ring.draw_arc(c, r, -PI * 0.5, -PI * 0.5 + TAU * _lock_frac, 48, col, 4.0, true)
	if _lock_frac >= 1.0:                                                            # complete flash
		_lock_ring.draw_arc(c, r, 0.0, TAU, 48, Color(1.0, 0.85, 0.4, 1.0), 5.0, true)


# Punch the screen with a colour flash (0..1). The core uses a steady low value for the
# damage-zone pulse and a hard 1.0 for the death kick; it eases back down on its own.
func flash(amount: float, col: Color = Color(1.0, 0.12, 0.10)) -> void:
	_flash_a = maxf(_flash_a, clampf(amount, 0.0, 1.0))
	_flash.color = Color(col.r, col.g, col.b, _flash.color.a)

func refresh() -> void:
	if ship == null:
		return
	# Ease the core flash back toward zero (set fresh each frame by main while in the danger zone).
	_flash_a = maxf(_flash_a - 2.0 * get_process_delta_time(), 0.0)
	_flash.color.a = _flash_a * 0.55
	var weapons_visible := not ship.frozen and not ship.transiting and ship.systems != null \
		and (ship.systems.weapons_target or ship.systems.weapons_fraction > .01)
	_reticle.visible = weapons_visible
	_hitmarker.visible = false # hit confirmation is drawn by fire control itself
	if weapons_visible and combat != null:
		_reticle.set_solution(combat.aim_solution, ship.camera)
	var kick := clampf(combat.hitmarker / 0.18, 0.0, 1.0) if combat != null else 0.0
	_reticle.set_target(1.0 if firing else 0.0, kick)
	# Distance from Earth (the scene origin). Astronomical distances span a huge
	# range, so show AU in-system and switch to ly once it's large.
	_flight_vector.ship = ship
	_flight_vector.show_nose = not _reticle.visible
	_flight_vector.queue_redraw()
	_dist_label.text = "%s  /  %s" % [physical_system_name if ship.newton else origin_name.to_upper(), ship.nearest_name.to_upper() if not ship.nearest_name.is_empty() else "DEEP SPACE"]
	var spd := ship.velocity.length()
	_mode_label.text = str(ship.flight_mode) + "   ·   RELATIVE SPEED" if ship.newton else ""
	_speed_label.text = _fmt_speed(spd)
	_tape_label.visible = true
	if ship.newton:
		var agl: float = planets.ground_altitude_km(ship.nearest_name) if planets != null else INF
		var stellar := planets != null and planets.kind_of(ship.nearest_name) == "star"
		if stellar:
			var radius_distance := ship.anchor_distance_km() if ship.nearest_name == ship.anchor_name else ship.nearest_dist
			agl = radius_distance-ship.nearest_radius
		var outward := -ship.nearest_dir.normalized()
		var vertical := ship.velocity.dot(outward)
		var g := ship.last_newton_g.length() / 0.00980665
		var altitude := "—" if agl == INF else ("%.0f m" % (agl * 1000.0) if absf(agl) < 1.0 else "%.2f km" % agl)
		if stellar:
			_tape_label.text = "PHOTO ALT  %s\nRADIAL  %s %s   /   %.2f g" % [altitude, "OUT" if vertical >= 0 else "IN", _fmt_speed(absf(vertical)), g]
			if vertical < 0 and ship.last_thrust_accel.dot(outward) > 0 \
					and (ship.last_thrust_accel+ship.support_accel+ship.last_newton_g).dot(outward) < 0:
				_tape_label.text += "\nFALLING — THRUST BELOW GRAVITY"
		elif agl < 100.0:
			_tape_label.text = "AGL  %s   /   V/S  %s%s\nGRAVITY  %.2f g" % [altitude, "+" if vertical >= 0.0 else "−", _fmt_speed(absf(vertical)), g]
			if ship.mach_number > .05:
				_tape_label.text += "\nMACH  %.1f   /   AIR LOAD  %s" % [ship.mach_number, _fmt_percent(ship.air_load)]
		else:
			_tape_label.text = "ALT  %s\nRADIAL  %s%s   /   %.2f g" % [altitude, "+" if vertical >= 0.0 else "−", _fmt_speed(absf(vertical)), g]
		if ship.drop_flash > 0.0:
			_mode_label.text = "CRUISE EXIT"
		if ship.time_rate > 1.0:
			_mode_label.text += "   ×%.0f" % ship.time_rate
		if ship.debug_toast != "":
			toast = ship.debug_toast
			toast_t = 2.2
			ship.debug_toast = ""
	else:
		_tape_label.text = ""
	if ship.systems != null:
		if not ship.landing_site.is_empty():
			_mode_label.text = "%s / PAD LOCKED · %s LIFT" % [ship.landing_site, "UP" if ship.touch_active else "SPACE"]
		elif ship.systems.gear_fraction > .01 or ship.systems.gear_target:
			_mode_label.text = "GEAR DOWN" if ship.systems.gear_fraction >= .999 else ("GEAR LOWERING" if ship.systems.gear_target else "GEAR RETRACTING")
			if ship.support_active:
				_mode_label.text += " / SHIP ASSISTANT"
			var lift_g := ship.jet_accel.dot(ship.anchor_off.normalized())/0.00980665
			if absf(lift_g) > .01:
				_tape_label.text += "\nLIFT JETS  %+.2f g" % lift_g
			if ship.newton and ship.terrain != null and ship.anchor_name == ship.nearest_name:
				var body_position := ship.terrain_local(ship.anchor_off, true)
				for site in ship.terrain.facilities:
					var center := SurfaceFacility.to_site(site, body_position)
					if center.length() > .6: continue
					var clearance := center.y
					var pose: Basis = site.transform.basis.inverse()*ship.terrain_basis.inverse()*ship.transform.basis
					for foot in ship.systems.foot_points():
						clearance = minf(clearance,(center+pose*foot).y)
					_tape_label.text += "\nPAD 01  %.0f m CLEAR / %.0f m OFFSET" % [maxf(0,clearance*1000),Vector2(center.x,center.z).length()*1000]
					break
		elif ship.support_active:
			_mode_label.text = "SHIP ASSISTANT / TERRAIN AVOIDANCE"
		elif ship.systems.weapons_target:
			_mode_label.text = "HARDPOINTS READY" if ship.weapons_ready() else "HARDPOINTS DEPLOYING"
		elif ship.systems.weapons_fraction > .01:
			_mode_label.text = "HARDPOINTS STOWING"
	if planets != null and not ship.transiting and not ship.frozen and not planets.stellar_hazard.is_empty():
		var stellar: Dictionary = planets.stellar_hazard
		if int(stellar.level) > 0:
			_tape_label.text += "\n%s  /  %.0f kW/m²" % [stellar.state, float(stellar.flux_w_m2)/1000.0]
	_combat_panel.visible = _edit or firing

	if combat != null:
		# Top-right box keeps just the kill count; the hull bar (top-left) is the HP gauge.
		_combat_label.text = "KILLS  %d" % combat.kills
		var hp_ratio: float = clampf(float(combat.player_hp) / maxf(float(combat.player_max), 1.0), 0.0, 1.0)
		_hull_label.text = "HULL  %d%%    /    PWR · BOOST" % int(100.0 * hp_ratio)
		_hull_fill.size.x = _hull_bar_w * hp_ratio
		# Green when healthy, amber at half, red when critical.
		_hull_fill.color = Color(0.4, 1.0, 0.55).lerp(Color(1.0, 0.35, 0.3), 1.0 - hp_ratio)
		if _energy_fill != null:
			var e_ratio: float = clampf(combat.energy / maxf(combat.e_max, 1.0), 0.0, 1.0)
			_energy_fill.size.x = _energy_bar_w * e_ratio
			# Cyan when charged, dim red when nearly empty (can't fire).
			_energy_fill.color = Color(0.4, 0.85, 1.0).lerp(Color(0.9, 0.4, 0.4), 1.0 - e_ratio)
		if _boost_fill != null:
			var b_ratio: float = clampf(combat.boost_energy / maxf(combat.e_max, 1.0), 0.0, 1.0)
			_boost_fill.size.x = _boost_bar_w * b_ratio
			_boost_fill.color = Color(1.0, 0.65, 0.25).lerp(Color(0.6, 0.4, 0.3), 1.0 - b_ratio)
		# Hitmarker flash (alpha tracks the combat hit timer).
		var hm: float = clampf(combat.hitmarker / 0.18, 0.0, 1.0)
		_hitmarker.modulate = Color(1.0, 0.95, 0.55, hm)

	# Discovery progress + toast.
	if codex != null:
		_codex_label.text = "SURVEY   %d / %d" % [codex.count(), codex.total()]
	if toast_t > 0.0:
		_toast_label.text = toast
		_toast_label.modulate = Color(0.5, 1.0, 0.7, clampf(toast_t, 0.0, 1.0))
	else:
		_toast_label.text = ""
	# Lore card eases IN over its first ~0.4s and OUT over its last second (lore_t is
	# counted down by main from LORE_SHOW). alpha = min(fade-in, fade-out).
	if _lore != null and _lore.visible:
		var fade_in: float = clampf((LORE_SHOW - lore_t) / 0.4, 0.0, 1.0)
		_lore.modulate.a = minf(fade_in, clampf(lore_t, 0.0, 1.0))
		if lore_t <= 0.0:
			_lore.visible = false

	if planets != null and planets.nearest_name != "":
		var near_au := planets.nearest_dist * AU_PER_UNIT
		_near_label.text = "%s   ·   %s" % [planets.nearest_name, _fmt_dist(near_au)]
		# Offer the Details button when you're close to that body.
		var close := planets.nearest_dist < _detail_range
		details_button.visible = close
		if close:
			details_button.text = "[G]  Inspect body"
	elif details_button != null:
		details_button.visible = false


func _fmt_speed(km_s: float) -> String:
	if km_s < 1.0:
		return "%.0f m/s" % (km_s * 1000.0)
	if km_s < 100.0:
		return "%.2f km/s" % km_s
	return "%.1f km/s" % km_s


# AU when in-system, light-years when far enough that AU stops reading well.
func _fmt_dist(au: float) -> String:
	if au >= 1000.0:
		return "%.3f ly" % (au * LY_PER_AU)
	if au < 0.01:
		return "%.0f km" % (au / AU_PER_UNIT)
	return "%.3f AU" % au


# A styled standalone label (soft drop-shadow + thin outline for legibility over
# the busy starfield). Not parented — the caller positions/adds it.
func _new_label(font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", font_size)
	# White fill so the shader's luminance test treats glyphs as "fill" (the hue
	# comes from the gradient material). Thin dark outline + soft shadow keep it
	# readable over the starfield; the shader leaves those dark passes alone.
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.55))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.45))
	label.add_theme_constant_override("outline_size", 2)
	label.material = null
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


# A per-label ShaderMaterial: a bright highlight up top fading to `color` at the
# bottom, spanning roughly one glyph's height — a lit-metal sheen in the label hue.
func _grad_material(color: Color, font_size: int) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = _text_shader
	m.set_shader_parameter("top_color", color.lightened(0.55))
	m.set_shader_parameter("bottom_color", color.darkened(0.05))
	m.set_shader_parameter("grad_height", float(font_size) * 1.2)
	return m

# A styled label placed at an absolute canvas position.
func _make_label(pos: Vector2, font_size: int, color := C_TEXT) -> Label:
	var label := _new_label(font_size, color)
	label.position = pos
	_canvas.add_child(label)
	return label

# A styled line added into a panel's VBox body.
func _add_line(body: VBoxContainer, font_size: int, color: Color) -> Label:
	var label := _new_label(font_size, color)
	body.add_child(label)
	return label


# One decimal from 1% up; below that one significant figure, so a real load never reads 0.0%.
static func _fmt_percent(fraction: float) -> String:
	var pct := fraction*100.0
	if pct <= 0.0: return "0%"
	if pct >= 1.0: return "%.1f%%" % pct
	return ("%." + str(clampi(ceili(-log(pct)/log(10.0)), 1, 9)) + "f%%") % pct
