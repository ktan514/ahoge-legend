extends SceneTree

const AppRootScene := preload("res://scenes/app/AppRoot.tscn")
const SettingsStoreScript := preload("res://src/settings/settings_store.gd")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var online_session = get_root().get_node_or_null("OnlineSession")
	if online_session == null:
		_fail("OnlineSession Autoloadが見つかりません。", null)
		return

	var settings_path := OS.get_environment("AHOGE_SETTINGS_PATH")
	if settings_path.is_empty():
		_fail("AHOGE_SETTINGS_PATHが設定されていません。", null)
		return
	_cleanup_file(settings_path)
	online_session.clear_session()

	var app = AppRootScene.instantiate()
	get_root().add_child(app)
	if not await _wait_screen(app, "TopMenu", 6000):
		_fail("起動後にTopMenuが表示されません。", app)
		return

	var top = app.get_child(0)
	var settings_button: Button = _find_button(top, "SETTINGS") as Button
	if settings_button == null or settings_button.disabled:
		_fail("Top MenuのSETTINGSが有効ではありません。", app)
		return
	settings_button.emit_signal("pressed")

	if not await _wait_screen(app, "Settings", 3000):
		_fail("Top MenuからSettingsへ遷移しません。", app)
		return

	var screen = app.get_child(0)
	var master := screen.find_child("MasterVolume", true, false) as HSlider
	var bgm := screen.find_child("BgmVolume", true, false) as HSlider
	var se := screen.find_child("SeVolume", true, false) as HSlider
	var voice := screen.find_child("VoiceVolume", true, false) as HSlider
	var mode := screen.find_child("DisplayMode", true, false) as OptionButton
	var resolution := screen.find_child("Resolution", true, false) as OptionButton
	var vsync := screen.find_child("VSync", true, false) as CheckButton
	if master == null or bgm == null or se == null or voice == null 			or mode == null or resolution == null or vsync == null:
		_fail("SettingsのAUDIO / DISPLAY controlが揃っていません。", app)
		return

	master.value = 55
	bgm.value = 44
	se.value = 33
	voice.value = 22
	mode.select(0)
	resolution.select(2)
	vsync.button_pressed = false

	var apply_button := screen.find_child("ApplyButton", true, false) as Button
	if apply_button == null:
		_fail("SettingsにAPPLYがありません。", app)
		return
	apply_button.emit_signal("pressed")
	if not await _wait_label_text(screen, "APPLIED", 3000):
		_fail("Settings APPLYが完了しません。", app)
		return

	for bus_name in ["BGM", "SE", "Voice"]:
		if AudioServer.get_bus_index(bus_name) < 0:
			_fail("Settings APPLY後にAudio Bus %sがありません。" % bus_name, app)
			return

	var store = SettingsStoreScript.new(settings_path)
	var saved: Dictionary = store.load_settings()
	if not _matches_saved_values(saved):
		_fail("Settings APPLY内容がsettings.cfgへ保存されていません。", app)
		return

	var back_button := screen.find_child("BackButton", true, false) as Button
	if back_button == null:
		_fail("SettingsにBACKがありません。", app)
		return
	back_button.emit_signal("pressed")
	if not await _wait_screen(app, "TopMenu", 3000):
		_fail("Settings BACKでTopMenuへ戻りません。", app)
		return

	top = app.get_child(0)
	settings_button = _find_button(top, "SETTINGS")
	settings_button.emit_signal("pressed")
	if not await _wait_screen(app, "Settings", 3000):
		_fail("Settingsを再表示できません。", app)
		return
	screen = app.get_child(0)
	var reopened: Dictionary = screen.call("current_values")
	if not _matches_saved_values(reopened):
		_fail("Settings再表示でAPPLY済み値を復元していません。", app)
		return

	var default_button := screen.find_child("DefaultButton", true, false) as Button
	if default_button == null:
		_fail("SettingsにDEFAULTがありません。", app)
		return
	default_button.emit_signal("pressed")
	await process_frame
	var default_values: Dictionary = screen.call("current_values")
	if not _matches_defaults(default_values):
		_fail("DEFAULTで編集値が初期値へ戻りません。", app)
		return

	back_button = screen.find_child("BackButton", true, false) as Button
	back_button.emit_signal("pressed")
	if not await _wait_screen(app, "TopMenu", 3000):
		_fail("DEFAULT後のBACKでTopMenuへ戻りません。", app)
		return

	top = app.get_child(0)
	settings_button = _find_button(top, "SETTINGS")
	settings_button.emit_signal("pressed")
	if not await _wait_screen(app, "Settings", 3000):
		_fail("Settingsを3回目に表示できません。", app)
		return
	screen = app.get_child(0)
	var after_discard: Dictionary = screen.call("current_values")
	if not _matches_saved_values(after_discard):
		_fail("DEFAULT未APPLY値がBACK後も保存されてしまいました。", app)
		return

	app.queue_free()
	await process_frame
	online_session.clear_session()
	_cleanup_file(settings_path)
	print("AHOGE LEGEND settings screen smoke: PASS")
	quit(0)


func _matches_saved_values(settings: Dictionary) -> bool:
	var audio: Dictionary = settings.get("audio", {})
	var display: Dictionary = settings.get("display", {})
	return is_equal_approx(float(audio.get("master_volume", -1)), 55.0) 		and is_equal_approx(float(audio.get("bgm_volume", -1)), 44.0) 		and is_equal_approx(float(audio.get("se_volume", -1)), 33.0) 		and is_equal_approx(float(audio.get("voice_volume", -1)), 22.0) 		and str(display.get("mode", "")) == "windowed" 		and str(display.get("resolution", "")) == "1920x1080" 		and not bool(display.get("vsync", true))


func _matches_defaults(settings: Dictionary) -> bool:
	var audio: Dictionary = settings.get("audio", {})
	var display: Dictionary = settings.get("display", {})
	return is_equal_approx(float(audio.get("master_volume", -1)), 100.0) 		and is_equal_approx(float(audio.get("bgm_volume", -1)), 100.0) 		and is_equal_approx(float(audio.get("se_volume", -1)), 100.0) 		and is_equal_approx(float(audio.get("voice_volume", -1)), 100.0) 		and str(display.get("mode", "")) == "windowed" 		and str(display.get("resolution", "")) == "1280x720" 		and bool(display.get("vsync", false))


func _wait_screen(app, screen_name: String, timeout_ms: int) -> bool:
	var deadline := Time.get_ticks_msec() + timeout_ms
	while Time.get_ticks_msec() < deadline:
		if str(app.call("current_screen_name")) == screen_name:
			return true
		await create_timer(0.05).timeout
	return false


func _wait_label_text(root: Node, text: String, timeout_ms: int) -> bool:
	var deadline := Time.get_ticks_msec() + timeout_ms
	while Time.get_ticks_msec() < deadline:
		if _has_label_text(root, text):
			return true
		await create_timer(0.05).timeout
	return false


func _has_label_text(root: Node, text: String) -> bool:
	if root is Label and str(root.text).contains(text):
		return true
	for child in root.get_children():
		if _has_label_text(child, text):
			return true
	return false


func _find_button(root: Node, text: String):
	if root is Button and str(root.text) == text:
		return root
	for child in root.get_children():
		var found = _find_button(child, text)
		if found != null:
			return found
	return null


func _cleanup_file(settings_path: String) -> void:
	var absolute_path := ProjectSettings.globalize_path(settings_path)
	if FileAccess.file_exists(settings_path):
		DirAccess.remove_absolute(absolute_path)


func _fail(message: String, root) -> void:
	var settings_path := OS.get_environment("AHOGE_SETTINGS_PATH")
	if not settings_path.is_empty():
		_cleanup_file(settings_path)
	var online_session = get_root().get_node_or_null("OnlineSession")
	if online_session != null:
		online_session.clear_session()
	if root != null and is_instance_valid(root):
		root.queue_free()
	push_error(message)
	print("AHOGE LEGEND settings screen smoke: FAIL")
	quit(1)
