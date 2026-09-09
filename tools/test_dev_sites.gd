extends SceneTree
# Pure table + geometry checks for DevSites (Ctrl+P dev-teleport panel). No
# autoload reference anywhere (DevSites itself is autoload-free by design), so
# this runs under plain `--script`.
# Run: godot --headless --script tools/test_dev_sites.gd

const DS := preload("res://scripts/world/dev_sites.gd")
const E := preload("res://scripts/autoload/ephemeris.gd")   # names only — E.PLANETS/PHYSICAL_MOONS are consts
var failures := 0


func _initialize() -> void:
	_check_table()
	_check_dir_round_trip()
	_check_heading()
	print("dev_sites: ", "OK" if failures == 0 else "FAIL %d" % failures)
	quit(0 if failures == 0 else 1)


func _known_body_names() -> Dictionary:
	var by := {}
	for p in E.PLANETS:
		if not p.get("craft", false):
			by[str(p.name)] = true
	for m in E.PHYSICAL_MOONS:
		by[str(m.name)] = true
	return by


func _check_table() -> void:
	var known := _known_body_names()
	var sites := DS.sites()
	check("sites_nonempty", sites.size() > 0)
	var seen_names := {}
	for site in sites:
		var label: String = "%s" % [str(site.get("name", "?"))]
		check(label + "_has_body", str(site.get("body", "")) != "")
		check(label + "_body_known", known.has(str(site.get("body", ""))))
		check(label + "_no_duplicate_name", not seen_names.has(str(site.name)))
		seen_names[str(site.name)] = true
		var mode := str(site.get("mode", "surface"))
		check(label + "_mode_valid", mode in ["surface", "park", "geo"])
		var lat: float = float(site.get("lat_deg", 0.0))
		var lon: float = float(site.get("lon_deg", 0.0))
		check(label + "_lat_in_range", lat >= -90.0 and lat <= 90.0)
		check(label + "_lon_in_range", lon >= -180.0 and lon <= 360.0)
		if mode == "surface":
			check(label + "_alt_positive", float(site.get("alt_km", 0.0)) > 0.0)
	# Sanity on the counts the brief asked for: one park row per PARK_BODIES
	# entry, plus every landmark row.
	var park_rows := sites.filter(func(s): return str(s.mode) == "park")
	check("park_row_count_matches_table", park_rows.size() == DS.PARK_BODIES.size())
	var landmark_rows := sites.filter(func(s): return str(s.mode) != "park")
	check("landmark_row_count_matches_table", landmark_rows.size() == DS.LANDMARKS.size())


func _check_dir_round_trip() -> void:
	var samples := [
		[0.0, 0.0], [27.99, 86.93], [-42.4, 70.5], [80.0, -170.0], [-80.0, 10.0],
		[33.0, -15.0], [5.4, 201.4], [-53.0, -169.0],
	]
	for s in samples:
		var lat: float = s[0]
		var lon: float = s[1]
		var dir := DS.dir_for(lat, lon)
		check("dir_unit_length_%.1f_%.1f" % [lat, lon], is_equal_approx(dir.length(), 1.0))
		var lat2 := rad_to_deg(asin(clampf(dir.y, -1.0, 1.0)))
		var lon2 := rad_to_deg(atan2(dir.z, dir.x))
		var lon_wrapped := fposmod(lon + 180.0, 360.0) - 180.0
		check("dir_round_trip_lat_%.1f_%.1f" % [lat, lon], absf(lat2 - lat) < 0.01)
		check("dir_round_trip_lon_%.1f_%.1f" % [lat, lon], absf(lon2 - lon_wrapped) < 0.01)


func _check_heading() -> void:
	# At the equator/prime meridian, dir = (1,0,0): heading 0 must face the
	# global pole (north), heading 90 must face the +lon derivative (east).
	var dir := DS.dir_for(0.0, 0.0)
	var north := DS.heading_forward(dir, 0.0)
	var east := DS.heading_forward(dir, 90.0)
	check("heading_0_is_north", north.is_equal_approx(Vector3(0.0, 1.0, 0.0)))
	check("heading_90_is_east", east.is_equal_approx(Vector3(0.0, 0.0, 1.0)))
	check("heading_forward_unit_length", is_equal_approx(DS.heading_forward(dir, 37.0).length(), 1.0))
	# Near-pole fallback must not degenerate to a zero vector.
	var pole_dir := DS.dir_for(89.999, 0.0)
	check("heading_near_pole_nonzero", DS.heading_forward(pole_dir, 0.0).length() > 0.5)


func check(label: String, ok: bool) -> void:
	if not ok:
		failures += 1
		push_error("dev_sites: " + label)
