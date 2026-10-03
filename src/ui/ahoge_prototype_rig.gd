extends Node2D

const CombatantStateScript := preload("res://src/domain/combatant_state.gd")

@export var source_anchor_reference: Vector2 = Vector2(180.0, 1175.0)
@export var source_reference_size: Vector2 = Vector2(1254.0, 1254.0)
@export var minimum_base_scale: float = 0.21

var _texture: Texture2D
var _motion_root: Node2D
var _sprite: Sprite2D

var _facing: float = 1.0
var _available: bool = true

var _head_velocity := Vector2.ZERO
var _head_acceleration := Vector2.ZERO
var _action_state: int = CombatantStateScript.ActionState.IDLE
var _action_age: float = 0.0
var _charge_ratio: float = 0.0
var _phase_duration: float = 0.20
var _max_charge_duration: float = 0.60

var _whole_angle: float = 0.0
var _whole_angle_velocity: float = 0.0
var _whole_reach: float = 1.0
var _whole_reach_velocity: float = 0.0
var _last_angle_target: float = 0.0
var _last_reach_target: float = 1.0


func _ready() -> void:
	_motion_root = Node2D.new()
	_motion_root.name = "AhogeMotionRoot"
	add_child(_motion_root)

	_sprite = Sprite2D.new()
	_sprite.name = "AhogeSprite"
	_sprite.centered = false
	_motion_root.add_child(_sprite)

	set_process(true)


func configure(texture_value: Texture2D, facing_value: float) -> void:
	_texture = texture_value
	_facing = 1.0 if facing_value >= 0.0 else -1.0
	scale = Vector2(_facing, 1.0)

	if _sprite != null:
		_sprite.texture = _texture
		_update_sprite_anchor()
	_apply_visual_transform()


func set_motion(
	head_velocity: Vector2,
	head_acceleration: Vector2,
	action_state: int,
	available: bool,
	charge_ratio: float = 0.0,
	phase_duration: float = 0.20,
	max_charge_duration: float = 0.60
) -> void:
	_available = available
	visible = available
	_head_velocity = head_velocity
	_head_acceleration = head_acceleration
	_charge_ratio = clampf(charge_ratio, 0.0, 1.0)
	_phase_duration = maxf(phase_duration, 0.001)
	_max_charge_duration = maxf(max_charge_duration, 0.001)

	if action_state != _action_state:
		_action_age = 0.0
	_action_state = action_state


func kick(power: float = 1.0) -> void:
	# 元prototypeの主運動はtarget + spring/damping。
	# kickは補助的なovershootだけを与える。
	_whole_angle_velocity += 0.10 * power


func _process(delta: float) -> void:
	if delta <= 0.0 or not _available or _texture == null:
		return

	_action_age += delta
	_simulate_whole_motion(delta)
	_apply_visual_transform()


func _simulate_whole_motion(delta: float) -> void:
	var forward_v := _head_velocity.x
	var forward_a := _head_acceleration.x

	var angle_target := forward_v * 0.00135 + forward_a * 0.000028
	var reach_target := 1.0

	match _action_state:
		CombatantStateScript.ActionState.CHARGING:
			var tension := clampf(
				_action_age / _max_charge_duration,
				0.0,
				1.0
			)
			angle_target = (
				-0.28
				-0.48 * tension
				+ angle_target * 0.12
			)
			reach_target = 1.0

		CombatantStateScript.ActionState.WINDUP:
			var windup_q := clampf(_action_age / _phase_duration, 0.0, 1.0)
			if _charge_ratio > 0.0:
				angle_target = -0.38 - 0.40 * _charge_ratio
				reach_target = 1.0
			else:
				var follow := _ease_out(windup_q)
				angle_target -= 0.62 * follow
				reach_target = lerpf(1.0, 0.80, follow)

		CombatantStateScript.ActionState.STRIKE:
			var strike_u := clampf(_action_age / _phase_duration, 0.0, 1.0)
			if _charge_ratio > 0.0:
				var charged_release := _ease_out(
					clampf((strike_u - 0.035) / 0.74, 0.0, 1.0)
				)
				angle_target = lerpf(
					-0.38 - 0.40 * _charge_ratio,
					1.04 + 0.20 * _charge_ratio,
					charged_release
				)
				reach_target = lerpf(
					1.0,
					2.10 + 0.42 * _charge_ratio,
					charged_release
				)
			else:
				var lag := sin(clampf(strike_u / 0.44, 0.0, 1.0) * PI)
				var normal_release := _ease_out(
					clampf((strike_u - 0.30) / 0.70, 0.0, 1.0)
				)
				angle_target += -0.50 * lag + 1.04 * normal_release
				reach_target = lerpf(0.82, 2.05, normal_release)

		CombatantStateScript.ActionState.PARRY:
			var parry_u := clampf(_action_age / _phase_duration, 0.0, 1.0)
			var rise := _ease_out(clampf((parry_u - 0.08) / 0.26, 0.0, 1.0))
			var strike_down := _ease_out(clampf((parry_u - 0.30) / 0.25, 0.0, 1.0))
			var settle := _ease_out(clampf((parry_u - 0.56) / 0.34, 0.0, 1.0))
			var vertical_inertia := (
				-_head_velocity.y * 0.00225
				-_head_acceleration.y * 0.000045
			)
			angle_target += (
				vertical_inertia
				+1.28 * rise
				-1.72 * strike_down
				+0.52 * settle
			)
			reach_target = 1.0

	angle_target = clampf(angle_target, -1.38, 1.48)
	reach_target = clampf(reach_target, 0.74, 2.55)
	_last_angle_target = angle_target
	_last_reach_target = reach_target

	var parrying := _action_state == CombatantStateScript.ActionState.PARRY

	var angle_stiffness := 38.0
	if parrying:
		angle_stiffness = 84.0
	elif _action_state == CombatantStateScript.ActionState.CHARGING:
		angle_stiffness = 46.0
	elif (
		_action_state == CombatantStateScript.ActionState.STRIKE
		and _charge_ratio > 0.0
	):
		angle_stiffness = 58.0

	var angle_damping := 6.6
	if parrying:
		angle_damping = 9.0
	elif _action_state == CombatantStateScript.ActionState.CHARGING:
		angle_damping = 7.2
	elif (
		_action_state == CombatantStateScript.ActionState.STRIKE
		and _charge_ratio > 0.0
	):
		angle_damping = 7.8

	var angle_accel := (
		(angle_target - _whole_angle) * angle_stiffness
		- _whole_angle_velocity * angle_damping
	)
	_whole_angle_velocity += angle_accel * delta
	_whole_angle += _whole_angle_velocity * delta

	var reach_stiffness := 38.0
	if parrying:
		reach_stiffness = 74.0
	elif _action_state == CombatantStateScript.ActionState.CHARGING:
		reach_stiffness = 72.0
	elif (
		_action_state == CombatantStateScript.ActionState.WINDUP
		and _charge_ratio > 0.0
	):
		reach_stiffness = 70.0
	elif _action_state == CombatantStateScript.ActionState.STRIKE:
		reach_stiffness = 58.0

	var reach_damping := 7.2
	if parrying:
		reach_damping = 11.0
	elif _action_state == CombatantStateScript.ActionState.CHARGING:
		reach_damping = 11.5
	elif _action_state == CombatantStateScript.ActionState.STRIKE:
		reach_damping = 8.5

	var reach_accel := (
		(reach_target - _whole_reach) * reach_stiffness
		- _whole_reach_velocity * reach_damping
	)
	_whole_reach_velocity += reach_accel * delta
	_whole_reach += _whole_reach_velocity * delta

	_whole_angle = clampf(_whole_angle, -1.50, 1.60)
	_whole_reach = clampf(_whole_reach, 0.68, 2.62)


func _apply_visual_transform() -> void:
	if _motion_root == null or _sprite == null or _texture == null:
		return

	var base_scale := minimum_base_scale
	if is_inside_tree():
		var viewport_width := get_viewport_rect().size.x
		if viewport_width > 0.0:
			base_scale = maxf(minimum_base_scale, viewport_width / 5200.0)

	var vertical_squash := lerpf(
		1.0,
		0.82,
		clampf((_whole_reach - 1.0) / 1.45, 0.0, 1.0)
	)

	_motion_root.rotation = _whole_angle
	_motion_root.scale = Vector2(
		base_scale * _whole_reach,
		base_scale * vertical_squash
	)


func _update_sprite_anchor() -> void:
	if _sprite == null or _texture == null:
		return

	var source_size := _texture.get_size()
	var normalized_anchor := Vector2(
		source_anchor_reference.x / maxf(source_reference_size.x, 1.0),
		source_anchor_reference.y / maxf(source_reference_size.y, 1.0)
	)
	var anchor := Vector2(
		source_size.x * normalized_anchor.x,
		source_size.y * normalized_anchor.y
	)
	_sprite.position = -anchor


func _ease_out(value: float) -> float:
	var x := clampf(value, 0.0, 1.0)
	return 1.0 - pow(1.0 - x, 3.0)


func debug_angle() -> float:
	return _whole_angle


func debug_reach() -> float:
	return _whole_reach


func debug_vertical_squash() -> float:
	return lerpf(
		1.0,
		0.82,
		clampf((_whole_reach - 1.0) / 1.45, 0.0, 1.0)
	)


func debug_sprite_anchor() -> Vector2:
	if _sprite == null:
		return Vector2.ZERO
	return -_sprite.position


func debug_angle_target() -> float:
	return _last_angle_target


func debug_reach_target() -> float:
	return _last_reach_target
