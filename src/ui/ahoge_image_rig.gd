extends Node2D

const CombatantStateScript := preload("res://src/domain/combatant_state.gd")

@export var display_height: float = 248.0
@export var segments: int = 22
@export var velocity_influence: float = 3.2
@export var acceleration_influence: float = 0.55
@export var max_bend: float = 58.0
@export var root_spring: float = 34.0
@export var tip_spring: float = 14.0
@export var root_damping: float = 9.0
@export var tip_damping: float = 4.8
@export var propagation: float = 0.42
@export var tip_power: float = 1.7
@export var stretch_response: float = 7.0
@export var flatten_response: float = 12.0
@export var extension_spring_idle: float = 18.0
@export var extension_spring_charge: float = 28.0
@export var extension_spring_windup: float = 36.0
@export var extension_spring_strike: float = 105.0
@export var extension_damping: float = 8.0
@export var charge_back_extension: float = 90.0
@export var windup_back_extension: float = 130.0
@export var strike_forward_extension: float = 520.0
@export var strike_impulse: float = 1800.0
@export var strike_flatten: float = 0.68
@export var charge_follow_delay: float = 0.10
@export var parry_back_extension: float = 20.0
@export var dodge_back_extension: float = 28.0
@export var stagger_back_extension: float = 38.0

var _polygon: Polygon2D
var _texture: Texture2D
var _facing: float = 1.0
var _available: bool = true
var _display_width: float = 120.0

var _head_velocity := Vector2.ZERO
var _head_acceleration := Vector2.ZERO
var _action_bend_target: float = 0.0
var _action_extension_target: float = 0.0
var _action_extension: float = 0.0
var _action_extension_velocity: float = 0.0
var _action_state: int = CombatantStateScript.ActionState.IDLE
var _action_age: float = 0.0
var _stretch_target: float = 0.0
var _stretch: float = 0.0
var _flatten_target: float = 0.0
var _flatten: float = 0.0

var _joint_offsets := PackedFloat32Array()
var _joint_velocities := PackedFloat32Array()


func _ready() -> void:
	_polygon = Polygon2D.new()
	_polygon.name = "AhogePolygon"
	add_child(_polygon)
	_resize_joint_state()
	set_process(true)
	_refresh_mesh()


func configure(texture_value: Texture2D, facing_value: float) -> void:
	_texture = texture_value
	_facing = 1.0 if facing_value >= 0.0 else -1.0
	scale.x = _facing
	if _polygon != null:
		_polygon.texture = _texture
	_refresh_dimensions()
	_resize_joint_state()
	_refresh_mesh()


func set_motion(
	head_velocity: Vector2,
	head_acceleration: Vector2,
	action_state: int,
	available: bool
) -> void:
	_available = available
	visible = available
	_head_velocity = head_velocity
	_head_acceleration = head_acceleration

	if action_state != _action_state:
		_action_age = 0.0
		_on_action_state_changed(action_state)
	_action_state = action_state

	match action_state:
		CombatantStateScript.ActionState.CHARGING:
			_action_bend_target = -18.0
			_action_extension_target = -charge_back_extension
			_stretch_target = 0.06
			_flatten_target = 0.0
		CombatantStateScript.ActionState.WINDUP:
			_action_bend_target = -26.0
			_action_extension_target = -windup_back_extension
			_stretch_target = 0.08
			_flatten_target = 0.05
		CombatantStateScript.ActionState.STRIKE:
			_action_bend_target = 54.0
			_action_extension_target = strike_forward_extension
			_stretch_target = 0.04
			_flatten_target = strike_flatten
		CombatantStateScript.ActionState.PARRY:
			_action_bend_target = -10.0
			_action_extension_target = -parry_back_extension
			_stretch_target = 0.015
			_flatten_target = 0.0
		CombatantStateScript.ActionState.DODGE:
			_action_bend_target = -24.0
			_action_extension_target = -dodge_back_extension
			_stretch_target = -0.02
			_flatten_target = 0.0
		CombatantStateScript.ActionState.STAGGER:
			_action_bend_target = -34.0
			_action_extension_target = -stagger_back_extension
			_stretch_target = -0.04
			_flatten_target = 0.0
		_:
			_action_bend_target = 0.0
			_action_extension_target = 0.0
			_stretch_target = 0.0
			_flatten_target = 0.0


func kick(power: float = 1.0) -> void:
	if _joint_velocities.size() <= 1:
		return
	for index in range(1, _joint_velocities.size()):
		var t := float(index) / float(_joint_velocities.size() - 1)
		_joint_velocities[index] += 95.0 * power * pow(t, 1.8)


func _on_action_state_changed(action_state: int) -> void:
	match action_state:
		CombatantStateScript.ActionState.CHARGING:
			# 頭が先に後退し、アホ毛は慣性で一瞬その場へ残す。
			pass
		CombatantStateScript.ActionState.WINDUP:
			_action_extension_velocity -= 160.0
		CombatantStateScript.ActionState.STRIKE:
			_action_extension_velocity += strike_impulse
		CombatantStateScript.ActionState.STAGGER:
			_action_extension_velocity -= 260.0


func _process(delta: float) -> void:
	if delta <= 0.0 or not _available or _texture == null:
		return

	_action_age += delta
	_simulate_secondary_motion(delta)
	_refresh_mesh()


func _simulate_secondary_motion(delta: float) -> void:
	_resize_joint_state()
	if _joint_offsets.size() <= 1:
		return

	_stretch = lerpf(
		_stretch,
		_stretch_target + clampf(-_head_acceleration.y * 0.0025, -0.035, 0.035),
		minf(delta * stretch_response, 1.0)
	)
	_flatten = lerpf(
		_flatten,
		_flatten_target,
		minf(delta * flatten_response, 1.0)
	)
	var extension_spring := extension_spring_idle
	var effective_extension_target := _action_extension_target
	match _action_state:
		CombatantStateScript.ActionState.CHARGING:
			extension_spring = extension_spring_charge
			if _action_age < charge_follow_delay:
				# 6コマ②: 頭だけを先に後退させ、アホ毛は元位置付近へ残す。
				effective_extension_target = 0.0
		CombatantStateScript.ActionState.WINDUP:
			extension_spring = extension_spring_windup
		CombatantStateScript.ActionState.STRIKE:
			extension_spring = extension_spring_strike

	var extension_accel := (
		(effective_extension_target - _action_extension) * extension_spring
		- _action_extension_velocity * extension_damping
	)
	_action_extension_velocity += extension_accel * delta
	_action_extension += _action_extension_velocity * delta
	_action_extension = clampf(
		_action_extension,
		-windup_back_extension * 1.35,
		strike_forward_extension * 1.35
	)

	var inertial_target := (
		-_head_velocity.x * velocity_influence
		-_head_acceleration.x * acceleration_influence
		+ _action_bend_target
	)
	inertial_target = clampf(inertial_target, -max_bend, max_bend)

	_joint_offsets[0] = 0.0
	_joint_velocities[0] = 0.0

	for index in range(1, _joint_offsets.size()):
		var t := float(index) / float(_joint_offsets.size() - 1)
		var weight := pow(t, tip_power)
		var desired := inertial_target * weight

		if index > 1:
			desired = lerpf(
				desired,
				_joint_offsets[index - 1],
				propagation * (1.0 - t * 0.35)
			)

		var spring := lerpf(root_spring, tip_spring, t)
		var damping := lerpf(root_damping, tip_damping, t)
		var accel := (desired - _joint_offsets[index]) * spring
		accel -= _joint_velocities[index] * damping

		_joint_velocities[index] += accel * delta
		_joint_offsets[index] += _joint_velocities[index] * delta


func _resize_joint_state() -> void:
	var count := maxi(segments, 4) + 1
	if _joint_offsets.size() == count and _joint_velocities.size() == count:
		return

	_joint_offsets.resize(count)
	_joint_velocities.resize(count)
	for index in range(count):
		_joint_offsets[index] = 0.0
		_joint_velocities[index] = 0.0


func _refresh_dimensions() -> void:
	if _texture == null:
		return
	var source_size := _texture.get_size()
	if source_size.y <= 0.0:
		return
	_display_width = display_height * source_size.x / source_size.y


func _refresh_mesh() -> void:
	if _polygon == null or _texture == null:
		return

	_resize_joint_state()
	var safe_segments := maxi(segments, 4)
	var points := PackedVector2Array()
	var uvs := PackedVector2Array()
	var source_size := _texture.get_size()

	for index in range(safe_segments + 1):
		var t := float(index) / float(safe_segments)
		var center := _segment_center(index, t)
		points.append(center + Vector2(-_display_width * 0.5, 0.0))
		uvs.append(Vector2(0.0, source_size.y * (1.0 - t)))

	for index in range(safe_segments, -1, -1):
		var t := float(index) / float(safe_segments)
		var center := _segment_center(index, t)
		points.append(center + Vector2(_display_width * 0.5, 0.0))
		uvs.append(Vector2(source_size.x, source_size.y * (1.0 - t)))

	_polygon.polygon = points
	_polygon.uv = uvs
	_polygon.texture = _texture


func _segment_center(index: int, t: float) -> Vector2:
	var x := 0.0
	if index >= 0 and index < _joint_offsets.size():
		x = _joint_offsets[index]

	# 透明余白がある画像でも実際の毛先まで伸長が伝わるよう、
	# 上側segment全体へ滑らかにextensionを配る。rootだけは固定する。
	var extension_weight := smoothstep(0.08, 0.92, t)
	x += _action_extension * extension_weight

	# STRIKEでは縦長の元形状を横方向へ引き伸ばす。
	# tipへ到達する見た目を頭部前進ではなくアホ毛変形で作る。
	var height_scale := maxf(0.18, (1.0 + _stretch) * (1.0 - _flatten))
	var y := -display_height * height_scale * t
	return Vector2(x, y)
