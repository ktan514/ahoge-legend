extends Control

signal apply_requested(settings: Dictionary)
signal back_requested

const RESOLUTION_OPTIONS := ["1280x720", "1600x900", "1920x1080"]

var _settings: Dictionary = {}
var _defaults: Dictionary = {}

var _master_slider: HSlider
var _bgm_slider: HSlider
var _se_slider: HSlider
var _voice_slider: HSlider
var _master_value: Label
var _bgm_value: Label
var _se_value: Label
var _voice_value: Label
var _mode: OptionButton
var _resolution: OptionButton
var _vsync: CheckButton
var _status: Label


func configure(settings: Dictionary, defaults: Dictionary) -> void:
	_settings = settings.duplicate(true)
	_defaults = defaults.duplicate(true)
	if is_node_ready():
		_set_values(_settings)


func _ready() -> void:
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var root := VBoxContainer.new()
	root.custom_minimum_size = Vector2(760.0, 0.0)
	root.add_theme_constant_override("separation", 12)
	center.add_child(root)

	var title := Label.new()
	title.text = "SETTINGS"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 32)
	root.add_child(title)

	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 28)
	root.add_child(columns)

	var audio := VBoxContainer.new()
	audio.custom_minimum_size = Vector2(300.0, 0.0)
	columns.add_child(audio)
	_add_section_title(audio, "AUDIO")
	var master := _add_volume_row(audio, "Master", "MasterVolume")
	_master_slider = master[0]
	_master_value = master[1]
	var bgm := _add_volume_row(audio, "BGM", "BgmVolume")
	_bgm_slider = bgm[0]
	_bgm_value = bgm[1]
	var se := _add_volume_row(audio, "SE", "SeVolume")
	_se_slider = se[0]
	_se_value = se[1]
	var voice := _add_volume_row(audio, "Voice", "VoiceVolume")
	_voice_slider = voice[0]
	_voice_value = voice[1]

	var display := VBoxContainer.new()
	display.custom_minimum_size = Vector2(260.0, 0.0)
	columns.add_child(display)
	_add_section_title(display, "DISPLAY")
	_mode = OptionButton.new()
	_mode.name = "DisplayMode"
	_mode.add_item("Window", 0)
	_mode.add_item("Fullscreen", 1)
	_add_control_row(display, "Mode", _mode)

	_resolution = OptionButton.new()
	_resolution.name = "Resolution"
	for option in RESOLUTION_OPTIONS:
		_resolution.add_item(option)
	_add_control_row(display, "Resolution", _resolution)

	_vsync = CheckButton.new()
	_vsync.name = "VSync"
	_vsync.text = "ON"
	_vsync.toggled.connect(func(enabled: bool) -> void:
		_vsync.text = "ON" if enabled else "OFF"
	)
	_add_control_row(display, "VSync", _vsync)

	var control := VBoxContainer.new()
	control.custom_minimum_size = Vector2(190.0, 0.0)
	columns.add_child(control)
	_add_section_title(control, "CONTROL")
	var left_click := Label.new()
	left_click.text = "Left Click: Attack / Charge"
	left_click.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	control.add_child(left_click)
	var right_click := Label.new()
	right_click.text = "Right Click: Parry / Dodge"
	right_click.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	control.add_child(right_click)
	var note := Label.new()
	note.text = "Key config: later"
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	control.add_child(note)

	_status = Label.new()
	_status.name = "Status"
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(_status)

	var actions := HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	actions.add_theme_constant_override("separation", 12)
	root.add_child(actions)

	var default_button := Button.new()
	default_button.name = "DefaultButton"
	default_button.text = "DEFAULT"
	default_button.pressed.connect(func() -> void:
		_set_values(_defaults)
		set_status("DEFAULT VALUES (NOT APPLIED)")
	)
	actions.add_child(default_button)

	var apply_button := Button.new()
	apply_button.name = "ApplyButton"
	apply_button.text = "APPLY"
	apply_button.pressed.connect(func() -> void:
		set_status("APPLYING...")
		apply_requested.emit(current_values())
	)
	actions.add_child(apply_button)

	var back_button := Button.new()
	back_button.name = "BackButton"
	back_button.text = "BACK"
	back_button.pressed.connect(func() -> void:
		back_requested.emit()
	)
	actions.add_child(back_button)

	if _settings.is_empty():
		_settings = _defaults.duplicate(true)
	_set_values(_settings)


func current_values() -> Dictionary:
	return {
		"audio": {
			"master_volume": _master_slider.value,
			"bgm_volume": _bgm_slider.value,
			"se_volume": _se_slider.value,
			"voice_volume": _voice_slider.value,
		},
		"display": {
			"mode": "fullscreen" if _mode.selected == 1 else "windowed",
			"resolution": _resolution.get_item_text(_resolution.selected),
			"vsync": _vsync.button_pressed,
		},
	}


func set_status(message: String) -> void:
	if _status != null:
		_status.text = message


func _set_values(settings: Dictionary) -> void:
	if _master_slider == null:
		return
	var audio: Dictionary = settings.get("audio", {})
	var display: Dictionary = settings.get("display", {})
	_master_slider.value = float(audio.get("master_volume", 100.0))
	_bgm_slider.value = float(audio.get("bgm_volume", 100.0))
	_se_slider.value = float(audio.get("se_volume", 100.0))
	_voice_slider.value = float(audio.get("voice_volume", 100.0))

	_mode.select(1 if str(display.get("mode", "windowed")) == "fullscreen" else 0)

	var resolution := str(display.get("resolution", "1280x720"))
	var resolution_index := RESOLUTION_OPTIONS.find(resolution)
	_resolution.select(maxi(resolution_index, 0))

	_vsync.button_pressed = bool(display.get("vsync", true))
	_vsync.text = "ON" if _vsync.button_pressed else "OFF"
	_update_volume_labels()


func _add_section_title(parent: VBoxContainer, text: String) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 20)
	parent.add_child(label)


func _add_volume_row(parent: VBoxContainer, label_text: String, slider_name: String) -> Array:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	parent.add_child(row)

	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size = Vector2(70.0, 0.0)
	row.add_child(label)

	var slider := HSlider.new()
	slider.name = slider_name
	slider.min_value = 0.0
	slider.max_value = 100.0
	slider.step = 1.0
	slider.custom_minimum_size = Vector2(160.0, 0.0)
	row.add_child(slider)

	var value_label := Label.new()
	value_label.custom_minimum_size = Vector2(48.0, 0.0)
	row.add_child(value_label)

	slider.value_changed.connect(func(_value: float) -> void:
		_update_volume_labels()
	)
	return [slider, value_label]


func _add_control_row(parent: VBoxContainer, label_text: String, control: Control) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	parent.add_child(row)
	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size = Vector2(82.0, 0.0)
	row.add_child(label)
	control.custom_minimum_size = Vector2(150.0, 0.0)
	row.add_child(control)


func _update_volume_labels() -> void:
	if _master_value == null:
		return
	_master_value.text = "%d%%" % int(round(_master_slider.value))
	_bgm_value.text = "%d%%" % int(round(_bgm_slider.value))
	_se_value.text = "%d%%" % int(round(_se_slider.value))
	_voice_value.text = "%d%%" % int(round(_voice_slider.value))
