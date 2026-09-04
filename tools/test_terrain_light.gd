extends SceneTree
# Contract for slice A6: the ground is lit, hazed, and lit by the SAME rule the
# globe above it uses.
# Run: godot --headless --path . --script res://tools/test_terrain_light.gd
#
# HONEST LIMIT, stated up front: this slice is entirely about appearance, and
# this environment renders on llvmpipe software Vulkan. Nothing here proves it
# LOOKS right. What it proves is that the rules are shared, the geometry did not
# move, the normals point the right way, and the haze and sky curves have the
# shape and range they were designed for. Three parameter judgments are
# deliberately left to a screenshot - see NEEDS-YOUR-EYES.md.

const G := preload("res://scripts/world/planet_generator.gd")
const SP := preload("res://scripts/world/surface_patch.gd")

const MOON_R := 1737.4
const EARTH_R := 6371.0


func _initialize() -> void:
	var failed := 0
	failed += _shared_rule()
	failed += _normals()
	failed += _haze()
	failed += _sky()
	if failed == 0:
		print("terrain_light: OK")
		quit(0)
	else:
		print("terrain_light: FAIL %d" % failed)
		quit(1)


# --- One lighting rule, two consumers ----------------------------------------
func _shared_rule() -> int:
	var failed := 0
	var earth := G.recipe_for({"name": "Earth"})
	var spec := {"spectral": "G"}
	var cook: ShaderMaterial = G.make_material(earth, spec) as ShaderMaterial
	var tile: ShaderMaterial = G.terrain_material(earth, spec)

	failed += _check("cook_material_exists", cook != null)
	failed += _check("tile_material_exists", tile != null)
	if cook == null or tile == null:
		return failed

	# THE assertion of this section. The tile meets the globe at the tile's own
	# outer edge; two different terminators would show a step in the light there
	# that no amount of parameter twiddling could remove.
	var c_lo: float = float(cook.get_shader_parameter("term_lo"))
	var c_hi: float = float(cook.get_shader_parameter("term_hi"))
	var t_lo: float = float(tile.get_shader_parameter("term_lo"))
	var t_hi: float = float(tile.get_shader_parameter("term_hi"))
	failed += _check("globe_and_tile_share_term_lo", is_equal_approx(c_lo, t_lo))
	failed += _check("globe_and_tile_share_term_hi", is_equal_approx(c_hi, t_hi))
	failed += _check("terminator_is_the_generators_constant",
		is_equal_approx(t_lo, G.TERMINATOR_LO) and is_equal_approx(t_hi, G.TERMINATOR_HI))
	failed += _check("terminator_is_a_real_ramp", t_hi > t_lo)

	# ...and the globe must no longer carry a hardcoded copy of it.
	var cook_src := FileAccess.get_file_as_string("res://shaders/planet_cook.gdshader")
	failed += _check("globe_has_no_hardcoded_terminator",
		cook_src.find("smoothstep(-0.04, 0.28, ndotl)") < 0)
	failed += _check("globe_reads_the_terminator_uniform",
		cook_src.find("smoothstep(term_lo, term_hi, ndotl)") >= 0)

	# The tile must not be unshaded-with-no-lighting any more. The shader DOES
	# declare `render_mode unshaded` - that only stops Godot adding its own light
	# on top - so the check is that it computes a terminator itself.
	var tile_src := FileAccess.get_file_as_string("res://shaders/terrain_tile.gdshader")
	failed += _check("tile_computes_its_own_light",
		tile_src.find("smoothstep(term_lo, term_hi") >= 0)
	var patch_src := FileAccess.get_file_as_string("res://scripts/world/surface_patch.gd")
	failed += _check("no_unshaded_ground_material_remains",
		patch_src.find("SHADING_MODE_UNSHADED") < 0
		or patch_src.find("_kit_material") >= 0)

	# The night side must never be pure black: at zero it loses its horizon and
	# reads as a hole punched in the world.
	failed += _check("night_side_keeps_some_fill", G.NIGHT_FILL > 0.0)
	failed += _check("night_side_is_still_night", G.NIGHT_FILL < 0.25)

	print("terrain_light: rule  terminator %.3f..%.3f shared by globe and tile, night fill %.3f"
		% [t_lo, t_hi, G.NIGHT_FILL])
	return failed


# --- Smooth normals that did not move the ground -----------------------------
func _normals() -> int:
	var failed := 0
	# Built over EARTH's Himalaya, not the Moon. A lunar tile cannot test this:
	# its relief comes from crust fbm at a ~1800 km wavelength, so across ring 0's
	# 3.2 km the ground is a plane and every normal is radial whether or not it
	# follows the terrain. Earth's DEM has real grade there.
	var earth := G.recipe_for({"name": "Earth"})
	var sampler: TerrainSampler = G.terrain_sampler(earth)
	var patch = SP.new()
	patch._ready()
	patch.bind_body(earth, sampler)
	var dir := _dir_of(27.95, 86.80)
	var ceiling: float = G.band_ceiling_km(sampler)
	for _i in SP.RING_COUNT:
		patch.update_for(dir * (EARTH_R + 8.0), "Earth", true, EARTH_R, 8.0, 0.02,
			ceiling, earth, sampler)

	# Shading data must NOT have leaked into positions. This is the same check
	# that guards the height function, re-run because normals touch the same mesh.
	var err: Dictionary = patch.vertex_error_km(EARTH_R)
	failed += _check("normals_did_not_move_the_geometry",
		maxf(float(err.over), float(err.under)) < _agreement_tol_km(EARTH_R))

	var n: Dictionary = patch.normal_report(EARTH_R)
	failed += _check("every_vertex_has_a_normal", int(n.counted) > 0)
	# Flat shading gives every vertex of a triangle the same normal, so a mesh
	# with smooth normals must show real variation between neighbours.
	failed += _check("normals_are_smooth_not_faceted", float(n.max_neighbour_angle) > 0.0001)
	# THE one that matters, and the one the first draft got wrong. A plain radial
	# normal also varies vertex to vertex, so neighbour variation cannot tell
	# "follows the terrain" from "smooth sphere" - and swapping the smooth normals
	# for radial ones passed the check above. Terrain-following normals must LEAN
	# OFF the radial where the ground has grade.
	failed += _check("normals_follow_the_terrain_not_the_sphere",
		float(n.max_radial_tilt) > 0.01)
	# "Not shattered" is a property of the MEAN, not the maximum. A sharp arete
	# legitimately creases, so a single 70-degree turn between two vertices is
	# terrain, not noise - the first version capped the maximum at 1.2 rad and was
	# just an arbitrary number that fought real ridges. What must stay small is the
	# typical turn.
	failed += _check("normals_are_not_shattered",
		float(n.mean_neighbour_angle) < 0.35)
	failed += _check("normals_are_not_degenerate", float(n.max_neighbour_angle) < 2.6)
	# An inverted normal lights the terrain from underneath and the tile reads
	# inside-out - the kind of thing that looks like a shader bug for an hour.
	failed += _check("every_normal_points_outward", int(n.inward) == 0)
	failed += _check("normals_are_unit_length", bool(n.unit))

	print("terrain_light: normals  %d over the Himalaya: neighbour turn mean %.1f deg / max %.0f deg, lean off radial max %.1f deg, %d inward"
		% [int(n.counted), rad_to_deg(float(n.mean_neighbour_angle)),
		rad_to_deg(float(n.max_neighbour_angle)),
		rad_to_deg(float(n.max_radial_tilt)), int(n.inward)])
	patch.free()
	return failed


# --- Aerial perspective -------------------------------------------------------
func _haze() -> int:
	var failed := 0
	# The haze distance is DERIVED: it must dissolve ring 3's rim so the LOD
	# boundary stops being a visible edge.
	# Ring 3's reach at the band ceiling, where the rings are widest.
	var rim: float = SP.ring_reach_km(3, SP.base_quad_km(16.16, EARTH_R))
	var at_rim: float = 1.0 - exp(-rim / G.HAZE_KM)
	var at_20: float = 1.0 - exp(-20.0 / G.HAZE_KM)
	var at_2: float = 1.0 - exp(-2.0 / G.HAZE_KM)
	failed += _check("haze_dissolves_ring_3", at_rim > 0.9)
	# ...without fogging the ground you are actually flying over.
	failed += _check("haze_leaves_the_near_ground_clear", at_20 < 0.4)
	failed += _check("haze_is_negligible_underfoot", at_2 < 0.1)
	failed += _check("haze_grows_with_distance", at_rim > at_20 and at_20 > at_2)

	# Vacuum gets NO haze. The Moon has to keep its hard horizon against black,
	# and this asserts a future tweak cannot fog a world with no air.
	var moon := G.recipe_for({"name": "Moon"})
	var m_mat: ShaderMaterial = G.terrain_material(moon, {"spectral": "G"})
	failed += _check("airless_world_has_no_air_amount",
		is_equal_approx(float(m_mat.get_shader_parameter("air_amount")), 0.0))
	var earth := G.recipe_for({"name": "Earth"})
	var e_mat: ShaderMaterial = G.terrain_material(earth, {"spectral": "G"})
	failed += _check("earth_has_air", float(e_mat.get_shader_parameter("air_amount")) > 0.5)

	# Haze follows the AIR, exponentially. The first version faded linearly to the
	# band ceiling, which left distant ground fogged at 30 km where there is
	# essentially no air to scatter in.
	var lo: float = G.haze_density_at(0.2, 100.0)
	var mid: float = G.haze_density_at(15.0, 100.0)
	var hi: float = G.haze_density_at(52.0, 100.0)
	failed += _check("haze_is_thicker_low_down", lo > mid and mid > hi)
	failed += _check("haze_is_gone_where_there_is_no_air", hi < 0.02)
	failed += _check("haze_is_present_on_the_deck", lo > 1.0)
	failed += _check("haze_has_no_air_in_vacuum",
		is_equal_approx(G.haze_density_at(1.0, 0.0), 0.0))

	# The warm colour comes from the STAR, so a red dwarf's horizon is red with no
	# per-system table entry.
	var g_warm: Color = G.sun_warm_for({"spectral": "G"})
	var m_warm: Color = G.sun_warm_for({"spectral": "M"})
	var b_warm: Color = G.sun_warm_for({"spectral": "B"})
	failed += _check("haze_warmth_follows_the_star",
		m_warm.r - m_warm.b > g_warm.r - g_warm.b)
	failed += _check("a_blue_star_does_not_warm_the_horizon",
		b_warm.b >= b_warm.r)
	failed += _check("scattered_light_is_paler_than_the_star",
		m_warm.b > G.color_from_spectral("M").b)

	print("terrain_light: haze  %.0f%% at ring 3's %.0f km rim, %.0f%% at 20 km, %.0f%% at 2 km; air density %.2f at 0.2 km / %.3f at 15 / %.4f at 52"
		% [at_rim * 100.0, rim, at_20 * 100.0, at_2 * 100.0, lo, mid, hi])
	return failed


# --- The air shell ------------------------------------------------------------
func _sky() -> int:
	var failed := 0
	const AIR_TOP := 100.0     # Earth's Karman line, Ephemeris.EARTH_ATMO_TOP_KM

	var at_0: float = G.air_shell_opacity(0.0, AIR_TOP, 1.0)
	var at_5: float = G.air_shell_opacity(5.0, AIR_TOP, 1.0)
	var at_15: float = G.air_shell_opacity(15.0, AIR_TOP, 1.0)
	var at_40: float = G.air_shell_opacity(40.0, AIR_TOP, 1.0)
	var at_52: float = G.air_shell_opacity(52.0, AIR_TOP, 1.0)
	var at_80: float = G.air_shell_opacity(80.0, AIR_TOP, 1.0)

	# THE ONE THE FIRST VERSION FAILED. Scattering needs air around the OBSERVER,
	# and air falls off exponentially with a scale height. The linear model
	# returned 0.333 at 52 km - a bright sky - where the real density is 0.0022,
	# and in play that painted the whole sky light blue from 52 km up, including
	# the directions pointing away from the planet into space. See the standing
	# physics note in NEEDS-YOUR-EYES.md.
	failed += _check("space_is_black_not_blue", at_52 < 0.01)
	failed += _check("high_altitude_is_effectively_vacuum", at_80 < 0.001)
	failed += _check("thirty_km_is_already_nearly_black",
		G.air_shell_opacity(30.0, AIR_TOP, 1.0) < 0.05)
	# ...while the band still has a real sky.
	failed += _check("real_sky_in_the_band", at_15 > 0.1)
	failed += _check("strong_sky_on_the_deck", at_0 > 0.95)
	failed += _check("sky_thickens_as_you_descend",
		at_0 > at_5 and at_5 > at_15 and at_15 > at_40 and at_40 > at_52 and at_52 > at_80)
	# The falloff must be EXPONENTIAL, not linear: halving the altitude must more
	# than double the density in the thin part of the range. A linear model
	# cannot satisfy this, which is what makes it a real check and not a restatement.
	failed += _check("falloff_is_exponential_not_linear",
		G.air_shell_opacity(10.0, AIR_TOP, 1.0) / at_40 > 20.0)

	# The sky must be dark on the NIGHT side, and the shell has to read the same
	# terminator the ground and the globe use to know that.
	var shell_src := FileAccess.get_file_as_string("res://shaders/air_shell.gdshader")
	failed += _check("night_sky_is_dark",
		shell_src.find("smoothstep(term_lo, term_hi") >= 0)
	# AIR MASS ALONG THE RAY, asserted numerically rather than by grepping for an
	# identifier. The first version of this check only looked for the word
	# "airmass" in the shader, and a mutation that flattened the curve kept the
	# word on its usage line and sailed through. The curve now lives in
	# PlanetGenerator as the specification, is bound to the shader as a uniform,
	# and its SHAPE is checked here.
	var zenith: float = G.sky_air_mass(1.0)
	var horizon: float = G.sky_air_mass(0.0)
	var mid_sky: float = G.sky_air_mass(0.5)
	failed += _check("zenith_is_dimmer_than_the_horizon", zenith < horizon)
	failed += _check("horizon_is_the_full_slant", is_equal_approx(horizon, 1.0))
	failed += _check("zenith_is_the_shared_floor",
		is_equal_approx(zenith, G.SKY_ZENITH_FLOOR))
	failed += _check("air_mass_falls_monotonically_upward",
		horizon > mid_sky and mid_sky > zenith)
	# Big enough a difference to actually darken the vacuum overhead: a near-flat
	# curve is what painted blue sky in every outward direction.
	failed += _check("air_mass_range_is_wide_enough", horizon / zenith > 5.0)
	failed += _check("shell_reads_the_shared_floor",
		shell_src.find("zenith_floor") >= 0)
	failed += _check("shell_scales_by_air_mass",
		shell_src.find("* airmass *") >= 0)
	# NOTE ON LIMITS: a shader's arithmetic cannot be evaluated headlessly. The
	# curve above is the contract; the shader mirrors it; a shader that fails to
	# compile shows up as SHADER ERROR in the boot log, not here.
	failed += _check("sky_is_gone_above_the_air",
		is_equal_approx(G.air_shell_opacity(AIR_TOP + 1.0, AIR_TOP, 1.0), 0.0))
	# Vacuum never draws it at all.
	failed += _check("no_sky_without_air",
		is_equal_approx(G.air_shell_opacity(1.0, 0.0, 0.0), 0.0))
	failed += _check("no_sky_on_an_airless_world",
		is_equal_approx(G.air_shell_opacity(1.0, AIR_TOP, 0.0), 0.0))

	# The shell and the ground haze must be able to meet in one colour, so both
	# read the same air colour and the same star warmth.
	var earth := G.recipe_for({"name": "Earth"})
	var spec := {"spectral": "G"}
	var shell: ShaderMaterial = G.air_shell_material(earth, spec)
	var tile: ShaderMaterial = G.terrain_material(earth, spec)
	failed += _check("shell_and_ground_share_the_air_colour",
		shell.get_shader_parameter("color_air") == tile.get_shader_parameter("color_air"))
	failed += _check("shell_and_ground_share_the_star_warmth",
		shell.get_shader_parameter("sun_warm") == tile.get_shader_parameter("sun_warm"))
	failed += _check("shell_starts_invisible",
		is_equal_approx(float(shell.get_shader_parameter("opacity")), 0.0))

	# GDScript CANNOT see a shader compile failure - Shader exposes no status, and
	# a broken shader just renders nothing while "SHADER ERROR" goes to stderr.
	# This test printed OK with the air shell failing to compile, so guard the one
	# construct that caused it: Godot rejects `return` in a fragment processor.
	for path in ["res://shaders/air_shell.gdshader",
			"res://shaders/terrain_tile.gdshader"]:
		var src := FileAccess.get_file_as_string(path)
		var frag := src.substr(maxi(src.find("void fragment()"), 0))
		# Strip // comments first. Both shaders EXPLAIN in prose why `return` is
		# forbidden here, so a plain find() matched the explanation rather than any
		# code - it failed twice on this file's own documentation before this.
		failed += _check("%s_has_no_return_in_fragment" % path.get_file().get_basename(),
			_strip_comments(frag).find("return") < 0)
	# The real check is the boot log. tools/ has no way to assert on stderr, so
	# the routine is: godot --headless --quit-after N | grep "SHADER ERROR".

	print("terrain_light: sky  opacity %.3f at 0 km, %.3f at 5, %.3f at 15, %.4f at 40, %.4f at 52, %.5f at 80"
		% [at_0, at_5, at_15, at_40, at_52, at_80])
	return failed


func _dir_of(lat_deg: float, lon_deg: float) -> Vector3:
	var lat := deg_to_rad(lat_deg)
	var lon := deg_to_rad(lon_deg)
	return Vector3(cos(lat) * cos(lon), sin(lat), cos(lat) * sin(lon)).normalized()


# Drop // comments so a source assertion tests code and not prose.
func _strip_comments(src: String) -> String:
	var out := ""
	for line in src.split("\n"):
		var cut: int = line.find("//")
		out += (line if cut < 0 else line.substr(0, cut)) + "\n"
	return out


# Tolerance for mesh-versus-height-function agreement, DERIVED from the body's
# radius rather than picked. Mesh vertices are float32, whose spacing at a
# magnitude R is about R * 2^-23 - so the same geometry quantises to 0.32 m on the
# Moon and 1.30 m on Earth, purely because Earth is 3.7x bigger. A flat tolerance
# is therefore wrong in kind: it either fails on the larger body or hides a real
# error on the smaller one. Four ULP leaves room for a normalize-and-multiply
# round trip while still failing anything at the metre-of-terrain scale.
func _agreement_tol_km(radius_km: float) -> float:
	return radius_km * pow(2.0, -23.0) * 4.0


func _check(name: String, ok: bool) -> int:
	if not ok:
		print("terrain_light: FAIL %s" % name)
		return 1
	return 0
