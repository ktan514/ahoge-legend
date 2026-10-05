extends RefCounted

const StateScript := preload("res://src/domain/combatant_state.gd")
const ParryScript := preload("res://src/ui/ahoge_parry_motion.gd")
const HANG_UP_ANGLE: float = -1.30
const HANG_TURN: float = 3.0
const TRAVEL_BEND: float = 0.60
const RECOVER_SECONDS: float = 0.24
const FOLLOW_WAVE_BEND: float = 1.10
const FOLLOW_END_BEND: float = 0.78
const FOLLOW_SECONDS: float = 0.16
const SOFT_ROOT_END: float = 0.15
const SOFT_FULL_AT: float = 0.80
const SOFT_COUNTER_RATIO: float = 0.65
const SOFT_IDLE_CURVE: float = 0.16
const SOFT_RESPONSE: float = 8.0

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
# STRIKE終了時までに進んだ振り抜き時間。負値なら継続しない。
var _continued_follow_seconds: float = -1.0
var softness: float = 1.0
var attachment_angle: float = 0.0
var _soft_counter_angle: float = 0.0


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
		# C字へ一律の角度を足すと末端が輪になる。開いた後方アーチを正本にする。
		var hang_angle: float = HANG_UP_ANGLE - HANG_TURN * smoothstep(0.30, 0.90, s)
		hang_angles.append(lerpf(angle, hang_angle, smoothstep(0.08, 0.22, s)))
		straight_angles.append(lerpf(angle, float(profile.straight_direction), smoothstep(0.10, 0.32, s)))
	configured = true
	state = -1
	blocked = false
	_reset_pose()
	_from_angles = current_angles.duplicate()
	return true


func advance(
	next_state: int,
	delta: float,
	phase_duration: float,
	max_charge: float,
	charge: float,
	available: bool,
	attachment_angle_radians: float = 0.0,
	softness_amount: float = 1.0
) -> void:
	if not configured or delta <= 0.0 or not is_finite(delta):
		return
	if not is_finite(attachment_angle_radians) or not is_finite(softness_amount):
		return
	attachment_angle = attachment_angle_radians
	softness = clampf(softness_amount, 0.0, 1.0)
	var counter_target: float = -attachment_angle * SOFT_COUNTER_RATIO * softness
	var response: float = 1.0 - exp(-SOFT_RESPONSE * delta)
	_soft_counter_angle = lerp_angle(_soft_counter_angle, counter_target, clampf(response, 0.0, 1.0))
	var changed: bool = next_state != state
	if changed:
		var carry: float = -1.0
		if state == StateScript.ActionState.STRIKE and next_state == StateScript.ActionState.COOLDOWN and not blocked:
			var contact_seconds: float = duration * contact_ratio
			if elapsed >= contact_seconds:
				carry = elapsed - contact_seconds
		_continued_follow_seconds = carry
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
				var desired: float = hanging_angle(i, progress)
				current_angles[i] = lerpf(_from_angles[i], desired, entry)
			hang = smoothstep(0.04, 1.0, progress)
			sweep = _from_sweep * (1.0 - entry)
		StateScript.ActionState.WINDUP:
			var windup: float = smoothstep(0.0, duration, elapsed)
			var target_hang: float = maxf(_from_hang, 0.22 + 0.78 * _charge)
			for i in range(current_angles.size()):
				current_angles[i] = lerpf(_from_angles[i], hanging_angle(i, target_hang), windup)
			hang = lerpf(_from_hang, target_hang, windup)
			sweep = _from_sweep * (1.0 - windup)
		StateScript.ActionState.STRIKE:
			var q: float = elapsed / maxf(duration * contact_ratio, 0.001)
			var after: float = follow_progress()
			for i in range(current_angles.size()):
				var s: float = fractions[i]
				current_angles[i] = lerpf(_from_angles[i], straight_angles[i], release_at(q, s))
				# 曲げの山を先端へ送り出し、接触後は別の曲げを根元側から返す。
				current_angles[i] += traveling_bend(q, s) + follow_bend(after, s)
			straighten = release_at(q, 1.0)
			hang = _from_hang * (1.0 - straighten)
		StateScript.ActionState.COOLDOWN:
			if _continued_follow_seconds >= 0.0:
				var recovering: float = recovery_seconds()
				for i in range(current_angles.size()):
					var trailing: float = straight_angles[i] + follow_bend(follow_progress(), fractions[i])
					current_angles[i] = lerpf(trailing, rest_angles[i], smoothstep(0.0, 0.18 + 0.06 * fractions[i], recovering))
				straighten = 1.0 - smoothstep(0.0, RECOVER_SECONDS, recovering)
			else:
				_recover_from_entry()
		StateScript.ActionState.PARRY:
			var join: float = smoothstep(0.0, ParryScript.ENTRY_SECONDS, elapsed)
			for i in range(current_angles.size()):
				current_angles[i] = lerpf(_from_angles[i], rest_angles[i], join)
			straighten = _from_straighten * (1.0 - join)
			hang = _from_hang * (1.0 - join)
			sweep = lerpf(_from_sweep, ParryScript.sweep_at(elapsed, duration), join)
		_:
			_recover_from_entry()
	vertices = vertices_from_angles(current_angles)
	if absf(sweep) > 0.000001:
		vertices = ParryScript.deform(_profile, vertices, sweep)


func hanging_angle(index: int, progress: float) -> float:
	var s: float = fractions[index]
	var p: float = clampf(progress, 0.0, 1.0)
	var local_hang: float = smoothstep(0.04 * s, 0.50 + 0.50 * s, p)
	# 前のC字を後ろへ渡す間も曲げを残す。一直線に伸びて画面上端へ出ない。
	var transfer: float = 2.0 * sin(PI * p) * exp(-pow((s - 0.35) / 0.28, 2.0)) * smoothstep(0.08, 0.22, s)
	return lerpf(rest_angles[index], hang_angles[index], local_hang) + transfer


func _recover_from_entry() -> void:
	for i in range(current_angles.size()):
		var back: float = smoothstep(0.0, 0.18 + 0.06 * fractions[i], elapsed)
		current_angles[i] = lerpf(_from_angles[i], rest_angles[i], back)
	var recover: float = 1.0 - smoothstep(0.0, RECOVER_SECONDS, elapsed)
	straighten = _from_straighten * recover
	hang = _from_hang * recover
	sweep = _from_sweep * (1.0 - smoothstep(0.0, ParryScript.EXIT_SECONDS, elapsed))


static func release_at(q: float, s: float) -> float:
	return smoothstep(0.02 + 0.35 * s, 0.42 + 0.58 * s, q)


static func traveling_bend(q: float, s: float) -> float:
	if q <= 0.0 or q >= 1.0:
		return 0.0
	var center: float = 0.18 + 0.95 * q
	return TRAVEL_BEND * pow(sin(PI * q), 2.0) * exp(-pow((s - center) / 0.24, 2.0)) * smoothstep(0.10, 0.26, s)


static func follow_bend(progress: float, s: float) -> float:
	var p: float = clampf(progress, 0.0, 1.0)
	var center: float = 0.20 + 0.68 * p
	var band: float = smoothstep(center - 0.30, center - 0.05, s) - smoothstep(center + 0.05, center + 0.30, s)
	var amplitude: float = lerpf(FOLLOW_WAVE_BEND, FOLLOW_END_BEND, smoothstep(0.65, 1.0, p))
	var downward_tip: float = 0.80 * smoothstep(0.70, 1.0, s) * smoothstep(0.35, 1.0, p)
	return -amplitude * band * smoothstep(0.0, 0.25, p) * smoothstep(0.10, 0.26, s) + downward_tip


func follow_seconds() -> float:
	if blocked:
		return -1.0
	if state == StateScript.ActionState.STRIKE:
		return elapsed - duration * contact_ratio
	if state == StateScript.ActionState.COOLDOWN and _continued_follow_seconds >= 0.0:
		return _continued_follow_seconds + elapsed
	return -1.0


func follow_progress() -> float:
	# 接触地点で静止せずに通過する。終端だけ減速させる。
	var u: float = clampf(follow_seconds() / FOLLOW_SECONDS, 0.0, 1.0)
	return u * (2.0 - u)


func recovery_seconds() -> float:
	if state == StateScript.ActionState.COOLDOWN and _continued_follow_seconds >= 0.0:
		return maxf(0.0, follow_seconds() - FOLLOW_SECONDS)
	return elapsed


func final_follow_angles() -> PackedFloat32Array:
	var result: PackedFloat32Array = straight_angles.duplicate()
	for i in range(result.size()):
		result[i] += follow_bend(1.0, fractions[i])
	return result


func force_contact() -> bool:
	if not configured or blocked or state not in [StateScript.ActionState.STRIKE, StateScript.ActionState.COOLDOWN]:
		return false
	# 遅れて届いた確定通知は、既に通過した時計や姿勢を戻さない。
	if follow_seconds() >= -0.000001:
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
		_continued_follow_seconds = 0.0
		elapsed = 0.0
	return true


func visual_vertices() -> PackedVector2Array:
	if not configured:
		return PackedVector2Array()
	var result: PackedVector2Array = visual_vertices_from_angles(current_angles)
	if absf(sweep) > 0.000001:
		result = ParryScript.deform(_profile, result, sweep)
	return result


func visual_vertices_from_angles(values: PackedFloat32Array) -> PackedVector2Array:
	return vertices_from_angles(_softened_angles(values, _soft_counter_angle, softness))


func soft_idle_vertices(attachment_angle_radians: float, softness_amount: float = 1.0) -> PackedVector2Array:
	if not configured or not is_finite(attachment_angle_radians) or not is_finite(softness_amount):
		return PackedVector2Array()
	var bounded: float = clampf(softness_amount, 0.0, 1.0)
	var counter: float = -attachment_angle_radians * SOFT_COUNTER_RATIO * bounded
	return vertices_from_angles(_softened_angles(rest_angles, counter, bounded))


func _softened_angles(values: PackedFloat32Array, counter_angle: float, amount: float) -> PackedFloat32Array:
	if values.size() != fractions.size():
		return values.duplicate()
	var result: PackedFloat32Array = values.duplicate()
	var bounded: float = clampf(amount, 0.0, 1.0)
	for i in range(result.size()):
		var s: float = fractions[i]
		var flex: float = smoothstep(SOFT_ROOT_END, SOFT_FULL_AT, s)
		var tip_curve: float = SOFT_IDLE_CURVE * bounded * pow(smoothstep(0.45, 1.0, s), 1.35)
		result[i] += counter_angle * flex + tip_curve
	return result


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
	_continued_follow_seconds = -1.0
