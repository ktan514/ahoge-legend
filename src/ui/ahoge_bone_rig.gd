extends Node2D

const CombatantStateScript := preload("res://src/domain/combatant_state.gd")

@export var display_height: float = 248.0
@export var bone_count: int = 7
@export var mesh_sections: int = 28
@export var alpha_threshold: float = 0.04
@export var alpha_search_radius: int = 10
@export var uv_padding: int = 2
@export var min_half_width: float = 1.5

@export var root_spring: float = 56.0
@export var tip_spring: float = 30.0
@export var root_damping: float = 10.0
@export var tip_damping: float = 5.5
@export var idle_sway_degrees: float = 2.4
@export var strike_total_turn_degrees: float = 108.0
@export var charge_total_turn_degrees: float = -34.0
@export var windup_total_turn_degrees: float = -58.0
@export var strike_length_scale: float = 2.25
@export var stretch_spring: float = 78.0
@export var stretch_damping: float = 13.0
@export var strike_propagation_seconds: float = 0.09

var _texture: Texture2D
var _polygon: Polygon2D
var _skeleton: Skeleton2D
var _bones: Array[Bone2D] = []

var _facing: float = 1.0
var _available: bool = true
var _head_velocity := Vector2.ZERO
var _head_acceleration := Vector2.ZERO
var _action_state: int = CombatantStateScript.ActionState.IDLE
var _action_age: float = 0.0
var _idle_phase: float = 0.0

var _bone_angles := PackedFloat32Array()
var _bone_angular_velocities := PackedFloat32Array()
var _rest_segment_length: float = 1.0
var _length_scale: float = 1.0
var _length_velocity: float = 0.0

var _source_center_offsets := PackedFloat32Array()
var _source_half_widths := PackedFloat32Array()
var _source_uv_left := PackedFloat32Array()
var _source_uv_right := PackedFloat32Array()
var _source_uv_y := PackedFloat32Array()


func _ready() -> void:
	_build_nodes()
	_resize_state()
	set_process(true)


func configure(texture_value: Texture2D, facing_value: float) -> void:
	_texture = texture_value
	_facing = 1.0 if facing_value >= 0.0 else -1.0
	scale = Vector2(_facing, 1.0)

	if _polygon != null:
		_polygon.texture = _texture

	_sample_source_profile()
	_build_skeleton()
	_build_skin_mesh()
	_reset_pose()


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


func kick(power: float = 1.0) -> void:
	if _bone_angular_velocities.is_empty():
		return
	for index in range(_bone_angular_velocities.size()):
		var t := float(index) / maxf(float(_bone_angular_velocities.size() - 1), 1.0)
		_bone_angular_velocities[index] += deg_to_rad(18.0) * power * pow(t, 1.7)


func _process(delta: float) -> void:
	if delta <= 0.0 or not _available or _texture == null or _bones.is_empty():
		return

	_action_age += delta
	_idle_phase += delta
	_simulate_bones(delta)
	_apply_pose()


func _build_nodes() -> void:
	_skeleton = Skeleton2D.new()
	_skeleton.name = "AhogeSkeleton2D"
	add_child(_skeleton)

	_polygon = Polygon2D.new()
	_polygon.name = "AhogeSkin"
	_polygon.antialiased = true
	add_child(_polygon)


func _resize_state() -> void:
	var count := maxi(bone_count, 3)
	_bone_angles.resize(count)
	_bone_angular_velocities.resize(count)
	for index in range(count):
		_bone_angles[index] = 0.0
		_bone_angular_velocities[index] = 0.0


func _clear_skeleton() -> void:
	_bones.clear()
	if _skeleton == null:
		return
	for child in _skeleton.get_children():
		_skeleton.remove_child(child)
		child.free()


func _build_skeleton() -> void:
	if _skeleton == null:
		return

	_clear_skeleton()
	_resize_state()

	var count := maxi(bone_count, 3)
	_rest_segment_length = display_height / maxf(float(count - 1), 1.0)

	var parent: Node = _skeleton
	for index in range(count):
		var bone := Bone2D.new()
		bone.name = "AhogeBone%d" % index
		bone.set_autocalculate_length_and_angle(false)
		bone.set_length(_rest_segment_length)
		bone.set_bone_angle(-PI * 0.5)
		if index > 0:
			bone.position = Vector2(0.0, -_rest_segment_length)
		parent.add_child(bone)
		bone.rest = bone.transform
		_bones.append(bone)
		parent = bone

	# NodePathはPolygon2DからSkeleton2Dへの相対path。
	_polygon.skeleton = _polygon.get_path_to(_skeleton)


func _sample_source_profile() -> void:
	_source_center_offsets = PackedFloat32Array()
	_source_half_widths = PackedFloat32Array()
	_source_uv_left = PackedFloat32Array()
	_source_uv_right = PackedFloat32Array()
	_source_uv_y = PackedFloat32Array()

	if _texture == null:
		return

	var image := _texture.get_image()
	if image == null or image.is_empty():
		return

	var source_width := image.get_width()
	var source_height := image.get_height()
	if source_width <= 0 or source_height <= 0:
		return

	var used := image.get_used_rect()
	if used.size.x <= 0 or used.size.y <= 0:
		used = Rect2i(0, 0, source_width, source_height)

	var section_count := maxi(mesh_sections, 8)
	var count := section_count + 1
	_source_center_offsets.resize(count)
	_source_half_widths.resize(count)
	_source_uv_left.resize(count)
	_source_uv_right.resize(count)
	_source_uv_y.resize(count)

	var centers_source := PackedFloat32Array()
	centers_source.resize(count)
	var scale_value := display_height / maxf(float(used.size.y - 1), 1.0)

	for index in range(count):
		var t := float(index) / float(section_count)
		var source_y_float := lerpf(
			float(used.position.y + used.size.y - 1),
			float(used.position.y),
			t
		)
		var source_y := clampi(int(round(source_y_float)), 0, source_height - 1)
		var span := _find_alpha_span(image, source_y, used)
		var left := int(span.x)
		var right := int(span.y)

		if left < 0 or right < left:
			if index > 0:
				left = int(_source_uv_left[index - 1])
				right = int(_source_uv_right[index - 1])
			else:
				left = used.position.x
				right = used.position.x + used.size.x - 1

		left = clampi(left - uv_padding, 0, source_width - 1)
		right = clampi(right + uv_padding, left, source_width - 1)

		var center_source := (float(left) + float(right)) * 0.5
		var half_width_source := maxf((float(right) - float(left)) * 0.5, 0.5)

		centers_source[index] = center_source
		_source_half_widths[index] = maxf(half_width_source * scale_value, min_half_width)
		_source_uv_left[index] = float(left)
		_source_uv_right[index] = float(right)
		_source_uv_y[index] = float(source_y)

	var root_center := centers_source[0]
	for index in range(count):
		_source_center_offsets[index] = (centers_source[index] - root_center) * scale_value


func _find_alpha_span(image: Image, center_y: int, used: Rect2i) -> Vector2:
	var min_x := clampi(used.position.x, 0, image.get_width() - 1)
	var max_x := clampi(used.position.x + used.size.x - 1, min_x, image.get_width() - 1)
	var min_y := clampi(used.position.y, 0, image.get_height() - 1)
	var max_y := clampi(used.position.y + used.size.y - 1, min_y, image.get_height() - 1)

	for radius in range(maxi(alpha_search_radius, 0) + 1):
		var candidates: Array[int] = [center_y]
		if radius > 0:
			candidates = [center_y - radius, center_y + radius]
		for candidate_y in candidates:
			if candidate_y < min_y or candidate_y > max_y:
				continue
			var left := -1
			var right := -1
			for x in range(min_x, max_x + 1):
				if image.get_pixel(x, candidate_y).a >= alpha_threshold:
					if left < 0:
						left = x
					right = x
			if left >= 0:
				return Vector2(float(left), float(right))

	return Vector2(-1.0, -1.0)


func _build_skin_mesh() -> void:
	if _polygon == null or _texture == null:
		return

	var section_count := maxi(mesh_sections, 8)
	var count := section_count + 1
	if _source_center_offsets.size() != count:
		return

	var points := PackedVector2Array()
	var uvs := PackedVector2Array()
	points.resize(count * 2)
	uvs.resize(count * 2)

	for index in range(count):
		var t := float(index) / float(section_count)
		var center := Vector2(
			_source_center_offsets[index],
			-display_height * t
		)
		var half_width := _source_half_widths[index]
		var left_index := index * 2
		var right_index := left_index + 1
		points[left_index] = center + Vector2(-half_width, 0.0)
		points[right_index] = center + Vector2(half_width, 0.0)
		uvs[left_index] = Vector2(_source_uv_left[index], _source_uv_y[index])
		uvs[right_index] = Vector2(_source_uv_right[index], _source_uv_y[index])

	var triangles: Array[PackedInt32Array] = []
	for index in range(section_count):
		var left_a := index * 2
		var right_a := left_a + 1
		var left_b := (index + 1) * 2
		var right_b := left_b + 1
		triangles.append(PackedInt32Array([left_a, right_a, left_b]))
		triangles.append(PackedInt32Array([right_a, right_b, left_b]))

	_polygon.polygon = points
	_polygon.uv = uvs
	_polygon.polygons = triangles
	_polygon.texture = _texture

	_bind_skin_weights(points.size(), section_count)


func _bind_skin_weights(vertex_count: int, section_count: int) -> void:
	if _polygon == null or _skeleton == null or _bones.is_empty():
		return

	_polygon.clear_bones()
	var weights_by_bone: Array[PackedFloat32Array] = []
	for _bone_index in range(_bones.size()):
		var weights := PackedFloat32Array()
		weights.resize(vertex_count)
		weights_by_bone.append(weights)

	for section_index in range(section_count + 1):
		var t := float(section_index) / float(section_count)
		var bone_position := t * float(_bones.size() - 1)
		var low := clampi(int(floor(bone_position)), 0, _bones.size() - 1)
		var high := clampi(low + 1, 0, _bones.size() - 1)
		var high_weight := bone_position - float(low)
		var low_weight := 1.0 - high_weight
		for vertex_offset in range(2):
			var vertex_index := section_index * 2 + vertex_offset
			var low_weights: PackedFloat32Array = weights_by_bone[low]
			low_weights[vertex_index] += low_weight
			weights_by_bone[low] = low_weights
			if high != low and high_weight > 0.0:
				var high_weights: PackedFloat32Array = weights_by_bone[high]
				high_weights[vertex_index] += high_weight
				weights_by_bone[high] = high_weights

	for bone_index in range(_bones.size()):
		var bone_path := _skeleton.get_path_to(_bones[bone_index])
		_polygon.add_bone(bone_path, weights_by_bone[bone_index])


func _reset_pose() -> void:
	_length_scale = 1.0
	_length_velocity = 0.0
	_action_age = 0.0
	_idle_phase = 0.0
	_resize_state()
	_apply_pose()


func _on_action_state_changed(action_state: int) -> void:
	match action_state:
		CombatantStateScript.ActionState.STRIKE:
			_length_velocity += 4.2
			for index in range(_bone_angular_velocities.size()):
				var t := float(index) / maxf(float(_bone_angular_velocities.size() - 1), 1.0)
				_bone_angular_velocities[index] += deg_to_rad(26.0) * pow(t, 1.5)
		CombatantStateScript.ActionState.STAGGER:
			for index in range(_bone_angular_velocities.size()):
				var t := float(index) / maxf(float(_bone_angular_velocities.size() - 1), 1.0)
				_bone_angular_velocities[index] -= deg_to_rad(18.0) * pow(t, 1.4)


func _simulate_bones(delta: float) -> void:
	var count := _bone_angles.size()
	if count <= 0:
		return

	var length_target := 1.0
	match _action_state:
		CombatantStateScript.ActionState.WINDUP:
			length_target = 1.04
		CombatantStateScript.ActionState.STRIKE:
			length_target = strike_length_scale

	var length_accel := (length_target - _length_scale) * stretch_spring
	length_accel -= _length_velocity * stretch_damping
	_length_velocity += length_accel * delta
	_length_scale += _length_velocity * delta
	_length_scale = clampf(_length_scale, 0.88, strike_length_scale * 1.06)

	for index in range(count):
		var t := float(index) / maxf(float(count - 1), 1.0)
		var target := _target_angle_for_bone(index, t)
		var spring := lerpf(root_spring, tip_spring, t)
		var damping := lerpf(root_damping, tip_damping, t)
		var accel := (target - _bone_angles[index]) * spring
		accel -= _bone_angular_velocities[index] * damping
		_bone_angular_velocities[index] += accel * delta
		_bone_angles[index] += _bone_angular_velocities[index] * delta


func _target_angle_for_bone(index: int, t: float) -> float:
	var count := maxf(float(_bone_angles.size()), 1.0)
	var total_turn := 0.0
	var action_weight := 1.0

	match _action_state:
		CombatantStateScript.ActionState.CHARGING:
			total_turn = deg_to_rad(charge_total_turn_degrees)
		CombatantStateScript.ActionState.WINDUP:
			total_turn = deg_to_rad(windup_total_turn_degrees)
		CombatantStateScript.ActionState.STRIKE:
			total_turn = deg_to_rad(strike_total_turn_degrees)
			var delay := t * strike_propagation_seconds
			action_weight = smoothstep(
				delay,
				delay + maxf(strike_propagation_seconds, 0.01),
				_action_age
			)
		CombatantStateScript.ActionState.PARRY:
			total_turn = deg_to_rad(-28.0)
		CombatantStateScript.ActionState.DODGE:
			total_turn = deg_to_rad(-36.0)
		CombatantStateScript.ActionState.STAGGER:
			total_turn = deg_to_rad(-48.0)
		_:
			total_turn = 0.0

	var distributed := total_turn / count
	var action_angle := distributed * action_weight * lerpf(0.72, 1.24, t)

	var local_velocity := _head_velocity.x
	var local_accel := _head_acceleration.x
	var inertial := clampf(
		-local_velocity * 0.00065 - local_accel * 0.000045,
		deg_to_rad(-7.0),
		deg_to_rad(7.0)
	) * pow(t, 1.55)

	var idle := 0.0
	if _action_state == CombatantStateScript.ActionState.IDLE:
		idle = deg_to_rad(idle_sway_degrees) * (
			sin(_idle_phase * 1.8 + float(index) * 0.52)
			+ sin(_idle_phase * 0.93 + float(index) * 0.31) * 0.38
		) * lerpf(0.18, 1.0, t)

	return action_angle + inertial + idle


func _apply_pose() -> void:
	if _bones.is_empty():
		return

	for index in range(_bones.size()):
		var bone := _bones[index]
		if index == 0:
			bone.position = Vector2.ZERO
		else:
			bone.position = Vector2(0.0, -_rest_segment_length * _length_scale)
		bone.rotation = _bone_angles[index]


func debug_tip_local_position() -> Vector2:
	if _bones.is_empty():
		return Vector2.ZERO

	var point := Vector2.ZERO
	var cumulative_angle := 0.0
	var segment_length := _rest_segment_length * _length_scale

	for index in range(_bones.size() - 1):
		cumulative_angle += _bone_angles[index]
		point += Vector2(0.0, -segment_length).rotated(cumulative_angle)

	cumulative_angle += _bone_angles[_bones.size() - 1]
	point += Vector2(0.0, -segment_length * 0.35).rotated(cumulative_angle)
	return point


func debug_total_length_scale() -> float:
	return _length_scale
