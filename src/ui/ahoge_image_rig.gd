extends Node2D

const CombatantStateScript := preload("res://src/domain/combatant_state.gd")

@export var display_height: float = 248.0
@export var segments: int = 26
@export var alpha_threshold: float = 0.04
@export var alpha_search_radius: int = 12
@export var uv_padding: int = 2
@export var min_section_half_width: float = 1.5

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
@export var pose_response: float = 12.0
@export var extension_spring_idle: float = 18.0
@export var extension_spring_charge: float = 28.0
@export var extension_spring_windup: float = 36.0
@export var extension_spring_strike: float = 105.0
@export var extension_damping: float = 8.0
@export var charge_back_extension: float = 90.0
@export var windup_back_extension: float = 130.0
@export var strike_forward_extension: float = 520.0
@export var strike_impulse: float = 1800.0
@export var strike_straighten: float = 0.86
@export var strike_height_scale: float = 0.42
@export var charge_follow_delay: float = 0.10
@export var parry_back_extension: float = 20.0
@export var dodge_back_extension: float = 28.0
@export var stagger_back_extension: float = 38.0

var _mesh_instance: MeshInstance2D
var _texture: Texture2D
var _facing: float = 1.0
var _available: bool = true

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
var _pose_target: float = 0.0
var _pose_blend: float = 0.0

var _joint_offsets := PackedFloat32Array()
var _joint_velocities := PackedFloat32Array()

# source PNGを縦方向にsamplingしたrest profile。
# center offset / half widthはdisplay座標、UVはsource texture座標。
var _source_center_offsets := PackedFloat32Array()
var _source_half_widths := PackedFloat32Array()
var _source_uv_left := PackedFloat32Array()
var _source_uv_right := PackedFloat32Array()
var _source_uv_y := PackedFloat32Array()


func _ready() -> void:
	_mesh_instance = MeshInstance2D.new()
	_mesh_instance.name = "AhogeRibbonMesh"
	add_child(_mesh_instance)
	_resize_joint_state()
	set_process(true)
	_refresh_mesh()


func configure(texture_value: Texture2D, facing_value: float) -> void:
	_texture = texture_value
	_facing = 1.0 if facing_value >= 0.0 else -1.0
	scale.x = _facing
	if _mesh_instance != null:
		_mesh_instance.texture = _texture
	_sample_source_profile()
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
			_stretch_target = 0.04
			_pose_target = 0.0
		CombatantStateScript.ActionState.WINDUP:
			_action_bend_target = -26.0
			_action_extension_target = -windup_back_extension
			_stretch_target = 0.06
			_pose_target = 0.10
		CombatantStateScript.ActionState.STRIKE:
			_action_bend_target = 54.0
			_action_extension_target = strike_forward_extension
			_stretch_target = 0.0
			_pose_target = 1.0
		CombatantStateScript.ActionState.PARRY:
			_action_bend_target = -10.0
			_action_extension_target = -parry_back_extension
			_stretch_target = 0.015
			_pose_target = 0.0
		CombatantStateScript.ActionState.DODGE:
			_action_bend_target = -24.0
			_action_extension_target = -dodge_back_extension
			_stretch_target = -0.02
			_pose_target = 0.0
		CombatantStateScript.ActionState.STAGGER:
			_action_bend_target = -34.0
			_action_extension_target = -stagger_back_extension
			_stretch_target = -0.04
			_pose_target = 0.0
		_:
			_action_bend_target = 0.0
			_action_extension_target = 0.0
			_stretch_target = 0.0
			_pose_target = 0.0


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
	_pose_blend = lerpf(
		_pose_blend,
		_pose_target,
		minf(delta * pose_response, 1.0)
	)

	var extension_spring := extension_spring_idle
	var effective_extension_target := _action_extension_target
	match _action_state:
		CombatantStateScript.ActionState.CHARGING:
			extension_spring = extension_spring_charge
			if _action_age < charge_follow_delay:
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

	var safe_segments := maxi(segments, 4)
	var count := safe_segments + 1
	_source_center_offsets.resize(count)
	_source_half_widths.resize(count)
	_source_uv_left.resize(count)
	_source_uv_right.resize(count)
	_source_uv_y.resize(count)

	var raw_centers := PackedFloat32Array()
	raw_centers.resize(count)
	var source_scale := display_height / maxf(float(used.size.y - 1), 1.0)

	for index in range(count):
		var t := float(index) / float(safe_segments)
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
			left = used.position.x
			right = used.position.x + used.size.x - 1

		left = clampi(left - uv_padding, 0, source_width - 1)
		right = clampi(right + uv_padding, left, source_width - 1)

		var center_source := (float(left) + float(right)) * 0.5
		var half_width_source := maxf((float(right) - float(left)) * 0.5, 0.5)

		raw_centers[index] = center_source
		_source_half_widths[index] = maxf(
			half_width_source * source_scale,
			min_section_half_width
		)
		_source_uv_left[index] = float(left)
		_source_uv_right[index] = float(right)
		_source_uv_y[index] = float(source_y)

	var root_center := raw_centers[0]
	for index in range(count):
		_source_center_offsets[index] = (raw_centers[index] - root_center) * source_scale


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


func _refresh_mesh() -> void:
	if _mesh_instance == null or _texture == null:
		return

	var geometry := _build_ribbon_geometry()
	var vertices_2d: PackedVector2Array = geometry.get("vertices", PackedVector2Array())
	var uvs: PackedVector2Array = geometry.get("uvs", PackedVector2Array())
	var indices: PackedInt32Array = geometry.get("indices", PackedInt32Array())
	if vertices_2d.is_empty() or indices.is_empty():
		_mesh_instance.mesh = null
		return

	var vertices_3d := PackedVector3Array()
	vertices_3d.resize(vertices_2d.size())
	for index in range(vertices_2d.size()):
		var point := vertices_2d[index]
		vertices_3d[index] = Vector3(point.x, point.y, 0.0)

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices_3d
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices

	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_mesh_instance.mesh = mesh
	_mesh_instance.texture = _texture


func _build_ribbon_geometry() -> Dictionary:
	_resize_joint_state()
	var safe_segments := maxi(segments, 4)
	var count := safe_segments + 1
	if _source_center_offsets.size() != count:
		_sample_source_profile()
	if _source_center_offsets.size() != count or _texture == null:
		return {
			"vertices": PackedVector2Array(),
			"uvs": PackedVector2Array(),
			"indices": PackedInt32Array(),
		}

	var centers := PackedVector2Array()
	centers.resize(count)
	for index in range(count):
		var t := float(index) / float(safe_segments)
		centers[index] = _segment_center(index, t)

	var vertices := PackedVector2Array()
	var uvs := PackedVector2Array()
	vertices.resize(count * 2)
	uvs.resize(count * 2)

	var source_size := _texture.get_size()
	var source_width := maxf(source_size.x, 1.0)
	var source_height := maxf(source_size.y, 1.0)

	for index in range(count):
		var previous_index := maxi(index - 1, 0)
		var next_index := mini(index + 1, count - 1)
		var tangent := centers[next_index] - centers[previous_index]
		if tangent.length_squared() <= 0.0001:
			tangent = Vector2(0.0, -1.0)
		else:
			tangent = tangent.normalized()

		# centerlineへ直交するnormalへ左右断面を配置する。
		# 各segmentを明示triangleで結ぶため、ribbon全体が自己交差しても
		# Polygon2Dの自動triangulation失敗で全体が消えることはない。
		var normal := Vector2(-tangent.y, tangent.x).normalized()
		var half_width := maxf(_source_half_widths[index], min_section_half_width)
		var left_index := index * 2
		var right_index := left_index + 1
		vertices[left_index] = centers[index] - normal * half_width
		vertices[right_index] = centers[index] + normal * half_width

		var uv_y := clampf(_source_uv_y[index] / source_height, 0.0, 1.0)
		uvs[left_index] = Vector2(
			clampf(_source_uv_left[index] / source_width, 0.0, 1.0),
			uv_y
		)
		uvs[right_index] = Vector2(
			clampf(_source_uv_right[index] / source_width, 0.0, 1.0),
			uv_y
		)

	var indices := PackedInt32Array()
	indices.resize(safe_segments * 6)
	var write_index := 0
	for segment_index in range(safe_segments):
		var left_a := segment_index * 2
		var right_a := left_a + 1
		var left_b := (segment_index + 1) * 2
		var right_b := left_b + 1

		indices[write_index] = left_a
		indices[write_index + 1] = right_a
		indices[write_index + 2] = left_b
		indices[write_index + 3] = right_a
		indices[write_index + 4] = right_b
		indices[write_index + 5] = left_b
		write_index += 6

	return {
		"vertices": vertices,
		"uvs": uvs,
		"indices": indices,
	}


func _segment_center(index: int, t: float) -> Vector2:
	var source_x := 0.0
	if index >= 0 and index < _source_center_offsets.size():
		source_x = _source_center_offsets[index]

	var joint_x := 0.0
	if index >= 0 and index < _joint_offsets.size():
		joint_x = _joint_offsets[index]

	var pose_weight := smoothstep(0.04, 1.0, t)
	var straighten_amount := clampf(
		_pose_blend * strike_straighten * pose_weight,
		0.0,
		0.95
	)
	var x := source_x * (1.0 - straighten_amount) + joint_x

	var extension_weight := smoothstep(0.08, 0.94, t)
	x += _action_extension * extension_weight

	var pose_height := lerpf(1.0, strike_height_scale, clampf(_pose_blend, 0.0, 1.0))
	var y := -display_height * (1.0 + _stretch) * pose_height * t
	return Vector2(x, y)
