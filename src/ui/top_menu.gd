extends Control

const MangaThemeScript := preload("res://src/ui/theme/manga_theme.gd")
const MangaBackdropScript := preload("res://src/ui/theme/manga_backdrop.gd")
const MangaHeroArtScript := preload("res://src/ui/theme/manga_hero_art.gd")

signal local_test_requested
signal online_battle_requested
signal ranking_requested
signal settings_requested
signal exit_requested


func _ready() -> void:
	var backdrop = MangaBackdropScript.new()
	add_child(backdrop)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 40)
	margin.add_theme_constant_override("margin_top", 32)
	margin.add_theme_constant_override("margin_right", 40)
	margin.add_theme_constant_override("margin_bottom", 28)
	add_child(margin)

	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 20)
	margin.add_child(page)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 16)
	page.add_child(header)

	var title := Label.new()
	title.text = "AHOGE LEGEND"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	MangaThemeScript.apply_screen_title(title)
	title.add_theme_color_override("font_outline_color", MangaThemeScript.IMPACT_YELLOW)
	title.add_theme_constant_override("outline_size", 2)
	header.add_child(title)

	var kicker := Label.new()
	kicker.text = "アホ毛でつながる、熱い対戦。"
	kicker.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	MangaThemeScript.apply_caption(kicker)
	header.add_child(kicker)

	var divider := HSeparator.new()
	page.add_child(divider)

	var content := HBoxContainer.new()
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 28)
	page.add_child(content)

	var menu_panel := PanelContainer.new()
	menu_panel.custom_minimum_size = Vector2(360, 0)
	menu_panel.add_theme_stylebox_override(
		"panel",
		MangaThemeScript.dark_panel_style(MangaThemeScript.IMPACT_YELLOW)
	)
	content.add_child(menu_panel)

	var menu_margin := MarginContainer.new()
	menu_margin.add_theme_constant_override("margin_left", 24)
	menu_margin.add_theme_constant_override("margin_top", 24)
	menu_margin.add_theme_constant_override("margin_right", 24)
	menu_margin.add_theme_constant_override("margin_bottom", 24)
	menu_panel.add_child(menu_margin)

	var menu := VBoxContainer.new()
	menu.alignment = BoxContainer.ALIGNMENT_CENTER
	menu.add_theme_constant_override("separation", 14)
	menu_margin.add_child(menu)

	var section := Label.new()
	section.text = "TOP MENU"
	section.add_theme_color_override("font_color", MangaThemeScript.WHITE)
	section.add_theme_font_size_override("font_size", 18)
	menu.add_child(section)

	var online_button := Button.new()
	online_button.name = "OnlineBattleButton"
	online_button.text = "対戦する"
	online_button.tooltip_text = "オンライン対戦へ進む"
	online_button.pressed.connect(func() -> void:
		online_battle_requested.emit()
	)
	MangaThemeScript.apply_primary_button(online_button)
	menu.add_child(online_button)

	var ranking_button := Button.new()
	ranking_button.name = "RankingButton"
	ranking_button.text = "ランキング"
	ranking_button.pressed.connect(func() -> void:
		ranking_requested.emit()
	)
	MangaThemeScript.apply_secondary_button(ranking_button)
	menu.add_child(ranking_button)

	var settings_button := Button.new()
	settings_button.name = "SettingsButton"
	settings_button.text = "設定"
	settings_button.pressed.connect(func() -> void:
		settings_requested.emit()
	)
	MangaThemeScript.apply_secondary_button(settings_button)
	menu.add_child(settings_button)

	var exit_button := Button.new()
	exit_button.name = "ExitButton"
	exit_button.text = "ゲームを終了"
	exit_button.pressed.connect(func() -> void:
		exit_requested.emit()
	)
	MangaThemeScript.apply_secondary_button(exit_button)
	menu.add_child(exit_button)

	if OS.is_debug_build():
		var debug_divider := HSeparator.new()
		menu.add_child(debug_divider)
		var debug_label := Label.new()
		debug_label.text = "DEBUG"
		debug_label.add_theme_color_override("font_color", MangaThemeScript.PAPER_2)
		debug_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		MangaThemeScript.apply_caption(debug_label)
		menu.add_child(debug_label)

		var local_button := Button.new()
		local_button.name = "LocalTestButton"
		local_button.text = "LOCAL TEST BATTLE"
		local_button.pressed.connect(func() -> void:
			local_test_requested.emit()
		)
		MangaThemeScript.apply_secondary_button(local_button)
		menu.add_child(local_button)

	var hero_panel := PanelContainer.new()
	hero_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hero_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	hero_panel.add_theme_stylebox_override(
		"panel",
		MangaThemeScript.panel_style(MangaThemeScript.PAPER_1, MangaThemeScript.INK_0, 4, true)
	)
	content.add_child(hero_panel)

	var hero_stack := VBoxContainer.new()
	hero_stack.add_theme_constant_override("separation", 12)
	hero_panel.add_child(hero_stack)

	var hero := MangaHeroArtScript.new()
	hero.custom_minimum_size = Vector2(540, 360)
	hero.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hero.size_flags_vertical = Control.SIZE_EXPAND_FILL
	hero_stack.add_child(hero)

	var hero_copy := Label.new()
	hero_copy.text = "小さなアホ毛で、でっかく熱く。"
	hero_copy.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hero_copy.add_theme_font_size_override("font_size", 24)
	hero_copy.add_theme_color_override("font_color", MangaThemeScript.INK_0)
	hero_stack.add_child(hero_copy)

	var footer := HBoxContainer.new()
	page.add_child(footer)

	var fan_note := Label.new()
	fan_note.text = "AHOGE LEGEND  /  hololive fan game prototype"
	fan_note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	MangaThemeScript.apply_caption(fan_note)
	footer.add_child(fan_note)

	var tagline := Label.new()
	tagline.text = "PLAY WITH YOUR AHOGE."
	MangaThemeScript.apply_caption(tagline)
	footer.add_child(tagline)
