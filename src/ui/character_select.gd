extends Control

const CharacterCatalogScript := preload("res://src/domain/character_catalog.gd")

signal battle_requested(player_one_id: String, player_two_id: String)
signal ranked_character_selected(character_id: String)
signal back_requested

const MODE_LOCAL := "local"
const MODE_RANKED := "ranked"

var _mode: String = MODE_LOCAL
var _player_one: OptionButton
var _player_two: OptionButton
var _preview: Label


func configure(player_one_id: String, player_two_id: String) -> void:
	set_meta("mode", MODE_LOCAL)
	set_meta("initial_player_one", player_one_id)
	set_meta("initial_player_two", player_two_id)


func configure_ranked(character_id: String) -> void:
	set_meta("mode", MODE_RANKED)
	set_meta("initial_player_one", character_id)


func _ready() -> void:
	_mode = str(get_meta("mode", MODE_LOCAL))

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
	player_one_label.text = "YOUR AHOGE" if _mode == MODE_RANKED else "PLAYER 1"
	player_one_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	player_one_box.add_child(player_one_label)
	_player_one = _create_character_selector()
	player_one_box.add_child(_player_one)
	selectors.add_child(player_one_box)

	if _mode == MODE_LOCAL:
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

	if _mode == MODE_RANKED:
		var note := Label.new()
		note.text = "Ranked Match / Rating対象"
		note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		root.add_child(note)

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
	start.text = "DECIDE" if _mode == MODE_RANKED else "START LOCAL BATTLE"
	start.pressed.connect(_on_start_pressed)
	actions.add_child(start)

	_player_one.item_selected.connect(func(_index: int) -> void:
		_update_preview()
	)
	if _player_two != null:
		_player_two.item_selected.connect(func(_index: int) -> void:
			_update_preview()
		)

	_select_id(_player_one, str(get_meta("initial_player_one", "LONG_TEST")))
	if _player_two != null:
		_select_id(_player_two, str(get_meta("initial_player_two", "SHORT_TEST")))
	_update_preview()


func _create_character_selector() -> OptionButton:
	var selector := OptionButton.new()
	for character in CharacterCatalogScript.all():
		selector.add_item(character.display_name)
		selector.set_item_metadata(selector.item_count - 1, character.character_id)
	return selector


func _select_id(selector: OptionButton, character_id: String) -> void:
	if selector == null:
		return
	for index in range(selector.item_count):
		if str(selector.get_item_metadata(index)) == character_id:
			selector.select(index)
			return


func _selected_id(selector: OptionButton) -> String:
	if selector == null or selector.selected < 0:
		return "LONG_TEST"
	return str(selector.get_item_metadata(selector.selected))


func _update_preview() -> void:
	var player_one = CharacterCatalogScript.get_by_id(_selected_id(_player_one))
	if _mode == MODE_RANKED:
		_preview.text = "%s [%s / %s]" % [
			player_one.display_name,
			player_one.ahoge_type_name(),
			player_one.attack_type_name(),
		]
		return

	var player_two = CharacterCatalogScript.get_by_id(_selected_id(_player_two))
	_preview.text = "%s [%s / %s]  VS  %s [%s / %s]" % [
		player_one.display_name,
		player_one.ahoge_type_name(),
		player_one.attack_type_name(),
		player_two.display_name,
		player_two.ahoge_type_name(),
		player_two.attack_type_name(),
	]


func _on_start_pressed() -> void:
	if _mode == MODE_RANKED:
		ranked_character_selected.emit(_selected_id(_player_one))
		return
	battle_requested.emit(_selected_id(_player_one), _selected_id(_player_two))
