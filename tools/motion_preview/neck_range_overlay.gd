extends Node2D

var fighter
var baseline_y: float = 0.0


func _draw() -> void:
	if not is_instance_valid(fighter):
		return
	var d: float = fighter.head_display_diameter()
	var origin: float = fighter.global_position.x + fighter.size.x * 0.5
	var left: float = origin - 0.4 * d
	var right: float = origin + 0.4 * d
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

	# 頭画像の実アンカーとアホ毛根元を重ねて表示する。
	var head_anchor: Vector2 = to_local(fighter.ahoge_head_anchor_canvas_position())
	var ahoge_root: Vector2 = to_local(fighter.ahoge_root_canvas_position())
	var root_error: float = head_anchor.distance_to(ahoge_root)
	draw_circle(head_anchor, 7.0, Color("e24b5b"))
	draw_circle(ahoge_root, 3.5, Color("2f8bd8"))
	if root_error > 0.25:
		draw_line(head_anchor, ahoge_root, Color("7d3fd1"), 2.0, true)
	var head_up: Vector2 = fighter.head_attachment_up_canvas_direction()
	var ahoge_up: Vector2 = fighter.ahoge_attachment_up_canvas_direction()
	var head_up_local: Vector2 = (to_local(fighter.ahoge_head_anchor_canvas_position() + head_up * 62.0) - head_anchor).normalized()
	var ahoge_up_local: Vector2 = (to_local(fighter.ahoge_root_canvas_position() + ahoge_up * 62.0) - ahoge_root).normalized()
	var dot_value: float = clampf(head_up.dot(ahoge_up), -1.0, 1.0)
	var angle_error_degrees: float = rad_to_deg(acos(dot_value))
	draw_line(head_anchor, head_anchor + head_up_local * 62.0, Color("e24b5b"), 3.0, true)
	draw_line(ahoge_root, ahoge_root + ahoge_up_local * 48.0, Color("2f8bd8"), 2.0, true)

	var font: Font = ThemeDB.fallback_font
	draw_string(font, Vector2(origin - 21, baseline_y - 18), "基準", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color("354355"))
	var left_text: String = "後ろ -0.4D" if fighter.facing > 0 else "前 +0.4D"
	var right_text: String = "前 +0.4D" if fighter.facing > 0 else "後ろ -0.4D"
	draw_string(font, Vector2(left - 55, baseline_y - 18), left_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color("354355"))
	draw_string(font, Vector2(right - 55, baseline_y - 18), right_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color("354355"))
	draw_string(font, gaze_start + Vector2(8.0, -8.0), "仰角 %+.1f°" % elevation, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color("8c2f4d"))
	draw_string(font, head_anchor + Vector2(12.0, -8.0), "根元誤差 %.3fpx / 角度差 %.3f°" % [root_error, angle_error_degrees], HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color("6b2f7d"))
