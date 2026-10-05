extends Node2D

var fighter
var baseline_y: float = 0.0


func _draw() -> void:
	if not is_instance_valid(fighter):
		return
	var d: float = fighter.head_display_diameter()
	var origin: float = fighter.global_position.x + fighter.size.x * 0.5
	var left: float = origin - 0.5 * d
	var right: float = origin + 0.5 * d
	var actual: float = origin + fighter.facing * fighter.neck_travel_ratio * d
	draw_line(Vector2(left, baseline_y), Vector2(right, baseline_y), Color("6b7688"), 2.0, true)
	for x in [left, origin, right]:
		draw_line(Vector2(x, baseline_y - 10), Vector2(x, baseline_y + 10), Color("6b7688"), 2.0, true)
		draw_dashed_line(Vector2(x, baseline_y + 15), Vector2(x, baseline_y + 95), Color(0.4, 0.46, 0.54, 0.45), 1.0, 5.0, true)
	draw_circle(Vector2(actual, baseline_y), 6.0, Color("287cc5"))

	# 目線仰角ガイド。上向きを正として画面Yだけ反転する。
	var elevation: float = fighter.neck_gaze_elevation_degrees()
	var angle: float = deg_to_rad(elevation)
	var gaze_dir := Vector2(fighter.facing * cos(angle), -sin(angle)).normalized()
	var gaze_start := Vector2(actual, baseline_y + 28.0)
	var gaze_end := gaze_start + gaze_dir * 78.0
	draw_line(gaze_start, gaze_end, Color("d14c72"), 3.0, true)
	draw_circle(gaze_end, 4.0, Color("d14c72"))

	var font: Font = ThemeDB.fallback_font
	draw_string(font, Vector2(origin - 21, baseline_y - 18), "基準", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color("354355"))
	var left_text: String = "後ろ -0.5D" if fighter.facing > 0 else "前 +0.5D"
	var right_text: String = "前 +0.5D" if fighter.facing > 0 else "後ろ -0.5D"
	draw_string(font, Vector2(left - 55, baseline_y - 18), left_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color("354355"))
	draw_string(font, Vector2(right - 55, baseline_y - 18), right_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color("354355"))
	draw_string(font, gaze_start + Vector2(8.0, -8.0), "仰角 %+.1f°" % elevation, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color("8c2f4d"))
