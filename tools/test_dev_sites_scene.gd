extends Node
# Scene-based half of test_dev_sites.gd: the Everest DevSites row must land on
# the real DEM peak, not merely on a plausible lat/lon. Scene-based (not
# --script) for the same reason test_dem_calibration.gd is: loading Earth's
# real res:// height map needs a live scene tree.
# Run: godot --headless tools/test_dev_sites_scene.tscn

const DS := preload("res://scripts/world/dev_sites.gd")
const G := preload("res://scripts/world/planet_generator.gd")

var failures := 0


func _ready() -> void:
	var everest: Variant = _find("Everest summit +3 km")
	check("everest_site_found", everest is Dictionary)
	if everest is Dictionary:
		var recipe := G.recipe_for({"name": str(everest.body)})
		var sampler := G.terrain_sampler(recipe)
		var dir := DS.dir_for(float(everest.lat_deg), float(everest.lon_deg))
		var h := sampler.height_m(dir)
		# SOURCES.txt: Everest's own texel samples 7198.3 m on the 8k Earth DEM —
		# well above the 6500 m bar this test asserts, comfortably below the real
		# 8848 m summit (area-averaging at 4.89 km/px undersamples the peak).
		check("everest_height_above_6500m", h > 6500.0)
		print("dev_sites_scene: Everest samples %.1f m at (%.2f, %.2f)"
			% [h, everest.lat_deg, everest.lon_deg])
	print("dev_sites_scene: ", "OK" if failures == 0 else "FAIL %d" % failures)
	get_tree().quit(0 if failures == 0 else 1)


func _find(site_name: String) -> Variant:
	for site in DS.sites():
		if str(site.name) == site_name:
			return site
	return null


func check(label: String, ok: bool) -> void:
	if not ok:
		failures += 1
		push_error("dev_sites_scene: " + label)
