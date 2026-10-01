extends Control

signal refresh_requested
signal character_select_requested
signal ready_requested(ready: bool)
signal leave_requested

const REFRESH_SECONDS := 0.5

var _room: Dictionary = {}
var _local_user_id: String = ""
var _room_code_label: Label
var _state_label: Label
var _host_label: Label
var _guest_label: Label
var _status_label: Label
var _ready_button: Button
var _character_button: Button
var _leave_button: Button
var _timer: Timer


func configure(room: Dictionary, local_user_id: String) -> void:
	_room = room.duplicate(true)
	_local_user_id = local_user_id


func _ready() -> void:
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var root := VBoxContainer.new()
	root.alignment = BoxContainer.ALIGNMENT_CENTER
	root.custom_minimum_size = Vector2(760.0, 0.0)
	root.add_theme_constant_override("separation", 12)
	center.add_child(root)

	var title := Label.new()
	title.text = "FRIEND ROOM"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 30)
	root.add_child(title)

	var room_row := HBoxContainer.new()
	room_row.alignment = BoxContainer.ALIGNMENT_CENTER
	room_row.add_theme_constant_override("separation", 10)
	root.add_child(room_row)

	_room_code_label = Label.new()
	room_row.add_child(_room_code_label)

	var copy := Button.new()
	copy.text = "COPY"
	copy.pressed.connect(_copy_room_code)
	room_row.add_child(copy)

	_state_label = Label.new()
	_state_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(_state_label)

	var players := HBoxContainer.new()
	players.alignment = BoxContainer.ALIGNMENT_CENTER
	players.add_theme_constant_override("separation", 36)
	root.add_child(players)

	_host_label = Label.new()
	_host_label.custom_minimum_size = Vector2(330.0, 100.0)
	_host_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_host_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	players.add_child(_host_label)

	_guest_label = Label.new()
	_guest_label.custom_minimum_size = Vector2(330.0, 100.0)
	_guest_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_guest_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	players.add_child(_guest_label)

	var actions := HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	actions.add_theme_constant_override("separation", 12)
	root.add_child(actions)

	_character_button = Button.new()
	_character_button.text = "CHARACTER SELECT"
	_character_button.pressed.connect(func() -> void:
		character_select_requested.emit()
	)
	actions.add_child(_character_button)

	_ready_button = Button.new()
	_ready_button.pressed.connect(_on_ready_pressed)
	actions.add_child(_ready_button)

	_leave_button = Button.new()
	_leave_button.text = "LEAVE ROOM"
	_leave_button.pressed.connect(func() -> void:
		leave_requested.emit()
	)
	actions.add_child(_leave_button)

	_status_label = Label.new()
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(_status_label)

	_timer = Timer.new()
	_timer.wait_time = REFRESH_SECONDS
	_timer.one_shot = false
	_timer.autostart = true
	_timer.timeout.connect(func() -> void:
		refresh_requested.emit()
	)
	add_child(_timer)

	_render()


func update_room(room: Dictionary) -> void:
	_room = room.duplicate(true)
	_render()


func set_status(message: String) -> void:
	if _status_label != null:
		_status_label.text = message


func room_code() -> String:
	return str(_room.get("room_code", ""))


func local_role() -> String:
	return str(_room.get("role", ""))


func local_character_id() -> String:
	return _character_for_role(local_role())


func local_ready() -> bool:
	return _ready_for_role(local_role())


func _render() -> void:
	if _room_code_label == null:
		return

	var code := room_code()
	_room_code_label.text = "CODE: %s" % code
	_state_label.text = "STATE: %s" % str(_room.get("state", ""))

	_host_label.text = _player_text(
		"HOST",
		str(_room.get("host_user_id", "")),
		str(_room.get("host_character_id", "")),
		bool(_room.get("host_ready", false))
	)
	_guest_label.text = _player_text(
		"GUEST",
		str(_room.get("guest_user_id", "")),
		str(_room.get("guest_character_id", "")),
		bool(_room.get("guest_ready", false))
	)

	var active := str(_room.get("state", "")) in ["STARTING", "IN_MATCH"]
	var both_present := (
		not str(_room.get("host_user_id", "")).is_empty()
		and not str(_room.get("guest_user_id", "")).is_empty()
	)
	var both_selected := (
		not str(_room.get("host_character_id", "")).is_empty()
		and not str(_room.get("guest_character_id", "")).is_empty()
	)
	_ready_button.text = "CANCEL READY" if local_ready() else "READY"
	_ready_button.disabled = active or not both_present or not both_selected
	_character_button.disabled = active
	_leave_button.disabled = active


func _player_text(
	role_name: String,
	user_id: String,
	character_id: String,
	ready: bool
) -> String:
	if user_id.is_empty():
		return "%s\nWAITING..." % role_name
	var short_id := user_id.substr(0, mini(8, user_id.length()))
	return "%s\n%s\n%s\n%s" % [
		role_name,
		short_id,
		character_id if not character_id.is_empty() else "NO CHARACTER",
		"READY" if ready else "NOT READY",
	]


func _character_for_role(role: String) -> String:
	if role == "host":
		return str(_room.get("host_character_id", ""))
	if role == "guest":
		return str(_room.get("guest_character_id", ""))
	return ""


func _ready_for_role(role: String) -> bool:
	if role == "host":
		return bool(_room.get("host_ready", false))
	if role == "guest":
		return bool(_room.get("guest_ready", false))
	return false


func _on_ready_pressed() -> void:
	ready_requested.emit(not local_ready())


func _copy_room_code() -> void:
	var code := room_code()
	if code.is_empty():
		return
	DisplayServer.clipboard_set(code)
	set_status("ROOM CODE COPIED")
