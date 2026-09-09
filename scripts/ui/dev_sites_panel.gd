class_name DevSitesPanel
extends CanvasLayer
# Ctrl+P dev-teleport panel: pick any Sol body/park/landmark from DevSites.sites()
# and jump straight there, no hunting for it by flying. House pattern copied from
# SettingsMenu/CodexPanel — pauses flight and frees the cursor while open, closing
# restores capture. main.gd owns the Ctrl+P key; this class only exposes toggle().
#
# Dev tool: no separate flag gate, same as F6/F7/F9 on Ship (always available).
# Sol only — outside Sol the ship isn't Newton-anchored to a body by name at all
# (ship.newton is false), so the list is intentionally left empty with a note
# instead of guessing at arcade-system coordinates.

const DS := preload("res://scripts/world/dev_sites.gd")

var ship: Ship
var main   # untyped: main.gd has no class_name (same reason SettingsMenu.main is untyped)

var _root: Control
var _list: VBoxContainer
var _filter: LineEdit
var _title: Label
var _open := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 97
	_build()
	_root.visible = false


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and _open:
		if event.keycode == KEY_ESCAPE:
			_close()
			get_viewport().set_input_as_handled()


func toggle() -> void:
	if _open:
		_close()
	else:
		_open_panel()


func _open_panel() -> void:
	_filter.text = ""
	_refresh()
	_open = true
	_root.visible = true
	get_tree().paused = true
	if ship != null:
		ship._set_capture(false)
	_filter.grab_focus()


func _close() -> void:
	_open = false
	_root.visible = false
	get_tree().paused = false
	if ship != null and not ship.frozen:
		ship._set_capture(true)


# ---------------------------------------------------------------------------
func _refresh() -> void:
	var in_sol := ship != null and ship.newton
	_title.text = "DEV SITES        Ctrl+P / Esc to close" if in_sol \
		else "DEV SITES        Sol only — fly home first"
	for c in _list.get_children():
		c.queue_free()
	if not in_sol:
		return
	var needle := _filter.text.to_lower()
	var by_body := {}
	var order: Array = []
	for site in DS.sites():
		var body: String = site.body
		var haystack := "%s %s %s" % [str(site.name), body, str(site.get("note", ""))]
		if not needle.is_empty() and not haystack.to_lower().contains(needle):
			continue
		if not by_body.has(body):
			by_body[body] = []
			order.append(body)
		by_body[body].append(site)
	order.sort()
	for body in order:
		var head := Label.new()
		head.text = body
		head.add_theme_font_size_override("font_size", 18)
		head.add_theme_color_override("font_color", Color(0.6, 1.0, 0.95))
		_list.add_child(head)
		for site in by_body[body]:
			var row := Button.new()
			row.focus_mode = Control.FOCUS_NONE
			row.alignment = HORIZONTAL_ALIGNMENT_LEFT
			row.flat = true
			row.text = "    %s   —  %s" % [str(site.name), str(site.get("note", ""))]
			row.pressed.connect(_pick.bind(site))
			_list.add_child(row)


func _pick(site: Dictionary) -> void:
	_close()
	go(site)


func _on_filter_changed(_text: String) -> void:
	_refresh()


# Teleport sequence: reanchor (main._anchor_ship, which also carries combat's
# entities via combat.shift_frame — docs/adr/0002), set the offset for the
# site's mode, zero velocity, reset the mesh/camera pose and face the
# requested heading (or back toward the body's centre for a park/GEO row —
# the same face_toward(-anchor_off) _skin_finish()/_arrive() already use),
# then reset time scale. Mirrors _debug_geo_park()/_skin_finish() in
# scripts/flight/ship.gd — reusing their public API, not duplicating their
# internals (ship.gd is out of this file's ownership).
func go(site: Dictionary) -> void:
	if ship == null or main == null:
		return
	var body: String = site.body
	main._anchor_ship(body)
	var mode := str(site.get("mode", "surface"))
	match mode:
		"geo":
			ship.anchor_off = Ephemeris.geo_start_pos()
		"park":
			ship.anchor_off = Ephemeris.sweet_spot_off(body)
		_:
			var dir := DS.dir_for(float(site.lat_deg), float(site.lon_deg))
			var radius := Ephemeris.body_radius_km(body)
			var sampler: TerrainSampler = main.planets.terrain_sampler_for(body) \
				if main.planets != null else null
			var ground_r := sampler.ground_radius_km(dir, radius) if sampler != null else radius
			ship.anchor_off = DS.surface_anchor_off(dir, ground_r, float(site.alt_km))
	ship.velocity = Vector3.ZERO
	ship.reset_mesh_pose()
	if mode == "geo" or mode == "park":
		ship.face_toward(-ship.anchor_off)
	else:
		var dir2 := DS.dir_for(float(site.lat_deg), float(site.lon_deg))
		var fwd := DS.heading_forward(dir2, float(site.get("heading_deg", 0.0)))
		ship.face_toward(fwd * 1000.0)
	ship.time_rate = 1.0


# ---------------------------------------------------------------------------
func _build() -> void:
	_root = ColorRect.new()
	_root.color = Color(0.01, 0.02, 0.05, 0.95)
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 60)
	_root.add_child(margin)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	margin.add_child(col)

	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 30)
	_title.add_theme_color_override("font_color", Color(0.6, 1.0, 0.95))
	col.add_child(_title)

	_filter = LineEdit.new()
	_filter.placeholder_text = "filter by name / body / note…"
	_filter.text_changed.connect(_on_filter_changed)
	col.add_child(_filter)
	col.add_child(HSeparator.new())

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 4)
	scroll.add_child(_list)

	var close := Label.new()
	close.text = "click a site to jump there   ·   Ctrl+P / Esc to close"
	close.add_theme_color_override("font_color", Color(0.7, 0.75, 0.85))
	col.add_child(close)
