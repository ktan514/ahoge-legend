extends Control

const SessionScript := preload("res://tools/motion_preview/preview_session.gd")
const OverlayScript := preload("res://tools/motion_preview/preview_overlay.gd")
const SCENE: String = "res://tools/motion_preview/MotionPreview.tscn"
const SPEEDS := [0.10, 0.25, 0.50, 1.0]
const FPS_VALUES := [30, 60, 120]

var session = SessionScript.new()
var busy: bool = true
var playing: bool = false
var looped: bool = true
var speed: float = 1.0
var _accumulator: float = 0.0
var _rebuilding: bool = false
var _rebuild_pending: bool = false
var _viewport: SubViewport
var _overlay
var _display: TextureRect
var _scenario: OptionButton
var _side: OptionButton
var _opponent: OptionButton
var _fps: OptionButton
var _resolution: OptionButton
var _speed: OptionButton
var _charge: SpinBox
var _play: Button
var _slider: HSlider
var _status: Label
var _notice: Label
var _contact: Button
var _path: CheckBox
var _mesh: CheckBox


func _ready() -> void:
	get_window().title = "AHOGE LEGEND / モーション調整プレビュー（オフライン）"
	if not OS.get_cmdline_user_args().has("--preview-test"):
		get_window().size = Vector2i(1440, 960)
	_build_ui()
	_restore_options()
	await rebuild()
	busy = false
	_update_status()


func _row(parent: Node) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	parent.add_child(row)
	return row


func _label(parent: Node, text: String) -> Label:
	var label := Label.new()
	label.text = text
	parent.add_child(label)
	return label


func _button(parent: Node, text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.pressed.connect(callback)
	parent.add_child(button)
	return button


func _options(parent: Node, title: String, choices: Array, selected: int) -> OptionButton:
	_label(parent, title)
	var option := OptionButton.new()
	for choice in choices:
		option.add_item(str(choice))
	option.selected = selected
	parent.add_child(option)
	return option


func _build_ui() -> void:
	var background := ColorRect.new()
	background.color = Color("17202c")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for edge in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + edge, 14)
	add_child(margin)
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 9)
	margin.add_child(stack)
	var title := _label(stack, "モーション調整  |  本体と同じ描画コード・サーバー不要")
	title.add_theme_font_size_override("font_size", 22)
	_label(stack, "VS Code等で保存 →「コード再読込」。これは表示用の入力列です。Hit・パリィ成功・通信は検証しません。")

	var choices := _row(stack)
	_scenario = _options(choices, "動作", SessionScript.SCENARIOS, 1)
	_side = _options(choices, "LONG側", ["左 / P1", "右 / P2"], 0)
	_opponent = _options(choices, "相手", ["SHORT", "LONG"], 0)
	_label(choices, "チャージ量")
	_charge = SpinBox.new()
	_charge.min_value = 0.0
	_charge.max_value = 1.0
	_charge.step = 0.1
	_charge.value = 1.0
	choices.add_child(_charge)
	_fps = _options(choices, "計算fps", [30, 60, 120], 1)
	_resolution = _options(choices, "内部解像度", ["1280×720", "1600×900"], 0)
	for option in [_scenario, _side, _opponent, _fps, _resolution]:
		option.item_selected.connect(func(_index: int): rebuild())
	_charge.value_changed.connect(func(_value: float): rebuild())

	var transport := _row(stack)
	_play = _button(transport, "再生", toggle_play)
	_button(transport, "先頭へ", func(): seek(0.0))
	_button(transport, "1コマ戻る", func(): seek(session.time - 1.0 / session.fps))
	_button(transport, "1コマ進む", step_forward)
	_contact = _button(transport, "接触時刻へ", func(): seek(session.contact_time))
	_speed = _options(transport, "速度", ["0.1倍", "0.25倍", "0.5倍", "1倍"], 3)
	_speed.item_selected.connect(func(index: int): speed = SPEEDS[index])
	var loop_button := CheckBox.new()
	loop_button.text = "ループ"
	loop_button.button_pressed = true
	loop_button.toggled.connect(func(value: bool): looped = value)
	transport.add_child(loop_button)
	_path = CheckBox.new()
	_path.text = "中心線・軌跡"
	_path.button_pressed = true
	_path.toggled.connect(func(_value: bool): _update_overlay())
	transport.add_child(_path)
	_mesh = CheckBox.new()
	_mesh.text = "三角メッシュ"
	_mesh.toggled.connect(func(_value: bool): _update_overlay())
	transport.add_child(_mesh)

	var actions := _row(stack)
	_button(actions, "コード再読込", reload_code)
	_button(actions, "PNG保存", save_capture)
	_button(actions, "調整ガイドを開く", func(): OS.shell_open(ProjectSettings.globalize_path("res://docs/MOTION_TUNING_GUIDE.md")))
	_notice = _label(actions, "開始は「再生」。← / →：コマ送り、Space：再生/停止")
	_notice.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_notice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	_slider = HSlider.new()
	_slider.min_value = 0.0
	_slider.step = 0.001
	_slider.value_changed.connect(func(value: float): seek(value))
	stack.add_child(_slider)
	_status = _label(stack, "準備中…")
	_status.add_theme_font_size_override("font_size", 17)
	var frame := PanelContainer.new()
	frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stack.add_child(frame)
	_display = TextureRect.new()
	_display.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_display.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_display.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(_display)
	_viewport = SubViewport.new()
	_viewport.name = "MotionPreviewViewport"
	_viewport.disable_3d = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_viewport)
	_display.texture = _viewport.get_texture()
	_label(stack, "青：中心線 / 緑：毛先軌跡 / 赤い輪：接触目標。全長は最終描画のpx値。画面保護<1は全体縮小が発生中。")


func rebuild() -> void:
	if _rebuilding:
		_rebuild_pending = true
		return
	_rebuilding = true
	if is_instance_valid(_overlay):
		_overlay.free()
	busy = true
	playing = false
	_accumulator = 0.0
	_viewport.size = Vector2i(1280, 720) if _resolution.selected == 0 else Vector2i(1600, 900)
	await session.reset(_viewport, _scenario.selected, _charge.value, _side.selected, "SHORT_TEST" if _opponent.selected == 0 else "LONG_TEST", FPS_VALUES[_fps.selected])
	_overlay = OverlayScript.new()
	_overlay.session = session
	_overlay.z_index = 100
	_viewport.add_child(_overlay)
	_slider.max_value = session.total
	_contact.disabled = session.contact_time < 0.0
	busy = false
	_rebuilding = false
	_update_status()
	if _rebuild_pending:
		_rebuild_pending = false
		call_deferred("rebuild")


func seek(target: float) -> void:
	if busy:
		return
	var bounded: float = clampf(target, 0.0, session.total)
	await rebuild()
	session.advance_to(bounded)
	_update_status()


func toggle_play() -> void:
	if busy:
		return
	if session.time >= session.total - 0.000001:
		await rebuild()
	playing = not playing
	_accumulator = 0.0
	_update_status()


func step_forward() -> void:
	if busy:
		return
	playing = false
	session.advance_to(session.time + 1.0 / session.fps)
	_update_status()


func _process(delta: float) -> void:
	if busy or not playing:
		return
	_accumulator += minf(delta, 0.25) * speed
	var step: float = 1.0 / session.fps
	while _accumulator >= step and session.time < session.total - 0.000001:
		session.advance_to(session.time + step)
		_accumulator -= step
	_update_status()
	if session.time >= session.total - 0.000001:
		playing = false
		if looped:
			await rebuild()
			playing = true


func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	if get_viewport().gui_get_focus_owner() is LineEdit:
		return
	match event.keycode:
		KEY_SPACE:
			toggle_play()
		KEY_RIGHT:
			step_forward()
		KEY_LEFT:
			seek(session.time - 1.0 / session.fps)
		_:
			return
	get_viewport().set_input_as_handled()


func _update_overlay() -> void:
	if is_instance_valid(_overlay):
		_overlay.show_path = _path.button_pressed
		_overlay.show_mesh = _mesh.button_pressed
		_overlay.queue_redraw()


func _update_status() -> void:
	if busy:
		return
	_play.text = "停止" if playing else "再生"
	_slider.set_value_no_signal(session.time)
	var error_text: String = "—"
	if is_instance_valid(session.attacker) and is_finite(float(session.attacker.last_contact_error)):
		error_text = "%.2fpx" % float(session.attacker.last_contact_error)
	_status.text = "%.3f / %.3f秒  |  %s  |  全長 %.1fpx  |  目標との差 %s  |  画面保護 %.3f" % [session.time, session.total, session.state_name(), session.length_on_screen(), error_text, float(session.attacker.last_safety_scale)]
	_update_overlay()


func save_capture() -> void:
	if busy:
		return
	playing = false
	_update_status()
	await RenderingServer.frame_post_draw
	var directory: String = "res://artifacts/motion-preview"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	var path: String = directory + "/preview_%s_%d.png" % [Time.get_datetime_string_from_system().replace(":", "-").replace("T", "_"), Time.get_ticks_msec()]
	var result: Error = _viewport.get_texture().get_image().save_png(path)
	_notice.text = ("保存: " + ProjectSettings.globalize_path(path)) if result == OK else "画像を保存できませんでした。"


func reload_arguments() -> PackedStringArray:
	# ソースのconstは新しいプロセスで読み込む。インスタンスの再生成だけでは不足する。
	return PackedStringArray(["--path", ProjectSettings.globalize_path("res://"), SCENE, "--", "--preview-scenario=%d" % _scenario.selected, "--preview-side=%d" % _side.selected, "--preview-opponent=%d" % _opponent.selected, "--preview-charge=%f" % _charge.value, "--preview-fps=%d" % _fps.selected, "--preview-resolution=%d" % _resolution.selected, "--preview-speed=%d" % _speed.selected])


func reload_code() -> void:
	if busy:
		return
	playing = false
	_notice.text = "保存したコードの構文を確認中…"
	await get_tree().process_frame
	var output: Array = []
	var check_args := PackedStringArray(["--headless", "--path", ProjectSettings.globalize_path("res://"), "--check-only", "--script", "res://tools/motion_preview/motion_preview.gd"])
	var code: int = OS.execute(OS.get_executable_path(), check_args, output, true)
	var log_text: String = "\n".join(output)
	if code != 0 or log_text.contains("SCRIPT ERROR:") or log_text.contains("Parse Error:"):
		_notice.text = "構文エラーがあります。コードを直して再読込してください。"
		var dialog := AcceptDialog.new()
		dialog.title = "コードの読み込みエラー"
		dialog.dialog_text = log_text.left(2500)
		add_child(dialog)
		dialog.confirmed.connect(dialog.queue_free)
		dialog.popup_centered(Vector2i(900, 400))
		return
	var pid: int = OS.create_instance(reload_arguments())
	if pid <= 0:
		_notice.text = "再起動できませんでした。ウィンドウを閉じて起動コマンドを再実行してください。"
		return
	get_tree().quit()


func _restore_options() -> void:
	var options: Dictionary = {"scenario": _scenario, "side": _side, "opponent": _opponent, "fps": _fps, "resolution": _resolution, "speed": _speed}
	for arg in OS.get_cmdline_user_args():
		if not arg.begins_with("--preview-") or not arg.contains("="):
			continue
		var pair: PackedStringArray = arg.trim_prefix("--preview-").split("=", true, 1)
		if pair[0] == "charge" and pair[1].is_valid_float():
			_charge.set_value_no_signal(clampf(float(pair[1]), 0.0, 1.0))
		elif options.has(pair[0]) and pair[1].is_valid_int():
			var control: OptionButton = options[pair[0]]
			control.select(clampi(int(pair[1]), 0, control.item_count - 1))
	speed = SPEEDS[_speed.selected]
