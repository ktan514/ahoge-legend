extends RefCounted

const StateScript := preload("res://src/domain/combatant_state.gd")
const ParryScript := preload("res://src/ui/ahoge_parry_motion.gd")
const BACK_BEND: float = -1.15
const TIP_DROP: float = 1.8
const RECOVER_SECONDS: float = 0.24
const FOLLOW_BEND: float = 0.12

var configured: bool = false
var state: int = -1
var elapsed: float = 0.0
var duration: float = 0.20
var contact_ratio: float = 0.70
var straighten: float = 0.0
var sweep: float = 0.0
var hang: float = 0.0
var blocked: bool = false
var vertices: PackedVector2Array = PackedVector2Array()
var current_angles: PackedFloat32Array = PackedFloat32Array()
var fractions: PackedFloat32Array = PackedFloat32Array()
var rest_angles: PackedFloat32Array = PackedFloat32Array()
var hang_angles: PackedFloat32Array = PackedFloat32Array()
var straight_angles: PackedFloat32Array = PackedFloat32Array()
var _lengths: PackedFloat32Array = PackedFloat32Array()
var _centers: PackedVector2Array = PackedVector2Array()
var _profile
var _from_angles: PackedFloat32Array = PackedFloat32Array()
var _from_straighten: float = 0.0
var _from_sweep: float = 0.0
var _from_hang: float = 0.0
var _charge: float = 0.0
var _max_charge: float = 0.62


func configure(profile) -> bool:
	configured = false
	if profile == null or not profile.prepare():
		return false
	_profile = profile
	_centers = ParryScript.centers_of(profile.rest_vertices, profile.WIDTH_POINTS)
	if _centers.size() < 3:
		return false
	var arc: PackedFloat32Array = ParryScript.arc_fractions(_centers)
	_lengths.clear()
	fractions.clear()
	rest_angles.clear()
	hang_angles.clear()
	straight_angles.clear()
	for i in range(_centers.size() - 1):
		var edge: Vector2 = _centers[i + 1] - _centers[i]
		var angle: float = edge.angle()
		if not rest_angles.is_empty():
			angle = rest_angles[-1] + wrapf(angle - rest_angles[-1], -PI, PI)
		var s: float = arc[i + 1]
		_lengths.append(edge.length())
		fractions.append(s)
		rest_angles.append(angle)
		hang_angles.append(angle + BACK_BEND * smoothstep(0.07, 0.30, s) + TIP_DROP * smoothstep(0.40, 0.97, s))
		straight_angles.append(lerpf(angle, float(profile.straight_direction), smoothstep(0.10, 0.32, s)))
	configured = true
	state = -1
	blocked = false
	_reset_pose()
	_from_angles = current_angles.duplicate()
	return true


func advance(next_state: int, delta: float, phase_duration: float, max_charge: float, charge: float, available: bool) -> void:
	if not configured or delta <= 0.0 or not is_finite(delta):
		return
	var changed: bool = next_state != state
	if changed:
		_from_angles = current_angles.duplicate()
		_from_straighten = straighten
		_from_sweep = sweep
		_from_hang = hang
		state = next_state
		elapsed = 0.0
		if available and state != StateScript.ActionState.ROUND_LOCKED:
			blocked = false
	duration = maxf(phase_duration, 0.001)
	_max_charge = maxf(max_charge, 0.001)
	_charge = clampf(charge, 0.0, 1.0)
	if not available or state == StateScript.ActionState.ROUND_LOCKED:
		blocked = true
		_reset_pose()
		return
	if blocked:
		_reset_pose()
		return
	# 防御の最初の表示は現在形状を保持する。サーバーの防御開始は遅らせない。
	if not (changed and state == StateScript.ActionState.PARRY):
		elapsed += delta
	_compute_pose()


func _compute_pose() -> void:
	straighten = 0.0
	sweep = 0.0
	hang = 0.0
	match state:
		StateScript.ActionState.CHARGING:
			var progress: float = clampf(elapsed / _max_charge, 0.0, 1.0)
			var entry: float = smoothstep(0.0, 0.08, elapsed)
			for i in range(current_angles.size()):
				var local_hang: float = smoothstep(0.04 * fractions[i], 0.50 + 0.50 * fractions[i], progress)
				var desired: float = lerpf(rest_angles[i], hang_angles[i], local_hang)
				current_angles[i] = lerpf(_from_angles[i], desired, entry)
			hang = smoothstep(0.04, 1.0, progress)
			sweep = _from_sweep * (1.0 - entry)
		StateScript.ActionState.WINDUP:
			var windup: float = smoothstep(0.0, duration, elapsed)
			var target_hang: float = maxf(_from_hang, 0.22 + 0.78 * _charge)
			for i in range(current_angles.size()):
				current_angles[i] = lerpf(_from_angles[i], lerpf(rest_angles[i], hang_angles[i], target_hang), windup)
			hang = lerpf(_from_hang, target_hang, windup)
			sweep = _from_sweep * (1.0 - windup)
		StateScript.ActionState.STRIKE:
			var q: float = elapsed / maxf(duration * contact_ratio, 0.001)
			var after: float = clampf((elapsed / duration - contact_ratio) / maxf(1.0 - contact_ratio, 0.001), 0.0, 1.0)
			for i in range(current_angles.size()):
				var s: float = fractions[i]
				var release: float = release_at(q, s)
				current_angles[i] = lerpf(_from_angles[i], straight_angles[i], release)
				current_angles[i] += FOLLOW_BEND * sin(after * PI) * smoothstep(0.40, 1.0, s)
			straighten = release_at(q, 1.0)
			hang = _from_hang * (1.0 - straighten)
		StateScript.ActionState.PARRY:
			var join: float = smoothstep(0.0, ParryScript.ENTRY_SECONDS, elapsed)
			for i in range(current_angles.size()):
				current_angles[i] = lerpf(_from_angles[i], rest_angles[i], join)
			straighten = _from_straighten * (1.0 - join)
			hang = _from_hang * (1.0 - join)
			sweep = lerpf(_from_sweep, ParryScript.sweep_at(elapsed, duration), join)
		_:
			for i in range(current_angles.size()):
				var back: float = smoothstep(0.0, 0.18 + 0.06 * fractions[i], elapsed)
				current_angles[i] = lerpf(_from_angles[i], rest_angles[i], back)
			var recover: float = 1.0 - smoothstep(0.0, RECOVER_SECONDS, elapsed)
			straighten = _from_straighten * recover
			hang = _from_hang * recover
			sweep = _from_sweep * (1.0 - smoothstep(0.0, ParryScript.EXIT_SECONDS, elapsed))
	vertices = vertices_from_angles(current_angles)
	if absf(sweep) > 0.000001:
		vertices = ParryScript.deform(_profile, vertices, sweep)


static func release_at(q: float, s: float) -> float:
	# 根元側の区間が先行し、先端は接触直前まで遅れる。
	return smoothstep(0.02 + 0.35 * s, 0.42 + 0.58 * s, q)


func force_contact() -> bool:
	if not configured or blocked or state not in [StateScript.ActionState.STRIKE, StateScript.ActionState.COOLDOWN]:
		return false
	current_angles = straight_angles.duplicate()
	straighten = 1.0
	hang = 0.0
	sweep = 0.0
	vertices = vertices_from_angles(current_angles)
	if state == StateScript.ActionState.STRIKE:
		elapsed = maxf(elapsed, duration * contact_ratio)
	else:
		_from_angles = current_angles.duplicate()
		_from_straighten = 1.0
		_from_hang = 0.0
		_from_sweep = 0.0
		elapsed = 0.0
	return true


func vertices_from_angles(values: PackedFloat32Array) -> PackedVector2Array:
	if not configured or values.size() != _lengths.size():
		return PackedVector2Array()
	var posed: PackedVector2Array = PackedVector2Array([_centers[0]])
	for i in range(values.size()):
		posed.append(posed[-1] + Vector2.from_angle(values[i]) * _lengths[i])
	var result: PackedVector2Array = _profile.rest_vertices.duplicate()
	var width: int = int(_profile.WIDTH_POINTS)
	for row in range(_centers.size() - 2):
		var k: int = row + 1
		var old_tangent: Vector2 = _centers[k + 1] - _centers[k - 1]
		var new_tangent: Vector2 = posed[k + 1] - posed[k - 1]
		var turn: float = new_tangent.angle() - old_tangent.angle()
		for column in range(width):
			var index: int = 1 + row * width + column
			result[index] = posed[k] + (_profile.rest_vertices[index] - _centers[k]).rotated(turn)
	result[0] = Vector2.ZERO
	result[-1] = posed[-1]
	return result


func _reset_pose() -> void:
	current_angles = rest_angles.duplicate()
	vertices = _profile.rest_vertices.duplicate()
	straighten = 0.0
	hang = 0.0
	sweep = 0.0
