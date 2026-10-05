extends "res://src/ui/battle_fighter_visual.gd"

const StateScript := preload("res://src/domain/combatant_state.gd")

# 首の段階調整。通常の攻撃モーションは親へ委譲し、勝敗/入力は変更しない。
const MAX_TRAVEL_DIAMETERS: float = 0.4
const DEFAULT_GAZE_MAX_DEGREES: float = 30.0
const MAX_GAZE_MAX_DEGREES: float = 30.0

var neck_preview_enabled: bool = false
var neck_travel_ratio: float = 0.0
var neck_gaze_max_degrees: float = DEFAULT_GAZE_MAX_DEGREES
var ahoge_softness: float = 1.0


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
	if not is_finite(value):
		return false
	ahoge_softness = clampf(value, 0.0, 1.0)
	if neck_preview_enabled:
		_apply_neck_pose()
		reset_ahoge_soft_follow()
	return true


func reset_ahoge_soft_follow() -> void:
	if not action_motion.configured:
		return
	action_motion.reset_soft_follow(deg_to_rad(_head_rotation), _head_offset.x * facing)


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
				action_motion.configure(_mesh_node.profile)
			var idle_vertices: PackedVector2Array = _mesh_node.profile.rest_vertices
			if action_motion.configured:
				if dynamic_delta > 0.0:
					action_motion.advance(
						StateScript.ActionState.IDLE,
						dynamic_delta,
						1.0,
						1.0,
						0.0,
						true,
						deg_to_rad(_head_rotation),
						ahoge_softness,
						_head_offset.x * facing
					)
					idle_vertices = action_motion.visual_vertices()
				else:
					idle_vertices = action_motion.soft_idle_vertices(deg_to_rad(_head_rotation), ahoge_softness)
			_mesh_node.set_action_pose(idle_vertices, 0.0, 0.0)
	last_safety_scale = 1.0
	last_presentation_weight = 0.0
	last_contact_error = INF
	queue_redraw()
