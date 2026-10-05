extends "res://src/ui/fighter_visual.gd"

const ParryMotionScript := preload("res://src/ui/ahoge_parry_motion.gd")
const ActionMotionScript := preload("res://src/ui/ahoge_action_motion.gd")
const HeadMotionScript := preload("res://src/ui/battle_head_motion.gd")
const FOLLOW_THROUGH_PX: Vector2 = Vector2(42.0, 100.0)
const FOLLOW_EDGE_MARGIN: float = 12.0
const WHIP_NORMAL_REACH_POWER: float = 1.8
const WHIP_CHARGED_REACH_POWER: float = 2.8
const WHIP_TURN_END: float = 0.95

var arena_canvas_rect: Rect2 = Rect2()
var last_contact_error: float = INF
var last_safety_scale: float = 1.0
var last_presentation_weight: float = 0.0
var action_motion = ActionMotionScript.new()
var _head_image: Image
var _head_image_texture: Texture2D
var _head_used: Rect2 = Rect2()
var _head_contact_px: Vector2 = Vector2.ZERO
var _presentation_state: int = -1
var _recovery_head_from: Vector2 = Vector2.ZERO
var _head_entry_pose: Vector3 = Vector3.ZERO
var _requested_head_rotation: float = 0.0
var _entry_transform: Transform2D = Transform2D.IDENTITY
var _base_motion_transform: Transform2D = Transform2D.IDENTITY
var _mesh_node
var _motion_node: Node2D
var _force_contact: bool = false
var _parry_blocks_old_contact: bool = false
var _contact_frozen: bool = false
var _contact_anchor_canvas: Vector2 = Vector2.ZERO
var _follow_end_canvas: Vector2 = Vector2.ZERO


func _ready() -> void:
	super._ready()
	_ahoge_rig.set_process(false)
	_mesh_node = find_child("AhogeDeformMesh", true, false)
	_motion_node = find_child("AhogeMotionRoot", true, false) as Node2D
	_cache_head_image()


func _process(delta: float) -> void:
	if combat_state == null or delta <= 0.0:
		return
	var next_state: int = int(combat_state.action_state)
	if next_state != _presentation_state:
		_recovery_head_from = _head_offset
		_head_entry_pose = Vector3(_head_offset.x * facing, _head_offset.y, _head_rotation * facing)
		if _motion_node != null:
			_entry_transform = _motion_node.transform
		if next_state == CombatantStateScript.ActionState.PARRY:
			_parry_blocks_old_contact = true
		if next_state in [CombatantStateScript.ActionState.CHARGING, CombatantStateScript.ActionState.WINDUP, CombatantStateScript.ActionState.STRIKE]:
			_parry_blocks_old_contact = false
			_force_contact = false
		if next_state == CombatantStateScript.ActionState.STRIKE:
			_contact_frozen = false
		_presentation_state = next_state
	if not bool(combat_state.ahoge_available) or next_state == CombatantStateScript.ActionState.ROUND_LOCKED:
		_force_contact = false
		_contact_frozen = false
		_parry_blocks_old_contact = true
	# 頭部を先に更新し、同じ時計で根元から毛先へしなりを渡す。
	super._process(delta)
	if not _asset_mode:
		return
	_ahoge_rig.call("_process", delta)
	if _mesh_node == null or not _mesh_node.configured:
		return
	if not action_motion.configured:
		action_motion.configure(_mesh_node.profile)
	var charge: float = _visual_charge_ratio()
	action_motion.contact_ratio = float(combat_state.config.attack_contact_ratio) if combat_state.config != null else 0.70
	# 溜め/予備動作は専用の後方アーチを正とし、二重変形しない。
	# 柔軟層は直前姿勢を記録し続けるため、STRIKE開始frameの切り返し速度は保持される。
	var motion_softness: float = 1.0 if next_state in [
		CombatantStateScript.ActionState.IDLE,
		CombatantStateScript.ActionState.STRIKE,
		CombatantStateScript.ActionState.COOLDOWN
	] else 0.0
	action_motion.advance(
		next_state,
		delta,
		_phase_duration_for_state(next_state, charge),
		_max_charge_duration(),
		charge,
		bool(combat_state.ahoge_available),
		deg_to_rad(_head_rotation),
		motion_softness,
		_head_offset.x * facing
	)


func _cache_head_image() -> void:
	if _head_sprite == null or _head_sprite.texture == null or _head_image_texture == _head_sprite.texture:
		return
	_head_image_texture = _head_sprite.texture
	_head_image = _head_image_texture.get_image()
	if _head_image == null or _head_image.is_empty():
		return
	if _head_image.is_compressed() and _head_image.decompress() != OK:
		_head_image = null
		return
	_head_used = Rect2(_head_image.get_used_rect())
	var x: int = clampi(int(_head_used.position.x + _head_used.size.x * 0.73), 0, _head_image.get_width() - 1)
	for y in range(int(_head_used.position.y), int(_head_used.end.y)):
		if _head_image.get_pixel(x, y).a >= 0.5:
			_head_contact_px = Vector2(x, y + 2) - _head_image_texture.get_size() * 0.5
			break


func contact_canvas_position() -> Vector2:
	_cache_head_image()
	if _asset_mode and _head_image != null:
		return _head_sprite.to_global(_head_contact_px)
	var radius: float = minf(122.0, maxf(92.0, size.x * 0.28))
	var center: Vector2 = Vector2(size.x * 0.5, size.y + 44.0) + _head_offset
	return get_global_transform() * (center + Vector2(facing * radius * 0.48, -radius * sqrt(1.0 - 0.48 * 0.48)))


func _prototype_head_target(charge_ratio: float) -> Vector2:
	var action: int = int(combat_state.action_state)
	if not _asset_mode:
		# SHORT仮描画の既存動作と画面内の移動範囲は変えない。
		var fallback: Vector2 = super._prototype_head_target(charge_ratio)
		var forward: float = fallback.x * facing
		match action:
			CombatantStateScript.ActionState.CHARGING:
				forward *= 28.0 / (78.0 * 1.15)
			CombatantStateScript.ActionState.WINDUP:
				forward *= 36.0 / (82.0 + 72.0 * charge_ratio)
			CombatantStateScript.ActionState.STRIKE:
				forward *= (28.0 / (86.0 + 74.0 * charge_ratio)) if forward >= 0.0 else (36.0 / (82.0 + 72.0 * charge_ratio))
			CombatantStateScript.ActionState.COOLDOWN:
				forward = _recovery_head_from.lerp(Vector2.ZERO, smoothstep(0.0, 0.18, _visual_action_age)).x * facing
		fallback.x = clampf(forward, -36.0, 28.0) * facing
		return fallback
	var pose: Vector3 = HeadMotionScript.sample(action, _visual_action_age, _phase_duration_for_state(action, charge_ratio), _max_charge_duration(), _head_entry_pose)
	_requested_head_rotation = pose.z * facing
	var target: Vector2 = Vector2(pose.x * facing, pose.y)
	if action == CombatantStateScript.ActionState.IDLE:
		var breathe: float = sin(_breath_phase * 2.0 + (0.0 if facing > 0.0 else 0.7)) * 4.0 + sin(_breath_phase * 0.8) * 1.6
		target.y += breathe * smoothstep(0.0, HeadMotionScript.RECOVER_SECONDS, _visual_action_age)
	_cache_head_image()
	if arena_canvas_rect.has_area() and _head_used.has_area():
		var local_bounds: Rect2 = get_global_transform().affine_inverse() * arena_canvas_rect
		# 今回描く傾きで外接範囲を評価する。旧charge角で判定しない。
		var extent: Rect2 = _head_local_extent(deg_to_rad(_requested_head_rotation))
		var low: float = local_bounds.position.x + 10.0 - size.x * 0.5 - extent.position.x
		var high: float = local_bounds.end.x - 10.0 - size.x * 0.5 - extent.end.x
		if low <= high:
			target.x = clampf(target.x, low, high)
	return target


func _update_asset_pose() -> void:
	if _asset_mode:
		# 親の旧charge専用角度ではなく、三動作の頭部角度を描画へ渡す。
		_head_rotation = _requested_head_rotation
	super._update_asset_pose()


func _head_local_extent(angle: float) -> Rect2:
	var local: Rect2 = Rect2(_head_used.position - _head_image_texture.get_size() * 0.5, _head_used.size)
	return Transform2D(angle, _head_sprite.scale, 0.0, Vector2.ZERO) * local


func head_canvas_bounds() -> Rect2:
	_cache_head_image()
	if _asset_mode and _head_image != null:
		return _head_sprite.global_transform * Rect2(_head_used.position - _head_image_texture.get_size() * 0.5, _head_used.size)
	var radius: float = minf(122.0, maxf(92.0, size.x * 0.28)) + 5.0
	var center: Vector2 = Vector2(size.x * 0.5, size.y + 44.0) + _head_offset
	return get_global_transform() * Rect2(center - Vector2.ONE * radius, Vector2.ONE * radius * 2.0)


func confirm_contact() -> bool:
	if not _asset_mode or not bool(combat_state.ahoge_available) or _parry_blocks_old_contact:
		return false
	if not action_motion.configured or action_motion.blocked:
		return false
	if int(combat_state.action_state) not in [CombatantStateScript.ActionState.STRIKE, CombatantStateScript.ActionState.COOLDOWN]:
		return false
	_force_contact = true
	return true


func _neutral_transform() -> Transform2D:
	var base_scale: float = maxf(0.21, get_viewport_rect().size.x / 5200.0)
	# 頭部の位置と傾きはroot anchorへ反映済み。全毛束を一体で回さない。
	# しなりはActionMotionへ任せ、接触補正後の歪みもここへ持ち越さない。
	return Transform2D(0.0, Vector2.ONE * base_scale, 0.0, Vector2.ZERO)


func _freeze_contact(target: Vector2) -> void:
	_contact_anchor_canvas = target
	_follow_end_canvas = _follow_end_for(target)
	_contact_frozen = true


func _follow_end_for(target: Vector2) -> Vector2:
	var result: Vector2 = target + Vector2(FOLLOW_THROUGH_PX.x * facing, FOLLOW_THROUGH_PX.y)
	if arena_canvas_rect.has_area():
		var safe: Rect2 = arena_canvas_rect.grow(-FOLLOW_EDGE_MARGIN)
		result.x = clampf(result.x, safe.position.x, safe.end.x)
		result.y = clampf(result.y, safe.position.y, safe.end.y)
	return result


func _project_tip(base: Transform2D, reference_tip: Vector2, aim: Vector2, reach_weight: float, turn_weight: float) -> Transform2D:
	var target_local: Vector2 = _ahoge_rig.to_local(aim)
	if reference_tip.length() <= 0.01 or target_local.length() <= 0.01:
		return base
	var axis: Vector2 = reference_tip.normalized()
	var ratio: float = lerpf(1.0, target_local.length() / reference_tip.length(), reach_weight)
	var stretch: Transform2D = Transform2D(Vector2.RIGHT + axis * ((ratio - 1.0) * axis.x), Vector2.DOWN + axis * ((ratio - 1.0) * axis.y), Vector2.ZERO)
	var turn: float = wrapf(target_local.angle() - reference_tip.angle(), -PI, PI) * turn_weight
	return Transform2D(turn, Vector2.ZERO) * stretch * base


func present_toward(target_canvas: Vector2) -> void:
	last_contact_error = INF
	last_presentation_weight = 0.0
	last_safety_scale = 1.0
	if not _asset_mode or _mesh_node == null or not _mesh_node.configured or not _ahoge_rig.visible or not action_motion.configured:
		return
	var confirmed: bool = _force_contact and action_motion.force_contact()
	_force_contact = false
	_mesh_node.set_action_pose(action_motion.visual_vertices(), action_motion.straighten, action_motion.sweep)
	last_presentation_weight = float(action_motion.straighten)
	var vertices: PackedVector2Array = _mesh_node.current_vertices
	var base: Transform2D = _neutral_transform()
	_base_motion_transform = base
	var source_tip: Vector2 = vertices[-1]
	if action_motion.blocked:
		_motion_node.transform = _fit_to_arena(base, vertices)
		return
	var tail_seconds: float = action_motion.follow_seconds()
	var tail_in_cooldown: bool = _presentation_state == CombatantStateScript.ActionState.COOLDOWN and _contact_frozen and tail_seconds >= 0.0
	if _presentation_state == CombatantStateScript.ActionState.STRIKE or confirmed or tail_in_cooldown:
		var contact_seconds: float = action_motion.duration * action_motion.contact_ratio
		var q: float = 1.0 if confirmed or tail_in_cooldown else action_motion.elapsed / maxf(contact_seconds, 0.001)
		if confirmed or (q >= 1.0 and not _contact_frozen):
			_freeze_contact(target_canvas)
		if tail_in_cooldown and tail_seconds >= ActionMotionScript.FOLLOW_SECONDS and not confirmed:
			# 振り抜き終点を基準としてから復帰する。STRIKE終了姿勢へ巻き戻さない。
			var final_vertices: PackedVector2Array = action_motion.visual_vertices_from_angles(action_motion.final_follow_angles())
			var end_transform: Transform2D = _project_tip(base, base * final_vertices[-1], _follow_end_canvas, 1.0, 1.0)
			base = end_transform.interpolate_with(base, smoothstep(0.0, 0.20, action_motion.recovery_seconds()))
		elif tail_seconds >= 0.0 and _contact_frozen and not confirmed:
			# 接触後は実毛先を下向き軌道へ合わせる。相手の移動は参照しない。
			var aim: Vector2 = _contact_anchor_canvas.lerp(_follow_end_canvas, action_motion.follow_progress())
			base = _project_tip(base, base * source_tip, aim, 1.0, 1.0)
		else:
			var contact_vertices: PackedVector2Array = action_motion.visual_vertices_from_angles(action_motion.straight_angles)
			var power: float = lerpf(WHIP_NORMAL_REACH_POWER, WHIP_CHARGED_REACH_POWER, _visual_charge_ratio())
			# 接触前から下向きの速度を持たせ、接触後の減速曲線へつなぐ。
			var pass_vector: Vector2 = _follow_end_for(target_canvas) - target_canvas
			var approach: Vector2 = target_canvas - pass_vector * (2.0 * contact_seconds / (PI * ActionMotionScript.FOLLOW_SECONDS)) * sin(PI * clampf(q, 0.0, 1.0))
			var reach_weight: float = pow(smoothstep(0.0, 0.90, q), power)
			base = _project_tip(base, base * contact_vertices[-1], approach, reach_weight, smoothstep(0.0, WHIP_TURN_END, q))
	elif _presentation_state == CombatantStateScript.ActionState.PARRY:
		base = _entry_transform.interpolate_with(base, smoothstep(0.0, ParryMotionScript.ENTRY_SECONDS, action_motion.elapsed))
	elif _presentation_state not in [CombatantStateScript.ActionState.CHARGING, CombatantStateScript.ActionState.WINDUP]:
		base = _entry_transform.interpolate_with(base, smoothstep(0.0, 0.20, action_motion.elapsed))
	_motion_node.transform = _fit_to_arena(base, vertices)
	if confirmed:
		_entry_transform = _motion_node.transform
	last_contact_error = _mesh_node.to_global(source_tip).distance_to(target_canvas)


func _fit_to_arena(base: Transform2D, vertices: PackedVector2Array) -> Transform2D:
	if arena_canvas_rect.has_area():
		var safe: Rect2 = arena_canvas_rect.grow(-2.0)
		var root_canvas: Vector2 = _ahoge_rig.global_position
		var world: Transform2D = _ahoge_rig.global_transform * base
		var factor: float = 1.0
		for point in vertices:
			var offset: Vector2 = world * point - root_canvas
			if offset.x < -0.001:
				factor = minf(factor, (safe.position.x - root_canvas.x) / offset.x)
			elif offset.x > 0.001:
				factor = minf(factor, (safe.end.x - root_canvas.x) / offset.x)
			if offset.y < -0.001:
				factor = minf(factor, (safe.position.y - root_canvas.y) / offset.y)
			elif offset.y > 0.001:
				factor = minf(factor, (safe.end.y - root_canvas.y) / offset.y)
		last_safety_scale = clampf(factor, 0.0, 1.0)
		base.x *= last_safety_scale
		base.y *= last_safety_scale
	return base


func mesh_canvas_vertices() -> PackedVector2Array:
	if _mesh_node == null or not _mesh_node.configured or not _ahoge_rig.visible:
		return PackedVector2Array()
	return _mesh_node.global_transform * _mesh_node.current_vertices


func rendered_straighten() -> float:
	return 0.0 if _mesh_node == null else float(_mesh_node.straighten)
