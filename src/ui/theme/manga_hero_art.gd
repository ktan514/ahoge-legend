extends Control

const MangaThemeScript := preload("res://src/ui/theme/manga_theme.gd")


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()


func _draw() -> void:
	if size.x <= 0 or size.y <= 0:
		return

	var rect := Rect2(Vector2.ZERO, size)
	draw_rect(rect, MangaThemeScript.PAPER_1)

	# Black comic frame.
	draw_line(Vector2(0, 0), Vector2(size.x, 0), MangaThemeScript.INK_0, 5)
	draw_line(Vector2(size.x, 0), Vector2(size.x, size.y), MangaThemeScript.INK_0, 5)
	draw_line(Vector2(size.x, size.y), Vector2(0, size.y), MangaThemeScript.INK_0, 5)
	draw_line(Vector2(0, size.y), Vector2(0, 0), MangaThemeScript.INK_0, 5)

	var center := Vector2(size.x * 0.5, size.y * 0.56)

	# Comic burst.
	for index in range(28):
		var angle := TAU * float(index) / 28.0
		var inner := center + Vector2(cos(angle), sin(angle)) * 54.0
		var outer := center + Vector2(cos(angle), sin(angle)) * (minf(size.x, size.y) * 0.48)
		var color := Color(MangaThemeScript.IMPACT_YELLOW, 0.18 if index % 2 == 0 else 0.08)
		draw_line(inner, outer, color, 4.0 if index % 2 == 0 else 2.0)

	# Two cropped head tops.
	var radius := minf(size.x, size.y) * 0.23
	var left_head := Vector2(size.x * 0.25, size.y + radius * 0.24)
	var right_head := Vector2(size.x * 0.75, size.y + radius * 0.24)
	draw_circle(left_head, radius, Color(MangaThemeScript.P1_BLUE, 0.88))
	draw_circle(right_head, radius, Color(MangaThemeScript.P2_RED, 0.88))

	# Ahoge curves are deliberately abstract vector placeholders.
	var left_root := left_head + Vector2(0, -radius + 6)
	var right_root := right_head + Vector2(0, -radius + 6)
	draw_polyline(
		PackedVector2Array([
			left_root,
			left_root + Vector2(14, -56),
			left_root + Vector2(76, -98),
			center + Vector2(-18, -26),
		]),
		MangaThemeScript.INK_0,
		12,
		true
	)
	draw_polyline(
		PackedVector2Array([
			right_root,
			right_root + Vector2(-12, -60),
			right_root + Vector2(-72, -100),
			center + Vector2(18, -26),
		]),
		MangaThemeScript.INK_0,
		12,
		true
	)
	draw_polyline(
		PackedVector2Array([
			left_root,
			left_root + Vector2(14, -56),
			left_root + Vector2(76, -98),
			center + Vector2(-18, -26),
		]),
		MangaThemeScript.P1_BLUE,
		6,
		true
	)
	draw_polyline(
		PackedVector2Array([
			right_root,
			right_root + Vector2(-12, -60),
			right_root + Vector2(-72, -100),
			center + Vector2(18, -26),
		]),
		MangaThemeScript.P2_RED,
		6,
		true
	)

	draw_circle(center, 18, MangaThemeScript.IMPACT_YELLOW)
	draw_circle(center, 9, MangaThemeScript.INK_0)
