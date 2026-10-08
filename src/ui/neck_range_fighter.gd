extends "res://src/ui/battle_fighter_visual.gd"

const StateScript := preload("res://src/domain/combatant_state.gd")

# 首の段階調整。通常の攻撃モーションは親へ委譲し、勝敗/入力は変更しない。
const MAX_TRAVEL_DIAMETERS: float = 0.4
const DEFAULT_GAZE_MAX_DEGREES: float = 30.0
const MAX_GAZE_MAX_DEGREES: float = 30.0

# NeckRangePreview専用の未承認tuning。
# MotionPreview/Battleの共通defaultへはHuman Verification合格まで昇格しない。
const NECK_SOFT_TUNING := {
	"control_targets": [0.00, 0.02, 0.05, 0.10, 0.18, 0.30, 0.45, 0.65, 1.00],
	"root_hinge_hz": 4.5,
	"root_hinge_damping": 1.00,
	"root_max_offset": 0.36,
	"root_blend_end": 0.30,
	"root_start_weight": 0.35,
	"max_offset_step": 0.045,
	"root_drive_ratio": 0.45,
	"next_drive_ratio": 0.35,
	"third_drive_ratio": 0.20,
	"chain_hz": 14.0,
	"root_damping": 0.95,
	"tip_damping": 1.00,
	"shape_restore_ratio": 0.018,
	"relative_damping_root": 0.40,
	"relative_damping_tip": 0.70,
	"tip_spring_gain": 0.45,
	"dynamic_curve_retention": 0.12,
	"directional_curve_retention": 0.00,
	"directional_root_hz": 20.0,
	"directional_root_max_offset": 3.10,
	"directional_max_offset": 3.10,
	"directional_control_step": 0.32,
	"directional_control_step_middle": 0.22,
	"directional_control_step_tip": 0.05,
	"active_tip_mass": 1.90,
	"active_root_direct_gain": 0.18,
	"active_tip_direct_gain": 0.82,
	"active_tip_drive_gain": 1.75,
	"active_tip_damping_ratio": 0.62,
	"active_preload_contraction": -0.035,
	"directional_clamp_previous_upstream": true,
	"curve_release_speed": 1500.0,
	"curve_release_angular_speed": 6.0,
	"forward_accel_drive": 0.000000,
	"drive_limit": 0.00,
	"max_offset": 0.65,
}

var neck_preview_enabled: bool = false
var neck_travel_ratio: float = 0.0
var neck_gaze_max_degrees: float = DEFAULT_GAZE_MAX_DEGREES
var ahoge_softness: float = 1.0
var ahoge_directional_amount: float = 0.0
var ahoge_directional_direction: float = 0.0
var ahoge_active_progress: float = -1.0
var ahoge_elastic_stretch: float = 0.0
var _neck_soft_tuning_applied: bool = false


func head_display_diameter() -> float:
	_cache_head_image()
	if _asset_mode and _head_used.has_area() and _head_sprite != null:
		# 中立時の素材横幅。回転・アホ毛・透過余白を含めない。
		return _head_used.size.x * absf(_head_sprite.scale.x)
	return 2.0 * (minf(122.0, maxf(92.0, size.x * 0.28)) + 5.0)


func set_neck_travel_ratio(value: float) -> bool:
	if not is_finite(value):
		return false
	neck_travel_ratio = clampf(value, -MAX_TRAVEL_DIAMETERS, MAX_TRAVEL_DIAMETERS)
	neck_preview_enabled = true
	_apply_neck_pose()
	return true


func set_neck_gaze_max_degrees(value: float) -> bool:
	if not is_finite(value):
		return false
	neck_gaze_max_degrees = clampf(value, 0.0, MAX_GAZE_MAX_DEGREES)
	if neck_preview_enabled:
		_apply_neck_pose()
	return true


func set_ahoge_softness(value: float) -> bool:
	if not super.set_motion_softness_amount(value):
		return false
	ahoge_softness = motion_softness_amount
	if neck_preview_enabled:
		_apply_neck_pose()
		reset_ahoge_soft_follow()
	return true


func _ensure_neck_soft_tuning() -> bool:
	if not action_motion.configured:
		return false
	if _neck_soft_tuning_applied:
		return true
	_neck_soft_tuning_applied = action_motion.set_soft_tuning(NECK_SOFT_TUNING)
	return _neck_soft_tuning_applied


func set_neck_ahoge_directional_extension(amount: float, direction: float) -> bool:
	if not is_finite(amount) or not is_finite(direction):
		return false
	ahoge_directional_amount = clampf(amount, 0.0, 1.0)
	ahoge_directional_direction = clampf(direction, -1.0, 1.0)
	return true


func set_neck_ahoge_attack_profile(active_progress: float, elastic_stretch: float) -> bool:
	if not is_finite(active_progress) or not is_finite(elastic_stretch):
		return false
	ahoge_active_progress = clampf(active_progress, -1.0, 1.0)
	ahoge_elastic_stretch = clampf(elastic_stretch, -0.08, 0.14)
	return true


func _neck_soft_attachment_angle() -> float:
	return deg_to_rad(_head_rotation * facing)


func _neck_soft_forward_px() -> float:
	return _head_offset.x * facing


func reset_ahoge_soft_follow() -> void:
	if not _ensure_neck_soft_tuning():
		return
	action_motion.reset_soft_follow(_neck_soft_attachment_angle(), _neck_soft_forward_px())


func advance_neck_preview(delta: float) -> void:
	if not neck_preview_enabled or delta <= 0.0 or not is_finite(delta):
		return
	_apply_neck_pose(delta)


func neck_gaze_elevation_degrees() -> float:
	# 仰角は上向きを正とする。後端(-0.4D)で+A、前端(+0.4D)で-A。
	return -(neck_travel_ratio / MAX_TRAVEL_DIAMETERS) * neck_gaze_max_degrees


func clear_neck_preview() -> void:
	neck_preview_enabled = false
	neck_travel_ratio = 0.0
	ahoge_directional_amount = 0.0
	ahoge_directional_direction = 0.0
	ahoge_active_progress = -1.0
	ahoge_elastic_stretch = 0.0
	_head_offset = Vector2.ZERO
	_head_velocity = Vector2.ZERO
	_head_acceleration = Vector2.ZERO
	_head_rotation = 0.0
	_requested_head_rotation = 0.0
	_head_entry_pose = Vector3.ZERO
	_presentation_state = -1
	_visual_action_state = -1
	_visual_action_age = 0.0
	_force_contact = false
	_contact_frozen = false
	_parry_blocks_old_contact = true
	action_motion = ActionMotionScript.new()
	_neck_soft_tuning_applied = false
	_update_asset_pose()
	queue_redraw()


func _process(delta: float) -> void:
	if neck_preview_enabled:
		_apply_neck_pose()
		return
	super._process(delta)


func present_toward(target_canvas: Vector2) -> void:
	if neck_preview_enabled:
		# 首だけを見るときに、相手への射程補正や自動復帰を重ねない。
		return
	super.present_toward(target_canvas)


func confirm_contact() -> bool:
	return false if neck_preview_enabled else super.confirm_contact()


func _apply_neck_pose(dynamic_delta: float = 0.0) -> void:
	if not is_inside_tree() or _head_sprite == null:
		return
	# 目そのものは描画しないため、首位置に応じた目線仰角を頭部回転で表現する。
	# Sprite2Dの画面回転は仰角と符号が逆。P2は左右反転するのでfacingも掛ける。
	var elevation: float = neck_gaze_elevation_degrees()
	_requested_head_rotation = -elevation * facing
	_head_rotation = _requested_head_rotation
	# resize直後にも、新しい表示倍率を反映してからDを求める。
	_update_asset_pose()
	_head_offset = Vector2(facing * head_display_diameter() * neck_travel_ratio, 0.0)
	_head_velocity = Vector2.ZERO
	_head_acceleration = Vector2.ZERO
	_update_asset_pose()
	if _asset_mode and _motion_node != null:
		_motion_node.transform = _neutral_transform()
		if _mesh_node != null and _mesh_node.configured:
			if not action_motion.configured:
				if action_motion.configure(_mesh_node.profile):
					_neck_soft_tuning_applied = false
			var idle_vertices: PackedVector2Array = _mesh_node.profile.rest_vertices
			if action_motion.configured and _ensure_neck_soft_tuning():
				if dynamic_delta > 0.0:
					action_motion.advance(
						StateScript.ActionState.IDLE,
						dynamic_delta,
						1.0,
						1.0,
						0.0,
						true,
						_neck_soft_attachment_angle(),
						ahoge_softness,
						_neck_soft_forward_px(),
						ahoge_directional_amount,
						ahoge_directional_direction,
						ahoge_active_progress,
						ahoge_elastic_stretch
					)
					idle_vertices = action_motion.visual_vertices()
				else:
					idle_vertices = action_motion.soft_idle_vertices(deg_to_rad(_head_rotation), ahoge_softness)
			_mesh_node.set_action_pose(idle_vertices, 0.0, 0.0)
	last_safety_scale = 1.0
	last_presentation_weight = 0.0
	last_contact_error = INF
	queue_redraw()
