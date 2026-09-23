class_name StarMap
extends CanvasLayer
# Star map overlay (M). Elite-style 3D local+global chart (see MapView3D) of the ~50-star
# catalogue laid out by real sky position, with toggleable layers (stars / wormholes /
# planets / lanes), a live player cursor, and hover read-outs. The right column lists the
# SELECTED system's bodies with Navigate / Chart-lane actions. The map NEVER moves the ship —
# it's a chart you read. Pauses flight + frees the cursor; process_mode = ALWAYS so M keeps
# working (and the chart keeps animating) while the tree is paused.

const PANEL := Vector2(1140, 624)
const PANEL_POS := Vector2((1280 - 1140) * 0.5, (720 - 624) * 0.5)
const CHART_OFF := Vector2(18, 110)             # below Local/Global tabs + filter chips
const CHART_SIZE := Vector2(700, 486)
const RIGHT_X := CHART_OFF.x + CHART_SIZE.x + 16

var main: Node

var _root: Control
var _panel: PanelContainer
var _chart: MapView3D
var _sys_list: VBoxContainer
var _title: Label
var _scale_label: Label
var _mode_local: Button
var _mode_global: Button
var _hint: Label
var _body_menu: PopupMenu
var _menu_body := ""
var _view_system := ""
var _open := false
var _tp_mode := false   # opened from a dock's TELEPORT NETWORK button: the right column
						#   offers "confirm teleport" for unlocked platforms instead of nav.


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 90
	_build()
	_root.visible = false


func _process(_delta: float) -> void:
	if _open and _chart != null and _scale_label != null:
		_scale_label.text = ("LOCAL  ·  orbit drag · wheel zoom · ship ⌖" if _chart.mode == MapView3D.Mode.LOCAL
			else "GLOBAL  ·  span ≈ %d ly  ·  orbit drag · wheel zoom · click a star" % _chart.span_ly())


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE and _open:
		_close()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_TAB and _open:
		if _chart != null:
			_chart.toggle_mode()
			if main != null and main.audio != null:
				main.audio.play_click()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_M:
		toggle()
		get_viewport().set_input_as_handled()
		return
	if _open and event is InputEventMouseButton and event.pressed \
			and not _body_menu.visible \
			and not _panel.get_global_rect().has_point(event.position):
		_close()
		get_viewport().set_input_as_handled()


func toggle() -> void:
	if _open:
		_close()
	else:
		_tp_mode = false   # M / map button = normal chart, never teleport mode
		_open_map()


# Open the chart in teleport mode (from a dock). Same chart, but the right column lets you
# confirm a jump to any unlocked platform. The platforms layer is forced on so targets show.
func open_teleport() -> void:
	if _open:
		_close()
	_tp_mode = true
	_open_map()
	if _chart != null:
		_chart.filters["platforms"] = true
		_chart.rebuild()


func _open_map() -> void:
	_open = true
	if main != null:
		_view_system = main.current_system
		main.notify_map_opened()
	_chart.view_system = _view_system
	_chart.set_mode(MapView3D.Mode.GLOBAL)
	if _mode_global != null:
		_mode_global.set_pressed_no_signal(true)
	if _mode_local != null:
		_mode_local.set_pressed_no_signal(false)
	_chart.init_view()
	if main != null:
		_chart.center_on(main.current_system)
	_refresh()
	_root.visible = true
	get_tree().paused = true
	if main != null and main.ship != null:
		main.ship._set_capture(false)


func _close() -> void:
	_open = false
	_tp_mode = false
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
	add_child(_root)

	_panel = PanelContainer.new()
	_panel.position = PANEL_POS
	_panel.size = PANEL
	var frame := StyleBoxFlat.new()
	frame.bg_color = Color(0, 0, 0, 0)
	frame.set_border_width_all(2)
	frame.border_color = Color(0.45, 0.85, 1.0, 0.9)
	frame.set_corner_radius_all(8)
	frame.shadow_color = Color(0.3, 0.7, 1.0, 0.35)
	frame.shadow_size = 14
	_panel.add_theme_stylebox_override("panel", frame)
	_root.add_child(_panel)

	var bg := TextureRect.new()
	var grad := Gradient.new()
	grad.set_color(0, Color(0.06, 0.11, 0.19, 0.97))
	grad.set_color(1, Color(0.01, 0.02, 0.05, 0.97))
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
	_title.text = "STAR  MAP"
	_title.position = PANEL_POS + Vector2(0, 12)
	_title.size = Vector2(PANEL.x, 28)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_font_size_override("font_size", 22)
	_title.add_theme_color_override("font_color", Color(0.6, 1.0, 0.95))
	_title.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
	_title.add_theme_constant_override("shadow_offset_y", 2)
	_root.add_child(_title)

	var hint := Label.new()
	_hint = hint
	hint.text = "● gold discovered · ● cyan known · 🔒 locked   ·   ◌ wormhole · 🪐 planet · ⌖ YOU   ·   Local / Global tabs · M / Esc to close"
	hint.position = PANEL_POS + Vector2(0, 40)
	hint.size = Vector2(PANEL.x, 18)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 12)
	hint.add_theme_color_override("font_color", Color(0.7, 0.75, 0.85))
	_root.add_child(hint)

	# Layer filter chips (web-style toggles): show/hide each map layer.
	var fx := PANEL_POS.x + CHART_OFF.x
	var fy := PANEL_POS.y + 62.0
	fx = _mode_chip("LOCAL", true, fx, fy)
	fx = _mode_chip("GLOBAL", false, fx, fy)
	fx += 16.0
	# Filter chips are shorter — nudge down so they sit mid-aligned with the tabs.
	var cy := fy + 7.0
	fx = _chip("✦ Stars", "stars", fx, cy, Color(1.0, 0.84, 0.4))
	fx = _chip("◌ Wormholes", "wormholes", fx, cy, Color(0.7, 0.6, 1.0))
	fx = _chip("🪐 Planets", "planets", fx, cy, Color(0.6, 0.85, 1.0))
	fx = _chip("⧓ Lanes", "lanes", fx, cy, Color(0.45, 0.85, 1.0))
	fx = _chip("⬡ Platforms", "platforms", fx, cy, Color(0.35, 1.0, 0.85))

	# The chart canvas.
	_chart = MapView3D.new()
	_chart.main = main
	_chart.position = PANEL_POS + CHART_OFF
	_chart.size = CHART_SIZE
	_chart.star_clicked.connect(_on_star)
	_chart.mode_changed.connect(_on_mode_changed)
	_root.add_child(_chart)

	_scale_label = Label.new()
	_scale_label.position = PANEL_POS + CHART_OFF + Vector2(8, CHART_SIZE.y - 22)
	_scale_label.add_theme_font_size_override("font_size", 11)
	_scale_label.add_theme_color_override("font_color", Color(0.6, 0.8, 0.95, 0.85))
	_scale_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	_root.add_child(_scale_label)

	# Right column: the selected system's bodies.
	var sys_header := Label.new()
	sys_header.text = "SYSTEM  BODIES"
	sys_header.position = PANEL_POS + Vector2(RIGHT_X, 66)
	sys_header.size = Vector2(PANEL.x - RIGHT_X - 18, 20)
	sys_header.add_theme_font_size_override("font_size", 13)
	sys_header.add_theme_color_override("font_color", Color(0.7, 0.85, 1.0))
	_root.add_child(sys_header)

	var scroll := ScrollContainer.new()
	scroll.position = PANEL_POS + Vector2(RIGHT_X - 4, 88)
	scroll.size = Vector2(PANEL.x - RIGHT_X - 14, PANEL.y - 110)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_root.add_child(scroll)
	_sys_list = VBoxContainer.new()
	_sys_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_sys_list.add_theme_constant_override("separation", 4)
	scroll.add_child(_sys_list)

	_body_menu = PopupMenu.new()
	_body_menu.add_item("◇ Navigate here", 0)
	_body_menu.add_item("» Auto-pilot", 1)
	_body_menu.add_item("ⓘ Inspect (details)", 2)
	_body_menu.id_pressed.connect(_on_body_menu)
	add_child(_body_menu)


# A filter toggle chip; returns the next x so chips lay out left-to-right.
func _chip(text: String, key: String, x: float, y: float, col: Color) -> float:
	var b := Button.new()
	b.text = text
	b.toggle_mode = true
	b.button_pressed = true
	b.focus_mode = Control.FOCUS_NONE
	b.position = Vector2(x, y)
	b.size = Vector2(0, 26)
	b.add_theme_font_size_override("font_size", 12)
	b.add_theme_color_override("font_color", col)
	b.add_theme_color_override("font_pressed_color", col)
	b.add_theme_color_override("font_hover_color", Color(1, 1, 1))
	b.add_theme_stylebox_override("normal", _chip_box(col, 0.06))
	b.add_theme_stylebox_override("hover", _chip_box(col, 0.18))
	b.add_theme_stylebox_override("pressed", _chip_box(col, 0.30))
	b.toggled.connect(func(on):
		if main != null and main.audio != null:
			main.audio.play_click()
		_chart.filters[key] = on
		_chart.rebuild())
	_root.add_child(b)
	var w: float = ThemeDB.fallback_font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x + 26.0
	b.size.x = w
	return x + w + 8.0


func _chip_box(col: Color, fill: float) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(col.r, col.g, col.b, fill)
	sb.border_color = Color(col.r, col.g, col.b, 0.7)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(13)
	sb.content_margin_left = 10; sb.content_margin_right = 10
	return sb



# LOCAL / GLOBAL mode tabs — large, touch-friendly (Android MAP button users).
# Only one is "pressed" at a time; wired to MapView3D.Mode.LOCAL / GLOBAL.
func _mode_chip(text: String, local: bool, x: float, y: float) -> float:
	var b := Button.new()
	b.text = ("◉  " if local else "✦  ") + text
	b.toggle_mode = true
	b.button_pressed = not local  # GLOBAL starts selected; open_map keeps them in sync
	b.focus_mode = Control.FOCUS_NONE
	b.position = Vector2(x, y)
	# ~44 px tall, wide enough for thumbs on phone landscape.
	var tab_w := 118.0
	b.size = Vector2(tab_w, 40)
	b.add_theme_font_size_override("font_size", 15)
	var col := Color(0.55, 1.0, 0.75) if local else Color(0.45, 0.85, 1.0)
	b.add_theme_color_override("font_color", col)
	b.add_theme_color_override("font_pressed_color", Color(1.0, 1.0, 1.0))
	b.add_theme_color_override("font_hover_color", Color(1, 1, 1))
	b.add_theme_stylebox_override("normal", _tab_box(col, false))
	b.add_theme_stylebox_override("hover", _tab_box(col, false, 0.18))
	b.add_theme_stylebox_override("pressed", _tab_box(col, true))
	b.toggled.connect(func(on: bool):
		if not on:
			# Keep at least one mode selected — re-press if the user clicked the active one off.
			b.button_pressed = true
			return
		if main != null and main.audio != null:
			main.audio.play_click()
		if local:
			if _mode_global != null:
				_mode_global.set_pressed_no_signal(false)
			_chart.set_mode(MapView3D.Mode.LOCAL)
		else:
			if _mode_local != null:
				_mode_local.set_pressed_no_signal(false)
			_chart.set_mode(MapView3D.Mode.GLOBAL)
		_refresh())
	_root.add_child(b)
	if local:
		_mode_local = b
	else:
		_mode_global = b
	return x + tab_w + 10.0


func _tab_box(col: Color, active: bool, fill_override: float = -1.0) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	var fill: float = (0.38 if active else 0.10) if fill_override < 0.0 else fill_override
	sb.bg_color = Color(col.r, col.g, col.b, fill)
	sb.border_color = Color(col.r, col.g, col.b, 0.95 if active else 0.55)
	sb.set_border_width_all(2 if active else 1)
	sb.border_width_bottom = 4 if active else 1
	sb.set_corner_radius_all(8)
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	return sb


func _on_mode_changed(mode: String) -> void:
	if _mode_local != null:
		_mode_local.set_pressed_no_signal(mode == "local")
	if _mode_global != null:
		_mode_global.set_pressed_no_signal(mode == "global")
	if _hint != null:
		if mode == "local":
			_hint.text = "LOCAL SYSTEM  ·  star / planets / wormholes / station / ⌖ YOU  ·  tap GLOBAL to zoom out"
		else:
			_hint.text = "● gold discovered · ● cyan known · 🔒 locked   ·   ◌ wormhole · 🪐 planet · ⌖ YOU   ·   Local / Global tabs · M / Esc to close"


func _refresh() -> void:
	_chart.view_system = _view_system
	_chart.rebuild()
	_refresh_system_list()


# Build the right-column body list for the selected system.
func _refresh_system_list() -> void:
	if _sys_list == null or main == null:
		return
	for c in _sys_list.get_children():
		c.queue_free()
	if _view_system == "":
		_view_system = main.current_system
	var sys: String = _view_system
	var here: bool = sys == main.current_system
	if _title != null:
		if _tp_mode:
			_title.text = "⌖  TELEPORT NETWORK   ·   %s" % SystemDB.display_name(sys)
		else:
			_title.text = "STAR  MAP   ·   %s%s" % [SystemDB.display_name(sys), "  (you are here)" if here else ""]
	_add_travel_action(sys, here)
	var rows := []
	for spec in SystemDB.bodies(sys):
		var bname: String = spec.name
		if bname.contains("✦"):
			continue
		var dist: float = main.planets.rel_of(bname).length() if here else 0.0
		rows.append({ "name": bname, "star": spec.get("star", false), "dist": dist, "here": here })
	rows.sort_custom(func(a, b): return a.dist < b.dist)
	for r in rows:
		var bname: String = r.name
		var captured: bool = main.codex != null and main.codex.is_discovered(bname)
		var info: Dictionary = PlanetData.BUNDLED.get(bname, {})
		var dtxt: String = ("%6.2f AU" % (r.dist / float(Ephemeris.AU_TO_UNITS))) if r.here else "   —   "
		var b := Button.new()
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.focus_mode = Control.FOCUS_NONE
		b.flat = true
		b.add_theme_font_size_override("font_size", 13)
		b.add_theme_color_override("font_hover_color", Color(1, 1, 1))
		if captured:
			var kind: String = info.get("type", "Star" if r.star else "Body")
			b.text = "✦  %-16s  %-9s  %s" % [bname, kind, dtxt]
			b.add_theme_color_override("font_color", Color(1.0, 0.84, 0.4))
		else:
			b.text = "🔒  %-16s  %-9s  %s" % ["? ? ?", "locked", dtxt]
			b.add_theme_color_override("font_color", Color(0.7, 0.78, 0.9))
		b.pressed.connect(_open_body_menu.bind(bname, captured, r.here, b))
		_sys_list.add_child(b)


# Top of the right panel: what this place is + how to reach it (Navigate / Chart-lane).
func _add_travel_action(sys: String, here: bool) -> void:
	if _sys_list == null or main == null:
		return
	var info := Label.new()
	info.add_theme_font_size_override("font_size", 12)
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.custom_minimum_size = Vector2(PANEL.x - RIGHT_X - 24, 0)
	info.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
	# Teleport mode: the only action is "confirm jump" to an unlocked platform.
	if _tp_mode:
		_add_teleport_action(sys, here, info)
		return
	if here:
		info.text = "◉  You are here."
		info.add_theme_color_override("font_color", Color(0.55, 1.0, 0.6))
		_sys_list.add_child(info)
		_sys_list.add_child(_spacer())
		return
	if sys == SystemDB.SOL:
		info.text = "⌂  Home. Use Emergency Return (H) to teleport back."
		info.add_theme_color_override("font_color", Color(0.55, 1.0, 0.6))
		_sys_list.add_child(info)
		_sys_list.add_child(_spacer())
		return
	if main.is_wormhole_known(sys):
		var discovered: bool = main.star_state(sys) == "discovered"
		var route: String = "Fly to its wormhole and enter it." if main.current_system == SystemDB.INTERSTELLAR \
			else "Take the exit wormhole to the hub, then its wormhole."
		info.text = ("✦  Discovered.  " if discovered else "◇  Wormhole known.  ") + route
		info.add_theme_color_override("font_color", Color(1.0, 0.84, 0.4) if discovered else Color(0.45, 0.85, 1.0))
		_sys_list.add_child(info)
		var nav := Button.new()
		nav.text = "»   NAVIGATE  HERE"
		nav.focus_mode = Control.FOCUS_NONE
		nav.add_theme_font_size_override("font_size", 13)
		nav.add_theme_color_override("font_color", Color(1.0, 0.72, 0.32))
		nav.pressed.connect(func():
			_click_fx(nav)
			main.navigate_to(sys)
			_close())
		_sys_list.add_child(nav)
	else:
		info.text = "🔒  Wormhole unknown — chart a lane, or fly the frontier to discover it."
		info.add_theme_color_override("font_color", Color(0.7, 0.78, 0.9))
		_sys_list.add_child(info)
		var pay := Button.new()
		pay.text = "◇   CHART LANE   —   %d coins" % main.nav_cost(sys)
		pay.focus_mode = Control.FOCUS_NONE
		pay.add_theme_font_size_override("font_size", 13)
		pay.add_theme_color_override("font_color", Color(0.7, 0.95, 1.0))
		pay.pressed.connect(func():
			_click_fx(pay)
			if main.unlock_nav(sys):
				_refresh())
		_sys_list.add_child(pay)
	_sys_list.add_child(_spacer())


# Teleport-mode right column: confirm a jump to the selected system if it's an unlocked
# platform; otherwise explain why it can't be a destination.
func _add_teleport_action(sys: String, here: bool, info: Label) -> void:
	if here:
		info.text = "◉  You are docked here.\n\nPick another ⬡ platform on the chart to jump to it."
		info.add_theme_color_override("font_color", Color(0.55, 1.0, 0.6))
		_sys_list.add_child(info)
		_sys_list.add_child(_spacer())
		return
	if main.is_teleport_unlocked(sys):
		info.text = "⬡  %s\n\nA teleport platform you've reached. Jump straight there — the ritual takes a few seconds." % SystemDB.display_name(sys)
		info.add_theme_color_override("font_color", Color(0.4, 1.0, 0.85))
		_sys_list.add_child(info)
		var go := Button.new()
		go.text = "⌖   CONFIRM TELEPORT"
		go.focus_mode = Control.FOCUS_NONE
		go.add_theme_font_size_override("font_size", 14)
		go.add_theme_color_override("font_color", Color(0.5, 1.0, 0.9))
		go.add_theme_stylebox_override("normal", _chip_box(Color(0.4, 1.0, 0.85), 0.12))
		go.add_theme_stylebox_override("hover", _chip_box(Color(0.5, 1.0, 0.9), 0.28))
		go.add_theme_stylebox_override("pressed", _chip_box(Color(0.7, 1.0, 1.0), 0.40))
		go.pressed.connect(func():
			_click_fx(go)
			_close()                      # unpause the tree BEFORE the ritual starts ticking
			main.teleport_to_platform(sys))
		_sys_list.add_child(go)
	elif SystemDB.has_station(sys):
		info.text = "🔒  %s has a platform, but you haven't reached it yet. Fly there once to add it to the network." % SystemDB.display_name(sys)
		info.add_theme_color_override("font_color", Color(0.7, 0.78, 0.9))
		_sys_list.add_child(info)
	else:
		info.text = "✦  %s has no teleport platform.\n\nPick a ⬡ system to jump to it." % SystemDB.display_name(sys)
		info.add_theme_color_override("font_color", Color(0.7, 0.78, 0.9))
		_sys_list.add_child(info)
	_sys_list.add_child(_spacer())


func _spacer() -> Control:
	var s := Control.new()
	s.custom_minimum_size = Vector2(0, 8)
	return s


func _open_body_menu(bname: String, captured: bool, here: bool, btn: Control = null) -> void:
	_click_fx(btn)
	_menu_body = bname
	_body_menu.set_item_disabled(0, not here)
	_body_menu.set_item_disabled(1, not (here and captured))
	_body_menu.set_item_disabled(2, not captured)
	var mp := Vector2i(get_viewport().get_mouse_position())
	_body_menu.popup(Rect2i(mp, Vector2i(10, 10)))


func _click_fx(c: Control = null) -> void:
	if main != null and main.audio != null:
		main.audio.play_click()
	if c != null:
		c.pivot_offset = c.size * 0.5
		var tw := create_tween()
		tw.tween_property(c, "scale", Vector2(0.93, 0.93), 0.05)
		tw.tween_property(c, "scale", Vector2(1, 1), 0.08)


func _on_body_menu(id: int) -> void:
	_click_fx()
	var bname := _menu_body
	if main == null or bname == "":
		return
	match id:
		0:
			_close()
			if main.has_method("set_nav_target"):
				main.set_nav_target(bname)
		1:
			_close()
			if main.has_method("start_autopilot"):
				main.start_autopilot(bname)
		2:
			_close()
			if main.has_method("open_details_for"):
				main.open_details_for(bname)


# A star was clicked on the chart → select it to browse its bodies on the right.
func _on_star(id: String) -> void:
	if main != null and main.audio != null:
		main.audio.play_click()
	_view_system = id
	_refresh()
