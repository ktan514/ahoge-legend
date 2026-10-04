extends SceneTree

const HudScene := preload("res://scenes/screens/battle/BattleHUD.tscn")
const StateScript := preload("res://src/domain/combatant_state.gd")
const ConfigScript := preload("res://src/config/combat_config.gd")
const CatalogScript := preload("res://src/domain/character_catalog.gd")
const OUT: String = "res://artifacts/ahoge-mesh/contact/"
var failures: Array[String] = []
var records: Array = []
var maximum_error: float = 0.0
var minimum_guard: float = 1.0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	await process_frame
	if DisplayServer.get_name() == "headless":
		push_error("接触検査には実描画が必要です。")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	for resolution in [Vector2i(1280, 720), Vector2i(1600, 900)]:
		for fps in [30, 60, 120]:
			for side in [0, 1]:
				for charge in [0.0, 1.0]:
					for opponent in ["SHORT_TEST", "LONG_TEST"]:
						await _cycle(resolution, fps, side, charge, opponent)
	var report: Dictionary = {"status": "PASS" if failures.is_empty() else "FAIL", "maximum_contact_error_px": maximum_error, "minimum_safety_scale": minimum_guard, "cases": records, "failures": failures, "human_verification": "未実施"}
	var file: FileAccess = FileAccess.open(OUT + "report.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "  "))
	file.close()
	print("AHOGE Battle contact: %s cases=%d max_error=%f" % [report["status"], records.size(), maximum_error])
	quit(0 if failures.is_empty() else 1)


func _cycle(resolution: Vector2i, fps: int, side: int, charge: float, opponent_id: String) -> void:
	var viewport: SubViewport = SubViewport.new()
	viewport.size = resolution
	viewport.disable_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var hud = HudScene.instantiate()
	hud.size = Vector2(resolution)
	viewport.add_child(hud)
	var director = hud.contact_director
	director.set_process(false)
	var config = ConfigScript.new()
	var a_state = StateScript.new(config)
	var b_state = StateScript.new(config)
	a_state.attack_charge_ratio = charge
	var a_character = CatalogScript.get_by_id("LONG_TEST")
	var b_character = CatalogScript.get_by_id(opponent_id)
	if side == 0:
		hud.set_combatants(a_character, a_state, b_character, b_state)
	else:
		hud.set_combatants(b_character, b_state, a_character, a_state)
	await process_frame
	await process_frame
	var attacker = director.fighters[side]
	var defender = director.fighters[1 - side]
	var area: Control = hud.find_child("BattleArea", true, false) as Control
	var label: String = "%d_%d_%d_%d_%s" % [resolution.x, fps, side, int(charge), opponent_id]
	var record: Dictionary = {"label": label, "strike_seconds": config.attack_strike_seconds(charge)}
	var phases: Array = [
		[StateScript.ActionState.IDLE, 0.1],
		[StateScript.ActionState.CHARGING, config.max_charge_seconds if charge > 0.0 else 0.02],
		[StateScript.ActionState.WINDUP, config.attack_windup_seconds(charge)],
		[StateScript.ActionState.STRIKE, config.attack_strike_seconds(charge)],
		[StateScript.ActionState.COOLDOWN, config.attack_cooldown_seconds(charge)]
	]
	var capture_sequence: bool = resolution.x == 1280 and fps == 60 and side == 0 and opponent_id == "SHORT_TEST"
	var frame: int = 0
	var contact_checked: bool = false
	for phase in phases:
		a_state.action_state = int(phase[0])
		var duration: float = float(phase[1])
		var elapsed: float = 0.0
		while elapsed < duration - 0.000001:
			var dt: float = minf(1.0 / float(fps), duration - elapsed)
			var contact_time: float = duration * config.attack_contact_ratio
			if a_state.action_state == StateScript.ActionState.STRIKE and elapsed < contact_time - 0.000001:
				dt = minf(dt, contact_time - elapsed)
			director.advance(dt)
			elapsed += dt
			_check_bounds(director, label)
			if a_state.action_state == StateScript.ActionState.STRIKE and not contact_checked and elapsed >= contact_time - 0.000001:
				contact_checked = true
				var error: float = float(attacker.last_contact_error)
				maximum_error = maxf(maximum_error, error)
				_expect(error <= 2.0, "毛先が相手に届いていません: " + label + " error=" + str(error))
				_expect(float(attacker.rendered_straighten()) >= 0.999, "接触時に毛先が直線化していません: " + label)
				_expect(float(attacker.last_safety_scale) >= 0.999, "接触姿勢が画面保護によって縮んでいます: " + label)
				record["contact_error_px"] = error
				record["straighten"] = attacker.rendered_straighten()
				var image: Image = await _capture(viewport, "contact_" + label + ".png")
				attacker.visible = false
				var without: Image = await _image(viewport)
				attacker.visible = true
				var changed: int = _contact_pixels(image, without, defender.contact_canvas_position())
				record["visible_tip_pixels_near_target"] = changed
				_expect(changed >= 2, "接触位置の近傍に描画された毛先がありません: " + label)
			if capture_sequence:
				await _capture(viewport, "cycle_%d_%03d.png" % [int(charge), frame])
				frame += 1
	_expect(contact_checked, "接触時刻を検査していません: " + label)
	_expect(float(attacker.rendered_straighten()) <= 0.001, "攻撃後にC字へ戻っていません: " + label)

	# 実Hitを表示するframeと、重複・防御中断・非表示からの再発を検査する。
	a_state.action_state = StateScript.ActionState.STRIKE
	director.advance(0.001)
	director.notify_confirmed_contact(side, 100, 10)
	director.advance(0.001)
	_expect(float(attacker.last_contact_error) <= 2.0 and float(attacker.rendered_straighten()) >= 0.999, "確定Hitの表示が接触していません: " + label)
	a_state.action_state = StateScript.ActionState.PARRY
	for i in range(30):
		director.advance(1.0 / 60.0)
		_check_bounds(director, label + " parry")
	_expect(float(attacker.rendered_straighten()) <= 0.001, "パリィ後に接触姿勢が残っています: " + label)
	director.notify_confirmed_contact(side, 100, 10)
	director.advance(0.001)
	_expect(float(attacker.rendered_straighten()) <= 0.001, "重複Hitが再生されています: " + label)
	a_state.action_state = StateScript.ActionState.STRIKE
	director.advance(0.001)
	director.notify_confirmed_contact(side, 110, 11)
	director.advance(0.001)
	a_state.ahoge_available = false
	director.advance(0.001)
	a_state.ahoge_available = true
	director.advance(0.001)
	_expect(float(attacker.rendered_straighten()) <= 0.001, "再表示で古い接触姿勢が再生されています: " + label)
	a_state.action_state = StateScript.ActionState.ROUND_LOCKED
	director.advance(0.01)
	_expect(float(attacker.rendered_straighten()) <= 0.001, "Round lockで古い攻撃が残っています: " + label)
	record["area"] = {"position": [area.global_position.x, area.global_position.y], "size": [area.size.x, area.size.y]}
	records.append(record)
	viewport.free()


func _check_bounds(director, label: String) -> void:
	for actor in director.fighters:
		var bounds: Rect2 = actor.arena_canvas_rect
		var head: Rect2 = actor.head_canvas_bounds()
		_expect(head.position.x >= bounds.position.x - 1.0 and head.end.x <= bounds.end.x + 1.0, "頭部が左右で見切れています: " + label)
		minimum_guard = minf(minimum_guard, float(actor.last_safety_scale))
		var points: PackedVector2Array = actor.mesh_canvas_vertices()
		for point in points:
			if not bounds.grow(0.5).has_point(point):
				_expect(false, "アホ毛がBattle領域外です: " + label)
				break


func _contact_pixels(with_actor: Image, without_actor: Image, target: Vector2) -> int:
	var changed: int = 0
	for y in range(maxi(0, int(target.y) - 9), mini(with_actor.get_height(), int(target.y) + 10)):
		for x in range(maxi(0, int(target.x) - 9), mini(with_actor.get_width(), int(target.x) + 10)):
			var a: Color = with_actor.get_pixel(x, y)
			var b: Color = without_actor.get_pixel(x, y)
			if absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b) > 0.04:
				changed += 1
	return changed


func _image(viewport: SubViewport) -> Image:
	await process_frame
	await RenderingServer.frame_post_draw
	return viewport.get_texture().get_image()


func _capture(viewport: SubViewport, name: String) -> Image:
	var image: Image = await _image(viewport)
	_expect(image != null and not image.is_empty(), "描画画像が空です")
	if image != null:
		_expect(image.save_png(OUT + name) == OK, "描画画像を保存できません")
	return image


func _expect(ok: bool, message: String) -> void:
	if not ok and not failures.has(message):
		failures.append(message)
		push_error(message)
