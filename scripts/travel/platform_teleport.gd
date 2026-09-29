class_name PlatformTeleport
extends CanvasLayer
# Isolated platform fast-travel console — NOT the star map and with no tie to it. It just
# lists every system you have reached (each has a platform once visited), bright + clickable;
# the one you're docked at is marked. Unreached stars need the interstellar drive. Click a
# tile, hit CONFIRM, and the teleport ritual carries
# you there. Opened from the dock's "TELEPORT NETWORK" button (main._on_open_teleport_map).

var main                      # set by main right after instancing
var _root: ColorRect
var _grid: GridContainer
var _confirm: Button
var _confirm_label: Label
var _selected := ""
var _open := false

const BRIGHT := Color(0.20, 0.95, 0.80)   # unlocked platform
const LOCKED := Color(0.28, 0.30, 0.34)   # locked / not reached
const HERE := Color(1.00, 0.80, 0.35)     # the platform you're docked at


func _ready() -> void:
	layer = 90
	process_mode = Node.PROCESS_MODE_ALWAYS   # runs while the tree is paused
	_root = ColorRect.new()
	_root.color = Color(0.02, 0.03, 0.06, 0.96)
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)

	var col := VBoxContainer.new()
	col.set_anchors_preset(Control.PRESET_FULL_RECT)
	col.add_theme_constant_override("separation", 14)
	col.offset_left = 60; col.offset_top = 40; col.offset_right = -60; col.offset_bottom = -40
	_root.add_child(col)

	var title := Label.new()
	title.text = "⬡  PLATFORM TELEPORT NETWORK"
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_color_override("font_color", Color(0.6, 1.0, 0.92))
	col.add_child(title)

	var hint := Label.new()
	hint.text = "Bright = reached (jump-ready).   Dark = locked — fly there once to add it.   Pick one, then CONFIRM."
	hint.add_theme_font_size_override("font_size", 15)
	hint.add_theme_color_override("font_color", Color(0.6, 0.7, 0.82))
	col.add_child(hint)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(scroll)
	_grid = GridContainer.new()
	_grid.columns = 4
	_grid.add_theme_constant_override("h_separation", 12)
	_grid.add_theme_constant_override("v_separation", 12)
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_grid)

	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 16)
	col.add_child(bar)
	_confirm_label = Label.new()
	_confirm_label.add_theme_font_size_override("font_size", 18)
	_confirm_label.add_theme_color_override("font_color", Color(0.85, 0.95, 1.0))
	_confirm_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(_confirm_label)
	_confirm = Button.new()
	_confirm.text = "✦  CONFIRM JUMP"
	_confirm.custom_minimum_size = Vector2(200, 44)
	_confirm.pressed.connect(_on_confirm)
	bar.add_child(_confirm)
	var close := Button.new()
	close.text = "✕  Close"
	close.custom_minimum_size = Vector2(120, 44)
	close.pressed.connect(close_panel)
	bar.add_child(close)

	_root.visible = false


func open() -> void:
	_selected = ""
	_build_tiles()
	_update_confirm()
	_root.visible = true
	_open = true
	get_tree().paused = true
	if main != null and main.ship != null:
		main.ship._set_capture(false)


func close_panel() -> void:
	_root.visible = false
	_open = false
	get_tree().paused = false
	if main != null and main.ship != null and not main.ship.frozen:
		main.ship._set_capture(true)


func _input(event: InputEvent) -> void:
	if _open and event is InputEventKey and event.pressed and not event.echo \
			and event.physical_keycode == KEY_ESCAPE:
		close_panel()
		get_viewport().set_input_as_handled()


func _build_tiles() -> void:
	for c in _grid.get_children():
		c.queue_free()
	for id in SystemDB.all():
		if not SystemDB.is_teleport_platform(id):
			continue
		var here: bool = (id == main.current_system)
		var unlocked: bool = main.is_teleport_unlocked(id)
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(0, 56)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.text = ("◉  " if here else "⬡  ") + SystemDB.display_name(id)
		btn.add_theme_font_size_override("font_size", 16)
		var col: Color = HERE if here else (BRIGHT if unlocked else LOCKED)
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(col.r, col.g, col.b, 0.16 if (unlocked or here) else 0.10)
		sb.set_border_width_all(2 if (id == _selected) else 1)
		sb.border_color = (Color.WHITE if id == _selected else col)
		sb.set_corner_radius_all(6)
		for st in ["normal", "hover", "pressed", "focus", "disabled"]:
			btn.add_theme_stylebox_override(st, sb)
		btn.add_theme_color_override("font_color", col)
		btn.add_theme_color_override("font_disabled_color", Color(col.r, col.g, col.b, 0.5))
		btn.disabled = here or not unlocked          # only reachable, not-current platforms pick
		if unlocked and not here:
			btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
			btn.pressed.connect(_select.bind(id))
		_grid.add_child(btn)


func _select(id: String) -> void:
	_selected = id
	_build_tiles()       # rebuild so the chosen tile shows its white ring
	_update_confirm()


func _update_confirm() -> void:
	if _selected == "":
		_confirm_label.text = "Select a bright ⬡ platform to jump to."
		_confirm.disabled = true
	else:
		_confirm_label.text = "JUMP TO  →  %s" % SystemDB.display_name(_selected)
		_confirm.disabled = false


func _on_confirm() -> void:
	if _selected == "":
		return
	var dest := _selected
	close_panel()
	if main != null:
		main.teleport_to_platform(dest)   # runs the light-ball teleport ritual
