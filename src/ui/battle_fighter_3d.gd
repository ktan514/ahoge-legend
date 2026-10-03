extends Node3D

const CombatantStateScript := preload("res://src/domain/combatant_state.gd")
const CharacterDefinitionScript := preload("res://src/domain/character_definition.gd")

@export var long_length: float = 3.5
@export var normal_length: float = 2.7
@export var short_length: float = 1.5
@export var radial_sides: int = 10
@export var length_segments: int = 24

var character
var combat_state
var facing: float = 1.0
var base_x: float = 0.0

var _head_root: Node3D
var _head_mesh: MeshInstance3D
var _hair_mesh: MeshInstance3D
var _ahoge_mesh: MeshInstance3D

var _head_offset := Vector2.ZERO
var _head_velocity := Vector2.ZERO
var _head_acceleration := Vector2.ZERO
var _head_rotation: float = 0.0
var _breath_phase: float = 0.0

var _extension: float = 0.0
var _extension_velocity: float = 0.0
var _bend: float = 0.0
var _bend_velocity: float = 0.0
var _pose_blend: float = 0.0
var _pose_target: float = 0.0
var _last_action_state: int = -1

var _hair_material: StandardMaterial3D
var _head_material: StandardMaterial3D
var _ahoge_material: StandardMaterial3D


func configure(character_value, combat_state_value, facing_value: float, base_x_value: float) -> void:
	character = character_value
	combat_state = combat_state_value
	facing = 1.0 if facing_value >= 0.0 else -1.0
	base_x = base_x_value
	if is_inside_tree():
		_apply_character_style()
		_update_geometry()


func _ready() -> void:
	_build_nodes()
	_apply_character_style()
	set_process(true)
	_update_geometry()


func _build_nodes() -> void:
	_head_root = Node3D.new()
	_head_root.name = "HeadRoot3D"
	add_child(_head_root)

	_head_mesh = MeshInstance3D.new()
	_head_mesh.name = "HeadMesh3D"
	var head_sphere := SphereMesh.new()
	head_sphere.radius = 2.28
	head_sphere.height = 4.56
	head_sphere.radial_segments = 40
	head_sphere.rings = 24
	_head_mesh.mesh = head_sphere
	_head_mesh.scale = Vector3(1.08, 0.94, 0.92)
	_head_root.add_child(_head_mesh)

	_hair_mesh = MeshInstance3D.new()
	_hair_mesh.name = "HairMesh3D"
	var hair_sphere := SphereMesh.new()
	hair_sphere.radius = 2.42
	hair_sphere.height = 4.84
	hair_sphere.radial_segments = 40
	hair_sphere.rings = 24
	_hair_mesh.mesh = hair_sphere
	_hair_mesh.scale = Vector3(1.10, 0.96, 0.94)
	_hair_mesh.position = Vector3(0.0, 0.10, 0.0)
	_head_root.add_child(_hair_mesh)

	_ahoge_mesh = MeshInstance3D.new()
	_ahoge_mesh.name = "AhogeMesh3D"
	add_child(_ahoge_mesh)

	_head_material = StandardMaterial3D.new()
	_head_material.albedo_color = Color("#ffd8cf")
	_head_material.roughness = 0.82

	_hair_material = StandardMaterial3D.new()
	_hair_material.roughness = 0.72

	_ahoge_material = StandardMaterial3D.new()
	_ahoge_material.roughness = 0.64
	_ahoge_material.cull_mode = BaseMaterial3D.CULL_DISABLED

	_head_mesh.material_override = _head_material
	_hair_mesh.material_override = _hair_material
	_ahoge_mesh.material_override = _ahoge_material


func _apply_character_style() -> void:
	if _hair_material == null or _ahoge_material == null:
		return

	var color := Color("#fe7793") if facing > 0.0 else Color("#ff4f58")
	if character != null and character.character_id == "LONG_TEST":
		color = Color("#fe7793")
	elif character != null and character.character_id == "SHORT_TEST":
		color = Color("#ff4f58")

	_hair_material.albedo_color = color
	_ahoge_material.albedo_color = color.darkened(0.03)


func _process(delta: float) -> void:
	if delta <= 0.0 or combat_state == null:
		return

	_breath_phase += delta
	_simulate_head(delta)
	_simulate_ahoge(delta)
	_update_geometry()


func _simulate_head(delta: float) -> void:
	var action_target := Vector2.ZERO
	var rotation_target := 0.0

	match combat_state.action_state:
		CombatantStateScript.ActionState.CHARGING:
			action_target.x = -facing * 0.62
			rotation_target = -3.0 * facing
		CombatantStateScript.ActionState.WINDUP:
			action_target.x = -facing * 0.78
			rotation_target = -4.0 * facing
		CombatantStateScript.ActionState.STRIKE:
			action_target.x = facing * 0.46
			rotation_target = 5.0 * facing
		CombatantStateScript.ActionState.PARRY:
			action_target.y = 0.32
			rotation_target = -2.5 * facing
		CombatantStateScript.ActionState.DODGE:
			action_target = Vector2(-facing * 0.28, -0.34)
			rotation_target = 3.0 * facing
		CombatantStateScript.ActionState.COOLDOWN:
			action_target.x = facing * 0.16
			rotation_target = 1.6 * facing
		CombatantStateScript.ActionState.STAGGER:
			action_target.x = -facing * 0.24
			rotation_target = -4.5 * facing

	var breath_scale := 1.0
	if combat_state.action_state in [
		CombatantStateScript.ActionState.CHARGING,
		CombatantStateScript.ActionState.WINDUP,
		CombatantStateScript.ActionState.STRIKE,
		CombatantStateScript.ActionState.PARRY,
		CombatantStateScript.ActionState.DODGE,
		CombatantStateScript.ActionState.STAGGER,
		CombatantStateScript.ActionState.ROUND_LOCKED,
	]:
		breath_scale = 0.0

	var breath_offset := Vector2(
		sin(_breath_phase * 1.35) * 0.05,
		sin(_breath_phase * 0.92 + 0.45) * 0.05
	) * breath_scale

	var target := action_target + breath_offset
	var previous_offset := _head_offset
	var previous_velocity := _head_velocity
	var response := 9.0
	if combat_state.action_state == CombatantStateScript.ActionState.STRIKE:
		response = 20.0
	elif combat_state.action_state == CombatantStateScript.ActionState.CHARGING:
		response = 7.5

	_head_offset = _head_offset.lerp(target, minf(delta * response, 1.0))
	_head_velocity = (_head_offset - previous_offset) / maxf(delta, 0.001)
	_head_acceleration = (_head_velocity - previous_velocity) / maxf(delta, 0.001)
	_head_rotation = lerpf(
		_head_rotation,
		rotation_target,
		minf(delta * 8.0, 1.0)
	)


func _simulate_ahoge(delta: float) -> void:
	var extension_target := 0.0
	var extension_spring := 18.0
	var bend_target := clampf(
		-_head_velocity.x * 0.34 - _head_acceleration.x * 0.028,
		-1.15,
		1.15
	)
	_pose_target = 0.0

	match combat_state.action_state:
		CombatantStateScript.ActionState.CHARGING:
			extension_target = -1.10
			extension_spring = 27.0
			bend_target -= facing * 0.28
		CombatantStateScript.ActionState.WINDUP:
			extension_target = -1.55
			extension_spring = 34.0
			bend_target -= facing * 0.42
		CombatantStateScript.ActionState.STRIKE:
			extension_target = 5.90 if _ahoge_length() > 2.0 else 3.20
			extension_spring = 62.0
			bend_target += facing * 0.70
			_pose_target = 1.0
		CombatantStateScript.ActionState.PARRY:
			extension_target = -0.35
			bend_target -= facing * 0.45
		CombatantStateScript.ActionState.DODGE:
			extension_target = -0.42
			bend_target -= facing * 0.60
		CombatantStateScript.ActionState.STAGGER:
			extension_target = -0.58
			bend_target -= facing * 0.72

	if combat_state.action_state != _last_action_state:
		if combat_state.action_state == CombatantStateScript.ActionState.STRIKE:
			_extension_velocity += 8.5
			_bend_velocity += facing * 4.2
		elif combat_state.action_state == CombatantStateScript.ActionState.STAGGER:
			_bend_velocity -= facing * 3.0
		_last_action_state = combat_state.action_state

	var extension_accel := (extension_target - _extension) * extension_spring
	extension_accel -= _extension_velocity * 8.5
	_extension_velocity += extension_accel * delta
	_extension += _extension_velocity * delta

	var bend_accel := (bend_target - _bend) * 22.0 - _bend_velocity * 6.0
	_bend_velocity += bend_accel * delta
	_bend += _bend_velocity * delta
	_pose_blend = lerpf(_pose_blend, _pose_target, minf(delta * 11.0, 1.0))


func kick(power: float = 1.0) -> void:
	_bend_velocity += facing * 3.8 * power
	_extension_velocity += 2.0 * power


func _update_geometry() -> void:
	if _head_root == null or _ahoge_mesh == null:
		return

	var head_center := Vector3(
		base_x + _head_offset.x,
		-3.45 + _head_offset.y,
		0.0
	)
	_head_root.position = head_center
	_head_root.rotation = Vector3(0.0, deg_to_rad(-5.0 * facing), deg_to_rad(_head_rotation))

	var available := combat_state == null or bool(combat_state.ahoge_available)
	_ahoge_mesh.visible = available
	if not available:
		return

	_ahoge_mesh.mesh = _build_ahoge_mesh(head_center)


func _build_ahoge_mesh(head_center: Vector3) -> ArrayMesh:
	var segment_count := maxi(length_segments, 6)
	var side_count := maxi(radial_sides, 6)
	var centers := PackedVector3Array()
	centers.resize(segment_count + 1)

	for index in range(segment_count + 1):
		var t := float(index) / float(segment_count)
		centers[index] = _centerline_point(head_center, t)

	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()

	vertices.resize((segment_count + 1) * side_count)
	normals.resize(vertices.size())
	uvs.resize(vertices.size())
	indices.resize(segment_count * side_count * 6)

	for index in range(segment_count + 1):
		var previous_index := maxi(index - 1, 0)
		var next_index := mini(index + 1, segment_count)
		var tangent := centers[next_index] - centers[previous_index]
		if tangent.length_squared() < 0.000001:
			tangent = Vector3.UP
		else:
			tangent = tangent.normalized()

		var binormal := Vector3(0.0, 0.0, 1.0)
		var normal_axis := binormal.cross(tangent)
		if normal_axis.length_squared() < 0.000001:
			normal_axis = Vector3.RIGHT
		else:
			normal_axis = normal_axis.normalized()
		binormal = tangent.cross(normal_axis).normalized()

		var t := float(index) / float(segment_count)
		var radius := lerpf(0.24, 0.045, pow(t, 1.28))
		for side in range(side_count):
			var angle := TAU * float(side) / float(side_count)
			var radial := normal_axis * cos(angle) + binormal * sin(angle)
			var vertex_index := index * side_count + side
			vertices[vertex_index] = centers[index] + radial * radius
			normals[vertex_index] = radial
			uvs[vertex_index] = Vector2(float(side) / float(side_count), t)

	var write_index := 0
	for index in range(segment_count):
		for side in range(side_count):
			var next_side := (side + 1) % side_count
			var a := index * side_count + side
			var b := index * side_count + next_side
			var c := (index + 1) * side_count + side
			var d := (index + 1) * side_count + next_side

			indices[write_index] = a
			indices[write_index + 1] = b
			indices[write_index + 2] = c
			indices[write_index + 3] = b
			indices[write_index + 4] = d
			indices[write_index + 5] = c
			write_index += 6

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices

	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _centerline_point(head_center: Vector3, t: float) -> Vector3:
	var crown := head_center + Vector3(0.0, 2.22, 0.0)
	var length := _ahoge_length()
	var rest_x := facing * (
		sin(t * PI * 1.08) * 0.62
		+ sin(t * PI * 2.10) * 0.12
	)
	var straighten := clampf(_pose_blend * smoothstep(0.10, 1.0, t), 0.0, 0.92)
	var x := rest_x * (1.0 - straighten)
	x += _bend * pow(t, 1.75)
	x += facing * _extension * smoothstep(0.08, 0.96, t)

	var height_scale := lerpf(1.0, 0.36, _pose_blend)
	var y := length * t * height_scale
	var z := sin(t * PI) * 0.10 * (1.0 - _pose_blend * 0.6)

	var local := Vector2(x, y).rotated(deg_to_rad(_head_rotation))
	return crown + Vector3(local.x, local.y, z)


func _ahoge_length() -> float:
	if character == null:
		return long_length
	match character.ahoge_type:
		CharacterDefinitionScript.AhogeType.SHORT:
			return short_length
		CharacterDefinitionScript.AhogeType.NORMAL:
			return normal_length
		_:
			return long_length
