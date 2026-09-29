class_name DevSitesPanel
extends CanvasLayer
# Ctrl+P dev-teleport panel: pick any Sol body/park/landmark from DevSites.sites()
# and jump straight there, no hunting for it by flying. House pattern copied from
# SettingsMenu/CodexPanel — pauses flight and frees the cursor while open, closing
# restores capture. main.gd owns the Ctrl+P key; this class only exposes toggle().
#
# Dev tool: no separate flag gate, same as F6/F7/F9 on Ship (always available).
# STAR SYSTEMS rows jump to any SystemDB star (dev travel bypass); the Sol
# site rows are hidden outside Sol — DevSites names Sol bodies only.

const DS := preload("res://scripts/world/dev_sites.gd")

var ship: Ship
var main   # untyped: main.gd has no class_name (same reason SettingsMenu.main is untyped)

var _root: Control
var _list: VBoxContainer
var _filter: LineEdit
var _title: Label
var _close_button: Button
var _open := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 110
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
	# Keep the phone keyboard closed until the player explicitly taps Search.
	if not OS.has_feature("mobile") and not "--touch" in OS.get_cmdline_user_args():
		_filter.grab_focus()


func _close() -> void:
	_open = false
	_root.visible = false
	get_tree().paused = false
	if ship != null and not ship.frozen:
		ship._set_capture(true)


# ---------------------------------------------------------------------------
func _refresh() -> void:
	var in_sol := ship != null and Ephemeris.system_id == Ephemeris.SOL_ID
	_title.text = "TELEPORT — %s" % SystemDB.display_name(Ephemeris.system_id).to_upper()
	for c in _list.get_children():
		c.queue_free()
	var needle := _filter.text.to_lower()
	_add_systems(needle)
	if not in_sol:
		return
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
		_add_head(body)
		for site in by_body[body]:
			var row := _row("    %s   —  %s" % [str(site.name), str(site.get("note", ""))])
			if site.body == "Earth" and site.get("mode", "surface") == "surface":
				var solar := Ephemeris.solar_state("Earth", DS.dir_for(site.lat_deg,site.lon_deg))
				var minutes := int(solar.hour*60) % 1440
				row.text += "  ·  %02d:%02d solar / %s" % [minutes/60,minutes%60,solar.phase]
			row.pressed.connect(_pick.bind(site))
			_list.add_child(row)


func _add_head(text: String) -> void:
	var head := Label.new()
	head.text = text
	head.add_theme_font_size_override("font_size", 18)
	head.add_theme_color_override("font_color", Color(0.6, 1.0, 0.95))
	_list.add_child(head)


func _row(text: String) -> Button:
	var row := Button.new()
	row.focus_mode = Control.FOCUS_NONE
	row.alignment = HORIZONTAL_ALIGNMENT_LEFT
	row.flat = true
	row.custom_minimum_size.y = 52
	row.add_theme_font_size_override("font_size", 16)
	row.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.text = text
	return row


func system_ids() -> Array:
	var ids := SystemDB.all()
	ids.erase(SystemDB.SOL)
	ids.sort_custom(func(a, b): return SystemDB.light_years(a) < SystemDB.light_years(b))
	return [SystemDB.SOL] + ids


func _add_systems(needle: String) -> void:
	var added := false
	for id in system_ids():
		var label := SystemDB.display_name(id)
		if not needle.is_empty() and not ("%s %s star system" % [label, id]).to_lower().contains(needle):
			continue
		if not added:
			_add_head("STAR SYSTEMS")
			added = true
		var ly := SystemDB.light_years(id)
		var row := _row("    %s   —  %s" % [label, "%.2f ly" % ly if ly > 0.0 else "home"])
		row.disabled = id == Ephemeris.system_id
		row.pressed.connect(_pick_system.bind(id))
		_list.add_child(row)


func _pick_system(id: String) -> void:
	_close()
	go_system(id)


func go_system(id: String) -> bool:
	if main == null:
		return false
	return main.travel_to(id, true)


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
	if ship == null or main == null or Ephemeris.system_id != Ephemeris.SOL_ID:
		return
	var body: String = site.body
	main._anchor_ship(body)
	var mode := str(site.get("mode", "surface"))
	var station: Dictionary = main.orbital_stations.state_for(str(site.get("station_id",""))) if mode == "station" else {}
	var body_basis: Basis = main.planets.surface_basis(body) if main.planets != null else Basis.IDENTITY
	match mode:
		"station":
			if station.is_empty(): return
			ship.relocate(station.position+station.position.normalized()*.4)
		"geo":
			ship.relocate(Ephemeris.geo_start_pos())
		"park":
			ship.relocate(Ephemeris.sweet_spot_off(body))
		_:
			var dir := DS.dir_for(float(site.lat_deg), float(site.lon_deg))
			var radius := Ephemeris.body_radius_km(body)
			var sampler: TerrainSampler = main.planets.terrain_sampler_for(body) \
				if main.planets != null else null
			var ground_r := sampler.ground_radius_km(dir, radius) if sampler != null else radius
			ship.relocate(body_basis * DS.surface_anchor_off(dir, ground_r, float(site.alt_km)))
	ship.velocity = station.velocity if mode == "station" else Vector3.ZERO
	ship.reset_mesh_pose()
	if mode == "station":
		ship.face_toward(station.position-ship.anchor_off)
	elif mode == "geo" or mode == "park":
		ship.face_toward(-ship.anchor_off)
	else:
		var dir2 := DS.dir_for(float(site.lat_deg), float(site.lon_deg))
		var fwd := DS.heading_forward(dir2, float(site.get("heading_deg", 0.0)))
		ship.transform.basis = Basis.looking_at(body_basis * fwd, body_basis * dir2)
		ship._cam_basis = ship.transform.basis
	ship.time_rate = 1.0
	ship._time_idx = 0
	ship._shell_edge_known = false
	ship.autopilot = false
	ship.auto_cruise = false
	ship._kill_turn_rates()
	ship._strafe = 0.0
	ship._lift = 0.0
	# Publish the destination before the next physics step. Old Earth terrain,
	# distances or exclusion geometry must never be applied to a Sun arrival.
	if main.planets != null:
		var planets: PlanetSystem = main.planets
		planets.refresh(ship.anchor_off, 0.0, ship.anchor_name, ship.velocity)
		ship.nearest_name = planets.nearest_name
		ship.nearest_dist = planets.nearest_dist
		ship.nearest_radius = planets.nearest_radius
		ship.nearest_dir = planets.nearest_dir
		ship.terrain = planets.terrain_sampler_for(planets.nearest_name)
		ship.set_terrain_frame(planets.surface_basis(planets.nearest_name), planets.surface_angle(planets.nearest_name))
		ship.last_newton_g = ship._newton_g()


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
		margin.add_theme_constant_override("margin_" + side, 28)
	_root.add_child(margin)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	margin.add_child(col)

	var header := HBoxContainer.new()
	col.add_child(header)
	_title = Label.new()
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title.add_theme_font_size_override("font_size", 26)
	_title.add_theme_color_override("font_color", Color(0.6, 1.0, 0.95))
	header.add_child(_title)
	_close_button = Button.new()
	_close_button.text = "CLOSE"
	_close_button.custom_minimum_size = Vector2(112, 48)
	_close_button.pressed.connect(_close)
	header.add_child(_close_button)

	_filter = LineEdit.new()
	_filter.placeholder_text = "Search star systems, planets and landmarks…"
	_filter.custom_minimum_size.y = 48
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
	close.text = "Choose a destination to jump there · Ctrl+P / Esc to close"
	close.add_theme_color_override("font_color", Color(0.7, 0.75, 0.85))
	col.add_child(close)
