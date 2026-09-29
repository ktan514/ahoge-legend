extends Control

signal ranked_requested
signal back_requested

var _status_label: Label


func _ready() -> void:
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var root := VBoxContainer.new()
	root.alignment = BoxContainer.ALIGNMENT_CENTER
	root.custom_minimum_size = Vector2(440.0, 0.0)
	root.add_theme_constant_override("separation", 14)
	center.add_child(root)

	var title := Label.new()
	title.text = "ONLINE BATTLE"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 32)
	root.add_child(title)

	var ranked := Button.new()
	ranked.text = "RANKED MATCH"
	ranked.pressed.connect(func() -> void:
		ranked_requested.emit()
	)
	root.add_child(ranked)

	var friend := Button.new()
	friend.text = "FRIEND MATCH（工程4後半）"
	friend.disabled = true
	root.add_child(friend)

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
