class_name MapChart
extends Control
# DEPRECATED: replaced by MapView3D (Elite local+global 3D chart). Kept only so old refs compile.
# The interactive star-chart canvas (the heart of the Star Map). A real, zoomable, pannable
# map drawn entirely in _draw() — no per-star Button nodes, so it stays crisp at any zoom:
#   • LANES      — known wormhole links between systems (cyan).
#   • WORMHOLES  — a ◌ swirl icon at each known link's midpoint (animated).
#   • STARS      — a star icon per system, core tinted by spectral colour, ringed by travel
#                  state (here / discovered / nav / locked).
#   • PLANETS    — the selected system's worlds, as tiny dots ringed around its node.
#   • PLAYER     — a live, pulsing cursor at the system you're in ("you are here", but a real
#                  marker, not text).
# Each layer is toggleable (see `filters`, driven by StarMap's filter chips). Wheel zooms about
# the cursor; left-drag pans; a click (no drag) selects the nearest star → `star_clicked`.
# Hovering a star floats its name/state/distance. process_mode is ALWAYS (the map pauses the
# tree) so the player pulse + wormhole swirl animate live while you read the chart.

signal star_clicked(id: String)

const MAX_SPAN_LY := 150.0          # zoomed fully out, ~this many ly fit across the chart
const ZOOM_STEP := 1.18
const STAR_R := 5.0                  # star icon core radius (px)
const HIT_R := 13.0                  # click/hover pick radius around a star (px)
const PLANET_RING := 17.0           # px radius of the planet ring around a selected star

var main: Node
var view_system := ""               # which system is selected (its planets + label show)
var filters := { "stars": true, "wormholes": true, "planets": true, "lanes": true, "platforms": true }

var _zoom := 16.0                   # px per light-year
var _zoom_min := 1.5
var _zoom_max := 64.0
var _pan := Vector2.ZERO            # world (ly) point shown at the chart centre
var _t := 0.0                       # animation clock
var _dragging := false
var _press_pos := Vector2.ZERO
var _moved := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	_t += delta
	queue_redraw()                  # live pulse / swirl + hover


# Set sensible zoom limits + default once the control has its real size.
func init_view() -> void:
	var half: float = minf(size.x, size.y) * 0.5
	_zoom_min = half / (MAX_SPAN_LY * 0.5)
	_zoom = clampf(half / 17.0, _zoom_min, _zoom_max)


func center_on(id: String) -> void:
	_pan = SystemDB.galaxy_pos(id)
	queue_redraw()


# World (ly, equatorial projection) → chart-local px.
func _project(world: Vector2) -> Vector2:
	return size * 0.5 + (world - _pan) * _zoom


# ---------------------------------------------------------------------------
func _draw() -> void:
	if main == null:
		return
	var font := ThemeDB.fallback_font
	var ids: Array = SystemDB.all()

	if filters.lanes or filters.wormholes:
		_draw_lanes()

	# Planets of the selected system (tiny dots ringed around its node).
	if filters.planets and view_system != "":
		_draw_planets(view_system)

	# Stars.
	if filters.stars:
		for id in ids:
			_draw_star(font, id)

	# Platforms — a ⬡ badge on every system that carries a dockable space platform
	# (bright once you've reached it, dim otherwise). These are the station→station
	# teleport network, so seeing them on the map lets you plan jumps.
	if filters.platforms:
		for id in ids:
			if SystemDB.has_station(id):
				_draw_platform(id)

	# Player cursor — always on top, animated.
	_draw_player(font)

	# Hover read-out (only when not dragging).
	if not _dragging:
		_draw_hover(font)


func _draw_lanes() -> void:
	for e in SystemDB.wh_edges():
		var a: String = e[0]
		var b: String = e[1]
		if a == SystemDB.INTERSTELLAR or b == SystemDB.INTERSTELLAR:
			continue
		if not main.is_edge_known(a, b):
			continue
		var pa := _project(SystemDB.galaxy_pos(a))
		var pb := _project(SystemDB.galaxy_pos(b))
		if filters.lanes:
			draw_line(pa, pb, Color(0.45, 0.85, 1.0, 0.25), 1.5, true)
		if filters.wormholes:
			_draw_wormhole((pa + pb) * 0.5)


# A small animated wormhole swirl ◌.
func _draw_wormhole(p: Vector2) -> void:
	var pulse: float = 0.5 + 0.5 * sin(_t * 3.0)
	draw_arc(p, 5.0, 0, TAU, 18, Color(0.6, 0.5, 1.0, 0.5 + 0.4 * pulse), 1.5, true)
	draw_arc(p, 2.4, _t * 2.0, _t * 2.0 + TAU * 0.7, 12, Color(0.85, 0.7, 1.0, 0.9), 1.5, true)


func _draw_star(font: Font, id: String) -> void:
	var p := _project(SystemDB.galaxy_pos(id))
	if p.x < -HIT_R or p.x > size.x + HIT_R or p.y < -HIT_R or p.y > size.y + HIT_R:
		return
	var st: String = main.star_state(id)
	var ring := _state_col(st)
	var core: Color = SystemDB.star_color(id)
	# Sparkle spikes (gives the dot an "icon" read).
	var sp: Color = Color(ring.r, ring.g, ring.b, 0.5)
	for k in 4:
		var a := PI * 0.5 * k + PI * 0.25
		var d := Vector2(cos(a), sin(a))
		draw_line(p + d * (STAR_R + 1.0), p + d * (STAR_R + 4.0), sp, 1.0, true)
	draw_circle(p, STAR_R + 1.5, Color(ring.r, ring.g, ring.b, 0.85))   # state ring
	draw_circle(p, STAR_R, core)                                         # spectral core
	# Label the meaningful ones (here / discovered / selected) so a zoomed-out chart stays clean.
	if st == "here" or st == "discovered" or id == view_system:
		var txt := SystemDB.display_name(id)
		if st == "discovered":
			txt += "  ▸%.1f ly" % SystemDB.light_years(id)
		_label(font, p + Vector2(STAR_R + 4.0, -6.0), txt, ring)


func _draw_planets(id: String) -> void:
	var p := _project(SystemDB.galaxy_pos(id))
	if p.x < -PLANET_RING or p.x > size.x + PLANET_RING or p.y < -PLANET_RING or p.y > size.y + PLANET_RING:
		return
	var worlds := []
	for spec in SystemDB.bodies(id):
		if spec.get("star", false) or str(spec.name).contains("✦"):
			continue
		worlds.append(spec)
	if worlds.is_empty():
		return
	draw_arc(p, PLANET_RING, 0, TAU, 28, Color(0.5, 0.7, 0.9, 0.18), 1.0, true)   # orbit guide
	var n := worlds.size()
	for i in n:
		var a := TAU * float(i) / float(n) - PI * 0.5
		var pp := p + Vector2(cos(a), sin(a)) * PLANET_RING
		var col: Color = worlds[i].get("color", Color(0.7, 0.8, 0.9))
		draw_circle(pp, 2.6, col)


# A ⬡ platform badge, set just above-right of the star. Teal, bright if the system is
# known (reachable platform), dim if still locked.
func _draw_platform(id: String) -> void:
	var p := _project(SystemDB.galaxy_pos(id))
	if p.x < -HIT_R or p.x > size.x + HIT_R or p.y < -HIT_R or p.y > size.y + HIT_R:
		return
	var known: bool = main.star_state(id) != "locked"
	var col := Color(0.35, 1.0, 0.85, 0.95) if known else Color(0.35, 0.8, 0.7, 0.4)
	var c := p + Vector2(STAR_R + 7.0, -(STAR_R + 6.0))
	var pts := PackedVector2Array()
	for k in 7:                                   # 6 sides + close
		var a := PI / 6.0 + TAU * float(k % 6) / 6.0
		pts.append(c + Vector2(cos(a), sin(a)) * 4.2)
	draw_polyline(pts, col, 1.4, true)
	draw_circle(c, 1.2, col)                       # tiny core dot


# The player marker: a mouse-cursor arrow at the current system, with a live pulse halo.
func _draw_player(font: Font) -> void:
	var here: String = main.current_system
	var p := _project(SystemDB.galaxy_pos(here))
	var pulse: float = 0.5 + 0.5 * sin(_t * 4.0)
	draw_arc(p, 11.0 + 3.0 * pulse, 0, TAU, 28, Color(0.5, 1.0, 0.7, 0.5 - 0.3 * pulse), 2.0, true)
	# Cursor arrow (classic pointer), tip at the node, body down-right.
	var pts := PackedVector2Array([
		p, p + Vector2(0, 16), p + Vector2(4.5, 11.5), p + Vector2(8, 18),
		p + Vector2(11, 16.5), p + Vector2(7.5, 9.5), p + Vector2(13, 8)])
	draw_colored_polygon(pts, Color(0.6, 1.0, 0.8))
	var outline := pts.duplicate()
	outline.append(p)               # close the cursor outline back to the tip
	draw_polyline(outline, Color(0.05, 0.2, 0.12, 0.9), 1.0, true)
	_label(font, p + Vector2(15, 14), "YOU", Color(0.7, 1.0, 0.85))


func _draw_hover(font: Font) -> void:
	var m := get_local_mouse_position()
	if not Rect2(Vector2.ZERO, size).has_point(m):
		return
	var id := _pick(m)
	if id == "":
		return
	var st: String = main.star_state(id)
	var head := "%s — %s · %.1f ly" % [SystemDB.display_name(id), SystemDB.spectral(id), SystemDB.light_years(id)]
	var sub: String = { "here": "you are here", "discovered": "discovered · click to browse",
		"nav": "wormhole known · click to browse", "locked": "locked · click to browse" }.get(st, "")
	var p := _project(SystemDB.galaxy_pos(id)) + Vector2(10, -34)
	var w: float = maxf(font.get_string_size(head, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x,
		font.get_string_size(sub, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x) + 14.0
	p.x = clampf(p.x, 2.0, size.x - w - 2.0)
	p.y = clampf(p.y, 2.0, size.y - 36.0)
	draw_rect(Rect2(p, Vector2(w, 32)), Color(0.03, 0.06, 0.11, 0.92))
	draw_rect(Rect2(p, Vector2(w, 32)), Color(0.45, 0.85, 1.0, 0.5), false, 1.0)
	draw_string(font, p + Vector2(7, 13), head, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.9, 0.95, 1.0))
	draw_string(font, p + Vector2(7, 27), sub, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, _state_col(st))


func _label(font: Font, pos: Vector2, txt: String, col: Color) -> void:
	draw_string(font, pos + Vector2(1, 1), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0, 0, 0, 0.8))
	draw_string(font, pos, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, col)


# Nearest star to a chart-local point, within HIT_R; "" if none.
func _pick(at: Vector2) -> String:
	var best := HIT_R
	var hit := ""
	for id in SystemDB.all():
		var d: float = _project(SystemDB.galaxy_pos(id)).distance_to(at)
		if d < best:
			best = d
			hit = id
	return hit


func _state_col(st: String) -> Color:
	match st:
		"here":       return Color(0.5, 1.0, 0.6)
		"discovered": return Color(1.0, 0.78, 0.32)
		"nav":        return Color(0.45, 0.85, 1.0)
		_:            return Color(0.55, 0.6, 0.68)


# --- interaction ------------------------------------------------------------
func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			_zoom_at(event.position, ZOOM_STEP)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			_zoom_at(event.position, 1.0 / ZOOM_STEP)
		elif event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_dragging = true
				_moved = false
				_press_pos = event.position
			else:
				_dragging = false
				if not _moved:                       # a click, not a drag → select a star
					var id := _pick(event.position)
					if id != "":
						star_clicked.emit(id)
	elif event is InputEventMouseMotion and _dragging:
		if event.position.distance_to(_press_pos) > 4.0:
			_moved = true
		_pan -= event.relative / _zoom
		queue_redraw()


func _zoom_at(at: Vector2, factor: float) -> void:
	var before: Vector2 = _pan + (at - size * 0.5) / _zoom
	_zoom = clampf(_zoom * factor, _zoom_min, _zoom_max)
	var after: Vector2 = _pan + (at - size * 0.5) / _zoom
	_pan += before - after
	queue_redraw()


func span_ly() -> int:
	return int(size.x / _zoom)
