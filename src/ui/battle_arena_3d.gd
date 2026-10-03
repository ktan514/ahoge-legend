extends SubViewportContainer

const BattleFighter3DScript := preload("res://src/ui/battle_fighter_3d.gd")

var _viewport: SubViewport
var _world_root: Node3D
var _camera: Camera3D
var _player_one
var _player_two

var _p1_character
var _p1_state
var _p2_character
var _p2_state


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	stretch = true
	_build_world()
	_apply_configuration()
	_sync_viewport_size()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_sync_viewport_size()


func configure(player_one_character, player_one_state, player_two_character, player_two_state) -> void:
	_p1_character = player_one_character
	_p1_state = player_one_state
	_p2_character = player_two_character
	_p2_state = player_two_state
	if is_inside_tree():
		_apply_configuration()


func _build_world() -> void:
	_viewport = SubViewport.new()
	_viewport.name = "Battle3DViewport"
	_viewport.transparent_bg = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_viewport.own_world_3d = true
	add_child(_viewport)

	_world_root = Node3D.new()
	_world_root.name = "BattleWorld3D"
	_viewport.add_child(_world_root)

	_camera = Camera3D.new()
	_camera.name = "BattleCamera3D"
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.size = 9.4
	_camera.position = Vector3(0.0, 0.0, 12.0)
	_camera.current = true
	_world_root.add_child(_camera)

	var key_light := DirectionalLight3D.new()
	key_light.name = "KeyLight3D"
	key_light.rotation_degrees = Vector3(-38.0, -28.0, 0.0)
	key_light.light_energy = 1.35
	_world_root.add_child(key_light)

	var fill_light := DirectionalLight3D.new()
	fill_light.name = "FillLight3D"
	fill_light.rotation_degrees = Vector3(28.0, 150.0, 0.0)
	fill_light.light_energy = 0.65
	_world_root.add_child(fill_light)

	_player_one = BattleFighter3DScript.new()
	_player_one.name = "PlayerOne3D"
	_world_root.add_child(_player_one)

	_player_two = BattleFighter3DScript.new()
	_player_two.name = "PlayerTwo3D"
	_world_root.add_child(_player_two)


func _apply_configuration() -> void:
	if _player_one == null or _player_two == null:
		return
	if _p1_character != null and _p1_state != null:
		_player_one.configure(_p1_character, _p1_state, 1.0, -4.15)
	if _p2_character != null and _p2_state != null:
		_player_two.configure(_p2_character, _p2_state, -1.0, 4.15)


func _sync_viewport_size() -> void:
	if _viewport == null:
		return
	var width := maxi(int(size.x), 2)
	var height := maxi(int(size.y), 2)
	_viewport.size = Vector2i(width, height)


func player_one_fighter():
	return _player_one


func player_two_fighter():
	return _player_two
