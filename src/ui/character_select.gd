class_name CharacterSelect
extends Control

signal battle_requested(player_one_id: String, player_two_id: String)
signal back_requested

var _player_one: OptionButton
var _player_two: OptionButton
var _preview: Label


func configure(player_one_id: String, player_two_id: String) -> void:
	if not is_node_ready():
		set_meta("initial_player_one", player_one_id)
		set_meta("initial_player_two", player_two_id)
		return
	_select_id(_player_one, player_one_id)
	_select_id(_player_two, player_two_id)
	_update_preview()


func _ready() -> void:
	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.alignment = BoxContainer.ALIGNMENT_CENTER
	root.add_theme_constant_override("separation", 12)
	add_child(root)

	var title := Label.new()
	title.text = "CHARACTER SELECT"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 28)
	root.add_child(title)

	var selectors := HBoxContainer.new()
	selectors.alignment = BoxContainer.ALIGNMENT_CENTER
	selectors.add_theme_constant_override("separation", 32)
	root.add_child(selectors)

	var player_one_box := VBoxContainer.new()
	var player_one_label := Label.new()
	player_one_label.text = "PLAYER 1"
	player_one_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	player_one_box.add_child(player_one_label)
	_player_one = _create_character_selector()
	player_one_box.add_child(_player_one)
	selectors.add_child(player_one_box)

	var player_two_box := VBoxContainer.new()
	var player_two_label := Label.new()
	player_two_label.text = "PLAYER 2"
	player_two_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	player_two_box.add_child(player_two_label)
	_player_two = _create_character_selector()
	player_two_box.add_child(_player_two)
	selectors.add_child(player_two_box)

	_preview = Label.new()
	_preview.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(_preview)

	var actions := HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	actions.add_theme_constant_override("separation", 16)
	root.add_child(actions)

	var back := Button.new()
	back.text = "BACK"
	back.pressed.connect(func() -> void:
		back_requested.emit()
	)
	actions.add_child(back)

	var start := Button.new()
	start.text = "START LOCAL BATTLE"
	start.pressed.connect(_on_start_pressed)
	actions.add_child(start)

	_player_one.item_selected.connect(func(_index: int) -> void:
		_update_preview()
	)
	_player_two.item_selected.connect(func(_index: int) -> void:
		_update_preview()
	)

	_select_id(_player_one, str(get_meta("initial_player_one", "LONG_TEST")))
	_select_id(_player_two, str(get_meta("initial_player_two", "SHORT_TEST")))
	_update_preview()


func _create_character_selector() -> OptionButton:
	var selector := OptionButton.new()
	for character in CharacterCatalog.all():
		selector.add_item(character.display_name)
		selector.set_item_metadata(selector.item_count - 1, character.character_id)
	return selector


func _select_id(selector: OptionButton, character_id: String) -> void:
	for index in range(selector.item_count):
		if str(selector.get_item_metadata(index)) == character_id:
			selector.select(index)
			return


func _selected_id(selector: OptionButton) -> String:
	if selector.selected < 0:
		return "LONG_TEST"
	return str(selector.get_item_metadata(selector.selected))


func _update_preview() -> void:
	var player_one := CharacterCatalog.get_by_id(_selected_id(_player_one))
	var player_two := CharacterCatalog.get_by_id(_selected_id(_player_two))
	_preview.text = "%s [%s / %s]  VS  %s [%s / %s]" % [
		player_one.display_name,
		player_one.ahoge_type_name(),
		player_one.attack_type_name(),
		player_two.display_name,
		player_two.ahoge_type_name(),
		player_two.attack_type_name(),
	]


func _on_start_pressed() -> void:
	battle_requested.emit(_selected_id(_player_one), _selected_id(_player_two))
