class_name PlanetInfo
extends CanvasLayer
# Details panel for the nearest planet (real NASA facts from PlanetData). Opens
# with G or the HUD "Details" button; pauses flight + frees the cursor while you
# read, like the other overlays. process_mode = ALWAYS so it runs while paused.

@onready var data := PlanetData   # autoload
var planets: PlanetSystem
var ship: Ship
@onready var codex := Codex   # autoload; gate facts behind discovery
var main: Node              # for the capture-reward Claim button

var _root: Control
var _title: Label
var _body: VBoxContainer
var _open := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 95
	_build()
	_root.visible = false


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_G and not _open:
			open_for_nearest()
			get_viewport().set_input_as_handled()
		elif _open and event.keycode in [KEY_G, KEY_ESCAPE]:
			_close()
			get_viewport().set_input_as_handled()


func open_for_nearest() -> void:
	if planets != null:
		open_for(planets.nearest_name)

func open_for(name: String) -> void:
	if name == "":
		return
	var facts: Dictionary
	if data != null and data.has(name):
		facts = data.get_facts(name)
	else:
		# No exoplanet-archive entry for this body — most of the 50+ nearby stars (Ross 128,
		# Wolf 359, …) simply have no confirmed planets, so there are no planetary facts. Show
		# the REAL stellar details we do have (spectral type + distance from the star catalog)
		# plus the body's mission story, so G always opens with genuine info, not nothing.
		facts = {}
		var sys := MissionDB.system_of(name)
		if sys != "":
			facts["distance"] = "%.2f ly" % SystemDB.light_years(sys)
			var sp := SystemDB.spectral(sys)
			if sp != "":
				facts["spectral"] = sp
				facts["type"] = "Star" if name == SystemDB.display_name(sys) else "Body"
		var blurb := MissionDB.story_for(name)
		facts["blurb"] = blurb if blurb != "" else "Deep-space object — no survey data on file yet."
	if planets != null:
		var recipe := planets.stellar_recipe_for(name)
		if not recipe.is_empty():
			facts = facts.duplicate(true)
			var s: Dictionary = recipe.stellar
			facts["type"] = str(s.type).replace("_", " ").capitalize()
			facts["spectral"] = s.spectral
			facts["radius_km"] = s.radius_km
			facts["mass"] = "%.3f solar masses" % float(s.mass_solar)
			facts["temp"] = "%.0f K  (photosphere)" % float(s.temperature_k)
			facts["luminosity"] = "%.5f × Sun" % float(s.luminosity_solar)
			facts["stellar_basis"] = "Spectral estimate / authored model" if s.estimated else "Solar reference"
			facts["blurb"] = "No solid landing surface. Heat and radiation rise on approach. Composition: %s." % ", ".join(s.composition)
	_populate(name, facts)
	_open = true
	_root.visible = true
	get_tree().paused = true
	if ship != null:
		ship._set_capture(false)


func _close() -> void:
	_open = false
	_root.visible = false
	get_tree().paused = false
	if ship != null and not ship.frozen:
		ship._set_capture(true)


# ---------------------------------------------------------------------------
func _populate(name: String, f: Dictionary) -> void:
	_title.text = "%s        %s" % [name, str(f.get("type", ""))]
	for c in _body.get_children():
		c.queue_free()

	# Locked until scanned — exploration reveals the data.
	if codex != null and not codex.is_discovered(name):
		var lock := Label.new()
		lock.text = "◌  UNSCANNED\n\nFly within range and hold  V  to scan this body and reveal its data."
		lock.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		lock.custom_minimum_size = Vector2(560, 0)
		lock.add_theme_font_size_override("font_size", 22)
		lock.add_theme_color_override("font_color", Color(0.7, 0.8, 0.9))
		_body.add_child(lock)
		return

	_row_if(f, "distance", "Distance")
	_row_if(f, "spectral", "Spectral type")
	var rkm = f.get("radius_km", null)
	if rkm != null:
		_row("Radius", "%s km" % _comma(int(rkm)))
	_row_if(f, "mass", "Mass")
	_row_if(f, "gravity", "Surface gravity")
	_row_if(f, "day", "Day length")
	_row_if(f, "year", "Year length")
	_row_if(f, "temp", "Temperature")
	_row_if(f, "luminosity", "Luminosity")
	_row_if(f, "stellar_basis", "Stellar data")
	_row_if(f, "moons", "Moons")
	_row_if(f, "atmosphere", "Atmosphere")

	if f.has("blurb"):
		var sep := HSeparator.new()
		_body.add_child(sep)
		var blurb := Label.new()
		blurb.text = str(f["blurb"])
		blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		blurb.custom_minimum_size = Vector2(560, 0)
		blurb.add_theme_font_size_override("font_size", 20)
		blurb.add_theme_color_override("font_color", Color(0.8, 0.9, 1.0))
		_body.add_child(blurb)

	# Capture reward: a one-time Claim button (the coins are NOT auto-given on capture).
	if main != null and main.has_method("can_claim") and main.can_claim(name):
		_body.add_child(HSeparator.new())
		var claim := Button.new()
		claim.text = "◈  CLAIM  %d coins" % MissionDB.reward(name)
		claim.focus_mode = Control.FOCUS_NONE
		claim.add_theme_font_size_override("font_size", 22)
		claim.add_theme_color_override("font_color", Color(1.0, 0.9, 0.5))
		claim.pressed.connect(_on_claim.bind(name, claim))
		_body.add_child(claim)


func _on_claim(name: String, btn: Button) -> void:
	if main == null:
		return
	if main.audio != null:
		main.audio.play_click()
	var got: int = main.claim_reward(name)
	if got > 0:
		btn.text = "✓  CLAIMED  +%d coins" % got
		btn.disabled = true


func _row_if(f: Dictionary, key: String, label: String) -> void:
	if f.has(key):
		_row(label, str(f[key]))

func _row(label: String, value: String) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 20)
	var l := Label.new()
	l.text = label
	l.custom_minimum_size = Vector2(220, 0)
	l.add_theme_font_size_override("font_size", 22)
	l.add_theme_color_override("font_color", Color(0.6, 0.85, 1.0))
	row.add_child(l)
	var v := Label.new()
	v.text = value
	v.add_theme_font_size_override("font_size", 22)
	v.add_theme_color_override("font_color", Color(1, 1, 1))
	row.add_child(v)
	_body.add_child(row)


func _build() -> void:
	_root = ColorRect.new()
	_root.color = Color(0.01, 0.02, 0.05, 0.93)
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(center)

	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _box())
	center.add_child(panel)

	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 30)
	panel.add_child(margin)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	col.custom_minimum_size = Vector2(600, 0)
	margin.add_child(col)

	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 34)
	_title.add_theme_color_override("font_color", Color(0.65, 1.0, 0.95))
	col.add_child(_title)
	col.add_child(HSeparator.new())

	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", 10)
	col.add_child(_body)

	col.add_child(HSeparator.new())
	var close := Button.new()
	close.text = "Close   (G / Esc)"
	close.focus_mode = Control.FOCUS_NONE
	close.add_theme_font_size_override("font_size", 20)
	close.pressed.connect(_close)
	col.add_child(close)


func _comma(n: int) -> String:
	var s := str(n)
	var out := ""
	var c := 0
	for i in range(s.length() - 1, -1, -1):
		out = s[i] + out
		c += 1
		if c % 3 == 0 and i > 0:
			out = "," + out
	return out


func _box() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.09, 0.14, 0.99)
	sb.set_border_width_all(2)
	sb.border_color = Color(0.4, 0.85, 1.0)
	sb.set_corner_radius_all(8)
	sb.set_content_margin_all(4)
	return sb
