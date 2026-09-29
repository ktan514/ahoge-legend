extends Control

const CombatConfigScript := preload("res://src/config/combat_config.gd")
const CombatantStateScript := preload("res://src/domain/combatant_state.gd")
const CharacterCatalogScript := preload("res://src/domain/character_catalog.gd")
const CombatInputProtocolScript := preload("res://src/online/combat_input_protocol.gd")

signal ranked_match_completed(summary: Dictionary)

@onready var hud = $BattleHUD

var _online_session = null

var _initial_snapshot: Dictionary = {}
var _rating_before: Dictionary = {}
var _config
var _local_state
var _opponent_state
var _local_user_id: String = ""
var _opponent_user_id: String = ""
var _local_character_id: String = ""
var _opponent_character_id: String = ""
var _input_ready: bool = false
var _attack_held: bool = false
var _match_finished: bool = false
var _round_countdown_active: bool = false
var _round_finished: bool = false
var _completion_emitted: bool = false
var _go_clear_generation: int = 0
var _snapshot := {
	"round_number": 1,
	"player_one_hits": 0,
	"player_two_hits": 0,
	"remaining_seconds": 85,
	"overtime": false,
	"player_one_rounds": 0,
	"player_two_rounds": 0,
	"match_finished": false,
}


func configure(initial_snapshot: Dictionary, rating_before: Dictionary) -> void:
	_initial_snapshot = initial_snapshot.duplicate(true)
	_rating_before = rating_before.duplicate(true)


func _ready() -> void:
	_online_session = get_node("/root/OnlineSession")
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_config = CombatConfigScript.new()
	_local_state = CombatantStateScript.new(_config)
	_opponent_state = CombatantStateScript.new(_config)
	if _online_session.session != null:
		_local_user_id = str(_online_session.session.user_id)

	_connect_online_signals()
	hud.set_connection_status("RANKED: CONNECTED")
	hud.set_help_text("左クリック Attack/Charge・右クリック Parry/Dodge")
	hud.set_exit_button_text("ONLINE MATCH中は退出不可")
	hud.exit_requested.connect(_on_exit_requested)

	var snapshot := _initial_snapshot
	if snapshot.is_empty():
		snapshot = _online_session.latest_match_snapshot
	if snapshot.is_empty():
		hud.flash_message("SERVER SNAPSHOTを待機中")
		return
	_apply_match_snapshot(snapshot)


func _connect_online_signals() -> void:
	_online_session.combat_state_changed.connect(_on_combat_state_changed)
	_online_session.ahoge_state_changed.connect(_on_ahoge_state_changed)
	_online_session.defense_resolved.connect(_on_defense_resolved)
	_online_session.hit_confirmed.connect(_on_hit_confirmed)
	_online_session.attack_clash.connect(_on_attack_clash)
	_online_session.round_hit_count_changed.connect(_on_round_hit_count_changed)
	_online_session.round_timer_changed.connect(_on_round_timer_changed)
	_online_session.round_overtime_started.connect(_on_round_overtime_started)
	_online_session.round_result.connect(_on_round_result)
	_online_session.bo3_score_changed.connect(_on_bo3_score_changed)
	_online_session.round_started.connect(_on_round_started)
	_online_session.match_result.connect(_on_match_result)
	_online_session.round_countdown_changed.connect(_on_round_countdown_changed)
	_online_session.match_snapshot_received.connect(_on_match_snapshot_received)
	_online_session.player_connection_changed.connect(_on_player_connection_changed)
	_online_session.reconnect_started.connect(_on_reconnect_started)
	_online_session.reconnect_succeeded.connect(_on_reconnect_succeeded)
	_online_session.reconnect_failed.connect(_on_reconnect_failed)


func _process(_delta: float) -> void:
	if _online_session.is_reconnecting():
		hud.show_network_overlay("RECONNECTING...")


func _input(event: InputEvent) -> void:
	if not _input_ready or _match_finished or _round_countdown_active:
		return
	if not event is InputEventMouseButton:
		return

	var hovered_control := get_viewport().gui_get_hovered_control()
	var over_button := hovered_control is BaseButton
	if event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed and not over_button and not _attack_held:
			_attack_held = true
			call_deferred("_send_action", CombatInputProtocolScript.ACTION_ATTACK_PRESS)
		elif not event.pressed and _attack_held:
			_attack_held = false
			call_deferred("_send_action", CombatInputProtocolScript.ACTION_ATTACK_RELEASE)
	elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed and not over_button:
		call_deferred("_send_action", CombatInputProtocolScript.ACTION_DEFEND)


func _send_action(action: String) -> void:
	var result: Dictionary = await _online_session.send_combat_input(action)
	if not bool(result.get("ok", false)):
		hud.flash_message(str(result.get("message", "入力送信に失敗しました。")))


func _configure_combatants(character_map: Dictionary) -> bool:
	if _local_user_id.is_empty():
		return false
	_opponent_user_id = ""
	for user_id in character_map.keys():
		if str(user_id) != _local_user_id:
			_opponent_user_id = str(user_id)
			break
	if _opponent_user_id.is_empty():
		return false

	_local_character_id = str(character_map.get(_local_user_id, ""))
	_opponent_character_id = str(character_map.get(_opponent_user_id, ""))
	var local_character = CharacterCatalogScript.get_by_id(_local_character_id)
	var opponent_character = CharacterCatalogScript.get_by_id(_opponent_character_id)
	if local_character == null or opponent_character == null:
		return false

	hud.set_combatants(
		local_character,
		_local_state,
		opponent_character,
		_opponent_state
	)
	return true


func _on_match_snapshot_received(snapshot: Dictionary) -> void:
	_apply_match_snapshot(snapshot)


func _apply_match_snapshot(snapshot: Dictionary) -> void:
	if str(snapshot.get("match_mode", "")) != "ranked":
		return
	var character_map: Dictionary = snapshot.get("character_id_by_user", {})
	if not _configure_combatants(character_map):
		hud.flash_message("authoritative player情報を取得できません。")
		return

	_snapshot["round_number"] = int(snapshot.get("round_number", 1))
	_snapshot["remaining_seconds"] = int(snapshot.get("remaining_seconds", 85))
	_snapshot["overtime"] = bool(snapshot.get("round_overtime", false))
	_snapshot["match_finished"] = bool(snapshot.get("match_finished", false))
	_snapshot["player_one_hits"] = int(
		snapshot.get("round_hit_count_by_user", {}).get(_local_user_id, 0)
	)
	_snapshot["player_two_hits"] = int(
		snapshot.get("round_hit_count_by_user", {}).get(_opponent_user_id, 0)
	)
	_apply_round_wins(snapshot.get("round_wins_by_user", {}))
	_round_finished = bool(snapshot.get("round_finished", false))
	_round_countdown_active = bool(snapshot.get("round_countdown_active", false))
	_match_finished = bool(snapshot.get("match_finished", false))

	var combat_states: Dictionary = snapshot.get("combat_state_by_user", {})
	_apply_snapshot_combat_state(_local_user_id, combat_states.get(_local_user_id, {}))
	_apply_snapshot_combat_state(_opponent_user_id, combat_states.get(_opponent_user_id, {}))

	_input_ready = not _match_finished and not _round_countdown_active
	if _match_finished:
		hud.set_connection_status("RANKED: MATCH FINISHED")
		_emit_result_from_snapshot(snapshot)
	else:
		hud.set_connection_status("RANKED: READY")
	_render()


func _apply_snapshot_combat_state(user_id: String, value) -> void:
	if not value is Dictionary:
		return
	var target = _state_for_user(user_id)
	if target == null:
		return
	var mapped := _action_state_from_name(str(value.get("state", "")))
	if mapped >= 0:
		target.action_state = mapped
	target.attack_charge_ratio = float(value.get("charge_ratio", 0.0))
	target.set_ahoge_available(bool(value.get("ahoge_available", true)))


func _on_combat_state_changed(user_id: String, state_name: String, _server_tick: int, charge_ratio: float) -> void:
	var target = _state_for_user(user_id)
	if target == null:
		return
	var mapped := _action_state_from_name(state_name)
	if mapped < 0:
		return
	target.action_state = mapped
	target.attack_charge_ratio = charge_ratio
	if state_name == "STAGGER":
		hud.flash_message("%s STAGGER" % _player_label(user_id))
	_render()


func _on_ahoge_state_changed(user_id: String, available: bool, _regrow_until_tick: int, _server_tick: int) -> void:
	var target = _state_for_user(user_id)
	if target == null:
		return
	var previous := bool(target.ahoge_available)
	target.ahoge_available = available
	if previous != available:
		hud.flash_message("%s %s" % [
			_player_label(user_id),
			"REGROW" if available else "DETACH",
		])
	_render()


func _on_defense_resolved(
	_attacker_id: String,
	defender_id: String,
	_server_tick: int,
	_input_sequence: int,
	result: String
) -> void:
	hud.flash_message("%s %s" % [_player_label(defender_id), result.replace("_", " ")])


func _on_hit_confirmed(attacker_id: String, _defender_id: String, _server_tick: int, _input_sequence: int) -> void:
	hud.flash_message("%s HIT" % _player_label(attacker_id))


func _on_attack_clash(
	_attacker_a_id: String,
	_attacker_b_id: String,
	_attacker_a_input_sequence: int,
	_attacker_b_input_sequence: int,
	_server_tick: int
) -> void:
	hud.flash_message("CLASH!")


func _on_round_hit_count_changed(user_id: String, hit_count: int, _server_tick: int, _input_sequence: int) -> void:
	if user_id == _local_user_id:
		_snapshot["player_one_hits"] = hit_count
	elif user_id == _opponent_user_id:
		_snapshot["player_two_hits"] = hit_count
	_render()


func _on_round_timer_changed(remaining_seconds: int, _server_tick: int) -> void:
	_snapshot["remaining_seconds"] = remaining_seconds
	_render()


func _on_round_overtime_started(_server_tick: int) -> void:
	_snapshot["overtime"] = true
	hud.flash_message("OVERTIME")
	_render()


func _on_round_result(
	round_number: int,
	winner_user_id: String,
	_loser_user_id: String,
	_finish_cause: String,
	_winner_hits: int,
	_loser_hits: int,
	_server_tick: int
) -> void:
	_round_finished = true
	hud.flash_message("ROUND %d WINNER: %s" % [round_number, _player_label(winner_user_id)])


func _on_bo3_score_changed(
	completed_round_number: int,
	round_winner_user_id: String,
	round_wins_by_user: Dictionary,
	match_finished: bool,
	_server_tick: int
) -> void:
	_apply_round_wins(round_wins_by_user)
	_snapshot["match_finished"] = match_finished
	if not match_finished:
		hud.show_round_result(
			_player_label(round_winner_user_id),
			completed_round_number,
			int(_snapshot["player_one_rounds"]),
			int(_snapshot["player_two_rounds"])
		)
		hud.flash_message("")
	_render()


func _on_round_started(round_number: int, round_wins_by_user: Dictionary, _server_tick: int) -> void:
	_snapshot["round_number"] = round_number
	_snapshot["remaining_seconds"] = 85
	_snapshot["player_one_hits"] = 0
	_snapshot["player_two_hits"] = 0
	_snapshot["overtime"] = false
	_round_countdown_active = false
	_round_finished = false
	_attack_held = false
	_apply_round_wins(round_wins_by_user)
	hud.flash_message("")
	_input_ready = true
	_render()


func _on_round_countdown_changed(round_number: int, countdown_value: int, _server_tick: int) -> void:
	_snapshot["round_number"] = round_number
	_snapshot["remaining_seconds"] = 85
	_snapshot["player_one_hits"] = 0
	_snapshot["player_two_hits"] = 0
	_snapshot["overtime"] = false
	_round_countdown_active = countdown_value > 0
	_input_ready = countdown_value == 0
	if countdown_value > 0:
		_attack_held = false
		_local_state.action_state = CombatantStateScript.ActionState.ROUND_LOCKED
		_opponent_state.action_state = CombatantStateScript.ActionState.ROUND_LOCKED
	hud.show_round_countdown(round_number, countdown_value)
	_render()
	_go_clear_generation += 1
	var generation := _go_clear_generation
	if countdown_value == 0:
		call_deferred("_clear_go_after_delay", generation)


func _clear_go_after_delay(generation: int) -> void:
	await get_tree().create_timer(0.45).timeout
	if generation == _go_clear_generation:
		hud.clear_round_countdown()


func _on_match_result(
	winner_user_id: String,
	loser_user_id: String,
	round_wins_by_user: Dictionary,
	final_round_number: int,
	finish_cause: String,
	_server_tick: int
) -> void:
	if _completion_emitted:
		return
	_apply_round_wins(round_wins_by_user)
	_snapshot["round_number"] = final_round_number
	_snapshot["match_finished"] = true
	_match_finished = true
	_input_ready = false
	_render()
	_emit_ranked_result({
		"winner_user_id": winner_user_id,
		"loser_user_id": loser_user_id,
		"round_wins_by_user": round_wins_by_user.duplicate(true),
		"final_round_number": final_round_number,
		"finish_cause": finish_cause,
	})


func _emit_result_from_snapshot(snapshot: Dictionary) -> void:
	if _completion_emitted:
		return
	var winner_user_id := str(snapshot.get("match_winner_user_id", ""))
	if winner_user_id.is_empty():
		return
	var loser_user_id := _opponent_user_id if winner_user_id == _local_user_id else _local_user_id
	_emit_ranked_result({
		"winner_user_id": winner_user_id,
		"loser_user_id": loser_user_id,
		"round_wins_by_user": snapshot.get("round_wins_by_user", {}).duplicate(true),
		"final_round_number": int(snapshot.get("round_number", 1)),
		"finish_cause": str(snapshot.get("match_finish_cause", "")),
	})


func _emit_ranked_result(authoritative_result: Dictionary) -> void:
	if _completion_emitted:
		return
	_completion_emitted = true
	var winner_user_id := str(authoritative_result.get("winner_user_id", ""))
	var summary := {
		"mode": "ranked",
		"winner_user_id": winner_user_id,
		"loser_user_id": str(authoritative_result.get("loser_user_id", "")),
		"local_user_id": _local_user_id,
		"local_won": winner_user_id == _local_user_id,
		"local_character_id": _local_character_id,
		"opponent_character_id": _opponent_character_id,
		"round_wins_by_user": authoritative_result.get("round_wins_by_user", {}).duplicate(true),
		"final_round_number": int(authoritative_result.get("final_round_number", 1)),
		"finish_cause": str(authoritative_result.get("finish_cause", "")),
		"rating_before": _rating_before.duplicate(true),
	}
	call_deferred("_emit_ranked_match_completed", summary)


func _emit_ranked_match_completed(summary: Dictionary) -> void:
	ranked_match_completed.emit(summary)


func _on_reconnect_started(_grace_seconds: int) -> void:
	_input_ready = false
	hud.set_connection_status("RANKED: RECONNECTING")
	hud.show_network_overlay("RECONNECTING...")


func _on_reconnect_succeeded(_match_id: String) -> void:
	hud.clear_network_overlay()
	if _match_finished:
		hud.set_connection_status("RANKED: MATCH FINISHED")
		_input_ready = false
	else:
		hud.set_connection_status("RANKED: READY")
		_input_ready = not _round_countdown_active


func _on_reconnect_failed(message: String) -> void:
	_input_ready = false
	hud.set_connection_status("RANKED: RECONNECT FAILED")
	hud.show_network_overlay(message)


func _on_player_connection_changed(
	user_id: String,
	connected: bool,
	_reconnect_deadline_tick: int,
	_server_tick: int
) -> void:
	if user_id != _opponent_user_id:
		return
	if connected:
		hud.clear_network_overlay()
		hud.set_connection_status("RANKED: READY")
	elif _round_finished or _round_countdown_active:
		hud.show_network_overlay("WAITING FOR OPPONENT...")
	else:
		hud.set_connection_status("RANKED: OPPONENT RECONNECTING")


func _on_exit_requested() -> void:
	hud.flash_message("Online match終了契約は未解決のため、対戦中は退出できません。")


func _apply_round_wins(round_wins_by_user: Dictionary) -> void:
	_snapshot["player_one_rounds"] = int(round_wins_by_user.get(_local_user_id, 0))
	_snapshot["player_two_rounds"] = int(round_wins_by_user.get(_opponent_user_id, 0))


func _state_for_user(user_id: String):
	if user_id == _local_user_id:
		return _local_state
	if user_id == _opponent_user_id:
		return _opponent_state
	return null


func _player_label(user_id: String) -> String:
	if user_id == _local_user_id:
		return "YOU"
	if user_id == _opponent_user_id:
		return "OPPONENT"
	return "?"


func _action_state_from_name(state_name: String) -> int:
	match state_name:
		"IDLE":
			return CombatantStateScript.ActionState.IDLE
		"CHARGING":
			return CombatantStateScript.ActionState.CHARGING
		"WINDUP":
			return CombatantStateScript.ActionState.WINDUP
		"STRIKE":
			return CombatantStateScript.ActionState.STRIKE
		"COOLDOWN":
			return CombatantStateScript.ActionState.COOLDOWN
		"PARRY":
			return CombatantStateScript.ActionState.PARRY
		"DODGE":
			return CombatantStateScript.ActionState.DODGE
		"STAGGER":
			return CombatantStateScript.ActionState.STAGGER
		"ROUND_LOCKED":
			return CombatantStateScript.ActionState.ROUND_LOCKED
	return -1


func _render() -> void:
	if _local_state == null or _opponent_state == null:
		return
	hud.render_authoritative(_snapshot, _local_state, _opponent_state)
