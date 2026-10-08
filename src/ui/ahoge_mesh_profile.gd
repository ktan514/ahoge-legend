extends Resource

# 素材ごとに制作した断面を読み、固定UVと9形状を一度だけ作る。
# 直線素材では素材座標(bind)とゲーム内待機姿勢(idle)を分離する。
# 画像の横走査や実行中の輪郭推測は行わない。
@export var source_texture_path: String = ""
@export var source_size: Vector2i = Vector2i(1254, 1254)
@export var source_rgba_sha256: String = ""
@export var source_file_sha256: String = ""
@export var root_anchor_px: Vector2 = Vector2.ZERO
@export var tip_px: Vector2 = Vector2.ZERO
@export var section_left_px: PackedVector2Array = PackedVector2Array()
@export var section_right_px: PackedVector2Array = PackedVector2Array()
@export var straight_direction: float = -0.85
@export var idle_pose_vertices: PackedVector2Array = PackedVector2Array()
@export var idle_centerline_scale: Vector2 = Vector2.ONE
@export var idle_curve_enabled: bool = false
@export var idle_curve_control_1: Vector2 = Vector2.ZERO
@export var idle_curve_control_2: Vector2 = Vector2.ZERO
@export var idle_curve_end: Vector2 = Vector2.ZERO
@export_range(0.05, 2.0, 0.01) var idle_width_scale: float = 1.0
@export_range(0.5, 4.0, 0.01) var attack_length_scale: float = 1.0
var bind_vertices: PackedVector2Array = PackedVector2Array()

const WIDTH_POINTS: int = 5
const KEY_COUNT: int = 9
var rest_vertices: PackedVector2Array = PackedVector2Array()
var uvs: PackedVector2Array = PackedVector2Array()
var indices: PackedInt32Array = PackedInt32Array()
var shape_keys: Array[PackedVector2Array] = []
var boundary_indices: PackedInt32Array = PackedInt32Array()
var draw_bounds: Rect2 = Rect2()
var _prepared: bool = false


func prepare() -> bool:
	if _prepared:
		return true
	uvs.clear()
	indices.clear()
	shape_keys.clear()
	boundary_indices.clear()
	var count: int = section_left_px.size()
	if count < 8 or count != section_right_px.size():
		return false
	if source_size.x <= 0 or source_size.y <= 0:
		return false
	var centers: PackedVector2Array = PackedVector2Array([root_anchor_px])
	rest_vertices = PackedVector2Array([Vector2.ZERO])
	for row in range(count):
		centers.append((section_left_px[row] + section_right_px[row]) * 0.5)
		for column in range(WIDTH_POINTS):
			var across: float = float(column) / float(WIDTH_POINTS - 1)
			rest_vertices.append(section_left_px[row].lerp(section_right_px[row], across) - root_anchor_px)
	centers.append(tip_px)
	rest_vertices.append(tip_px - root_anchor_px)
	bind_vertices = rest_vertices.duplicate()
	for point in bind_vertices:
		uvs.append((point + root_anchor_px) / Vector2(source_size))
	if not idle_pose_vertices.is_empty():
		if idle_pose_vertices.size() != bind_vertices.size() or not idle_pose_vertices[0].is_equal_approx(Vector2.ZERO):
			return false
		if (
			not idle_centerline_scale.is_finite()
			or idle_centerline_scale.x <= 0.0
			or idle_centerline_scale.y <= 0.0
			or not is_finite(idle_width_scale)
			or idle_width_scale <= 0.0
			or not is_finite(attack_length_scale)
			or attack_length_scale <= 0.0
		):
			return false
		for point in idle_pose_vertices:
			if not point.is_finite():
				return false
		rest_vertices = idle_pose_vertices.duplicate()
		centers = PackedVector2Array([root_anchor_px])
		for row in range(count):
			var first: int = 1 + row * WIDTH_POINTS
			centers.append((rest_vertices[first] + rest_vertices[first + WIDTH_POINTS - 1]) * 0.5 + root_anchor_px)
		centers.append(rest_vertices[-1] + root_anchor_px)

		if idle_curve_enabled:
			if (
				not idle_curve_control_1.is_finite()
				or not idle_curve_control_2.is_finite()
				or not idle_curve_end.is_finite()
			):
				return false
			var source_centers: PackedVector2Array = centers.duplicate()
			var arc: PackedFloat32Array = PackedFloat32Array([0.0])
			var total_arc: float = 0.0
			for i in range(1, source_centers.size()):
				total_arc += source_centers[i].distance_to(source_centers[i - 1])
				arc.append(total_arc)
			if total_arc <= 0.001:
				return false

			var posed_centers: PackedVector2Array = PackedVector2Array()
			for i in range(source_centers.size()):
				var t: float = arc[i] / total_arc
				var local_center: Vector2 = _cubic_bezier(
					Vector2.ZERO,
					idle_curve_control_1,
					idle_curve_control_2,
					idle_curve_end,
					t
				)
				posed_centers.append(root_anchor_px + local_center)

			var curved_vertices: PackedVector2Array = rest_vertices.duplicate()
			curved_vertices[0] = Vector2.ZERO
			for row in range(count):
				var center_index: int = row + 1
				var source_tangent: Vector2 = _tangent(source_centers, center_index)
				var posed_tangent: Vector2 = _tangent(posed_centers, center_index)
				if source_tangent.length() <= 0.000001 or posed_tangent.length() <= 0.000001:
					return false
				var turn: float = wrapf(
					posed_tangent.angle() - source_tangent.angle(),
					-PI,
					PI
				)
				for column in range(WIDTH_POINTS):
					var vertex_index: int = 1 + row * WIDTH_POINTS + column
					var relative: Vector2 = (
						rest_vertices[vertex_index]
						+ root_anchor_px
						- source_centers[center_index]
					) * idle_width_scale
					curved_vertices[vertex_index] = (
						posed_centers[center_index]
						- root_anchor_px
						+ relative.rotated(turn)
					)
			curved_vertices[-1] = posed_centers[-1] - root_anchor_px
			rest_vertices = curved_vertices
			centers = posed_centers
		elif not idle_centerline_scale.is_equal_approx(Vector2.ONE):
			var source_centers: PackedVector2Array = centers.duplicate()
			var posed_centers: PackedVector2Array = PackedVector2Array()
			for center in source_centers:
				var local: Vector2 = center - root_anchor_px
				posed_centers.append(
					root_anchor_px + Vector2(
						local.x * idle_centerline_scale.x,
						local.y * idle_centerline_scale.y
					)
				)
			var scaled_vertices: PackedVector2Array = rest_vertices.duplicate()
			scaled_vertices[0] = Vector2.ZERO
			for row in range(count):
				var center_index: int = row + 1
				var source_tangent: Vector2 = _tangent(source_centers, center_index)
				var posed_tangent: Vector2 = _tangent(posed_centers, center_index)
				if source_tangent.length() <= 0.000001 or posed_tangent.length() <= 0.000001:
					return false
				var turn: float = wrapf(
					posed_tangent.angle() - source_tangent.angle(),
					-PI,
					PI
				)
				for column in range(WIDTH_POINTS):
					var vertex_index: int = 1 + row * WIDTH_POINTS + column
					var relative: Vector2 = (
						rest_vertices[vertex_index]
						+ root_anchor_px
						- source_centers[center_index]
					)
					scaled_vertices[vertex_index] = (
						posed_centers[center_index]
						- root_anchor_px
						+ relative.rotated(turn)
					)
			scaled_vertices[-1] = posed_centers[-1] - root_anchor_px
			rest_vertices = scaled_vertices
			centers = posed_centers
	for column in range(WIDTH_POINTS - 1):
		_append_triangle(0, 1 + column, 2 + column)
	for row in range(count - 1):
		for column in range(WIDTH_POINTS - 1):
			var a: int = 1 + row * WIDTH_POINTS + column
			var b: int = a + WIDTH_POINTS
			_append_triangle(a, b, a + 1)
			_append_triangle(a + 1, b, b + 1)
	var tip_index: int = rest_vertices.size() - 1
	for column in range(WIDTH_POINTS - 1):
		_append_triangle(tip_index, tip_index - WIDTH_POINTS + column + 1, tip_index - WIDTH_POINTS + column)
	boundary_indices.append(0)
	for row in range(count):
		boundary_indices.append(1 + row * WIDTH_POINTS)
	boundary_indices.append(tip_index)
	for row in range(count - 1, -1, -1):
		boundary_indices.append((row + 1) * WIDTH_POINTS)

	var lengths: PackedFloat32Array = PackedFloat32Array()
	var angles: PackedFloat32Array = PackedFloat32Array()
	var distances: PackedFloat32Array = PackedFloat32Array([0.0])
	var total: float = 0.0
	for row in range(centers.size() - 1):
		var edge: Vector2 = centers[row + 1] - centers[row]
		if edge.length() < 0.001:
			return false
		var angle: float = edge.angle()
		if not angles.is_empty():
			angle = angles[-1] + wrapf(angle - angles[-1], -PI, PI)
		angles.append(angle)
		lengths.append(edge.length())
		total += edge.length()
		distances.append(total)

	shape_keys.append(rest_vertices.duplicate())
	for key_index in range(1, KEY_COUNT):
		var amount: float = float(key_index) / float(KEY_COUNT - 1)
		var posed_centers: PackedVector2Array = PackedVector2Array([root_anchor_px])
		for row in range(lengths.size()):
			# 根元の丸い接続部は固定し、流れに沿って折り返しをほどく。
			var weight: float = smoothstep(0.10, 0.32, distances[row + 1] / total)
			var target: float = lerpf(angles[row], straight_direction, weight)
			var angle: float = lerpf(angles[row], target, amount)
			posed_centers.append(posed_centers[-1] + Vector2.from_angle(angle) * lengths[row])
		var vertices: PackedVector2Array = PackedVector2Array([Vector2.ZERO])
		for row in range(count):
			var center_index: int = row + 1
			var turn: float = _tangent(posed_centers, center_index).angle() - _tangent(centers, center_index).angle()
			for column in range(WIDTH_POINTS):
				var vertex_index: int = 1 + row * WIDTH_POINTS + column
				var relative: Vector2 = rest_vertices[vertex_index] + root_anchor_px - centers[center_index]
				vertices.append(posed_centers[center_index] - root_anchor_px + relative.rotated(turn))
		vertices.append(posed_centers[-1] - root_anchor_px)
		shape_keys.append(vertices)
	var first: bool = true
	for vertices in shape_keys:
		for point in vertices:
			if not point.is_finite():
				return false
			if first:
				draw_bounds = Rect2(point, Vector2.ZERO)
				first = false
			else:
				draw_bounds = draw_bounds.expand(point)
	draw_bounds = draw_bounds.grow(4.0)
	_prepared = true
	return true


func sample(amount: float) -> PackedVector2Array:
	if not _prepared and not prepare():
		return PackedVector2Array()
	var position: float = clampf(amount, 0.0, 1.0) * float(KEY_COUNT - 1)
	var low: int = mini(int(floor(position)), KEY_COUNT - 2)
	var weight: float = position - float(low)
	var result: PackedVector2Array = PackedVector2Array()
	result.resize(rest_vertices.size())
	for i in range(result.size()):
		result[i] = shape_keys[low][i].lerp(shape_keys[low + 1][i], weight)
	return result


func matches_texture(texture: Texture2D) -> bool:
	if texture == null or texture.resource_path != source_texture_path:
		return false
	if Vector2i(texture.get_size()) != source_size:
		return false
	# 開発時は元PNGそのものを識別する。export時は復号画像のdigestを使用する。
	if FileAccess.file_exists(source_texture_path):
		return FileAccess.get_sha256(source_texture_path) == source_file_sha256
	var image: Image = texture.get_image()
	if image == null or image.is_empty():
		return false
	if image.is_compressed() and image.decompress() != OK:
		return false
	image.convert(Image.FORMAT_RGBA8)
	var context: HashingContext = HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(image.get_data())
	return context.finish().hex_encode() == source_rgba_sha256


func _cubic_bezier(
	p0: Vector2,
	p1: Vector2,
	p2: Vector2,
	p3: Vector2,
	t: float
) -> Vector2:
	var u: float = 1.0 - clampf(t, 0.0, 1.0)
	var v: float = 1.0 - u
	return (
		p0 * u * u * u
		+ p1 * 3.0 * u * u * v
		+ p2 * 3.0 * u * v * v
		+ p3 * v * v * v
	)


func _append_triangle(a: int, b: int, c: int) -> void:
	if (rest_vertices[b] - rest_vertices[a]).cross(rest_vertices[c] - rest_vertices[a]) < 0.0:
		indices.append_array(PackedInt32Array([a, c, b]))
	else:
		indices.append_array(PackedInt32Array([a, b, c]))


func _tangent(points: PackedVector2Array, index: int) -> Vector2:
	return (points[mini(index + 1, points.size() - 1)] - points[maxi(index - 1, 0)]).normalized()
