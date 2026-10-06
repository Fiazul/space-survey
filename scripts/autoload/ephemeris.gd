# Autoload singleton (registered as `Ephemeris` in project.godot). class_name dropped per ADR-0001.
extends Node
# Preloaded rather than referenced as global classes: autoloads resolve before
# the editor's class cache is guaranteed to be current, and the headless test
# runs have no cache at all.
const _ROT := preload("res://scripts/world/celestial_rotation.gd")
var rotation_clock := _ROT.new()

const _AF := preload("res://scripts/flight/anchor_frame.gd")
const _SOL := preload("res://scripts/world/sol_ephemeris.gd")
const _GEN := preload("res://scripts/world/generated_ephemeris.gd")
const _SYS := preload("res://scripts/world/system_ephemeris.gd")
# Real positions for every physical star system, one SystemEphemeris per star
# (docs/adr/0002). Sol is SolEphemeris (JPL/NASA, geocentric: Earth at the
# origin); other physical systems are GeneratedEphemeris (star at the origin).
# Every public call below answers for the CURRENT system; switch_system swaps it.
# Authored arcade systems keep Sol current, exactly as before, until slice 2.
#
# SCALE: 1 scene unit = 1 kilometre in every physical system.

const KM_PER_AU := _SOL.KM_PER_AU
const AU_TO_UNITS := KM_PER_AU          # 1 unit = 1 km
const EARTH_RADIUS_KM := _SOL.EARTH_RADIUS_KM
const SUN_RADIUS_KM := _SOL.SUN_RADIUS_KM
const GEO_RADIUS_KM := _SOL.GEO_RADIUS_KM
const MIN_STELLAR_PARK_PERIOD_S := 60.0
const GM_EARTH := _SOL.GM_EARTH
const GM_SUN := _SOL.GM_SUN
const GM_MOON := _SOL.GM_MOON
const GM_MERCURY := _SOL.GM_MERCURY
const GM_VENUS := _SOL.GM_VENUS
const GM_MARS := _SOL.GM_MARS
const GM_JUPITER := _SOL.GM_JUPITER
const GM_SATURN := _SOL.GM_SATURN
const GM_URANUS := _SOL.GM_URANUS
const GM_NEPTUNE := _SOL.GM_NEPTUNE
const MOON_RADIUS_KM := _SOL.MOON_RADIUS_KM
const MERCURY_RADIUS_KM := _SOL.MERCURY_RADIUS_KM
const VENUS_RADIUS_KM := _SOL.VENUS_RADIUS_KM
const MARS_RADIUS_KM := _SOL.MARS_RADIUS_KM
const JUPITER_RADIUS_KM := _SOL.JUPITER_RADIUS_KM
const SATURN_RADIUS_KM := _SOL.SATURN_RADIUS_KM
const URANUS_RADIUS_KM := _SOL.URANUS_RADIUS_KM
const NEPTUNE_RADIUS_KM := _SOL.NEPTUNE_RADIUS_KM
const EARTH_ATMO_TOP_KM := _SOL.EARTH_ATMO_TOP_KM
const ATMO_TOP_KM := _SOL.ATMO_TOP_KM
const EARTH_SPIN_RAD_S := _SOL.EARTH_SPIN_RAD_S
const MOON_SPIN_RAD_S := _SOL.MOON_SPIN_RAD_S
const SUN_SPIN_RAD_S := _SOL.SUN_SPIN_RAD_S
const PLANETS := _SOL.PLANETS
const PHYSICAL_MOONS := _SOL.PHYSICAL_MOONS
const STARS := _SOL.STARS
# Earth's measured density profile — the one drag curve. Ship._newton_atmo_drag
# applies it wherever FlightMode.has_drag_model says so: Earth in Sol, and any
# generated world whose recipe air_amount > 0, measured from that world's own
# radius and atmo_top_km. Same numbers everywhere.
const EARTH_ATMO_H_KM := 8.5            # density scale height
const RHO0 := 1.225                     # kg/m³ at sea level

# No landing — but you die on CONTACT with terrain, not at an altitude.
#
# This replaced a 29 km bubble (EARTH_MIN_R_KM = 6400, kill = 6400 - 6371) plus a
# 100 m floor for everything else. That rule killed you at a fixed radius from the
# centre regardless of what was under you: the Pacific and the summit of Everest
# were equally lethal at the same altitude, and Earth could never show ground at
# all, because the bubble sat 29 km above it.
#
# Now: TerrainSampler computes the ground beneath your own position, and the kill
# fires when the hull is within this margin of it. 20 m is under the hull's own
# size and 60x the mesh's float32 quantisation (~0.32 m at these radii), so the
# mesh can never make it fire early.
const CONTACT_KILL_FLOOR_KM := 0.02
const SURFACE_KILL_SECS := 2.2
# Extra kilometres above the body's base kill, by name. Gravity can raise this later.
var surface_kill_extra_km := {}
# Sky impostors sit BEHIND every in-range cook mesh, still inside the far plane.
# A body is opaque: you never see the Sun or the HYG field through it.
# 160,000 km was in front of the Moon (~354,000 km from GEO) and any mesh in
# the 160–442k band, so the Sun painting drew through those worlds.
const SKY_SHELL_KM := 500000.0
const SKY_STAR_KM := 510000.0
# Camera projection is a flat plane through a spherical star shell. Keep a
# generous margin or the forward cap clips into a circle that follows the view.
const CAM_RENDER_FAR_KM := SKY_STAR_KM * 2.0
# Far enough that the Moon (≈384,000 km) is a real cook ball from GEO, not a
# clipped 0.5° stamp. Meshes cut over at 0.85 × this; impostors stay behind that.
const CAM_FAR_SOL := 520000.0
const STAR_SHELL_RADIUS := SKY_STAR_KM
const SUN_ANG_RADIUS_DEG := 0.266       # real solar angular radius from 1 AU

const SOL_ID := "sol"
var _sol: _SOL = _SOL.new()
var _sys: _SYS = _sol
var _systems := { SOL_ID: _sol }
var system_id := SOL_ID
var primary_star: String:
	get:
		return _sys.primary_star

var _idx := 0           # which catalog body we're currently fetching
var _http: HTTPRequest
var live := false   # true once any live position has landed (HUD can show it)


func _ready() -> void:
	rotation_clock.unix_s = Time.get_unix_time_from_system()
	_sol.seed_fallback()
	if _sol.load_cache() and _sol.cache_complete():
		live = true
		return
	_fetch_all()


# --- systems -----------------------------------------------------------------
func _system_db():
	return load("res://scripts/autoload/system_db.gd")


# The ephemeris for a star system, built once per session from its star row.
# An id with no catalogue row (the deep-space hub) answers with Sol.
func system_for(id: String) -> _SYS:
	if _systems.has(id):
		return _systems[id]
	var row: Dictionary = _system_db().star_row(id)
	if row.is_empty():
		return _sol
	var e: _SYS = _GEN.build(id, row, rotation_clock.unix_s)
	_systems[id] = e
	return e


func switch_system(id: String) -> void:
	var changed := id != system_id
	system_id = id
	_sys = system_for(id)
	if changed and _sys is _GEN:
		(_sys as _GEN).place_at(rotation_clock.unix_s)


func current() -> _SYS:
	return _sys


func spawn_body() -> String:
	return _sys.spawn_body


func live_worlds() -> Array:
	return _sys.live_worlds()


# Every world that actually pulls, with its mu resolved once. Ship._newton_g runs
# this list per substep, so it must not allocate or re-scan the catalog.
func gravity_bodies() -> Array:
	return _sys.gravity_bodies()


# --- public: real position in SCENE units (Y-up), current system's frame ------
func scene_pos(name: String) -> Vector3:
	return _sys.scene_pos(name)


# The 64-bit scene-km position of a body. Ship/PlanetSystem anchor arithmetic
# goes through this, never through scene_pos (see docs/adr/0002).
func pos64(name: String) -> PackedFloat64Array:
	return _sys.pos64(name)


func has_pos(name: String) -> bool:
	return _sys.has_pos(name)


# True for a physical body the ship's Newton frame may anchor to. False for
# craft (Voyager 1/2 drift at 5 km/s; anchoring there clamps the ship at a
# moving point while the render drifts away — see docs/adr/0002 finding 3).
func is_anchorable(name: String) -> bool:
	return _sys.is_anchorable(name)


# `body` seen from `anchor`'s centre, in km. Subtracted in doubles, then packed —
# the ONE sanctioned way to ask where one body is relative to another.
func rel_km(body_name: String, anchor: String) -> Vector3:
	return _sys.rel_km(body_name, anchor)


func is_star(body_name: String) -> bool:
	return _sys.is_star(body_name)


func has_drag_air(body_name: String) -> bool:
	return _sys.has_drag_air(body_name)


# Star direction*radius on the backdrop shell (real RA/Dec, fixed radius).
const UNITS_PER_LY := 63241.077 * AU_TO_UNITS   # real interstellar scale


# Closer real bodies sit slightly closer on the impostor shell so a transit occludes.
static func sky_impostor_km(real_dist_km: float) -> float:
	var span: float = SKY_STAR_KM - SKY_SHELL_KM
	var t: float = 1.0 - 1.0 / (1.0 + maxf(real_dist_km, 0.0) / AU_TO_UNITS)
	return SKY_SHELL_KM + span * 0.85 * t


# Mesh cut is the near face, not the centre. A star bigger than the far plane
# still becomes a cook ball once that face sits inside CAM_FAR * 0.85.
static func physical_too_far(dist: float, radius: float) -> bool:
	return dist - maxf(radius, 0.0) > CAM_FAR_SOL * 0.85


static func show_physical_mesh(dist: float, radius: float) -> bool:
	return dist > 0.001 and not physical_too_far(dist, radius)


static func show_sky_impostor(dist: float, radius: float) -> bool:
	return dist > 0.001 and physical_too_far(dist, radius)


# Sunlit park above the system's spawn body, as an offset from its centre. Sol:
# GEO over Earth's day side, so Earth is lit and the Sun is behind the camera.
func spawn_pos() -> Vector3:
	var star := rel_km(primary_star, spawn_body())
	if star.length_squared() < 0.0001:
		return Vector3(0.0, 0.0, _sys.spawn_park_km())
	return star.normalized() * _sys.spawn_park_km()


func geo_start_pos() -> Vector3:
	return spawn_pos()

func star_scene_pos(star: Dictionary) -> Vector3:
	var ra := _hms_deg(star.ra) * PI / 180.0
	var dec := _dms_deg(star.dec) * PI / 180.0
	var eq := Vector3(cos(dec) * cos(ra), cos(dec) * sin(ra), sin(dec))
	return Vector3(eq.x, eq.z, eq.y) * STAR_SHELL_RADIUS

# Real galaxy position at the star's TRUE distance (a floating-origin destination
# you can actually fly to — the distance counts down as you approach).
func star_true_pos(star: Dictionary) -> Vector3:
	return star_scene_pos(star).normalized() * (float(star.ly) * UNITS_PER_LY)


func _hms_deg(hms: Array) -> float:
	return (float(hms[0]) + float(hms[1]) / 60.0 + float(hms[2]) / 3600.0) * 15.0

func _dms_deg(dms: Array) -> float:
	var sign := -1.0 if (float(dms[0]) < 0.0 or float(dms[1]) < 0.0 or float(dms[2]) < 0.0) else 1.0
	return sign * (abs(float(dms[0])) + abs(float(dms[1])) / 60.0 + abs(float(dms[2])) / 3600.0)



# --- live JPL Horizons fetch (serial; Horizons throttles parallel requests) --
func _fetch_all() -> void:
	_http = HTTPRequest.new()
	add_child(_http)
	_http.request_completed.connect(_on_reply)
	_idx = 0
	_fetch_next()


# Physical air column above the skin. 0 = vacuum.
func atmo_top_km(body_name: String) -> float:
	return _sys.atmo_top_km(body_name)


# Where the hull is vs this body. Used by the tape so flight is readable.
# CENTER inside 15% of radius · INSIDE below the skin · SKIN kill band · AIR · SPACE
func flight_zone(body_name: String, dist_km: float) -> String:
	var rad := body_radius_km(body_name)
	if rad <= 0.0:
		return "SPACE"
	if dist_km < rad * 0.15:
		return "CENTER"
	var alt := dist_km - rad
	if alt < 0.0:
		return "INSIDE"
	# SPHERE-relative, deliberately. The contact kill measures from the terrain
	# beneath the hull (TerrainSampler + main._update_skin_kill), so over Everest
	# this can still say AIR at the moment you crash. Ephemeris is an autoload with
	# no terrain dependency by design, and the kill - not this label - is
	# authoritative. tools/test_newton.gd asserts the discrepancy so it cannot be
	# mistaken for correctness.
	if alt <= surface_kill_km(body_name):
		return "SKIN"
	var air := atmo_top_km(body_name)
	if air > 0.0 and alt < air:
		return "AIR"
	return "SPACE"


# Contact margin: how close the hull may get to the ground BELOW IT before that
# is a crash. Not an altitude above the sphere any more — see
# CONTACT_KILL_FLOOR_KM. Every world uses the same margin; gravity or a hull
# upgrade can still widen one through surface_kill_extra_km.
func surface_kill_km(body_name: String = "") -> float:
	var extra := maxf(float(surface_kill_extra_km.get(body_name, 0.0)), 0.0)
	return CONTACT_KILL_FLOOR_KM + extra



# Safe park after a skin kill. Spawn body or star → the spawn park. Other worlds → sunward high park.
func sweet_spot(body_name: String = "") -> Vector3:
	if body_name == "" or body_name == spawn_body() or body_name == primary_star:
		return scene_pos(spawn_body()) + geo_start_pos()
	var bpos := scene_pos(body_name)
	var rad := body_radius_km(body_name)
	if rad <= 0.0:
		return scene_pos(spawn_body()) + geo_start_pos()
	# Park clear of the BAND, not clear of the old 29 km bubble. kill * 4 would now
	# be 80 m, which would respawn you inside the terrain you just died on.
	return bpos + sweet_spot_off(body_name)


# The same park as sweet_spot(), expressed as an offset from that body's centre —
# the form the ship's anchored state actually wants (docs/adr/0002).
func sweet_spot_off(body_name: String) -> Vector3:
	var rad := body_radius_km(body_name)
	if rad <= 0.0:
		return Vector3.ZERO
	var park := rad + maxf(atmo_top_km(body_name) * 1.5, 120.0)
	# The generic +120 km park is a 28 g trap at the Sun: even boosted
	# 3 g engines cannot climb out. At 4 stellar radii ordinary thrust can leave.
	if body_name == primary_star:
		# Compact-star inspection must remain stable with the ship's 0.25 s substeps.
		var period_floor := pow(gm(body_name) * pow(MIN_STELLAR_PARK_PERIOD_S / TAU, 2.0), 1.0 / 3.0)
		park = maxf(rad * 4.0, period_floor)
	var out: Vector3 = -rel_km(primary_star, body_name)
	if out.length_squared() < 0.0001:
		out = Vector3(1.0, 0.0, 0.0)
	return out.normalized() * park


func body_radius_km(body_name: String) -> float:
	return _sys.body_radius_km(body_name)


func surface_basis(body_name: String) -> Basis:
	return _ROT.basis_at(body_name, spin_rad_s(body_name), rotation_clock.unix_s)

func surface_angle(body_name: String) -> float:
	return _ROT.angle_at(body_name, spin_rad_s(body_name), rotation_clock.unix_s)

func solar_state(body_name: String, local_direction: Vector3) -> Dictionary:
	var sun := surface_basis(body_name).inverse()*rel_km(primary_star,body_name).normalized()
	var longitude := atan2(local_direction.z,local_direction.x)
	var sun_longitude := atan2(sun.z,sun.x)
	var hour := fposmod(12.0+(longitude-sun_longitude)*12.0/PI,24.0)
	var elevation := rad_to_deg(asin(clampf(local_direction.normalized().dot(sun),-1.0,1.0)))
	return {"hour":hour,"elevation":elevation,"phase":"DAY" if elevation > 0 else ("TWILIGHT" if elevation > -6 else "NIGHT")}

func scene_spin_rad_s(body_name: String) -> float:
	# Transport the surface frame at the same rate as visual rotation. This
	# never changes the integration delta used for gravity, thrust or weapons.
	return -_sys.visual_spin_rad_s(body_name) * rotation_clock.rate


func spin_rad_s(body_name: String) -> float:
	return _sys.spin_rad_s(body_name)


func gm(body_name: String) -> float:
	return _sys.gm(body_name)


# The live fetch always writes Sol, whichever system is current.
func _fetch_next() -> void:
	var cat: Array = _sol.catalog()
	if _idx >= cat.size():
		_sol.save_cache()
		if _http:
			_http.queue_free()
		return
	var body: Dictionary = cat[_idx]
	if body.get("fixed", false) or not body.has("id"):
		_idx += 1
		_fetch_next()
		return
	var err := _http.request(_sol.url_for(str(body.id)))
	if err != OK:
		push_warning("Ephemeris: request failed for %s (using fallback)" % body.name)
		_idx += 1
		_fetch_next()


func _on_reply(_result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	var cat: Array = _sol.catalog()
	if code == 200:
		var eq = _SOL.parse_vectors(body.get_string_from_utf8())
		if eq != null and _idx < cat.size():
			_sol.store_pos(str(cat[_idx].name), eq[0], eq[1], eq[2])
			_sol.rebuild_gravity()
			live = true
	_idx += 1
	_fetch_next()
