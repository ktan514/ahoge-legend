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
const SOFT_CONTROL_COUNT: int = 9
# 共通default。NeckRangePreviewの未承認調整値はこのconstを書き換えず、
# set_soft_tuning()で当該ActionMotionインスタンスだけへ適用する。
const SOFT_ROOT_HINGE_HZ: float = 7.0
const SOFT_ROOT_HINGE_DAMPING: float = 0.44
const SOFT_ROOT_MAX_OFFSET: float = 0.22
const SOFT_ROOT_BLEND_END: float = 0.12
const SOFT_ROOT_START_WEIGHT: float = 1.0
const SOFT_MAX_OFFSET_STEP: float = 0.055
const SOFT_ROOT_DRIVE_RATIO: float = 0.70
const SOFT_NEXT_DRIVE_RATIO: float = 0.30
const SOFT_THIRD_DRIVE_RATIO: float = 0.0
const SOFT_CHAIN_HZ: float = 8.5
const SOFT_ROOT_DAMPING: float = 0.50
const SOFT_TIP_DAMPING: float = 0.18
const SOFT_SHAPE_RESTORE_RATIO: float = 0.05
const SOFT_RELATIVE_DAMPING_ROOT: float = 0.0
const SOFT_RELATIVE_DAMPING_TIP: float = 0.0
const SOFT_TIP_SPRING_GAIN: float = 1.75
const SOFT_FORWARD_ACCEL_DRIVE: float = 0.000010
const SOFT_DRIVE_LIMIT: float = 0.70
const SOFT_MAX_OFFSET: float = 0.70
const SOFT_MAX_STEP: float = 1.0 / 240.0

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
var _soft_control_indices: PackedInt32Array = PackedInt32Array()
var _soft_world_angles: PackedFloat32Array = PackedFloat32Array()
var _soft_velocities: PackedFloat32Array = PackedFloat32Array()
var _soft_previous_forward_px: float = 0.0
var _soft_previous_forward_velocity: float = 0.0
var _soft_previous_angle: float = 0.0
var _soft_motion_initialized: bool = false

var soft_control_targets: Array[float] = [0.00, 0.04, 0.10, 0.18, 0.30, 0.45, 0.62, 0.80, 1.00]
var soft_root_hinge_hz: float = SOFT_ROOT_HINGE_HZ
var soft_root_hinge_damping: float = SOFT_ROOT_HINGE_DAMPING
var soft_root_max_offset: float = SOFT_ROOT_MAX_OFFSET
var soft_root_blend_end: float = SOFT_ROOT_BLEND_END
var soft_root_start_weight: float = SOFT_ROOT_START_WEIGHT
var soft_max_offset_step: float = SOFT_MAX_OFFSET_STEP
var soft_root_drive_ratio: float = SOFT_ROOT_DRIVE_RATIO
var soft_next_drive_ratio: float = SOFT_NEXT_DRIVE_RATIO
var soft_third_drive_ratio: float = SOFT_THIRD_DRIVE_RATIO
var soft_chain_hz: float = SOFT_CHAIN_HZ
var soft_root_damping: float = SOFT_ROOT_DAMPING
var soft_tip_damping: float = SOFT_TIP_DAMPING
var soft_shape_restore_ratio: float = SOFT_SHAPE_RESTORE_RATIO
var soft_relative_damping_root: float = SOFT_RELATIVE_DAMPING_ROOT
var soft_relative_damping_tip: float = SOFT_RELATIVE_DAMPING_TIP
var soft_tip_spring_gain: float = SOFT_TIP_SPRING_GAIN
var soft_forward_accel_drive: float = SOFT_FORWARD_ACCEL_DRIVE
var soft_drive_limit: float = SOFT_DRIVE_LIMIT
var soft_max_offset: float = SOFT_MAX_OFFSET


func set_soft_tuning(tuning: Dictionary) -> bool:
	var targets_value = tuning.get("control_targets", soft_control_targets)
	if not (targets_value is Array) or targets_value.size() != SOFT_CONTROL_COUNT:
		return false
	var targets: Array[float] = []
	var previous: float = -1.0
	for raw in targets_value:
		if typeof(raw) not in [TYPE_FLOAT, TYPE_INT]:
			return false
		var value: float = float(raw)
		if not is_finite(value) or value < 0.0 or value > 1.0 or value <= previous:
			return false
		targets.append(value)
		previous = value
	if not is_zero_approx(targets[0]) or not is_equal_approx(targets[-1], 1.0):
		return false

	var numeric_keys: Array[String] = [
		"root_hinge_hz", "root_hinge_damping", "root_max_offset", "root_blend_end",
		"root_start_weight", "max_offset_step", "root_drive_ratio", "next_drive_ratio",
		"third_drive_ratio", "chain_hz", "root_damping", "tip_damping",
		"shape_restore_ratio", "relative_damping_root", "relative_damping_tip",
		"tip_spring_gain", "forward_accel_drive", "drive_limit", "max_offset"
	]
	for key in numeric_keys:
		if tuning.has(key):
			var raw_value = tuning[key]
			if typeof(raw_value) not in [TYPE_FLOAT, TYPE_INT] or not is_finite(float(raw_value)):
				return false

	soft_control_targets = targets
	soft_root_hinge_hz = maxf(0.01, float(tuning.get("root_hinge_hz", soft_root_hinge_hz)))
	soft_root_hinge_damping = maxf(0.0, float(tuning.get("root_hinge_damping", soft_root_hinge_damping)))
	soft_root_max_offset = maxf(0.0, float(tuning.get("root_max_offset", soft_root_max_offset)))
	soft_root_blend_end = clampf(float(tuning.get("root_blend_end", soft_root_blend_end)), 0.001, 1.0)
	soft_root_start_weight = clampf(float(tuning.get("root_start_weight", soft_root_start_weight)), 0.0, 1.0)
	soft_max_offset_step = maxf(0.0001, float(tuning.get("max_offset_step", soft_max_offset_step)))
	soft_root_drive_ratio = maxf(0.0, float(tuning.get("root_drive_ratio", soft_root_drive_ratio)))
	soft_next_drive_ratio = maxf(0.0, float(tuning.get("next_drive_ratio", soft_next_drive_ratio)))
	soft_third_drive_ratio = maxf(0.0, float(tuning.get("third_drive_ratio", soft_third_drive_ratio)))
	soft_chain_hz = maxf(0.01, float(tuning.get("chain_hz", soft_chain_hz)))
	soft_root_damping = maxf(0.0, float(tuning.get("root_damping", soft_root_damping)))
	soft_tip_damping = maxf(0.0, float(tuning.get("tip_damping", soft_tip_damping)))
	soft_shape_restore_ratio = clampf(float(tuning.get("shape_restore_ratio", soft_shape_restore_ratio)), 0.0, 1.0)
	soft_relative_damping_root = maxf(0.0, float(tuning.get("relative_damping_root", soft_relative_damping_root)))
	soft_relative_damping_tip = maxf(0.0, float(tuning.get("relative_damping_tip", soft_relative_damping_tip)))
	soft_tip_spring_gain = maxf(0.0, float(tuning.get("tip_spring_gain", soft_tip_spring_gain)))
	soft_forward_accel_drive = maxf(0.0, float(tuning.get("forward_accel_drive", soft_forward_accel_drive)))
	soft_drive_limit = maxf(0.0, float(tuning.get("drive_limit", soft_drive_limit)))
	soft_max_offset = maxf(0.0, float(tuning.get("max_offset", soft_max_offset)))
	_build_soft_controls()
	_reset_soft_motion()
	return true


func soft_tuning_snapshot() -> Dictionary:
	return {
		"control_targets": soft_control_targets.duplicate(),
		"root_hinge_hz": soft_root_hinge_hz,
		"root_hinge_damping": soft_root_hinge_damping,
		"root_max_offset": soft_root_max_offset,
		"root_blend_end": soft_root_blend_end,
		"root_start_weight": soft_root_start_weight,
		"max_offset_step": soft_max_offset_step,
		"root_drive_ratio": soft_root_drive_ratio,
		"next_drive_ratio": soft_next_drive_ratio,
		"third_drive_ratio": soft_third_drive_ratio,
		"chain_hz": soft_chain_hz,
		"root_damping": soft_root_damping,
		"tip_damping": soft_tip_damping,
		"shape_restore_ratio": soft_shape_restore_ratio,
		"relative_damping_root": soft_relative_damping_root,
		"relative_damping_tip": soft_relative_damping_tip,
		"tip_spring_gain": soft_tip_spring_gain,
		"forward_accel_drive": soft_forward_accel_drive,
		"drive_limit": soft_drive_limit,
		"max_offset": soft_max_offset
	}


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
	_build_soft_controls()
	_reset_pose()
	_reset_soft_motion()
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
	softness_amount: float = 1.0,
	attachment_forward_px: float = 0.0
) -> void:
	if not configured or delta <= 0.0 or not is_finite(delta):
		return
	if not is_finite(attachment_angle_radians) or not is_finite(softness_amount) or not is_finite(attachment_forward_px):
		return
	attachment_angle = attachment_angle_radians
	softness = clampf(softness_amount, 0.0, 1.0)
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
		_reset_soft_motion()
		_reset_pose()
		return
	if blocked:
		_reset_soft_motion()
		_reset_pose()
		return
	# 防御の最初の表示は現在形状を保持する。サーバーの防御開始は遅らせない。
	if not (changed and state == StateScript.ActionState.PARRY):
		elapsed += delta
	_compute_pose()
	_advance_softness(delta, attachment_angle, attachment_forward_px, softness, state, available)


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
	return vertices_from_angles(_softened_angles(values))


func soft_idle_vertices(attachment_angle_radians: float, softness_amount: float = 1.0) -> PackedVector2Array:
	if not configured or not is_finite(attachment_angle_radians) or not is_finite(softness_amount):
		return PackedVector2Array()
	# 静止中はActionMotionの基準形状へ収束する。
	return vertices_from_angles(rest_angles)


func reset_soft_follow(attachment_angle_radians: float = 0.0, attachment_forward_px: float = 0.0) -> void:
	if not configured or not is_finite(attachment_angle_radians) or not is_finite(attachment_forward_px):
		return
	attachment_angle = attachment_angle_radians
	_soft_previous_angle = attachment_angle_radians
	_soft_previous_forward_px = attachment_forward_px
	_soft_previous_forward_velocity = 0.0
	_sync_soft_chain(attachment_angle_radians)
	_soft_motion_initialized = true


func _build_soft_controls() -> void:
	_soft_control_indices = PackedInt32Array()
	if fractions.is_empty():
		return
	# 根元側へcontrolを密に置き、最初の10%を剛体にしない。
	for target in soft_control_targets:
		var best_index: int = 0
		var best_distance: float = INF
		for i in range(fractions.size()):
			var distance: float = absf(fractions[i] - target)
			if distance < best_distance:
				best_distance = distance
				best_index = i
		if not _soft_control_indices.is_empty():
			best_index = maxi(best_index, _soft_control_indices[-1] + 1)
		best_index = mini(best_index, fractions.size() - 1)
		_soft_control_indices.append(best_index)
	_soft_control_indices[0] = 0
	_soft_control_indices[-1] = fractions.size() - 1


func _sync_soft_chain(angle: float) -> void:
	if _soft_control_indices.size() != SOFT_CONTROL_COUNT:
		_build_soft_controls()
	_soft_world_angles = PackedFloat32Array()
	_soft_velocities = PackedFloat32Array()
	_soft_world_angles.resize(_soft_control_indices.size())
	_soft_velocities.resize(_soft_control_indices.size())
	for control in range(_soft_control_indices.size()):
		var index: int = _soft_control_indices[control]
		_soft_world_angles[control] = angle + current_angles[index]
		_soft_velocities[control] = 0.0


func _advance_softness(
	delta: float,
	angle: float,
	forward_px: float,
	amount: float,
	action_state: int,
	available: bool
) -> void:
	var bounded: float = clampf(amount, 0.0, 1.0)
	softness = bounded
	if not available or action_state == StateScript.ActionState.ROUND_LOCKED:
		_reset_soft_motion()
		return
	if not _soft_motion_initialized or _soft_world_angles.size() != SOFT_CONTROL_COUNT:
		_soft_previous_angle = angle
		_soft_previous_forward_px = forward_px
		_soft_previous_forward_velocity = 0.0
		_sync_soft_chain(angle)
		_soft_motion_initialized = true
		return

	var safe_delta: float = maxf(delta, 0.000001)
	var forward_velocity: float = (forward_px - _soft_previous_forward_px) / safe_delta
	if bounded <= 0.000001:
		_soft_previous_angle = angle
		_soft_previous_forward_px = forward_px
		_soft_previous_forward_velocity = forward_velocity
		_sync_soft_chain(angle)
		return

	var forward_acceleration: float = (forward_velocity - _soft_previous_forward_velocity) / safe_delta
	_soft_previous_forward_px = forward_px
	_soft_previous_forward_velocity = forward_velocity
	_soft_previous_angle = angle
	var drive: float = clampf(-forward_acceleration * soft_forward_accel_drive, -soft_drive_limit, soft_drive_limit)
	var remaining: float = delta
	while remaining > 0.0000001:
		var step: float = minf(remaining, SOFT_MAX_STEP)
		var previous_world: PackedFloat32Array = _soft_world_angles.duplicate()
		var previous_velocity: PackedFloat32Array = _soft_velocities.duplicate()
		var root_index: int = _soft_control_indices[0]
		var root_baseline: float = angle + current_angles[root_index]
		var root_target: float = root_baseline + drive * soft_root_drive_ratio
		var root_error: float = wrapf(root_target - previous_world[0], -PI, PI)
		var root_omega: float = TAU * soft_root_hinge_hz
		var root_acceleration: float = root_omega * root_omega * root_error - 2.0 * soft_root_hinge_damping * root_omega * previous_velocity[0]
		var root_velocity: float = previous_velocity[0] + root_acceleration * step
		var root_world: float = previous_world[0] + root_velocity * step
		var root_offset: float = clampf(wrapf(root_world - root_baseline, -PI, PI), -soft_root_max_offset, soft_root_max_offset)
		_soft_world_angles[0] = root_baseline + root_offset
		_soft_velocities[0] = root_velocity
		if absf(root_offset) >= soft_root_max_offset - 0.0001:
			_soft_velocities[0] *= 0.35
		for control in range(1, _soft_control_indices.size()):
			var index: int = _soft_control_indices[control]
			var previous_index: int = _soft_control_indices[control - 1]
			var desired_curve: float = wrapf(current_angles[index] - current_angles[previous_index], -PI, PI)
			var coupled_target: float = previous_world[control - 1] + desired_curve
			if control == 1:
				coupled_target += drive * soft_next_drive_ratio
			elif control == 2:
				coupled_target += drive * soft_third_drive_ratio
			var absolute_target: float = angle + current_angles[index]
			var target: float = lerp_angle(coupled_target, absolute_target, soft_shape_restore_ratio)
			var error: float = wrapf(target - previous_world[control], -PI, PI)
			var fraction: float = clampf(fractions[index], 0.0, 1.0)
			var damping: float = lerpf(soft_root_damping, soft_tip_damping, fraction)
			var relative_damping: float = lerpf(soft_relative_damping_root, soft_relative_damping_tip, fraction)
			var spring_gain: float = lerpf(1.0, soft_tip_spring_gain, fraction * fraction)
			var omega: float = TAU * soft_chain_hz
			var relative_velocity: float = previous_velocity[control] - previous_velocity[control - 1]
			var acceleration: float = (
				omega * omega * spring_gain * error
				- 2.0 * damping * omega * previous_velocity[control]
				- 2.0 * relative_damping * omega * relative_velocity
			)
			var velocity: float = previous_velocity[control] + acceleration * step
			var world_angle: float = previous_world[control] + velocity * step
			_soft_velocities[control] = velocity
			_soft_world_angles[control] = world_angle
		remaining -= step


func _control_offset(control: int) -> float:
	if control < 0 or control >= _soft_control_indices.size() or control >= _soft_world_angles.size():
		return 0.0
	var index: int = _soft_control_indices[control]
	var baseline: float = attachment_angle + current_angles[index]
	var limit: float = soft_root_max_offset if control == 0 else soft_max_offset
	return clampf(wrapf(_soft_world_angles[control] - baseline, -PI, PI), -limit, limit)


func _softened_angles(values: PackedFloat32Array) -> PackedFloat32Array:
	if values.size() != fractions.size() or softness <= 0.000001 or _soft_control_indices.size() < 2:
		return values.duplicate()
	var result: PackedFloat32Array = values.duplicate()
	var offsets: PackedFloat32Array = PackedFloat32Array()
	offsets.resize(result.size())
	var control: int = 0
	var root_offset: float = _control_offset(0)
	for i in range(result.size()):
		var s: float = fractions[i]
		while control < _soft_control_indices.size() - 2 and s > fractions[_soft_control_indices[control + 1]]:
			control += 1
		var left_index: int = _soft_control_indices[control]
		var right_index: int = _soft_control_indices[control + 1]
		var left_s: float = fractions[left_index]
		var right_s: float = fractions[right_index]
		var weight: float = 0.0 if right_s <= left_s else clampf((s - left_s) / (right_s - left_s), 0.0, 1.0)
		var interpolated: float = lerpf(_control_offset(control), _control_offset(control + 1), weight)
		# 根元〜30%へ勾配を作る。根元区間を一体回転させず、最初の区間から
		# 中央手前まで角度差を積み上げて「根元から曲がる」見え方にする。
		var root_progress: float = smoothstep(0.0, soft_root_blend_end, s)
		var root_weight: float = lerpf(soft_root_start_weight, 1.0, root_progress)
		var root_component: float = root_offset * root_weight
		var chain_component: float = (interpolated - root_offset) * root_progress
		offsets[i] = root_component + chain_component

	# 動的offset自体も軽く平滑化し、根元で折れた関節のような角を作らない。
	for pass_index in range(2):
		var source: PackedFloat32Array = offsets.duplicate()
		for i in range(1, offsets.size() - 1):
			offsets[i] = source[i - 1] * 0.20 + source[i] * 0.60 + source[i + 1] * 0.20

	# 隣接区間の角度差を両方向から制限し、面反転を防ぎながら曲げを全体へ分散する。
	for i in range(1, offsets.size()):
		offsets[i] = clampf(offsets[i], offsets[i - 1] - soft_max_offset_step, offsets[i - 1] + soft_max_offset_step)
	for i in range(offsets.size() - 2, -1, -1):
		offsets[i] = clampf(offsets[i], offsets[i + 1] - soft_max_offset_step, offsets[i + 1] + soft_max_offset_step)

	for i in range(result.size()):
		result[i] += offsets[i] * softness
	return result


func soft_control_world_angles() -> PackedFloat32Array:
	return _soft_world_angles.duplicate()


func soft_control_velocities() -> PackedFloat32Array:
	return _soft_velocities.duplicate()


func soft_control_indices() -> PackedInt32Array:
	return _soft_control_indices.duplicate()


func _reset_soft_motion() -> void:
	_soft_world_angles = PackedFloat32Array()
	_soft_velocities = PackedFloat32Array()
	_soft_previous_forward_px = 0.0
	_soft_previous_forward_velocity = 0.0
	_soft_previous_angle = 0.0
	_soft_motion_initialized = false


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
