extends Resource

# 素材ごとの制作済み断面から、初期化時だけ固定メッシュと5形状キーを焼き出す。
@export var schema_version: int = 1
@export var source_texture_path: String = ""
@export var source_texture_size: Vector2i = Vector2i.ZERO
@export var source_texture_digest: String = ""
@export var source_pixel_digest: String = ""
@export var root_anchor_px: Vector2 = Vector2.ZERO
@export var head_attachment_reference: Vector2 = Vector2(0.525, 0.085)
@export var rest_centers_px: PackedVector2Array = PackedVector2Array()
@export var section_left_offsets_px: PackedFloat32Array = PackedFloat32Array()
@export var section_right_offsets_px: PackedFloat32Array = PackedFloat32Array()
@export var section_curve_positions: PackedFloat32Array = PackedFloat32Array()
@export var shape_key_values: PackedFloat32Array = PackedFloat32Array([0.0, 0.25, 0.5, 0.75, 1.0])
@export var unfold_target_angle_degrees: float = -70.0
@export var unfold_fixed_ratio: float = 0.075
@export var unfold_blend_ratio: float = 0.24
@export var root_fixed_ratio: float = 0.055

var rest_vertices_px := PackedVector2Array()
var uvs := PackedVector2Array()
var triangle_indices := PackedInt32Array()
var vertex_curve_positions := PackedFloat32Array()
var root_vertex_indices := PackedInt32Array()
var tip_vertex_index: int = -1
var shape_key_vertices: Array[PackedVector2Array] = []
var centerline_keys: Array[PackedVector2Array] = []
var local_draw_bounds := Rect2()
var minimum_area_ratio: float = 1.0
var _sections: Array[PackedInt32Array] = []
var _prepared: bool = false
var _failure: String = ""


func prepare() -> String:
	if _prepared:
		return _failure
	_prepared = true
	_failure = _check_authored_data()
	if not _failure.is_empty():
		return _failure
	_build_rest_mesh()
	_bake_shape_keys()
	_failure = _validate_interpolation()
	return _failure


func validate_source(texture_value: Texture2D) -> String:
	if texture_value == null or Vector2i(texture_value.get_size()) != source_texture_size:
		return "素材の寸法が固定メッシュと一致しません"
	# Editorでは原本、exportでは透明境界のRGBを除いた画素で同じ素材を識別する。
	if texture_value.resource_path == source_texture_path and FileAccess.file_exists(source_texture_path):
		if FileAccess.get_sha256(source_texture_path) != source_texture_digest:
			return "素材原本のSHA-256が一致しません"
		return ""
	var image: Image = texture_value.get_image()
	if image == null or image.is_empty():
		return "素材の画素を検証できません"
	if image.is_compressed() and image.decompress() != OK:
		return "素材の圧縮画素を展開できません"
	image.convert(Image.FORMAT_RGBA8)
	if image.has_mipmaps():
		image.clear_mipmaps()
	var hashing := HashingContext.new()
	if hashing.start(HashingContext.HASH_SHA256) != OK:
		return "素材の識別処理を開始できません"
	var bytes: PackedByteArray = image.get_data()
	for offset in range(0, bytes.size(), 4):
		if bytes[offset + 3] < 20:
			bytes[offset] = 0
			bytes[offset + 1] = 0
			bytes[offset + 2] = 0
	hashing.update(bytes)
	if hashing.finish().hex_encode() != source_pixel_digest:
		return "素材の画素が制作済みメッシュと一致しません"
	return ""


func vertices_at(amount: float) -> PackedVector2Array:
	if not prepare().is_empty():
		return PackedVector2Array()
	var value := clampf(amount, 0.0, 1.0)
	var low := 0
	while low + 1 < shape_key_values.size() - 1 and value > shape_key_values[low + 1]:
		low += 1
	var weight := (value - shape_key_values[low]) / (shape_key_values[low + 1] - shape_key_values[low])
	var result := PackedVector2Array()
	result.resize(rest_vertices_px.size())
	for index in range(result.size()):
		result[index] = shape_key_vertices[low][index].lerp(shape_key_vertices[low + 1][index], weight)
	return result


func export_verification_data() -> Dictionary:
	return {
		"source_texture_path": source_texture_path,
		"source_texture_size": [source_texture_size.x, source_texture_size.y],
		"source_texture_digest": source_texture_digest,
		"source_pixel_digest": source_pixel_digest,
		"root_anchor_px": [root_anchor_px.x, root_anchor_px.y],
		"rest_vertices_px": _pairs(rest_vertices_px),
		"uvs": _pairs(uvs),
		"triangle_indices": Array(triangle_indices),
		"shape_key_values": Array(shape_key_values),
		"shape_key_vertices": shape_key_vertices.map(func(points: PackedVector2Array) -> Array: return _pairs(points)),
		"centerline_keys": centerline_keys.map(func(points: PackedVector2Array) -> Array: return _pairs(points)),
		"vertex_curve_positions": Array(vertex_curve_positions),
		"root_vertex_indices": Array(root_vertex_indices),
		"tip_vertex_index": tip_vertex_index,
		"minimum_area_ratio": minimum_area_ratio,
	}


func _check_authored_data() -> String:
	var count := rest_centers_px.size()
	if schema_version != 1 or count < 8:
		return "メッシュ制作データの版または断面数が不正です"
	if source_texture_size.x <= 0 or source_texture_size.y <= 0 or source_pixel_digest.length() != 64:
		return "素材識別情報が不正です"
	if section_left_offsets_px.size() != count or section_right_offsets_px.size() != count or section_curve_positions.size() != count:
		return "断面データの個数が一致しません"
	if shape_key_values.size() < 2 or shape_key_values[0] != 0.0 or shape_key_values[-1] != 1.0:
		return "形状キーの端点が不正です"
	for index in range(1, shape_key_values.size()):
		if not is_finite(shape_key_values[index]) or shape_key_values[index] <= shape_key_values[index - 1]:
			return "形状キーが単調増加ではありません"
	if not (0.0 <= root_fixed_ratio and root_fixed_ratio < unfold_fixed_ratio and unfold_fixed_ratio < unfold_blend_ratio and unfold_blend_ratio < 1.0):
		return "根元固定範囲と直線化範囲が不正です"
	if not root_anchor_px.is_finite() or not head_attachment_reference.is_finite() or not is_finite(unfold_target_angle_degrees):
		return "接点または直線化方向が有限値ではありません"
	if section_curve_positions[0] != 0.0 or section_curve_positions[-1] != 1.0:
		return "毛束上の距離パラメータの端点が不正です"
	for index in range(count):
		if not rest_centers_px[index].is_finite() or not is_finite(section_left_offsets_px[index]) or not is_finite(section_right_offsets_px[index]) or not is_finite(section_curve_positions[index]):
			return "断面に有限でない値があります"
		if index > 0 and (rest_centers_px[index].distance_to(rest_centers_px[index - 1]) < 0.001 or section_curve_positions[index] <= section_curve_positions[index - 1]):
			return "毛束上の順序または区間長が不正です"
		if index > 0 and index < count - 1 and not (section_left_offsets_px[index] < 0.0 and section_right_offsets_px[index] > 0.0):
			return "断面が中心線の両側を囲んでいません"
	return ""


func _build_rest_mesh() -> void:
	var count := rest_centers_px.size()
	for index in range(count):
		var center := rest_centers_px[index]
		var normal := Vector2.from_angle(_tangent_angle(rest_centers_px, index) + PI * 0.5)
		var offsets := PackedFloat32Array([0.0]) if index == 0 or index == count - 1 else PackedFloat32Array([section_left_offsets_px[index], 0.0, section_right_offsets_px[index]])
		var ids := PackedInt32Array()
		for offset in offsets:
			var point := center + normal * offset
			var vertex_id := rest_vertices_px.size()
			ids.append(vertex_id)
			rest_vertices_px.append(point - root_anchor_px)
			uvs.append(point / Vector2(source_texture_size))
			vertex_curve_positions.append(section_curve_positions[index])
			if section_curve_positions[index] < root_fixed_ratio:
				root_vertex_indices.append(vertex_id)
		_sections.append(ids)
	for index in range(count - 1):
		var first := _sections[index]
		var second := _sections[index + 1]
		for column in range(2):
			if first.size() == 1:
				triangle_indices.append_array(PackedInt32Array([first[0], second[column + 1], second[column]]))
			elif second.size() == 1:
				triangle_indices.append_array(PackedInt32Array([first[column], first[column + 1], second[0]]))
			else:
				triangle_indices.append_array(PackedInt32Array([first[column], first[column + 1], second[column], first[column + 1], second[column + 1], second[column]]))
	tip_vertex_index = rest_vertices_px.size() - 1


func _bake_shape_keys() -> void:
	var lengths := PackedFloat32Array()
	var angles := PackedFloat32Array()
	for index in range(rest_centers_px.size() - 1):
		var difference := rest_centers_px[index + 1] - rest_centers_px[index]
		var angle := difference.angle()
		if not angles.is_empty():
			angle = angles[-1] + wrapf(angle - angles[-1], -PI, PI)
		lengths.append(difference.length())
		angles.append(angle)
	for amount in shape_key_values:
		var centers := PackedVector2Array([rest_centers_px[0]])
		for index in range(lengths.size()):
			var weight := smoothstep(unfold_fixed_ratio, unfold_blend_ratio, section_curve_positions[index])
			var target := lerpf(angles[index], deg_to_rad(unfold_target_angle_degrees), weight)
			var angle := lerpf(angles[index], target, amount)
			centers.append(centers[-1] + Vector2.from_angle(angle) * lengths[index])
		var vertices := PackedVector2Array()
		vertices.resize(rest_vertices_px.size())
		for index in range(centers.size()):
			var rotation_delta := _tangent_angle(centers, index) - _tangent_angle(rest_centers_px, index)
			for vertex_id in _sections[index]:
				var original_offset := rest_vertices_px[vertex_id] + root_anchor_px - rest_centers_px[index]
				vertices[vertex_id] = centers[index] + original_offset.rotated(rotation_delta) - root_anchor_px
		if amount == 0.0:
			vertices = rest_vertices_px.duplicate()
		shape_key_vertices.append(vertices)
		var relative_centers := PackedVector2Array()
		for center in centers:
			relative_centers.append(center - root_anchor_px)
		centerline_keys.append(relative_centers)
	local_draw_bounds = Rect2(rest_vertices_px[0], Vector2.ZERO)
	for key in shape_key_vertices:
		for point in key:
			local_draw_bounds = local_draw_bounds.expand(point)
	local_draw_bounds = local_draw_bounds.grow(2.0)


func _validate_interpolation() -> String:
	for key in shape_key_vertices:
		for point in key:
			if not point.is_finite():
				return "形状キーに有限でない頂点があります"
		for vertex_id in root_vertex_indices:
			if key[vertex_id].distance_to(rest_vertices_px[vertex_id]) > 0.002:
				return "形状キーで根元が移動しています"
	minimum_area_ratio = INF
	for offset in range(0, triangle_indices.size(), 3):
		var a := triangle_indices[offset]
		var b := triangle_indices[offset + 1]
		var c := triangle_indices[offset + 2]
		var reference := (rest_vertices_px[b] - rest_vertices_px[a]).cross(rest_vertices_px[c] - rest_vertices_px[a])
		if absf(reference) < 0.001:
			return "待機形状に退化した三角形があります"
		for key_index in range(shape_key_vertices.size() - 1):
			var first := shape_key_vertices[key_index]
			var second := shape_key_vertices[key_index + 1]
			var e := first[b] - first[a]
			var f := first[c] - first[a]
			var de := (second[b] - second[a]) - e
			var df := (second[c] - second[a]) - f
			var direction := signf(reference)
			var constant := e.cross(f) * direction
			var linear := (e.cross(df) + de.cross(f)) * direction
			var quadratic := de.cross(df) * direction
			var minimum := minf(constant, constant + linear + quadratic)
			if absf(quadratic) > 0.0000001:
				var extremum := -linear / (2.0 * quadratic)
				if extremum > 0.0 and extremum < 1.0:
					minimum = minf(minimum, constant + linear * extremum + quadratic * extremum * extremum)
			if minimum <= 0.001:
				return "キー補間の途中で三角形が退化または反転します"
			minimum_area_ratio = minf(minimum_area_ratio, minimum / absf(reference))
	return ""


func _tangent_angle(centers: PackedVector2Array, index: int) -> float:
	return (centers[mini(index + 1, centers.size() - 1)] - centers[maxi(index - 1, 0)]).angle()


func _pairs(points: PackedVector2Array) -> Array:
	var result: Array = []
	for point in points:
		result.append([point.x, point.y])
	return result
