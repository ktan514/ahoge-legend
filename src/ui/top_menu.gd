extends Control

signal local_test_requested
signal online_battle_requested
signal ranking_requested
signal settings_requested
signal exit_requested

const LOGO_TEXTURE: Texture2D = preload("res://assets/ui/top_menu/logo_ahoge_legend.png")

const BUTTON_NORMAL: Texture2D = preload("res://assets/ui/top_menu/btn_menu_normal.png")
const BUTTON_FOCUS: Texture2D = preload("res://assets/ui/top_menu/btn_menu_focus.png")
const BUTTON_PRESSED: Texture2D = preload("res://assets/ui/top_menu/btn_menu_pressed.png")
const BUTTON_DISABLED: Texture2D = preload("res://assets/ui/top_menu/btn_menu_disabled.png")

const LABEL_BATTLE: Texture2D = preload("res://assets/ui/top_menu/label_battle.png")
const LABEL_RANKING: Texture2D = preload("res://assets/ui/top_menu/label_ranking.png")
const LABEL_SETTINGS: Texture2D = preload("res://assets/ui/top_menu/label_settings.png")
const LABEL_EXIT: Texture2D = preload("res://assets/ui/top_menu/label_exit.png")

const MENU_WIDTH := 430.0
const MENU_BUTTON_SIZE := Vector2(410.0, 82.0)
const MENU_ROW_SIZE := Vector2(430.0, 86.0)
const FOCUS_OFFSET_X := 10.0
const FOCUS_DURATION := 0.10
const PRESS_PUSH_X := 6.0
const PRESS_SHAKE_X := 2.0

var _button_tweens: Dictionary = {}


func _ready() -> void:
	_build_background()
	var online_button := _build_menu()
	online_button.call_deferred("grab_focus")


func _build_background() -> void:
	var background := ColorRect.new()
	background.name = "TopMenuBackgroundPlaceholder"
	background.color = Color("#08121f")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)


func _build_menu() -> TextureButton:
	var safe_margin := MarginContainer.new()
	safe_margin.name = "TopMenuSafeArea"
	safe_margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	safe_margin.add_theme_constant_override("margin_left", 54)
	safe_margin.add_theme_constant_override("margin_top", 38)
	safe_margin.add_theme_constant_override("margin_right", 54)
	safe_margin.add_theme_constant_override("margin_bottom", 38)
	add_child(safe_margin)

	var horizontal := HBoxContainer.new()
	horizontal.add_theme_constant_override("separation", 30)
	safe_margin.add_child(horizontal)

	var left := VBoxContainer.new()
	left.name = "MenuColumn"
	left.custom_minimum_size.x = MENU_WIDTH
	left.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_theme_constant_override("separation", 8)
	horizontal.add_child(left)

	var logo := TextureRect.new()
	logo.name = "LogoTexture"
	logo.texture = LOGO_TEXTURE
	logo.custom_minimum_size = Vector2(MENU_WIDTH, 205)
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	left.add_child(logo)

	var spacer := Control.new()
	spacer.custom_minimum_size.y = 14
	left.add_child(spacer)

	var menu := VBoxContainer.new()
	menu.name = "MenuButtons"
	menu.add_theme_constant_override("separation", 6)
	left.add_child(menu)

	var online_button := _add_menu_button(
		menu,
		"OnlineBattleButton",
		LABEL_BATTLE,
		"オンライン対戦へ進む",
		Callable(self, "_on_online_battle_pressed")
	)
	_add_menu_button(
		menu,
		"RankingButton",
		LABEL_RANKING,
		"ランキングを表示する",
		Callable(self, "_on_ranking_pressed")
	)
	_add_menu_button(
		menu,
		"SettingsButton",
		LABEL_SETTINGS,
		"設定を開く",
		Callable(self, "_on_settings_pressed")
	)
	_add_menu_button(
		menu,
		"ExitButton",
		LABEL_EXIT,
		"ゲームを終了する",
		Callable(self, "_on_exit_pressed")
	)

	if _show_debug_menu():
		var debug_button := Button.new()
		debug_button.name = "LocalTestButton"
		debug_button.text = "DEBUG: LOCAL TEST BATTLE"
		debug_button.custom_minimum_size = Vector2(MENU_WIDTH, 42)
		debug_button.pressed.connect(_on_local_test_pressed)
		menu.add_child(debug_button)

	var right_spacer := Control.new()
	right_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	horizontal.add_child(right_spacer)

	return online_button


func _add_menu_button(
	menu: VBoxContainer,
	button_name: String,
	label_texture: Texture2D,
	tooltip: String,
	callback: Callable
) -> TextureButton:
	var row := Control.new()
	row.name = "%sRow" % button_name
	row.custom_minimum_size = MENU_ROW_SIZE
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	menu.add_child(row)

	var button := TextureButton.new()
	button.name = button_name
	button.position = Vector2.ZERO
	button.size = MENU_BUTTON_SIZE
	button.texture_normal = BUTTON_NORMAL
	button.texture_hover = BUTTON_FOCUS
	button.texture_focused = BUTTON_FOCUS
	button.texture_pressed = BUTTON_PRESSED
	button.texture_disabled = BUTTON_DISABLED
	button.ignore_texture_size = true
	button.stretch_mode = TextureButton.STRETCH_SCALE
	button.focus_mode = Control.FOCUS_ALL
	button.tooltip_text = tooltip
	button.mouse_entered.connect(_on_menu_button_mouse_entered.bind(button))
	button.focus_entered.connect(_on_menu_button_focus_changed.bind(button, true))
	button.focus_exited.connect(_on_menu_button_focus_changed.bind(button, false))
	button.button_down.connect(_on_menu_button_down.bind(button))
	button.pressed.connect(callback)
	row.add_child(button)

	var label := TextureRect.new()
	label.name = "LabelTexture"
	label.texture = label_texture
	label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	label.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	label.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(label)

	return button


func _on_menu_button_mouse_entered(button: TextureButton) -> void:
	if not button.disabled:
		button.grab_focus()


func _on_menu_button_focus_changed(button: TextureButton, focused: bool) -> void:
	_stop_button_tween(button)
	var tween := create_tween()
	_button_tweens[button.get_instance_id()] = tween
	var target_x := FOCUS_OFFSET_X if focused else 0.0
	tween.tween_property(
		button,
		"position",
		Vector2(target_x, 0.0),
		FOCUS_DURATION
	).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func _on_menu_button_down(button: TextureButton) -> void:
	_stop_button_tween(button)
	var tween := create_tween()
	_button_tweens[button.get_instance_id()] = tween
	var base_x := FOCUS_OFFSET_X if button.has_focus() else 0.0
	tween.tween_property(button, "position", Vector2(base_x + PRESS_PUSH_X, 0.0), 0.035)
	tween.tween_property(button, "position", Vector2(base_x - PRESS_SHAKE_X, 0.0), 0.025)
	tween.tween_property(button, "position", Vector2(base_x + PRESS_SHAKE_X, 0.0), 0.025)
	tween.tween_property(button, "position", Vector2(base_x, 0.0), 0.035)


func _stop_button_tween(button: TextureButton) -> void:
	var instance_id := button.get_instance_id()
	var current = _button_tweens.get(instance_id)
	if current is Tween and current.is_valid():
		current.kill()
	_button_tweens.erase(instance_id)


func _show_debug_menu() -> bool:
	return OS.is_debug_build() and OS.get_cmdline_user_args().has("--show-debug-menu")


func _on_online_battle_pressed() -> void:
	online_battle_requested.emit()


func _on_ranking_pressed() -> void:
	ranking_requested.emit()


func _on_settings_pressed() -> void:
	settings_requested.emit()


func _on_exit_pressed() -> void:
	exit_requested.emit()


func _on_local_test_pressed() -> void:
	local_test_requested.emit()
