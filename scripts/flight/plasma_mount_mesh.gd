class_name PlasmaMountMesh
extends RefCounted
## Compact hard-surface cannon, generated once and batched into four materials.
## Coordinates are fractions of hull length, with the emitter facing -Z.
const MUZZLE := Vector3(0, 0, -.106)
var _surfaces: Array[SurfaceTool] = []

func build(length_km: float, paint: Material, dark: Material, steel: Material) -> MeshInstance3D:
	var hot := StandardMaterial3D.new()
	hot.albedo_color = Color(.12, .48, .58)
	hot.emission_enabled = true
	hot.emission = Color(.12, .7, 1)
	hot.emission_energy_multiplier = 1.8
	for material in [dark, paint, steel, hot]:
		var surface := SurfaceTool.new()
		surface.begin(Mesh.PRIMITIVE_TRIANGLES)
		surface.set_material(material)
		_surfaces.append(surface)
	# Stepped receiver, tapered armour cheeks, and a short armoured emitter.
	_loft(0, [Vector3(.020,.015,.056), Vector3(.031,.023,.030), Vector3(.031,.023,-.039), Vector3(.022,.017,-.071)], Vector3.ZERO)
	for side in [-1.0, 1.0]:
		_loft(1, [Vector3(.006,.016,.044), Vector3(.009,.024,.020), Vector3(.009,.024,-.035), Vector3(.005,.013,-.083)], Vector3(side*.027,0,0))
		# Inset cooling fins, kept inside the main silhouette.
		for index in 4:
			_loft(2, [Vector3(.002,.015,.005),Vector3(.002,.015,-.002)], Vector3(side*.036,0,.012-index*.012))
		_loft(3, [Vector3(.001,.002,.021),Vector3(.001,.002,-.029)], Vector3(side*.0365,-.009,0))
	# Top attachment saddle and underside capacitor cover.
	_loft(2, [Vector3(.015,.007,.027),Vector3(.015,.007,-.028)], Vector3(0,.025,0))
	_loft(1, [Vector3(.018,.004,.034),Vector3(.022,.007,.014),Vector3(.018,.007,-.040)], Vector3(0,-.023,0))
	_loft(2, [Vector3(.021,.016,-.064),Vector3(.022,.017,-.077)], Vector3.ZERO)
	# Hollow muzzle: front rim, deep dark bore and recessed emitter. No glowing cap.
	var rear := _profile(Vector3(.024,.019,-.076),Vector3.ZERO)
	var front := _profile(Vector3(.019,.015,-.105),Vector3.ZERO)
	var aperture := _profile(Vector3(.011,.008,-.105),Vector3.ZERO)
	var bore := _profile(Vector3(.010,.007,-.091),Vector3.ZERO)
	_bridge(1,rear,front)
	_bridge(2,front,aperture)
	_bridge(0,aperture,bore)
	_cap(3,bore)
	var mesh := ArrayMesh.new()
	for surface in _surfaces:
		surface.commit(mesh)
	var node := MeshInstance3D.new()
	node.name = "PlasmaCannon"
	node.mesh = mesh
	node.scale = Vector3.ONE*length_km
	return node

func _profile(size: Vector3, offset: Vector3) -> PackedVector3Array:
	var ring := PackedVector3Array()
	for point in [Vector2(-.65,-1),Vector2(.65,-1),Vector2(1,-.65),Vector2(1,.65),Vector2(.65,1),Vector2(-.65,1),Vector2(-1,.65),Vector2(-1,-.65)]:
		ring.append(offset+Vector3(point.x*size.x,point.y*size.y,size.z))
	return ring

func _loft(material: int, stations: Array, offset: Vector3) -> void:
	var previous := _profile(stations[0],offset)
	_cap(material,previous,true)
	for station in stations.slice(1):
		var next := _profile(station,offset)
		_bridge(material,previous,next)
		previous = next
	_cap(material,previous)

func _bridge(material: int, a: PackedVector3Array, b: PackedVector3Array) -> void:
	for i in a.size():
		var j := (i+1)%a.size()
		_triangle(material,a[i],b[i],b[j])
		_triangle(material,a[i],b[j],a[j])

func _cap(material: int, ring: PackedVector3Array, reverse := false) -> void:
	var center := Vector3.ZERO
	for p in ring:
		center += p
	center /= ring.size()
	for i in ring.size():
		var j := (i+1)%ring.size()
		_triangle(material,center,ring[i] if reverse else ring[j],ring[j] if reverse else ring[i])

func _triangle(material: int, a: Vector3, b: Vector3, c: Vector3) -> void:
	# Godot uses clockwise front faces.
	var normal := (b-a).cross(c-a).normalized()
	var surface := _surfaces[material]
	for point in [a,c,b]:
		surface.set_normal(normal)
		surface.add_vertex(point)
