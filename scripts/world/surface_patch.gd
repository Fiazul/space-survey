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
const RING_0_QUAD_KM := 0.05        # 50 m
const RING_STEP := 4.0              # each ring out is this much coarser
# Rings 1..3 are DONUTS: the footprint the finer ring inside already covers is
# skipped, so nothing overdraws and the triangle budget stays flat with altitude.
# Each ring's outer edge drops straight down by one of its own quads. Adjacent
# rings sample the same height function at different rates, so their edges do not
# meet exactly; the skirt hides that gap and is invisible from above.
const SKIRT_QUADS := 1.0
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
	_props = MultiMeshInstance3D.new()
	_props.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_props.multimesh = _make_prop_multimesh(_kit)
	add_child(_props)
	visible = false


# Quad size of a ring, km. Ring 0 is the fine one under the hull.
static func ring_quad_km(ring: int) -> float:
	return RING_0_QUAD_KM * pow(RING_STEP, float(ring))


# How far a ring reaches from the hull, km, edge to edge.
static func ring_reach_km(ring: int) -> float:
	return ring_quad_km(ring) * float(RING_SEGS)


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
	var kit: String = PlanetGenerator.surface_kit(recipe)
	if kit != _kit or _props.multimesh == null:
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


func update_for(ship_pos: Vector3, body: String, physical: bool, radius: float,
		alt: float, kill: float, ceiling: float, recipe: Dictionary) -> void:
	if not should_show(body, physical, alt, kill, ceiling, recipe):
		visible = false
		return
	if _body != body or _sampler == null:
		bind_body(recipe, PlanetGenerator.terrain_sampler(recipe))
		_body = body
	visible = true
	var hit: Vector3 = ship_pos.normalized() * radius
	# Each ring rebuilds only when the hull has crossed one of ITS OWN quads, so
	# ring 0 follows you closely and cheaply while ring 3 almost never moves.
	for i in RING_COUNT:
		if _ring_anchor[i] == Vector3.ZERO or hit.distance_to(_ring_anchor[i]) > ring_quad_km(i):
			_build_ring(i, hit, radius)
			_ring_anchor[i] = hit
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
	var quad := ring_quad_km(ring)
	var half := ring_reach_km(ring) * 0.5
	# A donut: skip the ground the finer ring inside already owns.
	var hole := 0.0 if ring == 0 else ring_reach_km(ring - 1) * 0.5
	var land_st := SurfaceTool.new()
	var wat_st := SurfaceTool.new()
	var skirt_st := SurfaceTool.new()
	land_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	wat_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	skirt_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var skirted := false
	var prop_xforms: Array[Transform3D] = []
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
			var p00 := _vert(hit, up, east, north, radius, e0, n0)
			var p10 := _vert(hit, up, east, north, radius, e1, n0)
			var p01 := _vert(hit, up, east, north, radius, e0, n1)
			var p11 := _vert(hit, up, east, north, radius, e1, n1)
			var wet: float = (float(p00.w) + float(p10.w) + float(p01.w) + float(p11.w)) * 0.25
			var st: SurfaceTool = wat_st if wet > 0.55 else land_st
			var nrm: Vector3 = (p10.p - p00.p).cross(p01.p - p00.p)
			if nrm.length_squared() < 1e-10:
				nrm = up
			else:
				nrm = nrm.normalized()
			_tri(st, p00, p10, p11, nrm)
			_tri(st, p00, p11, p01, nrm)
			# Skirt the ring's outer rim so the seam to the next ring cannot show.
			var drop := quad * SKIRT_QUADS
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
					var sc: float = 0.012 + seedn * 0.028
					t.basis = Basis(east, nrm, north).orthonormalized().scaled(
						Vector3(sc, sc * _prop_aspect(seedn), sc))
					t.origin = p00.p + nrm * sc * 0.9
					prop_xforms.append(t)
	_ring_land[ring].mesh = land_st.commit()
	_ring_land[ring].material_override = _mat(false)
	_ring_water[ring].mesh = wat_st.commit()
	_ring_water[ring].material_override = _mat(true)
	_ring_skirt[ring].mesh = skirt_st.commit() if skirted else null
	_ring_skirt[ring].material_override = _mat(false)
	if ring == 0:
		_place_props(prop_xforms, hit, east, north)


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
	_tri(st, a, b, b_lo, nrm)
	_tri(st, a, b_lo, a_lo, nrm)


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
	var wet: float = 1.0 if _sampler.is_water(dir) else 0.0
	# 0..1 of this world's own relief, for prop placement and colour banding.
	var h: float = clampf((gr - radius) / maxf(_sampler.max_height_km(), 0.001), 0.0, 1.0)
	return { "p": dir * gr, "h": h, "w": wet, "c": _color_at(dir, uv, h), "uv": uv }


# Ground colour. Albedo map where the world has one, else the recipe's crust
# colours. Slice A5 replaces this with the sampler's shared palette, because at
# these altitudes the map is under two texels across the whole ring and carries
# no detail — see the spec.
func _color_at(dir: Vector3, uv: Vector2, h: float) -> Color:
	if _aimg != null:
		return _sample(_aimg, uv)
	var mixf: float = PlanetGenerator.fbm3(dir * 5.0 + Vector3(_seed, _seed, _seed))
	return _crust_a.lerp(_crust_b, clampf(mixf, 0.0, 1.0)).lightened(clampf(h - 0.5, 0.0, 0.3))


func _tri(st: SurfaceTool, a: Dictionary, b: Dictionary, c: Dictionary, n: Vector3) -> void:
	st.set_normal(n)
	st.set_color(a.c)
	st.set_uv(a.uv)
	st.add_vertex(a.p)
	st.set_normal(n)
	st.set_color(b.c)
	st.set_uv(b.uv)
	st.add_vertex(b.p)
	st.set_normal(n)
	st.set_color(c.c)
	st.set_uv(c.uv)
	st.add_vertex(c.p)


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


# A boulder: one squashed octahedron with the equator jittered, so a MultiMesh of
# them reads as scattered rock rather than a field of identical pyramids.
func _rock_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var stone := Color(0.44, 0.41, 0.38)
	var dark := Color(0.28, 0.26, 0.24)
	var top := Vector3(0.06, 0.62, -0.04)
	var bot := Vector3(-0.03, 0.0, 0.05)
	var nseg := 6
	var ring: Array[Vector3] = []
	for i in nseg:
		var a := TAU * float(i) / float(nseg)
		var r := 0.36 + _hash(Vector2(float(i), 3.0)) * 0.20
		var y := 0.22 + _hash(Vector2(float(i), 7.0)) * 0.14
		ring.append(Vector3(cos(a) * r, y, sin(a) * r))
	for i in nseg:
		var p0: Vector3 = ring[i]
		var p1: Vector3 = ring[(i + 1) % nseg]
		_face(st, top, p0, p1, stone)
		_face(st, bot, p1, p0, dark)
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
	var n: Vector3 = (b - a).cross(c - a)
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
		var n: Vector3 = (p[f[1]] - p[f[0]]).cross(p[f[2]] - p[f[0]]).normalized()
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
		"ring0_reach_km": ring_reach_km(0),
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
		if ring_quad_km(ring) * SKIRT_QUADS < ring_quad_km(ring + 1) * 0.05:
			return false
	return true


func _ring_vert_counts() -> PackedInt32Array:
	var out := PackedInt32Array()
	for ring in RING_COUNT:
		out.append(_verts_of(_ring_land[ring]) + _verts_of(_ring_water[ring]))
	return out


func _verts_of(mi: MeshInstance3D) -> int:
	if mi == null or mi.mesh == null or mi.mesh.get_surface_count() == 0:
		return 0
	return mi.mesh.surface_get_array_len(0)
