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
	# UIから直接操作したときに数値・実際の表示・攻撃速度テスト状態が一致する。
	scene.set_ratio(0.0)
	scene._slider.value = 0.20
	_expect(is_equal_approx(scene.fighter.neck_travel_ratio, 0.20), "スライダーが頭部へ反映されません")
	scene._number.value = -0.30
	_expect(is_equal_approx(scene._slider.value, -0.30) and is_equal_approx(scene.fighter.neck_travel_ratio, -0.30), "数値入力とスライダーが一致しません")
	scene._pitch.value = 30.0
	_expect(is_equal_approx(scene.fighter.neck_gaze_max_degrees, 30.0), "仰角幅の入力が頭部へ反映されません")
	scene._pitch.value = 30.0
	scene._softness.value = 0.35
	_expect(is_equal_approx(scene.fighter.ahoge_softness, 0.35), "柔らかさ入力がアホ毛へ反映されません")
	scene._softness.value = 1.0
	scene.toggle_oscillation()
	_expect(scene.oscillating, "攻撃速度テストが開始しません")
	scene.set_ratio(0.1)
	_expect(not scene.oscillating, "手動指定で攻撃速度テストが停止しません")
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
	actor.set_neck_gaze_max_degrees(30.0)
	actor.set_ahoge_softness(1.0)
	scene._softness.set_value_no_signal(1.0)
	scene.set_ratio(0.0)
	var d: float = actor.head_display_diameter()
	var neutral: Vector2 = head.global_position
	var neutral_root: Vector2 = rig.global_position
	var original_scale: Vector2 = head.scale
	var neutral_geometry: PackedVector2Array = mesh_node.current_vertices.duplicate()
	var neutral_tip_local: Vector2 = neutral_geometry[-1]
	var image: Image = head.texture.get_image()
	if image.is_compressed():
		image.decompress()
	var expected_d: float = image.get_used_rect().size.x * absf(original_scale.x)
	_expect(absf(d - expected_d) < 0.001 and d > 100.0, "Dが頭部の表示直径ではありません: " + label)
	var anchor_px: Vector2 = actor.ahoge_head_anchor_texture_position()
	var anchor_i := Vector2i(clampi(roundi(anchor_px.x), 0, image.get_width() - 1), clampi(roundi(anchor_px.y), 0, image.get_height() - 1))
	_expect(image.get_pixelv(anchor_i).a >= actor.ahoge_head_anchor_alpha_threshold, "頭側アンカーが画像表面の不透明ピクセルではありません: " + label)
	var backward: Vector2
	var forward: Vector2
	for amount in [-0.4, -0.2, 0.0, 0.2, 0.4, -5.0, 5.0]:
		scene.set_ratio(amount)
		actor._process(1.0 / fps)
		actor.present_toward(Vector2(-9999.0, -9999.0))
		var normalized: float = clampf(amount, -0.4, 0.4)
		var expected: Vector2 = Vector2(actor.facing * d * normalized, 0.0)
		var error: float = (head.global_position - neutral).distance_to(expected)
		max_error = maxf(max_error, error)
		_expect(error < 0.002, "前後0.4Dの位置が一致しません: " + label)
		var anchor_canvas: Vector2 = actor.ahoge_head_anchor_canvas_position()
		var root_canvas: Vector2 = actor.ahoge_root_canvas_position()
		_expect(anchor_canvas.distance_to(root_canvas) < 0.01, "アホ毛根元が頭部アンカーから外れました: " + label)
		var head_up: Vector2 = actor.head_attachment_up_canvas_direction()
		var ahoge_up: Vector2 = actor.ahoge_attachment_up_canvas_direction()
		_expect(head_up.dot(ahoge_up) > 0.999999, "アホ毛取り付け角度が頭部仰角から外れました: " + label)
		var mesh_vertices: PackedVector2Array = actor.mesh_canvas_vertices()
		_expect(not mesh_vertices.is_empty(), "アホ毛メッシュがありません: " + label)
		if not mesh_vertices.is_empty():
			_expect(mesh_vertices[0].distance_to(anchor_canvas) < 0.01, "実メッシュ根元が頭部アンカーから外れました: " + label)
		_expect(head.scale.is_equal_approx(original_scale), "端点で頭を縮小しました: " + label)
		var expected_elevation: float = -(normalized / actor.MAX_TRAVEL_DIAMETERS) * actor.neck_gaze_max_degrees
		var expected_rotation: float = deg_to_rad(-expected_elevation * actor.facing)
		_expect(absf(actor.neck_gaze_elevation_degrees() - expected_elevation) < 0.0001, "首位置と仰角が一致しません: " + label)
		_expect(absf(head.rotation - expected_rotation) < 0.0001, "頭部回転が仰角と一致しません: " + label)
		_expect(absf(head.global_position.y - neutral.y) < 0.00001, "仰角連動で頭部を上下移動しました: " + label)
		_expect(mesh_node.current_vertices.size() == neutral_geometry.size(), "柔軟化でメッシュ頂点数が変わりました: " + label)
		_expect(mesh_node.current_vertices[0].distance_to(Vector2.ZERO) < 0.001, "柔軟化で根元頂点が移動しました: " + label)
		for point in mesh_node.current_vertices:
			_expect(point.is_finite(), "柔軟化で非有限頂点が発生しました: " + label)
		_expect(_difference(mesh_node.current_vertices, neutral_geometry) < 0.003, "静止端点で柔らかさが恒常変形を残しました: " + label)
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
	# 静止端点では0.0/1.0ともrestへ収束し、柔らかさを恒常的な曲げ量で表現しない。
	scene.set_ratio(0.4)
	var static_soft: PackedVector2Array = mesh_node.current_vertices.duplicate()
	actor.set_ahoge_softness(0.0)
	scene._softness.set_value_no_signal(0.0)
	scene.set_ratio(0.4)
	var static_rigid: PackedVector2Array = mesh_node.current_vertices.duplicate()
	_expect(_difference(static_soft, static_rigid) < 0.003, "静止状態に柔らかさ由来の恒常差が残りました: " + label)

	# 約0.15秒で後端→前端へ切り返し、根元→中央→毛先の位相差を確認する。
	actor.set_ahoge_softness(1.0)
	scene._softness.set_value_no_signal(1.0)
	scene.set_ratio(-0.4)
	actor.reset_ahoge_soft_follow()
	var sweep_seconds: float = 0.15
	var sweep_frames: int = maxi(2, ceili(sweep_seconds * fps))
	for sweep_frame in range(sweep_frames):
		var u: float = float(sweep_frame + 1) / float(sweep_frames)
		actor.set_neck_travel_ratio(lerpf(-0.4, 0.4, smoothstep(0.0, 1.0, u)))
		actor.advance_neck_preview(sweep_seconds / float(sweep_frames))
	var dynamic_points: PackedVector2Array = actor.mesh_canvas_vertices()
	var softened: PackedFloat32Array = actor.action_motion._softened_angles(actor.action_motion.rest_angles)
	var near_index: int = _nearest_fraction(actor.action_motion.fractions, 0.25)
	var middle_index: int = _nearest_fraction(actor.action_motion.fractions, 0.55)
	var tip_index: int = _nearest_fraction(actor.action_motion.fractions, 0.95)
	var near_lag: float = absf(wrapf(softened[near_index] - actor.action_motion.rest_angles[near_index], -PI, PI))
	var middle_lag: float = absf(wrapf(softened[middle_index] - actor.action_motion.rest_angles[middle_index], -PI, PI))
	var tip_lag: float = absf(wrapf(softened[tip_index] - actor.action_motion.rest_angles[tip_index], -PI, PI))
	_expect(near_lag < middle_lag and middle_lag < tip_lag, "根元→中央→毛先の伝播遅延になっていません: " + label)
	_expect(tip_lag > 0.20, "前方切り返しで毛先に十分な時間差が出ません: " + label)
	_expect(dynamic_points[0].distance_to(actor.ahoge_head_anchor_canvas_position()) < 0.01, "動的柔軟化で根元が頭部から外れました: " + label)

	# 前端で最大遅延時間より長く保持すると現在姿勢へ追いつく。
	var settle_seconds: float = 0.22
	for settle_frame in range(maxi(1, ceili(settle_seconds * fps))):
		actor.advance_neck_preview(1.0 / fps)
	var settled: PackedFloat32Array = actor.action_motion._softened_angles(actor.action_motion.rest_angles)
	var settled_tip_lag: float = absf(wrapf(settled[tip_index] - actor.action_motion.rest_angles[tip_index], -PI, PI))
	_expect(settled_tip_lag < 0.02, "前端保持後も毛先の過去姿勢が残り続けます: " + label)

	# 柔らかさ0では同じ高速入力でも伝播遅延を描画へ加えない。
	actor.set_ahoge_softness(0.0)
	scene._softness.set_value_no_signal(0.0)
	scene.set_ratio(-0.4)
	actor.reset_ahoge_soft_follow()
	for sweep_frame in range(sweep_frames):
		var u: float = float(sweep_frame + 1) / float(sweep_frames)
		actor.set_neck_travel_ratio(lerpf(-0.4, 0.4, smoothstep(0.0, 1.0, u)))
		actor.advance_neck_preview(sweep_seconds / float(sweep_frames))
	var rigid_local: PackedVector2Array = actor.action_motion.vertices_from_angles(actor.action_motion.rest_angles)
	_expect(_difference(mesh_node.current_vertices, rigid_local) < 0.003, "柔らかさ0で伝播遅延が描画されました: " + label)

	actor.set_ahoge_softness(1.0)
	scene._softness.set_value_no_signal(1.0)
	scene.set_ratio(0.4)
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
	var preview_frames: int = ceili(scene.ATTACK_PREVIEW_SECONDS * 2.0 * fps)
	for frame in range(preview_frames):
		scene._process(1.0 / fps)
		minimum = minf(minimum, scene.fighter.neck_travel_ratio)
		maximum = maxf(maximum, scene.fighter.neck_travel_ratio)
	_expect(absf(minimum + 0.4) < 0.0001 and absf(maximum - 0.4) < 0.0001, "攻撃速度テストが可動域全体を使っていません: " + label)
	scene.stop_oscillation()
	scene.set_ratio(0.0)
	scene.set_process(true)
	cases.append({"label": label, "diameter_px": d, "range_each_side_px": 0.4 * d, "span_px": absf(forward.x - backward.x), "gaze_max_degrees": 30.0, "asset": mesh_node.texture.resource_path})

func _nearest_fraction(values: PackedFloat32Array, target: float) -> int:
	var best_index: int = 0
	var best_distance: float = INF
	for i in range(values.size()):
		var distance: float = absf(values[i] - target)
		if distance < best_distance:
			best_distance = distance
			best_index = i
	return best_index


func _difference(a: PackedVector2Array, b: PackedVector2Array) -> float:
	if a.size() != b.size():
		return INF
	var maximum: float = 0.0
	for i in range(a.size()):
		maximum = maxf(maximum, a[i].distance_to(b[i]))
	return maximum


func _find_button(node: Node, text: String) -> Button:
	if node is Button and node.text == text:
		return node
	for child in node.get_children():
		var found: Button = _find_button(child, text)
		if found != null:
			return found
	return null
