extends Control

signal join_requested(room_code: String)
signal back_requested

var _code_edit: LineEdit
var _status_label: Label


func _ready() -> void:
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var root := VBoxContainer.new()
	root.alignment = BoxContainer.ALIGNMENT_CENTER
	root.custom_minimum_size = Vector2(520.0, 0.0)
	root.add_theme_constant_override("separation", 12)
	center.add_child(root)

	var title := Label.new()
	title.text = "JOIN FRIEND ROOM"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 30)
	root.add_child(title)

	var code_label := Label.new()
	code_label.text = "ROOM CODE"
	code_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(code_label)

	_code_edit = LineEdit.new()
	_code_edit.placeholder_text = "A7K9PQ"
	_code_edit.max_length = 6
	_code_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_code_edit.text_changed.connect(_on_code_changed)
	root.add_child(_code_edit)

	var join := Button.new()
	join.text = "JOIN"
	join.pressed.connect(_on_join_pressed)
	root.add_child(join)

	_status_label = Label.new()
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(_status_label)

	var back := Button.new()
	back.text = "BACK"
	back.pressed.connect(func() -> void:
		back_requested.emit()
	)
	root.add_child(back)


func set_status(message: String) -> void:
	if _status_label != null:
		_status_label.text = message


func set_room_code(room_code: String) -> void:
	if _code_edit != null:
		_code_edit.text = room_code.to_upper().strip_edges().substr(0, 6)


func room_code_text() -> String:
	return _code_edit.text if _code_edit != null else ""


func _on_code_changed(value: String) -> void:
	var normalized := value.to_upper().strip_edges()
	if normalized.length() > 6:
		normalized = normalized.substr(0, 6)
	if normalized != value:
		var caret := mini(normalized.length(), _code_edit.caret_column)
		_code_edit.text = normalized
		_code_edit.caret_column = caret


func _on_join_pressed() -> void:
	var code := room_code_text().to_upper().strip_edges()
	if code.length() != 6:
		set_status("Room codeは6文字です。")
		return
	join_requested.emit(code)
