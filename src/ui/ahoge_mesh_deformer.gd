extends MeshInstance2D

signal deformation_failed(reason: String)

var profile
var current_vertices := PackedVector2Array()
var current_amount: float = 0.0
var vertex_stride_bytes: int = 0
var ready_for_deformation: bool = false
var failure_reason: String = ""
var _array_mesh: ArrayMesh


func setup(texture_value: Texture2D, profile_value) -> bool:
	ready_for_deformation = false
	visible = false
	profile = profile_value
	if profile == null:
		return _fail("固定メッシュの制作データがありません")
	var source_error: String = profile.validate_source(texture_value)
	if not source_error.is_empty():
		return _fail(source_error)
	var geometry_error: String = profile.prepare()
	if not geometry_error.is_empty():
		return _fail(geometry_error)
	texture = texture_value
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	current_vertices = profile.rest_vertices_px.duplicate()
	current_amount = 0.0
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = _vertices_3d(current_vertices)
	arrays[Mesh.ARRAY_TEX_UV] = profile.uvs
	arrays[Mesh.ARRAY_INDEX] = profile.triangle_indices
	_array_mesh = ArrayMesh.new()
	_array_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, Mesh.ARRAY_FLAG_USE_DYNAMIC_UPDATE)
	if _array_mesh.get_surface_count() != 1:
		return _fail("固定メッシュの描画面を作成できません")
	var format_bits: int = _array_mesh.surface_get_format(0)
	vertex_stride_bytes = RenderingServer.mesh_surface_get_format_vertex_stride(format_bits, current_vertices.size())
	var bytes := _vertices_3d(current_vertices).to_byte_array()
	if vertex_stride_bytes * current_vertices.size() != bytes.size():
		return _fail("描画形式と頂点更新バイト配列の長さが一致しません")
	var bounds: Rect2 = profile.local_draw_bounds
	_array_mesh.custom_aabb = AABB(Vector3(bounds.position.x, bounds.position.y, -0.5), Vector3(bounds.size.x, bounds.size.y, 1.0))
	mesh = _array_mesh
	ready_for_deformation = true
	failure_reason = ""
	visible = true
	return true


func set_straighten(value: float) -> bool:
	if not ready_for_deformation:
		return false
	if not is_finite(value):
		return _fail("直線化パラメータが有限値ではありません")
	var amount := clampf(value, 0.0, 1.0)
	if absf(current_amount - amount) < 0.000001:
		return true
	current_vertices = profile.vertices_at(amount)
	var bytes := _vertices_3d(current_vertices).to_byte_array()
	if bytes.size() != vertex_stride_bytes * current_vertices.size():
		return _fail("頂点更新のバイト配列が変化しました")
	# UV、index、surface、mesh RIDは変更せず、頂点バッファだけを更新する。
	_array_mesh.surface_update_vertex_region(0, 0, bytes)
	current_amount = amount
	return true


func _vertices_3d(points: PackedVector2Array) -> PackedVector3Array:
	var vertices := PackedVector3Array()
	vertices.resize(points.size())
	for index in range(points.size()):
		vertices[index] = Vector3(points[index].x, points[index].y, 0.0)
	return vertices


func _fail(reason: String) -> bool:
	ready_for_deformation = false
	failure_reason = reason
	visible = false
	deformation_failed.emit(reason)
	return false
