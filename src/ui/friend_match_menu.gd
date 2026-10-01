extends Control

signal create_requested
signal join_requested
signal back_requested

var _status_label: Label


func _ready() -> void:
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var root := VBoxContainer.new()
	root.alignment = BoxContainer.ALIGNMENT_CENTER
	root.custom_minimum_size = Vector2(480.0, 0.0)
	root.add_theme_constant_override("separation", 14)
	center.add_child(root)

	var title := Label.new()
	title.text = "FRIEND MATCH"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 32)
	root.add_child(title)

	var create := Button.new()
	create.text = "CREATE ROOM"
	create.pressed.connect(func() -> void:
		create_requested.emit()
	)
	root.add_child(create)

	var join := Button.new()
	join.text = "JOIN ROOM"
	join.pressed.connect(func() -> void:
		join_requested.emit()
	)
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
