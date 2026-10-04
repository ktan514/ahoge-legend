extends "res://src/ui/fighter_visual.gd"

const ParryMotionScript := preload("res://src/ui/ahoge_parry_motion.gd")

# Battle専用。固定メッシュ・形状キーと基準の二次運動は親実装へ委譲する。
var arena_canvas_rect: Rect2 = Rect2()
var last_contact_error: float = INF
var last_safety_scale: float = 1.0
var last_presentation_weight: float = 0.0
var _head_image: Image
var _head_image_texture: Texture2D
var _head_used: Rect2 = Rect2()
var _head_contact_px: Vector2 = Vector2.ZERO
var _presentation_state: int = -1
var _recovery_head_from: Vector2 = Vector2.ZERO
var _confirmed_age: float = 100.0
var _interrupt_age: float = 100.0
var _interrupt_from: float = 0.0
var _base_motion_transform: Transform2D = Transform2D.IDENTITY
var _mesh_node
var _motion_node: Node2D
var _parry_from_straighten: float = 0.0
var _parry_from_transform: Transform2D = Transform2D.IDENTITY
var _parry_tail_age: float = 100.0
var _parry_tail_straighten: float = 0.0
var _parry_tail_sweep: float = 0.0
var _parry_tail_transform: Transform2D = Transform2D.IDENTITY
var _parry_hidden: bool = false
var _parry_blocks_old_contact: bool = false


func _ready() -> void:
	super._ready()
	# 頭部とアホ毛を同じ時計で一度ずつ更新する。対戦ではdirectorが呼び出す。
	_ahoge_rig.set_process(false)
	_mesh_node = find_child("AhogeDeformMesh", true, false)
	_motion_node = find_child("AhogeMotionRoot", true, false) as Node2D
	_cache_head_image()


func _process(delta: float) -> void:
	if combat_state == null or delta <= 0.0:
		return
	var next_state: int = int(combat_state.action_state)
	var changed: bool = next_state != _presentation_state
	if changed:
		if _mesh_node != null and _mesh_node.configured:
			if next_state == CombatantStateScript.ActionState.PARRY:
				# 補正済みの実表示を保存。攻撃の途中から中立C字へ飛ばさない。
				_parry_from_straighten = float(_mesh_node.straighten)
				_parry_from_transform = _motion_node.transform
				_parry_tail_age = 100.0
				_parry_hidden = not bool(combat_state.ahoge_available)
				_parry_blocks_old_contact = true
			elif _presentation_state == CombatantStateScript.ActionState.PARRY:
				_parry_tail_age = 0.0
				_parry_tail_straighten = float(_mesh_node.straighten)
				_parry_tail_sweep = float(_mesh_node.parry_sweep)
				_parry_tail_transform = _motion_node.transform
		if next_state in [CombatantStateScript.ActionState.CHARGING, CombatantStateScript.ActionState.WINDUP, CombatantStateScript.ActionState.STRIKE]:
			_parry_blocks_old_contact = false
		_recovery_head_from = _head_offset
		_presentation_state = next_state
		_interrupt_age = 0.0
		_interrupt_from = 0.0
		if _presentation_state in [CombatantStateScript.ActionState.COOLDOWN, CombatantStateScript.ActionState.DODGE, CombatantStateScript.ActionState.STAGGER]:
			_interrupt_from = last_presentation_weight
		if _presentation_state != CombatantStateScript.ActionState.COOLDOWN:
			_confirmed_age = 100.0
	else:
		_parry_tail_age += delta
	if not bool(combat_state.ahoge_available) or _presentation_state == CombatantStateScript.ActionState.ROUND_LOCKED:
		_confirmed_age = 100.0
		_interrupt_from = 0.0
		_parry_hidden = true
		_parry_tail_age = 100.0
		_parry_from_straighten = 0.0
	_confirmed_age += delta
	_interrupt_age += delta
	super._process(delta)
	if _asset_mode:
		_ahoge_rig.call("_process", delta)
		_base_motion_transform = _motion_node.transform


func _cache_head_image() -> void:
	if _head_sprite == null or _head_sprite.texture == null:
		return
	if _head_image_texture == _head_sprite.texture:
		return
	_head_image_texture = _head_sprite.texture
	_head_image = _head_image_texture.get_image()
	if _head_image == null or _head_image.is_empty():
		return
	if _head_image.is_compressed() and _head_image.decompress() != OK:
		_head_image = null
		return
	_head_used = Rect2(_head_image.get_used_rect())
	# 素材の実輪郭。左右はHeadSpriteの反転で処理する。
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
	if _asset_mode and _mesh_node != null and _mesh_node.configured and int(combat_state.action_state) == CombatantStateScript.ActionState.PARRY:
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
	var basis: Transform2D = Transform2D(angle, _head_sprite.scale, 0.0, Vector2.ZERO)
	return basis * local


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
	if int(combat_state.action_state) not in [CombatantStateScript.ActionState.STRIKE, CombatantStateScript.ActionState.COOLDOWN]:
		return false
	_confirmed_age = 0.0
	return true


func present_toward(target_canvas: Vector2) -> void:
	last_contact_error = INF
	last_presentation_weight = 0.0
	last_safety_scale = 1.0
	if not _asset_mode or _mesh_node == null or not _mesh_node.configured or not _ahoge_rig.visible:
		return
	if _presentation_state == CombatantStateScript.ActionState.PARRY:
		_present_local_parry()
		return
	var amount: float = float(_ahoge_rig.debug_straighten())
	amount = maxf(amount, _interrupt_from * (1.0 - smoothstep(0.0, 0.16, _interrupt_age)))
	if _confirmed_age < 0.16:
		amount = maxf(amount, 1.0 - smoothstep(0.05, 0.16, _confirmed_age))
	var tail: float = smoothstep(0.0, ParryMotionScript.EXIT_SECONDS, _parry_tail_age)
	if tail < 1.0:
		amount = lerpf(_parry_tail_straighten, amount, tail)
		_mesh_node.set_parry_pose(amount, _parry_tail_sweep * (1.0 - tail))
	else:
		_mesh_node.set_straighten(amount)
	last_presentation_weight = amount
	var vertices: PackedVector2Array = _mesh_node.current_vertices
	if vertices.is_empty():
		return
	# 同じframeの再提示でも補正を累積しない。
	var base: Transform2D = _base_motion_transform
	var source_tip: Vector2 = vertices[-1]
	var base_tip: Vector2 = base * source_tip
	var target_local: Vector2 = _ahoge_rig.to_local(target_canvas)
	if amount > 0.0 and base_tip.length() > 0.01 and target_local.length() > 0.01:
		var axis: Vector2 = base_tip.normalized()
		var ratio: float = lerpf(1.0, target_local.length() / base_tip.length(), amount)
		var stretch: Transform2D = Transform2D(
			Vector2.RIGHT + axis * ((ratio - 1.0) * axis.x),
			Vector2.DOWN + axis * ((ratio - 1.0) * axis.y),
			Vector2.ZERO
		)
		var turn: float = wrapf(target_local.angle() - base_tip.angle(), -PI, PI) * amount
		base = Transform2D(turn, Vector2.ZERO) * stretch * base
	if tail < 1.0:
		base = _parry_tail_transform.interpolate_with(base, tail)
	_motion_node.transform = _fit_to_arena(base, vertices)
	last_contact_error = _mesh_node.to_global(source_tip).distance_to(target_canvas)


func _present_local_parry() -> void:
	var join: float = smoothstep(0.0, ParryMotionScript.ENTRY_SECONDS, _visual_action_age)
	var amount: float = _parry_from_straighten * (1.0 - join)
	var duration: float = _phase_duration_for_state(CombatantStateScript.ActionState.PARRY, _visual_charge_ratio())
	var sweep: float = ParryMotionScript.sweep_at(_visual_action_age, duration) * join
	var base: Transform2D = _parry_from_transform.interpolate_with(_base_motion_transform, join)
	if _parry_hidden:
		amount = 0.0
		sweep = 0.0
		base = _base_motion_transform
	_mesh_node.set_parry_pose(amount, sweep)
	_motion_node.transform = _fit_to_arena(base, _mesh_node.current_vertices)
	# 相手頭部のtargetは使わず、長距離の接触補正をパリィへ持ち込まない。


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
