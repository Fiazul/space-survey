class_name QuestLog
extends CanvasLayer
# The MISSION LOG (J). Every body in the catalogue is a mission (see MissionDB). Left column:
# a scrollable list of every mission, grouped by system, with a status icon. Right column:
# the selected mission's title, crude story, status, and a NAVIGATE button that sets
# the orange guide toward its system and closes the log — you FLY there and survey it.
# Pauses flight + frees the cursor like the Star Map; process_mode = ALWAYS so J keeps working
# while the tree is paused.
#
# Status per mission (from main.star_state(system) + codex):
#   complete  — already surveyed (green ✓)
#   active    — it's in the system you're in, not yet surveyed (cyan ◆)
#   open      — reachable (discovered / nav / here) but you're elsewhere (◇ — navigate)
#   locked    — no known route yet (🔒)

const PANEL := Vector2(1010, 560)
const PANEL_POS := Vector2((1280 - 1010) * 0.5, (720 - 560) * 0.5)

var main: Node
@onready var codex := Codex   # autoload

var _root: Control
var _panel: PanelContainer
var _list: VBoxContainer        # left: grouped mission rows
var _detail: VBoxContainer      # right: selected mission
var _title: Label
var _sel := ""                  # selected body name
var _open := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 95
	_build()
	_root.visible = false


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_J and not _open:
			_open_log()
			get_viewport().set_input_as_handled()
		elif _open and event.keycode in [KEY_J, KEY_ESCAPE]:
			_close()
			get_viewport().set_input_as_handled()


# A click that reaches the dim backdrop (i.e. outside the log panel) closes the log.
func _on_backdrop_input(event: InputEvent) -> void:
	if _open and event is InputEventMouseButton and event.pressed:
		_close()


func toggle() -> void:
	if _open:
		_close()
	else:
		_open_log()


func _open_log() -> void:
	_open = true
	if main != null:
		main.notify_log_opened()             # advances onboarding (the log pauses the tree)
	# Newcomers land on the GETTING STARTED quest first; once it's done, fall through to missions.
	if main != null and _sel == "" and not main.onboarding_state().complete:
		_sel = "__beginner__"
	if main != null and _sel == "":
		# Default selection: first unfinished mission in the system you're in.
		for body in MissionDB.bodies_in(main.current_system):
			if codex == null or not codex.is_discovered(body):
				_sel = body
				break
		if _sel == "":
			var ms: Array = MissionDB.bodies_in(main.current_system)
			_sel = ms[0] if not ms.is_empty() else ""
	_refresh()
	_root.visible = true
	get_tree().paused = true
	if main != null and main.ship != null:
		main.ship._set_capture(false)


func _close() -> void:
	_open = false
	_root.visible = false
	get_tree().paused = false
	if main != null and main.ship != null and not main.ship.frozen:
		main.ship._set_capture(true)


# ---------------------------------------------------------------------------
func _build() -> void:
	_root = ColorRect.new()
	_root.color = Color(0.01, 0.01, 0.04, 0.55)
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.gui_input.connect(_on_backdrop_input)   # click outside the panel closes the log
	add_child(_root)

	_panel = PanelContainer.new()
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP   # panel consumes its own clicks (don't close)
	_panel.position = PANEL_POS
	_panel.size = PANEL
	var frame := StyleBoxFlat.new()
	frame.bg_color = Color(0, 0, 0, 0)
	frame.set_border_width_all(2)
	frame.border_color = Color(1.0, 0.72, 0.32, 0.9)
	frame.set_corner_radius_all(8)
	frame.shadow_color = Color(1.0, 0.6, 0.2, 0.3)
	frame.shadow_size = 14
	_panel.add_theme_stylebox_override("panel", frame)
	_root.add_child(_panel)

	var bg := TextureRect.new()
	var grad := Gradient.new()
	grad.set_color(0, Color(0.10, 0.08, 0.05, 0.97))
	grad.set_color(1, Color(0.02, 0.02, 0.04, 0.97))
	var gt := GradientTexture2D.new()
	gt.gradient = grad
	gt.fill = GradientTexture2D.FILL_LINEAR
	gt.fill_from = Vector2(0, 0)
	gt.fill_to = Vector2(0, 1)
	gt.width = 8; gt.height = 64
	bg.texture = gt
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(bg)

	_title = Label.new()
	_title.position = PANEL_POS + Vector2(0, 14)
	_title.size = Vector2(PANEL.x, 28)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_font_size_override("font_size", 22)
	_title.add_theme_color_override("font_color", Color(1.0, 0.84, 0.4))
	_title.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
	_title.add_theme_constant_override("shadow_offset_y", 2)
	_root.add_child(_title)

	var hint := Label.new()
	hint.text = "✓ surveyed · ◆ here now · ◇ reachable · 🔒 locked   ·   click a mission → story + Navigate   ·   J / Esc to close"
	hint.position = PANEL_POS + Vector2(0, 44)
	hint.size = Vector2(PANEL.x, 18)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 12)
	hint.add_theme_color_override("font_color", Color(0.75, 0.72, 0.62))
	_root.add_child(hint)

	# Left: scrollable mission list.
	var scroll := ScrollContainer.new()
	scroll.position = PANEL_POS + Vector2(22, 74)
	scroll.size = Vector2(440, PANEL.y - 96)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_root.add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 2)
	scroll.add_child(_list)

	# Right: selected mission detail.
	var dscroll := ScrollContainer.new()
	dscroll.position = PANEL_POS + Vector2(484, 74)
	dscroll.size = Vector2(PANEL.x - 506, PANEL.y - 96)
	dscroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_root.add_child(dscroll)
	_detail = VBoxContainer.new()
	_detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_detail.add_theme_constant_override("separation", 10)
	dscroll.add_child(_detail)


# ---------------------------------------------------------------------------
func _refresh() -> void:
	if main == null:
		return
	var total := 0
	var done := 0
	for m in MissionDB.all_missions():
		total += 1
		if codex != null and codex.is_discovered(m.body):
			done += 1
	_title.text = "MISSION  LOG        %d / %d  surveyed" % [done, total]

	for c in _list.get_children():
		c.queue_free()

	# Pinned first: the GETTING STARTED beginner quest (always present, even when complete).
	_add_beginner_group()

	# Group by system; show the system you're in first, then by distance from home.
	var ids: Array = SystemDB.all().duplicate()
	var here: String = main.current_system
	ids.sort_custom(func(a, b):
		if a == here: return true
		if b == here: return false
		return SystemDB.light_years(a) < SystemDB.light_years(b))

	for id in ids:
		var bodies: Array = MissionDB.bodies_in(id)
		if bodies.is_empty():
			continue
		var st: String = main.star_state(id)
		var sdone := 0
		for b in bodies:
			if codex != null and codex.is_discovered(b):
				sdone += 1
		_add_group_header(id, st, sdone, bodies.size())
		for body in bodies:
			_add_mission_row(id, body, st)

	_refresh_detail()


func _add_group_header(id: String, st: String, done: int, n: int) -> void:
	var h := Label.new()
	var tag := "  ◉ HERE" if st == "here" else ("  🔒" if st == "locked" else "")
	h.text = "%s   %d/%d%s" % [SystemDB.display_name(id).to_upper(), done, n, tag]
	h.add_theme_font_size_override("font_size", 13)
	h.add_theme_color_override("font_color", _sys_col(st))
	h.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_top", 8)
	pad.add_child(h)
	_list.add_child(pad)


func _add_mission_row(id: String, body: String, st: String) -> void:
	var status := _status(id, body, st)
	var icon: String = { "complete": "✓", "active": "◆", "open": "◇", "locked": "🔒" }.get(status, "◇")
	var tracked: bool = main != null and main.active_quest() == body
	var b := Button.new()
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.focus_mode = Control.FOCUS_NONE
	b.flat = true
	b.add_theme_font_size_override("font_size", 14)
	b.add_theme_color_override("font_hover_color", Color(1, 1, 1))
	b.add_theme_color_override("font_color", Color(0.5, 1.0, 0.7) if tracked else _status_col(status))
	b.text = "  %s%s  %s" % ["★ " if tracked else "", icon, MissionDB.title_for(body)]
	if body == _sel:
		b.text = "▸" + b.text
	b.pressed.connect(func():
		_click()
		_sel = body
		_refresh_detail())
	_list.add_child(b)


# The pinned GETTING STARTED quest at the top of the list: a clickable header + a compact
# step checklist. Always shown (re-doable even after completion).
func _add_beginner_group() -> void:
	if main == null:
		return
	var ob: Dictionary = main.onboarding_state()
	var done := 0
	for s in ob.steps:
		if s.done:
			done += 1
	var col: Color = Color(0.55, 1.0, 0.7) if ob.complete else Color(1.0, 0.84, 0.4)
	var b := Button.new()
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.focus_mode = Control.FOCUS_NONE
	b.flat = true
	b.add_theme_font_size_override("font_size", 14)
	b.add_theme_color_override("font_hover_color", Color(1, 1, 1))
	b.add_theme_color_override("font_color", col)
	b.text = "%s%s  GETTING STARTED   %d/%d" % \
		["▸" if _sel == "__beginner__" else " ", "✓" if ob.complete else "★", done, ob.total]
	b.pressed.connect(func():
		_click()
		_sel = "__beginner__"
		_refresh_detail())
	_list.add_child(b)
	for s in ob.steps:
		var l := Label.new()
		var ic: String = "✓" if s.done else ("◆" if s.current else "○")
		l.text = "       %s  %s" % [ic, s.title]
		l.add_theme_font_size_override("font_size", 12)
		var lc: Color = Color(0.55, 1.0, 0.6) if s.done else (Color(0.45, 0.85, 1.0) if s.current else Color(0.62, 0.65, 0.72))
		l.add_theme_color_override("font_color", lc)
		_list.add_child(l)
	var sep := HSeparator.new()
	_list.add_child(sep)


# The right-hand detail for the GETTING STARTED quest: full checklist + a Restart button.
func _refresh_beginner_detail() -> void:
	var ob: Dictionary = main.onboarding_state()
	_dlabel("GETTING STARTED", 21, Color(1.0, 0.84, 0.4), true)
	_dlabel("Your first quest — learn the controls. It stays here; replay it any time.",
		13, Color(0.7, 0.8, 0.95))
	_detail.add_child(HSeparator.new())
	for s in ob.steps:
		var ic: String = "✓" if s.done else ("◆" if s.current else "○")
		var c: Color = Color(0.55, 1.0, 0.6) if s.done else (Color(0.45, 0.85, 1.0) if s.current else Color(0.88, 0.9, 0.95))
		_dlabel("%s  %s" % [ic, s.title], 14, c)
		_dlabel("        %s" % s.tip, 11, Color(0.62, 0.66, 0.74))
	_detail.add_child(_spacer(8))
	if ob.complete:
		_dlabel("✓  Completed. Replay any time to brush up.", 13, Color(0.6, 0.9, 0.65))
	var r := _action_button("↻   RESTART  THIS  QUEST", Color(1.0, 0.72, 0.32))
	r.pressed.connect(func():
		_click()
		main.restart_onboarding()
		_refresh())
	_detail.add_child(r)


# Build the right-hand detail for the selected mission.
func _refresh_detail() -> void:
	if _detail == null:
		return
	for c in _detail.get_children():
		c.queue_free()
	if _sel == "__beginner__":
		_refresh_beginner_detail()
		return
	if _sel == "":
		return
	var id := MissionDB.system_of(_sel)
	var st: String = main.star_state(id) if main != null else "locked"
	var status := _status(id, _sel, st)
	var mission := MissionDB.mission_for(_sel)

	_dlabel(MissionDB.title_for(_sel), 21, Color(1.0, 0.84, 0.4), true)
	_dlabel("◇  %s   ·   %s   ·   %.1f ly" % [_sel, SystemDB.display_name(id), SystemDB.light_years(id)],
		13, Color(0.7, 0.8, 0.95))

	var stat_txt: String = { "complete": "✓  SURVEYED",
		"active": "◆  YOU ARE HERE — fly close to survey it",
		"open": "◇  Another system",
		"locked": "🔒  No known route" }.get(status, "")
	_dlabel(stat_txt, 13, _status_col(status))

	var sep := HSeparator.new()
	_detail.add_child(sep)

	var story := Label.new()
	story.text = str(mission.get("story", ""))
	story.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	story.custom_minimum_size = Vector2(PANEL.x - 520, 0)
	story.add_theme_font_size_override("font_size", 14)
	story.add_theme_color_override("font_color", Color(0.9, 0.9, 0.92))
	story.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	_detail.add_child(story)

	_detail.add_child(_spacer(8))

	# Action: track the quest (free) and let the nav arrow guide you to it.
	var tracked: bool = main != null and main.active_quest() == _sel
	if status == "complete":
		_dlabel("Mission accomplished. Don't get sentimental.", 12, Color(0.6, 0.8, 0.6))
	elif status == "locked" or status == "open":
		pass
	elif tracked:
		_dlabel("★  TRACKED — the nav arrow is guiding you here.", 13, Color(0.5, 1.0, 0.7))
		var stop := _action_button("✖   STOP  TRACKING", Color(1.0, 0.6, 0.4))
		stop.pressed.connect(func():
			_click()
			main.cancel_locked_nav()
			_refresh())
		_detail.add_child(stop)
	else:
		var t := _action_button("★   TRACK  THIS  QUEST", Color(1.0, 0.72, 0.32))
		t.pressed.connect(func():
			_click()
			main.track_quest(_sel)        # free guide; arrow + tracker lead you there
			_close())
		_detail.add_child(t)


# ---------------------------------------------------------------------------
func _status(id: String, body: String, st: String) -> String:
	if codex != null and codex.is_discovered(body):
		return "complete"
	if st == "here":
		return "active"
	if st == "discovered" or st == "nav":
		return "open"
	return "locked"


func _status_col(status: String) -> Color:
	match status:
		"complete": return Color(0.55, 1.0, 0.6)
		"active":   return Color(0.45, 0.85, 1.0)
		"open":     return Color(1.0, 0.84, 0.4)
		_:          return Color(0.6, 0.62, 0.7)


func _sys_col(st: String) -> Color:
	match st:
		"here":       return Color(0.6, 1.0, 0.7)
		"discovered": return Color(1.0, 0.84, 0.45)
		"nav":        return Color(0.55, 0.9, 1.0)
		_:            return Color(0.62, 0.66, 0.74)


func _dlabel(text: String, size: int, col: Color, bold := false) -> void:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(PANEL.x - 520, 0)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	if bold:
		l.add_theme_constant_override("shadow_offset_y", 1)
	_detail.add_child(l)


func _action_button(text: String, col: Color) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 14)
	b.add_theme_color_override("font_color", col)
	return b


func _spacer(h: int) -> Control:
	var s := Control.new()
	s.custom_minimum_size = Vector2(0, h)
	return s


func _click() -> void:
	if main != null and main.audio != null:
		main.audio.play_click()
