extends Control

const CharacterDefinitionScript := preload("res://src/domain/character_definition.gd")
const MangaThemeScript := preload("res://src/ui/theme/manga_theme.gd")

var character = null
var animate: bool = false
var _phase: float = 0.0


func configure(character_value, animate_value: bool = false) -> void:
	character = character_value
	animate = animate_value
	set_process(animate)
	queue_redraw()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(animate)
	queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()


func _process(delta: float) -> void:
	if not animate or delta <= 0.0:
		return
	_phase += delta
	queue_redraw()


func _draw() -> void:
	if character == null or size.x <= 0.0 or size.y <= 0.0:
		return

	var head_radius := minf(size.x * 0.30, size.y * 0.43)
	var head_center := Vector2(size.x * 0.5, size.y + head_radius * 0.10)
	var ink := MangaThemeScript.INK_0
	var hair := MangaThemeScript.PAPER_2
	var highlight := MangaThemeScript.PAPER_0

	# 顔は描かず、画面下端から頭頂部だけを見せる。
	draw_circle(head_center, head_radius + 4.0, ink)
	draw_circle(head_center, head_radius, hair)

	var crown_y := head_center.y - head_radius * 0.58
	draw_arc(
		head_center + Vector2(-head_radius * 0.14, -head_radius * 0.10),
		head_radius * 0.62,
		PI * 1.10,
		PI * 1.72,
		20,
		highlight,
		maxf(3.0, head_radius * 0.08),
		true
	)
	for index in range(3):
		var x := head_center.x - head_radius * 0.38 + float(index) * head_radius * 0.36
		draw_line(
			Vector2(x, crown_y),
			Vector2(x + 7.0, crown_y - 10.0 - float(index % 2) * 6.0),
			MangaThemeScript.INK_2,
			maxf(2.0, head_radius * 0.04),
			true
		)

	var length_ratio := 0.72
	match character.ahoge_type:
		CharacterDefinitionScript.AhogeType.LONG:
			length_ratio = 0.86
		CharacterDefinitionScript.AhogeType.NORMAL:
			length_ratio = 0.70
		CharacterDefinitionScript.AhogeType.SHORT:
			length_ratio = 0.48

	var max_length := minf(size.y * length_ratio, size.x * 0.46)
	var sway := sin(_phase * 2.8) * minf(10.0, size.x * 0.04) if animate else 0.0
	var root := head_center + Vector2(0.0, -head_radius + 4.0)
	var middle := root + Vector2(size.x * 0.06 + sway * 0.35, -max_length * 0.52)
	var tip := root + Vector2(size.x * 0.14 + sway, -max_length)

	var outer_width := maxf(7.0, size.x * 0.035)
	var inner_width := maxf(3.0, outer_width * 0.52)
	draw_line(root, middle, ink, outer_width, true)
	draw_line(middle, tip, ink, outer_width * 0.86, true)
	draw_line(root, middle, MangaThemeScript.IMPACT_YELLOW, inner_width, true)
	draw_line(middle, tip, MangaThemeScript.IMPACT_YELLOW, inner_width * 0.84, true)

	# THROW型は投擲方向を示す小さなmotion cueだけを追加する。
	if character.attack_type == CharacterDefinitionScript.AttackType.THROW:
		var cue_start := tip + Vector2(10.0, 8.0)
		for index in range(2):
			var offset := Vector2(float(index) * 9.0, float(index) * 5.0)
			draw_line(
				cue_start + offset,
				cue_start + offset + Vector2(18.0, 7.0),
				MangaThemeScript.INK_2,
				2.0,
				true
			)
