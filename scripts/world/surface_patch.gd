class_name SurfacePatch
extends Node3D
# Local bird-view ground just above the kill line. Hills, water, kit props.
# Still a paint. You still do not land.
#
# One tile, the nearest body only, alive only inside the skin band. Everything it
# needs comes from the RECIPE — height map when the world has one, the cook
# shader's own fbm crust when it does not. It NEVER reaches for Earth's maps by
# name: binding earth_height.jpg on the Moon paints Earth's continents on lunar
# regolith, which is the same class of bug as the 36 km sticker at 100 km.
#
# Deliberately holds no reference to any autoload (the kill line arrives as an
# argument), so tools/test_surface_band.gd can run it under plain `--script`.

# --- Nested rings ---
# One plate cannot be both fine and far. 50 m triangles out to the horizon you see
# from 10 km up (~350 km) is 49 million quads; a 36 km plate fine enough to fly
# through has no horizon at all. Concentric rings, each quad 4x the one inside it,
# give 50 m underfoot AND 205 km of reach for a constant ~32k triangles.
const RING_COUNT := 4
const RING_SEGS := 64
const RING_STEP := 4.0              # each ring out is this much coarser
# RING SIZE FOLLOWS THE HORIZON. This is the fix for the flat plates with hard
# straight edges seen below 10 km.
#
# The rings were a fixed 50 m base reaching 204.8 km. But the horizon is
# sqrt(2*R*alt): 50 km at 200 m altitude, 277 km at 6 km, 437 km at 15 km. So a
# fixed set covered 406% of the visible ground down low - triangles thrown away
# past the horizon - and only 47% up high. The other 53% fell through to the
# body's own SphereMesh, which is 192x96 segments on a 6371 km ball: facets of
# 208 x 104 km. At a grazing angle those ARE the giant flat planes with straight
# edges, and the pale diagonal band in the 15 km screenshot was one of their
# edges seen nearly end-on.
#
# RING_STEP^3 * RING_SEGS = 4096, so ring 3 reaches base_quad * 4096. Setting
# that to the horizon makes the terrain cover exactly the ground you can see, at
# every altitude, for the same constant triangle count. Screen-space quad density
# was already uniform across rings (~49 px each); coverage was the actual fault.
const RING_SPAN := 4096.0           # RING_STEP^3 * RING_SEGS
const BASE_QUAD_MIN_KM := 0.01      # 10 m; the DEM has nothing finer
const BASE_QUAD_MAX_KM := 1.0
# Rings 1..3 are DONUTS: the footprint the finer ring inside already covers is
# skipped, so nothing overdraws and the triangle budget stays flat with altitude.
# Each ring's outer edge drops straight down by one of its own quads. Adjacent
# rings sample the same height function at different rates, so their edges do not
# meet exactly; the skirt hides that gap and is invisible from above.
const SKIRT_QUADS := 1.0
# ...BUT CAPPED. A skirt only has to cover the height DISAGREEMENT between two
# rings sampling the same function at different rates - tens of metres of terrain
# variation. One full quad was fine when quads were a fixed 50 m; now that ring
# scale follows the horizon, ring 3's quad is 4.3 km at 6 km altitude, so each
# ring grew a KILOMETRES-TALL VERTICAL WALL around itself. Four concentric
# cliffs, which is what was reported three times as "cubes and boxes".
const SKIRT_DROP_MAX_KM := 0.25
# Rebuild a ring after the hull has crossed this fraction of the ring's REACH,
# not one of its quads. One quad meant ring 0 - which is 3.2 km wide - rebuilt
# every 50 m: at 230 m/s that is 4.6 full rebuilds a second, and a rebuild
# measured 240 ms. Drifting an eighth of the reach off-centre still leaves
# 1.2 km of fine ground ahead of the hull.
const REBUILD_FRAC := 0.125
# Rebuilds currently commit together to preserve the shared tangent frame.
# A future double-buffered builder can spread work without displaying torn rings.
# Rebuild everything once the altitude has moved the ring scale this far.
const BASE_DRIFT_FRAC := 0.25
# Start building while still this many ceilings out, so the rings exist by the
# time the band opens instead of hitching in on arrival. Nothing is SHOWN until
# it is genuinely in the band.
const PREBUILD_CEILINGS := 2.5
# Sea level and the body's own sphere sit at the same radius, so the ocean would
# z-fight the globe under it. Lift the water MESH INSTANCE - not its vertices -
# so vertex_error_km() is untouched.
const WATER_LIFT_KM := 0.001
const PROP_MAX := 220

var _ring_land: Array[MeshInstance3D] = []
var _ring_water: Array[MeshInstance3D] = []
# Skirts live in their OWN mesh, not mixed into the land grid. Not cosmetic: a
# skirt vertex is (rim - up * drop), and at ring 3's edge that tilts its direction
# by ~1e-4 rad, which is ~190 m of surface displacement - so it lands over
# DIFFERENT terrain than its rim. Mixed in, that showed up as ~16 m of apparent
# mesh/function disagreement and forced a tolerance loose enough to hide a real
# kilometre-scale error. Separated, vertex_error_km() can assert float32-tight.
var _ring_skirt: Array[MeshInstance3D] = []
var _ring_anchor: Array[Vector3] = []    # ZERO = that ring has never been built
var _props: MultiMeshInstance3D
# The SHARED height function. main's contact kill holds this same instance, which
# is the only reason mesh and lethality cannot drift apart.
var _sampler: TerrainSampler
var _tris := 0
# ONE material per surface kind, built on bind and reused by every ring. The old
# code called _mat() on every ring rebuild, which minted a fresh
# StandardMaterial3D each time - eight per full tile, several times a second.
var _land_mat: ShaderMaterial
var _prop_mat: ShaderMaterial
var _water_mat: ShaderMaterial
var _base_quad := 0.0          # ring 0's quad size for the current altitude
var _rim_stitched: Array[bool] = []  # per ring: was its rim snapped to the coarser grid
# The base quad each ring was last BUILT at. If two of these ever differ, the
# rings are at mismatched scales and their boundaries are torn open.
var _ring_base: Array[float] = []
var _radius := 1.0             # the body's radius, for the colour palette's texel maths
# Recipe-bound sources. Any of the three images may be null; the noise path covers it.
var _himg: Image               # height map (land elevation), else fbm crust
var _simg: Image               # water mask (white = liquid), else the land_amount cut
var _aimg: Image               # albedo, else color_a/color_b crust
var _seed := 0.0               # SAME seed the cook shader runs, so the hills agree
var _land := 1.0               # recipe land_amount, the water cut when there is no mask
var _kit := "none"             # "tree" | "rock" | "ice" | "none"
var _crust_a := Color(0.45, 0.40, 0.35)
var _crust_b := Color(0.55, 0.48, 0.42)
var _body := ""
var _prop_pool := 0            # candidates the plate offered, before the PROP_MAX cut
var _prop_cover := Vector2.ZERO # km the placed props reach along the plate's own east/north


func _ready() -> void:
	for _i in RING_COUNT:
		var land := MeshInstance3D.new()
		land.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(land)
		_ring_land.append(land)
		var water := MeshInstance3D.new()
		water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(water)
		_ring_water.append(water)
		var skirt := MeshInstance3D.new()
		skirt.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(skirt)
		_ring_skirt.append(skirt)
		_ring_anchor.append(Vector3.ZERO)
		_rim_stitched.append(false)
		_ring_base.append(0.0)
	_props = MultiMeshInstance3D.new()
	_props.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_props.multimesh = _make_prop_multimesh(_kit)
	add_child(_props)
	visible = false


# Distance to the visible horizon from an altitude, km. Pure geometry.
static func horizon_km(alt_km: float, radius_km: float) -> float:
	var a := maxf(alt_km, 0.0)
	return sqrt(maxf(2.0 * radius_km * a + a * a, 0.0))


# Ring 0's quad size for an altitude, chosen so ring 3 lands on the horizon -
# then QUANTISED TO POWERS OF TWO.
#
# The continuous version changed with every metre of altitude, and a change
# invalidates every ring at once. With one ring rebuilt per frame, ring 0 then sat
# at the new scale while rings 1-3 were still at the old one, so their shared
# boundaries no longer lined up and the mesh tore open. Over a 20 km descent that
# happened EIGHT times, which in flight is continuous. Quantising means the scale
# changes rarely and always by exactly 2x, and rescale_is_atomic below makes sure
# the rings are never at two different scales at once.
static func base_quad_km(alt_km: float, radius_km: float) -> float:
	# Full width must cover BOTH sides of the horizon, with projection margin.
	var want: float = clampf(2.4 * horizon_km(alt_km, radius_km) * (1.0 + maxf(alt_km, 0.0) / radius_km) / RING_SPAN,
		BASE_QUAD_MIN_KM, BASE_QUAD_MAX_KM)
	# CEIL, not round. Rounding to the nearest power of two can land 0.71x short
	# of the horizon, which puts the body's bare 208 km-facet sphere back in the
	# outer third of the view - the very fault the horizon-scaling fixed. Rounding
	# up keeps coverage in [1.0, 2.0]: never short, at worst some geometry past the
	# horizon, which is hidden.
	var steps: float = ceil(log(want / BASE_QUAD_MIN_KM) / log(2.0) - 0.0001)
	return clampf(BASE_QUAD_MIN_KM * pow(2.0, steps),
		BASE_QUAD_MIN_KM, BASE_QUAD_MAX_KM)


# Quad size of a ring, km. Ring 0 is the fine one under the hull.
static func ring_quad_km(ring: int, base: float) -> float:
	return base * pow(RING_STEP, float(ring))


# How far a ring reaches from the hull, km, edge to edge.
static func ring_reach_km(ring: int, base: float) -> float:
	return ring_quad_km(ring, base) * float(RING_SEGS)


# Point the tile at a world, with the SHARED sampler the contact kill also holds.
func bind_body(recipe: Dictionary, sampler: TerrainSampler) -> void:
	_sampler = sampler
	bind_recipe(recipe)


# Point the tile at a world. Called on arrival at a new body, not per frame.
func bind_recipe(recipe: Dictionary) -> void:
	_himg = _img_of(str(recipe.get("height", "")))
	_simg = _img_of(str(recipe.get("specular", "")))
	_aimg = _img_of(str(recipe.get("albedo", "")))
	_seed = float(recipe.get("seed", 0.0))
	_land = float(recipe.get("land_amount", 1.0))
	_crust_a = recipe.get("color_a", Color(0.45, 0.40, 0.35))
	_crust_b = recipe.get("color_b", _crust_a.lightened(0.18))
	# Lit, hazed materials running the globe's own terminator. These replaced two
	# SHADING_MODE_UNSHADED StandardMaterial3Ds, which is why the ground used to
	# read as a flat sheet with no sun angle at all.
	var spec := { "spectral": str(recipe.get("spectral", "G")) }
	_land_mat = PlanetGenerator.terrain_material(recipe, spec)
	_water_mat = PlanetGenerator.terrain_material(recipe, spec)
	_water_mat.set_shader_parameter("night_fill", PlanetGenerator.NIGHT_FILL * 0.5)
	_prop_mat = ShaderMaterial.new()
	_prop_mat.shader = preload("res://shaders/surface_prop.gdshader")
	_prop_mat.set_shader_parameter("air_amount", float(recipe.get("air_amount", 0.0)))
	_prop_mat.set_shader_parameter("color_air", recipe.get("color_air", Color(0.3, 0.56, 1.0)))
	_prop_mat.set_shader_parameter("ice_surface", _sampler.surface.ice_surface if _sampler != null else 0.0)
	_props.material_override = _prop_mat
	var kit: String = PlanetGenerator.surface_kit(recipe)
	# Geometry colours are recipe-derived, so a Moon -> Mars switch must repaint
	# even though both bodies use the same morphology.
	_kit = kit
	_props.multimesh = _make_prop_multimesh(kit)
	for i in RING_COUNT:
		_ring_anchor[i] = Vector3.ZERO      # force every ring to rebuild


func _img_of(path: String) -> Image:
	if path.is_empty() or not ResourceLoader.exists(path):
		return null
	var tex := load(path) as Texture2D
	if tex == null:
		return null
	var img := tex.get_image()
	if img != null and img.is_compressed():
		img.decompress()
	return img


func hush() -> void:
	visible = false


# `physical` is the 1u = 1 km truth flag. Without it an arcade system (1u = 0.01 AU,
# radii boosted by VISUAL_SCALE) hands us an "altitude" of 0.1 that is really a
# million kilometres, and a ground tile pops in deep space. main._update_skin_kill
# guards the kill line the same way.
static func should_show(body: String, physical: bool, alt: float, kill: float,
		ceiling: float, recipe: Dictionary) -> bool:
	if body.is_empty() or not physical:
		return false
	if not PlanetGenerator.has_surface(recipe):
		return false
	return PlanetGenerator.ground_stamp_ok(alt, kill, ceiling)


# `sampler` is the SHARED height function, passed in rather than constructed here.
# It used to call PlanetGenerator.terrain_sampler() itself, which meant the tile
# and main's contact kill held DIFFERENT instances - two 14.6 MB height-map loads,
# and the one-shared-function design this slice rests on was not actually true in
# the shipped path. They agreed only because the maths is deterministic.
func update_for(ship_pos: Vector3, body: String, physical: bool, radius: float,
		alt: float, kill: float, ceiling: float, recipe: Dictionary,
		sampler: TerrainSampler) -> void:
	if sampler == null:
		visible = false
		return
	# PREBUILD: warm the rings while still approaching so they exist by the time
	# the band opens, rather than hitching in on arrival.
	var in_band := should_show(body, physical, alt, kill, ceiling, recipe)
	var warming: bool = physical and not body.is_empty() \
		and PlanetGenerator.has_surface(recipe) \
		and alt > kill and alt < ceiling * PREBUILD_CEILINGS
	if not in_band and not warming:
		visible = false
		return
	if _body != body or _sampler != sampler:
		bind_body(recipe, sampler)
		_body = body
	_radius = radius
	_land_mat.set_shader_parameter("body_radius_km", radius)
	_water_mat.set_shader_parameter("body_radius_km", radius)
	var hit: Vector3 = ship_pos.normalized() * radius
	# Ring scale follows the horizon, so a change of altitude invalidates them all.
	# RESCALE IS ATOMIC. A scale change invalidates every ring, and rebuilding them
	# one per frame left ring 0 at the new scale beside rings still at the old one -
	# mismatched boundaries, so the mesh tore open for three frames every time.
	# Rebuild them all in this one update instead: one bounded hitch, and the rings
	# are never at two scales at once.
	# AGL can be tiny above a mountain while the sea-level horizon is far away.
	var want_base: float = base_quad_km(maxf(alt, ship_pos.length() - radius), radius)
	var rescaled: bool = not is_equal_approx(want_base, _base_quad)
	var recentered := _ring_anchor[0] == Vector3.ZERO or hit.distance_to(_ring_anchor[0]) > ring_reach_km(0, want_base) * REBUILD_FRAC
	if rescaled or recentered:
		_base_quad = want_base
		for i in RING_COUNT:
			_build_ring(i, hit, radius)
			_ring_anchor[i] = hit
	# All rings share a tangent frame; independent recentering tears their seams.
	visible = in_band
	_tris = 0
	for m in _ring_land:
		_tris += _tri_count(m)
	for m in _ring_water:
		_tris += _tri_count(m)
	for m in _ring_skirt:
		_tris += _tri_count(m)


func _tri_count(mi: MeshInstance3D) -> int:
	if mi == null or mi.mesh == null or mi.mesh.get_surface_count() == 0:
		return 0
	return mi.mesh.surface_get_array_len(0) / 3


func _build_ring(ring: int, hit: Vector3, radius: float) -> void:
	var up := hit.normalized()
	var east := up.cross(Vector3.UP)
	if east.length_squared() < 0.0001:
		east = up.cross(Vector3.RIGHT)
	east = east.normalized()
	var north := east.cross(up).normalized()
	var quad := ring_quad_km(ring, _base_quad)
	var half := ring_reach_km(ring, _base_quad) * 0.5
	# A donut: skip the ground the finer ring inside already owns.
	var hole := 0.0 if ring == 0 else ring_reach_km(ring - 1, _base_quad) * 0.5
	var land_st := SurfaceTool.new()
	var wat_st := SurfaceTool.new()
	var skirt_st := SurfaceTool.new()
	land_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	wat_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	skirt_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var skirted := false
	var prop_xforms: Array[Transform3D] = []
	# Sample every unique grid point ONCE. Quads share corners, so emitting
	# per-quad called _vert four times for the same position: 16,384 calls where
	# 65x65 = 4,225 points exist. The height function costs ~10 us a call (fbm3
	# alone is 40 sin() per height), so that 4x waste was ~180 ms per ring.
	var side := RING_SEGS + 1
	var grid: Array = []
	grid.resize(side * side)
	for j in side:
		for i in side:
			grid[j * side + i] = _vert(hit, up, east, north, radius,
				-half + quad * float(i), -half + quad * float(j))
	# SMOOTH VERTEX NORMALS, from the grid's own neighbours. Free: the perf pass
	# already samples every unique point once, so the cross-products cost no extra
	# height calls. Face normals made every 50 m quad a visible facet, which was
	# tolerable while the terrain was unlit and is not once light lands.
	# Positions are NOT touched here - vertex_error_km() is what proves shading
	# data did not leak into geometry.
	for j in side:
		for i in side:
			var c: Dictionary = grid[j * side + i]
			var pe: Vector3 = (grid[j * side + mini(i + 1, side - 1)] as Dictionary).p \
				- (grid[j * side + maxi(i - 1, 0)] as Dictionary).p
			var pn: Vector3 = (grid[mini(j + 1, side - 1) * side + i] as Dictionary).p \
				- (grid[maxi(j - 1, 0) * side + i] as Dictionary).p
			var nrm: Vector3 = pn.cross(pe)
			# Degenerate at a pole or a flat duplicate: fall back to the radial.
			if nrm.length_squared() < 1.0e-12:
				nrm = (c.p as Vector3).normalized()
			else:
				nrm = nrm.normalized()
			# A normal must never point into the ground: an inverted one lights the
			# terrain from underneath and the whole tile reads inside-out.
			if nrm.dot((c.p as Vector3).normalized()) < 0.0:
				nrm = -nrm
			c["n"] = nrm
	# STITCH THE OUTER RIM to the next ring's grid.
	#
	# Every ring samples the same height function, but ring N+1 does it on a 4x
	# coarser grid, so along their shared boundary ring N traces the terrain with
	# four vertices per one of ring N+1's. The two edges therefore do not coincide,
	# and the difference is the terrain's deviation from a straight line over one
	# COARSE quad - in the Himalaya, where ring 3's quad is 5.3 km, that is
	# kilometres. A skirt tall enough to bridge it is a kilometres-high wall (the
	# original "boxes"); a skirt short enough not to be a wall leaves a gap you see
	# the planet's bare globe through (the slivers that replaced them).
	#
	# So the rim is snapped: every rim vertex that is not on the coarse grid is
	# moved onto the straight line between the two that are, which is exactly the
	# line ring N+1's edge draws. The edges then coincide and there is no gap to
	# cover. Those vertices are deliberately NOT on the height function any more,
	# so the quads that use them are emitted into the SKIRT mesh - which
	# vertex_error_km() already excludes - keeping the land mesh exactly on the
	# function. The outermost ring has nothing beyond it and is left alone.
	var stitch: bool = ring < RING_COUNT - 1
	_rim_stitched[ring] = stitch
	_ring_base[ring] = _base_quad
	if stitch:
		var step := int(RING_STEP)
		for k in range(0, side, step):
			var k2: int = mini(k + step, side - 1)
			for t in range(1, step):
				var kk := k + t
				if kk >= side - 1:
					break
				var f := float(t) / float(step)
				# All four edges of the square rim.
				_snap(grid, side, kk, 0, k, 0, k2, 0, f)
				_snap(grid, side, kk, side - 1, k, side - 1, k2, side - 1, f)
				_snap(grid, side, 0, kk, 0, k, 0, k2, f)
				_snap(grid, side, side - 1, kk, side - 1, k, side - 1, k2, f)
	for j in RING_SEGS:
		for i in RING_SEGS:
			var e0 := -half + quad * float(i)
			var n0 := -half + quad * float(j)
			var e1 := e0 + quad
			var n1 := n0 + quad
			# Wholly inside the hole means the finer ring covers it already.
			if hole > 0.0 and maxf(absf(e0), absf(e1)) <= hole \
					and maxf(absf(n0), absf(n1)) <= hole:
				continue
			var p00: Dictionary = grid[j * side + i]
			var p10: Dictionary = grid[j * side + i + 1]
			var p01: Dictionary = grid[(j + 1) * side + i]
			var p11: Dictionary = grid[(j + 1) * side + i + 1]
			# ALL FOUR corners, not the average. An average over 0.55 made any
			# quad with two wet corners a full water plate, so every shoreline grew
			# a fringe of dark quads standing 1 m proud of the land beside them.
			# A shoreline quad is better drawn as land; slice C gives it a real edge.
			# ONE MESH. Land and water used to be split into two meshes by a
			# per-quad test, which drew every coastline at quad resolution - 1.5 km
			# on ring 2, 6.1 km on ring 3 - as hard-edged angular polygons, and put
			# a material change on the boundary so the step could not soften.
			# Wetness is now a vertex colour that interpolates.
			var wet: float = (float(p00.w) + float(p10.w) + float(p01.w) + float(p11.w)) * 0.25
			var st: SurfaceTool = land_st
			# A quad touching the stitched rim goes into the skirt mesh, because its
			# rim corners were moved off the height function to meet the neighbour.
			var on_rim: bool = i == 0 or j == 0 or i == RING_SEGS - 1 or j == RING_SEGS - 1
			if stitch and on_rim:
				st = skirt_st
				skirted = true
			_tri(st, p00, p10, p11)
			_tri(st, p00, p11, p01)
			# Skirt the ring's outer rim so the seam to the next ring cannot show.
			var drop: float = minf(quad * SKIRT_QUADS, SKIRT_DROP_MAX_KM)
			if i == 0:
				_skirt(skirt_st, p01, p00, up, drop)
				skirted = true
			if i == RING_SEGS - 1:
				_skirt(skirt_st, p10, p11, up, drop)
				skirted = true
			if j == 0:
				_skirt(skirt_st, p00, p10, up, drop)
				skirted = true
			if j == RING_SEGS - 1:
				_skirt(skirt_st, p11, p01, up, drop)
				skirted = true
			# Props ride ring 0 only this slice; slice D revisits density per ring.
			if ring == 0:
				var seedn := _hash(Vector2(float(i), float(j)))
				if _prop_here(wet, float(p00.h), seedn):
					var t := Transform3D()
					var sc: float = 0.004 + seedn * 0.012
					# Stand the prop on the vertex's own SMOOTH normal, so a
					# boulder on a slope leans with the slope instead of with the
					# quad it happened to land in.
					var stand: Vector3 = p00.n
					t.basis = Basis(east, stand, north).orthonormalized().scaled(
						Vector3(sc, sc * _prop_aspect(seedn), sc))
					# Kit meshes already have their base at y=0. Lifting by nearly
					# a full scale made floating, building-sized lunar boulders.
					t.origin = p00.p - stand * sc * 0.08
					prop_xforms.append(t)
	_ring_land[ring].mesh = land_st.commit()
	_ring_land[ring].material_override = _land_mat
	# The water mesh is retired - one surface now - but the node stays so the
	# report and the error walk keep a stable shape.
	_ring_water[ring].mesh = null
	_ring_skirt[ring].mesh = skirt_st.commit() if skirted else null
	_ring_skirt[ring].material_override = _land_mat
	if ring == 0:
		_place_props(prop_xforms, hit, east, north)


# Move one rim vertex onto the straight line between the two coarse-grid vertices
# that bracket it, so this ring's edge traces the same polyline the next ring out
# does. Colour and water flag are interpolated too, or the stitch band would
# change material halfway along.
func _snap(grid: Array, side: int, x: int, y: int, ax: int, ay: int,
		bx: int, by: int, f: float) -> void:
	var v: Dictionary = grid[y * side + x]
	var a: Dictionary = grid[ay * side + ax]
	var b: Dictionary = grid[by * side + bx]
	v["p"] = (a.p as Vector3).lerp(b.p as Vector3, f)
	v["c"] = (a.c as Color).lerp(b.c as Color, f)
	v["w"] = lerpf(float(a.w), float(b.w), f)
	v["n"] = ((a.n as Vector3).lerp(b.n as Vector3, f)).normalized()


# Two triangles hanging straight down from a rim edge, hiding the gap where this
# ring's edge and the next ring's edge sampled the same ground at different rates.
func _skirt(st: SurfaceTool, a: Dictionary, b: Dictionary, up: Vector3, drop: float) -> void:
	var a_lo: Dictionary = a.duplicate()
	var b_lo: Dictionary = b.duplicate()
	a_lo["p"] = a.p - up * drop
	b_lo["p"] = b.p - up * drop
	var nrm: Vector3 = (b.p - a.p).cross(a_lo.p - a.p)
	if nrm.length_squared() < 1e-10:
		nrm = up
	else:
		nrm = nrm.normalized()
	# A skirt is a vertical wall, so all four corners share its face normal - it
	# must NOT inherit the smooth ground normals or it lights as if it were ground.
	var a_w: Dictionary = a.duplicate()
	var b_w: Dictionary = b.duplicate()
	a_w["n"] = nrm
	b_w["n"] = nrm
	a_lo["n"] = nrm
	b_lo["n"] = nrm
	_tri(st, a_w, b_w, b_lo)
	_tri(st, a_w, b_lo, a_lo)


# Where a kit prop is allowed to stand. Placement rules, not just a recolour:
# trees want dry mid-slope ground, boulders scatter over any dry crust, and ice
# spires collect on the high cold ground.
func _prop_here(wet: float, h: float, seedn: float) -> bool:
	match _kit:
		"tree":
			return wet < 0.35 and h > 0.06 and h < 0.55 and seedn > 0.82
		"rock":
			return wet < 0.5 and seedn > 0.86
		"ice":
			return wet < 0.5 and h > 0.3 and seedn > 0.84
		_:
			return false


# Vertical stretch. A tree is tall, a boulder is squat, an ice spire is tallest.
func _prop_aspect(seedn: float) -> float:
	match _kit:
		"tree":
			return 1.6 + seedn
		"rock":
			return 0.55 + seedn * 0.35
		"ice":
			return 1.9 + seedn * 1.4
		_:
			return 1.0


# Vertex at a metric offset (km, east/north) from the ring's centre. Height comes
# from the SHARED sampler — the same call main's contact kill makes — so mesh and
# lethality cannot disagree. Do NOT sample a height map directly here.
func _vert(hit: Vector3, up: Vector3, east: Vector3, north: Vector3,
		radius: float, off_e: float, off_n: float) -> Dictionary:
	var dir: Vector3 = (hit + east * off_e + north * off_n).normalized()
	var uv := _dir_uv(dir)
	var gr: float = _sampler.ground_radius_km(dir, radius)
	var wet: float = _sampler.water01(dir)
	# 0..1 of this world's own relief, for prop placement and colour banding.
	var h: float = clampf((gr - radius) / maxf(_sampler.max_height_km(), 0.001), 0.0, 1.0)
	# "n" starts radial and is replaced by the grid's smooth normal in _build_ring.
	# Skirt vertices keep this radial one, which is correct for a vertical wall.
	# Shader textures tagged source_color are linearized by Godot; vertex colours
	# are not. Match that space before blending or close terrain washes out.
	var col: Color = _color_at(dir, uv, h).srgb_to_linear()
	col.a = wet          # the shader reads wetness from COLOR.a as its fallback
	return { "p": dir * gr, "h": h, "w": wet, "n": dir, "c": col, "uv": uv, "lava": _sampler.lava01(dir) }


# Ground colour. Albedo map where the world has one, else the recipe's crust
# colours. Slice A5 replaces this with the sampler's shared palette, because at
# these altitudes the map is under two texels across the whole ring and carries
# no detail — see the spec.
func _color_at(dir: Vector3, uv: Vector2, h: float) -> Color:
	if _sampler != null:
		# The palette, weighted by how many albedo texels the ring still spans.
		# Straight albedo sampling gave ONE flat colour: Earth's map is 19.5 km per
		# texel and ring 0 at 6 km altitude spans 0.22 of one.
		# Palette only, DRY. The shader blends the ocean per fragment from the mask,
		# so baking it in here would quantise the shoreline to the vertex spacing -
		# 10.24 km on ring 3 at 13 km altitude.
		return _sampler.land_color(dir, _radius)
	var mixf: float = PlanetGenerator.fbm3(dir * 5.0 + Vector3(_seed, _seed, _seed))
	return _crust_a.lerp(_crust_b, clampf(mixf, 0.0, 1.0)).lightened(clampf(h - 0.5, 0.0, 0.3))


# Per-VERTEX normals, so a ridge shades as a curve instead of as 50 m facets.
func _tri(st: SurfaceTool, a: Dictionary, b: Dictionary, c: Dictionary) -> void:
	for v in [a, b, c]:
		st.set_normal(v.n)
		st.set_color(v.c)
		st.set_uv(v.uv)
		st.set_uv2(Vector2(float(v.get("lava", 0.0)), 0.0))
		st.add_vertex(v.p)


func _dir_uv(dir: Vector3) -> Vector2:
	var lon := atan2(dir.z, dir.x)
	var lat := asin(clampf(dir.y, -1.0, 1.0))
	return Vector2(lon / TAU + 0.5, 0.5 - lat / PI)


func _sample(img: Image, uv: Vector2) -> Color:
	if img == null:
		return Color(0.2, 0.25, 0.15)
	var x := int(floor(fposmod(uv.x, 1.0) * float(img.get_width())))
	var y := int(floor(clampf(uv.y, 0.0, 0.999) * float(img.get_height())))
	return img.get_pixel(x, y)


func _hash(p: Vector2) -> float:
	return fposmod(sin(p.dot(Vector2(127.1, 311.7))) * 43758.5453, 1.0)


func _mat(water: bool) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.roughness = 0.22 if water else 0.92
	m.metallic = 0.05 if water else 0.0
	if water:
		m.albedo_color = Color(0.06, 0.22, 0.32)
		m.emission_enabled = true
		m.emission = Color(0.02, 0.08, 0.12)
		m.emission_energy_multiplier = 0.25
	else:
		m.albedo_color = Color(1, 1, 1)
	return m


func _make_prop_multimesh(kit: String) -> MultiMesh:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = _kit_mesh(kit)
	mm.instance_count = PROP_MAX
	mm.visible_instance_count = 0
	return mm


# The kit, generated. No GLB per world and no GLB at all yet: the CC0 pack in
# docs/specs/2026-08-22-universal-planet-asset-kit-design.md is not acquired, so
# these are project-owned primitives standing in for its rock / plant / crystal
# morphologies. Unshaded on purpose — shaded boxes in a dark scene were the
# "black boxes" bug in PLANET_GENERATOR.md.
func _kit_mesh(kit: String) -> ArrayMesh:
	match kit:
		"tree":
			return _tree_mesh()
		"rock":
			return _rock_mesh()
		"ice":
			return _ice_mesh()
		_:
			return _rock_mesh()


func _tree_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var brown := Color(0.28, 0.18, 0.08)
	var green := Color(0.12, 0.32, 0.10)
	_box(st, Vector3(0, 0.35, 0), Vector3(0.12, 0.7, 0.12), brown)
	_cone(st, Vector3(0, 1.35, 0), 0.55, 1.4, green)
	st.set_material(_kit_material())
	return st.commit()


# A fractured boulder with five irregular cross-sections and a capped crown.
# The shared prop shader supplies stone grain, strata, sunlight and haze.
func _rock_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var stone := _crust_a.lerp(Color(0.38, 0.36, 0.33), 0.6)
	const SEGMENTS := 11
	var rings: Array[PackedVector3Array] = []
	for layer in 5:
		var ring := PackedVector3Array()
		var y := float(layer) * 0.17
		var radius := [0.28, 0.52, 0.48, 0.33, 0.12][layer] as float
		for i in SEGMENTS:
			var a := TAU * float(i) / SEGMENTS
			var irregular := 0.78 + _hash(Vector2(i, layer + 13)) * 0.40
			ring.append(Vector3(cos(a) * radius * irregular + y * 0.16,
				y + _hash(Vector2(i + 11, layer)) * 0.06, sin(a) * radius * irregular))
		rings.append(ring)
	for layer in 4:
		for i in SEGMENTS:
			var j := (i + 1) % SEGMENTS
			_face(st, rings[layer][i], rings[layer + 1][j], rings[layer + 1][i], stone)
			_face(st, rings[layer][i], rings[layer][j], rings[layer + 1][j], stone.darkened(0.05))
	for i in SEGMENTS:
		_face(st, Vector3(0.1, 0.74, 0.0), rings[4][i], rings[4][(i + 1) % SEGMENTS], stone)
	st.set_material(_kit_material())
	return st.commit()


# An ice spire: two stacked faceted prisms. Pale, translucent-looking, and NOT a
# recoloured tree — a cold world gets cold geometry.
func _ice_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var pale := Color(0.74, 0.84, 0.92)
	var deep := Color(0.42, 0.58, 0.72)
	var nseg := 5
	var ring: Array[Vector3] = []
	for i in nseg:
		var a := TAU * float(i) / float(nseg)
		var r := 0.26 + _hash(Vector2(float(i), 11.0)) * 0.10
		ring.append(Vector3(cos(a) * r, 0.30, sin(a) * r))
	var tip := Vector3(0.03, 1.25, -0.02)
	for i in nseg:
		var p0: Vector3 = ring[i]
		var p1: Vector3 = ring[(i + 1) % nseg]
		_face(st, tip, p0, p1, pale)
		_face(st, Vector3(0, 0, 0), p1, p0, deep)
	st.set_material(_kit_material())
	return st.commit()


func _kit_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.roughness = 0.9
	return mat


func _face(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, col: Color) -> void:
	# Godot front faces are clockwise; their outward normal is the NEGATIVE cross.
	var n: Vector3 = -(b - a).cross(c - a)
	if n.length_squared() < 1e-10:
		n = Vector3.UP
	else:
		n = n.normalized()
	st.set_normal(n); st.set_color(col); st.add_vertex(a)
	st.set_normal(n); st.set_color(col); st.add_vertex(b)
	st.set_normal(n); st.set_color(col); st.add_vertex(c)


func _box(st: SurfaceTool, mid: Vector3, size: Vector3, col: Color) -> void:
	var h := size * 0.5
	var p := [
		mid + Vector3(-h.x, -h.y, -h.z), mid + Vector3(h.x, -h.y, -h.z),
		mid + Vector3(h.x, h.y, -h.z), mid + Vector3(-h.x, h.y, -h.z),
		mid + Vector3(-h.x, -h.y, h.z), mid + Vector3(h.x, -h.y, h.z),
		mid + Vector3(h.x, h.y, h.z), mid + Vector3(-h.x, h.y, h.z),
	]
	var faces := [[0,1,2,3], [5,4,7,6], [4,0,3,7], [1,5,6,2], [3,2,6,7], [4,5,1,0]]
	for f in faces:
		var n: Vector3 = -(p[f[1]] - p[f[0]]).cross(p[f[2]] - p[f[0]]).normalized()
		st.set_normal(n); st.set_color(col); st.add_vertex(p[f[0]])
		st.set_normal(n); st.set_color(col); st.add_vertex(p[f[1]])
		st.set_normal(n); st.set_color(col); st.add_vertex(p[f[2]])
		st.set_normal(n); st.set_color(col); st.add_vertex(p[f[0]])
		st.set_normal(n); st.set_color(col); st.add_vertex(p[f[2]])
		st.set_normal(n); st.set_color(col); st.add_vertex(p[f[3]])


func _cone(st: SurfaceTool, tip: Vector3, rad: float, ht: float, col: Color) -> void:
	var base := tip - Vector3(0, ht, 0)
	var nseg := 6
	for i in nseg:
		var a0 := TAU * float(i) / float(nseg)
		var a1 := TAU * float(i + 1) / float(nseg)
		var p0 := base + Vector3(cos(a0) * rad, 0, sin(a0) * rad)
		var p1 := base + Vector3(cos(a1) * rad, 0, sin(a1) * rad)
		_face(st, tip, p0, p1, col)


# Push at most PROP_MAX props to the GPU. When the plate offers more, walk the
# candidate list at an even fractional stride rather than truncating it: the
# candidates arrive in row-major order, so a plain cut would dress the first few
# rows and leave the rest of the ground empty.
func _place_props(xforms: Array[Transform3D], hit: Vector3, east: Vector3, north: Vector3) -> void:
	var mm := _props.multimesh
	if mm == null:
		return
	mm.instance_count = PROP_MAX
	var total := xforms.size()
	var n := mini(total, PROP_MAX)
	mm.visible_instance_count = n
	if n == 0:
		return
	var step := float(total) / float(n)
	var e_lo := INF
	var e_hi := -INF
	var n_lo := INF
	var n_hi := -INF
	for i in n:
		var pick := mini(int(float(i) * step), total - 1)
		var xf: Transform3D = xforms[pick]
		mm.set_instance_transform(i, xf)
		var off: Vector3 = xf.origin - hit
		var de: float = off.dot(east)
		var dn: float = off.dot(north)
		e_lo = minf(e_lo, de)
		e_hi = maxf(e_hi, de)
		n_lo = minf(n_lo, dn)
		n_hi = maxf(n_hi, dn)
	# How far the PLACED props reach across ring 0, along the ring itself. Both
	# axes matter: a row-major truncate keeps east at full width and collapses
	# north, so a world-axis AABB cannot see the failure.
	_prop_cover = Vector2(e_hi - e_lo, n_hi - n_lo)
	_prop_pool = total


# What the tile is actually made of right now — read by tools/test_surface_band.gd
# and the cook tape, so "it showed something" can be told apart from "it showed
# the right world's ground".
# Feed the light and air state the shader needs. Called every frame by
# PlanetSystem, with the SAME sun vector the globe's material receives.
func set_view(sun_dir: Vector3, alt_km: float, atmo_top_km: float) -> void:
	if _land_mat == null:
		return
	var d: Vector3 = sun_dir.normalized() if sun_dir.length_squared() > 0.0001 \
		else Vector3(0.72, 0.28, 0.63)
	var density: float = PlanetGenerator.haze_density_at(alt_km, atmo_top_km)
	for m in [_land_mat, _water_mat]:
		m.set_shader_parameter("sun_dir", d)
		m.set_shader_parameter("haze_density", density)
		# How much the albedo map still knows at this ring size.
		m.set_shader_parameter("map_weight",
			_sampler.map_weight(ring_reach_km(0, _base_quad), _radius))
	if _prop_mat != null:
		_prop_mat.set_shader_parameter("sun_dir", d)
		_prop_mat.set_shader_parameter("haze_density", density)


# What the committed normals look like. Test hook: flat shading gives every
# vertex of a triangle the same normal, so real neighbour-to-neighbour variation
# is what distinguishes smooth from faceted. `inward` counts normals pointing
# into the ground, which light the terrain from underneath.
func normal_report(radius: float) -> Dictionary:
	var counted := 0
	var inward := 0
	var unit := true
	var max_turn := 0.0
	var max_tilt := 0.0
	var turn_sum := 0.0
	var turn_n := 0
	for ring in RING_COUNT:
		var mi: MeshInstance3D = _ring_land[ring]
		if mi == null or mi.mesh == null or mi.mesh.get_surface_count() == 0:
			continue
		var arrays: Array = mi.mesh.surface_get_arrays(0)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var norms: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var prev := Vector3.ZERO
		for i in norms.size():
			var nv: Vector3 = norms[i]
			counted += 1
			if absf(nv.length() - 1.0) > 0.01:
				unit = false
			if verts[i].length() > 0.0001 and nv.dot(verts[i].normalized()) < 0.0:
				inward += 1
			if i > 0:
				var turn: float = prev.angle_to(nv)
				max_turn = maxf(max_turn, turn)
				turn_sum += turn
				turn_n += 1
			prev = nv
			# How far the normal leans off the plain RADIAL direction. This is the
			# number that distinguishes "follows the terrain" from "smooth sphere":
			# a radial normal varies per vertex too, so neighbour-to-neighbour
			# variation alone cannot tell the two apart - and a mutation swapping
			# smooth normals for radial ones passed that check.
			if verts[i].length() > 0.0001:
				max_tilt = maxf(max_tilt, nv.angle_to(verts[i].normalized()))
	return { "counted": counted, "inward": inward, "unit": unit,
		"max_neighbour_angle": max_turn, "max_radial_tilt": max_tilt,
		"mean_neighbour_angle": 0.0 if turn_n == 0 else turn_sum / float(turn_n) }


# Test hook: reach a ring's mesh node by name so a probe can walk its triangles.
func mesh_for(kind: String, ring: int) -> MeshInstance3D:
	if ring < 0 or ring >= RING_COUNT:
		return null
	match kind:
		"land":
			return _ring_land[ring]
		"water":
			return _ring_water[ring]
		"skirt":
			return _ring_skirt[ring]
	return null


# Was this ring's outer rim snapped onto the next ring's grid? Every ring but
# the outermost must be, or the boundary opens and you see the body's bare globe
# through it. Test hook.
func rim_is_stitched(ring: int) -> bool:
	return ring >= 0 and ring < RING_COUNT - 1 and _rim_stitched.size() > ring \
		and _rim_stitched[ring]


# Is this tile reading the given height function? Test hook for the invariant
# that the tile, the contact kill and the ship's ground clamp share ONE instance.
func uses_sampler(sampler: TerrainSampler) -> bool:
	return _sampler == sampler


func report() -> Dictionary:
	return {
		"body": _body,
		"kit": _kit,
		"height_source": "map" if _himg != null else "noise",
		"water_source": "mask" if _simg != null else ("albedo" if _aimg != null else "noise"),
		"albedo_source": "map" if _aimg != null else "recipe-colors",
		"seed": _seed,
		"props": 0 if _props == null or _props.multimesh == null else _props.multimesh.visible_instance_count,
		"visible": visible,
		# Geometry actually committed. Zero here means the rings are empty meshes —
		# which is exactly the state the band sat in before it was ever reachable.
		"rings": RING_COUNT,
		"tris": _tris,
		"ring0_verts": _verts_of(_ring_land[0]) if _ring_land.size() > 0 else 0,
		"ring0_water_verts": _verts_of(_ring_water[0]) if _ring_water.size() > 0 else 0,
		"ring0_aabb": AABB() if _ring_land.size() == 0 or _ring_land[0].mesh == null \
			else _ring_land[0].mesh.get_aabb(),
		"ring0_reach_km": ring_reach_km(0, _base_quad),
		"base_quad_km": _base_quad,
		"ring_bases": _ring_base.duplicate(),
		"ring3_reach_km": ring_reach_km(3, _base_quad),
		# Per-ring land vertices, so the donut is directly observable: rings 1-3
		# each drop the footprint of the ring inside them, so they MUST commit
		# fewer land vertices than ring 0's full grid despite being the same
		# 64x64 resolution.
		"ring_verts": _ring_vert_counts(),
		"prop_pool": _prop_pool,
		"prop_cover": _prop_cover,
	}


# How far committed vertices stray from where the height function says the ground
# is, per ring, in km. Returns {over, under}.
#
# The first version of this returned only the OVER-height error, reasoning that
# skirts hang below the ground deliberately. Mutation testing killed that: making
# every vertex ignore terrain height entirely (dir * radius instead of dir * gr)
# put the whole mesh BELOW the ground on the Moon, which is precisely the
# fly-through-rock failure, and the sign rule discarded all of it. The check was
# blind to the failure it exists to catch.
#
# So under-height is measured too, and bounded PER RING by that ring's own skirt
# drop. Ring 0's drop is 50 m, so a kilometre of error cannot hide behind ring 3's
# 3.2 km one.
func vertex_error_km(radius: float) -> Dictionary:
	var over := 0.0
	var under := 0.0
	for ring in RING_COUNT:
		# Skirts are excluded STRUCTURALLY (their own mesh), not by tolerance, so
		# this can be asserted at float32 precision instead of at a slack value
		# big enough to swallow a real error.
		for mi in [_ring_land[ring], _ring_water[ring]]:
			if mi == null or mi.mesh == null or mi.mesh.get_surface_count() == 0:
				continue
			var arrays: Array = mi.mesh.surface_get_arrays(0)
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			for v in verts:
				var d := v.length()
				if d < 0.0001:
					continue
				var want: float = _sampler.ground_radius_km(v / d, radius)
				var err := d - want
				if err > over:
					over = err
				if -err > under:
					under = -err
	return { "over": over, "under": under }


# Does every ring's skirt hang deep enough to cover the height disagreement the
# next ring out can produce? A ring samples the same function on a 4x coarser
# grid, so its edge can sit up to roughly one of ITS quads away vertically.
func rings_seal() -> bool:
	for ring in range(RING_COUNT - 1):
		var drop: float = minf(ring_quad_km(ring, _base_quad) * SKIRT_QUADS,
			SKIRT_DROP_MAX_KM)
		if drop < minf(ring_quad_km(ring + 1, _base_quad) * 0.05, SKIRT_DROP_MAX_KM):
			return false
	return true


func _ring_vert_counts() -> PackedInt32Array:
	var out := PackedInt32Array()
	for ring in RING_COUNT:
		# Skirt INCLUDED. The stitch moves each ring's outer row of quads into the
		# skirt mesh, so land-only counts stopped describing "how much of the grid
		# this ring committed" and two assertions built on them started measuring a
		# mechanism that no longer existed.
		out.append(_verts_of(_ring_land[ring]) + _verts_of(_ring_water[ring])
			+ _verts_of(_ring_skirt[ring]))
	return out


func _verts_of(mi: MeshInstance3D) -> int:
	if mi == null or mi.mesh == null or mi.mesh.get_surface_count() == 0:
		return 0
	return mi.mesh.surface_get_array_len(0)
