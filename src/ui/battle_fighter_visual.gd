extends "res://src/ui/fighter_visual.gd"

const ParryMotionScript := preload("res://src/ui/ahoge_parry_motion.gd")
const ActionMotionScript := preload("res://src/ui/ahoge_action_motion.gd")
const HeadMotionScript := preload("res://src/ui/battle_head_motion.gd")
const FOLLOW_THROUGH_PX: Vector2 = Vector2(42.0, 100.0)
const FOLLOW_EDGE_MARGIN: float = 12.0
const WHIP_REACH_EARLY_START_Q: float = 0.20
const WHIP_REACH_EARLY_FULL_Q: float = 0.42
const WHIP_REACH_EARLY_WEIGHT: float = 0.36
const WHIP_REACH_LATE_START_Q: float = 0.45
const WHIP_REACH_LATE_FULL_Q: float = 0.68

var arena_canvas_rect: Rect2 = Rect2()
var last_contact_error: float = INF
var last_safety_scale: float = 1.0
var last_presentation_weight: float = 0.0
var action_motion = ActionMotionScript.new()
var motion_softness_amount: float = 1.0
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
var _contact_pose_vertices: PackedVector2Array = PackedVector2Array()
var _contact_motion_transform: Transform2D = Transform2D.IDENTITY
var _capture_contact_transform: bool = false
var _parry_entry_vertices: PackedVector2Array = PackedVector2Array()
var _parry_entry_centers: PackedVector2Array = PackedVector2Array()


func _ready() -> void:
	super._ready()
	_ahoge_rig.set_process(false)
	_mesh_node = find_child("AhogeDeformMesh", true, false)
	_motion_node = find_child("AhogeMotionRoot", true, false) as Node2D
	_cache_head_image()


func set_motion_softness_amount(value: float) -> bool:
	if not is_finite(value):
		return false
	motion_softness_amount = clampf(value, 0.0, 1.0)
	return true


func _state_softness_weight(action: int) -> float:
	match action:
		CombatantStateScript.ActionState.IDLE:
			return 1.0
		CombatantStateScript.ActionState.CHARGING:
			return 0.0
		CombatantStateScript.ActionState.WINDUP:
			return 0.45
		CombatantStateScript.ActionState.STRIKE, CombatantStateScript.ActionState.COOLDOWN:
			return 1.0
		_:
			return 0.0


func _process(delta: float) -> void:
	if combat_state == null or delta <= 0.0:
		return
	var next_state: int = int(combat_state.action_state)
	var previous_presentation_state: int = _presentation_state
	if next_state != _presentation_state:
		_recovery_head_from = _head_offset
		_head_entry_pose = Vector3(_head_offset.x * facing, _head_offset.y, _head_rotation * facing)
		if _motion_node != null:
			_entry_transform = _motion_node.transform
		if next_state == CombatantStateScript.ActionState.PARRY:
			_parry_blocks_old_contact = true
			_parry_entry_vertices = PackedVector2Array()
			_parry_entry_centers = PackedVector2Array()
			if _mesh_node != null and _mesh_node.configured:
				# PARRY開始の最初の1frameは、どの遷移元でも直前の実表示をそのまま保持する。
				_parry_entry_vertices = _mesh_node.current_vertices.duplicate()
				var width_points: int = int(_mesh_node.profile.WIDTH_POINTS)
				var current_centers: PackedVector2Array = ParryMotionScript.centers_of(
					_mesh_node.current_vertices,
					width_points
				)
				var rest_centers: PackedVector2Array = ParryMotionScript.centers_of(
					_mesh_node.profile.rest_vertices,
					width_points
				)
				var current_length: float = _centerline_length(current_centers)
				var rest_length: float = _centerline_length(rest_centers)
				if (
					previous_presentation_state == CombatantStateScript.ActionState.STRIKE
					and rest_length > 0.001
					and current_length > rest_length * 1.005
				):
					_parry_entry_centers = current_centers
		else:
			_parry_entry_vertices = PackedVector2Array()
			_parry_entry_centers = PackedVector2Array()
		if next_state in [CombatantStateScript.ActionState.CHARGING, CombatantStateScript.ActionState.WINDUP, CombatantStateScript.ActionState.STRIKE]:
			_parry_blocks_old_contact = false
			_force_contact = false
		if next_state == CombatantStateScript.ActionState.STRIKE:
			_contact_frozen = false
			_contact_pose_vertices = PackedVector2Array()
			_contact_motion_transform = Transform2D.IDENTITY
			_capture_contact_transform = false
		_presentation_state = next_state
	if not bool(combat_state.ahoge_available) or next_state == CombatantStateScript.ActionState.ROUND_LOCKED:
		_force_contact = false
		_contact_frozen = false
		_contact_pose_vertices = PackedVector2Array()
		_contact_motion_transform = Transform2D.IDENTITY
		_capture_contact_transform = false
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
	# NeckRangePreview / MotionPreview / 通常Battleで同じ柔らかさ設定を使用する。
	# 溜め形そのものはActionMotionを正としつつ、頭部の後退・切り返しへ二次動作を重ねる。
	var motion_softness: float = motion_softness_amount * _state_softness_weight(next_state)
	action_motion.advance(
		next_state,
		delta,
		_phase_duration_for_state(next_state, charge),
		_max_charge_duration(),
		charge,
		bool(combat_state.ahoge_available),
		deg_to_rad(_head_rotation),
		motion_softness,
		_head_offset.x
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


func _blend_parry_entry_shape(
	entry_centers: PackedVector2Array,
	target_vertices: PackedVector2Array,
	weight: float
) -> PackedVector2Array:
	if _mesh_node == null or not _mesh_node.configured:
		return target_vertices.duplicate()
	var profile = _mesh_node.profile
	var width_points: int = int(profile.WIDTH_POINTS)
	var target_centers: PackedVector2Array = ParryMotionScript.centers_of(target_vertices, width_points)
	var rest_centers: PackedVector2Array = ParryMotionScript.centers_of(profile.rest_vertices, width_points)
	if (
		entry_centers.size() != target_centers.size()
		or target_centers.size() != rest_centers.size()
		or target_centers.size() < 3
	):
		return target_vertices.duplicate()

	var t: float = clampf(weight, 0.0, 1.0)
	if t >= 0.999:
		return target_vertices.duplicate()

	# center座標を直接lerpすると、向きの違うsegmentが途中でショートカットして
	# 弧長が基準長より短くなる。segment長と角度を補間してrootから再積算する。
	var segment_count: int = target_centers.size() - 1
	var blended_lengths: PackedFloat32Array = PackedFloat32Array()
	var blended_angles: PackedFloat32Array = PackedFloat32Array()
	var entry_angles: PackedFloat32Array = PackedFloat32Array()
	var target_angles: PackedFloat32Array = PackedFloat32Array()
	blended_lengths.resize(segment_count)
	blended_angles.resize(segment_count)
	entry_angles.resize(segment_count)
	target_angles.resize(segment_count)
	for segment in range(segment_count):
		var entry_edge: Vector2 = entry_centers[segment + 1] - entry_centers[segment]
		var target_edge: Vector2 = target_centers[segment + 1] - target_centers[segment]
		if entry_edge.length() <= 0.000001 or target_edge.length() <= 0.000001:
			return target_vertices.duplicate()
		entry_angles[segment] = entry_edge.angle()
		target_angles[segment] = target_edge.angle()
		if segment > 0:
			entry_angles[segment] = entry_angles[segment - 1] + wrapf(entry_angles[segment] - entry_angles[segment - 1], -PI, PI)
			target_angles[segment] = target_angles[segment - 1] + wrapf(target_angles[segment] - target_angles[segment - 1], -PI, PI)
		blended_lengths[segment] = lerpf(entry_edge.length(), target_edge.length(), t)
		blended_angles[segment] = lerpf(entry_angles[segment], target_angles[segment], t)

	# endpointのどちらよりも急な局所折れをENTRY途中に生成しない。
	for segment in range(1, segment_count):
		var entry_curve: float = absf(entry_angles[segment] - entry_angles[segment - 1])
		var target_curve: float = absf(target_angles[segment] - target_angles[segment - 1])
		var limit: float = maxf(entry_curve, target_curve) + 0.03
		blended_angles[segment] = clampf(
			blended_angles[segment],
			blended_angles[segment - 1] - limit,
			blended_angles[segment - 1] + limit
		)
	for segment in range(segment_count - 2, -1, -1):
		var entry_curve: float = absf(entry_angles[segment + 1] - entry_angles[segment])
		var target_curve: float = absf(target_angles[segment + 1] - target_angles[segment])
		var limit: float = maxf(entry_curve, target_curve) + 0.03
		blended_angles[segment] = clampf(
			blended_angles[segment],
			blended_angles[segment + 1] - limit,
			blended_angles[segment + 1] + limit
		)

	var blended_centers: PackedVector2Array = PackedVector2Array([Vector2.ZERO])
	for segment in range(segment_count):
		blended_centers.append(
			blended_centers[-1] + Vector2.from_angle(blended_angles[segment]) * blended_lengths[segment]
		)

	var result: PackedVector2Array = profile.rest_vertices.duplicate()
	result[0] = Vector2.ZERO
	var row_count: int = int((result.size() - 2) / width_points)
	for row in range(row_count):
		var center_index: int = row + 1
		var rest_prev: Vector2 = rest_centers[maxi(center_index - 1, 0)]
		var rest_next: Vector2 = rest_centers[mini(center_index + 1, rest_centers.size() - 1)]
		var posed_prev: Vector2 = blended_centers[maxi(center_index - 1, 0)]
		var posed_next: Vector2 = blended_centers[mini(center_index + 1, blended_centers.size() - 1)]
		var rest_tangent: Vector2 = rest_next - rest_prev
		var posed_tangent: Vector2 = posed_next - posed_prev
		if center_index == blended_centers.size() - 2:
			# ENTRY補間の最終断面もtipへ向かう最終edgeを基準にする。
			# 平均接線だと伸長を畳む途中でtip三角形が反転する。
			rest_tangent = rest_centers[-1] - rest_centers[-2]
			posed_tangent = blended_centers[-1] - blended_centers[-2]
		var turn: float = 0.0
		if rest_tangent.length() > 0.000001 and posed_tangent.length() > 0.000001:
			turn = wrapf(posed_tangent.angle() - rest_tangent.angle(), -PI, PI)
		for column in range(width_points):
			var index: int = 1 + row * width_points + column
			var relative: Vector2 = profile.rest_vertices[index] - rest_centers[center_index]
			result[index] = blended_centers[center_index] + relative.rotated(turn)
	result[-1] = blended_centers[-1]
	return result


func _centerline_length(points: PackedVector2Array) -> float:
	var total: float = 0.0
	for i in range(1, points.size()):
		total += points[i].distance_to(points[i - 1])
	return total


func _neutral_transform() -> Transform2D:
	var base_scale: float = maxf(0.21, get_viewport_rect().size.x / 5200.0)
	# 頭部の位置と傾きはroot anchorへ反映済み。全毛束を一体で回さない。
	# しなりはActionMotionへ任せ、接触補正後の歪みもここへ持ち越さない。
	return Transform2D(0.0, Vector2.ONE * base_scale, 0.0, Vector2.ZERO)


func _freeze_contact(target: Vector2) -> void:
	_contact_anchor_canvas = target
	_follow_end_canvas = _follow_end_for(target)
	_capture_contact_transform = true
	_contact_frozen = true


func _follow_end_for(target: Vector2) -> Vector2:
	var result: Vector2 = target + Vector2(FOLLOW_THROUGH_PX.x * facing, FOLLOW_THROUGH_PX.y)
	if arena_canvas_rect.has_area():
		var safe: Rect2 = arena_canvas_rect.grow(-FOLLOW_EDGE_MARGIN)
		result.x = clampf(result.x, safe.position.x, safe.end.x)
		result.y = clampf(result.y, safe.position.y, safe.end.y)
	return result


func _vertices_inside_arena_actual(candidate: Transform2D, vertices: PackedVector2Array) -> bool:
	if not arena_canvas_rect.has_area() or _motion_node == null or _mesh_node == null:
		return true
	var previous: Transform2D = _motion_node.transform
	_motion_node.transform = candidate
	var world: Transform2D = _mesh_node.global_transform
	var safe: Rect2 = arena_canvas_rect.grow(-0.25)
	var inside: bool = true
	for point in vertices:
		if not safe.has_point(world * point):
			inside = false
			break
	_motion_node.transform = previous
	return inside


func _follow_transform_inside_arena(
	vertices: PackedVector2Array,
	source_tip: Vector2,
	progress: float
) -> Transform2D:
	if _contact_pose_vertices.is_empty() or source_tip.length() <= 0.01:
		return _contact_motion_transform
	var desired_progress: float = clampf(progress, 0.0, 1.0)
	var desired_aim: Vector2 = _contact_anchor_canvas.lerp(_follow_end_canvas, desired_progress)
	var reference_tip: Vector2 = _contact_motion_transform * source_tip
	var desired: Transform2D = _project_tip(
		_contact_motion_transform,
		reference_tip,
		desired_aim,
		1.0,
		1.0
	)
	if _vertices_inside_arena_actual(desired, vertices):
		return desired

	var low: float = 0.0
	var high: float = desired_progress
	for _iteration in range(14):
		var middle: float = (low + high) * 0.5
		var aim: Vector2 = _contact_anchor_canvas.lerp(_follow_end_canvas, middle)
		var candidate: Transform2D = _project_tip(
			_contact_motion_transform,
			reference_tip,
			aim,
			1.0,
			1.0
		)
		if _vertices_inside_arena_actual(candidate, vertices):
			low = middle
		else:
			high = middle
	var limited_aim: Vector2 = _contact_anchor_canvas.lerp(_follow_end_canvas, low)
	return _project_tip(
		_contact_motion_transform,
		reference_tip,
		limited_aim,
		1.0,
		1.0
	)


func _fixed_axis_reach(base: Transform2D, axis_value: Vector2, ratio_value: float) -> Transform2D:
	if axis_value.length() <= 0.01 or not axis_value.is_finite() or not is_finite(ratio_value):
		return base
	var axis: Vector2 = axis_value.normalized()
	var ratio: float = clampf(ratio_value, 0.25, 3.0)
	var stretch: Transform2D = Transform2D(
		Vector2.RIGHT + axis * ((ratio - 1.0) * axis.x),
		Vector2.DOWN + axis * ((ratio - 1.0) * axis.y),
		Vector2.ZERO
	)
	return stretch * base


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
	var pose_vertices: PackedVector2Array = action_motion.visual_vertices()
	var active_q: float = 0.0
	var active_reach_ratio: float = 1.0
	var active_reach_axis: Vector2 = Vector2.RIGHT
	if _presentation_state == CombatantStateScript.ActionState.PARRY and not _parry_entry_vertices.is_empty():
		var parry_join: float = smoothstep(0.0, ParryMotionScript.ENTRY_SECONDS, action_motion.elapsed)
		if parry_join <= 0.001:
			pose_vertices = _parry_entry_vertices.duplicate()
		elif not _parry_entry_centers.is_empty():
			pose_vertices = _blend_parry_entry_shape(_parry_entry_centers, pose_vertices, parry_join)
		else:
			# 通常PARRY/WINDUP等は1frame保持後に従来PARRYへ戻す。
			_parry_entry_vertices = PackedVector2Array()
		if parry_join >= 0.999:
			_parry_entry_vertices = PackedVector2Array()
			_parry_entry_centers = PackedVector2Array()
	if _presentation_state == CombatantStateScript.ActionState.STRIKE and not confirmed:
		var active_contact_seconds: float = action_motion.duration * action_motion.contact_ratio
		active_q = action_motion.elapsed / maxf(active_contact_seconds, 0.001)
		var active_target_canvas: Vector2 = _contact_anchor_canvas if _contact_frozen else target_canvas
		# Active Strikeのcenterline座標系はMotionRootのneutral transformより内側。
		# q=1でtipを目標へ一致させるため、方向だけでなく距離もmesh-localへ変換する。
		var active_base: Transform2D = _neutral_transform()
		var active_target_local: Vector2 = active_base.affine_inverse() * _ahoge_rig.to_local(active_target_canvas)
		var active_charge: float = _visual_charge_ratio()
		pose_vertices = action_motion.active_strike_vertices(active_target_local, active_q, active_charge)
		var final_active_vertices: PackedVector2Array = action_motion.active_strike_vertices(active_target_local, 1.0, active_charge)
		if not final_active_vertices.is_empty() and final_active_vertices[-1].length() > 0.01:
			active_reach_ratio = clampf(active_target_local.length() / final_active_vertices[-1].length(), 0.25, 3.0)
			active_reach_axis = active_target_local.normalized()
	var frozen_tail_seconds: float = action_motion.follow_seconds()
	var use_frozen_follow_pose: bool = (
		_contact_frozen
		and not _capture_contact_transform
		and frozen_tail_seconds >= 0.0
		and frozen_tail_seconds < ActionMotionScript.FOLLOW_SECONDS - 0.000001
		and not _contact_pose_vertices.is_empty()
	)
	if use_frozen_follow_pose:
		pose_vertices = _contact_pose_vertices.duplicate()
	_mesh_node.set_action_pose(pose_vertices, action_motion.straighten, action_motion.sweep)
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
			# 接触後は接触frameの実メッシュとTransformを基準にし、
			# 相手を追尾せず、画面内に収まる最大位置まで下方向へ振り抜く。
			if (
				tail_seconds < ActionMotionScript.FOLLOW_SECONDS - 0.000001
				and not _contact_pose_vertices.is_empty()
				and not _capture_contact_transform
			):
				base = _follow_transform_inside_arena(vertices, source_tip, action_motion.follow_progress())
			else:
				var aim: Vector2 = _contact_anchor_canvas.lerp(_follow_end_canvas, action_motion.follow_progress())
				base = _project_tip(base, base * source_tip, aim, 1.0, 1.0)
		else:
			if confirmed:
				# 確定Hitの再提示は攻撃速度を進めるframeではない。
				# 過去のHit位置へ正確に戻すため、この経路だけ完全投影を許可する。
				base = _project_tip(base, base * source_tip, target_canvas, 1.0, 1.0)
			else:
				# q=1のActive形状から求めた最終reach倍率を早い区間で確定する。
				# terminal snap開始前に倍率変化を終え、接触直前の中央同時加速を防ぐ。
				var early_reach: float = WHIP_REACH_EARLY_WEIGHT * smoothstep(
					WHIP_REACH_EARLY_START_Q,
					WHIP_REACH_EARLY_FULL_Q,
					q
				)
				var late_reach: float = (1.0 - WHIP_REACH_EARLY_WEIGHT) * smoothstep(
					WHIP_REACH_LATE_START_Q,
					WHIP_REACH_LATE_FULL_Q,
					q
				)
				var reach_progress: float = clampf(early_reach + late_reach, 0.0, 1.0)
				var reach_ratio: float = lerpf(1.0, active_reach_ratio, reach_progress)
				base = _fixed_axis_reach(base, active_reach_axis, reach_ratio)
	elif _presentation_state == CombatantStateScript.ActionState.PARRY:
		base = _entry_transform.interpolate_with(base, smoothstep(0.0, ParryMotionScript.ENTRY_SECONDS, action_motion.elapsed))
	elif _presentation_state not in [CombatantStateScript.ActionState.CHARGING, CombatantStateScript.ActionState.WINDUP]:
		base = _entry_transform.interpolate_with(base, smoothstep(0.0, 0.20, action_motion.elapsed))
	var constrained_follow: bool = (
		_contact_frozen
		and not _capture_contact_transform
		and tail_seconds >= 0.0
		and tail_seconds < ActionMotionScript.FOLLOW_SECONDS - 0.000001
		and not _contact_pose_vertices.is_empty()
	)
	if constrained_follow:
		last_safety_scale = 1.0
		_motion_node.transform = base
	else:
		_motion_node.transform = _fit_to_arena(base, vertices)
	if _capture_contact_transform:
		_contact_motion_transform = _motion_node.transform
		_contact_pose_vertices = _mesh_node.current_vertices.duplicate()
		_capture_contact_transform = false
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
