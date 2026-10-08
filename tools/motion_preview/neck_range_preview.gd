extends Control

# 実BattleHUDのfighterをそのまま使用し、中央へ置いて首の可動域だけを確認する。
const HudScene := preload("res://scenes/screens/battle/BattleHUD.tscn")
const ConfigScript := preload("res://src/config/combat_config.gd")
const StateScript := preload("res://src/domain/combatant_state.gd")
const CatalogScript := preload("res://src/domain/character_catalog.gd")
const OverlayScript := preload("res://tools/motion_preview/neck_range_overlay.gd")
const SCENE: String = "res://tools/motion_preview/NeckRangePreview.tscn"
const REAR_HOLD_SECONDS: float = 0.30
const STRIKE_SWING_SECONDS: float = 0.15
const FRONT_HOLD_SECONDS: float = 0.30
const RESET_SECONDS: float = 0.30
const PRELOAD_CONTRACTION: float = -0.035
const STRIKE_STRETCH: float = 0.30
const FRONT_RESIDUAL_STRETCH: float = 0.02
const ATTACK_PREVIEW_SECONDS: float = REAR_HOLD_SECONDS + STRIKE_SWING_SECONDS + FRONT_HOLD_SECONDS + RESET_SECONDS

var fighter
var viewport: SubViewport
var ready_for_input: bool = false
var oscillating: bool = false
var travel_ratio: float = 0.0
var _phase: float = 0.0
var _slider: HSlider
var _number: SpinBox
var _side: OptionButton
var _resolution: OptionButton
var _status: Label
var _notice: Label
var _pitch: SpinBox
var _softness: SpinBox
var _auto_button: Button
var _overlay
var _rebuilding: bool = false
var _pending: bool = false


func _ready() -> void:
	get_window().title = "AHOGE LEGEND / 首の前後調整"
	if not OS.get_cmdline_user_args().has("--neck-test"):
		get_window().size = Vector2i(1440, 960)
	_build_ui()
	await rebuild()


func _text(parent: Node, text: String) -> Label:
	var label := Label.new()
	label.text = text
	parent.add_child(label)
	return label


func _button(parent: Node, text: String, method: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.pressed.connect(method)
	parent.add_child(button)
	return button


func _build_ui() -> void:
	var background := ColorRect.new()
	background.color = Color("17202c")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for edge in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + edge, 14)
	add_child(margin)
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 10)
	margin.add_child(stack)
	_text(stack, "STEP 4  ロングアホ毛の柔軟追従  |  後ろ0.4D ← 基準 → 前0.4D").add_theme_font_size_override("font_size", 24)
	_text(stack, "D = 頭部の表示直径。攻撃速度テストでは後端保持→0.15秒の前方切り返し→前端保持で、根元→中央→毛先の時間差を確認します。")
	var controls := HBoxContainer.new()
	controls.add_theme_constant_override("separation", 10)
	stack.add_child(controls)
	_button(controls, "後端 -0.4D", func(): set_ratio(-0.4))
	_button(controls, "基準 0", func(): set_ratio(0.0))
	_button(controls, "前端 +0.4D", func(): set_ratio(0.4))
	_auto_button = _button(controls, "攻撃速度テスト", toggle_oscillation)
	_text(controls, "向き")
	_side = OptionButton.new()
	_side.add_item("P1 / 右向き")
	_side.add_item("P2 / 左向き")
	_side.item_selected.connect(func(_index: int): rebuild())
	controls.add_child(_side)
	_resolution = OptionButton.new()
	_resolution.add_item("1280×720")
	_resolution.add_item("1600×900")
	_resolution.item_selected.connect(func(_index: int): rebuild())
	controls.add_child(_resolution)
	var input_row := HBoxContainer.new()
	stack.add_child(input_row)
	_text(input_row, "後ろ")
	_slider = HSlider.new()
	_slider.min_value = -0.4
	_slider.max_value = 0.4
	_slider.step = 0.005
	_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_slider.value_changed.connect(set_ratio)
	input_row.add_child(_slider)
	_text(input_row, "前")
	_number = SpinBox.new()
	_number.min_value = -0.4
	_number.max_value = 0.4
	_number.step = 0.005
	_number.suffix = "D"
	_number.custom_minimum_size.x = 140
	_number.value_changed.connect(set_ratio)
	input_row.add_child(_number)
	_text(input_row, "片側最大仰角")
	_pitch = SpinBox.new()
	_pitch.min_value = 0.0
	_pitch.max_value = 30.0
	_pitch.step = 1.0
	_pitch.value = 30.0
	_pitch.suffix = "°"
	_pitch.custom_minimum_size.x = 110
	_pitch.value_changed.connect(set_pitch)
	input_row.add_child(_pitch)
	_text(input_row, "アホ毛柔らかさ")
	_softness = SpinBox.new()
	_softness.min_value = 0.0
	_softness.max_value = 1.0
	_softness.step = 0.05
	_softness.value = 1.0
	_softness.custom_minimum_size.x = 110
	_softness.value_changed.connect(set_softness)
	input_row.add_child(_softness)
	_status = _text(stack, "頭部の準備中…")
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 10)
	stack.add_child(actions)
	_button(actions, "PNG保存", save_capture)
	_button(actions, "モーション調整へ戻る", func(): get_tree().change_scene_to_file("res://tools/motion_preview/MotionPreview.tscn"))
	_notice = _text(actions, "「攻撃速度テスト」では後端で後方へ伸び、切り返し後は前方へ伸びます。C字のまま前後移動するのはNGです。")
	_notice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_notice.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var display := TextureRect.new()
	display.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	display.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	display.size_flags_vertical = Control.SIZE_EXPAND_FILL
	display.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	display.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_child(display)
	viewport = SubViewport.new()
	viewport.disable_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	display.texture = viewport.get_texture()


func rebuild() -> void:
	if _rebuilding:
		_pending = true
		return
	_rebuilding = true
	ready_for_input = false
	stop_oscillation()
	for child in viewport.get_children():
		child.free()
	viewport.size = Vector2i(1280, 720) if _resolution.selected == 0 else Vector2i(1600, 900)
	var paper := ColorRect.new()
	paper.color = Color("fff7e8")
	paper.size = Vector2(viewport.size)
	paper.mouse_filter = Control.MOUSE_FILTER_IGNORE
	viewport.add_child(paper)
	var hud = HudScene.instantiate()
	viewport.add_child(hud)
	hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hud.contact_director.set_process(false)
	var config = ConfigScript.new()
	var character = CatalogScript.get_by_id("LONG_TEST")
	hud.set_combatants(character, StateScript.new(config), character, StateScript.new(config))
	await get_tree().process_frame
	await get_tree().process_frame
	fighter = hud.contact_director.fighters[_side.selected]
	var actual_size: Vector2 = fighter.size
	fighter.reparent(viewport, false)
	fighter.set_anchors_preset(Control.PRESET_TOP_LEFT)
	fighter.size = actual_size
	fighter.position = Vector2((viewport.size.x - actual_size.x) * 0.5, viewport.size.y - actual_size.y - 16.0)
	fighter.set_process(false)
	fighter.arena_canvas_rect = Rect2(Vector2.ZERO, Vector2(viewport.size))
	hud.free()
	_overlay = OverlayScript.new()
	_overlay.fighter = fighter
	_overlay.baseline_y = 70.0
	viewport.add_child(_overlay)
	ready_for_input = true
	_rebuilding = false
	_apply_ratio(travel_ratio)
	if _pending:
		_pending = false
		await rebuild()


func set_ratio(value: float) -> void:
	if not is_finite(value):
		return
	stop_oscillation()
	_apply_ratio(value)


func set_pitch(value: float) -> void:
	if not is_finite(value):
		return
	stop_oscillation()
	if ready_for_input and is_instance_valid(fighter):
		fighter.set_neck_gaze_max_degrees(value)
	_apply_ratio(travel_ratio)


func set_softness(value: float) -> void:
	if not is_finite(value):
		return
	stop_oscillation()
	if ready_for_input and is_instance_valid(fighter):
		fighter.set_ahoge_softness(value)
		fighter.reset_ahoge_soft_follow()
	_apply_ratio(travel_ratio)


func _apply_ratio(value: float, dynamic_delta: float = 0.0) -> void:
	travel_ratio = clampf(value, -0.4, 0.4)
	_slider.set_value_no_signal(travel_ratio)
	_number.set_value_no_signal(travel_ratio)
	if not ready_for_input or not is_instance_valid(fighter):
		return
	fighter.set_neck_gaze_max_degrees(float(_pitch.value))
	if not is_equal_approx(fighter.ahoge_softness, float(_softness.value)):
		fighter.set_ahoge_softness(float(_softness.value))
	fighter.set_neck_travel_ratio(travel_ratio)
	if dynamic_delta > 0.0:
		fighter.advance_neck_preview(dynamic_delta)
	var d: float = fighter.head_display_diameter()
	var elevation: float = fighter.neck_gaze_elevation_degrees()
	_status.text = "位置 %+.3fD  |  移動量 %+.1fpx  |  仰角 %+.1f°  |  柔らかさ %.2f  |  D=%.1fpx" % [travel_ratio, travel_ratio * d, elevation, fighter.ahoge_softness, d]
	_overlay.queue_redraw()


func toggle_oscillation() -> void:
	if not ready_for_input:
		return
	if oscillating:
		stop_oscillation()
	else:
		_phase = 0.0
		_apply_ratio(-0.4)
		if is_instance_valid(fighter):
			fighter.set_neck_ahoge_directional_extension(1.0, -1.0)
			fighter.set_neck_ahoge_attack_profile(0.0, 0.0)
			fighter.reset_ahoge_soft_follow()
		oscillating = true
		_auto_button.text = "テスト停止"


func stop_oscillation() -> void:
	oscillating = false
	if ready_for_input and is_instance_valid(fighter):
		fighter.set_neck_ahoge_directional_extension(0.0, 0.0)
		fighter.set_neck_ahoge_attack_profile(-1.0, 0.0)
	if _auto_button != null:
		_auto_button.text = "攻撃速度テスト"


static func attack_preview_direction(seconds: float) -> float:
	var t: float = fposmod(maxf(seconds, 0.0), ATTACK_PREVIEW_SECONDS)
	if t < REAR_HOLD_SECONDS:
		return -1.0
	t -= REAR_HOLD_SECONDS
	if t < STRIKE_SWING_SECONDS:
		# 頭部は0.15秒で滑らかに前進するが、アホ毛は序盤22%を後方保持。
		# その後22%→62%の短い区間で急反転し、rootへ明確な加速を作る。
		var u: float = clampf(t / STRIKE_SWING_SECONDS, 0.0, 1.0)
		if u <= 0.22:
			return -1.0
		if u >= 0.62:
			return 1.0
		return lerpf(-1.0, 1.0, smoothstep(0.22, 0.62, u))
	t -= STRIKE_SWING_SECONDS
	if t < FRONT_HOLD_SECONDS:
		return 1.0
	t -= FRONT_HOLD_SECONDS
	var back: float = smoothstep(0.0, RESET_SECONDS, t)
	return lerpf(1.0, -1.0, back)


static func attack_preview_active_progress(seconds: float) -> float:
	var t: float = fposmod(maxf(seconds, 0.0), ATTACK_PREVIEW_SECONDS)
	if t < REAR_HOLD_SECONDS:
		return 0.0
	t -= REAR_HOLD_SECONDS
	if t < STRIKE_SWING_SECONDS:
		return clampf(t / STRIKE_SWING_SECONDS, 0.0, 1.0)
	t -= STRIKE_SWING_SECONDS
	if t < FRONT_HOLD_SECONDS:
		return 1.0
	return -1.0


static func attack_preview_elastic_stretch(seconds: float) -> float:
	var t: float = fposmod(maxf(seconds, 0.0), ATTACK_PREVIEW_SECONDS)
	if t < REAR_HOLD_SECONDS:
		var rear_u: float = clampf(t / REAR_HOLD_SECONDS, 0.0, 1.0)
		return lerpf(0.0, PRELOAD_CONTRACTION, smoothstep(0.0, 0.70, rear_u))
	t -= REAR_HOLD_SECONDS
	if t < STRIKE_SWING_SECONDS:
		var strike_u: float = clampf(t / STRIKE_SWING_SECONDS, 0.0, 1.0)
		return lerpf(PRELOAD_CONTRACTION, STRIKE_STRETCH, smoothstep(0.68, 1.00, strike_u))
	t -= STRIKE_SWING_SECONDS
	if t < FRONT_HOLD_SECONDS:
		var front_u: float = clampf(t / FRONT_HOLD_SECONDS, 0.0, 1.0)
		# 1.25倍は前端の恒常長ではなく、振り抜き慣性による一時overshoot。
		# 前端到達後約0.12秒で残留2%まで急速に戻す。
		return lerpf(STRIKE_STRETCH, FRONT_RESIDUAL_STRETCH, smoothstep(0.0, 0.40, front_u))
	t -= FRONT_HOLD_SECONDS
	var reset_u: float = clampf(t / RESET_SECONDS, 0.0, 1.0)
	return lerpf(FRONT_RESIDUAL_STRETCH, 0.0, smoothstep(0.0, 0.65, reset_u))


static func attack_preview_ratio(seconds: float) -> float:
	var t: float = fposmod(maxf(seconds, 0.0), ATTACK_PREVIEW_SECONDS)
	if t < REAR_HOLD_SECONDS:
		return -0.4
	t -= REAR_HOLD_SECONDS
	if t < STRIKE_SWING_SECONDS:
		var u: float = smoothstep(0.0, STRIKE_SWING_SECONDS, t)
		return lerpf(-0.4, 0.4, u)
	t -= STRIKE_SWING_SECONDS
	if t < FRONT_HOLD_SECONDS:
		return 0.4
	t -= FRONT_HOLD_SECONDS
	var back: float = smoothstep(0.0, RESET_SECONDS, t)
	return lerpf(0.4, -0.4, back)


func _process(delta: float) -> void:
	if oscillating and ready_for_input:
		_phase = fposmod(_phase + delta, ATTACK_PREVIEW_SECONDS)
		fighter.set_neck_ahoge_directional_extension(1.0, attack_preview_direction(_phase))
		fighter.set_neck_ahoge_attack_profile(
			attack_preview_active_progress(_phase),
			attack_preview_elastic_stretch(_phase)
		)
		_apply_ratio(attack_preview_ratio(_phase), delta)


func save_capture() -> void:
	if not ready_for_input:
		return
	var path: String = "res://artifacts/neck-range/neck_%d.png" % Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://artifacts/neck-range"))
	await RenderingServer.frame_post_draw
	var image: Image = viewport.get_texture().get_image()
	if image == null or image.is_empty() or image.save_png(path) != OK:
		_notice.text = "PNGを保存できませんでした。"
	else:
		_notice.text = "保存: " + ProjectSettings.globalize_path(path)
