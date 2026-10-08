extends Control

# 実BattleHUDのfighterをそのまま使用し、中央へ置いて首の可動域だけを確認する。
const HudScene := preload("res://scenes/screens/battle/BattleHUD.tscn")
const ConfigScript := preload("res://src/config/combat_config.gd")
const StateScript := preload("res://src/domain/combatant_state.gd")
const CatalogScript := preload("res://src/domain/character_catalog.gd")
const OverlayScript := preload("res://tools/motion_preview/neck_range_overlay.gd")
const SCENE: String = "res://tools/motion_preview/NeckRangePreview.tscn"

enum PreviewMode {
	CHARGED_ATTACK,
	NORMAL_ATTACK,
	PARRY,
}

const PREVIEW_MODE_NAMES: Array[String] = ["チャージ攻撃", "通常攻撃", "パリィ"]
const NORMAL_IDLE_BEFORE_SECONDS: float = 0.45
const NORMAL_PREP_SECONDS: float = 0.16
const NORMAL_HEAD_LEAD_SECONDS: float = 0.04
const NORMAL_PREP_DIRECTIONAL_MAX: float = 0.20
const NORMAL_STRIKE_DIRECTIONAL_FULL_Q: float = 0.35
const NORMAL_FRONT_HOLD_SECONDS: float = 0.12
const NORMAL_RETURN_TO_IDLE_SECONDS: float = 0.35
const NORMAL_IDLE_HOLD_SECONDS: float = 1.20
const NORMAL_PRELOAD_CONTRACTION: float = -0.015
const NORMAL_STRIKE_STRETCH: float = 0.14
const NORMAL_RESIDUAL_STRETCH: float = 0.01
const PARRY_IDLE_BEFORE_SECONDS: float = 0.45
const PARRY_RETURN_TO_IDLE_SECONDS: float = 0.35
const PARRY_IDLE_HOLD_SECONDS: float = 1.20

const CHARGE_PREP_SECONDS: float = 0.20
const REAR_HOLD_SECONDS: float = 0.30
const STRIKE_SWING_SECONDS: float = 0.15
const FRONT_HOLD_SECONDS: float = 0.30
const RETURN_TO_IDLE_SECONDS: float = 0.30
const IDLE_HOLD_SECONDS: float = 1.20
const RESET_SECONDS: float = 0.30
const PRELOAD_CONTRACTION: float = -0.035
const STRIKE_STRETCH: float = 0.30
const FRONT_RESIDUAL_STRETCH: float = 0.02
# ATTACK_PREVIEW_SECONDSはチャージ攻撃本体の既存自動検証用。意味を変更しない。
const ATTACK_PREVIEW_SECONDS: float = REAR_HOLD_SECONDS + STRIKE_SWING_SECONDS + FRONT_HOLD_SECONDS + RESET_SECONDS
const CHARGED_PREVIEW_SECONDS: float = (
	CHARGE_PREP_SECONDS
	+ REAR_HOLD_SECONDS
	+ STRIKE_SWING_SECONDS
	+ FRONT_HOLD_SECONDS
	+ RETURN_TO_IDLE_SECONDS
	+ IDLE_HOLD_SECONDS
)

var fighter
var viewport: SubViewport
var ready_for_input: bool = false
var oscillating: bool = false
var travel_ratio: float = 0.0
var _phase: float = 0.0
var _slider: HSlider
var _number: SpinBox
var _mode: OptionButton
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
	get_window().title = "AHOGE LEGEND / ロングアホ毛 動作調整"
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
	_text(stack, "STEP 4  ロングアホ毛 動作調整  |  チャージ攻撃 / 通常攻撃 / パリィ").add_theme_font_size_override("font_size", 24)
	_text(stack, "同じ画面・同じLONG_TEST素材で3動作を切り替え、Human Verificationしながら個別に調整します。")
	var mode_row := HBoxContainer.new()
	mode_row.add_theme_constant_override("separation", 10)
	stack.add_child(mode_row)
	_text(mode_row, "モード")
	_mode = OptionButton.new()
	for mode_name in PREVIEW_MODE_NAMES:
		_mode.add_item(mode_name)
	_mode.selected = PreviewMode.CHARGED_ATTACK
	_mode.item_selected.connect(set_preview_mode)
	mode_row.add_child(_mode)
	_text(mode_row, "選択中の動作だけを「動作テスト」でループ再生します。")
	var controls := HBoxContainer.new()
	controls.add_theme_constant_override("separation", 10)
	stack.add_child(controls)
	_button(controls, "後端 -0.4D", func(): set_ratio(-0.4))
	_button(controls, "基準 0", func(): set_ratio(0.0))
	_button(controls, "前端 +0.4D", func(): set_ratio(0.4))
	_auto_button = _button(controls, "動作テスト", toggle_oscillation)
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
	_notice = _text(actions, "チャージ攻撃を調整中。モードを切り替えると通常攻撃・パリィも同じ画面で確認できます。")
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


func set_preview_mode(index: int) -> void:
	if _mode == null:
		return
	var selected: int = clampi(index, 0, PREVIEW_MODE_NAMES.size() - 1)
	_mode.select(selected)
	stop_oscillation()
	if ready_for_input and is_instance_valid(fighter):
		fighter.reset_neck_preview_action()
		fighter.set_neck_ahoge_directional_extension(0.0, 0.0)
		fighter.set_neck_ahoge_attack_profile(-1.0, 0.0)
	_apply_ratio(0.0)
	match selected:
		PreviewMode.CHARGED_ATTACK:
			_notice.text = "チャージ攻撃: 溜め→攻撃→基準0D・待機C字への自然復帰→1.20秒の静止確認まで見られます。"
		PreviewMode.NORMAL_ATTACK:
			_notice.text = "通常攻撃: 開始前0.45秒→攻撃→自然復帰→標準C字1.20秒確認。初動は頭を0.04秒先行させます。"
		PreviewMode.PARRY:
			_notice.text = "パリィ: 開始前0.45秒→払い→自然復帰→標準C字1.20秒確認。初動prepareを緩やかにしています。"


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
		if is_instance_valid(fighter):
			fighter.reset_neck_preview_action()
			fighter.reset_ahoge_soft_follow()
		_apply_preview_frame(0.0, 0.0)
		oscillating = true
		_auto_button.text = "テスト停止"


func stop_oscillation() -> void:
	oscillating = false
	if ready_for_input and is_instance_valid(fighter):
		fighter.set_neck_ahoge_directional_extension(0.0, 0.0)
		fighter.set_neck_ahoge_attack_profile(-1.0, 0.0)
		fighter.set_neck_preview_action(StateScript.ActionState.IDLE, 1.0)
	if _auto_button != null:
		_auto_button.text = "動作テスト"


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


func _charged_ratio(seconds: float) -> float:
	var t: float = fposmod(maxf(seconds, 0.0), CHARGED_PREVIEW_SECONDS)
	if t < CHARGE_PREP_SECONDS:
		return lerpf(0.0, -0.4, smoothstep(0.0, CHARGE_PREP_SECONDS, t))
	t -= CHARGE_PREP_SECONDS
	if t < REAR_HOLD_SECONDS:
		return -0.4
	t -= REAR_HOLD_SECONDS
	if t < STRIKE_SWING_SECONDS:
		return lerpf(-0.4, 0.4, smoothstep(0.0, STRIKE_SWING_SECONDS, t))
	t -= STRIKE_SWING_SECONDS
	if t < FRONT_HOLD_SECONDS:
		return 0.4
	t -= FRONT_HOLD_SECONDS
	if t < RETURN_TO_IDLE_SECONDS:
		return lerpf(0.4, 0.0, smoothstep(0.0, RETURN_TO_IDLE_SECONDS, t))
	return 0.0


func _charged_directional_amount(seconds: float) -> float:
	var t: float = fposmod(maxf(seconds, 0.0), CHARGED_PREVIEW_SECONDS)
	if t < CHARGE_PREP_SECONDS:
		return smoothstep(0.0, CHARGE_PREP_SECONDS, t)
	t -= CHARGE_PREP_SECONDS
	var active_seconds: float = REAR_HOLD_SECONDS + STRIKE_SWING_SECONDS + FRONT_HOLD_SECONDS
	if t < active_seconds:
		return 1.0
	t -= active_seconds
	if t < RETURN_TO_IDLE_SECONDS:
		return lerpf(1.0, 0.0, smoothstep(0.0, RETURN_TO_IDLE_SECONDS, t))
	return 0.0


func _charged_direction(seconds: float) -> float:
	var t: float = fposmod(maxf(seconds, 0.0), CHARGED_PREVIEW_SECONDS)
	if t < CHARGE_PREP_SECONDS:
		return -1.0
	t -= CHARGE_PREP_SECONDS
	var core_seconds: float = REAR_HOLD_SECONDS + STRIKE_SWING_SECONDS + FRONT_HOLD_SECONDS
	if t < core_seconds:
		return attack_preview_direction(t)
	return 1.0


func _charged_active_progress(seconds: float) -> float:
	var t: float = fposmod(maxf(seconds, 0.0), CHARGED_PREVIEW_SECONDS)
	if t < CHARGE_PREP_SECONDS:
		return 0.0
	t -= CHARGE_PREP_SECONDS
	var core_seconds: float = REAR_HOLD_SECONDS + STRIKE_SWING_SECONDS + FRONT_HOLD_SECONDS
	if t < core_seconds:
		return attack_preview_active_progress(t)
	return -1.0


func _charged_elastic_stretch(seconds: float) -> float:
	var t: float = fposmod(maxf(seconds, 0.0), CHARGED_PREVIEW_SECONDS)
	if t < CHARGE_PREP_SECONDS:
		return lerpf(0.0, PRELOAD_CONTRACTION, smoothstep(0.0, CHARGE_PREP_SECONDS, t))
	t -= CHARGE_PREP_SECONDS
	if t < REAR_HOLD_SECONDS:
		return PRELOAD_CONTRACTION
	t -= REAR_HOLD_SECONDS
	if t < STRIKE_SWING_SECONDS:
		var strike_u: float = clampf(t / STRIKE_SWING_SECONDS, 0.0, 1.0)
		return lerpf(PRELOAD_CONTRACTION, STRIKE_STRETCH, smoothstep(0.68, 1.00, strike_u))
	t -= STRIKE_SWING_SECONDS
	if t < FRONT_HOLD_SECONDS:
		var front_u: float = clampf(t / FRONT_HOLD_SECONDS, 0.0, 1.0)
		return lerpf(STRIKE_STRETCH, FRONT_RESIDUAL_STRETCH, smoothstep(0.0, 0.40, front_u))
	t -= FRONT_HOLD_SECONDS
	if t < RETURN_TO_IDLE_SECONDS:
		return lerpf(FRONT_RESIDUAL_STRETCH, 0.0, smoothstep(0.0, 0.65, t / RETURN_TO_IDLE_SECONDS))
	return 0.0


func _charged_is_idle_hold(seconds: float) -> bool:
	var t: float = fposmod(maxf(seconds, 0.0), CHARGED_PREVIEW_SECONDS)
	var idle_start: float = (
		CHARGE_PREP_SECONDS
		+ REAR_HOLD_SECONDS
		+ STRIKE_SWING_SECONDS
		+ FRONT_HOLD_SECONDS
		+ RETURN_TO_IDLE_SECONDS
	)
	return t >= idle_start


func _normal_cycle_seconds() -> float:
	var config = ConfigScript.new()
	return (
		NORMAL_IDLE_BEFORE_SECONDS
		+ NORMAL_PREP_SECONDS
		+ config.normal_strike_seconds
		+ NORMAL_FRONT_HOLD_SECONDS
		+ NORMAL_RETURN_TO_IDLE_SECONDS
		+ NORMAL_IDLE_HOLD_SECONDS
	)


func _parry_cycle_seconds() -> float:
	var config = ConfigScript.new()
	return (
		PARRY_IDLE_BEFORE_SECONDS
		+ config.parry_active_seconds
		+ PARRY_RETURN_TO_IDLE_SECONDS
		+ PARRY_IDLE_HOLD_SECONDS
	)


func preview_cycle_seconds() -> float:
	match _mode.selected:
		PreviewMode.NORMAL_ATTACK:
			return _normal_cycle_seconds()
		PreviewMode.PARRY:
			return _parry_cycle_seconds()
		_:
			return CHARGED_PREVIEW_SECONDS


func _normal_local_time(seconds: float) -> float:
	return fposmod(maxf(seconds, 0.0), _normal_cycle_seconds())


func _normal_ratio(seconds: float) -> float:
	var config = ConfigScript.new()
	var t: float = _normal_local_time(seconds)
	if t < NORMAL_IDLE_BEFORE_SECONDS:
		return 0.0
	t -= NORMAL_IDLE_BEFORE_SECONDS
	if t < NORMAL_PREP_SECONDS:
		return lerpf(0.0, -0.18, smoothstep(0.0, NORMAL_PREP_SECONDS, t))
	t -= NORMAL_PREP_SECONDS
	if t < config.normal_strike_seconds:
		return lerpf(-0.18, 0.30, smoothstep(0.0, config.normal_strike_seconds, t))
	t -= config.normal_strike_seconds
	if t < NORMAL_FRONT_HOLD_SECONDS:
		return 0.30
	t -= NORMAL_FRONT_HOLD_SECONDS
	if t < NORMAL_RETURN_TO_IDLE_SECONDS:
		return lerpf(0.30, 0.0, smoothstep(0.0, NORMAL_RETURN_TO_IDLE_SECONDS, t))
	return 0.0


func _normal_direction(seconds: float) -> float:
	var config = ConfigScript.new()
	var t: float = _normal_local_time(seconds)
	if t < NORMAL_IDLE_BEFORE_SECONDS:
		return -1.0
	t -= NORMAL_IDLE_BEFORE_SECONDS
	if t < NORMAL_PREP_SECONDS:
		return -1.0
	t -= NORMAL_PREP_SECONDS
	if t < config.normal_strike_seconds:
		var q: float = clampf(t / config.normal_strike_seconds, 0.0, 1.0)
		if q <= 0.15:
			return -1.0
		if q >= 0.55:
			return 1.0
		return lerpf(-1.0, 1.0, smoothstep(0.15, 0.55, q))
	return 1.0


func _normal_directional_amount(seconds: float) -> float:
	var config = ConfigScript.new()
	var t: float = _normal_local_time(seconds)
	if t < NORMAL_IDLE_BEFORE_SECONDS:
		return 0.0
	t -= NORMAL_IDLE_BEFORE_SECONDS
	if t < NORMAL_PREP_SECONDS:
		if t <= NORMAL_HEAD_LEAD_SECONDS:
			return 0.0
		return NORMAL_PREP_DIRECTIONAL_MAX * smoothstep(
			NORMAL_HEAD_LEAD_SECONDS,
			NORMAL_PREP_SECONDS,
			t
		)
	t -= NORMAL_PREP_SECONDS
	if t < config.normal_strike_seconds:
		var q: float = clampf(t / config.normal_strike_seconds, 0.0, 1.0)
		return lerpf(
			NORMAL_PREP_DIRECTIONAL_MAX,
			1.0,
			smoothstep(0.0, NORMAL_STRIKE_DIRECTIONAL_FULL_Q, q)
		)
	t -= config.normal_strike_seconds
	if t < NORMAL_FRONT_HOLD_SECONDS:
		return 1.0
	t -= NORMAL_FRONT_HOLD_SECONDS
	if t < NORMAL_RETURN_TO_IDLE_SECONDS:
		return lerpf(1.0, 0.0, smoothstep(0.0, NORMAL_RETURN_TO_IDLE_SECONDS, t))
	return 0.0


func _normal_active_progress(seconds: float) -> float:
	var config = ConfigScript.new()
	var t: float = _normal_local_time(seconds)
	if t < NORMAL_IDLE_BEFORE_SECONDS:
		return -1.0
	t -= NORMAL_IDLE_BEFORE_SECONDS
	if t < NORMAL_PREP_SECONDS:
		return 0.0
	t -= NORMAL_PREP_SECONDS
	if t < config.normal_strike_seconds:
		return clampf(t / config.normal_strike_seconds, 0.0, 1.0)
	t -= config.normal_strike_seconds
	if t < NORMAL_FRONT_HOLD_SECONDS:
		return 1.0
	return -1.0


func _normal_elastic_stretch(seconds: float) -> float:
	var config = ConfigScript.new()
	var t: float = _normal_local_time(seconds)
	if t < NORMAL_IDLE_BEFORE_SECONDS:
		return 0.0
	t -= NORMAL_IDLE_BEFORE_SECONDS
	if t < NORMAL_PREP_SECONDS:
		if t <= NORMAL_HEAD_LEAD_SECONDS:
			return 0.0
		return lerpf(
			0.0,
			NORMAL_PRELOAD_CONTRACTION,
			smoothstep(NORMAL_HEAD_LEAD_SECONDS, NORMAL_PREP_SECONDS, t)
		)
	t -= NORMAL_PREP_SECONDS
	if t < config.normal_strike_seconds:
		var q: float = clampf(t / config.normal_strike_seconds, 0.0, 1.0)
		return lerpf(NORMAL_PRELOAD_CONTRACTION, NORMAL_STRIKE_STRETCH, smoothstep(0.65, 1.0, q))
	t -= config.normal_strike_seconds
	if t < NORMAL_FRONT_HOLD_SECONDS:
		return lerpf(NORMAL_STRIKE_STRETCH, NORMAL_RESIDUAL_STRETCH, smoothstep(0.0, 1.0, t / NORMAL_FRONT_HOLD_SECONDS))
	t -= NORMAL_FRONT_HOLD_SECONDS
	if t < NORMAL_RETURN_TO_IDLE_SECONDS:
		return lerpf(NORMAL_RESIDUAL_STRETCH, 0.0, smoothstep(0.0, NORMAL_RETURN_TO_IDLE_SECONDS, t))
	return 0.0


func _normal_is_idle_hold(seconds: float) -> bool:
	var t: float = _normal_local_time(seconds)
	var idle_start: float = (
		NORMAL_IDLE_BEFORE_SECONDS
		+ NORMAL_PREP_SECONDS
		+ ConfigScript.new().normal_strike_seconds
		+ NORMAL_FRONT_HOLD_SECONDS
		+ NORMAL_RETURN_TO_IDLE_SECONDS
	)
	return t >= idle_start or t < NORMAL_IDLE_BEFORE_SECONDS


func _parry_local_time(seconds: float) -> float:
	return fposmod(maxf(seconds, 0.0), _parry_cycle_seconds())


func _parry_action_time(seconds: float) -> float:
	return _parry_local_time(seconds) - PARRY_IDLE_BEFORE_SECONDS


func _parry_ratio(seconds: float) -> float:
	var config = ConfigScript.new()
	var t: float = _parry_local_time(seconds)
	if t < PARRY_IDLE_BEFORE_SECONDS:
		return 0.0
	t -= PARRY_IDLE_BEFORE_SECONDS
	if t < config.parry_active_seconds:
		var q: float = clampf(t / config.parry_active_seconds, 0.0, 1.0)
		if q < 0.16:
			return lerpf(0.0, -0.10, smoothstep(0.0, 0.16, q))
		if q < 0.40:
			return lerpf(-0.10, 0.18, smoothstep(0.16, 0.40, q))
		if q < 0.72:
			return lerpf(0.18, 0.06, smoothstep(0.40, 0.72, q))
		return lerpf(0.06, 0.0, smoothstep(0.72, 1.0, q))
	return 0.0


func _parry_is_idle_hold(seconds: float) -> bool:
	var t: float = _parry_local_time(seconds)
	var idle_start: float = PARRY_IDLE_BEFORE_SECONDS + ConfigScript.new().parry_active_seconds + PARRY_RETURN_TO_IDLE_SECONDS
	return t >= idle_start or t < PARRY_IDLE_BEFORE_SECONDS


func _apply_preview_frame(seconds: float, delta: float) -> void:
	match _mode.selected:
		PreviewMode.NORMAL_ATTACK:
			fighter.set_neck_preview_action(StateScript.ActionState.IDLE, 1.0)
			fighter.set_neck_ahoge_directional_extension(
				_normal_directional_amount(seconds),
				_normal_direction(seconds)
			)
			fighter.set_neck_ahoge_attack_profile(
				_normal_active_progress(seconds),
				_normal_elastic_stretch(seconds)
			)
			_apply_ratio(_normal_ratio(seconds), delta)
		PreviewMode.PARRY:
			var config = ConfigScript.new()
			var action_t: float = _parry_action_time(seconds)
			fighter.set_neck_ahoge_directional_extension(0.0, 0.0)
			fighter.set_neck_ahoge_attack_profile(-1.0, 0.0)
			fighter.set_neck_preview_action(
				StateScript.ActionState.PARRY
				if action_t >= 0.0 and action_t < config.parry_active_seconds
				else StateScript.ActionState.IDLE,
				config.parry_active_seconds
			)
			_apply_ratio(_parry_ratio(seconds), delta)
		_:
			fighter.set_neck_preview_action(StateScript.ActionState.IDLE, 1.0)
			fighter.set_neck_ahoge_directional_extension(
				_charged_directional_amount(seconds),
				_charged_direction(seconds)
			)
			fighter.set_neck_ahoge_attack_profile(
				_charged_active_progress(seconds),
				_charged_elastic_stretch(seconds)
			)
			_apply_ratio(_charged_ratio(seconds), delta)


func _process(delta: float) -> void:
	if oscillating and ready_for_input:
		var cycle: float = preview_cycle_seconds()
		# ループ境界でActionMotion/soft chainを作り直さない。
		# 終了後IDLE_HOLDで自然収束した状態をそのまま次周期へ持ち越す。
		_phase = fposmod(_phase + delta, cycle)
		_apply_preview_frame(_phase, delta)


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
