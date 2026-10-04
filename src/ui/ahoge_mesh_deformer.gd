extends MeshInstance2D

const ProfileScript := preload("res://src/ui/ahoge_mesh_profile.gd")
const PROFILE_PATH: String = "res://assets/characters/prototype/charactor_01/ahoge_mesh_profile.tres"
var profile: ProfileScript
var current_vertices: PackedVector2Array = PackedVector2Array()
var straighten: float = 0.0
var configured: bool = false
var _array_mesh: ArrayMesh


func configure(source: Texture2D) -> bool:
	configured = false
	visible = false
	mesh = null
	profile = load(PROFILE_PATH) as ProfileScript
	if profile == null or not profile.matches_texture(source) or not profile.prepare():
		return false
	texture = source
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	current_vertices = profile.sample(0.0)
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = _vertices_3d(current_vertices)
	arrays[Mesh.ARRAY_TEX_UV] = profile.uvs
	arrays[Mesh.ARRAY_INDEX] = profile.indices
	_array_mesh = ArrayMesh.new()
	_array_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, Mesh.ARRAY_FLAG_USE_DYNAMIC_UPDATE)
	var bounds: Rect2 = profile.draw_bounds
	_array_mesh.custom_aabb = AABB(Vector3(bounds.position.x, bounds.position.y, -1.0), Vector3(bounds.size.x, bounds.size.y, 2.0))
	mesh = _array_mesh
	straighten = 0.0
	configured = true
	visible = true
	return true


func set_straighten(value: float) -> void:
	if not configured:
		return
	var bounded: float = clampf(value, 0.0, 1.0)
	if is_equal_approx(bounded, straighten):
		return
	straighten = bounded
	current_vertices = profile.sample(straighten)
	# indexとUVはconfigure時だけ設定する。動的領域のXYZだけを更新する。
	_array_mesh.surface_update_vertex_region(0, 0, _vertices_3d(current_vertices).to_byte_array())


func _vertices_3d(points: PackedVector2Array) -> PackedVector3Array:
	var result: PackedVector3Array = PackedVector3Array()
	result.resize(points.size())
	for i in range(points.size()):
		result[i] = Vector3(points[i].x, points[i].y, 0.0)
	return result
