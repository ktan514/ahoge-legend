extends RefCounted

const PAPER_0 := Color("#fff8e8")
const PAPER_1 := Color("#f3e9d4")
const PAPER_2 := Color("#ded2ba")
const INK_0 := Color("#151515")
const INK_1 := Color("#2a2a2a")
const INK_2 := Color("#4a4a4a")
const IMPACT_YELLOW := Color("#ffd43b")
const P1_BLUE := Color("#3f86ff")
const P2_RED := Color("#ff4f58")
const DANGER := Color("#d73535")
const SUCCESS := Color("#2d9b59")
const INFO := Color("#2e73d2")
const WHITE := Color("#ffffff")


static func build_theme() -> Theme:
	var value := Theme.new()
	value.default_font_size = 16

	value.set_color("font_color", "Label", INK_0)
	value.set_color("font_shadow_color", "Label", Color(0, 0, 0, 0))
	value.set_font_size("font_size", "Label", 16)

	_apply_button_theme(value, "Button")
	_apply_button_theme(value, "OptionButton")

	var panel := panel_style(PAPER_0, INK_0, 3, true)
	value.set_stylebox("panel", "PanelContainer", panel)
	value.set_stylebox("panel", "Panel", panel)

	var line_normal := panel_style(PAPER_0, INK_0, 2, false)
	line_normal.content_margin_left = 14
	line_normal.content_margin_right = 14
	line_normal.content_margin_top = 10
	line_normal.content_margin_bottom = 10
	value.set_stylebox("normal", "LineEdit", line_normal)
	var line_focus := panel_style(PAPER_0, IMPACT_YELLOW, 4, false)
	line_focus.content_margin_left = 12
	line_focus.content_margin_right = 12
	line_focus.content_margin_top = 8
	line_focus.content_margin_bottom = 8
	value.set_stylebox("focus", "LineEdit", line_focus)
	value.set_color("font_color", "LineEdit", INK_0)
	value.set_color("caret_color", "LineEdit", INK_0)
	value.set_color("selection_color", "LineEdit", Color(IMPACT_YELLOW, 0.6))

	var slider := StyleBoxFlat.new()
	slider.bg_color = INK_2
	slider.corner_radius_top_left = 3
	slider.corner_radius_top_right = 3
	slider.corner_radius_bottom_left = 3
	slider.corner_radius_bottom_right = 3
	slider.content_margin_top = 3
	slider.content_margin_bottom = 3
	value.set_stylebox("slider", "HSlider", slider)

	value.set_constant("separation", "VBoxContainer", 16)
	value.set_constant("separation", "HBoxContainer", 16)
	return value


static func apply_primary_button(button: Button) -> void:
	_apply_button_override(button, IMPACT_YELLOW, Color("#ffe472"), INK_0, WHITE)
	button.custom_minimum_size.y = 60.0
	button.add_theme_font_size_override("font_size", 20)


static func apply_secondary_button(button: Button) -> void:
	_apply_button_override(button, PAPER_0, PAPER_1, INK_0, WHITE)
	button.custom_minimum_size.y = 52.0
	button.add_theme_font_size_override("font_size", 18)


static func apply_destructive_button(button: Button) -> void:
	_apply_button_override(button, DANGER, Color("#eb4d4d"), WHITE, WHITE)
	button.custom_minimum_size.y = 52.0
	button.add_theme_font_size_override("font_size", 18)


static func apply_back_button(button: Button) -> void:
	apply_secondary_button(button)
	button.custom_minimum_size = Vector2(132.0, 48.0)


static func apply_screen_title(label: Label) -> void:
	label.add_theme_font_size_override("font_size", 40)
	label.add_theme_color_override("font_color", INK_0)
	label.add_theme_constant_override("outline_size", 0)


static func apply_section_title(label: Label) -> void:
	label.add_theme_font_size_override("font_size", 24)
	label.add_theme_color_override("font_color", INK_0)


static func apply_caption(label: Label) -> void:
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", INK_2)


static func apply_impact_label(label: Label, color: Color = IMPACT_YELLOW) -> void:
	label.add_theme_font_size_override("font_size", 56)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", INK_0)
	label.add_theme_constant_override("outline_size", 8)


static func panel_style(
	background: Color = PAPER_0,
	border: Color = INK_0,
	border_width: int = 3,
	with_shadow: bool = true
) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.border_width_left = border_width
	style.border_width_top = border_width
	style.border_width_right = border_width
	style.border_width_bottom = border_width
	style.corner_radius_top_left = 2
	style.corner_radius_top_right = 2
	style.corner_radius_bottom_left = 2
	style.corner_radius_bottom_right = 2
	style.content_margin_left = 20
	style.content_margin_right = 20
	style.content_margin_top = 16
	style.content_margin_bottom = 16
	if with_shadow:
		style.shadow_color = INK_0
		style.shadow_size = 4
		style.shadow_offset = Vector2(5, 5)
	return style


static func dark_panel_style(accent: Color = IMPACT_YELLOW) -> StyleBoxFlat:
	var style := panel_style(INK_1, accent, 3, true)
	return style


static func _apply_button_theme(theme: Theme, type_name: String) -> void:
	theme.set_color("font_color", type_name, INK_0)
	theme.set_color("font_hover_color", type_name, INK_0)
	theme.set_color("font_pressed_color", type_name, INK_0)
	theme.set_color("font_disabled_color", type_name, Color(INK_2, 0.6))
	theme.set_font_size("font_size", type_name, 18)
	theme.set_stylebox("normal", type_name, _button_style(PAPER_0, INK_0, 2, Vector2(4, 4)))
	theme.set_stylebox("hover", type_name, _button_style(IMPACT_YELLOW, INK_0, 3, Vector2(5, 5)))
	theme.set_stylebox("pressed", type_name, _button_style(IMPACT_YELLOW, INK_0, 3, Vector2(1, 1)))
	theme.set_stylebox("disabled", type_name, _button_style(PAPER_2, Color(INk_2 if false else INK_2, 0.55), 2, Vector2.ZERO))
	theme.set_stylebox("focus", type_name, _button_style(PAPER_0, IMPACT_YELLOW, 4, Vector2(4, 4)))


static func _apply_button_override(
	button: Button,
	normal_color: Color,
	hover_color: Color,
	font_color: Color,
	reverse_font_color: Color
) -> void:
	button.add_theme_stylebox_override("normal", _button_style(normal_color, INK_0, 3, Vector2(5, 5)))
	button.add_theme_stylebox_override("hover", _button_style(hover_color, INK_0, 4, Vector2(6, 6)))
	button.add_theme_stylebox_override("pressed", _button_style(hover_color, INK_0, 4, Vector2(1, 1)))
	button.add_theme_stylebox_override("disabled", _button_style(PAPER_2, Color(INK_2, 0.6), 2, Vector2.ZERO))
	button.add_theme_color_override("font_color", font_color)
	button.add_theme_color_override("font_hover_color", font_color)
	button.add_theme_color_override("font_pressed_color", font_color)
	button.add_theme_color_override("font_disabled_color", Color(INK_2, 0.65))
	if normal_color == DANGER:
		button.add_theme_color_override("font_color", reverse_font_color)
		button.add_theme_color_override("font_hover_color", reverse_font_color)
		button.add_theme_color_override("font_pressed_color", reverse_font_color)


static func _button_style(
	background: Color,
	border: Color,
	border_width: int,
	shadow_offset: Vector2
) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.border_width_left = border_width
	style.border_width_top = border_width
	style.border_width_right = border_width
	style.border_width_bottom = border_width
	style.corner_radius_top_left = 2
	style.corner_radius_top_right = 2
	style.corner_radius_bottom_left = 2
	style.corner_radius_bottom_right = 2
	style.content_margin_left = 18
	style.content_margin_right = 18
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	if shadow_offset != Vector2.ZERO:
		style.shadow_color = INK_0
		style.shadow_size = 3
		style.shadow_offset = shadow_offset
	return style
