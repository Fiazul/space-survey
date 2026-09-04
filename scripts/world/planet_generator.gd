class_name PlanetGenerator
extends RefCounted
# One cook. Every world is a recipe. A real map when we have evidence,
# invented land/ocean when we do not. Map path is the USGS / NASA swap slot.
# Close-up extras (clouds, night, height) bind when the player goes near.

const COOK_SHADER := preload("res://shaders/planet_cook.gdshader")
const TERRAIN_SHADER := preload("res://shaders/terrain_tile.gdshader")
const AIR_SHELL_SHADER := preload("res://shaders/air_shell.gdshader")

# --- The day/night terminator, shared ---
# planet_cook.gdshader hardcoded smoothstep(-0.04, 0.28, ndotl) in three places.
# The ground tile meets that globe at the tile's own outer edge, so if the tile
# lit itself any other way - Godot's lambert, say - the seam would show a step in
# the light that no parameter twiddling could remove. Both shaders take these as
# uniforms and tools/test_terrain_light.gd asserts they receive the same pair.
const TERMINATOR_LO := -0.04
const TERMINATOR_HI := 0.28
# Starlight / body-shine on the side facing away from the star. Never zero: a
# night side at pure black loses its horizon and reads as a hole in the world.
const NIGHT_FILL := 0.06
# Distance at which haze reaches 63%. Derived, not tasted: it dissolves ring 3's
# 204.8 km rim to 95% (hiding the LOD boundary) while leaving the first 20 km at
# 25%. See the swept table in the light-and-air spec.
const HAZE_KM := 70.0

# Named Sol recipes. albedo is the evidence slot. Missing files fall through
# to colour so a world still cooks. extras bind on approach (ensure_close_maps).
const RECIPES := {
	"Sun": {
		"kind": "star",
		"albedo": "res://assets/planets/sun_2k.jpg",
		"source": "ready-map",
		"evidence": "Solar System Scope / NASA photosphere",
		"cloud_amount": 0.0,
		"water_shine": 0.0,
		"land_amount": 0.0,
		"color_a": Color(1.00, 0.85, 0.30),
		"color_b": Color(1.00, 0.62, 0.18),
	},
	"Earth": {
		"kind": "rocky",
		"albedo": "res://assets/planets/earth_2k.jpg",
		"clouds": "res://assets/planets/earth_clouds_2k.jpg",
		"night": "res://assets/planets/earth_night_2k.jpg",
		"height": "res://assets/planets/earth_height.jpg",
		"specular": "res://assets/planets/earth_spec_2k.png",
		"normal": "res://assets/planets/earth_normal_2k.png",
		"source": "ready-map",
		"evidence": "Solar System Scope / NASA Blue Marble",
		"cloud_amount": 1.0,
		"city_amount": 1.0,
		"water_shine": 0.85,
		"ice_amount": 0.1,
		"air_amount": 1.0,
		"color_ocean": Color(0.03, 0.09, 0.22),
		"color_air": Color(0.30, 0.56, 1.0),
	},
	"Moon": {
		"kind": "rocky",
		"albedo": "res://assets/planets/moon_2k.jpg",
		"source": "ready-map",
		"evidence": "Solar System Scope / NASA LROC",
		"cloud_amount": 0.0,
		"water_shine": 0.0,
		"ice_amount": 0.0,
		"land_amount": 1.0,
		"color_a": Color(0.78, 0.78, 0.80),
	},
	"Mercury": {
		"kind": "rocky",
		"albedo": "res://assets/planets/mercury_2k.jpg",
		"source": "ready-map",
		"evidence": "Solar System Scope / MESSENGER",
		"cloud_amount": 0.0,
		"water_shine": 0.0,
		"ice_amount": 0.02,
		"land_amount": 1.0,
		"color_a": Color(0.533, 0.533, 0.533),
	},
	"Venus": {
		"kind": "rocky",
		"albedo": "res://assets/planets/venus_2k.jpg",
		"source": "ready-map",
		"evidence": "Solar System Scope / Venus cloud tops",
		"cloud_amount": 0.0,
		"water_shine": 0.0,
		"ice_amount": 0.0,
		"land_amount": 1.0,
		"air_amount": 0.35,
		"color_air": Color(0.90, 0.78, 0.45),
		"color_a": Color(0.890, 0.831, 0.714),
	},
	"Mars": {
		"kind": "rocky",
		"albedo": "res://assets/planets/mars_2k.jpg",
		"source": "ready-map",
		"evidence": "Solar System Scope / Viking / MGS",
		"cloud_amount": 0.08,
		"water_shine": 0.0,
		"ice_amount": 0.08,
		"land_amount": 1.0,
		"color_a": Color(0.737, 0.353, 0.263),
	},
	"Jupiter": {
		"kind": "gas",
		"albedo": "res://assets/planets/jupiter_2k.jpg",
		"source": "ready-map",
		"evidence": "Solar System Scope / Cassini / Hubble",
		"cloud_amount": 0.0,
		"water_shine": 0.0,
		"band_count": 10.0,
		"color_a": Color(0.690, 0.498, 0.208),
		"color_b": Color(0.85, 0.70, 0.45),
	},
	"Saturn": {
		"kind": "gas",
		"albedo": "res://assets/planets/saturn_2k.jpg",
		"rings": "res://assets/planets/saturn_ring_2k.png",
		"source": "ready-map",
		"evidence": "Solar System Scope / Cassini",
		"cloud_amount": 0.0,
		"water_shine": 0.0,
		"band_count": 9.0,
		"color_a": Color(0.886, 0.749, 0.490),
		"color_b": Color(0.75, 0.62, 0.40),
	},
	"Uranus": {
		"kind": "ice",
		"albedo": "res://assets/planets/uranus_2k.jpg",
		"source": "ready-map",
		"evidence": "Solar System Scope / Voyager 2",
		"cloud_amount": 0.0,
		"water_shine": 0.0,
		"ice_amount": 0.4,
		"color_a": Color(0.294, 0.439, 0.867),
	},
	"Neptune": {
		"kind": "ice",
		"albedo": "res://assets/planets/neptune_2k.jpg",
		"source": "ready-map",
		"evidence": "Solar System Scope / Voyager 2",
		"cloud_amount": 0.0,
		"water_shine": 0.0,
		"ice_amount": 0.35,
		"color_a": Color(0.153, 0.275, 0.529),
	},
	"Phobos": {
		"kind": "rocky",
		"albedo": "res://assets/planets/phobos_2k.jpg",
		"source": "ready-map",
		"evidence": "Viking mosaic (Stooke / PDS)",
		"cloud_amount": 0.0, "water_shine": 0.0, "land_amount": 1.0,
		"color_a": Color(0.42, 0.40, 0.38),
	},
	"Deimos": {
		"kind": "rocky",
		"albedo": "res://assets/planets/deimos_2k.jpg",
		"source": "ready-map",
		"evidence": "Viking / MRO",
		"cloud_amount": 0.0, "water_shine": 0.0, "land_amount": 1.0,
		"color_a": Color(0.46, 0.44, 0.41),
	},
	"Io": {
		"kind": "rocky",
		"albedo": "res://assets/planets/io_2k.jpg",
		"source": "ready-map",
		"evidence": "Galileo / Voyager",
		"cloud_amount": 0.0, "water_shine": 0.0, "land_amount": 1.0,
		"color_a": Color(0.95, 0.90, 0.50),
		"color_b": Color(0.70, 0.35, 0.12),
	},
	"Europa": {
		"kind": "ice",
		"albedo": "res://assets/planets/europa_2k.jpg",
		"source": "ready-map",
		"evidence": "Galileo / Voyager SSI mosaic",
		"cloud_amount": 0.0, "water_shine": 0.15, "ice_amount": 0.85, "land_amount": 0.2,
		"color_a": Color(0.90, 0.88, 0.82),
		"color_ice": Color(0.92, 0.94, 0.96),
	},
	"Ganymede": {
		"kind": "ice",
		"albedo": "res://assets/planets/ganymede_2k.jpg",
		"source": "ready-map",
		"evidence": "USGS Voyager/Galileo photomosaic",
		"notes": "sheet-grid",
		"cloud_amount": 0.0, "water_shine": 0.0, "ice_amount": 0.45, "land_amount": 0.7,
		"color_a": Color(0.70, 0.64, 0.56),
	},
	"Callisto": {
		"kind": "ice",
		"albedo": "res://assets/planets/callisto_2k.jpg",
		"source": "ready-map",
		"evidence": "Voyager mosaic (JPL/USGS)",
		"cloud_amount": 0.0, "water_shine": 0.0, "ice_amount": 0.3, "land_amount": 1.0,
		"color_a": Color(0.50, 0.46, 0.44),
	},
	"Titan": {
		"kind": "ice",
		"albedo": "res://assets/planets/titan_2k.jpg",
		"source": "ready-map",
		"evidence": "Cassini ISS / VIMS",
		"cloud_amount": 0.55, "water_shine": 0.2, "ice_amount": 0.15, "land_amount": 0.45,
		"air_amount": 0.55,
		"color_air": Color(0.85, 0.62, 0.22),
		"color_a": Color(0.92, 0.66, 0.30),
		"color_ocean": Color(0.25, 0.22, 0.18),
	},
	"Enceladus": {
		"kind": "ice",
		"albedo": "res://assets/planets/enceladus_2k.jpg",
		"source": "ready-map",
		"evidence": "Cassini",
		"cloud_amount": 0.0, "water_shine": 0.05, "ice_amount": 0.95, "land_amount": 0.1,
		"color_a": Color(0.92, 0.93, 0.94),
	},
	"Mimas": {
		"kind": "ice",
		"albedo": "res://assets/planets/mimas_2k.jpg",
		"source": "ready-map",
		"evidence": "Cassini",
		"cloud_amount": 0.0, "water_shine": 0.0, "ice_amount": 0.7, "land_amount": 1.0,
		"color_a": Color(0.72, 0.70, 0.66),
	},
	"Tethys": {
		"kind": "ice",
		"albedo": "res://assets/planets/tethys_2k.jpg",
		"source": "ready-map",
		"evidence": "Cassini",
		"cloud_amount": 0.0, "water_shine": 0.0, "ice_amount": 0.8, "land_amount": 1.0,
		"color_a": Color(0.80, 0.80, 0.78),
	},
	"Dione": {
		"kind": "ice",
		"albedo": "res://assets/planets/dione_2k.jpg",
		"source": "ready-map",
		"evidence": "Cassini",
		"cloud_amount": 0.0, "water_shine": 0.0, "ice_amount": 0.7, "land_amount": 1.0,
		"color_a": Color(0.74, 0.73, 0.70),
	},
	"Rhea": {
		"kind": "ice",
		"albedo": "res://assets/planets/rhea_2k.jpg",
		"source": "ready-map",
		"evidence": "Cassini",
		"cloud_amount": 0.0, "water_shine": 0.0, "ice_amount": 0.65, "land_amount": 1.0,
		"color_a": Color(0.70, 0.68, 0.64),
	},
	"Iapetus": {
		"kind": "rocky",
		"albedo": "res://assets/planets/iapetus_2k.jpg",
		"source": "ready-map",
		"evidence": "Cassini two-tone",
		"cloud_amount": 0.0, "water_shine": 0.0, "ice_amount": 0.35, "land_amount": 1.0,
		"color_a": Color(0.55, 0.42, 0.32),
		"color_b": Color(0.88, 0.86, 0.82),
	},
	"Miranda": {
		"kind": "ice",
		"albedo": "res://assets/planets/miranda_2k.jpg",
		"source": "ready-map",
		"evidence": "Voyager 2",
		"cloud_amount": 0.0, "water_shine": 0.0, "ice_amount": 0.6, "land_amount": 1.0,
		"color_a": Color(0.62, 0.60, 0.58),
	},
	"Ariel": {
		"kind": "ice",
		"albedo": "res://assets/planets/ariel_2k.jpg",
		"source": "ready-map",
		"evidence": "Voyager 2",
		"cloud_amount": 0.0, "water_shine": 0.0, "ice_amount": 0.7, "land_amount": 1.0,
		"color_a": Color(0.70, 0.68, 0.66),
	},
	"Umbriel": {
		"kind": "ice",
		"albedo": "res://assets/planets/umbriel_2k.jpg",
		"source": "ready-map",
		"evidence": "Voyager 2",
		"cloud_amount": 0.0, "water_shine": 0.0, "ice_amount": 0.55, "land_amount": 1.0,
		"color_a": Color(0.40, 0.38, 0.36),
	},
	"Titania": {
		"kind": "ice",
		"albedo": "res://assets/planets/titania_2k.jpg",
		"source": "ready-map",
		"evidence": "Voyager 2",
		"cloud_amount": 0.0, "water_shine": 0.0, "ice_amount": 0.6, "land_amount": 1.0,
		"color_a": Color(0.58, 0.52, 0.48),
	},
	"Oberon": {
		"kind": "ice",
		"albedo": "res://assets/planets/oberon_2k.jpg",
		"source": "ready-map",
		"evidence": "Voyager 2",
		"cloud_amount": 0.0, "water_shine": 0.0, "ice_amount": 0.55, "land_amount": 1.0,
		"color_a": Color(0.52, 0.46, 0.42),
	},
	"Triton": {
		"kind": "ice",
		"albedo": "res://assets/planets/triton_2k.jpg",
		"source": "ready-map",
		"evidence": "Voyager 2",
		"cloud_amount": 0.05, "water_shine": 0.05, "ice_amount": 0.7, "land_amount": 0.6,
		"color_a": Color(0.72, 0.68, 0.62),
		"color_b": Color(0.55, 0.45, 0.55),
	},
	"Pluto": {
		"kind": "ice",
		"albedo": "res://assets/planets/pluto_2k.jpg",
		"source": "ready-map",
		"evidence": "New Horizons MVIC extended color",
		"cloud_amount": 0.0, "water_shine": 0.0, "ice_amount": 0.35, "land_amount": 1.0,
		"color_a": Color(0.72, 0.60, 0.48),
		"color_b": Color(0.85, 0.78, 0.70),
	},
	"Charon": {
		"kind": "ice",
		"albedo": "res://assets/planets/charon_2k.jpg",
		"source": "ready-map",
		"evidence": "New Horizons",
		"cloud_amount": 0.0, "water_shine": 0.0, "ice_amount": 0.4, "land_amount": 1.0,
		"color_a": Color(0.62, 0.55, 0.50),
	},
}

const CLOSE_KEYS := ["clouds", "night", "height", "specular", "normal"]


# Catalog row → cook spec. No GLB. Spectral/size pick kind and colour.
static func color_from_spectral(sp: String) -> Color:
	var c := sp.strip_edges().to_upper()
	if c.is_empty():
		return Color(1.00, 0.85, 0.50)
	match c[0]:
		"O":
			return Color(0.60, 0.70, 1.00)
		"B":
			return Color(0.70, 0.80, 1.00)
		"A":
			return Color(0.95, 0.96, 1.00)
		"F":
			return Color(1.00, 0.98, 0.92)
		"G":
			return Color(1.00, 0.92, 0.65)
		"K":
			return Color(1.00, 0.76, 0.42)
		"M":
			return Color(1.00, 0.50, 0.30)
		"L", "T":
			return Color(0.72, 0.34, 0.26)
		"D":
			return Color(0.86, 0.90, 1.00)
		_:
			return Color(1.00, 0.85, 0.50)


static func catalog_star(row: Dictionary) -> Dictionary:
	var sp := str(row.get("spectral", ""))
	var col := color_from_spectral(sp)
	if row.has("color"):
		col = row.color
	return {
		"name": str(row.get("name", "Star")),
		"star": true,
		"live": false,
		"pos": row.get("pos", Vector3.ZERO),
		"radius": float(row.get("radius", 5.0)),
		"mass": float(row.get("mass", 40000.0)),
		"color": col,
		"glow": 2.0,
		"spectral": sp,
	}


static func catalog_planet(row: Dictionary) -> Dictionary:
	var re := float(row.get("pl_rade", row.get("radius_earth", 1.0)))
	var teq := float(row.get("pl_eqt", 280.0))
	var kind := "rocky"
	if re >= 8.0:
		kind = "gas"
	elif re >= 2.0:
		kind = "ice"
	elif teq < 220.0:
		kind = "ice"
	var col := Color(0.55, 0.45, 0.38)
	if kind == "gas":
		col = Color(0.85, 0.55, 0.28) if teq > 800.0 else Color(0.55, 0.70, 0.85)
	elif kind == "ice":
		col = Color(0.32, 0.55, 0.72)
	elif teq > 400.0:
		col = Color(0.72, 0.40, 0.28)
	return {
		"name": str(row.get("name", "Planet")),
		"star": false,
		"kind": kind,
		"pl_rade": re,
		"radius": clampf(re * 1.4, 1.2, 8.0),
		"color": col,
		"glow": 0.4,
		"live": false,
		"pos": row.get("pos", Vector3(8.0, 0.4, 5.0)),
	}


static func recipe_for(spec: Dictionary) -> Dictionary:
	var name := str(spec.get("name", ""))
	if RECIPES.has(name):
		var r: Dictionary = (RECIPES[name] as Dictionary).duplicate()
		r["name"] = name
		r["features"] = r.get("features", [])
		if not has_map(r):
			r["source"] = "named-pending-map"
		return r
	return invent(spec)


static func invent(spec: Dictionary) -> Dictionary:
	var name := str(spec.get("name", ""))
	var color: Color = spec.get("color", Color(0.5, 0.5, 0.5))
	var kind := "rocky"
	var ocean_world := color.b > color.r + 0.08 and color.b > 0.45
	var asked := str(spec.get("kind", ""))
	if spec.get("star", false) or asked == "star":
		kind = "star"
	elif asked == "rocky" or asked == "gas" or asked == "ice":
		kind = asked
	elif spec.get("ring", false):
		kind = "gas"
	elif ocean_world:
		kind = "ice" if float(spec.get("radius", 1.0)) < 4.0 else "gas"
	elif float(spec.get("radius", 1.0)) >= 6.0 and not spec.get("physical", false):
		kind = "gas"
	var land := 0.55
	var clouds := 0.38
	var ice := 0.08
	var shine := 0.35
	var ocean := Color(0.03, 0.10, 0.22)
	var land_c := color
	if kind == "star":
		land = 0.0
		clouds = 0.0
		shine = 0.0
		ice = 0.0
	elif kind == "gas":
		land = 0.0
		clouds = 0.0
		shine = 0.0
		ice = 0.0
	elif kind == "ice" or ocean_world:
		land = 0.18
		clouds = 0.55
		ice = 0.28
		shine = 0.75
		ocean = Color(color.r * 0.25, color.g * 0.35, color.b * 0.55).darkened(0.35)
		land_c = Color(0.24, 0.36, 0.18)
	else:
		land = 0.62
		clouds = 0.22
		shine = 0.2
		ocean = Color(0.04, 0.12, 0.18)
		land_c = color
	return {
		"name": name,
		"kind": kind,
		"albedo": "",
		"clouds": "",
		"night": "",
		"source": "invented",
		"evidence": _invent_evidence(spec),
		"color_a": color,
		"color_b": color.lightened(0.18),
		"color_land": land_c,
		"color_ocean": ocean,
		"ice_amount": ice,
		"land_amount": land,
		"cloud_amount": clouds,
		"city_amount": 0.0,
		"water_shine": shine,
		"air_amount": 0.0,
		"seed": float(name.hash() % 10000) * 0.017,
		"features": [],
	}


static func _invent_evidence(spec: Dictionary) -> String:
	var sp := str(spec.get("spectral", ""))
	if sp != "":
		return "catalog spectral %s" % sp
	if spec.has("pl_rade"):
		return "catalog radius %.2f Re" % float(spec.pl_rade)
	return "invented from type/mass/color"


static func has_map(recipe: Dictionary) -> bool:
	return _tex_exists(str(recipe.get("albedo", "")))


static func has_rings(recipe: Dictionary) -> bool:
	return _tex_exists(str(recipe.get("rings", "")))


static func _tex_exists(path: String) -> bool:
	if path.is_empty():
		return false
	return FileAccess.file_exists(path) or ResourceLoader.exists(path)


static func paint(spec: Dictionary, radius: float) -> Dictionary:
	var recipe := recipe_for(spec)
	var mi := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	var physical: bool = spec.get("physical", false)
	var is_star: bool = spec.get("star", false) or str(recipe.get("kind", "")) == "star"
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 192 if physical else 32
	mesh.rings = 96 if physical else 16
	if is_star and physical:
		mesh.radial_segments = 96
		mesh.rings = 48
	mi.mesh = mesh
	var mat := make_material(recipe, spec)
	mi.material_override = mat
	mi.visible = false
	if physical:
		mi.extra_cull_margin = 8000.0
	return { "sphere": mi, "mat": mat, "recipe": recipe }


static func make_material(recipe: Dictionary, spec: Dictionary) -> Material:
	return _cook_material(recipe, spec, false)


static func apply_sky(mat: Material, recipe: Dictionary, spec: Dictionary) -> void:
	if mat is StandardMaterial3D:
		var sm := mat as StandardMaterial3D
		if has_map(recipe):
			var tex := load(str(recipe.albedo)) as Texture2D
			if tex != null:
				sm.albedo_texture = tex
				sm.albedo_color = Color.WHITE
				sm.emission_texture = tex
		else:
			sm.albedo_color = spec.get("color", Color.WHITE)
			sm.emission = spec.get("color", Color.WHITE)


static func apply_view(mat: Material, sun_dir: Vector3, detail: float) -> void:
	if mat is ShaderMaterial:
		var sm := mat as ShaderMaterial
		if sun_dir.length_squared() < 0.0001:
			sun_dir = Vector3(0.72, 0.28, 0.63)
		sm.set_shader_parameter("sun_dir", sun_dir.normalized())
		sm.set_shader_parameter("detail", clampf(detail, 0.0, 1.0))


# Bind height/clouds/night when the player is close. Albedo is already on.
static func ensure_close_maps(mat: Material, recipe: Dictionary) -> void:
	if not mat is ShaderMaterial:
		return
	var sm := mat as ShaderMaterial
	for key in CLOSE_KEYS:
		var flag := _flag_for(key)
		if float(sm.get_shader_parameter(flag)) > 0.5:
			continue
		_bind_tex(sm, recipe, key, _tex_for(key), flag)


static func close_enough(dist: float, radius: float) -> bool:
	if dist < 80000.0:
		return true
	return dist < maxf(radius * 22.0, 400.0)


# --- Skin band ceiling ---
# This rule REPLACED a plate-width one, and the reason matters more than the
# numbers. The old ceiling (3.24 km) came from TILE_KM_MAX * 0.09, because a
# single local plate only reads as ground while its width dwarfs your altitude -
# a 36 km plate seen from 100 km up is a sticker on a globe. Four nested rings
# reach 205 km, so that constraint no longer exists.
#
# The ceiling's job is now the OPPOSITE one: open the band ABOVE the tallest
# terrain, or you enter the band already inside a mountain. Do not reintroduce a
# plate-ratio rule here - it no longer describes anything real.
const BAND_CEILING_MULT := 1.7      # headroom above the highest ground
const BAND_CEILING_MIN_KM := 3.0    # floor for a world so flat that 1.7x its own
                                    # relief would open the band underground


# Ceiling of the band for this world, km above sea level.
# Earth: the DEM's highest sample plus detail headroom is 9.51 km, x 1.7 = 16.2.
# A world with no map: 3.2 km of noise relief x 0.96875 x 1.7 = 5.27.
static func band_ceiling_km(sampler: TerrainSampler) -> float:
	if sampler == null:
		return BAND_CEILING_MIN_KM
	return maxf(sampler.max_height_km() * BAND_CEILING_MULT, BAND_CEILING_MIN_KM)


static func close_detail(alt_km: float) -> float:
	const NEAR_KM := 2.0
	const FAR_KM := 35.0
	if alt_km >= FAR_KM:
		return 0.0
	if alt_km <= NEAR_KM:
		return 1.0
	return 1.0 - (alt_km - NEAR_KM) / (FAR_KM - NEAR_KM)


# Is a ground tile allowed at this altitude? Above the kill line (you are alive)
# and below this world's own ceiling. The ceiling is PER-WORLD now, so it arrives
# as an argument instead of being read off a global constant - see band_ceiling_km.
#
# Earth's window is still empty at this point in the work, but for a different
# reason than before: its ceiling now clears Everest (16.2 km) and what keeps the
# band shut is the 29 km kill bubble sitting above it. Moving that bubble to
# contact is what opens Earth.
static func ground_stamp_ok(alt_km: float, kill_km: float, ceiling_km: float) -> bool:
	return alt_km > kill_km and alt_km < ceiling_km


# Does a body get a ground tile at all? A gas giant and a star have no surface to
# stand a plate on. Every rocky / ice world does, mapped or invented.
static func has_surface(recipe: Dictionary) -> bool:
	var kind := str(recipe.get("kind", "rocky"))
	return kind == "rocky" or kind == "ice"


# Which kit morphology dresses the tile. Recipe-driven, per the asset-kit spec:
# recognizable vegetation needs a biosphere, so "tree" is gated on real air AND
# standing liquid, not on a colour. Cold worlds get ice shards, the rest bare
# rock. These are separate meshes on purpose — recolouring a tree blue does not
# make it an ice spire, and recolouring lava does not make it cryovolcanism.
static func surface_kit(recipe: Dictionary) -> String:
	if not has_surface(recipe):
		return "none"
	if float(recipe.get("air_amount", 0.0)) > 0.5 and float(recipe.get("water_shine", 0.0)) > 0.3:
		return "tree"
	if float(recipe.get("ice_amount", 0.0)) > 0.25:
		return "ice"
	return "rock"


# --- Crust height, shared with the shader ---
# planet_cook.gdshader's sample_height() falls back to fbm(n * CRUST_FREQ + seed)
# for any world with no height map. The ground tile MUST use the same function
# with the same seed, or the hills you fly over disagree with the crust the globe
# above you is painting. hash3/noise3/fbm3 are a line-for-line mirror of that
# shader's hash/noise/fbm — if you touch one, touch both.
const CRUST_FREQ := 6.0


static func _hash3(p: Vector3) -> float:
	var v: float = sin(p.dot(Vector3(127.1, 311.7, 74.7))) * 43758.5453
	return v - floor(v)


static func _noise3(p: Vector3) -> float:
	var i := p.floor()
	var f := p - i
	f = f * f * (Vector3(3.0, 3.0, 3.0) - f * 2.0)
	var n000 := _hash3(i)
	var n100 := _hash3(i + Vector3(1.0, 0.0, 0.0))
	var n010 := _hash3(i + Vector3(0.0, 1.0, 0.0))
	var n110 := _hash3(i + Vector3(1.0, 1.0, 0.0))
	var n001 := _hash3(i + Vector3(0.0, 0.0, 1.0))
	var n101 := _hash3(i + Vector3(1.0, 0.0, 1.0))
	var n011 := _hash3(i + Vector3(0.0, 1.0, 1.0))
	var n111 := _hash3(i + Vector3(1.0, 1.0, 1.0))
	var nx00 := lerpf(n000, n100, f.x)
	var nx10 := lerpf(n010, n110, f.x)
	var nx01 := lerpf(n001, n101, f.x)
	var nx11 := lerpf(n011, n111, f.x)
	return lerpf(lerpf(nx00, nx10, f.y), lerpf(nx01, nx11, f.y), f.z)


static func fbm3(p: Vector3) -> float:
	return fbm3_octaves(p, 5)


# Same fbm with a chosen octave count. fbm3() must stay at FIVE because it mirrors
# planet_cook.gdshader exactly - change that and the tile's hills stop matching the
# crust painted on the globe. Decorative detail can afford fewer: each octave is 8
# hash() calls (40 sin() at five), and that is the single dominant cost in a ring
# rebuild. Octaves 4 and 5 contribute at most 9% of the amplitude.
static func fbm3_octaves(p: Vector3, octaves: int) -> float:
	var a := 0.5
	var s := 0.0
	var q := p
	for _i in maxi(octaves, 1):
		s += a * _noise3(q)
		q *= 2.07
		a *= 0.5
	return s


# Height at a point on the crust, 0..1-ish, for a world with no height map.
# `n` is the outward unit normal in MODEL space (the same vector the shader uses).
static func crust_height(n: Vector3, seed_v: float) -> float:
	return fbm3(n * CRUST_FREQ + Vector3(seed_v, seed_v, seed_v))


# One sampler per body, built from its recipe. Callers must SHARE the instance —
# the ring mesh builder and the contact kill have to be looking at the same
# terrain, or you die in clear air or fly through rock. PlanetSystem owns the
# per-body cache (see terrain_sampler_for).
static func terrain_sampler(recipe: Dictionary) -> TerrainSampler:
	return TerrainSampler.new(recipe)


# Material for the skin-band ground rings. Lit and hazed, running the SAME
# terminator as the globe above it.
static func terrain_material(recipe: Dictionary, spec: Dictionary) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = TERRAIN_SHADER
	mat.set_shader_parameter("term_lo", TERMINATOR_LO)
	mat.set_shader_parameter("term_hi", TERMINATOR_HI)
	mat.set_shader_parameter("night_fill", NIGHT_FILL)
	mat.set_shader_parameter("haze_km", HAZE_KM)
	mat.set_shader_parameter("air_amount", float(recipe.get("air_amount", 0.0)))
	var air: Color = recipe.get("color_air", Color(0.30, 0.56, 1.0))
	mat.set_shader_parameter("color_air", Vector3(air.r, air.g, air.b))
	var warm := sun_warm_for(spec)
	mat.set_shader_parameter("sun_warm", Vector3(warm.r, warm.g, warm.b))
	return mat


# Material for the inside-the-atmosphere sky shell.
static func air_shell_material(recipe: Dictionary, spec: Dictionary) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = AIR_SHELL_SHADER
	var air: Color = recipe.get("color_air", Color(0.30, 0.56, 1.0))
	mat.set_shader_parameter("color_air", Vector3(air.r, air.g, air.b))
	var warm := sun_warm_for(spec)
	mat.set_shader_parameter("sun_warm", Vector3(warm.r, warm.g, warm.b))
	mat.set_shader_parameter("opacity", 0.0)
	return mat


# The warm colour haze takes when you look toward the star. Derived from the
# star's own spectral colour, so a red dwarf's horizon is red without any per-
# system table entry. Lifted toward white because scattered light is paler than
# the source.
static func sun_warm_for(spec: Dictionary) -> Color:
	var c: Color = color_from_spectral(str(spec.get("spectral", "G")))
	return c.lerp(Color(1.0, 1.0, 1.0), 0.35)


# How much sky there is at this altitude. depth^1.5 so it fades out well before
# the air does: 0.78 at 15 km of Earth's 100 km column, 0.09 at 80 km. Orbit
# keeps its black sky, and the band gets a real one.
static func air_shell_opacity(alt_km: float, atmo_top_km: float, air_amount: float) -> float:
	if atmo_top_km <= 0.0 or air_amount <= 0.0:
		return 0.0
	var depth := clampf(1.0 - alt_km / atmo_top_km, 0.0, 1.0)
	return pow(depth, 1.5) * clampf(air_amount, 0.0, 1.0)


# How much thicker the haze is down low. Flying the deck you look through far
# more air than you do from the ceiling.
static func haze_density_at(alt_km: float, ceiling_km: float) -> float:
	if ceiling_km <= 0.0:
		return 1.0
	return lerpf(1.35, 0.7, clampf(alt_km / ceiling_km, 0.0, 1.0))


static func make_ring_material(recipe: Dictionary) -> StandardMaterial3D:
	var rmat := StandardMaterial3D.new()
	rmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	rmat.cull_mode = BaseMaterial3D.CULL_DISABLED
	rmat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_ALWAYS
	rmat.albedo_color = Color(0.86, 0.79, 0.60, 0.85)
	if has_rings(recipe):
		var tex := load(str(recipe.rings)) as Texture2D
		if tex != null:
			rmat.albedo_texture = tex
			rmat.albedo_color = Color(1, 1, 1, 1)
	return rmat


static func _cook_material(recipe: Dictionary, spec: Dictionary, close: bool) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = COOK_SHADER
	var a: Color = recipe.get("color_a", spec.get("color", Color(0.45, 0.4, 0.35)))
	var b: Color = recipe.get("color_b", a.lightened(0.18))
	var land_c: Color = recipe.get("color_land", a)
	var ocean: Color = recipe.get("color_ocean", Color(0.03, 0.09, 0.22))
	mat.set_shader_parameter("color_a", Vector3(a.r, a.g, a.b))
	mat.set_shader_parameter("color_b", Vector3(b.r, b.g, b.b))
	mat.set_shader_parameter("color_land", Vector3(land_c.r, land_c.g, land_c.b))
	mat.set_shader_parameter("color_ocean", Vector3(ocean.r, ocean.g, ocean.b))
	var ice_c: Color = recipe.get("color_ice", Color(0.86, 0.89, 0.93))
	mat.set_shader_parameter("color_ice", Vector3(ice_c.r, ice_c.g, ice_c.b))
	var kind := str(recipe.get("kind", "rocky"))
	mat.set_shader_parameter("kind", _kind_id(kind))
	mat.set_shader_parameter("term_lo", TERMINATOR_LO)
	mat.set_shader_parameter("term_hi", TERMINATOR_HI)
	mat.set_shader_parameter("seed", float(recipe.get("seed", 0.0)))
	mat.set_shader_parameter("ice_amount", float(recipe.get("ice_amount", 0.12)))
	mat.set_shader_parameter("land_amount", float(recipe.get("land_amount", 0.32)))
	mat.set_shader_parameter("cloud_amount", float(recipe.get("cloud_amount", 0.4)))
	mat.set_shader_parameter("city_amount", float(recipe.get("city_amount", 0.0)))
	mat.set_shader_parameter("water_shine", float(recipe.get("water_shine", 0.5)))
	mat.set_shader_parameter("air_amount", float(recipe.get("air_amount", 0.0)))
	var air_c: Color = recipe.get("color_air", Color(0.30, 0.56, 1.0))
	mat.set_shader_parameter("color_air", Vector3(air_c.r, air_c.g, air_c.b))
	mat.set_shader_parameter("band_count", float(recipe.get("band_count", 9.0 if kind == "gas" else 6.0)))
	_bind_tex(mat, recipe, "albedo", "albedo_tex", "has_albedo")
	if close:
		for key in CLOSE_KEYS:
			_bind_tex(mat, recipe, key, _tex_for(key), _flag_for(key))
	else:
		for key in CLOSE_KEYS:
			mat.set_shader_parameter(_flag_for(key), 0.0)
	return mat


static func _kind_id(kind: String) -> int:
	if kind == "gas":
		return 1
	if kind == "ice":
		return 2
	if kind == "star":
		return 3
	return 0


static func _tex_for(key: String) -> String:
	match key:
		"clouds":
			return "cloud_tex"
		"night":
			return "night_tex"
		"height":
			return "height_tex"
		"specular":
			return "spec_tex"
		"normal":
			return "normal_tex"
		_:
			return "albedo_tex"


static func _flag_for(key: String) -> String:
	match key:
		"clouds":
			return "has_clouds"
		"night":
			return "has_night"
		"height":
			return "has_height"
		"specular":
			return "has_spec"
		"normal":
			return "has_normal"
		_:
			return "has_albedo"


static func _bind_tex(mat: ShaderMaterial, recipe: Dictionary, key: String, tex_u: String, flag_u: String) -> void:
	var path := str(recipe.get(key, ""))
	if _tex_exists(path):
		var tex := load(path) as Texture2D
		if tex != null:
			mat.set_shader_parameter(tex_u, tex)
			mat.set_shader_parameter(flag_u, 1.0)
			return
	mat.set_shader_parameter(flag_u, 0.0)
