extends Control

signal local_test_requested
signal exit_requested


func _ready() -> void:
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var menu := VBoxContainer.new()
	menu.alignment = BoxContainer.ALIGNMENT_CENTER
	menu.custom_minimum_size = Vector2(360.0, 0.0)
	center.add_child(menu)

	var title := Label.new()
	title.text = "AHOGE LEGEND"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 36)
	menu.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "機能優先プロトタイプ"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	menu.add_child(subtitle)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0.0, 24.0)
	menu.add_child(spacer)

	var local_button := Button.new()
	local_button.text = "LOCAL TEST BATTLE"
	local_button.pressed.connect(func() -> void:
		local_test_requested.emit()
	)
	menu.add_child(local_button)

	var online_button := Button.new()
	online_button.text = "ONLINE BATTLE（後続Issue）"
	online_button.disabled = true
	menu.add_child(online_button)

	var ranking_button := Button.new()
	ranking_button.text = "RANKING（後続Issue）"
	ranking_button.disabled = true
	menu.add_child(ranking_button)

	var settings_button := Button.new()
	settings_button.text = "SETTINGS（後続Issue）"
	settings_button.disabled = true
	menu.add_child(settings_button)

	var exit_button := Button.new()
	exit_button.text = "EXIT"
	exit_button.pressed.connect(func() -> void:
		exit_requested.emit()
	)
	menu.add_child(exit_button)
