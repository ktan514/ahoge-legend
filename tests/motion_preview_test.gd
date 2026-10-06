extends SceneTree

const PreviewScene := preload("res://tools/motion_preview/MotionPreview.tscn")
var failures: Array[String] = []
var checks: int = 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	await process_frame
	var preview = PreviewScene.instantiate()
	root.add_child(preview)
	while preview.busy:
		await process_frame
	preview.set_process(false)
	var cases: int = 0
	for resolution in [0, 1]:
		for side in [0, 1]:
			for scenario in range(5):
				preview._resolution.select(resolution)
				preview._side.select(side)
				preview._scenario.select(scenario)
				await preview.rebuild()
				_expect(preview.session.hud.size == Vector2(preview._viewport.size), "HUDの寸法が一致")
				_expect(not preview.session.director.is_processing(), "二重更新を防止")
				_expect(preview.session.phases.size() >= 3, "入力列が存在")
				var target: float = preview.session.contact_time
				if target > 0:
					preview.session.advance_to(target)
					_expect(preview.session.attacker.last_contact_error <= 2.0, "本体の接触表示へ接続")
				preview.session.advance_to(preview.session.total)
				_expect(preview.session.pose().size() == 427, "本体の固定メッシュへ接続")
				_expect(absf(preview.session.time - preview.session.total) < 0.00001, "最後まで進行")
				cases += 1
	preview._resolution.select(0)
	preview._side.select(0)
	preview._scenario.select(1)
	# MotionPreviewの柔らかさ0/1が実BattleFighterVisualへ渡り、実頂点に差を出す。
	preview._fps.select(1)
	preview._softness.set_value_no_signal(0.0)
	await preview.rebuild()
	var strike_probe: float = _phase_probe(preview.session.phases, 3, 0.45)
	preview.session.advance_to(strike_probe)
	var rigid_strike: PackedVector2Array = preview.session.pose().duplicate()
	_expect(is_equal_approx(preview.session.softness, 0.0), "MotionPreview柔らかさ0がSessionへ反映")
	preview._softness.set_value_no_signal(1.0)
	await preview.rebuild()
	strike_probe = _phase_probe(preview.session.phases, 3, 0.45)
	preview.session.advance_to(strike_probe)
	var soft_strike: PackedVector2Array = preview.session.pose().duplicate()
	_expect(is_equal_approx(preview.session.softness, 1.0), "MotionPreview柔らかさ1がSessionへ反映")
	_expect(_difference(rigid_strike, soft_strike) > 4.0, "MotionPreviewのSTRIKEへ柔軟chainが実描画反映")
	for fps_index in range(3):
		preview._fps.select(fps_index)
		await preview.rebuild()
		var contact: float = preview.session.contact_time
		await preview.seek(contact + 0.08)
		var a: PackedVector2Array = preview.session.pose().duplicate()
		await preview.seek(0.3)
		await preview.seek(contact + 0.08)
		var b: PackedVector2Array = preview.session.pose()
		_expect(_difference(a, b) < 0.001, "逆送り後も同じ時刻は同じ実頂点")
		var old: float = preview.session.time
		preview.step_forward()
		_expect(absf(preview.session.time - old - 1.0 / preview.session.fps) < 0.00001, "1コマ進行")
		_expect(not preview.playing, "コマ送りで停止")
	preview._fps.select(1)
	await preview.rebuild()
	preview._play.pressed.emit()
	_expect(preview.playing, "再生ボタン接続")
	preview._play.pressed.emit()
	_expect(not preview.playing, "停止ボタン接続")
	await preview.seek(preview.session.contact_time + 0.05)
	preview._mesh.button_pressed = true
	preview._update_status()
	var args: PackedStringArray = preview.reload_arguments()
	_expect(args.has("res://tools/motion_preview/MotionPreview.tscn"), "再読込は通常ゲームでなく開発Scene")
	_expect(args.has("--preview-scenario=1"), "再読込は動作選択を保持")
	_expect(_has_prefix(args, "--preview-softness="), "再読込は柔らかさ設定を保持")
	var online = root.get_node_or_null("OnlineSession")
	_expect(online == null or (online.session == null and online.client == null and online.current_match_id.is_empty()), "認証・HTTPクライアント・試合を作らない")
	if DisplayServer.get_name() != "headless":
		await preview.save_capture()
		await process_frame
		await RenderingServer.frame_post_draw
		var img: Image = root.get_texture().get_image()
		_expect(not img.is_empty(), "ツールUIの実描画")
		img.save_png("res://artifacts/motion-preview/tool_ui.png")
	print("AHOGE motion preview: %s cases=%d checks=%d failures=%s" % ["PASS" if failures.is_empty() else "FAIL", cases, checks, JSON.stringify(failures)])
	preview.free()
	quit(0 if failures.is_empty() else 1)


func _phase_probe(phases: Array[Dictionary], action: int, progress: float) -> float:
	for phase in phases:
		if int(phase["state"]) == action:
			return lerpf(float(phase["start"]), float(phase["end"]), clampf(progress, 0.0, 1.0))
	return 0.0


func _has_prefix(values: PackedStringArray, prefix: String) -> bool:
	for value in values:
		if value.begins_with(prefix):
			return true
	return false


func _difference(a: PackedVector2Array, b: PackedVector2Array) -> float:
	if a.size() != b.size():
		return INF
	var result: float = 0.0
	for i in range(a.size()):
		result = maxf(result, a[i].distance_to(b[i]))
	return result


func _expect(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error(label)
