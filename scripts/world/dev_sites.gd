class_name DevSites
extends RefCounted
# Static site table for the Ctrl+P dev-teleport panel (DevSitesPanel, main.gd).
# Pure data + pure geometry helpers only — no autoload reference anywhere in
# this file, so it loads cleanly under `--script` (tools/test_dev_sites.gd
# exercises the table and the helpers headless).
#
# Three site MODEs:
#   "surface" — lat_deg/lon_deg/alt_km on the body's own terrain. dir_for()
#               uses the SAME lat/lon convention as TerrainSampler._dir_uv /
#               surface_patch._dir_uv / render_terrain.gd's own `dir`: lon =
#               atan2(dir.z, dir.x), lat = asin(dir.y). That frame does NOT
#               rotate with the body's spin (planet_system.gd only rotates the
#               far VISUAL mesh/model — see b.sphere.rotate_y/b.model.rotate_y
#               — the ring/TerrainSampler direction render_terrain.gd itself
#               samples is always this fixed, un-spun frame), so a fixed
#               lat/lon always lands on the same real feature (Everest stays
#               Everest) with no spin correction needed.
#   "park"    — Ephemeris.sweet_spot_off(body): the same safe sunward park
#               _skin_finish()/F7 already use for a respawn.
#   "geo"     — Ephemeris.geo_start_pos(): the sunlit Earth GEO F7 parks at.

# Every Sol physical body (Ephemeris.PLANETS + PHYSICAL_MOONS, craft excluded)
# gets a "park" row. Names only — no coordinates needed for a park.
const PARK_BODIES := [
	"Earth", "Sun", "Moon", "Mercury", "Venus", "Mars", "Jupiter", "Saturn",
	"Uranus", "Neptune", "Pluto",
	"Phobos", "Deimos", "Io", "Europa", "Ganymede", "Callisto",
	"Mimas", "Enceladus", "Tethys", "Dione", "Rhea", "Titan", "Iapetus",
	"Miranda", "Ariel", "Umbriel", "Titania", "Oberon", "Triton", "Charon",
]

# Landmark/orbit sites. Coordinates match tools/render_terrain.gd's shot table
# or assets/planets/SOURCES.txt where the same feature is already reviewed
# there; a few (Dead Sea, Mare Imbrium, Tharsis line, Valles Marineris, Venus/
# Titan/Saturn parking altitudes) are new, taken from this brief.
const LANDMARKS := [
	# --- Earth ---
	{"name": "Himalaya 9 km", "body": "Earth", "mode": "surface",
		"lat_deg": 27.95, "lon_deg": 86.80, "alt_km": 9.0, "heading_deg": 0.0,
		"note": "broad relief above the range"},
	{"name": "Everest summit +3 km", "body": "Earth", "mode": "surface",
		"lat_deg": 27.99, "lon_deg": 86.93, "alt_km": 3.0, "heading_deg": 180.0,
		"note": "3 km above the DEM's own summit sample here (~7.2 km, not the real 8848 m — area-averaging); looking south"},
	{"name": "Sahara coast 12 km", "body": "Earth", "mode": "surface",
		"lat_deg": 20.5, "lon_deg": -17.0, "alt_km": 12.0, "heading_deg": 0.0,
		"note": "coast/desert boundary, broad view"},
	{"name": "Atlantic mid-ocean 25 km", "body": "Earth", "mode": "surface",
		"lat_deg": 30.0, "lon_deg": -40.0, "alt_km": 25.0, "heading_deg": 0.0,
		"note": "open ocean — ring LOD band review"},
	{"name": "Amazon 25 km", "body": "Earth", "mode": "surface",
		"lat_deg": -3.0, "lon_deg": -60.0, "alt_km": 25.0, "heading_deg": 0.0,
		"note": "dense green land — ring LOD band review"},
	{"name": "Cloud deck, under (2 km)", "body": "Earth", "mode": "surface",
		"lat_deg": 35.9, "lon_deg": -75.3, "alt_km": 2.0, "heading_deg": 0.0,
		"note": "dense real cloud cover — looking up from under the deck"},
	{"name": "Cloud deck, above (20 km)", "body": "Earth", "mode": "surface",
		"lat_deg": 50.27, "lon_deg": 132.36, "alt_km": 20.0, "heading_deg": 0.0,
		"note": "scattered cloud edge — looking down from above the deck"},
	{"name": "Mariana Trench 2 km", "body": "Earth", "mode": "surface",
		"lat_deg": 11.35, "lon_deg": 142.2, "alt_km": 2.0, "heading_deg": 0.0,
		"note": "bathymetry clamps to the liquid datum here — expect flat open sea, not a canyon"},
	{"name": "Dead Sea 1 km", "body": "Earth", "mode": "surface",
		"lat_deg": 31.5, "lon_deg": 35.5, "alt_km": 1.0, "heading_deg": 0.0,
		"note": "real -427 m basin — masked land below sea level"},
	{"name": "GEO start", "body": "Earth", "mode": "geo",
		"lat_deg": 0.0, "lon_deg": 0.0, "alt_km": 0.0, "heading_deg": 0.0,
		"note": "sunlit geostationary park — F7's own spot"},
	# --- Moon ---
	{"name": "Moon grazing 7 km", "body": "Moon", "mode": "surface",
		"lat_deg": 10.0, "lon_deg": 20.0, "alt_km": 7.0, "heading_deg": 0.0,
		"note": "grazing low-altitude pass"},
	{"name": "Moon nadir 1 km", "body": "Moon", "mode": "surface",
		"lat_deg": 10.0, "lon_deg": 20.0, "alt_km": 1.0, "heading_deg": 0.0,
		"note": "straight-down crater-bowl framing (render_terrain also asks for a low sun + steep pitch here — position only)"},
	{"name": "Moon 200 m", "body": "Moon", "mode": "surface",
		"lat_deg": 10.0, "lon_deg": 20.0, "alt_km": 0.2, "heading_deg": 0.0,
		"note": "lowest render_terrain altitude — small craters"},
	{"name": "Tycho 20 km", "body": "Moon", "mode": "surface",
		"lat_deg": -43.3, "lon_deg": -11.4, "alt_km": 20.0, "heading_deg": 0.0,
		"note": "sub-texel crater at 4 ppd — DEM-scale basin/highland shape only"},
	{"name": "Mare Imbrium 30 km", "body": "Moon", "mode": "surface",
		"lat_deg": 33.0, "lon_deg": -15.0, "alt_km": 30.0, "heading_deg": 0.0,
		"note": "large mare basin"},
	{"name": "Selenean summit", "body": "Moon", "mode": "surface",
		"lat_deg": 5.4, "lon_deg": 201.4, "alt_km": 3.0, "heading_deg": 0.0,
		"note": "the Moon's real highest point (SOURCES.txt: 10622 m at 16 ppd)"},
	{"name": "South Pole-Aitken 100 km", "body": "Moon", "mode": "surface",
		"lat_deg": -53.0, "lon_deg": -169.0, "alt_km": 100.0, "heading_deg": 0.0,
		"note": "largest lunar basin — published center approx, not in SOURCES.txt/unverified against the local DEM"},
	# --- Mars ---
	{"name": "Olympus Mons 38 km", "body": "Mars", "mode": "surface",
		"lat_deg": 18.65, "lon_deg": 226.2, "alt_km": 38.0, "heading_deg": 0.0,
		"note": "real shield + rim; yaw west after arrival for the rest of the Tharsis rise"},
	{"name": "Olympus Mons 5 km", "body": "Mars", "mode": "surface",
		"lat_deg": 18.65, "lon_deg": 226.2, "alt_km": 5.0, "heading_deg": 0.0,
		"note": "close pass over the shield"},
	{"name": "Tharsis Montes line 60 km", "body": "Mars", "mode": "surface",
		"lat_deg": 1.0, "lon_deg": 247.0, "alt_km": 60.0, "heading_deg": 0.0,
		"note": "the three-volcano line, broad view"},
	{"name": "Hellas Planitia floor 10 km", "body": "Mars", "mode": "surface",
		"lat_deg": -42.4, "lon_deg": 70.5, "alt_km": 10.0, "heading_deg": 0.0,
		"note": "real DEM basin floor"},
	{"name": "Valles Marineris 20 km", "body": "Mars", "mode": "surface",
		"lat_deg": -13.9, "lon_deg": 300.4, "alt_km": 20.0, "heading_deg": 0.0,
		"note": "the canyon system"},
	# --- Venus / Titan / Io / Europa / Jupiter / Saturn ---
	{"name": "Venus 260 km", "body": "Venus", "mode": "surface",
		"lat_deg": 0.0, "lon_deg": 0.0, "alt_km": 260.0, "heading_deg": 0.0,
		"note": "just outside the 250 km atmosphere shell, inbound"},
	{"name": "Titan 500 km", "body": "Titan", "mode": "surface",
		"lat_deg": 0.0, "lon_deg": 0.0, "alt_km": 500.0, "heading_deg": 0.0,
		"note": "high park view of Saturn's biggest moon"},
	{"name": "Io volcano site", "body": "Io", "mode": "surface",
		"lat_deg": 10.0, "lon_deg": 20.0, "alt_km": 6.0, "heading_deg": 0.0,
		"note": "near Io's volcanic terrain (procedural; render_terrain picks the exact peak live off this same base coordinate)"},
	{"name": "Europa ice 300 m", "body": "Europa", "mode": "surface",
		"lat_deg": 10.0, "lon_deg": 20.0, "alt_km": 0.3, "heading_deg": 0.0,
		"note": "close ice-surface pass"},
	{"name": "Jupiter 80,000 km", "body": "Jupiter", "mode": "surface",
		"lat_deg": 10.0, "lon_deg": 20.0, "alt_km": 80000.0, "heading_deg": 0.0,
		"note": "storm-band overview, no solid surface"},
	{"name": "Saturn 120,000 km", "body": "Saturn", "mode": "surface",
		"lat_deg": 0.0, "lon_deg": 0.0, "alt_km": 120000.0, "heading_deg": 0.0,
		"note": "above the ring plane — aim manually for the ring-edge view"},
]


static func sites() -> Array:
	var out := []
	for body in PARK_BODIES:
		out.append({"name": "%s — park" % body, "body": body, "mode": "park",
			"lat_deg": 0.0, "lon_deg": 0.0, "alt_km": 0.0, "heading_deg": 0.0,
			"note": "safe sunward park"})
	out.append_array(LANDMARKS)
	return out


# Outward unit vector for a lat/lon pair, in the body's own fixed (un-spun)
# frame — mirrors TerrainSampler._dir_uv / render_terrain.gd's own `dir` line
# for line so a site here samples the exact ground render_terrain would show.
static func dir_for(lat_deg: float, lon_deg: float) -> Vector3:
	var lat := deg_to_rad(lat_deg)
	var lon := deg_to_rad(lon_deg)
	return Vector3(cos(lat) * cos(lon), sin(lat), cos(lat) * sin(lon)).normalized()


# East/north tangent basis at a surface direction (matches render_terrain.gd's
# cam_east/north exactly: east = dir x UP, north = east x dir). Falls back to
# an arbitrary tangent pair right at the poles, where dir x UP degenerates.
static func surface_frame(dir: Vector3) -> Dictionary:
	var east := dir.cross(Vector3.UP)
	if east.length_squared() < 0.0001:
		east = Vector3.RIGHT.cross(dir)
	if east.length_squared() < 0.0001:
		east = Vector3.FORWARD.cross(dir)
	east = east.normalized()
	var north := east.cross(dir).normalized()
	return {"up": dir, "east": east, "north": north}


# Compass-style forward tangent: 0 = north, 90 = east, positive clockwise seen
# from above (matches real compass bearing — verified against surface_frame()
# at the equator: east there is exactly the +lon derivative direction).
static func heading_forward(dir: Vector3, heading_deg: float) -> Vector3:
	var f := surface_frame(dir)
	var h := deg_to_rad(heading_deg)
	return (f.north * cos(h) + f.east * sin(h)).normalized()


# Anchor offset (body-centre to ship, km) for a surface site: ground radius at
# that direction (real terrain height where a DEM exists) plus the requested
# altitude above it.
static func surface_anchor_off(dir: Vector3, ground_radius_km: float, alt_km: float) -> Vector3:
	return dir * (ground_radius_km + alt_km)
