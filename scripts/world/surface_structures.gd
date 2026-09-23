class_name SurfaceStructures
extends Node3D
## Three instanced meshes, fixed budget, worker-built buffers. No per-building nodes.
const Layout := preload("res://scripts/world/surface_settlement.gd")
var _nodes: Array[MultiMeshInstance3D] = []
var material: ShaderMaterial
var _sampler: TerrainSampler
var _anchor := Vector3.INF
var _task := -1
var _pending := false
var _result := {}
var _cache := {}
var count := 0

func _setup() -> void:
	material = ShaderMaterial.new()
	material.shader = preload("res://shaders/surface_structure.gdshader")
	for variant in 3:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for part in Layout.parts(variant):
			var box := BoxMesh.new()
			box.size = part.size
			st.append_from(box, 0, Transform3D(Basis.IDENTITY, part.get_center()))
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = st.commit()
		var node := MultiMeshInstance3D.new()
		node.multimesh = mm
		node.material_override = material
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(node)
		_nodes.append(node)

func update_for(sampler: TerrainSampler, hit: Vector3, radius: float, agl: float) -> void:
	if _pending and WorkerThreadPool.is_task_completed(_task):
		WorkerThreadPool.wait_for_task_completion(_task)
		_publish(sampler)
	if sampler != _sampler:
		_sampler = sampler
		_anchor = Vector3.INF
		for node in _nodes:
			node.multimesh.visible_instance_count = 0
		count = 0
	visible = agl < 8.0 and not sampler.settlements.is_empty()
	if not visible:
		return
	if material == null:
		_setup()
	if not _pending and (_anchor == Vector3.INF or hit.distance_to(_anchor) > .35):
		var result := {"sampler": sampler, "anchor": hit}
		_result = result
		_pending = true
		_task = WorkerThreadPool.add_task(func():
			if _cache.get("sampler") != sampler or _cache.size() > 10000:
				_cache.clear()
				_cache["sampler"] = sampler
			result["buffers"] = scatter(sampler, hit, radius, _cache), false, "surface_ruins")

static func scatter(sampler: TerrainSampler, hit: Vector3, radius: float, cache: Dictionary = {}) -> Array:
	var candidates := []
	for index in sampler.settlements.size():
		var region: Dictionary = sampler.settlements[index]
		if hit.normalized().distance_to(region.dir) * radius > float(region.radius) + Layout.DRAW_REACH:
			continue
		var rb: Basis = region.basis
		var p: Vector3 = rb.transposed() * (hit - region.dir * radius)
		var reach := int(ceil(Layout.DRAW_REACH / Layout.STEP))
		var cx := int(floor(p.x / Layout.STEP))
		var cz := int(floor(p.z / Layout.STEP))
		for z in range(cz-reach, cz+reach+1):
			for x in range(cx-reach, cx+reach+1):
				var distance := Vector2((x+.5)*Layout.STEP-p.x, (z+.5)*Layout.STEP-p.z).length_squared()
				if distance <= Layout.DRAW_REACH * Layout.DRAW_REACH:
					candidates.append([distance, index, x, z])
	candidates.sort_custom(func(a, b): return a[0] < b[0])
	var buffers: Array = [[], [], []]
	var count_built := 0
	for candidate in candidates:
		if count_built >= Layout.DRAW_BUDGET:
			break
		var key := Vector3i(candidate[2], candidate[3], candidate[1])
		if not cache.has(key):
			cache[key] = Layout.cell(sampler, sampler.settlements[key.z], key.x, key.y, radius)
		var item: Dictionary = cache[key]
		if item.is_empty():
			continue
		var xf: Transform3D = item.transform
		var p := xf.origin - hit
		var b := xf.basis
		var tint := .68 + SurfaceForest.cell_hash(key.x, key.y, 2, key.z) * .3
		buffers[item.variant].append_array([b.x.x, b.y.x, b.z.x, p.x,
			b.x.y, b.y.y, b.z.y, p.y, b.x.z, b.y.z, b.z.z, p.z,
			tint, tint*.93, tint*.81, float(item.variant) * .5])
		count_built += 1
	return [PackedFloat32Array(buffers[0]), PackedFloat32Array(buffers[1]), PackedFloat32Array(buffers[2])]

func _publish(sampler: TerrainSampler) -> void:
	_pending = false
	if _result.sampler != sampler:
		_result = {}
		return
	_anchor = _result.anchor
	position = _anchor
	count = 0
	for i in 3:
		var buffer: PackedFloat32Array = _result.buffers[i]
		var mm := _nodes[i].multimesh
		mm.instance_count = buffer.size() / 16
		if mm.instance_count > 0:
			mm.buffer = buffer
		mm.visible_instance_count = mm.instance_count
		count += mm.instance_count
	_result = {}

func force_ready() -> void:
	if _pending:
		WorkerThreadPool.wait_for_task_completion(_task)
		_publish(_sampler)

func _exit_tree() -> void:
	if _pending:
		WorkerThreadPool.wait_for_task_completion(_task)
