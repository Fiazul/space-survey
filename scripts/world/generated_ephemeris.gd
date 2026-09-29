class_name GeneratedEphemeris
extends SystemEphemeris
## A star system invented at real scale from its catalogue row (spectral type ->
## StarRecipe mass/radius/luminosity) plus a seed. Star-centred frame: the
## primary sits at the origin, 2-6 worlds on circular Keplerian orbits in km.
## Same seed, same system. Looks come from PlanetGenerator.invent via each
## world's kind/color/air_amount, exactly like any other recipe world.
const _STAR := preload("res://scripts/world/star_recipe.gd")
const J2000_UNIX := 946728000.0
const GM_SUN := 132712440018.0
const GM_EARTH := 398600.4418
const EARTH_RADIUS_KM := 6371.0
const DAY_S := 86400.0
# Spawn park, in radii of the spawn world. Ship._newton_g works in the anchor's
# free-falling frame, so only the star's tidal residue reaches the ship; at 2 R it
# is well under 1 % of the world's pull for every generated orbit.
const SPAWN_RADII := 2.0
const LETTERS := "bcdefg"
# Chen & Kipping 2017 (ApJ 834:17) mass-radius power laws, Earth units.
const TERRAN_EXP := 0.279
const NEPTUNIAN_EXP := 0.589
const JOVIAN_EXP := -0.044
const TERRAN_MAX_ME := 2.0
const JOVIAN_ME := 317.8
const JOVIAN_RE := 11.2
# Innermost orbit floor, clear of the photosphere and corona.
const MIN_ORBIT_STAR_RADII := 20.0

var star_row := {}
var system_seed := 0
var _orbits := {}   # name -> { a_km, phase0, n, inc }


static func build(system_id: String, row: Dictionary, unix_s: float) -> GeneratedEphemeris:
	var e := GeneratedEphemeris.new()
	e.id = system_id
	e.star_row = row
	e.system_seed = hash("%s|%s" % [system_id, str(row.get("name", system_id))])
	e._generate()
	e.place_at(unix_s)
	return e


func _generate() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = system_seed
	primary_star = str(star_row.get("star_name", star_row.get("name", id)))
	var star_spec := star_row.duplicate()
	star_spec["name"] = primary_star
	var recipe := _STAR.resolve(star_spec)
	var stellar: Dictionary = recipe.stellar
	var star_gm := float(stellar.mass_solar) * GM_SUN
	var star_r := float(stellar.radius_km)
	var lum := maxf(float(stellar.luminosity_solar), 1.0e-5)
	_catalog.append({
		"name": primary_star, "radius": star_r, "mu": star_gm,
		"spin": TAU / (rng.randf_range(20.0, 90.0) * DAY_S),
		"mass": float(stellar.mass_solar) * 333000.0, "color": recipe.color_a,
		"spectral": str(star_row.get("spectral", "")), "glow": 2.0,
		"star": true, "physical": true,
	})
	var count := rng.randi_range(2, 6)
	var hz_au := sqrt(lum)
	var a_au := maxf(hz_au * rng.randf_range(0.25, 0.6), star_r * MIN_ORBIT_STAR_RADII / KM_PER_AU)
	var snow_au := 2.7 * hz_au
	var prefix := str(star_row.get("planet_prefix", primary_star))
	for i in count:
		var name := "%s %s" % [prefix, LETTERS[i]]
		var world := _world(rng, name, a_au, snow_au, star_gm)
		_catalog.append(world)
		_orbits[name] = {
			"a_km": a_au * KM_PER_AU, "phase0": rng.randf() * TAU,
			"n": sqrt(star_gm / pow(a_au * KM_PER_AU, 3.0)),
			"inc": deg_to_rad(rng.randf_range(-2.0, 2.0)),
		}
		a_au *= rng.randf_range(1.5, 2.3)
	spawn_body = _pick_spawn(hz_au)
	_build_gravity_bodies()


func _world(rng: RandomNumberGenerator, name: String, a_au: float, snow_au: float, star_gm: float) -> Dictionary:
	var kind := "rocky"
	var mass := rng.randf_range(0.3, 1.9)
	if a_au > snow_au and rng.randf() < 0.7:
		kind = "gas"
		mass = rng.randf_range(20.0, 600.0)
	elif rng.randf() < 0.3:
		kind = "ice"
		mass = rng.randf_range(2.0, 15.0)
	var radius := radius_re(mass) * EARTH_RADIUS_KM
	var orbit_n := sqrt(star_gm / pow(a_au * KM_PER_AU, 3.0))
	# Rough tidal-lock line: close-in worlds turn once per orbit.
	var spin := orbit_n
	if a_au > 0.25 * sqrt(star_gm / GM_SUN):
		spin = TAU / (rng.randf_range(9.0, 18.0) if kind == "gas" else rng.randf_range(10.0, 40.0)) / 3600.0
	var air := 0.0
	var atmo := 0.0
	match kind:
		"gas":
			air = rng.randf_range(0.6, 0.9)
			atmo = rng.randf_range(300.0, 700.0)
		"ice":
			air = rng.randf_range(0.5, 0.9)
			atmo = rng.randf_range(200.0, 500.0)
		_:
			if mass >= 0.5 and rng.randf() < 0.6:
				air = rng.randf_range(0.3, 1.0)
				atmo = rng.randf_range(60.0, 160.0)
	var palette := {
		"rocky": [Color(0.62, 0.46, 0.40), Color(0.55, 0.52, 0.48), Color(0.70, 0.40, 0.28)],
		"ice": [Color(0.55, 0.70, 0.85), Color(0.70, 0.80, 0.88)],
		"gas": [Color(0.78, 0.66, 0.48), Color(0.60, 0.62, 0.72), Color(0.82, 0.58, 0.40)],
	}
	var colors: Array = palette[kind]
	return {
		"name": name, "radius": radius, "mass": mass, "mu": mass * GM_EARTH,
		"spin": spin, "atmo_top_km": atmo, "air_amount": air, "drag": air > 0.0,
		"kind": kind, "color": colors[rng.randi() % colors.size()], "glow": 0.4,
		"physical": true, "a_au": a_au,
	}


static func radius_re(mass_me: float) -> float:
	if mass_me <= TERRAN_MAX_ME:
		return pow(mass_me, TERRAN_EXP)
	var neptunian := pow(TERRAN_MAX_ME, TERRAN_EXP) * pow(mass_me / TERRAN_MAX_ME, NEPTUNIAN_EXP)
	return minf(neptunian, JOVIAN_RE * pow(mass_me / JOVIAN_ME, JOVIAN_EXP))


# The solid world nearest the habitable-zone distance; falls back to the first.
func _pick_spawn(hz_au: float) -> String:
	var best := ""
	var best_d := INF
	for p in _catalog:
		if p.get("star", false) or str(p.get("kind", "")) == "gas":
			continue
		var d := absf(log(float(p.a_au) / hz_au))
		if d < best_d:
			best_d = d
			best = str(p.name)
	return best if best != "" else str(_catalog[1].name)


# Freezes every world at its orbit phase for `unix_s`. Like Sol's JPL positions,
# they hold still for the session so an anchored ship never rides a moving frame.
func place_at(unix_s: float) -> void:
	_pos64[primary_star] = PackedFloat64Array([0.0, 0.0, 0.0])
	for name in _orbits:
		var o: Dictionary = _orbits[name]
		var th: float = float(o.phase0) + float(o.n) * (unix_s - J2000_UNIX)
		var a: float = o.a_km
		_pos64[name] = PackedFloat64Array([
			a * cos(th), a * sin(th) * sin(float(o.inc)), a * sin(th) * cos(float(o.inc))])


func spawn_park_km() -> float:
	return body_radius_km(spawn_body) * SPAWN_RADII
