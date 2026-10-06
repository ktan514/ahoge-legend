extends SceneTree

const HudScene := preload("res://scenes/screens/battle/BattleHUD.tscn")
const StateScript := preload("res://src/domain/combatant_state.gd")
const ConfigScript := preload("res://src/config/combat_config.gd")
const CatalogScript := preload("res://src/domain/character_catalog.gd")
const ActionScript := preload("res://src/ui/ahoge_action_motion.gd")
const ParryScript := preload("res://src/ui/ahoge_parry_motion.gd")
const OUT: String = "res://artifacts/ahoge-mesh/actions/"
var failures: Array[String] = []
var records: Array = []
var samples: Array = []
var checks: int = 0
var minimum_area: float = INF
var maximum_length_error: float = 0.0
var maximum_width_error: float = 0.0
var geometry_frames: int = 0
var _profile
var _rest_length: float = 0.0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	await process_frame
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	_profile = load("res://assets/characters/prototype/charactor_01/ahoge_mesh_profile.tres")
	_expect(_profile != null and _profile.prepare(), "profileを準備できません")
	if _profile == null or not _profile.prepare():
		quit(1)
		return
	_rest_length = _length(ParryScript.centers_of(_profile.rest_vertices, _profile.WIDTH_POINTS))
	_check_release_order()
	if DisplayServer.get_name() == "headless":
		_expect(false, "三動作の検査には実描画が必要です")
	else:
		for resolution in [Vector2i(1280, 720), Vector2i(1600, 900)]:
			for fps in [30, 60, 120]:
				for side in [0, 1]:
					for charge in [0.0, 1.0]:
						await _cycle(resolution, fps, side, charge)
	_expect(records.size() == 24, "三動作の実行条件数が24ではありません")
	_expect(checks > 1000 and geometry_frames > 100, "検査が十分に実行されていません")
	var report: Dictionary = {"status": "PASS" if failures.is_empty() else "FAIL", "checks": checks, "geometry_frames": geometry_frames, "minimum_twice_area": minimum_area, "maximum_length_error": maximum_length_error, "maximum_width_error": maximum_width_error, "cases": records, "failures": failures, "human_verification": "未実施"}
	_write_json("report.json", report)
	_write_json("geometry_samples.json", {"boundary": _profile.boundary_indices, "samples": samples})
	print("AHOGE all actions: %s cases=%d checks=%d failures=%s" % [report["status"], records.size(), checks, JSON.stringify(failures)])
	quit(0 if failures.is_empty() else 1)


func _check_release_order() -> void:
	var peak_times: Array[float] = []
	for s in [0.25, 0.55, 0.98]:
		var peak: float = -INF
		var peak_time: float = 0.0
		for i in range(1, 601):
			var q: float = float(i) / 600.0
			var rate: float = ActionScript.release_at(q, s) - ActionScript.release_at(q - 1.0 / 600.0, s)
			if rate > peak:
				peak = rate
				peak_time = q
		peak_times.append(peak_time)
	_expect(peak_times[0] < peak_times[1] and peak_times[1] < peak_times[2], "しなり解放の速度ピークが根元側から先端の順ではありません")
	_expect(ActionScript.release_at(0.65, 0.98) < 0.6, "接触前に先端の遅れが失われています")
	_write_json("release_order.json", {"normalized_peak_times": peak_times})


func _cycle(resolution: Vector2i, fps: int, side: int, charge: float) -> void:
	var viewport: SubViewport = SubViewport.new()
	viewport.size = resolution
	viewport.disable_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var hud = HudScene.instantiate()
	viewport.add_child(hud)
	hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var director = hud.contact_director
	director.set_process(false)
	var config = ConfigScript.new()
	var state = StateScript.new(config)
	var other_state = StateScript.new(config)
	state.attack_charge_ratio = charge
	var character = CatalogScript.get_by_id("LONG_TEST")
	var other_character = CatalogScript.get_by_id("SHORT_TEST")
	if side == 0:
		hud.set_combatants(character, state, other_character, other_state)
	else:
		hud.set_combatants(other_character, other_state, character, state)
	await process_frame
	await process_frame
	var actor = director.fighters[side]
	var mesh_node = actor.find_child("AhogeDeformMesh", true, false)
	var label: String = "%d_%d_%d_%d" % [resolution.x, fps, side, int(charge)]
	var capture: bool = resolution.x == 1280 and fps == 60 and side == 0
	_expect(hud.size.is_equal_approx(Vector2(resolution)), "HUD寸法不一致: " + label)
	var rid: RID = mesh_node.mesh.get_rid()
	var frame: int = 0
	var trace: Array = []
	var contact_tip: Vector2 = Vector2.ZERO
	var end_tip: Vector2 = Vector2.ZERO
	var min_charge_guard: float = 1.0
	var max_parry_tip: float = 0.0
	var charge_softness_disabled: bool = false
	var windup_softness_seen: bool = false
	var strike_softness_seen: bool = false
	var parry_softness_disabled: bool = false
	var held_vertices: PackedVector2Array = PackedVector2Array()
	var hold_difference: float = 0.0
	var contact_seen: bool = false
	var max_active_length_ratio: float = 1.0
	var phases: Array = [
		[StateScript.ActionState.IDLE, 0.10],
		[StateScript.ActionState.CHARGING, config.max_charge_seconds + 0.40 if charge > 0.0 else 0.02],
		[StateScript.ActionState.WINDUP, config.attack_windup_seconds(charge)],
		[StateScript.ActionState.STRIKE, config.attack_strike_seconds(charge)],
		[StateScript.ActionState.COOLDOWN, config.attack_cooldown_seconds(charge)],
		[StateScript.ActionState.PARRY, config.parry_active_seconds + 1.0 / fps],
		[StateScript.ActionState.IDLE, 0.30]
	]
	for phase in phases:
		state.action_state = int(phase[0])
		var elapsed: float = 0.0
		var duration: float = float(phase[1])
		while elapsed < duration - 0.000001:
			var delta: float = minf(1.0 / fps, duration - elapsed)
			var contact_seconds: float = duration * config.attack_contact_ratio
			if state.action_state == StateScript.ActionState.STRIKE and elapsed < contact_seconds - 0.000001:
				delta = minf(delta, contact_seconds - elapsed)
			director.advance(delta)
			elapsed += delta
			var points: PackedVector2Array = actor.mesh_canvas_vertices()
			_expect(points.size() == 427, "実描画の頂点数が不正: " + label)
			if points.size() != 427:
				break
			for point in points:
				_expect(actor.arena_canvas_rect.grow(0.5).has_point(point), "三動作の途中でアホ毛が見切れました: " + label)
			var allow_active_stretch: bool = (
				state.action_state == StateScript.ActionState.STRIKE
				or (
					state.action_state == StateScript.ActionState.PARRY
					and actor.action_motion.elapsed < ParryScript.ENTRY_SECONDS + 0.000001
				)
			)
			_check_geometry(mesh_node.current_vertices, label, allow_active_stretch)
			var root: Vector2 = points[0]
			var tip: Vector2 = points[-1]
			if state.action_state == StateScript.ActionState.CHARGING:
				charge_softness_disabled = charge_softness_disabled or actor.action_motion.softness <= 0.001
				min_charge_guard = minf(min_charge_guard, actor.last_safety_scale)
				if charge > 0.0 and elapsed >= config.max_charge_seconds + 0.05:
					_expect(mesh_node.current_vertices[-1].x < -100.0, "最大溜めで毛先が後方にありません: " + label)
					_expect(mesh_node.current_vertices[-1].y > _profile.rest_vertices[-1].y + 100.0, "最大溜めで毛先が下へ垂れていません: " + label)
					if held_vertices.is_empty():
						held_vertices = mesh_node.current_vertices.duplicate()
					else:
						hold_difference = maxf(hold_difference, _difference(held_vertices, mesh_node.current_vertices))
			if state.action_state == StateScript.ActionState.WINDUP:
				windup_softness_seen = windup_softness_seen or actor.action_motion.softness >= 0.449
			if state.action_state == StateScript.ActionState.STRIKE:
				strike_softness_seen = strike_softness_seen or actor.action_motion.softness >= 0.999
				var active_length: float = _length(ParryScript.centers_of(mesh_node.current_vertices, 5))
				max_active_length_ratio = maxf(max_active_length_ratio, active_length / maxf(_rest_length, 0.001))
				trace.append({"time": elapsed, "root": [root.x, root.y], "near": [points[107].x, points[107].y], "middle": [points[237].x, points[237].y], "tip": [tip.x, tip.y]})
				if not contact_seen and elapsed >= contact_seconds - 0.000001:
					contact_seen = true
					contact_tip = tip
					_expect(actor.last_contact_error <= 2.0, "ムチ打ちが接触時刻に届いていません: " + label)
					_expect(actor.rendered_straighten() >= 0.999, "接触で先端までほどけていません: " + label)
					if capture:
						await _capture(viewport, "contact_" + label + ".png")
				if elapsed >= duration - 0.000001:
					end_tip = tip
					var before: PackedVector2Array = points.duplicate()
					actor.present_toward(Vector2(-3000.0, -3000.0))
					_expect(_difference(before, actor.mesh_canvas_vertices()) < 0.002, "振り抜きで相手位置を追尾しています: " + label)
			if state.action_state == StateScript.ActionState.PARRY and actor.action_motion.elapsed >= ParryScript.ENTRY_SECONDS:
				parry_softness_disabled = parry_softness_disabled or actor.action_motion.softness <= 0.001
				var local: PackedVector2Array = mesh_node.current_vertices
				var travel: float = local[-1].distance_to(_profile.rest_vertices[-1]) * resolution.x / 5200.0
				max_parry_tip = maxf(max_parry_tip, travel)
				_expect(actor.last_presentation_weight == 0.0, "パリィに長距離接触補正が掛かっています: " + label)
				var arc: PackedFloat32Array = ParryScript.arc_fractions(ParryScript.centers_of(_profile.rest_vertices, 5))
				for row in range(85):
					if arc[row + 1] <= 0.62:
						for col in range(5):
							var i: int = 1 + row * 5 + col
							_expect(local[i].distance_to(_profile.rest_vertices[i]) < 0.003, "パリィの固定部が動いています: " + label)
			if capture:
				if frame % 6 == 0:
					samples.append({"label": label, "state": int(state.action_state), "vertices": _pairs(mesh_node.current_vertices)})
				await _capture(viewport, "cycle_%d_%03d.png" % [int(charge), frame])
			frame += 1
	_expect(contact_seen, "接触を未検査: " + label)
	_expect(charge_softness_disabled, "CHARGING中に柔軟chainが最大溜め形へ重なっています: " + label)
	_expect(windup_softness_seen, "WINDUPへ柔軟chainが接続されていません: " + label)
	_expect(strike_softness_seen, "STRIKEへ動的柔軟追従が接続されていません: " + label)
	var expected_active_ratio: float = 1.08 if charge <= 0.001 else 1.16
	_expect(max_active_length_ratio >= expected_active_ratio, "STRIKEでアホ毛自身が十分に伸長していません: %s ratio=%f" % [label, max_active_length_ratio])
	_expect(max_active_length_ratio <= 1.50, "Active Strikeの伸長が上限を超えています: %s ratio=%f" % [label, max_active_length_ratio])
	_expect(parry_softness_disabled, "PARRYへ未承認の柔軟追従が混入しました: " + label)
	_expect(contact_tip.distance_to(end_tip) > 10.0, "接触後に毛先が貼り付いています: " + label)
	_expect(min_charge_guard >= 0.999, "チャージを全体縮小して見切れを隠しています: " + label)
	_expect(hold_difference < 0.003, "長押し保持中の形状が収束していません: " + label)
	_expect(max_parry_tip >= 10.0 and max_parry_tip < 110.0, "パリィが近距離の払いになっていません: " + label)
	var expected_idle: PackedVector2Array = actor.action_motion.visual_vertices_from_angles(actor.action_motion.rest_angles)
	_expect(_difference(mesh_node.current_vertices, expected_idle) < 0.003, "三動作後に柔らかい待機姿勢へ戻りません: " + label)
	_expect(rid == mesh_node.mesh.get_rid(), "三動作中にmesh RIDが変わりました: " + label)
	records.append({"label": label, "contact_checked": contact_seen, "follow_through_px": contact_tip.distance_to(end_tip), "minimum_charge_guard": min_charge_guard, "hold_difference": hold_difference, "parry_tip_travel_px": max_parry_tip, "trace": trace})
	viewport.free()


func _check_geometry(vertices: PackedVector2Array, label: String, allow_active_stretch: bool = false) -> void:
	geometry_frames += 1
	var centers: PackedVector2Array = ParryScript.centers_of(vertices, 5)
	var current_length: float = _length(centers)
	var length_error: float = absf(current_length - _rest_length)
	maximum_length_error = maxf(maximum_length_error, length_error)
	if allow_active_stretch:
		_expect(current_length >= _rest_length * 0.995 and current_length <= _rest_length * 1.50, "Active Strike/PARRY ENTRYの弧長が許容範囲外です: " + label)
	else:
		_expect(length_error < 0.04, "STRIKE以外で局所弧長が変化しました: " + label)
	for row in range(85):
		var left: int = 1 + row * 5
		var right: int = left + 4
		var width_error: float = absf(vertices[left].distance_to(vertices[right]) - _profile.rest_vertices[left].distance_to(_profile.rest_vertices[right]))
		maximum_width_error = maxf(maximum_width_error, width_error)
		_expect(width_error < 0.02, "三動作で断面幅が潰れました: " + label)
	for i in range(0, _profile.indices.size(), 3):
		var a: Vector2 = vertices[_profile.indices[i]]
		var b: Vector2 = vertices[_profile.indices[i + 1]]
		var c: Vector2 = vertices[_profile.indices[i + 2]]
		var area: float = (b - a).cross(c - a)
		minimum_area = minf(minimum_area, area)
		_expect(area > 0.0001, "三動作で面反転または退化: " + label)


func _length(centers: PackedVector2Array) -> float:
	var total: float = 0.0
	for i in range(1, centers.size()):
		total += centers[i].distance_to(centers[i - 1])
	return total


func _difference(a: PackedVector2Array, b: PackedVector2Array) -> float:
	if a.size() != b.size():
		return INF
	var result: float = 0.0
	for i in range(a.size()):
		result = maxf(result, a[i].distance_to(b[i]))
	return result


func _pairs(points: PackedVector2Array) -> Array:
	var result: Array = []
	for point in points:
		result.append([point.x, point.y])
	return result


func _write_json(name: String, value: Dictionary) -> void:
	var file: FileAccess = FileAccess.open(OUT + name, FileAccess.WRITE)
	if file == null:
		_expect(false, "結果ファイルを作成できません: " + name)
		return
	file.store_string(JSON.stringify(value, "  "))
	file.close()


func _capture(viewport: SubViewport, name: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	var image: Image = viewport.get_texture().get_image()
	_expect(image != null and not image.is_empty(), "三動作の実描画が空です")
	if image != null:
		_expect(image.save_png(OUT + name) == OK, "実描画を保存できません")


func _expect(ok: bool, message: String) -> void:
	checks += 1
	if not ok and not failures.has(message):
		failures.append(message)
		push_error(message)
