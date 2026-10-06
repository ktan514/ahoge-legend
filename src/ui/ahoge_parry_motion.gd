extends RefCounted

# ムチ状の毛束末端だけを返す。根元側の固定範囲は広げない。
const FIXED_FRACTION: float = 0.62
const FULL_FRACTION: float = 0.80
const ENTRY_SECONDS: float = 0.055
const EXIT_SECONDS: float = 0.08
const PREPARE_ANGLE: float = 0.24
const SWEEP_ANGLE: float = -0.72
const RECOIL_ANGLE: float = 0.12
const HEAD_MOVE_PX: float = 3.0


static func sweep_at(elapsed: float, duration: float) -> float:
	var u: float = clampf(elapsed / maxf(duration, 0.001), 0.0, 1.0)
	if u < 0.12:
		return lerpf(0.0, PREPARE_ANGLE, smoothstep(0.0, 0.12, u))
	if u < 0.52:
		return lerpf(PREPARE_ANGLE, SWEEP_ANGLE, smoothstep(0.12, 0.52, u))
	if u < 0.76:
		return lerpf(SWEEP_ANGLE, RECOIL_ANGLE, smoothstep(0.52, 0.76, u))
	return lerpf(RECOIL_ANGLE, 0.0, smoothstep(0.76, 1.0, u))


static func centers_of(vertices: PackedVector2Array, width_points: int) -> PackedVector2Array:
	var result: PackedVector2Array = PackedVector2Array()
	if width_points < 2 or vertices.size() < width_points + 2:
		return result
	var count: int = int((vertices.size() - 2) / width_points)
	result.append(vertices[0])
	for row in range(count):
		var first: int = 1 + row * width_points
		result.append((vertices[first] + vertices[first + width_points - 1]) * 0.5)
	result.append(vertices[-1])
	return result


static func arc_fractions(centers: PackedVector2Array) -> PackedFloat32Array:
	var result: PackedFloat32Array = PackedFloat32Array()
	result.resize(centers.size())
	var length: float = 0.0
	for i in range(1, centers.size()):
		length += centers[i].distance_to(centers[i - 1])
		result[i] = length
	if length > 0.001:
		for i in range(result.size()):
			result[i] /= length
	return result


static func deform(profile, vertices: PackedVector2Array, sweep: float) -> PackedVector2Array:
	if absf(sweep) < 0.000001:
		return vertices.duplicate()
	var width_points: int = int(profile.WIDTH_POINTS)
	var centers: PackedVector2Array = centers_of(vertices, width_points)
	var rest_centers: PackedVector2Array = centers_of(profile.rest_vertices, width_points)
	if centers.size() < 3 or centers.size() != rest_centers.size():
		return PackedVector2Array()
	var fractions: PackedFloat32Array = arc_fractions(rest_centers)
	var bounded: float = clampf(sweep, SWEEP_ANGLE, PREPARE_ANGLE)
	var posed: PackedVector2Array = PackedVector2Array([centers[0]])
	for i in range(1, centers.size()):
		var weight: float = smoothstep(FIXED_FRACTION, FULL_FRACTION, fractions[i])
		var edge: Vector2 = centers[i] - centers[i - 1]
		posed.append(posed[-1] + edge.rotated(bounded * weight))
	var result: PackedVector2Array = vertices.duplicate()
	var count: int = centers.size() - 2
	for row in range(count):
		var center_index: int = row + 1
		if fractions[center_index] <= FIXED_FRACTION:
			continue
		var posed_tangent: Vector2
		var source_tangent: Vector2
		if center_index == centers.size() - 2:
			# 最終断面は平均接線ではなくtipへ向かう最終edgeを基準にする。
			# 強いsweep時でもtipを含む最後の三角形が反転しないようにする。
			posed_tangent = posed[-1] - posed[-2]
			source_tangent = centers[-1] - centers[-2]
		else:
			posed_tangent = _tangent(posed, center_index)
			source_tangent = _tangent(centers, center_index)
		var turn: float = wrapf(posed_tangent.angle() - source_tangent.angle(), -PI, PI)
		for column in range(width_points):
			var index: int = 1 + row * width_points + column
			result[index] = posed[center_index] + (vertices[index] - centers[center_index]).rotated(turn)
	result[-1] = posed[-1]
	return result


static func _tangent(points: PackedVector2Array, index: int) -> Vector2:
	return (points[mini(index + 1, points.size() - 1)] - points[maxi(index - 1, 0)]).normalized()
