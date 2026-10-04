extends Node

const StateScript := preload("res://src/domain/combatant_state.gd")

var fighters: Array = []
var arena: Control
var _last_targets: Array[Vector2] = [Vector2.ZERO, Vector2.ZERO]
var _pending_hits: Array[int] = []
var _last_hit_tokens: Dictionary = {}
var _attack_start_ticks: Dictionary = {}
var _online_session


func configure(left, right, battle_area: Control) -> void:
	fighters = [left, right]
	arena = battle_area
	for fighter in fighters:
		fighter.set_process(false)
	process_priority = 20
	set_process(true)


func _ready() -> void:
	_online_session = get_node_or_null("/root/OnlineSession")
	if _online_session != null:
		_online_session.hit_confirmed.connect(_on_hit_confirmed)
		_online_session.combat_state_changed.connect(_on_combat_state_changed)


func _process(delta: float) -> void:
	advance(delta)


func advance(delta: float) -> void:
	if fighters.size() != 2 or arena == null or delta <= 0.0:
		return
	var bounds: Rect2 = arena.get_global_transform() * Rect2(Vector2.ZERO, arena.size)
	for fighter in fighters:
		fighter.arena_canvas_rect = bounds
		fighter.call("_process", delta)
	for index in _pending_hits:
		fighters[index].confirm_contact()
	_pending_hits.clear()
	for index in range(2):
		var other = fighters[1 - index]
		if other.combat_state == null:
			continue
		# 回避へ入った相手をアホ毛で追尾しない。
		if int(other.combat_state.action_state) != StateScript.ActionState.DODGE or _last_targets[index] == Vector2.ZERO:
			_last_targets[index] = other.contact_canvas_position()
		fighters[index].present_toward(_last_targets[index])


func notify_confirmed_contact(index: int, server_tick: int, sequence: int) -> void:
	if index < 0 or index >= fighters.size():
		return
	var previous: Vector2i = _last_hit_tokens.get(index, Vector2i(-1, -1))
	if server_tick < previous.x or (server_tick == previous.x and sequence <= previous.y):
		return
	_last_hit_tokens[index] = Vector2i(server_tick, sequence)
	if not _pending_hits.has(index):
		_pending_hits.append(index)


func _on_combat_state_changed(user_id: String, state: String, server_tick: int, _charge: float) -> void:
	if state in ["CHARGING", "WINDUP", "STRIKE"]:
		_attack_start_ticks[user_id] = server_tick


func _on_hit_confirmed(attacker_id: String, defender_id: String, server_tick: int, sequence: int) -> void:
	if _online_session == null or _online_session.session == null:
		return
	var snapshot: Dictionary = _online_session.latest_match_snapshot
	var characters: Dictionary = snapshot.get("character_id_by_user", {})
	var local_id: String = str(_online_session.session.user_id)
	if not characters.has(attacker_id) or not characters.has(defender_id) or not characters.has(local_id):
		return
	if server_tick < int(_attack_start_ticks.get(attacker_id, -1)):
		return
	notify_confirmed_contact(0 if attacker_id == local_id else 1, server_tick, sequence)
