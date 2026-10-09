class_name GalacticCore
extends Node3D
# Seeded 3D bulge, nuclear disc and cusp. Vertices retain physical distances in ly;
# only the final projection is compressed into the existing depth-tested sky shell.
const STAR_SHADER := preload("res://shaders/core_stars.gdshader")
const GAS_SHADER := preload("res://shaders/core_gas.gdshader")
const DISTRIBUTION := preload("res://scripts/world/galactic_core_distribution.gd")
const SEED := DISTRIBUTION.SEED
var _stars: MeshInstance3D
var _gas: MeshInstance3D
var _star_material: ShaderMaterial
var _gas_material: ShaderMaterial
var _last_observer := Vector3(INF, INF, INF)
var _pole := Vector3.ZERO

static func galactic_basis() -> Basis:
	return DISTRIBUTION.galactic_basis()

static func samples() -> Dictionary:
	return DISTRIBUTION.samples()

func _ready() -> void:
	_pole = galactic_basis().y
	var points := samples()
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = points.positions
	arrays[Mesh.ARRAY_COLOR] = points.colors
	arrays[Mesh.ARRAY_TEX_UV] = points.attributes
	var resolved_flags := PackedVector2Array()
	for i in points.positions.size(): resolved_flags.append(Vector2(1.0 if i in points.physical_indices else 0.0, 0.0))
	arrays[Mesh.ARRAY_TEX_UV2] = resolved_flags
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_POINTS, arrays)
	_stars = MeshInstance3D.new()
	_stars.mesh = mesh
	_star_material = ShaderMaterial.new()
	_star_material.shader = STAR_SHADER
	_star_material.render_priority = -110
	_star_material.set_shader_parameter("pole", _pole)
	_stars.material_override = _star_material
	_stars.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_stars.custom_aabb = AABB(Vector3.ONE*-1100000.0, Vector3.ONE*2200000.0)
	add_child(_stars)
	_build_gas()
	refresh(Vector3.ZERO, "")

func _build_gas() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED + 1
	var frame := galactic_basis()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in 180:
		var r := rng.randf_range(50.0, 1400.0)
		var a := rng.randf()*TAU
		var center := frame * Vector3(cos(a)*r, rng.randfn(0.0, 20.0), sin(a)*r)
		var size := rng.randf_range(8.0, 50.0)
		for wrap in [0.0,.5,1.0]:
			for uv in [Vector2(-1,-1),Vector2(1,-1),Vector2(1,1),Vector2(-1,-1),Vector2(1,1),Vector2(-1,1)]:
				st.set_uv(uv)
				st.set_uv2(Vector2(size, float(i)))
				var color := Color(.27,.13,.055,wrap) if i % 4 else Color(.22,.25,.28,wrap)
				st.set_color(color)
				st.add_vertex(center)
	_gas = MeshInstance3D.new()
	_gas.mesh = st.commit()
	_gas_material = ShaderMaterial.new()
	_gas_material.shader = GAS_SHADER
	_gas_material.render_priority = -110
	_gas.material_override = _gas_material
	_gas.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_gas.custom_aabb = AABB(Vector3.ONE*-1100000.0, Vector3.ONE*2200000.0)
	add_child(_gas)

func refresh(ship_off: Vector3, anchor: String) -> void:
	if _stars == null: return
	var origin := SystemDB.coord(Ephemeris.system_id) - SystemDB.coord(SystemDB.SAGITTARIUS_A)
	var body := Ephemeris.pos64(anchor)
	var km_ly := Ephemeris.UNITS_PER_LY
	var observer := origin + Vector3((body[0]+float(ship_off.x))/km_ly,
		(body[1]+float(ship_off.y))/km_ly, (body[2]+float(ship_off.z))/km_ly)
	if observer == _last_observer: return
	_last_observer = observer
	_star_material.set_shader_parameter("observer_ly", observer)
	_gas_material.set_shader_parameter("observer_ly", observer)
