extends Control

const MangaThemeScript := preload("res://src/ui/theme/manga_theme.gd")

var _dark: bool = false


func configure(dark: bool = false) -> void:
	_dark = dark
	queue_redraw()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()


func _draw() -> void:
	var background := MangaThemeScript.INK_0 if _dark else MangaThemeScript.PAPER_0
	var ink := MangaThemeScript.WHITE if _dark else MangaThemeScript.INK_0
	draw_rect(Rect2(Vector2.ZERO, size), background)

	# Halftone dots: corners only, so content stays readable.
	var dot_color := Color(ink, 0.055 if not _dark else 0.04)
	var spacing := 24.0
	for x in range(0, int(minf(size.x * 0.34, 460.0)), int(spacing)):
		for y in range(0, int(minf(size.y * 0.28, 260.0)), int(spacing)):
			var radius := 1.5 + float((x + y) % 48) / 48.0 * 2.0
			draw_circle(Vector2(x + 12, y + 12), radius, dot_color)

	# Manga slashes at top-right / bottom-left.
	var slash_color := Color(MangaThemeScript.IMPACT_YELLOW, 0.16 if not _dark else 0.10)
	for index in range(7):
		var offset := float(index) * 42.0
		var p1 := Vector2(size.x - 360.0 + offset, 0.0)
		var p2 := Vector2(size.x - 300.0 + offset, 0.0)
		var p3 := Vector2(size.x - 460.0 + offset, 180.0)
		var p4 := Vector2(size.x - 520.0 + offset, 180.0)
		draw_colored_polygon(PackedVector2Array([p1, p2, p3, p4]), slash_color)

	var line_color := Color(ink, 0.10)
	draw_line(Vector2(0, size.y - 72), Vector2(size.x * 0.36, size.y), line_color, 2)
	draw_line(Vector2(0, size.y - 44), Vector2(size.x * 0.28, size.y), line_color, 2)
