extends SceneTree

const FighterScript := preload("res://src/ui/fighter_visual.gd")
const OriginalRigScript := preload("res://src/ui/ahoge_prototype_rig.gd")
const CatalogScript := preload("res://src/domain/character_catalog.gd")
const ConfigScript := preload("res://src/config/combat_config.gd")
const StateScript := preload("res://src/domain/combatant_state.gd")
var _failures: Array[String] = []
var _checks: int = 0
var _viewport: SubViewport
var _fighter
var _rig
var _baseline
var _state
var _case_name: String
var _frame_number: int = 0
var _last_state: int = -1
var _contact_samples: Array = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	DirAccess.make_dir_recursive_absolute("res://artifacts/ahoge-mesh/cycles")
	_viewport = SubViewport.new()
	_viewport.size = Vector2i(1280, 720)
	_viewport.transparent_bg = true
	_viewport.disable_3d = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(_viewport)
	for fps in [30, 60, 120]:
		for direction in [1.0, -1.0]:
			for charge in [0.0, 1.0]:
				_case_name = "%dfps_%s_%s" % [fps, "left" if direction > 0.0 else "right", "normal" if charge == 0.0 else "charged"]
				_setup(direction)
				await _phase(StateScript.ActionState.IDLE, 0.15, charge, fps)
				if charge > 0.0:
					await _phase(StateScript.ActionState.CHARGING, _state.config.max_charge_seconds, charge, fps)
				await _phase(StateScript.ActionState.WINDUP, _state.config.attack_windup_seconds(charge), charge, fps)
				await _phase(StateScript.ActionState.STRIKE, _state.config.attack_strike_seconds(charge), charge, fps)
				await _phase(StateScript.ActionState.COOLDOWN, _state.config.attack_cooldown_seconds(charge), charge, fps)
				_expect(_rig.debug_straighten() < 0.001, "実Cooldown時間内で元のC字へ戻る")
				# 途中のパリィキャンセルは現在の変形量から連続して戻す。
				await _phase(StateScript.ActionState.STRIKE, 0.07, charge, fps, false)
				var before: float = _rig.debug_straighten()
				_rig.set_motion(Vector2.ZERO, Vector2.ZERO, StateScript.ActionState.PARRY, true, charge, 0.18)
				_expect(absf(_rig.debug_straighten() - before) < 0.00001, "パリィ割込みで形状を瞬間リセットしない")
				await _phase(StateScript.ActionState.PARRY, 0.18, charge, fps)
				_expect(_rig.debug_straighten() < 0.001, "パリィ割込み後の形状復帰")
				_rig.set_motion(Vector2.ZERO, Vector2.ZERO, StateScript.ActionState.ROUND_LOCKED, false)
				_expect(not _rig.visible and _rig.debug_straighten() == 0.0, "ラウンドロックと非表示で変形を解除")
				_rig.configure(load(CatalogScript.get_by_id("LONG_TEST").ahoge_asset_path), direction)
				_expect(_rig.mesh_ready and _rig.debug_straighten() == 0.0, "再構成後も元画像ではなくメッシュが成立")
				var deformer = _rig.find_child("AhogeMeshInstance", true, false)
				_expect(not deformer.set_straighten(NAN), "非有限パラメータを拒否")
				var fallback = _rig.find_child("AhogeSprite", true, false)
				_expect(not _rig.mesh_ready and fallback.visible and not deformer.visible, "異常時は元Spriteだけを表示")
				_fighter.free()
				_baseline.free()
	var report := FileAccess.open("res://artifacts/ahoge-mesh/cycle_metrics.json", FileAccess.WRITE)
	report.store_string(JSON.stringify(_contact_samples, "\t"))
	for failure in _failures:
		push_error(failure)
	print("Ahoge mesh real-duration cycles: %s (%d checks)" % ["PASS" if _failures.is_empty() else "FAIL", _checks])
	quit(0 if _failures.is_empty() else 1)

func _setup(direction: float) -> void:
	_state = StateScript.new(ConfigScript.new())
	_fighter = FighterScript.new()
	_fighter.position = Vector2(40, 240) if direction > 0.0 else Vector2(820, 240)
	_fighter.size = Vector2(420, 460)
	_fighter.configure(CatalogScript.get_by_id("LONG_TEST"), _state, direction)
	_viewport.add_child(_fighter)
	_fighter.set_process(false)
	_rig = _fighter.find_child("AhogePrototypeRig", true, false)
	_rig.set_process(false)
	_baseline = OriginalRigScript.new()
	_viewport.add_child(_baseline)
	_baseline.configure(load(CatalogScript.get_by_id("LONG_TEST").ahoge_asset_path), direction)
	_baseline.set_process(false)
	_baseline.visible = false
	_last_state = -1
	_frame_number = 0
	_expect(_rig.mesh_ready, "BattleのFighterVisualに実メッシュを接続")

func _phase(action: int, duration: float, charge: float, fps: int, check_contact: bool = true) -> void:
	_state.action_state = action
	_state.attack_charge_ratio = charge
	_state.ahoge_available = true
	var elapsed := 0.0
	var captured := false
	while elapsed < duration - 0.000001:
		var delta := minf(1.0 / float(fps), duration - elapsed)
		elapsed += delta
		_fighter.call("_process", delta)
		_baseline.set_motion(_rig.get("_head_velocity"), _rig.get("_head_acceleration"), action, true, charge, _rig.get("_phase_duration"), 0.60)
		if action != _last_state:
			match action:
				StateScript.ActionState.STRIKE: _baseline.kick(1.0)
				StateScript.ActionState.PARRY: _baseline.kick(0.55)
				StateScript.ActionState.DODGE: _baseline.kick(0.45)
				StateScript.ActionState.STAGGER: _baseline.kick(0.8)
			_last_state = action
		_rig.call("_process", delta)
		_baseline.call("_process", delta)
		_expect(_rig.mesh_ready, "cycle途中にfallbackへ落ちない")
		_expect(absf(_rig.debug_angle() - _baseline.debug_angle()) < 0.000001, "元prototypeの全体角度を維持")
		_expect(absf(_rig.debug_reach() - _baseline.debug_reach()) < 0.000001, "元prototypeのReachを維持")
		var head := _fighter.find_child("HeadSprite", true, false) as Sprite2D
		var point: Vector2 = (_rig.mesh_head_attachment_reference() - Vector2(0.5, 0.5)) * head.texture.get_size()
		_expect(head.to_global(point).distance_to(_rig.to_global(Vector2.ZERO)) < 0.001, "移動・回転・左右反転時も頭頂部と根元が一致")
		if action == StateScript.ActionState.STRIKE and check_contact and not captured and elapsed + 0.000001 >= duration * _state.config.attack_contact_ratio:
			_expect(_rig.debug_straighten() > 0.999, "実STRIKE接触時点までに毛先を直線化")
			var tip: Vector2 = _rig.to_global(_rig.actual_tip_local_position())
			var image: Image = await _capture("%s_contact" % _case_name)
			_expect(_alpha_near(image, tip, 5) > 0.04, "実cycle接触時の先端に描画画素がある")
			_contact_samples.append({"case": _case_name, "strike_duration": duration, "contact_elapsed": elapsed, "straighten": _rig.debug_straighten(), "angle": _rig.debug_angle(), "reach": _rig.debug_reach(), "tip": [tip.x, tip.y]})
			captured = true
		if fps == 60 and _fighter.facing > 0.0 and charge == 0.0 and check_contact:
			await _capture("sequence_%04d" % _frame_number)
		_frame_number += 1

func _capture(file_name: String) -> Image:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var image := _viewport.get_texture().get_image()
	image.convert(Image.FORMAT_RGBA8)
	image.save_png("res://artifacts/ahoge-mesh/cycles/%s.png" % file_name)
	return image

func _alpha_near(image: Image, position_value: Vector2, radius: int) -> float:
	var maximum := 0.0
	for y in range(maxi(int(position_value.y) - radius, 0), mini(int(position_value.y) + radius + 1, image.get_height())):
		for x in range(maxi(int(position_value.x) - radius, 0), mini(int(position_value.x) + radius + 1, image.get_width())):
			maximum = maxf(maximum, image.get_pixel(x, y).a)
	return maximum

func _expect(condition: bool, label: String) -> void:
	_checks += 1
	if not condition and _failures.size() < 30:
		_failures.append(_case_name + ": " + label)
