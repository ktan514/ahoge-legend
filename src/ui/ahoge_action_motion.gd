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
const ACTIVE_START_Q: float = 0.18
const ACTIVE_FULL_Q: float = 0.88
const ACTIVE_ROOT_FRACTION: float = 0.12
const ACTIVE_FULL_FRACTION: float = 0.55
const ACTIVE_NORMAL_STRETCH: float = 1.22
const ACTIVE_CHARGED_STRETCH: float = 1.45
const ACTIVE_MAX_OFFSET_STEP: float = 0.045
const ACTIVE_TIP_SNAP_START_Q: float = 0.90
const ACTIVE_TIP_SNAP_FRACTION: float = 0.70
const ACTIVE_TIP_SNAP_WEIGHT: float = 0.70
const ACTIVE_DISTAL_AIM_FRACTION: float = 0.70
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
const SOFT_DYNAMIC_CURVE_RETENTION: float = 1.0
const SOFT_DIRECTIONAL_CURVE_RETENTION: float = 1.0
const SOFT_DIRECTIONAL_ROOT_HZ: float = SOFT_ROOT_HINGE_HZ
const SOFT_DIRECTIONAL_ROOT_MAX_OFFSET: float = SOFT_ROOT_MAX_OFFSET
const SOFT_DIRECTIONAL_MAX_OFFSET: float = SOFT_MAX_OFFSET
const SOFT_DIRECTIONAL_CONTROL_STEP: float = PI
const SOFT_DIRECTIONAL_CONTROL_STEP_TIP: float = PI
const SOFT_CURVE_RELEASE_SPEED: float = 1500.0
const SOFT_CURVE_RELEASE_ANGULAR_SPEED: float = 6.0
const SOFT_FORWARD_ACCEL_DRIVE: float = 0.000010
const SOFT_DRIVE_LIMIT: float = 0.70
const SOFT_MAX_OFFSET: float = 0.70
# 通常Battleでは無効の中立値。NeckRangePreviewのHuman Verification用Active Driveだけ
# set_soft_tuning()で上書きする。
const SOFT_ACTIVE_TIP_MASS: float = 1.0
const SOFT_ACTIVE_ROOT_DIRECT_GAIN: float = 0.0
const SOFT_ACTIVE_TIP_DIRECT_GAIN: float = 0.0
const SOFT_ACTIVE_TIP_DRIVE_GAIN: float = 1.0
const SOFT_ACTIVE_TIP_DAMPING_RATIO: float = 1.0
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
var _soft_directional_amount: float = 0.0
var _soft_directional_direction: float = 0.0
var _soft_active_progress: float = -1.0
var _soft_elastic_stretch: float = 0.0

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
var soft_dynamic_curve_retention: float = SOFT_DYNAMIC_CURVE_RETENTION
var soft_directional_curve_retention: float = SOFT_DIRECTIONAL_CURVE_RETENTION
var soft_directional_root_hz: float = SOFT_DIRECTIONAL_ROOT_HZ
var soft_directional_root_max_offset: float = SOFT_DIRECTIONAL_ROOT_MAX_OFFSET
var soft_directional_max_offset: float = SOFT_DIRECTIONAL_MAX_OFFSET
var soft_directional_control_step: float = SOFT_DIRECTIONAL_CONTROL_STEP
var soft_directional_control_step_tip: float = SOFT_DIRECTIONAL_CONTROL_STEP_TIP
var soft_curve_release_speed: float = SOFT_CURVE_RELEASE_SPEED
var soft_curve_release_angular_speed: float = SOFT_CURVE_RELEASE_ANGULAR_SPEED
var soft_forward_accel_drive: float = SOFT_FORWARD_ACCEL_DRIVE
var soft_drive_limit: float = SOFT_DRIVE_LIMIT
var soft_max_offset: float = SOFT_MAX_OFFSET
var soft_active_tip_mass: float = SOFT_ACTIVE_TIP_MASS
var soft_active_root_direct_gain: float = SOFT_ACTIVE_ROOT_DIRECT_GAIN
var soft_active_tip_direct_gain: float = SOFT_ACTIVE_TIP_DIRECT_GAIN
var soft_active_tip_drive_gain: float = SOFT_ACTIVE_TIP_DRIVE_GAIN
var soft_active_tip_damping_ratio: float = SOFT_ACTIVE_TIP_DAMPING_RATIO


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
		"tip_spring_gain", "dynamic_curve_retention", "directional_curve_retention",
		"directional_root_hz", "directional_root_max_offset", "directional_max_offset", "directional_control_step", "directional_control_step_tip", "curve_release_speed",
		"curve_release_angular_speed", "forward_accel_drive", "drive_limit", "max_offset",
		"active_tip_mass", "active_root_direct_gain", "active_tip_direct_gain",
		"active_tip_drive_gain", "active_tip_damping_ratio"
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
	soft_dynamic_curve_retention = clampf(float(tuning.get("dynamic_curve_retention", soft_dynamic_curve_retention)), 0.0, 1.0)
	soft_directional_curve_retention = clampf(float(tuning.get("directional_curve_retention", soft_directional_curve_retention)), 0.0, 1.0)
	soft_directional_root_hz = maxf(0.01, float(tuning.get("directional_root_hz", soft_directional_root_hz)))
	soft_directional_root_max_offset = maxf(0.0, float(tuning.get("directional_root_max_offset", soft_directional_root_max_offset)))
	soft_directional_max_offset = maxf(0.0, float(tuning.get("directional_max_offset", soft_directional_max_offset)))
	soft_directional_control_step = clampf(float(tuning.get("directional_control_step", soft_directional_control_step)), 0.001, PI)
	soft_directional_control_step_tip = clampf(float(tuning.get("directional_control_step_tip", soft_directional_control_step_tip)), 0.001, PI)
	soft_curve_release_speed = maxf(1.0, float(tuning.get("curve_release_speed", soft_curve_release_speed)))
	soft_curve_release_angular_speed = maxf(0.01, float(tuning.get("curve_release_angular_speed", soft_curve_release_angular_speed)))
	soft_forward_accel_drive = maxf(0.0, float(tuning.get("forward_accel_drive", soft_forward_accel_drive)))
	soft_drive_limit = maxf(0.0, float(tuning.get("drive_limit", soft_drive_limit)))
	soft_max_offset = maxf(0.0, float(tuning.get("max_offset", soft_max_offset)))
	soft_active_tip_mass = maxf(1.0, float(tuning.get("active_tip_mass", soft_active_tip_mass)))
	soft_active_root_direct_gain = clampf(float(tuning.get("active_root_direct_gain", soft_active_root_direct_gain)), 0.0, 1.0)
	soft_active_tip_direct_gain = clampf(float(tuning.get("active_tip_direct_gain", soft_active_tip_direct_gain)), 0.0, 1.0)
	soft_active_tip_drive_gain = maxf(1.0, float(tuning.get("active_tip_drive_gain", soft_active_tip_drive_gain)))
	soft_active_tip_damping_ratio = clampf(float(tuning.get("active_tip_damping_ratio", soft_active_tip_damping_ratio)), 0.05, 1.0)
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
		"dynamic_curve_retention": soft_dynamic_curve_retention,
		"directional_curve_retention": soft_directional_curve_retention,
		"directional_root_hz": soft_directional_root_hz,
		"directional_root_max_offset": soft_directional_root_max_offset,
		"directional_max_offset": soft_directional_max_offset,
		"directional_control_step": soft_directional_control_step,
		"directional_control_step_tip": soft_directional_control_step_tip,
		"curve_release_speed": soft_curve_release_speed,
		"curve_release_angular_speed": soft_curve_release_angular_speed,
		"forward_accel_drive": soft_forward_accel_drive,
		"drive_limit": soft_drive_limit,
		"max_offset": soft_max_offset,
		"active_tip_mass": soft_active_tip_mass,
		"active_root_direct_gain": soft_active_root_direct_gain,
		"active_tip_direct_gain": soft_active_tip_direct_gain,
		"active_tip_drive_gain": soft_active_tip_drive_gain,
		"active_tip_damping_ratio": soft_active_tip_damping_ratio
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
	attachment_forward_px: float = 0.0,
	directional_amount: float = 0.0,
	directional_direction: float = 0.0,
	active_progress: float = -1.0,
	elastic_stretch: float = 0.0
) -> void:
	if not configured or delta <= 0.0 or not is_finite(delta):
		return
	if (
		not is_finite(attachment_angle_radians)
		or not is_finite(softness_amount)
		or not is_finite(attachment_forward_px)
		or not is_finite(directional_amount)
		or not is_finite(directional_direction)
		or not is_finite(active_progress)
		or not is_finite(elastic_stretch)
	):
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
	var effective_softness: float = softness
	if (
		state == StateScript.ActionState.COOLDOWN
		and _continued_follow_seconds >= 0.0
		and follow_seconds() >= 0.0
		and follow_seconds() <= FOLLOW_SECONDS + 0.000001
	):
		# 接触後0.16秒はActive Strikeの振り抜き軌道を正とし、
		# 頭部回復加速度によるPassive Flexの反動を重ねない。
		effective_softness = 0.0
	_advance_softness(
		delta,
		attachment_angle,
		attachment_forward_px,
		effective_softness,
		state,
		available,
		clampf(directional_amount, 0.0, 1.0),
		clampf(directional_direction, -1.0, 1.0),
		clampf(active_progress, -1.0, 1.0),
		clampf(elastic_stretch, -0.08, 0.14)
	)


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
	var softened: PackedFloat32Array = _softened_angles(values)
	if absf(_soft_elastic_stretch) <= 0.000001 or _soft_directional_amount <= 0.000001:
		return vertices_from_angles(softened)
	var length_scales: PackedFloat32Array = PackedFloat32Array()
	length_scales.resize(softened.size())
	for i in range(length_scales.size()):
		# 根元固定を守り、弧長方向にだけ伸縮を増やす。
		var weight: float = smoothstep(0.08, 1.0, fractions[i])
		length_scales[i] = 1.0 + _soft_elastic_stretch * weight
	return vertices_from_angles_scaled(softened, length_scales)


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
	available: bool,
	directional_amount: float,
	directional_direction: float,
	active_progress: float,
	elastic_stretch: float
) -> void:
	var bounded: float = clampf(amount, 0.0, 1.0)
	softness = bounded
	_soft_directional_amount = clampf(directional_amount, 0.0, 1.0) * bounded
	_soft_directional_direction = clampf(directional_direction, -1.0, 1.0)
	_soft_active_progress = clampf(active_progress, -1.0, 1.0)
	_soft_elastic_stretch = clampf(elastic_stretch, -0.08, 0.14) * bounded
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
	var angular_velocity: float = wrapf(angle - _soft_previous_angle, -PI, PI) / safe_delta
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
	var speed_activity: float = clampf(absf(forward_velocity) / soft_curve_release_speed, 0.0, 1.0)
	var angular_activity: float = clampf(absf(angular_velocity) / soft_curve_release_angular_speed, 0.0, 1.0)
	var drive_activity: float = clampf(absf(drive) / maxf(soft_drive_limit, 0.000001), 0.0, 1.0)
	var motion_activity: float = maxf(speed_activity, maxf(angular_activity, drive_activity))
	var dynamic_curve_retention: float = lerpf(
		1.0,
		soft_dynamic_curve_retention,
		smoothstep(0.05, 1.0, motion_activity)
	)
	var directional_weight: float = _soft_directional_amount
	var direction_u: float = (_soft_directional_direction + 1.0) * 0.5
	var directional_local_angle: float = lerpf(-PI, 0.0, direction_u)
	var curve_retention: float = dynamic_curve_retention * lerpf(
		1.0,
		soft_directional_curve_retention,
		directional_weight
	)
	var remaining: float = delta
	while remaining > 0.0000001:
		var step: float = minf(remaining, SOFT_MAX_STEP)
		var previous_world: PackedFloat32Array = _soft_world_angles.duplicate()
		var previous_velocity: PackedFloat32Array = _soft_velocities.duplicate()
		var root_index: int = _soft_control_indices[0]
		var root_local_baseline: float = current_angles[root_index]
		var root_local_target: float = lerp_angle(root_local_baseline, directional_local_angle, directional_weight)
		var root_baseline: float = angle + root_local_baseline
		var root_target: float = angle + root_local_target + drive * soft_root_drive_ratio
		var root_error: float = wrapf(root_target - previous_world[0], -PI, PI)
		var root_hz: float = lerpf(soft_root_hinge_hz, soft_directional_root_hz, directional_weight)
		var root_omega: float = TAU * root_hz
		var root_acceleration: float = root_omega * root_omega * root_error - 2.0 * soft_root_hinge_damping * root_omega * previous_velocity[0]
		var root_velocity: float = previous_velocity[0] + root_acceleration * step
		var root_world: float = previous_world[0] + root_velocity * step
		var root_limit: float = lerpf(soft_root_max_offset, soft_directional_root_max_offset, directional_weight)
		var root_offset: float = clampf(wrapf(root_world - root_baseline, -PI, PI), -root_limit, root_limit)
		_soft_world_angles[0] = root_baseline + root_offset
		_soft_velocities[0] = root_velocity
		if absf(root_offset) >= root_limit - 0.0001:
			_soft_velocities[0] *= 0.35
		for control in range(1, _soft_control_indices.size()):
			var index: int = _soft_control_indices[control]
			var previous_index: int = _soft_control_indices[control - 1]
			var desired_curve: float = wrapf(current_angles[index] - current_angles[previous_index], -PI, PI)
			# 高速移動中は待機C字の局所曲率を弱め、毛束を根元〜中央からほどく。
			# 停止時はdynamic_curve_retention=1へ戻るため、待機C字へ自然復元する。
			desired_curve *= curve_retention
			var coupled_target: float = previous_world[control - 1] + desired_curve
			if control == 1:
				coupled_target += drive * soft_next_drive_ratio
			elif control == 2:
				coupled_target += drive * soft_third_drive_ratio
			var absolute_target: float = angle + current_angles[index]
			# 通常の方向付き伸長ではrootだけが絶対方向targetを直接受ける。
			# NeckRange専用Active Driveが有効なときだけ、弧長方向に開始時刻を遅らせて
			# control 1〜8へ前方targetを順番に開く。全control同時の剛体回転にはしない。
			var absolute_restore: float = soft_shape_restore_ratio * (1.0 - directional_weight)
			var target: float = lerp_angle(coupled_target, absolute_target, absolute_restore)
			var fraction: float = clampf(fractions[index], 0.0, 1.0)
			var active_section: float = 0.0
			if _soft_active_progress >= 0.0 and directional_weight > 0.000001:
				var active_start: float = 0.30 + 0.55 * smoothstep(0.0, 1.0, fraction)
				var active_full: float = 0.50 + 0.50 * smoothstep(0.0, 1.0, fraction)
				active_section = smoothstep(active_start, active_full, _soft_active_progress)
				var direct_gain: float = lerpf(
					soft_active_root_direct_gain,
					soft_active_tip_direct_gain,
					smoothstep(0.0, 1.0, fraction)
				) * active_section
				# キャラクター前方基準のlocal 0radへ自力で向く。
				target = lerp_angle(target, angle, direct_gain)
			var error: float = wrapf(target - previous_world[control], -PI, PI)
			var mass: float = lerpf(1.0, soft_active_tip_mass, pow(fraction, 1.5))
			var damping: float = lerpf(soft_root_damping, soft_tip_damping, fraction)
			damping *= lerpf(1.0, soft_active_tip_damping_ratio, active_section * fraction)
			var relative_damping: float = lerpf(soft_relative_damping_root, soft_relative_damping_tip, fraction)
			# directional chainでは中央から明確に遅らせる。通常のPassive Flexは従来のfraction²を維持する。
			var spring_fraction: float = fraction if directional_weight > 0.000001 else fraction * fraction
			var spring_gain: float = lerpf(1.0, soft_tip_spring_gain, spring_fraction)
			var active_drive_gain: float = lerpf(
				1.0,
				lerpf(1.0, soft_active_tip_drive_gain, fraction),
				active_section
			)
			var omega: float = TAU * soft_chain_hz
			var relative_velocity: float = previous_velocity[control] - previous_velocity[control - 1]
			var acceleration: float = (
				omega * omega * spring_gain * active_drive_gain * error / mass
				- 2.0 * damping * omega * previous_velocity[control]
				- 2.0 * relative_damping * omega * relative_velocity
			)
			var velocity: float = previous_velocity[control] + acceleration * step
			var world_angle: float = previous_world[control] + velocity * step
			if directional_weight > 0.000001:
				# 描画segmentではなく動的control同士の差を制限する。
				# controlの速度状態は残すため、rootの変化を同一frameでtipまで書き換えない。
				var upstream_world: float = _soft_world_angles[control - 1]
				var relative_angle: float = wrapf(world_angle - upstream_world, -PI, PI)
				var control_step_limit: float = lerpf(
					soft_directional_control_step,
					soft_directional_control_step_tip,
					fraction
				)
				var limited_relative: float = clampf(
					relative_angle,
					-control_step_limit,
					control_step_limit
				)
				if not is_equal_approx(relative_angle, limited_relative):
					world_angle = upstream_world + limited_relative
					velocity *= 0.35
			_soft_velocities[control] = velocity
			_soft_world_angles[control] = world_angle
		remaining -= step


func _control_offset(control: int) -> float:
	if control < 0 or control >= _soft_control_indices.size() or control >= _soft_world_angles.size():
		return 0.0
	var index: int = _soft_control_indices[control]
	var baseline: float = attachment_angle + current_angles[index]
	var normal_limit: float = soft_root_max_offset if control == 0 else soft_max_offset
	var directional_limit: float = soft_directional_root_max_offset if control == 0 else soft_directional_max_offset
	var limit: float = lerpf(normal_limit, directional_limit, _soft_directional_amount)
	return clampf(wrapf(_soft_world_angles[control] - baseline, -PI, PI), -limit, limit)


func _softened_angles(values: PackedFloat32Array) -> PackedFloat32Array:
	if values.size() != fractions.size() or softness <= 0.000001 or _soft_control_indices.size() < 2:
		return values.duplicate()

	# NeckRangeの方向付き伸長では、待機C字へのoffset差分へ戻さず、
	# chainが実際に保持している区間角度をlocalへ戻して直接描画する。
	# これにより保持中はほぼ直線、反転中だけcontrol間の位相差で曲がる。
	if _soft_directional_amount > 0.000001 and _soft_world_angles.size() == _soft_control_indices.size():
		var directional_result: PackedFloat32Array = values.duplicate()
		var directional_control: int = 0
		for i in range(directional_result.size()):
			var s: float = fractions[i]
			while directional_control < _soft_control_indices.size() - 2 and s > fractions[_soft_control_indices[directional_control + 1]]:
				directional_control += 1
			var left_index: int = _soft_control_indices[directional_control]
			var right_index: int = _soft_control_indices[directional_control + 1]
			var left_s: float = fractions[left_index]
			var right_s: float = fractions[right_index]
			var weight: float = 0.0 if right_s <= left_s else clampf((s - left_s) / (right_s - left_s), 0.0, 1.0)
			var left_local: float = _soft_world_angles[directional_control] - attachment_angle
			var right_local: float = _soft_world_angles[directional_control + 1] - attachment_angle
			var chain_local: float = lerp_angle(left_local, right_local, weight)
			directional_result[i] = lerp_angle(values[i], chain_local, _soft_directional_amount)

		return directional_result

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
	_soft_directional_amount = 0.0
	_soft_directional_direction = 0.0
	_soft_active_progress = -1.0
	_soft_elastic_stretch = 0.0


func active_strike_vertices(target_local: Vector2, contact_progress: float, charge_ratio: float) -> PackedVector2Array:
	if not configured or target_local.length() <= 0.01 or not target_local.is_finite():
		return visual_vertices()
	var q: float = clampf(contact_progress, 0.0, 1.0)
	var global_active: float = smoothstep(ACTIVE_START_Q, ACTIVE_FULL_Q, q)
	if global_active <= 0.000001:
		return visual_vertices()
	var base_angles: PackedFloat32Array = _softened_angles(current_angles)
	var aimed_angles: PackedFloat32Array = base_angles.duplicate()
	var desired_angle: float = target_local.angle()
	var stretch_max: float = lerpf(ACTIVE_NORMAL_STRETCH, ACTIVE_CHARGED_STRETCH, clampf(charge_ratio, 0.0, 1.0))
	var length_scales: PackedFloat32Array = PackedFloat32Array()
	var active_offsets: PackedFloat32Array = PackedFloat32Array()
	var snap_offsets: PackedFloat32Array = PackedFloat32Array()
	length_scales.resize(base_angles.size())
	active_offsets.resize(base_angles.size())
	snap_offsets.resize(base_angles.size())
	for i in range(base_angles.size()):
		var s: float = fractions[i]
		# 能動制御もchainと同様に根元側から毛先側へ時間差で伝える。
		# 全区間を同じactive値で動かすとmiddle/tipの速度ピークが同時になる。
		var timing: float = smoothstep(0.08, 0.65, s)
		var section_start: float = lerpf(ACTIVE_START_Q, 0.38, timing)
		var section_full: float = lerpf(0.72, 0.84, timing)
		if s > 0.65:
			# distal 35%は別の「溜め→スナップ」領域。
			# 中央が動いている間は後方遅れを保ち、接触直前に毛先自身の速度ピークを作る。
			var distal: float = smoothstep(0.65, 1.0, s)
			section_start = lerpf(0.38, 0.88, distal)
			section_full = lerpf(0.84, 1.0, distal)
		var section_active: float = smoothstep(section_start, section_full, q)
		var turn_weight: float = smoothstep(ACTIVE_ROOT_FRACTION, ACTIVE_FULL_FRACTION, s) * section_active
		var target_delta: float = wrapf(desired_angle - base_angles[i], -PI, PI)
		active_offsets[i] = target_delta * turn_weight

		# 中央のピーク後に毛先自身が最後の加速を出すterminal snap。
		# 通常turnとは分離し、後段の双方向clampで中央側へ同frame逆伝播させない。
		var snap_time: float = smoothstep(ACTIVE_TIP_SNAP_START_Q, 1.0, q)
		var snap_space: float = smoothstep(ACTIVE_TIP_SNAP_FRACTION, 1.0, s)
		snap_offsets[i] = target_delta * snap_time * snap_space * ACTIVE_TIP_SNAP_WEIGHT

		var stretch_weight: float = smoothstep(0.08, 0.92, s) * section_active
		length_scales[i] = lerpf(1.0, stretch_max, stretch_weight)

	# 能動turnを弧長方向へ平滑化し、1区間だけ折れる形を作らない。
	for pass_index in range(2):
		var source: PackedFloat32Array = active_offsets.duplicate()
		for i in range(1, active_offsets.size() - 1):
			active_offsets[i] = source[i - 1] * 0.20 + source[i] * 0.60 + source[i + 1] * 0.20
	for i in range(1, active_offsets.size()):
		active_offsets[i] = clampf(
			active_offsets[i],
			active_offsets[i - 1] - ACTIVE_MAX_OFFSET_STEP,
			active_offsets[i - 1] + ACTIVE_MAX_OFFSET_STEP
		)
	for i in range(active_offsets.size() - 2, -1, -1):
		active_offsets[i] = clampf(
			active_offsets[i],
			active_offsets[i + 1] - ACTIVE_MAX_OFFSET_STEP,
			active_offsets[i + 1] + ACTIVE_MAX_OFFSET_STEP
		)

	# terminal snapは時間差を守るため通常turnの双方向clamp後に加える。
	# 追加後は根元→毛先だけをclampし、毛先の加速を上流へ瞬時に戻さない。
	for i in range(active_offsets.size()):
		active_offsets[i] += snap_offsets[i]
	for i in range(1, active_offsets.size()):
		active_offsets[i] = clampf(
			active_offsets[i],
			active_offsets[i - 1] - ACTIVE_MAX_OFFSET_STEP,
			active_offsets[i - 1] + ACTIVE_MAX_OFFSET_STEP
		)
	for i in range(base_angles.size()):
		aimed_angles[i] = base_angles[i] + active_offsets[i]
	var active_vertices: PackedVector2Array = vertices_from_angles_scaled(aimed_angles, length_scales)
	return _active_distal_aim(active_vertices, target_local, q)


func _active_distal_aim(source: PackedVector2Array, target_local: Vector2, q: float) -> PackedVector2Array:
	if q <= ACTIVE_TIP_SNAP_START_Q or source.is_empty() or target_local.length() <= 0.01:
		return source
	var width_points: int = int(_profile.WIDTH_POINTS)
	var source_centers: PackedVector2Array = ParryScript.centers_of(source, width_points)
	if source_centers.size() != _centers.size() or source_centers.size() < 3:
		return source
	var source_tip: Vector2 = source_centers[-1]
	if source_tip.length() <= 0.01:
		return source
	var time_weight: float = smoothstep(ACTIVE_TIP_SNAP_START_Q, 1.0, q)
	var turn: float = wrapf(target_local.angle() - source_tip.angle(), -PI, PI) * time_weight
	if absf(turn) <= 0.000001:
		return source
	var arc: PackedFloat32Array = ParryScript.arc_fractions(source_centers)
	var posed: PackedVector2Array = source_centers.duplicate()
	for i in range(1, posed.size()):
		var space_weight: float = smoothstep(ACTIVE_DISTAL_AIM_FRACTION, 1.0, arc[i])
		posed[i] = source_centers[i].rotated(turn * space_weight)
	posed[0] = Vector2.ZERO
	return _vertices_from_posed_centers(posed)


func active_stretch_ratio(contact_progress: float, charge_ratio: float) -> float:
	var active: float = smoothstep(ACTIVE_START_Q, ACTIVE_FULL_Q, clampf(contact_progress, 0.0, 1.0))
	return lerpf(1.0, lerpf(ACTIVE_NORMAL_STRETCH, ACTIVE_CHARGED_STRETCH, clampf(charge_ratio, 0.0, 1.0)), active)


func vertices_from_angles_scaled(values: PackedFloat32Array, length_scales: PackedFloat32Array) -> PackedVector2Array:
	if not configured or values.size() != _lengths.size() or length_scales.size() != _lengths.size():
		return PackedVector2Array()
	var posed: PackedVector2Array = PackedVector2Array([_centers[0]])
	for i in range(values.size()):
		var scale_value: float = clampf(length_scales[i], 0.25, 2.0)
		posed.append(posed[-1] + Vector2.from_angle(values[i]) * _lengths[i] * scale_value)
	return _vertices_from_posed_centers(posed)


func _vertices_from_posed_centers(posed: PackedVector2Array) -> PackedVector2Array:
	if posed.size() != _centers.size():
		return PackedVector2Array()
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


func vertices_from_angles(values: PackedFloat32Array) -> PackedVector2Array:
	if not configured or values.size() != _lengths.size():
		return PackedVector2Array()
	var posed: PackedVector2Array = PackedVector2Array([_centers[0]])
	for i in range(values.size()):
		posed.append(posed[-1] + Vector2.from_angle(values[i]) * _lengths[i])
	return _vertices_from_posed_centers(posed)


func _reset_pose() -> void:
	current_angles = rest_angles.duplicate()
	vertices = _profile.rest_vertices.duplicate()
	straighten = 0.0
	hang = 0.0
	sweep = 0.0
	_continued_follow_seconds = -1.0
