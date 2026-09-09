class_name SettingsMenu
extends CanvasLayer
# Esc-toggled settings overlay: Master Volume, Mouse Sensitivity, and GFX
# (Glow, Render scale, Fullscreen). Opening pauses flight and frees the
# cursor; closing restores capture. process_mode = ALWAYS so it keeps running
# (and Esc keeps working) while the tree is paused.
#
# Spawned by main, which passes `ship` (sensitivity + capture) and `env` (glow).

const SENS_MIN := 0.0008
const SENS_MAX := 0.0050
# Render scale doubles as a supersampling control: >100% renders the 3D scene at
# a higher internal resolution and downsamples — "ultra resolution", crisp and
# alias-free, at a GPU cost. <100% is the performance path on weak hardware.
const RENDER_SCALES := [2.0, 1.5, 1.0, 0.75, 0.5]   # matches the OptionButton rows below
const RENDER_LABELS := ["200%  (Ultra)", "150%", "100%", "75%", "50%"]

# One-click graphics presets. Each tunes render scale + anti-aliasing + glow
# together so the player can jump straight to the highest settings ("Ultra").
const QUALITY := ["Ultra", "High", "Balanced", "Performance"]

# Clouds are optional (player feedback: low-altitude fog read as flying
# underwater). Off/Light/Full maps directly to GameState.cloud_quality, which
# PlanetSystem._cloud_recipe() reads to scale cloud_amount before it reaches
# the deck and the fly-through fog.
const CLOUD_LABELS := ["Off", "Light", "Full"]

var ship: Ship
var env: Environment
var hud: HUD                 # set by main, for the "Edit HUD Layout" button
var main                     # set by main, for the "Reset Progress" button
var _reset_btn: Button       # two-tap confirm guard for the wipe
var _reset_armed := false

var _root: Control          # dim + panel; visibility is the open/closed state
var _open := false
var _master_bus := 0
var _fs_check: CheckButton
var _rs_option: OptionButton   # render-scale dropdown (kept so presets can drive it)
var _glow_check: CheckButton   # single glow on/off (kept so presets can drive it)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 100
	_master_bus = AudioServer.get_bus_index("Master")
	_build()
	_root.visible = false


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		# Esc only CLOSES settings (back) — it no longer opens it; the ⚙ button does.
		if event.keycode == KEY_ESCAPE and _open:
			_close()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_F11:          # global fullscreen toggle (works anytime)
			toggle_fullscreen()
			get_viewport().set_input_as_handled()


func toggle() -> void:
	if _open:
		_close()
	else:
		_open_menu()


func _open_menu() -> void:
	_open = true
	_root.visible = true
	get_tree().paused = true
	if _reset_btn != null:            # disarm the wipe each time the menu opens
		_reset_armed = false
		_reset_btn.text = "Reset Progress…"
	if ship != null:
		ship._set_capture(false)


func _close() -> void:
	_open = false
	_root.visible = false
	get_tree().paused = false
	if ship != null and not ship.frozen:
		ship._set_capture(true)


# ---------------------------------------------------------------------------
func _build() -> void:
	_root = ColorRect.new()
	_root.color = Color(0, 0, 0, 0.55)            # dim the game behind the panel
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(center)

	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _panel_box())
	center.add_child(panel)

	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	panel.add_child(margin)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 14)
	col.custom_minimum_size = Vector2(380, 0)
	margin.add_child(col)

	col.add_child(_title("SETTINGS"))

	# --- Graphics Quality preset (top: drives the GFX rows below in one click) ---
	var quality := OptionButton.new()
	for q in QUALITY:
		quality.add_item(q)
	quality.selected = 1   # default the dropdown to High (the rows reflect live state)
	quality.item_selected.connect(_on_quality)
	col.add_child(_row("Graphics Quality", quality))

	# --- Master Volume ---
	var vol := _slider(0.0, 1.0, 0.01, db_to_linear(AudioServer.get_bus_volume_db(_master_bus)))
	vol.value_changed.connect(_on_volume)
	col.add_child(_row("Master Volume", vol))

	# --- Mouse Sensitivity ---
	var cur_sens := ship.mouse_sens if ship != null else Ship.MOUSE_SENS
	var sens_t := clampf(inverse_lerp(SENS_MIN, SENS_MAX, cur_sens), 0.0, 1.0)
	var sens := _slider(0.0, 1.0, 0.01, sens_t)
	sens.value_changed.connect(_on_sensitivity)
	col.add_child(_row("Mouse Sensitivity", sens))

	# --- Glow ---
	# ONE variant, not a High/Low pair. The old dropdown's "High" was the full-strength
	# chain and its "Low" was glow off, so it read as a quality choice while actually
	# being a toggle. main.gd now ships a single mid-strength glow (see the ONE GLOW
	# LEVEL note in _setup_environment); all this row does is turn it on or off.
	_glow_check = CheckButton.new()
	_glow_check.button_pressed = env != null and env.glow_enabled
	_glow_check.toggled.connect(_on_glow)
	col.add_child(_row("Glow", _glow_check))

	# --- Render scale (incl. >100% ultra-resolution supersampling) ---
	_rs_option = OptionButton.new()
	for lbl in RENDER_LABELS:
		_rs_option.add_item(lbl)
	_rs_option.selected = RENDER_SCALES.find(get_viewport().scaling_3d_scale)
	if _rs_option.selected < 0:
		_rs_option.selected = RENDER_SCALES.find(1.0)
	_rs_option.item_selected.connect(_on_render_scale)
	col.add_child(_row("Render Scale", _rs_option))

	# --- Clouds (Off / Light / Full) ---
	var clouds := OptionButton.new()
	for lbl in CLOUD_LABELS:
		clouds.add_item(lbl)
	clouds.selected = clampi(GameState.cloud_quality, 0, CLOUD_LABELS.size() - 1)
	clouds.item_selected.connect(_on_clouds)
	col.add_child(_row("Clouds", clouds))

	# --- Fullscreen ---
	_fs_check = CheckButton.new()
	_fs_check.button_pressed = _is_fullscreen()
	_fs_check.toggled.connect(_apply_fullscreen)
	col.add_child(_row("Fullscreen  (F11)", _fs_check))

	# --- Edit HUD Layout: close settings, then enter the HUD's drag-to-move editor.
	var edit_hud := Button.new()
	edit_hud.text = "Edit HUD Layout…"
	edit_hud.focus_mode = Control.FOCUS_NONE
	edit_hud.pressed.connect(_on_edit_hud)
	col.add_child(edit_hud)

	# --- Reset Progress: wipe the save (visited systems, codex, coins, HUD layout) and restart
	# fresh from Earth. Two-tap confirm so it can't be hit by accident.
	_reset_btn = Button.new()
	_reset_btn.text = "Reset Progress…"
	_reset_btn.focus_mode = Control.FOCUS_NONE
	_reset_btn.add_theme_color_override("font_color", Color(1.0, 0.55, 0.5))
	_reset_btn.pressed.connect(_on_reset)
	col.add_child(_reset_btn)

	var resume := Button.new()
	resume.text = "Resume   (Esc)"
	resume.focus_mode = Control.FOCUS_NONE
	resume.pressed.connect(_close)
	col.add_child(resume)


func _on_reset() -> void:
	if not _reset_armed:
		_reset_armed = true
		_reset_btn.text = "⚠  TAP AGAIN TO WIPE ALL PROGRESS"
		return
	if main != null:
		main.reset_progress()


func _on_edit_hud() -> void:
	_close()
	if hud != null:
		hud.enter_edit()


# --- control callbacks ---
func _on_volume(v: float) -> void:
	AudioServer.set_bus_mute(_master_bus, v <= 0.001)
	AudioServer.set_bus_volume_db(_master_bus, linear_to_db(maxf(v, 0.001)))

func _on_sensitivity(t: float) -> void:
	if ship != null:
		ship.mouse_sens = lerpf(SENS_MIN, SENS_MAX, t)

func _on_glow(on: bool) -> void:
	if env != null:
		env.glow_enabled = on

func _on_render_scale(idx: int) -> void:
	_apply_render_scale(RENDER_SCALES[idx])

func _apply_render_scale(scale: float) -> void:
	var vp := get_viewport()
	vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
	vp.scaling_3d_scale = scale


# One-click preset: set render scale, MSAA, screen-space AA and glow together.
# "Ultra" = supersampled 2x with 8x MSAA — the highest the player can pick.
func _on_quality(idx: int) -> void:
	var vp := get_viewport()
	var scale := 1.0
	match idx:
		0:   # Ultra — supersample + maximum AA + glow
			scale = 2.0
			vp.msaa_3d = Viewport.MSAA_8X
			vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
			vp.use_taa = true
			# There is only ONE glow variant now (see main.gd _setup_environment), so a
			# quality preset has nothing to pick — it leaves the Glow row alone.
		1:   # High — native res, strong MSAA + glow
			scale = 1.0
			vp.msaa_3d = Viewport.MSAA_4X
			vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
			vp.use_taa = false
			# There is only ONE glow variant now (see main.gd _setup_environment), so a
			# quality preset has nothing to pick — it leaves the Glow row alone.
		2:   # Balanced — native res, light AA + glow
			scale = 1.0
			vp.msaa_3d = Viewport.MSAA_2X
			vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA
			vp.use_taa = false
			# There is only ONE glow variant now (see main.gd _setup_environment), so a
			# quality preset has nothing to pick — it leaves the Glow row alone.
		3:   # Performance — lower res, no MSAA, no glow
			scale = 0.75
			vp.msaa_3d = Viewport.MSAA_DISABLED
			vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA
			vp.use_taa = false
			if env != null:
				env.glow_enabled = false
	_apply_render_scale(scale)
	# Reflect the preset in the individual GFX rows.
	if _rs_option != null:
		var ri := RENDER_SCALES.find(scale)
		if ri >= 0:
			_rs_option.selected = ri
	if _glow_check != null:
		_glow_check.button_pressed = env != null and env.glow_enabled

func _on_clouds(idx: int) -> void:
	GameState.cloud_quality = idx
	if main != null and main.has_method("_save_profile"):
		main._save_profile()

func _is_fullscreen() -> bool:
	var m := get_window().mode
	return m == Window.MODE_FULLSCREEN or m == Window.MODE_EXCLUSIVE_FULLSCREEN

func _apply_fullscreen(on: bool) -> void:
	get_window().mode = Window.MODE_FULLSCREEN if on else Window.MODE_WINDOWED
	if _fs_check != null:
		_fs_check.set_pressed_no_signal(on)

func toggle_fullscreen() -> void:
	_apply_fullscreen(not _is_fullscreen())


# --- small UI builders ---
func _row(label_text: String, control: Control) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	var l := Label.new()
	l.text = label_text
	l.custom_minimum_size = Vector2(160, 0)
	l.add_theme_color_override("font_color", Color(0.85, 0.93, 1.0))
	row.add_child(l)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(control)
	return row

func _slider(min_v: float, max_v: float, step: float, value: float) -> HSlider:
	var s := HSlider.new()
	s.min_value = min_v
	s.max_value = max_v
	s.step = step
	s.value = value
	s.custom_minimum_size = Vector2(180, 0)
	return s

func _title(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", 26)
	l.add_theme_color_override("font_color", Color(0.6, 1.0, 0.95))
	return l

func _panel_box() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.07, 0.09, 0.13, 0.98)
	sb.set_border_width_all(2)
	sb.border_color = Color(0.40, 0.85, 1.0)
	sb.set_corner_radius_all(6)
	sb.set_content_margin_all(4)
	return sb
