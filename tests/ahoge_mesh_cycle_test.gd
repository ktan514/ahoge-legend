extends SceneTree

const FighterScript := preload("res://src/ui/fighter_visual.gd")
const StateScript := preload("res://src/domain/combatant_state.gd")
const ConfigScript := preload("res://src/config/combat_config.gd")
const CatalogScript := preload("res://src/domain/character_catalog.gd")
const OUT: String = "res://artifacts/ahoge-mesh/"
var failures: Array[String] = []
var records: Array = []
var max_root_error: float = 0.0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	await process_frame
	if DisplayServer.get_name() == "headless":
		push_error("攻撃cycleの描画試験には描画バックエンドが必要です。")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var viewport: SubViewport = SubViewport.new()
	viewport.size = Vector2i(1280, 720)
	viewport.disable_3d = true
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	for fps in [30, 60, 120]:
		for direction in [1.0, -1.0]:
			for charge in [0.0, 1.0]:
				await _cycle(viewport, fps, direction, charge)
	var report: Dictionary = {
		"status": "PASS" if failures.is_empty() else "FAIL",
		"cycles": records,
		"max_root_error_px": max_root_error,
		"failures": failures,
		"human_verification": "未実施",
	}
	var file: FileAccess = FileAccess.open(OUT + "cycles.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "  "))
	file.close()
	viewport.free()
	print("AHOGE mesh cycles: %s cycles=%d root_error=%f" % [report["status"], records.size(), max_root_error])
	quit(0 if failures.is_empty() else 1)


func _cycle(viewport: SubViewport, fps: int, direction: float, charge: float) -> void:
	var config = ConfigScript.new()
	var state = StateScript.new(config)
	state.attack_charge_ratio = charge
	var fighter = FighterScript.new()
	fighter.size = Vector2(420.0, 460.0)
	fighter.position = Vector2(65.0 if direction > 0.0 else 795.0, 240.0)
	fighter.configure(CatalogScript.get_by_id("LONG_TEST"), state, direction)
	viewport.add_child(fighter)
	fighter.set_process(false)
	var rig = fighter.find_child("AhogePrototypeRig", true, false)
	var mesh_node = fighter.find_child("AhogeDeformMesh", true, false)
	var head: Sprite2D = fighter.find_child("HeadSprite", true, false) as Sprite2D
	_expect(rig != null and mesh_node != null and head != null, "製品FighterVisualにメッシュがありません")
	if rig == null or mesh_node == null or head == null:
		fighter.free()
		return
	rig.set_process(false)
	_expect(rig.debug_mesh_active(), "製品描画がSpriteへfallbackしています")
	if not rig.debug_mesh_active():
		fighter.free()
		return
	await process_frame
	var label: String = "%d_%s_%d" % [fps, "left" if direction > 0 else "right", int(charge)]
	var phases: Array = [
		[StateScript.ActionState.IDLE, 0.10],
		[StateScript.ActionState.CHARGING, config.max_charge_seconds if charge > 0.0 else 0.02],
		[StateScript.ActionState.WINDUP, config.attack_windup_seconds(charge)],
		[StateScript.ActionState.STRIKE, config.attack_strike_seconds(charge)],
		[StateScript.ActionState.COOLDOWN, config.attack_cooldown_seconds(charge)],
	]
	var contact_amount: float = -1.0
	var frame_number: int = 0
	for phase in phases:
		state.action_state = int(phase[0])
		var elapsed: float = 0.0
		var duration: float = float(phase[1])
		while elapsed < duration - 0.000001:
			var delta: float = minf(1.0 / float(fps), duration - elapsed)
			fighter.call("_process", delta)
			rig.call("_process", delta)
			elapsed += delta
			_check_root(fighter, mesh_node)
			var amount: float = float(rig.debug_straighten())
			_expect(is_finite(amount) and amount >= 0.0 and amount <= 1.0, "変形パラメータが範囲外です")
			if state.action_state in [StateScript.ActionState.CHARGING, StateScript.ActionState.WINDUP]:
				_expect(amount <= 0.0001, "溜め中に先端直線化が発生しています")
			if state.action_state == StateScript.ActionState.STRIKE and contact_amount < 0.0 and elapsed + 0.000001 >= duration * config.attack_contact_ratio:
				contact_amount = amount
				_expect(amount >= 0.999, "実際の接触時刻に先端が伸び切っていません: " + label)
				await _capture(viewport, "contact_" + label + ".png")
			if fps == 60 and direction > 0.0 and (state.action_state == StateScript.ActionState.STRIKE or (state.action_state == StateScript.ActionState.COOLDOWN and elapsed < 0.22)):
				await _capture(viewport, "cycle_%d_%03d.png" % [int(charge), frame_number])
				frame_number += 1
	_expect(float(rig.debug_straighten()) <= 0.001, "Cooldown後にC字へ戻っていません")

	# 攻撃中断、非表示と同一攻撃への再表示、Round lock復帰。
	state.action_state = StateScript.ActionState.STRIKE
	for i in range(4):
		fighter.call("_process", 1.0 / 60.0)
		rig.call("_process", 1.0 / 60.0)
	var before: float = float(rig.debug_straighten())
	state.action_state = StateScript.ActionState.PARRY
	fighter.call("_process", 1.0 / 60.0)
	rig.call("_process", 1.0 / 60.0)
	_expect(absf(float(rig.debug_straighten()) - before) < 0.1, "パリィ中断時に形状が飛んでいます")
	for i in range(20):
		fighter.call("_process", 1.0 / 60.0)
		rig.call("_process", 1.0 / 60.0)
		_check_root(fighter, mesh_node)
	_expect(float(rig.debug_straighten()) <= 0.001, "パリィ中断後に攻撃形状が残っています")
	state.action_state = StateScript.ActionState.STRIKE
	state.ahoge_available = false
	fighter.call("_process", 1.0 / 60.0)
	_expect(not rig.visible, "不在のアホ毛が表示されています")
	state.ahoge_available = true
	fighter.call("_process", 1.0 / 60.0)
	rig.call("_process", 1.0 / 60.0)
	_expect(float(rig.debug_straighten()) <= 0.001, "再表示で古い攻撃が再発しました")
	state.action_state = StateScript.ActionState.ROUND_LOCKED
	fighter.call("_process", 1.0 / 60.0)
	rig.call("_process", 1.0 / 60.0)
	_expect(float(rig.debug_straighten()) <= 0.001, "Round lockで攻撃形状が残りました")
	records.append({"fps": fps, "facing": direction, "charge": charge, "strike_seconds": config.attack_strike_seconds(charge), "straighten_at_contact": contact_amount})
	fighter.free()


func _check_root(fighter, mesh_node) -> void:
	var anchor: Vector2 = fighter.ahoge_head_anchor_canvas_position()
	var error: float = anchor.distance_to(mesh_node.to_global(Vector2.ZERO))
	max_root_error = maxf(max_root_error, error)
	_expect(error <= 0.01, "頭画像表面アンカーからアホ毛根元がずれています")


func _capture(viewport: SubViewport, name: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	var image: Image = viewport.get_texture().get_image()
	_expect(image != null and not image.is_empty(), "攻撃cycle画像が空です")
	if image != null:
		_expect(image.save_png(OUT + name) == OK, "攻撃cycle画像を保存できません")


func _expect(value: bool, message: String) -> void:
	if not value and not failures.has(message):
		failures.append(message)
		push_error(message)
