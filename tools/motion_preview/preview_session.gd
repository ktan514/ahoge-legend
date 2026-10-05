extends RefCounted

# 計算式は製品コードを再利用する。ここでは再生する入力列と時計だけを管理する。
const HudScene := preload("res://scenes/screens/battle/BattleHUD.tscn")
const StateScript := preload("res://src/domain/combatant_state.gd")
const ConfigScript := preload("res://src/config/combat_config.gd")
const CatalogScript := preload("res://src/domain/character_catalog.gd")
const SCENARIOS := ["通常攻撃", "チャージ攻撃", "溜め保持", "パリィ", "攻撃→パリィ中断"]

var hud
var director
var attacker
var defender
var state
var other_state
var viewport: SubViewport
var phases: Array[Dictionary] = []
var time: float = 0.0
var total: float = 0.0
var contact_time: float = -1.0
var fps: int = 60
var side: int = 0
var scenario: int = 1
var charge: float = 1.0
var opponent: String = "SHORT_TEST"
var phase_index: int = 0
var tip_history := PackedVector2Array()


func reset(view: SubViewport, mode: int, amount: float, actor_side: int, enemy: String, sample_fps: int) -> void:
	viewport = view
	scenario = clampi(mode, 0, SCENARIOS.size() - 1)
	charge = clampf(amount, 0.0, 1.0)
	side = clampi(actor_side, 0, 1)
	opponent = enemy if enemy in ["LONG_TEST", "SHORT_TEST"] else "SHORT_TEST"
	fps = sample_fps if sample_fps in [30, 60, 120] else 60
	if is_instance_valid(hud):
		hud.free()
	hud = HudScene.instantiate()
	viewport.add_child(hud)
	hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	director = hud.contact_director
	director.set_process(false)
	var config = ConfigScript.new()
	state = StateScript.new(config)
	other_state = StateScript.new(config)
	state.attack_charge_ratio = charge if scenario in [1, 4] else 0.0
	var player = CatalogScript.get_by_id("LONG_TEST")
	var enemy_character = CatalogScript.get_by_id(opponent)
	if side == 0:
		hud.set_combatants(player, state, enemy_character, other_state)
	else:
		hud.set_combatants(enemy_character, other_state, player, state)
	attacker = director.fighters[side]
	defender = director.fighters[1 - side]
	_build_phases(config)
	time = 0.0
	phase_index = 0
	tip_history.clear()
	state.action_state = int(phases[0]["state"])
	# Containerの配置が確定するまで進行しない。
	await viewport.get_tree().process_frame
	await viewport.get_tree().process_frame


func _add_phase(action: int, seconds: float) -> void:
	if seconds <= 0.0:
		return
	phases.append({"state": action, "start": total, "end": total + seconds})
	total += seconds


func _build_phases(config) -> void:
	phases.clear()
	total = 0.0
	contact_time = -1.0
	_add_phase(StateScript.ActionState.IDLE, 0.20)
	match scenario:
		2:
			_add_phase(StateScript.ActionState.CHARGING, config.max_charge_seconds + 1.0)
			_add_phase(StateScript.ActionState.IDLE, 0.60)
		3:
			_add_phase(StateScript.ActionState.PARRY, config.parry_active_seconds)
			_add_phase(StateScript.ActionState.IDLE, 0.50)
		_:
			var ratio: float = charge if scenario in [1, 4] else 0.0
			# 現行FighterVisualの表示用charge閾値に合わせた入力列。
			var held: float = 0.02 if ratio <= 0.0 else 0.18 + ratio * maxf(config.max_charge_seconds - 0.18, 0.0)
			_add_phase(StateScript.ActionState.CHARGING, held)
			_add_phase(StateScript.ActionState.WINDUP, config.attack_windup_seconds(ratio))
			var strike: float = config.attack_strike_seconds(ratio)
			if scenario == 4:
				_add_phase(StateScript.ActionState.STRIKE, strike * 0.45)
				_add_phase(StateScript.ActionState.PARRY, config.parry_active_seconds)
			else:
				contact_time = total + strike * config.attack_contact_ratio
				_add_phase(StateScript.ActionState.STRIKE, strike)
			_add_phase(StateScript.ActionState.COOLDOWN, config.attack_cooldown_seconds(ratio))
			_add_phase(StateScript.ActionState.IDLE, 0.30)


func advance_to(target: float) -> void:
	var goal: float = clampf(target, time, total)
	var step: float = 1.0 / float(fps)
	while time < goal - 0.0000001:
		while phase_index < phases.size() - 1 and time >= float(phases[phase_index]["end"]) - 0.0000001:
			phase_index += 1
		state.action_state = int(phases[phase_index]["state"])
		var delta: float = minf(step, goal - time)
		delta = minf(delta, float(phases[phase_index]["end"]) - time)
		if contact_time > time + 0.0000001:
			delta = minf(delta, contact_time - time)
		if delta <= 0.0000001:
			break
		director.advance(delta)
		time += delta
		var points: PackedVector2Array = attacker.mesh_canvas_vertices()
		if not points.is_empty():
			tip_history.append(points[-1])
			if tip_history.size() > 1200:
				tip_history.remove_at(0)


func state_name() -> String:
	return str(StateScript.ActionState.keys()[int(state.action_state)]) if state != null else "IDLE"


func pose() -> PackedVector2Array:
	return attacker.mesh_canvas_vertices() if is_instance_valid(attacker) else PackedVector2Array()


func length_on_screen() -> float:
	var points: PackedVector2Array = pose()
	if points.size() < 7:
		return 0.0
	var last: Vector2 = points[0]
	var result: float = 0.0
	for i in range(1, points.size() - 1, 5):
		var center: Vector2 = (points[i] + points[i + 4]) * 0.5
		result += last.distance_to(center)
		last = center
	return result + last.distance_to(points[-1])
