class_name HUD
extends Node3D
# Heads-up display: code-spawned controls on a CanvasLayer, styled for a clean
# "space game" look — small text, soft drop-shadows, and frosted-glass panels
# (linear-gradient backdrops + glowing edge borders) instead of bare labels.
#
# Layout is authored against the 1280x720 reference (project stretch = canvas_items),
# so it scales to fullscreen. refresh() is called by main.gd each frame.

# Scale conversions for the readouts. Must match Ephemeris.AU_TO_UNITS (1 unit = 1 km).
const AU_PER_UNIT := 1.0 / 149597870.7
const LY_PER_AU := 1.0 / 63241.077

# --- palette -----------------------------------------------------------------
const C_ACCENT := Color(0.45, 0.85, 1.0)     # cyan UI accent / edges
const C_TEXT := Color(0.84, 0.92, 1.0)       # primary readout text
const C_DIM := Color(0.55, 0.70, 0.88)       # secondary / labels
const C_GREEN := Color(0.55, 1.0, 0.80)      # discovery / scan
const C_WARN := Color(1.0, 0.45, 0.45)       # boss / danger

# Shared right margin (1280 reference width − 16px). The combat readout and the
# MAP/CODEX/?/⚙ bar below it both align their right edge here.
const RIGHT_EDGE := 1264.0

# Metallic gradient shader for glyph fills (see hud_text.gdshader). Each label gets
# its own ShaderMaterial so the gradient hue/height can match that label.
var _text_shader := load("res://shaders/hud_text.gdshader") as Shader

signal ship_selected(index: int)   # emitted when a hangar row is clicked
signal ship_color_selected(part: String, key: String)
signal ship_finish_selected(key: String)
signal open_teleport_map()   # clicked the dock's "TELEPORT NETWORK" button -> open the map

var ship: Ship
var planets: PlanetSystem
var combat: Combat           # for HP / kills readout
var coins := 0               # player currency, shown beside KILLS (set by main)
@onready var codex := Codex   # autoload; discovery progress
var origin_name := "Earth"   # what the distance readout measures from (per system)

# Scan/discovery state, fed by main each frame.
var scan_progress := 0.0     # 0..1 while scanning the nearest body
var scan_name := ""          # which body is being scanned
var scan_hint := ""          # "hold V to scan X" prompt when in range
var toast := ""              # transient "✓ discovered" message
var toast_t := 0.0

var _canvas: CanvasLayer
var _dist_label: Label
var _speed_label: Label
var _tape_label: Label
var _near_label: Label
var _prompt: Label    # "Press F to dock" near the station
var _menu: Label      # centered overlay text (wormhole-transit countdown)
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
var _combat_label: Label
var _boss_label: Label
var _hull_label: Label       # "HULL  170 / 220" sitting over the hull bar
var _hull_fill: ColorRect    # the coloured fill of the player hull bar (top-left)
var _hull_bar_w := 0.0       # inner (fillable) width of the hull bar
var _energy_fill: ColorRect  # weapon-energy bar fill (shooting)
var _energy_bar_w := 0.0
var _boost_fill: ColorRect   # boost-energy bar fill (Shift)
var _boost_bar_w := 0.0
var _boss_bar: Control       # red boss HP bar (top-center, shown only while a boss lives)
var _boss_fill: ColorRect
var _boss_bar_w := 0.0
var _reticle: Control   # dynamic crosshair (crosshair.gd)
const RETICLE_AIM_DIST := 800.0   # how far down the nose the crosshair marks the shot line
var _lock_ring: Control # radial progress arc drawn around the crosshair while holding X
var _lock_frac := 0.0   # 0..1 hold progress (set by main from the X-hold timer)
var _capture_ring: Control  # big centred radial that fills while capturing a body
var _capture_label: Label   # "◎ CAPTURING …" centred under the ring
var _guardian_label: Label  # guardian-fight banner: "WAVE 2/3 · capture locked/ready"
var firing := false     # set by main each frame — blooms the crosshair while held
var _hitmarker: Label   # flashes on the crosshair when a shot lands
var _codex_label: Label # "Discovered N/M"
var _objective_label: Label # "→ <star> <dist>" — the Survey guide line
var _scan_label: Label  # scan prompt / progress (center-lower)
var _toast_label: Label # "✓ X discovered" pop
var _controls: PanelContainer   # the controls cheat-sheet menu (toggled by ?)
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
const LAYOUT_PATH := "user://hud_layout.cfg"
# The shipped DEFAULT layout (the hand-tuned "best" arrangement). Used as each
# widget's built-in position/scale, so fresh installs and Reset land here. A saved
# user layout still overrides it.
const DEFAULT_LAYOUT := {
	"nav": Vector2(16, 14), "combat": Vector2(10.66, 628.67), "hull": Vector2(15.33, 98.67),
	"teleport": Vector2(1088, 674), "buttons": Vector2(8.67, 680.0),
	"details": Vector2(1088, 636), "radar": Vector2(1129.33, 11.33),
	"cancel_nav": Vector2(12, 602),
}
const DEFAULT_SCALE := {
	"nav": 0.76, "combat": 0.7, "hull": 0.94, "teleport": 1.0,
	"buttons": 0.76, "details": 1.0, "radar": 0.76, "cancel_nav": 0.7,
}
var ship_ref: Ship                 # set by main, used to free/recapture the cursor in edit mode
var _movable: Array = []           # [{ id, node, def }]
var _saved := {}                   # id -> Vector2 position loaded from disk
var _saved_scale := {}             # id -> float scale loaded from disk
var _edit := false
var _drag: Control = null          # widget currently being dragged
var _drag_grab := Vector2.ZERO     # mouse offset within the dragged widget
var _btn_bar: Control              # container wrapping the MAP/CODEX/?/⚙ buttons
var _edit_ui: Control              # dim scrim + banner + Save/Reset/Done toolbar
var _edit_toolbar: Control         # the toolbar rect (clicks here aren't drags)


func _ready() -> void:
	# ALWAYS so the layout editor still receives input while the game is paused.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_canvas = CanvasLayer.new()
	add_child(_canvas)
	_load_layout()

	# Top-left flight readout, grouped in one frosted-glass panel.
	var nav := _glass_panel(Vector2(16, 14), 198.0, C_ACCENT)
	_canvas.add_child(nav.panel)
	_track("nav", nav.panel)
	_dist_label = _add_line(nav.body, 14, C_TEXT)
	_speed_label = _add_line(nav.body, 10, C_DIM)
	_tape_label = _add_line(nav.body, 10, C_DIM)
	_near_label = _add_line(nav.body, 11, C_TEXT)
	_codex_label = _add_line(nav.body, 10, C_GREEN)
	_objective_label = _add_line(nav.body, 11, C_ACCENT)   # Survey guide: next unclaimed star

	# Scan prompt/progress (center, below the crosshair) + discovery toast (center).
	# Declutter: feedback moves OFF the centre to the free right side (x ≈ 980), left-aligned,
	# so the play area around the crosshair stays clean. (A proper right-side rail/box is next.)
	var rx := SCREEN.x - 300.0
	_scan_label = _make_label(Vector2(rx, 214), 12, C_GREEN)
	_scan_label.size = Vector2(288, 22)
	_scan_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_toast_label = _make_label(Vector2(rx, 150), 14, C_GREEN)
	_toast_label.size = Vector2(288, 60)
	_toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_toast_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_toast_label.modulate.a = 0.0

	# Contextual prompt ("Press F to …") — right side, under the toast, left-aligned.
	_prompt = _make_label(Vector2(rx, 244), 13, C_TEXT)
	_prompt.size = Vector2(288, 44)
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_prompt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	# Centered overlay text — used for the wormhole-transit countdown.
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
	_tip = _make_label(Vector2(0, 110), 11, Color(1.0, 0.97, 0.9))
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
	_combat_label = _add_line(cstat.body, 12, C_TEXT)
	_combat_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_combat_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	# Player hull bar (top-left, under the nav panel). A real coloured bar; the
	# top-right box keeps just the kill count. Draggable/resizable in the HUD editor.
	_build_hull_bar(_canvas)

	# Boss banner (top-center) — only shows while Vortex is alive — with a red HP bar.
	_boss_label = _make_label(Vector2(0, 64), 13, C_WARN)
	_boss_label.size = Vector2(1280, 24)
	_boss_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_build_boss_bar(_canvas)

	# Guardian fight banner (top-centre, under the boss bar): always-visible wave count +
	# capture status during a guardian fight, so you can see "WAVE 2/3" and whether you can grab it.
	_guardian_label = _make_label(Vector2(0, 102), 15, Color(1.0, 0.55, 0.4))
	_guardian_label.size = Vector2(1280, 24)
	_guardian_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_guardian_label.visible = false

	# Dynamic aiming reticle (custom-drawn): blooms while firing, kicks on a hit.
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

	# Capture ring — a big, centred, semi-transparent radial that FILLS while you survey/capture
	# a body, so the player sees and enjoys the progress. Driven from the scan block each frame.
	_capture_ring = Control.new()
	_capture_ring.set_anchors_preset(Control.PRESET_FULL_RECT)
	_capture_ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_capture_ring.draw.connect(_draw_capture_ring)
	_canvas.add_child(_capture_ring)
	_capture_label = _make_label(Vector2(0, 446), 16, C_GREEN)
	_capture_label.size = Vector2(1280, 24)
	_capture_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_capture_label.visible = false

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
	details_button.size = Vector2(176, 32)
	details_button.focus_mode = Control.FOCUS_NONE
	details_button.add_theme_font_size_override("font_size", 12)
	details_button.add_theme_color_override("font_color", C_TEXT)
	details_button.add_theme_stylebox_override("normal", _metal_box(Color(0.55, 0.85, 1.0), 0.5))
	details_button.add_theme_stylebox_override("hover", _metal_box(Color(0.7, 0.95, 1.0), 0.9))
	details_button.add_theme_stylebox_override("pressed", _metal_box(Color(0.8, 1.0, 1.0), 1.0))
	details_button.visible = false
	_canvas.add_child(details_button)
	_track("details", details_button)

	_build_edit_ui(_canvas)


# Squared, brushed-metal, cyan-glow sci-fi button: "⌖ TELEPORT EARTH".
func _build_teleport_button(canvas: CanvasLayer) -> void:
	teleport_button = Button.new()
	teleport_button.text = "⌖  TELEPORT EARTH"
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
	_track("teleport", teleport_button)


# Bottom-centre "TELEPORT NETWORK" button — appears while docked at a platform (set_hangar
# toggles it), opens the platform fast-travel console. Disabled-looking when nothing's unlocked.
func _build_teleport_net_button(canvas: CanvasLayer) -> void:
	_tp_net_button = Button.new()
	_tp_net_button.text = "⌖  TELEPORT NETWORK"
	_tp_net_button.size = Vector2(268, 36)
	_tp_net_button.position = Vector2(640 - 134, 660)   # design-space bottom-centre
	_tp_net_button.focus_mode = Control.FOCUS_NONE
	_tp_net_button.add_theme_font_size_override("font_size", 13)
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
	sb.set_corner_radius_all(3)
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
	_hull_label = _new_label(10, C_DIM)
	_hull_label.position = Vector2(1, 0)
	holder.add_child(_hull_label)
	var bar := _build_bar(184, 12, C_GREEN)
	bar.root.position = Vector2(0, 14)
	holder.add_child(bar.root)
	_hull_fill = bar.fill
	_hull_bar_w = bar.inner_w
	# Weapon-energy bar (thin, cyan) — drained by shooting.
	var ebar := _build_bar(184, 6, Color(0.4, 0.85, 1.0))
	ebar.root.position = Vector2(0, 27)
	holder.add_child(ebar.root)
	_energy_fill = ebar.fill
	_energy_bar_w = ebar.inner_w
	# Boost-energy bar (thin, orange) — drained by Shift boost.
	var bbar := _build_bar(184, 6, Color(1.0, 0.65, 0.25))
	bbar.root.position = Vector2(0, 35)
	holder.add_child(bbar.root)
	_boost_fill = bbar.fill
	_boost_bar_w = bbar.inner_w
	holder.size = Vector2(184, 42)
	canvas.add_child(holder)
	_track("hull", holder)


# Boss HP bar (top-center) — a wide red bar under the boss banner.
func _build_boss_bar(canvas: CanvasLayer) -> void:
	_boss_bar = Control.new()
	_boss_bar.position = Vector2(640 - 170, 84)
	_boss_bar.size = Vector2(340, 12)
	_boss_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bar := _build_bar(340, 12, C_WARN)
	_boss_bar.add_child(bar.root)
	_boss_fill = bar.fill
	_boss_bar_w = bar.inner_w
	_boss_bar.visible = false
	canvas.add_child(_boss_bar)


# Styled top-right control bar: open the map / codex / controls / settings by click.
# Tiny bold instruction line, bottom-centre — a quick reminder of the core verbs.
func _build_guide(canvas: CanvasLayer) -> void:
	var g := Label.new()
	g.text = "W warp · Shift boost · grab ⚡ cells & ✦ probes to refuel · M map · G claim coins · L-click fire / R-click laser"
	g.position = Vector2(0, SCREEN.y - 22)
	g.size = Vector2(SCREEN.x, 18)
	g.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	g.add_theme_font_size_override("font_size", 11)
	g.add_theme_color_override("font_color", Color(0.78, 0.86, 1.0, 0.85))
	g.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	g.add_theme_constant_override("shadow_offset_y", 1)
	g.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(g)


func _build_button_bar(canvas: CanvasLayer) -> void:
	# The four buttons live inside one Control container laid out left-to-right, so
	# the whole bar drags as a single unit. The container's right edge sits at
	# RIGHT_EDGE so it lines up with the combat readout above it.
	var gap := 6.0
	var w_nav := 64.0
	var w_map := 66.0
	var w_log := 28.0          # quest log: a small ✦ icon button (tooltip explains it)
	var w_codex := 74.0
	var w_icon := 28.0
	var bar_w := w_nav + gap + w_map + gap + w_log + gap + w_codex + gap + w_icon + gap + w_icon
	_btn_bar = Control.new()
	_btn_bar.position = Vector2(RIGHT_EDGE - bar_w, 80.0)
	_btn_bar.size = Vector2(bar_w, 26)
	canvas.add_child(_btn_bar)

	var x_nav := 0.0
	var x_map := x_nav + w_nav + gap
	var x_log := x_map + w_map + gap
	var x_codex := x_log + w_log + gap
	var x_controls := x_codex + w_codex + gap
	var x_settings := x_controls + w_icon + gap
	nav_button = _icon_button(_btn_bar, "⊘ NAV", Vector2(x_nav, 0), w_nav, C_WARN)
	map_button = _icon_button(_btn_bar, "◎ MAP", Vector2(x_map, 0), w_map, C_ACCENT)
	log_button = _icon_button(_btn_bar, "✦", Vector2(x_log, 0), w_log, Color(1.0, 0.78, 0.35))
	log_button.tooltip_text = "Mission Log (J)"
	codex_button = _icon_button(_btn_bar, "▤ CODEX", Vector2(x_codex, 0), w_codex, C_GREEN)
	controls_button = _icon_button(_btn_bar, "?", Vector2(x_controls, 0), w_icon, Color(0.8, 0.85, 1.0))
	settings_button = _icon_button(_btn_bar, "⚙", Vector2(x_settings, 0), w_icon, Color(0.8, 0.85, 1.0))
	controls_button.pressed.connect(toggle_controls)
	_track("buttons", _btn_bar)

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
		nav_button.text = "▶ NAV" if stopped else "⊘ NAV"

# Show/hide the Cancel-Nav button (main calls this while a locked waypoint is active).
func set_cancel_nav_visible(v: bool) -> void:
	if cancel_nav_button != null:
		cancel_nav_button.visible = v

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
	var def_scl := node.scale
	if DEFAULT_SCALE.has(id):
		var ds: float = DEFAULT_SCALE[id]
		def_scl = Vector2(ds, ds)
	node.position = def_pos
	node.scale = def_scl
	_movable.append({ "id": id, "node": node, "def": def_pos, "defs": def_scl })
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
	if cfg.load(LAYOUT_PATH) != OK:
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
	cfg.save(LAYOUT_PATH)

func _reset_layout() -> void:
	for item in _movable:
		item.node.position = item.def
		item.node.scale = item.defs
	_saved.clear()
	_saved_scale.clear()
	var cfg := ConfigFile.new()   # write an empty file so the reset persists
	cfg.save(LAYOUT_PATH)


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
		_drag.position = Vector2(
			clampf(mpos.x - _drag_grab.x, 0.0, SCREEN.x - sz.x),
			clampf(mpos.y - _drag_grab.y, 0.0, SCREEN.y - sz.y))
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
	sb.border_color = edge                         # cyan edge line (the "glow" rim)
	sb.set_corner_radius_all(4)                    # softly rounded
	sb.set_content_margin_all(7)
	sb.shadow_color = Color(edge.r, edge.g, edge.b, 0.45 * glow)
	sb.shadow_size = int(9 * glow)                 # cyan halo glow around the box
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
	["W hold", "Spool warp (open space)"],
	["Num Lk", "Auto-cruise toggle"],
	["L-Click", "Fire weapons"],
	["T / RMB", "Free-look (hold)"],
	["Tab", "Cycle target"],
	["X hold", "Lock nav target"],
	["W + C", "Drift-flip leap (escape)"],
	["N", "Stop / resume nav"],
	["V", "Scan / capture"],
	["G", "Planet details"],
	["L", "Codex log"],
	["J", "Mission log"],
	["M", "Star map"],
	["F", "Dock / wormhole"],
	["1–4", "Swap ship (docked)"],
	["H", "Teleport home"],
	["F11", "Fullscreen"],
	["Esc", "Release cursor / back"],
]

# System explainers shown under the controls grid in the ? panel — always available, so a
# player past the beginner tips can still look up exactly how each mechanic works.
const GUIDE := [
	["TAB TARGETING",
	 "Aim down the crosshair and press Tab to lock the object your aim ray passes nearest to. Tab steps through the up-to-4 closest (1st → 2nd → 3rd → 4th → loop); move the cursor to re-rank. Unscanned objects read \"Unknown\" until you scan them. Hold X for 1s to LOCK the target as an orange waypoint — it sticks through aim changes and further Tabs until you press ✖ Cancel Nav."],
	["WORMHOLES",
	 "Glowing rings are wormholes to neighbouring systems. Fly close and press F to dive through — a dark tunnel carries you across the light-years (longer hops take longer). Known lanes show on the map (M) and the corner radar; the network links every system within a few hops of home."],
	["TELEPORT  (H)",
	 "Press H anywhere for an emergency jump straight home to Earth: a light-ball wraps the ship, shrinks to a bead, and you arrive. It is the rare, theatrical exception — ordinary travel between stars is always flown through wormholes."],
	["PLATFORMS & STATIONS",
	 "Every charted system has a dockable platform; Earth has the home station. Press F nearby to dock, then swap among the four authored ships (1–4) and open the TELEPORT NETWORK. From the network you can jump to any platform you have already reached and arrive right beside it. All platforms share the same ship roster and the same network."],
	["WARP & FLIGHT",
	 "WASD thrusts, Shift boosts (drains the boost bar), Q/E roll, Space/Ctrl climb and dive. Hold W in open space to spool the warp drive and cross light-years; near stars and planets you are held to sublight. Num Lock toggles hands-free auto-cruise. Hold W and tap C for a drift-flip LEAP — a quick boost with a slow, wide cinematic barrel roll (A/D picks the side). The leap punches through a star/planet slow-zone, so it's how you break free when gravity is holding you in."],
	["COMBAT & DISCOVERY",
	 "Left-click fires instant ray-bullets down the crosshair (opening fire eases you to combat speed). Press V near a body to scan/capture it — that fills the Codex (L), the details panel (G), and completes its survey mission. A guarded body's boss is SHIELDED until you clear its summoned swarm — kill the minions first, then burn the boss down to capture the body."],
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

	# System explainers: how targeting / wormholes / teleport / platforms / combat work.
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


# Guardian-fight banner: pass the wave/capture text and whether the body is capturable now.
# Empty text hides it. Green when capture is ready, hot-amber while the waves are locking it.
func set_guardian(text: String, ready := false) -> void:
	if _guardian_label == null:
		return
	_guardian_label.visible = text != ""
	_guardian_label.text = text
	_guardian_label.add_theme_color_override("font_color",
		Color(0.5, 1.0, 0.65) if ready else Color(1.0, 0.55, 0.4))

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


# Outer frame stylebox: transparent fill (so a gradient TextureRect shows through),
# glowing cyan edge + soft halo. Shared by the hangar and controls panels.
func _frame_box(edge: Color) -> StyleBoxFlat:
	var frame := StyleBoxFlat.new()
	frame.bg_color = Color(0, 0, 0, 0)
	frame.set_border_width_all(2)
	frame.border_color = Color(edge.r, edge.g, edge.b, 0.9)
	frame.set_corner_radius_all(6)
	frame.shadow_color = Color(edge.r, edge.g, edge.b, 0.35)
	frame.shadow_size = 10
	return frame


# A frosted-glass info panel: gradient backdrop + glowing edge + a VBox body you
# pour styled lines into. Returns { panel, body }.
func _glass_panel(pos: Vector2, min_w: float, edge: Color) -> Dictionary:
	var panel := PanelContainer.new()
	panel.position = pos
	panel.custom_minimum_size = Vector2(min_w, 0)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel", _frame_box(edge))

	var bg := TextureRect.new()
	bg.texture = _linear_gradient(
		Color(0.06, 0.11, 0.18, 0.82), Color(0.01, 0.02, 0.05, 0.82))
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
	col.add_theme_constant_override("separation", 2)
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
	var sig := ("%d|%s|%s|%s|%s|%s" % [current, station, ",".join(names), body_key, finish, tp_sig]) if open else ""
	if sig == _hangar_sig:
		return
	_hangar_sig = sig
	_hangar.visible = open
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
	for c in _hangar_rows.get_children():
		c.queue_free()
	for i in names.size():
		_hangar_rows.add_child(_make_hangar_row(names[i], i, i == current))
	if has_color:
		_hangar_rows.add_child(_make_color_swatches("SHIP COLOUR", body_key))
	if has_finish:
		_hangar_rows.add_child(_make_choice_row("FINISH",
			[{"key": "metallic", "label": "METALLIC"}, {"key": "glassy", "label": "GLASSY"}],
			finish, _on_finish_choice))
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

	var nm := _new_label(13, Color(1, 1, 1) if is_current else C_TEXT)
	nm.text = ship_name
	nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(nm)

	var key := _new_label(11, Color(0.7, 1.0, 1.0) if is_current else C_DIM)
	key.text = ("◄ %d" % (idx + 1)) if is_current else str(idx + 1)
	h.add_child(key)

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
	var label := _new_label(10, Color(0.7, 0.95, 1.0))
	label.text = title
	wrap.add_child(label)
	var grid := GridContainer.new()
	grid.columns = 7
	grid.add_theme_constant_override("h_separation", 5)
	grid.add_theme_constant_override("v_separation", 5)
	wrap.add_child(grid)
	for palette in Ship.SHIP_PALETTES:
		var selected: bool = String(palette.key) == current_key
		var button := Button.new()
		button.custom_minimum_size = Vector2(24, 24)
		button.tooltip_text = String(palette.name)
		button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		var style := StyleBoxFlat.new()
		style.bg_color = palette.swatch
		style.set_border_width_all(3 if selected else 1)
		style.border_color = Color(1, 1, 1, 0.95) if selected else Color(0.35, 0.5, 0.65, 0.8)
		style.set_corner_radius_all(4)
		for state in ["normal", "hover", "pressed", "focus", "disabled"]:
			button.add_theme_stylebox_override(state, style)
		button.pressed.connect(_on_swatch_pressed.bind(String(palette.key)))
		grid.add_child(button)
	return pad


func _on_swatch_pressed(key: String) -> void:
	ship_color_selected.emit("body", key)


func _make_choice_row(title: String, options: Array, current_key: String, callback: Callable) -> Control:
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


# Big centred capture ring: a soft semi-transparent disc with a filling arc + breathing glow,
# so surveying a world feels like a ritual you can watch. Driven by scan_progress each frame.
func _draw_capture_ring() -> void:
	if scan_progress <= 0.0 or scan_name == "":
		return
	var c := Vector2(640.0, 360.0)
	var f := clampf(scan_progress, 0.0, 1.0)
	var r := 84.0
	var t := Time.get_ticks_msec() * 0.001
	var pulse := 0.5 + 0.5 * sin(t * 4.0)
	# Soft translucent disc — the "circle" the player sees fill with light.
	_capture_ring.draw_circle(c, r, Color(0.20, 1.0, 0.75, 0.06 + 0.05 * pulse))
	_capture_ring.draw_circle(c, r * f, Color(0.30, 1.0, 0.80, 0.10 + 0.06 * pulse))   # inner fill grows
	# Faint full track, then the bright filling arc from the top (clockwise).
	_capture_ring.draw_arc(c, r, 0.0, TAU, 72, Color(0.5, 1.0, 0.8, 0.22), 3.0, true)
	_capture_ring.draw_arc(c, r, -PI * 0.5, -PI * 0.5 + TAU * f, 72, Color(0.6, 1.0, 0.85, 0.95), 5.0, true)
	# Spinning lead dot riding the arc tip, and a complete-flash when full.
	var tip := c + Vector2(cos(-PI * 0.5 + TAU * f), sin(-PI * 0.5 + TAU * f)) * r
	_capture_ring.draw_circle(tip, 4.0 + 2.0 * pulse, Color(0.85, 1.0, 0.92, 0.9))
	if f >= 1.0:
		_capture_ring.draw_arc(c, r, 0.0, TAU, 72, Color(0.9, 1.0, 0.95, 1.0), 7.0, true)


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
	# Hide the crosshair when Vela is hypersonic — combat is disabled then.
	var hyper := ship.is_hypersonic()
	var armed := ship.can_fire and not hyper   # utility hulls show no crosshair
	_reticle.visible = armed
	_hitmarker.visible = armed
	# Pin the crosshair to where the NOSE points (bullets fly along the ship's forward).
	# The chase camera lags + sways, so a fixed-centre reticle drifts off the true shot
	# line — projecting the nose ray each frame keeps the crosshair exactly on aim.
	if armed and ship.camera != null:
		var cam: Camera3D = ship.camera
		var aim: Vector3 = (-ship.transform.basis.z) * RETICLE_AIM_DIST   # ship is at render origin
		if (cam.global_transform.affine_inverse() * aim).z < 0.0:         # aim is in front of cam
			var sp: Vector2 = cam.unproject_position(aim)
			_reticle.position = sp - _reticle.size * 0.5
			_hitmarker.position = Vector2(sp.x - 640.0, sp.y - 18.0)      # 1280-wide centred label
	# Feed the dynamic crosshair: bloom while firing, kick on a fresh hit.
	var kick := clampf(combat.hitmarker / 0.18, 0.0, 1.0) if combat != null else 0.0
	_reticle.set_target(1.0 if firing else 0.0, kick)
	# Distance from Earth (the scene origin). Astronomical distances span a huge
	# range, so show AU in-system and switch to ly once it's large.
	var dist_au := float(ship.to_body("Earth").length()) * AU_PER_UNIT
	# On the galactic voyage the authoritative distance is the core scanner, not the flown
	# distance (which
	# only creeps at her ordinary warp while the galaxy looms the real 26,000 ly). Once she's made
	# any progress toward the core, show travelled = total − remaining; flying back out winds it to
	# ~0, and a fresh system arrival resets remaining to total, handing the readout back to it.
	if ship.has_galactic_drive and (ship.core_total_ly - ship.core_dist_ly) > 0.5:
		dist_au = (ship.core_total_ly - ship.core_dist_ly) / LY_PER_AU
	_dist_label.text = "From %s   %s" % [origin_name, _fmt_dist(dist_au)]
	var spd := ship.velocity.length()
	var spd_ly := spd * AU_PER_UNIT * LY_PER_AU
	if _tape_label != null:
		_tape_label.visible = ship.newton
	if ship.newton:
		# No nearby body: fall back to Earth, which is what the origin always meant.
		var to_earth: Vector3 = ship.to_body("Earth")
		var inward := to_earth.normalized() if to_earth.length_squared() > 0.001 else Vector3.FORWARD
		var dist := to_earth.length()
		var rad := Ephemeris.EARTH_RADIUS_KM
		var mu := Ephemeris.GM_EARTH
		var who := "Earth"
		if planets != null and ship.nearest_name != "" and ship.nearest_dir.length_squared() > 0.0001 \
				and ship.nearest_dist > 0.001:
			inward = ship.nearest_dir.normalized()
			dist = ship.nearest_dist
			who = ship.nearest_name
			rad = planets.nearest_radius
			mu = Ephemeris.gm(who)
			if mu <= 0.0:
				mu = Ephemeris.GM_EARTH
		var alt := dist - rad
		var zone := Ephemeris.flight_zone(who, dist)
		var mode := str(ship.flight_mode)
		var tag := "  · %s" % zone
		if ship.drop_flash > 0.0:
			tag += "  · DROP"
			mode = "DROP"
		else:
			tag += "  · %s" % mode
		if dist > 0.001 and spd > 0.001:
			var radial := -ship.velocity.dot(inward)   # + = away from that body
			var nose := -ship.transform.basis.z
			var vdir := ship.velocity / spd
			if radial > 0.001:
				tag += "  · out %s %s" % [_fmt_speed(radial), who]
			elif radial < -0.001:
				tag += "  · in %s %s" % [_fmt_speed(-radial), who]
			if nose.dot(vdir) < 0.45:
				tag += " leftover"
		if ship.dev_speed:
			tag += "  DEV"
			if FlightMode.dev_fast_air:
				tag += "·FASTAIR"
			if FlightMode.dev_no_death:
				tag += "·NODEATH"
		if ship.time_rate > 1.0:
			tag += "  ×%.0f" % ship.time_rate
		if ship.drop_flash > 0.0:
			_speed_label.modulate = Color(1.35, 1.35, 1.25)
		else:
			_speed_label.modulate = Color.WHITE
		_speed_label.text = "Speed   %s%s" % [_fmt_speed(spd), tag]
		var v_c := sqrt(mu / dist) if dist > 0.001 else 0.0
		var v_e := sqrt(2.0 * mu / dist) if dist > 0.001 else 0.0
		_tape_label.visible = true
		var extra := "\nZone    %s" % zone
		extra += "\nMode    %s" % mode
		if alt >= 0.0:
			extra += "  ·  skin %+.0f km" % alt
		else:
			extra += "  ·  inside %.0f km" % (-alt)
		var air_top := Ephemeris.atmo_top_km(who)
		if air_top > 0.0:
			extra += "\nAir     %.0f km top" % air_top
		var g_mag := ship.last_newton_g.length() / 9.80665e-3
		var vspeed := -ship.velocity.dot(inward) if dist > 0.001 else 0.0
		extra += "\nG       %.2f g  ·  Vspd %s%s" % [
			g_mag, "+" if vspeed >= 0.0 else "-", _fmt_speed(absf(vspeed))]
		if zone == FlightMode.AIR:
			extra += "\nMach    %.2f  ·  Load %.0f%%" % [
				ship.mach_number, ship.air_load * 100.0]
		if planets != null:
			if ship.newton and planets.cook_n > 0:
				extra += "\nCook    %d  · mesh %d  · sky %d" % [
					planets.cook_n, planets.cook_mesh_n, planets.cook_sky_n]
				if planets.cook_look != "":
					extra += "\nLook    %s" % planets.cook_look
			if who == "Earth":
				var mrel: Vector3 = planets.rel_of("Moon")
				if mrel.length() > 1.0:
					extra += "\nMoon    %.0f km" % mrel.length()
			var srel: Vector3 = planets.rel_of("Sun")
			if srel.length() > 1.0:
				extra += "\nSun     %.3f AU" % (srel.length() / Ephemeris.AU_TO_UNITS)
		var agl: float = planets.ground_altitude_km(who) if planets != null else alt
		var altitude_text := "%.0f m" % (agl * 1000.0) if absf(agl) < 1.0 else "%.2f km" % agl
		_tape_label.text = "AGL     %s  %s\nNeed    %s circle  ·  %s esc%s" % [
			altitude_text, who, _fmt_speed(v_c), _fmt_speed(v_e), extra]
		if ship.debug_toast != "":
			toast = ship.debug_toast
			toast_t = 2.2
			ship.debug_toast = ""
	elif ship.galactic_cruising():
		# On the galactic drive the REAL speed is the looming pace (ly/s the core distance is
		# burning down), not her tiny translation velocity — that's why the readout looked like a
		# lie. Show the actual rate so it matches the distance flying past each second.
		_speed_label.text = "Speed   %.1f ly/s  ⚡GALACTIC" % absf(ship.galactic_loom_rate())
	elif spd_ly >= 0.001:
		_speed_label.text = "Speed   %.3f ly/s  ⚡FTL" % spd_ly
	elif ship.warp > 1.0:
		# Sublight cruise: tell the pilot whether FTL is available yet.
		var tag := "  ▲ FTL READY" if ship.warp_ready() else "  · sublight (clear the star)"
		_speed_label.text = "Speed   %.0f u/s%s" % [spd, tag]
	else:
		_speed_label.text = "Speed   %.0f u/s" % spd

	if combat != null:
		# Top-right box keeps just the kill count; the hull bar (top-left) is the HP gauge.
		_combat_label.text = "KILLS  %d      ◈ %d" % [combat.kills, coins]
		var hp_ratio: float = clampf(float(combat.player_hp) / maxf(float(combat.player_max), 1.0), 0.0, 1.0)
		_hull_label.text = "HULL   %d / %d" % [combat.player_hp, combat.player_max]
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
		var bs: Dictionary = combat.target_state()
		_boss_bar.visible = bs.alive
		if bs.alive:
			var br: float = clampf(float(bs.hp) / maxf(float(bs.max), 1.0), 0.0, 1.0)
			if bs.get("shielded", false):
				_boss_label.text = "◼  %s   ⛨ SHIELDED · clear the swarm" % String(bs.get("name", "VORTEX")).to_upper()
			else:
				_boss_label.text = "◼  %s   %d%%" % [String(bs.get("name", "VORTEX")).to_upper(), int(round(100.0 * br))]
			_boss_fill.size.x = _boss_bar_w * br
		else:
			_boss_label.text = ""

	# Discovery progress + scan prompt / progress + toast.
	if codex != null:
		_codex_label.text = "Discovered  %d / %d" % [codex.count(), codex.total()]
	if scan_progress > 0.0 and scan_name != "":
		_scan_label.text = "Capturing  %s …  %d%%" % [scan_name, int(scan_progress * 100.0)]
		_capture_label.text = "◎  CAPTURING  %s   %d%%" % [scan_name, int(scan_progress * 100.0)]
		_capture_label.visible = true
		_capture_label.modulate = Color(0.6, 1.0, 0.82, 0.85)
		_capture_ring.queue_redraw()          # animate the ring each frame while capturing
	else:
		_scan_label.text = scan_hint
		if _capture_label.visible:
			_capture_label.visible = false
			_capture_ring.queue_redraw()      # clear the ring once capture ends
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
		_near_label.text = "Nearest  %s  (%s)" % [planets.nearest_name, _fmt_dist(near_au)]
		# Offer the Details button when you're close to that body.
		var close := planets.nearest_dist < _detail_range
		details_button.visible = close
		if close:
			details_button.text = "ⓘ  %s  DETAILS  (G)" % planets.nearest_name
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
	label.add_theme_color_override("font_color", Color.WHITE)
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.55))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.45))
	label.add_theme_constant_override("outline_size", 2)
	label.material = _grad_material(color, font_size)
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
