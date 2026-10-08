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
	_expect(actor.action_motion.configured, "NeckRangeのActionMotionを構成できません: " + label)
	var tuning: Dictionary = actor.action_motion.soft_tuning_snapshot()
	_expect(tuning["control_targets"] == actor.NECK_SOFT_TUNING["control_targets"], "NeckRange専用control配置が未適用です: " + label)
	_expect(is_equal_approx(float(tuning["root_hinge_hz"]), 4.5), "NeckRange専用root hingeが未適用です: " + label)
	_expect(float(tuning["root_hinge_damping"]) >= 0.90, "NeckRange専用root dampingが不足しています: " + label)
	_expect(is_equal_approx(float(tuning["root_blend_end"]), 0.30), "NeckRange専用root blendが未適用です: " + label)
	_expect(is_equal_approx(float(tuning["root_start_weight"]), 0.35), "NeckRange専用root weightが未適用です: " + label)
	_expect(float(tuning["chain_hz"]) >= 12.0 and float(tuning["chain_hz"]) <= 16.0, "NeckRange専用chain Hzが不正です: " + label)
	_expect(float(tuning["root_damping"]) >= 0.80, "NeckRange専用chain root dampingが不足しています: " + label)
	_expect(float(tuning["tip_damping"]) >= 0.95, "NeckRange専用tip dampingが不足しています: " + label)
	_expect(
		float(tuning["tip_spring_gain"]) >= 0.15 and float(tuning["tip_spring_gain"]) <= 0.50,
		"NeckRange専用tip springが中央・毛先の遅延域から外れています: " + label
	)
	_expect(is_equal_approx(float(tuning["dynamic_curve_retention"]), 0.12), "NeckRange専用C字曲率解放が未適用です: " + label)
	_expect(float(tuning["directional_curve_retention"]) <= 0.001, "NeckRange方向targetへ待機C字曲率を残しています: " + label)
	_expect(float(tuning["directional_root_hz"]) >= 18.0 and float(tuning["directional_root_hz"]) <= 22.0, "NeckRange専用directional root Hzが不正です: " + label)
	_expect(float(tuning["directional_root_max_offset"]) >= 2.80, "NeckRange専用root伸長角が前方targetへ不足しています: " + label)
	_expect(float(tuning["directional_max_offset"]) >= 2.80, "NeckRange専用chain伸長角が前方targetへ不足しています: " + label)
	_expect(
		float(tuning["directional_control_step"]) >= 0.31 and float(tuning["directional_control_step"]) <= 0.33,
		"NeckRange専用root側control間位相差上限が候補域から外れています: " + label
	)
	_expect(
		float(tuning["directional_control_step_middle"]) >= 0.20
		and float(tuning["directional_control_step_middle"]) <= 0.24,
		"NeckRange専用middle側control間位相差上限が候補域から外れています: " + label
	)
	_expect(
		float(tuning["directional_control_step_tip"]) >= 0.08 and float(tuning["directional_control_step_tip"]) <= 0.10,
		"NeckRange専用tip側control間位相差上限が候補域から外れています: " + label
	)
	_expect(float(tuning["active_tip_mass"]) >= 1.50, "NeckRange専用の毛先慣性が不足しています: " + label)
	_expect(
		float(tuning["active_root_direct_gain"]) < float(tuning["active_tip_direct_gain"]),
		"NeckRange専用Active Driveが毛先側ほど強くなっていません: " + label
	)
	_expect(float(tuning["active_tip_drive_gain"]) >= 1.50, "NeckRange専用の毛先駆動gainが不足しています: " + label)
	_expect(float(tuning["active_tip_damping_ratio"]) < 0.80, "NeckRange専用の毛先慣性保持が不足しています: " + label)
	_expect(
		float(tuning["directional_clamp_upstream_blend"]) >= 0.999
		and float(tuning["directional_clamp_upstream_blend"]) <= 1.001,
		"NeckRange専用のclamp部分伝播率が候補域から外れています: " + label
	)
	_expect(
		float(tuning["active_preload_contraction"]) >= -0.037
		and float(tuning["active_preload_contraction"]) <= -0.033,
		"NeckRange専用の弾性溜め量が候補域から外れています: " + label
	)
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

	# 攻撃速度テストの正本:
	# 後端では後方へ伸び、切り返しで根元→中央→毛先の順に反転し、前端では前方へ伸びる。
	actor.set_ahoge_softness(1.0)
	scene._softness.set_value_no_signal(1.0)
	scene.set_ratio(-0.4)
	actor.set_neck_ahoge_directional_extension(1.0, -1.0)
	actor.reset_ahoge_soft_follow()
	var rest_angles: PackedFloat32Array = actor.action_motion.rest_angles
	var rest_curvature: float = _body_curvature(rest_angles, actor.action_motion.fractions, 0.75)
	var rest_length: float = 0.0
	for segment_length in actor.action_motion._lengths:
		rest_length += float(segment_length)
	_expect(rest_curvature > 0.10 and rest_length > 100.0, "待機C字の基準弧長を取得できません: " + label)

	var rear_frames: int = maxi(1, ceili(scene.REAR_HOLD_SECONDS * fps))
	for rear_frame in range(rear_frames):
		var rear_seconds: float = scene.REAR_HOLD_SECONDS * float(rear_frame + 1) / float(rear_frames)
		actor.set_neck_ahoge_attack_profile(
			scene.attack_preview_active_progress(rear_seconds),
			scene.attack_preview_elastic_stretch(rear_seconds)
		)
		actor.advance_neck_preview(1.0 / fps)
	var rear_vertices: PackedVector2Array = mesh_node.current_vertices.duplicate()
	var rear_length: float = _mesh_centerline_length(actor.action_motion, rear_vertices)
	var rear_length_ratio: float = rear_length / rest_length
	_expect(rear_length_ratio >= 0.96 and rear_length_ratio < 1.0, "後端の溜めで適度な弾性圧縮になっていません: %s ratio=%f" % [label, rear_length_ratio])
	var rear_angles: PackedFloat32Array = actor.action_motion._softened_angles(rest_angles)
	var rear_curvature: float = _body_curvature(rear_angles, actor.action_motion.fractions, 0.75)
	_expect(rear_vertices[-1].x <= -rest_length * 0.70, "後端保持でアホ毛が十分後方へ伸びません: %s tip_x=%f length=%f" % [label, rear_vertices[-1].x, rest_length])
	_expect(absf(rear_vertices[-1].y) <= rest_length * 0.15, "後端保持でdirection targetから斜めへ外れています: %s tip=%s length=%f" % [label, str(rear_vertices[-1]), rest_length])
	_expect(rear_curvature <= 0.25, "後端保持がほぼ直線ではありません: %s rest=%f rear=%f" % [label, rest_curvature, rear_curvature])
	_expect(actor.mesh_canvas_vertices()[0].distance_to(actor.ahoge_head_anchor_canvas_position()) < 0.01, "後方伸長で根元が頭部から外れました: " + label)

	var sweep_seconds: float = scene.STRIKE_SWING_SECONDS
	var sweep_frames: int = maxi(2, ceili(sweep_seconds * fps))
	var near_cross: float = INF
	var middle_cross: float = INF
	var tip_cross: float = INF
	var observed_seconds: float = 0.0
	var maximum_transition_curvature: float = 0.0
	var maximum_stretch_ratio: float = rear_length_ratio
	var peak_visible_speeds := PackedFloat32Array([0.0, 0.0, 0.0])
	var peak_control_speeds := PackedFloat32Array([0.0, 0.0, 0.0])
	var peak_control_times := PackedFloat32Array([INF, INF, INF])
	var previous_points: Array[Vector2] = _mesh_chain_points(actor.action_motion, rear_vertices, [0.20, 0.55, 0.95])
	for sweep_frame in range(sweep_frames):
		var u: float = float(sweep_frame + 1) / float(sweep_frames)
		var step_seconds: float = sweep_seconds / float(sweep_frames)
		var phase_seconds: float = scene.REAR_HOLD_SECONDS + sweep_seconds * u
		var direction: float = scene.attack_preview_direction(phase_seconds)
		actor.set_neck_ahoge_directional_extension(1.0, direction)
		actor.set_neck_ahoge_attack_profile(
			scene.attack_preview_active_progress(phase_seconds),
			scene.attack_preview_elastic_stretch(phase_seconds)
		)
		actor.set_neck_travel_ratio(lerpf(-0.4, 0.4, smoothstep(0.0, 1.0, u)))
		actor.advance_neck_preview(step_seconds)
		observed_seconds += step_seconds
		var sweep_angles: PackedFloat32Array = actor.action_motion._softened_angles(rest_angles)
		maximum_transition_curvature = maxf(maximum_transition_curvature, _body_curvature(sweep_angles, actor.action_motion.fractions, 1.0))
		var front_hold_angles: PackedFloat32Array = actor.action_motion._softened_angles(rest_angles)
		maximum_transition_curvature = maxf(maximum_transition_curvature, _body_curvature(front_hold_angles, actor.action_motion.fractions, 1.0))
		var current_length: float = _mesh_centerline_length(actor.action_motion, mesh_node.current_vertices)
		maximum_stretch_ratio = maxf(maximum_stretch_ratio, current_length / rest_length)
		_track_soft_peaks(actor.action_motion, observed_seconds, peak_control_speeds, peak_control_times)
		var points: Array[Vector2] = _mesh_chain_points(actor.action_motion, mesh_node.current_vertices, [0.20, 0.55, 0.95])
		for slot in range(points.size()):
			var forward_speed: float = (points[slot].x - previous_points[slot].x) / step_seconds
			if forward_speed > peak_visible_speeds[slot]:
				peak_visible_speeds[slot] = forward_speed
		previous_points = points
		var phase_points: Array[Vector2] = _soft_chain_points(actor.action_motion, [0.20, 0.55, 0.95])
		if near_cross == INF and phase_points[0].x > 0.0:
			near_cross = observed_seconds
		if middle_cross == INF and phase_points[1].x > 0.0:
			middle_cross = observed_seconds
		if tip_cross == INF and phase_points[2].x > 0.0:
			tip_cross = observed_seconds
		if fps == 60 and side == 0 and resolution == 0 and DisplayServer.get_name() != "headless":
			await _save_dynamic_frame(scene.viewport, "strike_%02d.png" % sweep_frame)

	# 前端保持中も追跡し、毛先が最後に前方へ抜けるまでを見る。
	actor.set_neck_ahoge_directional_extension(1.0, 1.0)
	actor.set_neck_travel_ratio(0.4)
	var front_frames: int = maxi(1, ceili(scene.FRONT_HOLD_SECONDS * fps))
	for front_frame in range(front_frames):
		var step_seconds: float = 1.0 / fps
		var phase_seconds: float = scene.REAR_HOLD_SECONDS + scene.STRIKE_SWING_SECONDS + step_seconds * float(front_frame + 1)
		actor.set_neck_ahoge_attack_profile(
			scene.attack_preview_active_progress(phase_seconds),
			scene.attack_preview_elastic_stretch(phase_seconds)
		)
		actor.advance_neck_preview(step_seconds)
		observed_seconds += step_seconds
		var current_length: float = _mesh_centerline_length(actor.action_motion, mesh_node.current_vertices)
		maximum_stretch_ratio = maxf(maximum_stretch_ratio, current_length / rest_length)
		_track_soft_peaks(actor.action_motion, observed_seconds, peak_control_speeds, peak_control_times)
		var points: Array[Vector2] = _mesh_chain_points(actor.action_motion, mesh_node.current_vertices, [0.20, 0.55, 0.95])
		for slot in range(points.size()):
			var forward_speed: float = (points[slot].x - previous_points[slot].x) / step_seconds
			if forward_speed > peak_visible_speeds[slot]:
				peak_visible_speeds[slot] = forward_speed
		previous_points = points
		var phase_points: Array[Vector2] = _soft_chain_points(actor.action_motion, [0.20, 0.55, 0.95])
		if near_cross == INF and phase_points[0].x > 0.0:
			near_cross = observed_seconds
		if middle_cross == INF and phase_points[1].x > 0.0:
			middle_cross = observed_seconds
		if tip_cross == INF and phase_points[2].x > 0.0:
			tip_cross = observed_seconds
		if fps == 60 and side == 0 and resolution == 0 and DisplayServer.get_name() != "headless" and front_frame in [0, 3, 7, 11]:
			await _save_dynamic_frame(scene.viewport, "front_%02d.png" % front_frame)

	var front_vertices: PackedVector2Array = mesh_node.current_vertices.duplicate()
	var front_angles: PackedFloat32Array = actor.action_motion._softened_angles(rest_angles)
	var front_curvature: float = _body_curvature(front_angles, actor.action_motion.fractions, 0.75)
	_expect(near_cross < middle_cross and middle_cross < tip_cross and tip_cross < INF, "前方反転が根元→中央→毛先の順になっていません: %s times=[%f,%f,%f]" % [label, near_cross, middle_cross, tip_cross])
	_expect(front_vertices[-1].x >= rest_length * 0.70, "前端保持でアホ毛が十分前方へ伸びません: %s tip_x=%f length=%f" % [label, front_vertices[-1].x, rest_length])
	_expect(absf(front_vertices[-1].y) <= rest_length * 0.15, "前端保持でdirection targetから斜めへ外れています: %s tip=%s length=%f" % [label, str(front_vertices[-1]), rest_length])
	_expect(front_curvature <= 0.25, "前端保持がほぼ直線ではありません: %s rest=%f front=%f" % [label, rest_curvature, front_curvature])
	_expect(maximum_transition_curvature <= 2.20, "切り返し中に毛束が輪状へ巻き込んでいます: %s curvature=%f" % [label, maximum_transition_curvature])
	_expect(maximum_stretch_ratio >= 1.04 and maximum_stretch_ratio <= 1.07, "前方攻撃の弾性伸長が少量の範囲から外れています: %s ratio=%f" % [label, maximum_stretch_ratio])
	_expect(
		peak_control_times[0] < peak_control_times[1] and peak_control_times[1] < peak_control_times[2],
		"角速度ピークがroot→middle→tipの順ではありません: %s times=%s speeds=%s" % [label, str(peak_control_times), str(peak_control_speeds)]
	)
	_expect(
		peak_visible_speeds[2] >= peak_visible_speeds[1] * 1.08,
		"毛先へ実描画の前方速度が集まっていません: %s speeds=%s" % [label, str(peak_visible_speeds)]
	)
	_expect(actor.mesh_canvas_vertices()[0].distance_to(actor.ahoge_head_anchor_canvas_position()) < 0.01, "前方伸長で根元が頭部から外れました: " + label)

	# 方向targetを解除して停止すると待機C字へ戻る。
	actor.set_neck_ahoge_directional_extension(0.0, 0.0)
	actor.set_neck_ahoge_attack_profile(-1.0, 0.0)
	var settle_seconds: float = 1.20
	for settle_frame in range(maxi(1, ceili(settle_seconds * fps))):
		actor.advance_neck_preview(1.0 / fps)
	var settled: PackedFloat32Array = actor.action_motion._softened_angles(rest_angles)
	var settled_curvature: float = _body_curvature(settled, actor.action_motion.fractions, 0.75)
	_expect(absf(settled_curvature - rest_curvature) <= rest_curvature * 0.08, "停止後に待機C字へ戻りません: %s rest=%f settled=%f" % [label, rest_curvature, settled_curvature])

	# 柔らかさ0では同じ高速入力でもchainの動的offsetを描画へ加えない。
	actor.set_ahoge_softness(0.0)
	scene._softness.set_value_no_signal(0.0)
	scene.set_ratio(-0.4)
	actor.reset_ahoge_soft_follow()
	for sweep_frame in range(sweep_frames):
		var u: float = float(sweep_frame + 1) / float(sweep_frames)
		actor.set_neck_travel_ratio(lerpf(-0.4, 0.4, smoothstep(0.0, 1.0, u)))
		actor.advance_neck_preview(sweep_seconds / float(sweep_frames))
	var rigid_local: PackedVector2Array = actor.action_motion.vertices_from_angles(actor.action_motion.rest_angles)
	_expect(_difference(mesh_node.current_vertices, rigid_local) < 0.003, "柔らかさ0でchain動作が描画されました: " + label)

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

func _mesh_centerline(action_motion, vertices: PackedVector2Array) -> PackedVector2Array:
	var result := PackedVector2Array()
	if vertices.size() < 3:
		return result
	var width: int = int(action_motion._profile.WIDTH_POINTS)
	if width <= 0 or (vertices.size() - 2) % width != 0:
		return result
	result.append(vertices[0])
	var rows: int = (vertices.size() - 2) / width
	for row in range(rows):
		var center := Vector2.ZERO
		var base: int = 1 + row * width
		for column in range(width):
			center += vertices[base + column]
		result.append(center / float(width))
	result.append(vertices[-1])
	return result


func _mesh_centerline_length(action_motion, vertices: PackedVector2Array) -> float:
	var centers: PackedVector2Array = _mesh_centerline(action_motion, vertices)
	var total: float = 0.0
	for i in range(1, centers.size()):
		total += centers[i].distance_to(centers[i - 1])
	return total


func _mesh_chain_points(action_motion, vertices: PackedVector2Array, targets: Array[float]) -> Array[Vector2]:
	var centers: PackedVector2Array = _mesh_centerline(action_motion, vertices)
	var result: Array[Vector2] = []
	if centers.size() != action_motion.fractions.size() + 1:
		for _target in targets:
			result.append(Vector2.ZERO)
		return result
	for target in targets:
		var segment_index: int = _nearest_fraction(action_motion.fractions, target)
		result.append(centers[clampi(segment_index + 1, 0, centers.size() - 1)])
	return result


func _soft_chain_points(action_motion, targets: Array[float]) -> Array[Vector2]:
	var angles: PackedFloat32Array = action_motion._softened_angles(action_motion.rest_angles)
	var result: Array[Vector2] = []
	for target in targets:
		var point: Vector2 = Vector2.ZERO
		for i in range(angles.size()):
			point += Vector2.from_angle(angles[i]) * action_motion._lengths[i]
			if action_motion.fractions[i] >= target:
				break
		result.append(point)
	return result


func _body_curvature(angles: PackedFloat32Array, fractions: PackedFloat32Array, max_fraction: float) -> float:
	if angles.size() < 2 or angles.size() != fractions.size():
		return 0.0
	var total: float = 0.0
	for i in range(1, angles.size()):
		if fractions[i] > max_fraction:
			break
		total += absf(wrapf(angles[i] - angles[i - 1], -PI, PI))
	return total


func _soft_shape_metrics(action_motion) -> Vector3:
	var softened: PackedFloat32Array = action_motion._softened_angles(action_motion.rest_angles)
	if softened.size() != action_motion.rest_angles.size():
		return Vector3.ZERO
	var i03: int = _nearest_fraction(action_motion.fractions, 0.03)
	var i12: int = _nearest_fraction(action_motion.fractions, 0.12)
	var i28: int = _nearest_fraction(action_motion.fractions, 0.28)
	var i95: int = _nearest_fraction(action_motion.fractions, 0.95)
	var o03: float = wrapf(softened[i03] - action_motion.rest_angles[i03], -PI, PI)
	var o12: float = wrapf(softened[i12] - action_motion.rest_angles[i12], -PI, PI)
	var o28: float = wrapf(softened[i28] - action_motion.rest_angles[i28], -PI, PI)
	var o95: float = wrapf(softened[i95] - action_motion.rest_angles[i95], -PI, PI)
	var root_zone: float = maxf(absf(o03), maxf(absf(o12), absf(o28)))
	var root_curve: float = absf(o12 - o03) + absf(o28 - o12)
	return Vector3(root_zone, root_curve, absf(o95))


func _track_soft_peaks(action_motion, seconds: float, peak_speeds: PackedFloat32Array, peak_times: PackedFloat32Array) -> void:
	var velocities: PackedFloat32Array = action_motion.soft_control_velocities()
	if velocities.size() != action_motion.SOFT_CONTROL_COUNT:
		return
	var indices: Array[int] = [0, action_motion.SOFT_CONTROL_COUNT / 2, action_motion.SOFT_CONTROL_COUNT - 1]
	for slot in range(indices.size()):
		var speed: float = absf(velocities[indices[slot]])
		if speed > peak_speeds[slot]:
			peak_speeds[slot] = speed
			peak_times[slot] = seconds


func _save_dynamic_frame(viewport: SubViewport, name: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	var image: Image = viewport.get_texture().get_image()
	_expect(image != null and not image.is_empty(), "動的柔軟追従の描画が空です: " + name)
	if image != null and not image.is_empty():
		_expect(image.save_png(OUT + name) == OK, "動的柔軟追従の画像保存失敗: " + name)


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
