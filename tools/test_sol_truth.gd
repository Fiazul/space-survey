extends SceneTree
# Radii, fallback distances, visual scale, and EZ vs real air.
# Run: godot --headless --path . --script res://tools/test_sol_truth.gd

const E := preload("res://scripts/autoload/ephemeris.gd")
const M := preload("res://scripts/flight/flight_mode.gd")


func _initialize() -> void:
	var failed := 0
	# IAU / NASA mean radii (km). Sphere uses mean, not equatorial bulge.
	var rad := {
		"Sun": 695700.0, "Mercury": 2439.7, "Venus": 6051.8, "Earth": 6371.0,
		"Moon": 1737.4, "Mars": 3389.5, "Jupiter": 69911.0, "Saturn": 58232.0,
		"Uranus": 25362.0, "Neptune": 24622.0, "Pluto": 1188.3,
		"Phobos": 11.08, "Deimos": 6.2, "Io": 1821.6, "Europa": 1560.8,
		"Ganymede": 2634.1, "Callisto": 2410.3, "Mimas": 198.2, "Enceladus": 252.1,
		"Tethys": 531.0, "Dione": 561.4, "Rhea": 763.8, "Titan": 2574.7,
		"Iapetus": 734.5, "Miranda": 235.8, "Ariel": 578.9, "Umbriel": 584.7,
		"Titania": 788.4, "Oberon": 761.4, "Triton": 1353.4, "Charon": 606.0,
	}
	var air := {
		"Earth": 100.0, "Venus": 250.0, "Mars": 80.0, "Titan": 600.0,
		"Jupiter": 400.0, "Saturn": 700.0, "Uranus": 300.0, "Neptune": 300.0,
	}
	var worlds: Array = []
	worlds.append_array(E.PLANETS)
	worlds.append_array(E.PHYSICAL_MOONS)
	var by := {}
	for p in worlds:
		if p.get("craft", false):
			continue
		by[str(p.name)] = p

	for nm in rad.keys():
		if not by.has(nm):
			print("sol_truth: MISSING %s" % nm)
			failed += 1
			continue
		var got: float = float(by[nm].radius)
		var want: float = float(rad[nm])
		var ok: bool = absf(got - want) <= maxf(want * 0.01, 2.0)
		if not ok:
			print("sol_truth: RADIUS %s got %.2f want %.2f" % [nm, got, want])
		failed += _check("radius_%s" % nm, ok)
		failed += _check("physical_%s" % nm, bool(by[nm].get("physical", false)))

	var eph: Node = E.new()
	for nm in rad.keys():
		var r: float = float(rad[nm])
		var a: float = float(air.get(nm, 0.0))
		var star: bool = nm == "Sun"
		var ez: float = M.exclusion_from_center(r, eph.atmo_top_km(nm), star)
		var want_ez: float = r + (2500.0 if star else (a if a > 0.0 else 10.0))
		if absf(ez - want_ez) > 1.0:
			print("sol_truth: EZ %s got %.1f want %.1f" % [nm, ez, want_ez])
			failed += 1
		else:
			failed += _check("ez_%s" % nm, true)
		failed += _check("air_%s" % nm, is_equal_approx(eph.atmo_top_km(nm), a))
	eph.free()

	var sun_eq: Vector3 = by["Sun"].eq
	var moon_eq: Vector3 = by["Moon"].eq
	var sun_au: float = sun_eq.length()
	var moon_km: float = moon_eq.length() * E.AU_TO_UNITS
	print("sol_truth: fallback Sun %.4f AU  Moon %.0f km" % [sun_au, moon_km])
	failed += _check("sun_about_1au", sun_au > 0.95 and sun_au < 1.05)
	failed += _check("moon_about_384k", moon_km > 350000.0 and moon_km < 420000.0)
	failed += _check("geo_from_mean_earth", is_equal_approx(E.GEO_RADIUS_KM, 42157.0))

	var src := FileAccess.get_file_as_string("res://scripts/world/planet_system.gd")
	# physical_vis_1 / vrad_physical_1 rewritten 2026-09-29: the arcade VISUAL_SCALE
	# branch they guarded is gone, so every body paints at its real radius.
	failed += _check("no_visual_scale", src.find("VISUAL_SCALE") < 0)
	failed += _check("paint_at_real_radius", src.find("PlanetGenerator.paint(p, float(p.radius))") >= 0)
	failed += _check("rings_inner_real", src.find("float(p.radius) * 1.15,") >= 0)
	failed += _check("rings_outer_real", src.find("float(p.radius) * 2.35,") >= 0)

	if failed == 0:
		print("sol_truth: OK")
		quit(0)
	else:
		print("sol_truth: FAIL %d" % failed)
		quit(1)


func _check(name: String, ok: bool) -> int:
	if not ok:
		print("sol_truth: FAIL %s" % name)
		return 1
	return 0
