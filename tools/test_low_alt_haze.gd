extends SceneTree
# Contract for the low-altitude haze/cloud-fog stacking fix (user report: "flying
# over surface feels like I'm underwater" - a uniform blue-grey murk at 2 km under
# a dense Earth cloud deck).
#
# HONEST LIMIT: planet_system.gd cannot be preloaded under `--script` at all -
# it references the Ephemeris/GameState autoloads at multiple call sites
# (pre-existing, not introduced by this fix), and CLAUDE.md already records that
# an autoload identifier anywhere in a preloaded script hangs this runtime
# rather than erroring (the removed test_wh_network.gd note). So both the
# fly-through fog BAND math (inline in PlanetSystem._update_air) and the cloud
# quality multiplier table (PlanetSystem.CLOUD_QUALITY_MULT /
# cloud_recipe_for_quality(), the `_cloud_recipe` region) are mirrored here with
# the same constants/values and cited by name. If either changes in
# scripts/world/planet_system.gd, this mirror must change with it - the same
# contract PLANET_GENERATOR.md states for the cook/shader pair.

const G := preload("res://scripts/world/planet_generator.gd")
const CLOUD_QUALITY_MULT := [0.0, 0.5, 1.0]  # mirrors PlanetSystem.CLOUD_QUALITY_MULT

const EARTH_ATMO_TOP_KM := 100.0
const CLOUD_ALT_KM := 9.0        # CloudLayer.DEFAULT_CLOUD_ALT_KM
const CLOUD_THICKNESS_KM := 3.0  # CloudLayer.DEFAULT_THICKNESS_KM


func _initialize() -> void:
	var failed := 0
	failed += _fog_band()
	failed += _budget()
	failed += _cloud_quality_mult()
	if failed == 0:
		print("low_alt_haze: OK")
		quit(0)
	else:
		print("low_alt_haze: FAIL %d" % failed)
		quit(1)


# Mirrors planet_system.gd:_update_air's band ramp (scripts/world/planet_system.gd,
# the `_update_air` region, "half"/"margin"/"d"/"band" lines).
func _band(alt_km: float) -> float:
	var half: float = CLOUD_THICKNESS_KM * 0.5
	var margin: float = clampf(half * 0.3, 0.1, 1.0)
	var d: float = absf(alt_km - CLOUD_ALT_KM)
	return clampf((half + margin - d) / margin, 0.0, 1.0)


func _fog_band() -> int:
	var failed := 0
	# 2 km is 5.5 km below the deck's true base (7.5 km) - clear air, per the
	# reference: "the air between you and [the deck] is CLEAR" below it.
	var cov := 1.0
	var fog_at_2km: float = _band(2.0) * cov
	failed += _check("fog_zero_below_base_2km", is_equal_approx(fog_at_2km, 0.0))
	# 1 km below the true base (alt 6.5) must ALSO read clear - the specific
	# case named in the brief ("never tint the whole sky ... 1 km below base").
	var fog_1km_below: float = _band(6.5) * cov
	failed += _check("fog_zero_1km_below_base", is_equal_approx(fog_1km_below, 0.0))
	# Inside the deck (alt == cloud_alt_km, dead centre) fog must reach a real
	# white-out, >= 0.8.
	var fog_inside: float = _band(CLOUD_ALT_KM) * cov
	failed += _check("fog_saturates_inside_deck", fog_inside >= 0.8)
	return failed


func _budget() -> int:
	var failed := 0
	# Sweep altitudes across and beyond the deck; the combined air-shell opacity
	# + fog (clampf'd in _update_air) must never exceed the 1.0 budget - a
	# literal ceiling, but also never NEGATIVE or NaN from the ramp maths.
	var alt := 0.0
	while alt <= 20.0:
		var air: float = G.air_shell_opacity(alt, EARTH_ATMO_TOP_KM, 1.0)
		var fog: float = _band(alt) * 1.0
		var combined: float = clampf(air + fog, 0.0, 1.0)
		failed += _check("budget_%.1f" % alt, combined <= 1.0001 and combined >= 0.0)
		alt += 0.5
	return failed


# Mirrors PlanetSystem.cloud_recipe_for_quality() (scripts/world/planet_system.gd,
# the `_cloud_recipe` region): a COPY of the recipe with cloud_amount scaled by
# CLOUD_QUALITY_MULT[quality_idx], never mutating the source dictionary.
func _cloud_recipe_for_quality(recipe: Dictionary, quality_idx: int) -> Dictionary:
	var idx: int = clampi(quality_idx, 0, CLOUD_QUALITY_MULT.size() - 1)
	var mult: float = CLOUD_QUALITY_MULT[idx]
	if mult >= 0.999:
		return recipe
	var scaled: Dictionary = recipe.duplicate()
	scaled["cloud_amount"] = float(recipe.get("cloud_amount", 0.0)) * mult
	return scaled


func _cloud_quality_mult() -> int:
	var failed := 0
	var recipe := {"cloud_amount": 1.0}
	var off: Dictionary = _cloud_recipe_for_quality(recipe, 0)
	var light: Dictionary = _cloud_recipe_for_quality(recipe, 1)
	var full: Dictionary = _cloud_recipe_for_quality(recipe, 2)
	failed += _check("off_zeroes_cloud_amount", is_equal_approx(float(off.cloud_amount), 0.0))
	failed += _check("light_halves_cloud_amount", is_equal_approx(float(light.cloud_amount), 0.5))
	failed += _check("full_keeps_cloud_amount", is_equal_approx(float(full.cloud_amount), 1.0))
	# The scaled dictionary must be a COPY - the caller's recipe is untouched.
	failed += _check("source_recipe_untouched", is_equal_approx(float(recipe.cloud_amount), 1.0))
	return failed


func _check(name: String, ok: bool) -> int:
	if not ok:
		print("low_alt_haze: FAIL %s" % name)
		return 1
	return 0
