extends SceneTree

const PreviewScene := preload("res://tools/motion_preview/NeckRangePreview.tscn")
const StateScript := preload("res://src/domain/combatant_state.gd")
const OUT: String = "res://artifacts/neck-range/"
var failures: Array[String] = []
var cases: Array = []
var checks: int = 0
var max_error: float = 0.0


func _init() -> void:
	call_deferred("_run")


func _expect(ok: bool, message: String) -> void:
	checks += 1
	if not ok and not failures.has(message):
		failures.append(message)
		push_error(message)


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	root.size = Vector2i(1440, 960)
	var scene = PreviewScene.instantiate()
	root.add_child(scene)
	for i in range(12):
		await process_frame
		if scene.ready_for_input:
			break
	_expect(scene.ready_for_input, "首プレビューを起動できません")
	if not scene.ready_for_input:
		quit(1)
		return
	for resolution in [0, 1]:
		for side in [0, 1]:
			scene._resolution.select(resolution)
			scene._side.select(side)
			await scene.rebuild()
			for fps in [30, 60, 120]:
				await _case(scene, fps, resolution, side)
	# UIから直接操作したときに数値・実際の表示・往復状態が一致する。
	scene.set_ratio(0.0)
	scene._slider.value = 0.20
	_expect(is_equal_approx(scene.fighter.neck_travel_ratio, 0.20), "スライダーが頭部へ反映されません")
	scene._number.value = -0.30
	_expect(is_equal_approx(scene._slider.value, -0.30) and is_equal_approx(scene.fighter.neck_travel_ratio, -0.30), "数値入力とスライダーが一致しません")
	scene._pitch.value = 20.0
	_expect(is_equal_approx(scene.fighter.neck_gaze_max_degrees, 20.0), "仰角幅の入力が頭部へ反映されません")
	scene._pitch.value = 15.0
	scene.toggle_oscillation()
	_expect(scene.oscillating, "往復再生が開始しません")
	scene.set_ratio(0.1)
	_expect(not scene.oscillating, "手動指定で往復再生が停止しません")
	for text in ["後端 -0.4D", "基準 0", "前端 +0.4D"]:
		var button: Button = _find_button(scene, text)
		_expect(button != null, "端点ボタンがありません: " + text)
		if button != null:
			button.pressed.emit()
			var expected: float = -0.4 if text.begins_with("後") else (0.4 if text.begins_with("前") else 0.0)
			_expect(is_equal_approx(scene.travel_ratio, expected), "端点ボタンが正しく動きません: " + text)
	if DisplayServer.get_name() != "headless":
		scene._side.select(0)
		scene._resolution.select(0)
		await scene.rebuild()
		scene.set_ratio(0.4)
		await process_frame
		await RenderingServer.frame_post_draw
		_expect(root.get_texture().get_image().save_png(OUT + "tool_ui.png") == OK, "UI画像の保存失敗")
	_expect(cases.size() == 12 and checks > 300, "検査の実行条件が不足しています")
	var report := {"status": "PASS" if failures.is_empty() else "FAIL", "checks": checks, "cases": cases, "max_error_px": max_error, "failures": failures, "human_verification": "未実施"}
	var f := FileAccess.open(OUT + "report.json", FileAccess.WRITE)
	_expect(f != null, "検査結果の保存失敗")
	if f != null:
		f.store_string(JSON.stringify(report, "  "))
		f.close()
	print("AHOGE neck range: %s cases=%d checks=%d error=%f failures=%s" % [report.status, cases.size(), checks, max_error, JSON.stringify(failures)])
	scene.free()
	quit(0 if failures.is_empty() else 1)


func _case(scene, fps: int, resolution: int, side: int) -> void:
	var actor = scene.fighter
	var head := actor.find_child("HeadSprite", true, false) as Sprite2D
	var rig := actor.find_child("AhogePrototypeRig", true, false) as Node2D
	var mesh_node = actor.find_child("AhogeDeformMesh", true, false)
	var label: String = "%d_%d_%d" % [scene.viewport.size.x, side, fps]
	actor.set_neck_gaze_max_degrees(15.0)
	scene.set_ratio(0.0)
	var d: float = actor.head_display_diameter()
	var neutral: Vector2 = head.global_position
	var neutral_root: Vector2 = rig.global_position
	var original_scale: Vector2 = head.scale
	var geometry: PackedVector2Array = mesh_node.current_vertices.duplicate()
	var image: Image = head.texture.get_image()
	if image.is_compressed():
		image.decompress()
	var expected_d: float = image.get_used_rect().size.x * absf(original_scale.x)
	_expect(absf(d - expected_d) < 0.001 and d > 100.0, "Dが頭部の表示直径ではありません: " + label)
	var backward: Vector2
	var forward: Vector2
	for amount in [-0.5, -0.20, 0.0, 0.20, 0.5, -5.0, 5.0]:
		scene.set_ratio(amount)
		actor._process(1.0 / fps)
		actor.present_toward(Vector2(-9999.0, -9999.0))
		var normalized: float = clampf(amount, -0.4, 0.4)
		var expected: Vector2 = Vector2(actor.facing * d * normalized, 0.0)
		var error: float = (head.global_position - neutral).distance_to(expected)
		max_error = maxf(max_error, error)
		_expect(error < 0.002, "前後0.4Dの位置が一致しません: " + label)
		var display_height: float = head.texture.get_size().y * absf(head.scale.y)
		var crown_offset := Vector2(actor.facing * 10.0, -display_height * 0.5 + 34.0)
		var expected_root_from_head: Vector2 = crown_offset.rotated(head.rotation)
		_expect((rig.global_position - head.global_position).distance_to(expected_root_from_head) < 0.002, "根元が回転後の頭頂部に固定されていません: " + label)
		_expect(head.scale.is_equal_approx(original_scale), "端点で頭を縮小しました: " + label)
		var expected_elevation: float = -(normalized / actor.MAX_TRAVEL_DIAMETERS) * actor.neck_gaze_max_degrees
		var expected_rotation: float = deg_to_rad(-expected_elevation * actor.facing)
		_expect(absf(actor.neck_gaze_elevation_degrees() - expected_elevation) < 0.0001, "首位置と仰角が一致しません: " + label)
		_expect(absf(head.rotation - expected_rotation) < 0.0001, "頭部回転が仰角と一致しません: " + label)
		_expect(absf(head.global_position.y - neutral.y) < 0.00001, "仰角連動で頭部を上下移動しました: " + label)
		_expect(geometry == mesh_node.current_vertices, "首だけの調整でアホ毛の形が変わりました: " + label)
		_expect(absf(actor.head_display_diameter() - d) < 0.001, "移動でDが変わりました: " + label)
		var bounds: Rect2 = actor.head_canvas_bounds()
		_expect(bounds.position.x >= 0.0 and bounds.end.x <= scene.viewport.size.x, "頭部の横端が見切れました: " + label)
		for point in actor.mesh_canvas_vertices():
			_expect(point.x >= 0.0 and point.x <= scene.viewport.size.x, "アホ毛の横端が見切れました: " + label)
		_expect(not actor.confirm_contact(), "単独調整中に攻撃接触を受け付けました")
		if is_equal_approx(amount, -0.4):
			backward = head.global_position
		if is_equal_approx(amount, 0.4):
			forward = head.global_position
		if absf(amount) <= 0.400001 and (is_equal_approx(amount, -0.4) or is_zero_approx(amount) or is_equal_approx(amount, 0.4)) and fps == 60 and side == 0 and resolution == 0 and DisplayServer.get_name() != "headless":
			await process_frame
			await RenderingServer.frame_post_draw
			_expect(scene.viewport.get_texture().get_image().save_png(OUT + "position_%+.1f.png" % amount) == OK, "端点画像の保存失敗")
	_expect(absf(absf(forward.x - backward.x) - 0.8 * d) < 0.01 and absf(forward.y - backward.y) < 0.01, "端点間の横幅が0.8Dではありません: %s actual_x=%f expected=%f dy=%f" % [label, absf(forward.x - backward.x), 0.8 * d, absf(forward.y - backward.y)])
	var before: Vector2 = head.global_position
	var before_pitch: float = actor.neck_gaze_max_degrees
	_expect(not actor.set_neck_travel_ratio(NAN) and not actor.set_neck_travel_ratio(INF), "無効入力を受け付けました")
	_expect(head.global_position.is_equal_approx(before), "無効入力で位置を変えました")
	_expect(not actor.set_neck_gaze_max_degrees(NAN) and not actor.set_neck_gaze_max_degrees(INF), "無効な仰角幅を受け付けました")
	_expect(is_equal_approx(actor.neck_gaze_max_degrees, before_pitch), "無効な仰角幅で設定を変えました")
	_expect(actor.set_neck_gaze_max_degrees(999.0) and is_equal_approx(actor.neck_gaze_max_degrees, actor.MAX_GAZE_MAX_DEGREES), "仰角幅の上限が機能しません")
	actor.set_neck_gaze_max_degrees(15.0)
	actor.clear_neck_preview()
	_expect(not actor.neck_preview_enabled, "通常モードへ戻せません")
	_expect(absf(head.rotation) < 0.0001, "通常モード復帰で首の仰角が残りました")
	actor.combat_state.action_state = StateScript.ActionState.STRIKE
	actor._process(1.0 / fps)
	actor._process(1.0 / fps)
	_expect(actor._head_offset != Vector2.ZERO, "解除後の頭部アニメーションが停止しました")
	actor.combat_state.action_state = StateScript.ActionState.IDLE
	scene.set_ratio(0.0)
	scene.set_process(false)
	scene.toggle_oscillation()
	var minimum: float = INF
	var maximum: float = -INF
	for frame in range(4 * fps):
		scene._process(1.0 / fps)
		minimum = minf(minimum, scene.fighter.neck_travel_ratio)
		maximum = maxf(maximum, scene.fighter.neck_travel_ratio)
	_expect(absf(minimum + 0.4) < 0.0001 and absf(maximum - 0.4) < 0.0001, "往復再生が可動域全体を使っていません: " + label)
	scene.stop_oscillation()
	scene.set_ratio(0.0)
	scene.set_process(true)
	cases.append({"label": label, "diameter_px": d, "range_each_side_px": 0.4 * d, "span_px": absf(forward.x - backward.x), "gaze_max_degrees": 15.0, "asset": mesh_node.texture.resource_path})


func _find_button(node: Node, text: String) -> Button:
	if node is Button and node.text == text:
		return node
	for child in node.get_children():
		var found: Button = _find_button(child, text)
		if found != null:
			return found
	return null
