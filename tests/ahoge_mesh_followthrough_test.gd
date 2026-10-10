extends SceneTree

const HudScene := preload("res://scenes/screens/battle/BattleHUD.tscn")
const StateScript := preload("res://src/domain/combatant_state.gd")
const ConfigScript := preload("res://src/config/combat_config.gd")
const CatalogScript := preload("res://src/domain/character_catalog.gd")
const ActionScript := preload("res://src/ui/ahoge_action_motion.gd")
const OUT: String = "res://artifacts/ahoge-mesh/followthrough/"
var failures: Array[String] = []
var records: Array = []
var checks: int = 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	await process_frame
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	if DisplayServer.get_name() == "headless":
		_expect(false, "振り抜き検査には実描画が必要です")
	else:
		for resolution in [Vector2i(1280, 720), Vector2i(1600, 900)]:
			for fps in [30, 60, 120]:
				for side in [0, 1]:
					for charge in [0.0, 1.0]:
						for opponent in ["SHORT_TEST", "LONG_TEST"]:
							await _cycle(resolution, fps, side, charge, opponent)
	_expect(records.size() == 48 and checks > 1000, "48条件の実検査が完了していません")
	var report: Dictionary = {"status": "PASS" if failures.is_empty() else "FAIL", "cases": records, "checks": checks, "failures": failures, "human_verification": "未実施"}
	var file: FileAccess = FileAccess.open(OUT + "report.json", FileAccess.WRITE)
	if file == null:
		push_error("振り抜き検証結果を保存できません")
		quit(1)
		return
	file.store_string(JSON.stringify(report, "  "))
	file.close()
	print("AHOGE deep follow-through: %s cases=%d checks=%d" % [report["status"], records.size(), checks])
	quit(0 if failures.is_empty() else 1)


func _cycle(resolution: Vector2i, fps: int, side: int, charge: float, opponent: String) -> void:
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
	var other = StateScript.new(config)
	state.attack_charge_ratio = charge
	var a = CatalogScript.get_by_id("LONG_TEST")
	var b = CatalogScript.get_by_id(opponent)
	if side == 0:
		hud.set_combatants(a, state, b, other)
	else:
		hud.set_combatants(b, other, a, state)
	await process_frame
	await process_frame
	var actor = director.fighters[side]
	var mesh_node = actor.find_child("AhogeDeformMesh", true, false)
	var label: String = "%d_%d_%d_%d_%s" % [resolution.x, fps, side, int(charge), opponent]
	_expect(hud.size.is_equal_approx(Vector2(resolution)), "HUD寸法: " + label)
	if mesh_node == null or not mesh_node.configured:
		_expect(false, "実メッシュがありません: " + label)
		viewport.free()
		return
	var capture: bool = resolution.x == 1280 and fps == 60 and side == 0
	var frames: Array = []
	var frame: int = 0
	var contact_tip: Vector2 = Vector2.ZERO
	var previous_tail_y: float = -INF
	var maximum_drop: float = 0.0
	var strike_end_drop: float = 0.0
	var contact_seen: bool = false
	var tail_end_seen: bool = false
	var continued_in_cooldown: bool = false
	var peak_parry: float = 0.0
	var phases: Array = [
		[StateScript.ActionState.IDLE, 0.10],
		[StateScript.ActionState.CHARGING, config.max_charge_seconds + 0.20 if charge > 0.0 else 0.02],
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
		var contact_seconds: float = config.attack_strike_seconds(charge) * config.attack_contact_ratio
		var cooldown_tail: float = ActionScript.FOLLOW_SECONDS - (config.attack_strike_seconds(charge) - contact_seconds)
		while elapsed < duration - 0.000001:
			var dt: float = minf(1.0 / fps, duration - elapsed)
			if state.action_state == StateScript.ActionState.STRIKE and elapsed < contact_seconds - 0.000001:
				dt = minf(dt, contact_seconds - elapsed)
			if state.action_state == StateScript.ActionState.COOLDOWN and elapsed < cooldown_tail - 0.000001:
				dt = minf(dt, cooldown_tail - elapsed)
			director.advance(dt)
			elapsed += dt
			var points: PackedVector2Array = actor.mesh_canvas_vertices()
			_expect(points.size() == 427, "実頂点数: " + label)
			if points.size() != 427:
				break
			for point in points:
				_expect(point.is_finite() and actor.arena_canvas_rect.grow(0.5).has_point(point), "画面内包含: " + label)
			var tip: Vector2 = points[-1]
			if state.action_state == StateScript.ActionState.STRIKE and not contact_seen and elapsed >= contact_seconds - 0.000001:
				contact_seen = true
				contact_tip = tip
				_expect(actor.last_contact_error <= 2.0, "接触誤差: " + label)
				if capture:
					await _save(viewport, "contact_" + label + ".png")
			var tail: float = actor.action_motion.follow_seconds()
			if contact_seen and tail >= 0.0 and tail <= ActionScript.FOLLOW_SECONDS + 0.000001:
				_expect(actor.last_safety_scale >= 0.999, "全体縮小で振り抜きを隠しています: " + label)
				_expect(tip.y >= previous_tail_y - 0.05, "下への振り抜きが途中で逆行しています: " + label)
				previous_tail_y = tip.y
				maximum_drop = maxf(maximum_drop, tip.y - contact_tip.y)
				if state.action_state == StateScript.ActionState.COOLDOWN:
					continued_in_cooldown = true
				var original: PackedVector2Array = points.duplicate()
				actor.present_toward(Vector2(-5000.0, -5000.0))
				_expect(_difference(original, actor.mesh_canvas_vertices()) < 0.002, "接触後に相手を追尾しています: " + label)
				if tail >= ActionScript.FOLLOW_SECONDS - 0.000001:
					tail_end_seen = true
					await _save(viewport, "lowest_" + label + ".png")
			if state.action_state == StateScript.ActionState.STRIKE and elapsed >= duration - 0.000001:
				strike_end_drop = tip.y - contact_tip.y
			if state.action_state == StateScript.ActionState.COOLDOWN and elapsed >= duration - 0.000001:
				_expect(actor.rendered_straighten() <= 0.001, "振り抜き後にC字へ戻りません: " + label)
			if state.action_state == StateScript.ActionState.PARRY and actor.action_motion.elapsed >= 0.055:
				var local: PackedVector2Array = mesh_node.current_vertices
				var transform: Transform2D = mesh_node.global_transform
				var displacement: float = (transform * local[-1]).distance_to(transform * mesh_node.profile.rest_vertices[-1])
				peak_parry = maxf(peak_parry, displacement * 1280.0 / resolution.x)
				_expect(actor.last_presentation_weight == 0.0, "パリィに遠方接触補正: " + label)
			if capture:
				frames.append({"frame": frame, "delta": dt, "state": int(state.action_state), "tail_seconds": tail, "tip": [tip.x, tip.y]})
				await _save(viewport, "cycle_%d_%s_%03d.png" % [int(charge), opponent, frame])
				frame += 1
	_expect(contact_seen and tail_end_seen and continued_in_cooldown, "接触からCOOLDOWNへ振り抜きが連続していません: " + label)
	_expect(maximum_drop >= 35.0, "接触後の下への振り抜きが浅い: " + label + " drop=" + str(maximum_drop))
	_expect(maximum_drop >= strike_end_drop + 8.0, "COOLDOWN開始で振り抜きが終わっています: " + label)
	_expect(peak_parry >= 60.0 and peak_parry <= 110.0, "パリィの毛先払い幅: " + label + " px=" + str(peak_parry))
	_expect(actor.rendered_straighten() <= 0.001, "最終復帰: " + label)
	# 振り抜き中に防御へ割り込んでも遠方補正を再生しない。
	state.action_state = StateScript.ActionState.STRIKE
	director.advance(0.001)
	actor.confirm_contact()
	director.advance(0.001)
	state.action_state = StateScript.ActionState.PARRY
	for i in range(18):
		director.advance(1.0 / 60.0)
	_expect(actor.action_motion.follow_seconds() < 0.0 and actor.last_presentation_weight == 0.0, "パリィへ振り抜きを持ち越しました: " + label)
	records.append({"label": label, "contact_seen": contact_seen, "tail_end_seen": tail_end_seen, "continued_in_cooldown": continued_in_cooldown, "maximum_drop_px": maximum_drop, "strike_end_drop_px": strike_end_drop, "parry_tip_travel_at_1280_px": peak_parry, "frames": frames})
	viewport.free()


func _difference(a: PackedVector2Array, b: PackedVector2Array) -> float:
	if a.size() != b.size():
		return INF
	var maximum: float = 0.0
	for i in range(a.size()):
		maximum = maxf(maximum, a[i].distance_to(b[i]))
	return maximum


func _save(viewport: SubViewport, name: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	var image: Image = viewport.get_texture().get_image()
	_expect(image != null and not image.is_empty(), "振り抜き画像が空です")
	if image != null:
		_expect(image.save_png(OUT + name) == OK, "振り抜き画像を保存できません")


func _expect(ok: bool, message: String) -> void:
	checks += 1
	if not ok and not failures.has(message):
		failures.append(message)
		push_error(message)
