extends MeshInstance2D

const ProfileScript := preload("res://src/ui/ahoge_mesh_profile.gd")
const ParryMotionScript := preload("res://src/ui/ahoge_parry_motion.gd")
const PROFILE_PATH: String = "res://assets/characters/prototype/charactor_01/ahoge_mesh_profile.tres"
var profile: ProfileScript
var current_vertices: PackedVector2Array = PackedVector2Array()
var straighten: float = 0.0
var parry_sweep: float = 0.0
var configured: bool = false
var _array_mesh: ArrayMesh
var _custom_pose: bool = false


func configure(source: Texture2D) -> bool:
	configured = false
	visible = false
	mesh = null
	_custom_pose = false
	parry_sweep = 0.0
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
	_set_draw_bounds(current_vertices)
	mesh = _array_mesh
	straighten = 0.0
	configured = true
	visible = true
	return true


func set_straighten(value: float) -> void:
	if not configured:
		return
	var bounded: float = clampf(value, 0.0, 1.0)
	if is_equal_approx(bounded, straighten) and not _custom_pose:
		return
	straighten = bounded
	_custom_pose = false
	parry_sweep = 0.0
	_write_vertices(profile.sample(straighten))


func set_parry_pose(straighten_value: float, sweep: float) -> void:
	if not configured or not is_finite(straighten_value) or not is_finite(sweep):
		return
	straighten = clampf(straighten_value, 0.0, 1.0)
	parry_sweep = clampf(sweep, ParryMotionScript.SWEEP_ANGLE, ParryMotionScript.PREPARE_ANGLE)
	var points: PackedVector2Array = ParryMotionScript.deform(profile, profile.sample(straighten), parry_sweep)
	if points.size() != profile.rest_vertices.size():
		return
	_custom_pose = true
	_write_vertices(points)


func set_action_pose(points: PackedVector2Array, straight_value: float, sweep_value: float) -> bool:
	if not configured or points.size() != profile.rest_vertices.size():
		return false
	if not is_finite(straight_value) or not is_finite(sweep_value):
		return false
	for point in points:
		if not point.is_finite():
			return false
	straighten = clampf(straight_value, 0.0, 1.0)
	parry_sweep = sweep_value
	_custom_pose = true
	_write_vertices(points)
	return true


func _write_vertices(points: PackedVector2Array) -> void:
	current_vertices = points
	# index、UV、mesh RIDは変更しない。XYZ領域のみ更新する。
	_array_mesh.surface_update_vertex_region(0, 0, _vertices_3d(current_vertices).to_byte_array())
	_set_draw_bounds(points)


func _set_draw_bounds(points: PackedVector2Array) -> void:
	# 全動作の末端変位を描画境界へ含める。
	var bounds: Rect2 = profile.draw_bounds
	for point in points:
		bounds = bounds.expand(point)
	bounds = bounds.grow(4.0)
	_array_mesh.custom_aabb = AABB(Vector3(bounds.position.x, bounds.position.y, -1.0), Vector3(bounds.size.x, bounds.size.y, 2.0))


func _vertices_3d(points: PackedVector2Array) -> PackedVector3Array:
	var result: PackedVector3Array = PackedVector3Array()
	result.resize(points.size())
	for i in range(points.size()):
		result[i] = Vector3(points[i].x, points[i].y, 0.0)
	return result
