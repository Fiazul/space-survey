extends SceneTree
# Headless check on the CONTACT margin and the post-death park.
# Run: godot --headless --path . --script res://tools/test_skin_kill.gd
#
# This file used to pin Earth's kill at a 29 km bubble (EARTH_MIN_R_KM = 6400).
# That rule is gone: you die on contact with the ground beneath you, which
# TerrainSampler computes per position, so the Pacific and Everest's summit are no
# longer equally lethal at the same altitude. Whether the kill FIRES is asserted in
# tools/test_earth_terrain.gd _kill(); what stays here is the margin itself and the
# respawn park.

const E := preload("res://scripts/autoload/ephemeris.gd")


func _initialize() -> void:
	var eph: Node = E.new()
	var failed := 0
	failed += _check("atmo_end_about_6500", is_equal_approx(E.EARTH_RADIUS_KM + E.EARTH_ATMO_TOP_KM, 6471.0))
	failed += _check("cutscene_2_to_3s", E.SURFACE_KILL_SECS >= 2.0 and E.SURFACE_KILL_SECS <= 3.0)

	# One contact margin, the same on every world, because "how close may the hull
	# get to rock" is a property of the hull, not of the planet.
	failed += _check("earth_uses_a_contact_margin",
		is_equal_approx(eph.surface_kill_km("Earth"), E.CONTACT_KILL_FLOOR_KM))
	failed += _check("every_world_uses_the_same_margin",
		is_equal_approx(eph.surface_kill_km("Moon"), eph.surface_kill_km("Earth")))
	# Small enough to fly the deck: the old 29 km bubble made Earth's whole band
	# unreachable, which is what this change exists to undo.
	failed += _check("margin_is_small_enough_to_fly_the_deck",
		eph.surface_kill_km("Earth") < 0.1)
	# ...and big enough to beat the mesh's own float32 quantisation (~0.32 m at
	# these radii), so geometry noise can never make the kill fire early.
	failed += _check("margin_beats_mesh_quantisation",
		eph.surface_kill_km("Earth") > 0.005)

	# Per-body widening still works (gravity, a heavier hull) and still clamps.
	eph.surface_kill_extra_km["Jupiter"] = 0.4
	failed += _check("jupiter_raised",
		is_equal_approx(eph.surface_kill_km("Jupiter"), E.CONTACT_KILL_FLOOR_KM + 0.4))
	eph.surface_kill_extra_km["Jupiter"] = -2.0
	failed += _check("negative_extra_clamped",
		is_equal_approx(eph.surface_kill_km("Jupiter"), E.CONTACT_KILL_FLOOR_KM))
	eph.surface_kill_extra_km.erase("Jupiter")

	# The substep ground clamp must be TERRAIN-relative, not a flat radius. This is
	# a source check because _newton_ground runs inside _newton_advance and is not
	# reachable from a pure test — but it is worth having: the old flat 6400 km
	# clamp was an INDEPENDENT blocker on the Earth flyover, and removing the kill
	# bubble alone would have left every descent stopped 29 km up while looking
	# like the band itself was broken.
	var ship_src := FileAccess.get_file_as_string("res://scripts/flight/ship.gd")
	failed += _check("ground_clamp_follows_the_terrain",
		ship_src.find("terrain.ground_radius_km") >= 0)
	failed += _check("no_flat_radius_clamp_remains",
		ship_src.find("EARTH_MIN_R_KM") < 0)
	var main_src := FileAccess.get_file_as_string("res://scripts/core/main.gd")
	failed += _check("kill_sweeps_the_frames_movement",
		main_src.find("swept_contact") >= 0)

	# The park must clear the BAND, not the retired bubble. At the old kill * 4 it
	# would now be 80 m — respawning you inside the terrain you just died on.
	var park: Vector3 = eph.sweet_spot("Earth")
	failed += _check("earth_park_is_geo", park.length() > E.EARTH_RADIUS_KM + 1000.0)
	var moon_park: Vector3 = eph.sweet_spot("Moon")
	var moon_alt: float = (moon_park - eph.scene_pos("Moon")).length() - 1737.4
	failed += _check("airless_park_clears_the_band", moon_alt > 20.0)
	failed += _check("airless_park_is_not_absurd", moon_alt < 5000.0)
	eph.free()

	if failed == 0:
		print("skin_kill: OK")
		quit(0)
	else:
		print("skin_kill: FAIL %d" % failed)
		quit(1)


func _check(name: String, ok: bool) -> int:
	if not ok:
		print("skin_kill: FAIL %s" % name)
		return 1
	return 0
