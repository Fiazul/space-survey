# Autoload singleton (registered as `Ephemeris` in project.godot). class_name dropped per ADR-0001.
extends Node
# REAL positions for Cold Light. Earth is the anchor at the scene origin (0,0,0) —
# every coordinate here is GEOCENTRIC, the frame NASA RA/Dec are measured in.
#
# Two kinds of body, two truths:
#   • Sun + planets MOVE day-to-day -> fetched LIVE from JPL Horizons (keyless)
#     for the real current date, so you fly today's real sky. If the net is down
#     we fall back to baked constants that were verified against Horizons to 4
#     decimals (see tools/real_positions.py).
#   • Stars don't visibly move over years -> the J2000 catalog below IS today's
#     real star sky. Placed by real RA/Dec/parallax-distance.
#
# Frame: ICRS / J2000 equatorial, AU. Scene mapping (Godot, Y-up):
#     scene = Vector3(eq.x, eq.z, eq.y) * AU_TO_UNITS   (celestial north = +Y)
#
# SCALE: 1 scene unit = 1 kilometre. Distances stay real (JPL AU × this).
# Sol slice 1 uses this so Earth and the Sun have physical radii. Other systems
# still use their authored local layouts (they do not go through scene_pos).

const KM_PER_AU := 149597870.7
const AU_TO_UNITS := KM_PER_AU          # 1 unit = 1 km
const EARTH_RADIUS_KM := 6371.0
const SUN_RADIUS_KM := 695700.0          # IAU nominal solar radius
const GEO_RADIUS_KM := 42157.0          # geostationary, from Earth's centre
# Standard gravitational parameters (km³/s²). Accel = GM / r² in scene units.
const GM_EARTH := 398600.4418
const GM_SUN := 132712440018.0
const GM_MOON := 4902.8
const GM_MERCURY := 22031.7
const GM_VENUS := 324858.6
const GM_MARS := 42828.4
const GM_JUPITER := 126686534.9
const GM_SATURN := 37931206.2
const GM_URANUS := 5793951.3
const GM_NEPTUNE := 6835107.3
const MOON_RADIUS_KM := 1737.4
const MERCURY_RADIUS_KM := 2439.7
const VENUS_RADIUS_KM := 6051.8
const MARS_RADIUS_KM := 3389.5
const JUPITER_RADIUS_KM := 69911.0
const SATURN_RADIUS_KM := 58232.0
const URANUS_RADIUS_KM := 25362.0
const NEPTUNE_RADIUS_KM := 24622.0
const EARTH_ATMO_TOP_KM := 100.0        # Karman; drag is zero above this
# Real air column above the 1-bar / solid skin (km). 0 = vacuum. Drag/co-rotate stay Earth-only.
const ATMO_TOP_KM := {
	"Earth": 100.0,
	"Venus": 250.0,
	"Mars": 80.0,
	"Titan": 600.0,
	"Jupiter": 400.0,
	"Saturn": 700.0,
	"Uranus": 300.0,
	"Neptune": 300.0,
}
const EARTH_ATMO_H_KM := 8.5            # density scale height
const RHO0 := 1.225                     # kg/m³ at sea level
# Sidereal spins (rad/s). Honest. In air the ship co-rotates, so you do not
# see the ground race. From GEO a day is still a day — a slow crawl at most.
const EARTH_SPIN_RAD_S := 7.292115e-5   # 1 turn / 86164 s
const MOON_SPIN_RAD_S := 2.6617e-6
const MERCURY_SPIN_RAD_S := 1.24001e-6
const VENUS_SPIN_RAD_S := -2.9926e-7    # retrograde
const MARS_SPIN_RAD_S := 7.0882e-5
const JUPITER_SPIN_RAD_S := 1.7585e-4
const SATURN_SPIN_RAD_S := 1.6378e-4
const URANUS_SPIN_RAD_S := -1.0124e-4
const NEPTUNE_SPIN_RAD_S := 1.083e-4
const SUN_SPIN_RAD_S := 2.9e-6
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

# Sol bodies use physical radii (km). Positions stay real (JPL AU × AU_TO_UNITS).
# eq = geocentric equatorial XYZ in AU (verified fallback for 2026-06-12).
# Optional "model" = a GLB the dot resolves into up close. "glow" = self-illum
# energy (no scene lights). Earth is the origin anchor; the Sun wears star.glb,
# which is also reused for every star (see PlanetSystem).
const PLANETS := [
	# Mean radii (km). Mass Earth=1. Positions geocentric AU (live JPL, else this fallback).
	{ "name": "Earth",   "id": "399", "eq": Vector3(0, 0, 0),               "radius": EARTH_RADIUS_KM, "mass": 1.0,      "color": Color(0.169, 0.510, 0.788), "model": "res://assets/earth.glb", "glow": 0.12, "fixed": true, "physical": true },
	{ "name": "Sun",     "id": "10",  "eq": Vector3( 0.1640,  0.9194,  0.3985), "radius": SUN_RADIUS_KM, "mass": 333000.0, "color": Color(1.00, 0.85, 0.30), "star": true, "model": "res://assets/sol.obj", "glow": 2.0, "physical": true },
	{ "name": "Moon",    "id": "301", "eq": Vector3( 0.0020,  0.0014,  0.0008), "radius": MOON_RADIUS_KM, "mass": 0.0123, "color": Color(0.78, 0.78, 0.80), "glow": 0.08, "physical": true, "parent": "Earth" },
	{ "name": "Mercury", "id": "199", "eq": Vector3(-0.2269,  0.7801,  0.3646), "radius": MERCURY_RADIUS_KM, "mass": 0.055, "color": Color(0.533, 0.533, 0.533), "physical": true },
	{ "name": "Venus",   "id": "299", "eq": Vector3(-0.5535,  0.9404,  0.4534), "radius": VENUS_RADIUS_KM, "mass": 0.815, "color": Color(0.890, 0.831, 0.714), "physical": true },
	{ "name": "Mars",    "id": "499", "eq": Vector3( 1.4583,  1.4672,  0.6149), "radius": MARS_RADIUS_KM, "mass": 0.107, "color": Color(0.737, 0.353, 0.263), "physical": true },
	{ "name": "Jupiter", "id": "599", "eq": Vector3(-2.6447,  4.9896,  2.2115), "radius": JUPITER_RADIUS_KM, "mass": 317.8, "color": Color(0.690, 0.498, 0.208), "physical": true },
	{ "name": "Saturn",  "id": "699", "eq": Vector3( 9.5512,  2.1483,  0.5020), "radius": SATURN_RADIUS_KM, "mass": 95.2, "color": Color(0.886, 0.749, 0.490), "ring": true, "physical": true },
	{ "name": "Uranus",  "id": "799", "eq": Vector3( 9.4808, 16.6122,  7.1397), "radius": URANUS_RADIUS_KM, "mass": 14.5, "color": Color(0.294, 0.439, 0.867), "physical": true },
	{ "name": "Neptune", "id": "899", "eq": Vector3(30.0174,  2.1421,  0.1558), "radius": NEPTUNE_RADIUS_KM, "mass": 17.1, "color": Color(0.153, 0.275, 0.529), "physical": true },
	{ "name": "Pluto",   "id": "999", "eq": Vector3(12.50, -31.20, 4.10), "radius": 1188.3, "mass": 0.00218, "color": Color(0.72, 0.60, 0.48), "physical": true },
	# The Voyagers — real interstellar probes, fetched LIVE from Horizons (spacecraft
	# IDs -31 / -32, same geocentric frame as the planets). The eq fallbacks are their
	# approximate 2026 positions (~160 / ~136 AU out) so they appear even offline. We
	# respect them: they sit at their true coordinates and get a safe-zone speed limit.
	# drift = constant outward speed (units/s). Real V1≈17.0 km/s, V2≈15.4 km/s are
	# microscopic at this scale, so these are visible speeds keeping the real ratio.
	{ "name": "Voyager 1", "id": "-31", "eq": Vector3(-33.2, -155.9, 33.9),  "radius": 8.0, "mass": 8000.0, "color": Color(0.82, 0.86, 0.92), "model": "res://assets/Space probe.glb", "glow": 0.1, "craft": true, "drift": 5.0 },
	{ "name": "Voyager 2", "id": "-32", "eq": Vector3(39.0, -67.6, -111.4),  "radius": 8.0, "mass": 8000.0, "color": Color(0.82, 0.86, 0.92), "model": "res://assets/Space probe.glb", "glow": 0.1, "craft": true, "drift": 4.5 },
]

# Arcade moons (authored systems). Sol uses PHYSICAL_MOONS at 1:1 instead.
const MOONS := [
	{ "name": "Moon",     "parent": "Earth",   "radius": 1.6, "mass": 0.0123, "orbit_r": 16.0, "orbit_speed": 0.45, "color": Color(0.78, 0.78, 0.80) },
	{ "name": "Phobos",   "parent": "Mars",    "radius": 0.5, "mass": 0.0000000018,  "orbit_r": 7.0,  "orbit_speed": 1.10, "color": Color(0.42, 0.40, 0.38) },
	{ "name": "Deimos",   "parent": "Mars",    "radius": 0.35,"mass": 0.00000000025, "orbit_r": 11.0, "orbit_speed": 0.55, "color": Color(0.46, 0.44, 0.41) },
	{ "name": "Io",       "parent": "Jupiter", "radius": 1.4, "mass": 0.015,  "orbit_r": 34.0, "orbit_speed": 0.80, "color": Color(0.95, 0.90, 0.50) },
	{ "name": "Europa",   "parent": "Jupiter", "radius": 1.3, "mass": 0.008,  "orbit_r": 45.0, "orbit_speed": 0.62, "color": Color(0.90, 0.88, 0.82) },
	{ "name": "Ganymede", "parent": "Jupiter", "radius": 1.8, "mass": 0.025,  "orbit_r": 57.0, "orbit_speed": 0.46, "color": Color(0.70, 0.64, 0.56) },
	{ "name": "Callisto", "parent": "Jupiter", "radius": 1.7, "mass": 0.018,  "orbit_r": 70.0, "orbit_speed": 0.34, "color": Color(0.50, 0.46, 0.44) },
	{ "name": "Titan",    "parent": "Saturn",  "radius": 1.7, "mass": 0.0225, "orbit_r": 42.0, "orbit_speed": 0.50, "color": Color(0.92, 0.66, 0.30) },
]

# Sol 1:1 moons. Real radii (km), real sma (km), Horizons ids. Positions are
# live JPL when the net is up; fallback is parent + sma in the equatorial plane.
# Moon itself already lives in PLANETS (id 301).
const PHYSICAL_MOONS := [
	{ "name": "Phobos",   "id": "401", "parent": "Mars",    "sma_km": 9376.0,    "radius": 11.08,  "mass": 1.8e-9,  "mu": 0.00071, "spin": 0.000228, "color": Color(0.42, 0.40, 0.38), "physical": true },
	{ "name": "Deimos",   "id": "402", "parent": "Mars",    "sma_km": 23463.0,   "radius": 6.2,    "mass": 2.5e-10, "mu": 0.00010, "spin": 0.0000576,"color": Color(0.46, 0.44, 0.41), "physical": true },
	{ "name": "Io",       "id": "501", "parent": "Jupiter", "sma_km": 421700.0,  "radius": 1821.6, "mass": 0.015,    "mu": 5959.9,   "spin": 0.0000411,"color": Color(0.95, 0.90, 0.50), "physical": true },
	{ "name": "Europa",   "id": "502", "parent": "Jupiter", "sma_km": 671034.0,  "radius": 1560.8, "mass": 0.008,    "mu": 3202.7,   "spin": 0.0000205,"color": Color(0.90, 0.88, 0.82), "physical": true },
	{ "name": "Ganymede", "id": "503", "parent": "Jupiter", "sma_km": 1070412.0, "radius": 2634.1, "mass": 0.025,    "mu": 9887.8,   "spin": 0.0000102,"color": Color(0.70, 0.64, 0.56), "physical": true },
	{ "name": "Callisto", "id": "504", "parent": "Jupiter", "sma_km": 1882709.0, "radius": 2410.3, "mass": 0.018,    "mu": 7179.3,   "spin": 0.00000436,"color": Color(0.50, 0.46, 0.44), "physical": true },
	{ "name": "Mimas",    "id": "601", "parent": "Saturn",  "sma_km": 185539.0,  "radius": 198.2,  "mass": 0.0000063,"mu": 2.5,     "spin": 0.0000770,"color": Color(0.72, 0.70, 0.66), "physical": true },
	{ "name": "Enceladus","id": "602", "parent": "Saturn",  "sma_km": 237948.0,  "radius": 252.1,  "mass": 0.000018, "mu": 7.2,     "spin": 0.0000531,"color": Color(0.92, 0.93, 0.94), "physical": true },
	{ "name": "Tethys",   "id": "603", "parent": "Saturn",  "sma_km": 294619.0,  "radius": 531.0,  "mass": 0.000103, "mu": 41.2,    "spin": 0.0000386,"color": Color(0.80, 0.80, 0.78), "physical": true },
	{ "name": "Dione",    "id": "604", "parent": "Saturn",  "sma_km": 377396.0,  "radius": 561.4,  "mass": 0.000183, "mu": 73.1,    "spin": 0.0000266,"color": Color(0.74, 0.73, 0.70), "physical": true },
	{ "name": "Rhea",     "id": "605", "parent": "Saturn",  "sma_km": 527108.0,  "radius": 763.8,  "mass": 0.000386, "mu": 153.9,   "spin": 0.0000161,"color": Color(0.70, 0.68, 0.64), "physical": true },
	{ "name": "Titan",    "id": "606", "parent": "Saturn",  "sma_km": 1221870.0, "radius": 2574.7, "mass": 0.0225,   "mu": 8978.1,   "spin": 0.00000456,"color": Color(0.92, 0.66, 0.30), "physical": true },
	{ "name": "Iapetus",  "id": "608", "parent": "Saturn",  "sma_km": 3560820.0, "radius": 734.5,  "mass": 0.000302, "mu": 120.5,   "spin": 0.00000092,"color": Color(0.55, 0.42, 0.32), "physical": true },
	{ "name": "Miranda",  "id": "705", "parent": "Uranus",  "sma_km": 129902.0,  "radius": 235.8,  "mass": 0.000011, "mu": 4.4,     "spin": 0.0000515,"color": Color(0.62, 0.60, 0.58), "physical": true },
	{ "name": "Ariel",    "id": "701", "parent": "Uranus",  "sma_km": 190900.0,  "radius": 578.9,  "mass": 0.000226, "mu": 86.5,    "spin": 0.0000289,"color": Color(0.70, 0.68, 0.66), "physical": true },
	{ "name": "Umbriel",  "id": "702", "parent": "Uranus",  "sma_km": 266000.0,  "radius": 584.7,  "mass": 0.00020,  "mu": 81.5,    "spin": 0.0000176,"color": Color(0.40, 0.38, 0.36), "physical": true },
	{ "name": "Titania",  "id": "703", "parent": "Uranus",  "sma_km": 436300.0,  "radius": 788.4,  "mass": 0.00059,  "mu": 228.2,   "spin": 0.00000836,"color": Color(0.58, 0.52, 0.48), "physical": true },
	{ "name": "Oberon",   "id": "704", "parent": "Uranus",  "sma_km": 583519.0,  "radius": 761.4,  "mass": 0.00050,  "mu": 205.3,   "spin": 0.00000541,"color": Color(0.52, 0.46, 0.42), "physical": true },
	{ "name": "Triton",   "id": "801", "parent": "Neptune", "sma_km": 354759.0,  "radius": 1353.4, "mass": 0.00358,  "mu": 1428.5,   "spin": 0.0000124,"color": Color(0.72, 0.68, 0.62), "physical": true },
	{ "name": "Charon",   "id": "901", "parent": "Pluto",   "sma_km": 19591.0,   "radius": 606.0,  "mass": 0.00026,  "mu": 105.9,   "spin": 0.0000114,"color": Color(0.62, 0.55, 0.50), "physical": true },
]

# Real nearby stars (J2000): RA(h,m,s), Dec(d,m,s), distance(ly). HYG/SIMBAD.
# color ~ real spectral type.
const STARS := [
	# mass = real stellar mass in EARTH masses (≈ solar × 333000) — drives the size of
	# the force-slow zone as you approach (heavier star = stronger, wider slow).
	{ "name": "Proxima Centauri", "ra": [14,29,42.9], "dec": [-62,40,46], "ly": 4.2465, "mass": 40000.0,  "color": Color(1.0, 0.60, 0.42) },
	{ "name": "Alpha Centauri",   "ra": [14,39,36.5], "dec": [-60,50, 2], "ly": 4.3650, "mass": 366000.0, "color": Color(1.0, 0.95, 0.82) },
	{ "name": "Barnard's Star",   "ra": [17,57,48.5], "dec": [  4,41,36], "ly": 5.9630, "mass": 48000.0,  "color": Color(1.0, 0.65, 0.45) },
	{ "name": "Wolf 359",         "ra": [10,56,29.2], "dec": [  7, 0,53], "ly": 7.8560, "mass": 30000.0,  "color": Color(1.0, 0.55, 0.40) },
	{ "name": "Lalande 21185",    "ra": [11, 3,20.2], "dec": [ 35,58,12], "ly": 8.3070, "mass": 130000.0, "color": Color(1.0, 0.70, 0.50) },
	{ "name": "Sirius",           "ra": [ 6,45, 8.9], "dec": [-16,42,58], "ly": 8.6110, "mass": 686000.0, "color": Color(0.80, 0.90, 1.0) },
	{ "name": "Epsilon Eridani",  "ra": [ 3,32,55.8], "dec": [ -9,27,30], "ly": 10.475, "mass": 270000.0, "color": Color(1.0, 0.85, 0.60) },
	{ "name": "Tau Ceti",         "ra": [ 1,44, 4.1], "dec": [-15,56,15], "ly": 11.912, "mass": 261000.0, "color": Color(1.0, 0.95, 0.85) },
]

const _CACHE_PATH := "user://ephemeris_cache.json"
const _HOST := "https://ssd.jpl.nasa.gov/api/horizons.api"

# Live geocentric eq-AU positions, keyed by name. Seeded from the verified
# fallback so the scene is correct from frame 1; patched as Horizons replies.
var _pos := {}
var _today := ""
var _idx := 0           # which catalog body we're currently fetching
var _http: HTTPRequest
var live := false   # true once any live position has landed (HUD can show it)
var _catalog: Array = []
var _cached_names := {}
var _mu_extra := {}
var _spin_extra := {}
var _radius_extra := {}


func live_worlds() -> Array:
	var out := []
	out.append_array(PLANETS)
	out.append_array(PHYSICAL_MOONS)
	return out


func _catalog_num(body_name: String, key: String, fallback: float) -> float:
	for p in live_worlds():
		if str(p.name) == body_name and p.has(key):
			return float(p[key])
	return fallback


func _ready() -> void:
	_catalog = live_worlds()
	for p in PLANETS:
		_pos[p.name] = p.eq
	for m in PHYSICAL_MOONS:
		_pos[m.name] = _fallback_moon_eq(m)
		_mu_extra[m.name] = float(m.get("mu", 0.0))
		_spin_extra[m.name] = float(m.get("spin", 0.0))
		_radius_extra[m.name] = float(m.radius)
	_radius_extra["Pluto"] = 1188.3
	_mu_extra["Pluto"] = 869.6
	_spin_extra["Pluto"] = 1.1386e-5
	var d := Time.get_date_dict_from_system()
	_today = "%04d-%02d-%02d" % [d.year, d.month, d.day]

	if _load_cache() and _cache_complete():
		live = true
		return
	_fetch_all()


func _fallback_moon_eq(m: Dictionary) -> Vector3:
	var parent_eq := Vector3.ZERO
	var parent := str(m.get("parent", ""))
	for p in PLANETS:
		if str(p.name) == parent:
			parent_eq = p.eq
			break
	var au := float(m.get("sma_km", 0.0)) / KM_PER_AU
	var phase := float(str(m.name).hash() % 1000) * 0.0062832
	return parent_eq + Vector3(cos(phase) * au, sin(phase) * au * 0.15, sin(phase) * au)


# --- public: real geocentric position in SCENE units (Y-up) -----------------
func scene_pos(name: String) -> Vector3:
	var eq: Vector3 = _pos.get(name, Vector3.ZERO)
	return Vector3(eq.x, eq.z, eq.y) * AU_TO_UNITS   # eq(x,y,z) -> scene(x,z,y)


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


func geo_start_pos() -> Vector3:
	# Sunlit GEO: ship sits on the day side so Earth is lit and the Sun is behind
	# the camera. Anti-sun GEO looks at the night face and the planet hides the Sun.
	var sun := scene_pos("Sun")
	if sun.length_squared() < 0.0001:
		return Vector3(0.0, 0.0, GEO_RADIUS_KM)
	return sun.normalized() * GEO_RADIUS_KM

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


# Physical air column above the skin. 0 = vacuum. Drag/co-rotate still Earth only.
func atmo_top_km(body_name: String) -> float:
	return float(ATMO_TOP_KM.get(body_name, 0.0))


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


# Safe park after a skin kill. Earth → sunlit GEO. Other worlds → sunward high park.
func sweet_spot(body_name: String = "") -> Vector3:
	if body_name == "" or body_name == "Earth" or body_name == "Sun":
		return geo_start_pos()
	var bpos := scene_pos(body_name)
	var rad := body_radius_km(body_name)
	if rad <= 0.0:
		return geo_start_pos()
	# Park clear of the BAND, not clear of the old 29 km bubble. kill * 4 would now
	# be 80 m, which would respawn you inside the terrain you just died on.
	var park := rad + maxf(atmo_top_km(body_name) * 1.5, 120.0)
	var sun := scene_pos("Sun")
	var out: Vector3 = bpos - sun
	if out.length_squared() < 0.0001:
		out = Vector3(1.0, 0.0, 0.0)
	return bpos + out.normalized() * park


func body_radius_km(body_name: String) -> float:
	match body_name:
		"Earth":
			return EARTH_RADIUS_KM
		"Sun":
			return SUN_RADIUS_KM
		"Moon":
			return MOON_RADIUS_KM
		"Mercury":
			return MERCURY_RADIUS_KM
		"Venus":
			return VENUS_RADIUS_KM
		"Mars":
			return MARS_RADIUS_KM
		"Jupiter":
			return JUPITER_RADIUS_KM
		"Saturn":
			return SATURN_RADIUS_KM
		"Uranus":
			return URANUS_RADIUS_KM
		"Neptune":
			return NEPTUNE_RADIUS_KM
		_:
			return float(_catalog_num(body_name, "radius", _radius_extra.get(body_name, 0.0)))


func spin_rad_s(body_name: String) -> float:
	match body_name:
		"Earth":
			return EARTH_SPIN_RAD_S
		"Moon":
			return MOON_SPIN_RAD_S
		"Mercury":
			return MERCURY_SPIN_RAD_S
		"Venus":
			return VENUS_SPIN_RAD_S
		"Mars":
			return MARS_SPIN_RAD_S
		"Jupiter":
			return JUPITER_SPIN_RAD_S
		"Saturn":
			return SATURN_SPIN_RAD_S
		"Uranus":
			return URANUS_SPIN_RAD_S
		"Neptune":
			return NEPTUNE_SPIN_RAD_S
		"Sun":
			return SUN_SPIN_RAD_S
		_:
			return float(_catalog_num(body_name, "spin", _spin_extra.get(body_name, 0.02)))


func gm(body_name: String) -> float:
	match body_name:
		"Earth":
			return GM_EARTH
		"Sun":
			return GM_SUN
		"Moon":
			return GM_MOON
		"Mercury":
			return GM_MERCURY
		"Venus":
			return GM_VENUS
		"Mars":
			return GM_MARS
		"Jupiter":
			return GM_JUPITER
		"Saturn":
			return GM_SATURN
		"Uranus":
			return GM_URANUS
		"Neptune":
			return GM_NEPTUNE
		_:
			return float(_catalog_num(body_name, "mu", _mu_extra.get(body_name, 0.0)))


func _fetch_next() -> void:
	if _idx >= _catalog.size():
		_save_cache()
		if _http:
			_http.queue_free()
		return
	var body: Dictionary = _catalog[_idx]
	if body.get("fixed", false) or not body.has("id"):
		_idx += 1
		_fetch_next()
		return
	var err := _http.request(_url_for(str(body.id)))
	if err != OK:
		push_warning("Ephemeris: request failed for %s (using fallback)" % body.name)
		_idx += 1
		_fetch_next()


func _url_for(id: String) -> String:
	# One epoch (today 00:00), geocentric, ICRF frame, position vector in AU.
	var tomorrow := _date_plus_one()
	var q := {
		"format": "json", "COMMAND": "'%s'" % id, "EPHEM_TYPE": "VECTORS",
		"CENTER": "'500@399'", "REF_PLANE": "FRAME", "OUT_UNITS": "AU-D",
		"VEC_TABLE": "1", "START_TIME": "'%s'" % _today,
		"STOP_TIME": "'%s'" % tomorrow, "STEP_SIZE": "'1 d'",
	}
	var parts := PackedStringArray()
	for k in q:
		parts.append("%s=%s" % [k, String(q[k]).uri_encode()])
	return _HOST + "?" + "&".join(parts)


func _on_reply(_result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if code == 200:
		var eq = _parse_vectors(body.get_string_from_utf8())
		if eq != null and _idx < _catalog.size():
			_pos[_catalog[_idx].name] = eq
			live = true
	_idx += 1
	_fetch_next()


# Pull "X = .. Y = .. Z = .." (AU) from the $$SOE/$$EOE block of a Horizons reply.
func _parse_vectors(text: String):
	var json = JSON.parse_string(text)
	if typeof(json) != TYPE_DICTIONARY or not json.has("result"):
		return null
	var result: String = json["result"]
	var soe := result.find("$$SOE")
	var eoe := result.find("$$EOE")
	if soe < 0 or eoe < 0:
		return null
	var block := result.substr(soe, eoe - soe)
	var re := RegEx.new()
	re.compile("X\\s*=\\s*([-\\d.E+]+)\\s+Y\\s*=\\s*([-\\d.E+]+)\\s+Z\\s*=\\s*([-\\d.E+]+)")
	var m := re.search(block)
	if m == null:
		return null
	return Vector3(float(m.get_string(1)), float(m.get_string(2)), float(m.get_string(3)))


# --- date-stamped cache so a potato doesn't re-fetch 8 bodies every launch ---
func _load_cache() -> bool:
	if not FileAccess.file_exists(_CACHE_PATH):
		return false
	var f := FileAccess.open(_CACHE_PATH, FileAccess.READ)
	if f == null:
		return false
	var data = JSON.parse_string(f.get_as_text())
	if typeof(data) != TYPE_DICTIONARY or data.get("date", "") != _today:
		return false
	for name in data.get("bodies", {}):
		var a = data["bodies"][name]
		if a is Array and a.size() == 3:
			_pos[name] = Vector3(a[0], a[1], a[2])
			_cached_names[name] = true
	return true


func _cache_complete() -> bool:
	for p in _catalog:
		if p.get("fixed", false):
			continue
		if not _cached_names.has(str(p.name)):
			return false
	return true


func _save_cache() -> void:
	var bodies := {}
	for name in _pos:
		var v: Vector3 = _pos[name]
		bodies[name] = [v.x, v.y, v.z]
	var f := FileAccess.open(_CACHE_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify({ "date": _today, "bodies": bodies }))


func _date_plus_one() -> String:
	var d := Time.get_date_dict_from_system()
	var unix := Time.get_unix_time_from_datetime_dict(d) + 86400
	var n := Time.get_datetime_dict_from_unix_time(unix)
	return "%04d-%02d-%02d" % [n.year, n.month, n.day]
