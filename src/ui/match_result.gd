class_name MatchResult
extends Control

signal rematch_requested
signal character_select_requested
signal top_requested

var _summary: Dictionary = {}


func configure(summary: Dictionary) -> void:
	_summary = summary.duplicate(true)


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
	var winner := int(_summary.get("winner", 0))
	title.text = "PLAYER %d WIN" % (winner + 1)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 36)
	root.add_child(title)

	var details := Label.new()
	details.text = "%s  %d - %d  %s" % [
		str(_summary.get("player_one_id", "LONG_TEST")),
		int(_summary.get("player_one_rounds", 0)),
		int(_summary.get("player_two_rounds", 0)),
		str(_summary.get("player_two_id", "SHORT_TEST")),
	]
	details.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(details)

	var note := Label.new()
	note.text = "ローカル縦切り検証のため、Rating / Ranking更新は行いません。"
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(note)

	var actions := HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	actions.add_theme_constant_override("separation", 12)
	root.add_child(actions)

	var rematch := Button.new()
	rematch.text = "REMATCH"
	rematch.pressed.connect(func() -> void:
		rematch_requested.emit()
	)
	actions.add_child(rematch)

	var character_select := Button.new()
	character_select.text = "CHANGE CHARACTER"
	character_select.pressed.connect(func() -> void:
		character_select_requested.emit()
	)
	actions.add_child(character_select)

	var top := Button.new()
	top.text = "TOP"
	top.pressed.connect(func() -> void:
		top_requested.emit()
	)
	actions.add_child(top)
