extends SceneTree

const HeadMotion := preload("res://src/ui/battle_head_motion.gd")
const HudScene := preload("res://scenes/screens/battle/BattleHUD.tscn")
const StateScript := preload("res://src/domain/combatant_state.gd")
const ConfigScript := preload("res://src/config/combat_config.gd")
const CatalogScript := preload("res://src/domain/character_catalog.gd")
const OUT: String = "res://artifacts/head-motion/"
var failures: Array[String] = []
var records: Array = []
var checks: int = 0
var max_anchor_error: float = 0.0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	await process_frame
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var entry := Vector3(-14.0, 5.0, -3.0)
	for action in [StateScript.ActionState.CHARGING, StateScript.ActionState.WINDUP, StateScript.ActionState.STRIKE, StateScript.ActionState.PARRY, StateScript.ActionState.COOLDOWN]:
		_expect(HeadMotion.sample(action, 0.0, 0.20, 0.60, entry).is_equal_approx(entry), "状態開始で頭部姿勢が飛びました")
	_expect(HeadMotion.sample(StateScript.ActionState.CHARGING, 5.0, 0.20, 0.60, entry).is_equal_approx(HeadMotion.CHARGE), "長押しで頭部が止まりません")
	for resolution in [Vector2i(1280, 720), Vector2i(1600, 900)]:
		for fps in [30, 60, 120]:
			for side in [0, 1]:
				for charge in [0.0, 1.0]:
					await _cycle(resolution, fps, side, charge)
	_expect(records.size() == 24, "頭部モーションの条件数が24ではありません")
	_expect(checks > 1000, "頭部モーションの検査が不足しています")
	var report := {"status": "PASS" if failures.is_empty() else "FAIL", "checks": checks, "cases": records, "failures": failures, "maximum_anchor_error_px": max_anchor_error, "new_asset_integrated": false, "human_verification": "未実施"}
	var output := FileAccess.open(OUT + "report.json", FileAccess.WRITE)
	if output == null:
		push_error("頭部の検証結果を保存できません")
		quit(1)
		return
	output.store_string(JSON.stringify(report, "  "))
	output.close()
	print("AHOGE head motion: %s cases=%d checks=%d anchor_error=%f failures=%s" % [report["status"], records.size(), checks, max_anchor_error, JSON.stringify(failures)])
	quit(0 if failures.is_empty() else 1)


func _cycle(resolution: Vector2i, fps: int, side: int, charge: float) -> void:
	var viewport := SubViewport.new()
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
	var long_character = CatalogScript.get_by_id("LONG_TEST")
	var short_character = CatalogScript.get_by_id("SHORT_TEST")
	if side == 0:
		hud.set_combatants(long_character, state, short_character, other)
	else:
		hud.set_combatants(short_character, other, long_character, state)
	await process_frame
	await process_frame
	var actor = director.fighters[side]
	var head := actor.find_child("HeadSprite", true, false) as Sprite2D
	var rig := actor.find_child("AhogePrototypeRig", true, false) as Node2D
	var label: String = "%d_%d_%d_%d" % [resolution.x, fps, side, int(charge)]
	_expect(head != null and rig != null, "頭部またはアホ毛がありません: " + label)
	if head == null or rig == null:
		viewport.free()
		return
	var phases: Array = [
		[StateScript.ActionState.IDLE, 0.10],
		[StateScript.ActionState.CHARGING, 0.80 if charge > 0.0 else 0.02],
		[StateScript.ActionState.WINDUP, config.attack_windup_seconds(charge)],
		[StateScript.ActionState.STRIKE, config.attack_strike_seconds(charge)],
		[StateScript.ActionState.COOLDOWN, config.attack_cooldown_seconds(charge)],
		[StateScript.ActionState.PARRY, config.parry_active_seconds + 1.0 / fps],
		[StateScript.ActionState.IDLE, 0.50]
	]
	var head_image: Image = head.texture.get_image()
	if head_image.is_compressed():
		head_image.decompress()
	var anchor_px: Vector2 = actor.ahoge_head_anchor_texture_position()
	var anchor_i := Vector2i(clampi(roundi(anchor_px.x), 0, head_image.get_width() - 1), clampi(roundi(anchor_px.y), 0, head_image.get_height() - 1))
	_expect(head_image.get_pixelv(anchor_i).a >= actor.ahoge_head_anchor_alpha_threshold, "頭側アンカーが頭画像表面にありません: " + label)
	var result: Dictionary = {"label": label, "anchor_px": [anchor_px.x, anchor_px.y]}
	for phase in phases:
		state.action_state = int(phase[0])
		var start_position: Vector2 = head.position
		var start_rotation: float = float(actor._head_rotation)
		var movement: float = 0.0
		var rotation_change: float = 0.0
		var elapsed: float = 0.0
		var duration: float = float(phase[1])
		var screenshot_saved: bool = false
		while elapsed < duration - 0.000001:
			var delta: float = minf(1.0 / fps, duration - elapsed)
			var contact: float = duration * config.attack_contact_ratio
			if state.action_state == StateScript.ActionState.STRIKE and elapsed < contact - 0.000001:
				delta = minf(delta, contact - elapsed)
			director.advance(delta)
			elapsed += delta
			movement = maxf(movement, head.position.distance_to(start_position))
			rotation_change = maxf(rotation_change, absf(float(actor._head_rotation) - start_rotation))
			_expect(head.transform.is_finite(), "頭部transformが非有限: " + label)
			var expected_anchor: Vector2 = actor.ahoge_head_anchor_canvas_position()
			var root_canvas: Vector2 = actor.ahoge_root_canvas_position()
			var error: float = expected_anchor.distance_to(root_canvas)
			max_anchor_error = maxf(max_anchor_error, error)
			_expect(error < 0.01, "頭部アンカーからアホ毛Rig根元が外れました: " + label)
			var mesh_vertices: PackedVector2Array = actor.mesh_canvas_vertices()
			_expect(not mesh_vertices.is_empty(), "アホ毛メッシュがありません: " + label)
			if not mesh_vertices.is_empty():
				var mesh_error: float = mesh_vertices[0].distance_to(expected_anchor)
				max_anchor_error = maxf(max_anchor_error, mesh_error)
				_expect(mesh_error < 0.01, "頭部アンカーから実メッシュ根元が外れました: " + label)
			var bounds: Rect2 = actor.head_canvas_bounds()
			var arena: Rect2 = actor.arena_canvas_rect
			_expect(bounds.position.x >= arena.position.x - 0.5 and bounds.end.x <= arena.end.x + 0.5, "頭部が左右で見切れました: " + label)
			_expect(actor._head_clip.clip_contents, "頭部下端cropが解除されました: " + label)
			if state.action_state == StateScript.ActionState.PARRY:
				_expect(actor.last_presentation_weight < 0.001, "頭部パリィに攻撃伸長が入りました: " + label)
			if not screenshot_saved and resolution.x == 1280 and fps == 60 and side == 0 and charge > 0.0 and elapsed >= duration * 0.42 and DisplayServer.get_name() != "headless":
				await process_frame
				await RenderingServer.frame_post_draw
				var image: Image = viewport.get_texture().get_image()
				_expect(image != null and not image.is_empty(), "頭部の実描画が空です")
				if image != null:
					_expect(image.save_png(OUT + "head_%d.png" % int(phase[0])) == OK, "頭部の画像を保存できません")
				screenshot_saved = true
		if state.action_state in [StateScript.ActionState.STRIKE, StateScript.ActionState.PARRY] or (state.action_state == StateScript.ActionState.CHARGING and charge > 0.0):
			_expect(movement >= 7.0, "アホ毛だけ動き頭部の移動が不足しています: " + label + "/" + str(state.action_state))
			_expect(rotation_change >= 2.0, "頭部の傾きが不足しています: " + label + "/" + str(state.action_state))
			result[str(state.action_state)] = {"movement_px": movement, "rotation_degrees": rotation_change}
	records.append(result)
	viewport.free()


func _expect(ok: bool, message: String) -> void:
	checks += 1
	if not ok and not failures.has(message):
		failures.append(message)
		push_error(message)
