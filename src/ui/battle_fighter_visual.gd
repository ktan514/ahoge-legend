extends "res://src/ui/fighter_visual.gd"

const ParryMotionScript := preload("res://src/ui/ahoge_parry_motion.gd")
const ActionMotionScript := preload("res://src/ui/ahoge_action_motion.gd")
const FOLLOW_THROUGH_PX: Vector2 = Vector2(30.0, 22.0)
const WHIP_NORMAL_REACH_POWER: float = 4.0
const WHIP_CHARGED_REACH_POWER: float = 6.0
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
var _entry_transform: Transform2D = Transform2D.IDENTITY
var _base_motion_transform: Transform2D = Transform2D.IDENTITY
var _mesh_node
var _motion_node: Node2D
var _force_contact: bool = false
var _parry_blocks_old_contact: bool = false
var _contact_frozen: bool = false
var _contact_anchor_canvas: Vector2 = Vector2.ZERO


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
	# 小さい頭部モーションを先に更新してから、同じframeの毛束形状へ渡す。
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
	action_motion.advance(next_state, delta, _phase_duration_for_state(next_state, charge), _max_charge_duration(), charge, bool(combat_state.ahoge_available))


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
	var target: Vector2 = super._prototype_head_target(charge_ratio)
	if _asset_mode and int(combat_state.action_state) == CombatantStateScript.ActionState.PARRY:
		var duration: float = _phase_duration_for_state(CombatantStateScript.ActionState.PARRY, charge_ratio)
		var join: float = smoothstep(0.0, ParryMotionScript.ENTRY_SECONDS, _visual_action_age)
		var sweep: float = ParryMotionScript.sweep_at(_visual_action_age, duration)
		var cue: Vector2 = Vector2(-facing * sweep, sweep * 0.5) * ParryMotionScript.HEAD_MOVE_PX
		target = _recovery_head_from.lerp(cue, join)
	var forward: float = target.x * facing
	match int(combat_state.action_state):
		CombatantStateScript.ActionState.CHARGING:
			forward *= 28.0 / (78.0 * 1.15)
		CombatantStateScript.ActionState.WINDUP:
			forward *= 36.0 / (82.0 + 72.0 * charge_ratio)
		CombatantStateScript.ActionState.STRIKE:
			forward *= (28.0 / (86.0 + 74.0 * charge_ratio)) if forward >= 0.0 else (36.0 / (82.0 + 72.0 * charge_ratio))
		CombatantStateScript.ActionState.COOLDOWN:
			var recovered: Vector2 = _recovery_head_from.lerp(Vector2.ZERO, smoothstep(0.0, 0.18, _visual_action_age))
			forward = recovered.x * facing
	target.x = clampf(forward, -36.0, 28.0) * facing
	_cache_head_image()
	if _asset_mode and arena_canvas_rect.has_area() and _head_used.has_area():
		var local_bounds: Rect2 = get_global_transform().affine_inverse() * arena_canvas_rect
		var angle: float = -facing * (_prototype_charge_lean(charge_ratio) + _prototype_cooldown_lean(charge_ratio)) * 0.035
		var extent: Rect2 = _head_local_extent(angle)
		var low: float = local_bounds.position.x + 10.0 - size.x * 0.5 - extent.position.x
		var high: float = local_bounds.end.x - 10.0 - size.x * 0.5 - extent.end.x
		if low <= high:
			target.x = clampf(target.x, low, high)
	return target


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
	return Transform2D(0.0, Vector2.ONE * base_scale, 0.0, Vector2.ZERO)


func present_toward(target_canvas: Vector2) -> void:
	last_contact_error = INF
	last_presentation_weight = 0.0
	last_safety_scale = 1.0
	if not _asset_mode or _mesh_node == null or not _mesh_node.configured or not _ahoge_rig.visible or not action_motion.configured:
		return
	var confirmed: bool = _force_contact and action_motion.force_contact()
	_force_contact = false
	_mesh_node.set_action_pose(action_motion.vertices, action_motion.straighten, action_motion.sweep)
	last_presentation_weight = float(action_motion.straighten)
	var vertices: PackedVector2Array = _mesh_node.current_vertices
	var base: Transform2D = _neutral_transform()
	_base_motion_transform = base
	var source_tip: Vector2 = vertices[-1]
	if action_motion.blocked:
		_motion_node.transform = _fit_to_arena(base, vertices)
		return
	if _presentation_state == CombatantStateScript.ActionState.STRIKE or confirmed:
		var contact_seconds: float = action_motion.duration * action_motion.contact_ratio
		var q: float = 1.0 if confirmed else action_motion.elapsed / maxf(contact_seconds, 0.001)
		if q >= 1.0 and not _contact_frozen:
			_contact_anchor_canvas = target_canvas
			_contact_frozen = true
		var aim: Vector2 = target_canvas
		if q > 1.0 and not confirmed:
			var after: float = smoothstep(contact_seconds, action_motion.duration, action_motion.elapsed)
			aim = _contact_anchor_canvas + Vector2(FOLLOW_THROUGH_PX.x * facing, FOLLOW_THROUGH_PX.y) * after
		var target_local: Vector2 = _ahoge_rig.to_local(aim)
		# 接触時の形を固定した基準とし、現在形のしなりをそのまま描く。
		var contact_vertices: PackedVector2Array = action_motion.vertices_from_angles(action_motion.straight_angles)
		var contact_tip: Vector2 = base * contact_vertices[-1]
		if contact_tip.length() > 0.01 and target_local.length() > 0.01:
			var axis: Vector2 = contact_tip.normalized()
			var power: float = lerpf(WHIP_NORMAL_REACH_POWER, WHIP_CHARGED_REACH_POWER, _visual_charge_ratio())
			var reach_weight: float = pow(clampf(q, 0.0, 1.0), power)
			var turn_weight: float = smoothstep(0.0, WHIP_TURN_END, q)
			var ratio: float = lerpf(1.0, target_local.length() / contact_tip.length(), reach_weight)
			var stretch: Transform2D = Transform2D(Vector2.RIGHT + axis * ((ratio - 1.0) * axis.x), Vector2.DOWN + axis * ((ratio - 1.0) * axis.y), Vector2.ZERO)
			var turn: float = wrapf(target_local.angle() - contact_tip.angle(), -PI, PI) * turn_weight
			base = Transform2D(turn, Vector2.ZERO) * stretch * base
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
