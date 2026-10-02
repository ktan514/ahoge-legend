extends Control

const CharacterCatalogScript := preload("res://src/domain/character_catalog.gd")
const MangaThemeScript := preload("res://src/ui/theme/manga_theme.gd")
const MangaBackdropScript := preload("res://src/ui/theme/manga_backdrop.gd")
const MangaCharacterArtScript := preload("res://src/ui/theme/manga_character_art.gd")

signal battle_requested(player_one_id: String, player_two_id: String)
signal ranked_character_selected(character_id: String)
signal friend_character_selected(character_id: String)
signal back_requested

const MODE_LOCAL := "local"
const MODE_RANKED := "ranked"
const MODE_FRIEND := "friend"

var _mode: String = MODE_LOCAL
var _selected_player_one_id: String = "LONG_TEST"
var _selected_player_two_id: String = "SHORT_TEST"
var _character_buttons: Dictionary = {}
var _preview_title: Label
var _preview_detail: Label
var _preview_art
var _local_player_two: OptionButton


func configure(player_one_id: String, player_two_id: String) -> void:
	set_meta("mode", MODE_LOCAL)
	set_meta("initial_player_one", player_one_id)
	set_meta("initial_player_two", player_two_id)


func configure_ranked(character_id: String) -> void:
	set_meta("mode", MODE_RANKED)
	set_meta("initial_player_one", character_id)


func configure_friend(character_id: String) -> void:
	set_meta("mode", MODE_FRIEND)
	set_meta("initial_player_one", character_id)


func _ready() -> void:
	_mode = str(get_meta("mode", MODE_LOCAL))
	_selected_player_one_id = str(get_meta("initial_player_one", "LONG_TEST"))
	_selected_player_two_id = str(get_meta("initial_player_two", "SHORT_TEST"))

	var backdrop = MangaBackdropScript.new()
	add_child(backdrop)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 40)
	margin.add_theme_constant_override("margin_top", 28)
	margin.add_theme_constant_override("margin_right", 40)
	margin.add_theme_constant_override("margin_bottom", 28)
	add_child(margin)

	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 18)
	margin.add_child(page)

	var header := HBoxContainer.new()
	page.add_child(header)

	var title := Label.new()
	title.text = "キャラクターを選ぶ"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	MangaThemeScript.apply_screen_title(title)
	header.add_child(title)

	var mode_badge := Label.new()
	mode_badge.text = _mode_label()
	mode_badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	mode_badge.add_theme_font_size_override("font_size", 18)
	mode_badge.add_theme_color_override("font_color", MangaThemeScript.INK_0)
	header.add_child(mode_badge)

	var divider := HSeparator.new()
	page.add_child(divider)

	if _mode == MODE_LOCAL:
		_build_local_debug(page)
	else:
		_build_online_cards(page)

	var actions := HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_END
	actions.add_theme_constant_override("separation", 16)
	page.add_child(actions)

	var back := Button.new()
	back.name = "BackButton"
	back.text = "戻る"
	back.pressed.connect(func() -> void:
		back_requested.emit()
	)
	MangaThemeScript.apply_back_button(back)
	actions.add_child(back)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.add_child(spacer)

	var decide := Button.new()
	decide.name = "DecideButton"
	decide.text = "決定" if _mode != MODE_LOCAL else "ローカル対戦開始"
	decide.pressed.connect(_on_start_pressed)
	MangaThemeScript.apply_primary_button(decide)
	decide.custom_minimum_size.x = 220
	actions.add_child(decide)

	_update_selection_visuals()
	_update_preview()


func _build_online_cards(parent: VBoxContainer) -> void:
	var content := HBoxContainer.new()
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 24)
	parent.add_child(content)

	var card_panel := PanelContainer.new()
	card_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card_panel.add_theme_stylebox_override(
		"panel",
		MangaThemeScript.panel_style(MangaThemeScript.PAPER_0, MangaThemeScript.INK_0, 3, true)
	)
	content.add_child(card_panel)

	var card_margin := MarginContainer.new()
	card_margin.add_theme_constant_override("margin_left", 18)
	card_margin.add_theme_constant_override("margin_top", 18)
	card_margin.add_theme_constant_override("margin_right", 18)
	card_margin.add_theme_constant_override("margin_bottom", 18)
	card_panel.add_child(card_margin)

	var cards := GridContainer.new()
	cards.columns = 2
	cards.add_theme_constant_override("h_separation", 16)
	cards.add_theme_constant_override("v_separation", 16)
	card_margin.add_child(cards)

	for character in CharacterCatalogScript.all():
		var button := Button.new()
		button.name = "Character_%s" % character.character_id
		button.text = ""
		button.custom_minimum_size = Vector2(240, 190)
		button.pressed.connect(_select_character.bind(character.character_id))
		MangaThemeScript.apply_secondary_button(button)
		cards.add_child(button)

		var button_margin := MarginContainer.new()
		button_margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		button_margin.add_theme_constant_override("margin_left", 12)
		button_margin.add_theme_constant_override("margin_top", 10)
		button_margin.add_theme_constant_override("margin_right", 12)
		button_margin.add_theme_constant_override("margin_bottom", 10)
		button.add_child(button_margin)

		var card_box := VBoxContainer.new()
		card_box.add_theme_constant_override("separation", 4)
		button_margin.add_child(card_box)

		var card_art = MangaCharacterArtScript.new()
		card_art.name = "CharacterArt_%s" % character.character_id
		card_art.custom_minimum_size = Vector2(196, 102)
		card_art.configure(character, false)
		card_box.add_child(card_art)

		var card_name := Label.new()
		card_name.text = character.display_name
		card_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		card_name.add_theme_font_size_override("font_size", 18)
		card_box.add_child(card_name)

		var card_types := Label.new()
		card_types.text = "%s / %s" % [
			character.ahoge_type_name(),
			character.attack_type_name(),
		]
		card_types.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		MangaThemeScript.apply_caption(card_types)
		card_box.add_child(card_types)

		_set_mouse_passthrough(button_margin)
		_character_buttons[character.character_id] = button

	var preview_panel := PanelContainer.new()
	preview_panel.custom_minimum_size = Vector2(420, 0)
	preview_panel.add_theme_stylebox_override(
		"panel",
		MangaThemeScript.dark_panel_style(MangaThemeScript.IMPACT_YELLOW)
	)
	content.add_child(preview_panel)

	var preview_box := VBoxContainer.new()
	preview_box.add_theme_constant_override("separation", 12)
	preview_panel.add_child(preview_box)

	_preview_art = MangaCharacterArtScript.new()
	_preview_art.name = "SelectedCharacterArt"
	_preview_art.custom_minimum_size = Vector2(380, 260)
	preview_box.add_child(_preview_art)

	_preview_title = Label.new()
	_preview_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_preview_title.add_theme_font_size_override("font_size", 28)
	_preview_title.add_theme_color_override("font_color", MangaThemeScript.WHITE)
	preview_box.add_child(_preview_title)

	_preview_detail = Label.new()
	_preview_detail.name = "SelectedCharacterDetail"
	_preview_detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_preview_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_preview_detail.add_theme_color_override("font_color", MangaThemeScript.PAPER_1)
	preview_box.add_child(_preview_detail)


func _build_local_debug(parent: VBoxContainer) -> void:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override(
		"panel",
		MangaThemeScript.panel_style(MangaThemeScript.PAPER_0, MangaThemeScript.INK_0, 3, true)
	)
	parent.add_child(panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 16)
	panel.add_child(box)

	var note := Label.new()
	note.text = "DEBUG / ローカル対戦"
	MangaThemeScript.apply_section_title(note)
	box.add_child(note)

	var p1 := OptionButton.new()
	for character in CharacterCatalogScript.all():
		p1.add_item(character.display_name)
		p1.set_item_metadata(p1.item_count - 1, character.character_id)
	_select_id(p1, _selected_player_one_id)
	p1.item_selected.connect(func(_index: int) -> void:
		_selected_player_one_id = _selected_id(p1)
	)
	box.add_child(p1)

	_local_player_two = OptionButton.new()
	for character in CharacterCatalogScript.all():
		_local_player_two.add_item(character.display_name)
		_local_player_two.set_item_metadata(_local_player_two.item_count - 1, character.character_id)
	_select_id(_local_player_two, _selected_player_two_id)
	_local_player_two.item_selected.connect(func(_index: int) -> void:
		_selected_player_two_id = _selected_id(_local_player_two)
	)
	box.add_child(_local_player_two)


func _select_character(character_id: String) -> void:
	_selected_player_one_id = character_id
	_update_selection_visuals()
	_update_preview()


func _update_selection_visuals() -> void:
	for character_id in _character_buttons.keys():
		var button: Button = _character_buttons[character_id]
		if str(character_id) == _selected_player_one_id:
			MangaThemeScript.apply_primary_button(button)
		else:
			MangaThemeScript.apply_secondary_button(button)


func _update_preview() -> void:
	if _preview_title == null or _preview_detail == null:
		return
	var character = CharacterCatalogScript.get_by_id(_selected_player_one_id)
	if character == null:
		return
	_preview_title.text = character.display_name
	if _preview_art != null:
		_preview_art.configure(character, true)
	var feature_text := character.feature_text
	if feature_text.is_empty():
		feature_text = "アホ毛の形と戦い方で選ぼう。"
	_preview_detail.text = "%s\n\nアホ毛タイプ: %s\n攻撃タイプ: %s" % [
		feature_text,
		character.ahoge_type_name(),
		character.attack_type_name(),
	]


func _set_mouse_passthrough(control: Control) -> void:
	control.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child in control.get_children():
		if child is Control:
			_set_mouse_passthrough(child)


func _mode_label() -> String:
	if _mode == MODE_RANKED:
		return "ランクマッチ"
	if _mode == MODE_FRIEND:
		return "フレンド対戦"
	return "ローカルテスト"


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


func _on_start_pressed() -> void:
	if _mode == MODE_RANKED:
		ranked_character_selected.emit(_selected_player_one_id)
		return
	if _mode == MODE_FRIEND:
		friend_character_selected.emit(_selected_player_one_id)
		return
	battle_requested.emit(_selected_player_one_id, _selected_player_two_id)
