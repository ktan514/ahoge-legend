extends Control

const OnlineConfigScript := preload("res://src/config/online_config.gd")
const CombatInputProtocolScript := preload("res://src/online/combat_input_protocol.gd")
const CombatConfigScript := preload("res://src/config/combat_config.gd")
const CombatantStateScript := preload("res://src/domain/combatant_state.gd")
const CharacterCatalogScript := preload("res://src/domain/character_catalog.gd")

signal exit_requested

@onready var hud = $BattleHUD

var _online_session = null
var _nakama = null

var _config
var _p1_state
var _p2_state

var _p1_user_id: String = ""
var _p2_user_id: String = ""
var _p1_match_id: String = ""
var _p2_match_id: String = ""

var _p2_client = null
var _p2_socket = null
var _p2_ticket: String = ""
var _p2_sequence: int = 0
var _p2_failure: String = ""

var _input_ready: bool = false
var _p1_attack_held: bool = false
var _p2_attack_held: bool = false
var _match_finished: bool = false
var _round_countdown_active: bool = false
var _go_clear_generation: int = 0
var _ci_smoke: bool = false
var _ci_completed: bool = false
var _has_timer: bool = false
var _has_p1_count: bool = false
var _has_p2_count: bool = false
var _has_countdown: bool = false
var _has_round_started: bool = false
var _round_finished: bool = false
var _p2_connected: bool = true

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


func _ready() -> void:
	_online_session = get_node("/root/OnlineSession")
	_nakama = get_node("/root/Nakama")
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ci_smoke = OS.get_cmdline_user_args().has("--m1-ci-smoke")
	_config = CombatConfigScript.new()
	_p1_state = CombatantStateScript.new(_config)
	_p2_state = CombatantStateScript.new(_config)

	var player_one = CharacterCatalogScript.get_by_id(OnlineConfigScript.RANKED_CHARACTER_LONG_TEST)
	var player_two = CharacterCatalogScript.get_by_id(OnlineConfigScript.RANKED_CHARACTER_SHORT_TEST)
	hud.set_combatants(player_one, _p1_state, player_two, _p2_state)
	hud.set_connection_status("M1 AUTHORITATIVE: CONNECTING...")
	hud.flash_message("Nakamaへ接続中")
	hud.render_authoritative(_snapshot, _p1_state, _p2_state)
	hud.exit_requested.connect(_on_exit_requested)

	_connect_online_signals()
	call_deferred("_start_authoritative_match")


func _connect_online_signals() -> void:
	_online_session.ranked_match_joined.connect(_on_p1_ranked_match_joined)
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


func _start_authoritative_match() -> void:
	_online_session.clear_session()

	var auth_result: Dictionary = await _online_session.authenticate_local_device()
	if not bool(auth_result.get("ok", false)):
		_fail("P1 Device認証に失敗しました。")
		return
	_p1_user_id = str(auth_result.get("user_id", ""))

	var realtime_result: Dictionary = await _online_session.connect_realtime_socket()
	if not bool(realtime_result.get("ok", false)):
		_fail("P1 Realtime Socket接続に失敗しました。")
		return

	_p2_client = _nakama.create_client(
		OnlineConfigScript.SERVER_KEY,
		OnlineConfigScript.HOST,
		OnlineConfigScript.PORT,
		OnlineConfigScript.SCHEME,
		OnlineConfigScript.CLIENT_TIMEOUT_SECONDS,
		OnlineConfigScript.CLIENT_LOG_LEVEL
	)
	var second_device_id := Crypto.new().generate_random_bytes(32).hex_encode()
	var second_session = await _p2_client.authenticate_device_async(second_device_id, null, true)
	if second_session == null or second_session.is_exception():
		_fail("P2 Device認証に失敗しました。")
		return
	_p2_user_id = str(second_session.user_id)

	_p2_socket = _nakama.create_socket_from(_p2_client)
	_p2_socket.received_matchmaker_matched.connect(_on_p2_matchmaker_matched)
	var second_connect = await _p2_socket.connect_async(
		second_session,
		OnlineConfigScript.SOCKET_APPEAR_ONLINE,
		OnlineConfigScript.SOCKET_CONNECT_TIMEOUT_SECONDS
	)
	if second_connect == null or second_connect.is_exception():
		_fail("P2 Realtime Socket接続に失敗しました。")
		return

	var p1_start: Dictionary = await _online_session.start_ranked_matchmaking(
		1500,
		OnlineConfigScript.RANKED_CHARACTER_LONG_TEST
	)
	if not bool(p1_start.get("ok", false)):
		_fail("P1 Matchmakerを開始できませんでした。")
		return

	var query: String = _online_session.build_ranked_matchmaker_query(1500)
	var second_ticket_result = await _p2_socket.add_matchmaker_async(
		query,
		OnlineConfigScript.RANKED_MATCHMAKER_MIN_COUNT,
		OnlineConfigScript.RANKED_MATCHMAKER_MAX_COUNT,
		{
			"mode": OnlineConfigScript.RANKED_MATCHMAKER_MODE,
			"character_id": OnlineConfigScript.RANKED_CHARACTER_SHORT_TEST,
		},
		{"rating": 1500.0}
	)
	if second_ticket_result == null or second_ticket_result.is_exception():
		_fail("P2 Matchmakerを開始できませんでした。")
		return
	_p2_ticket = str(second_ticket_result.ticket)

	var deadline := Time.get_ticks_msec() + 40000
	while Time.get_ticks_msec() < deadline:
		if not _p2_failure.is_empty():
			_fail(_p2_failure)
			return
		if not _p1_match_id.is_empty() and not _p2_match_id.is_empty():
			break
		await get_tree().create_timer(0.1).timeout

	if _p1_match_id.is_empty() or _p2_match_id.is_empty():
		_fail("M1の2クライアントがauthoritative matchへjoinできませんでした。")
		return
	if _p1_match_id != _p2_match_id:
		_fail("M1のP1/P2 match IDが一致しません。")
		return

	_input_ready = true
	hud.set_connection_status("M1 AUTHORITATIVE: READY")
	hud.flash_message("P1/P2 ONLINE READY")
	_render()
	_maybe_finish_ci_smoke()


func _process(_delta: float) -> void:
	if _online_session.is_reconnecting():
		var remaining: int = int(_online_session.reconnect_remaining_seconds())
		if remaining > 0:
			hud.show_network_overlay("RECONNECTING...\n%d" % remaining)
		else:
			hud.show_network_overlay("RESTORING ORIGINAL MATCH...")


func _input(event: InputEvent) -> void:
	if not _input_ready or _match_finished or _round_countdown_active:
		return

	if event is InputEventMouseButton:
		var hovered_control := get_viewport().gui_get_hovered_control()
		var over_button := hovered_control is BaseButton
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed and not over_button and not _p1_attack_held:
				_p1_attack_held = true
				call_deferred("_send_p1_action", CombatInputProtocolScript.ACTION_ATTACK_PRESS)
			elif not event.pressed and _p1_attack_held:
				_p1_attack_held = false
				call_deferred("_send_p1_action", CombatInputProtocolScript.ACTION_ATTACK_RELEASE)
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed and not over_button:
			call_deferred("_send_p1_action", CombatInputProtocolScript.ACTION_DEFEND)

	if event is InputEventKey and not event.echo:
		if event.keycode == KEY_Q:
			if event.pressed and not _p2_attack_held:
				_p2_attack_held = true
				call_deferred("_send_p2_action", CombatInputProtocolScript.ACTION_ATTACK_PRESS)
			elif not event.pressed and _p2_attack_held:
				_p2_attack_held = false
				call_deferred("_send_p2_action", CombatInputProtocolScript.ACTION_ATTACK_RELEASE)
		elif event.keycode == KEY_E and event.pressed:
			call_deferred("_send_p2_action", CombatInputProtocolScript.ACTION_DEFEND)
		elif event.keycode == KEY_F8 and event.pressed:
			_simulate_p1_unexpected_disconnect()


func _simulate_p1_unexpected_disconnect() -> void:
	if _online_session.realtime_socket == null or not _online_session.is_realtime_connected():
		return
	hud.flash_message("M1 HV: SIMULATE P1 DROP")
	# M1 Human Verification専用。intentional disconnect APIを通さずclosed signalを発生させる。
	_online_session.realtime_socket.close()


func _send_p1_action(action: String) -> void:
	var result: Dictionary = await _online_session.send_combat_input(action)
	if not bool(result.get("ok", false)):
		_fail("P1 %sを送信できませんでした。" % action)


func _send_p2_action(action: String) -> void:
	if _p2_socket == null or _p2_match_id.is_empty():
		_fail("P2はauthoritative matchへjoinしていません。")
		return
	_p2_sequence += 1
	var result = await _p2_socket.send_match_state_async(
		_p2_match_id,
		CombatInputProtocolScript.OPCODE_COMBAT_INPUT,
		CombatInputProtocolScript.build_input_payload(_p2_sequence, action)
	)
	if result != null and result.has_method("is_exception") and result.is_exception():
		_fail("P2 %sを送信できませんでした。" % action)


func _on_p1_ranked_match_joined(match_id: String) -> void:
	_p1_match_id = match_id


func _on_p2_matchmaker_matched(matched) -> void:
	if matched == null or matched.is_exception():
		_p2_failure = "P2 matchmaker matched通知が不正です。"
		return
	if str(matched.ticket) != _p2_ticket:
		return
	var match_id := str(matched.match_id)
	if match_id.is_empty():
		_p2_failure = "P2 matched通知にauthoritative match IDがありません。"
		return
	var join_result = await _p2_socket.join_match_async(match_id)
	if join_result == null or join_result.is_exception():
		_p2_failure = "P2 authoritative match joinに失敗しました。"
		return
	_p2_match_id = str(join_result.match_id)


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
		hud.flash_message(
			"%s %s" % [_player_label(user_id), "REGROW" if available else "DETACH"]
		)
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
	if user_id == _p1_user_id:
		_snapshot["player_one_hits"] = hit_count
		_has_p1_count = true
	elif user_id == _p2_user_id:
		_snapshot["player_two_hits"] = hit_count
		_has_p2_count = true
	_render()
	_maybe_finish_ci_smoke()


func _on_round_timer_changed(remaining_seconds: int, _server_tick: int) -> void:
	_snapshot["remaining_seconds"] = remaining_seconds
	_has_timer = true
	_render()
	_maybe_finish_ci_smoke()


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
	if not _p2_connected:
		hud.show_network_overlay("WAITING FOR OPPONENT...")


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
	_has_round_started = true
	_p1_attack_held = false
	_p2_attack_held = false
	_apply_round_wins(round_wins_by_user)
	hud.flash_message("")
	_render()
	_maybe_finish_ci_smoke()


func _on_round_countdown_changed(round_number: int, countdown_value: int, _server_tick: int) -> void:
	_snapshot["round_number"] = round_number
	_snapshot["remaining_seconds"] = 85
	_snapshot["player_one_hits"] = 0
	_snapshot["player_two_hits"] = 0
	_snapshot["overtime"] = false
	_round_countdown_active = countdown_value > 0
	if countdown_value > 0:
		_has_countdown = true
		if countdown_value == 3:
			hud.flash_message("")
		_p1_attack_held = false
		_p2_attack_held = false
		_p1_state.action_state = CombatantStateScript.ActionState.ROUND_LOCKED
		_p2_state.action_state = CombatantStateScript.ActionState.ROUND_LOCKED
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


func _on_reconnect_started(_grace_seconds: int) -> void:
	_input_ready = false
	hud.set_connection_status("M1 AUTHORITATIVE: RECONNECTING")
	hud.show_network_overlay(
		"RECONNECTING...\n%d" % _online_session.reconnect_remaining_seconds()
	)


func _on_reconnect_succeeded(_match_id: String) -> void:
	hud.clear_network_overlay()
	if _match_finished:
		hud.set_connection_status("M1 AUTHORITATIVE: MATCH FINISHED")
		_input_ready = false
		return
	hud.set_connection_status("M1 AUTHORITATIVE: READY")
	_input_ready = not _round_countdown_active


func _on_reconnect_failed(message: String) -> void:
	_input_ready = false
	hud.set_connection_status("M1 AUTHORITATIVE: RECONNECT FAILED")
	hud.show_network_overlay(message)


func _on_player_connection_changed(
	user_id: String,
	connected: bool,
	_reconnect_deadline_tick: int,
	_server_tick: int
) -> void:
	if user_id != _p2_user_id:
		return

	_p2_connected = connected
	if connected:
		hud.clear_network_overlay()
		hud.set_connection_status("M1 AUTHORITATIVE: READY")
		return

	if _round_finished or _round_countdown_active or not _has_round_started:
		hud.show_network_overlay("WAITING FOR OPPONENT...")
	else:
		hud.set_connection_status("M1 AUTHORITATIVE: OPPONENT RECONNECTING")


func _on_match_snapshot_received(snapshot: Dictionary) -> void:
	_snapshot["round_number"] = int(snapshot.get("round_number", 1))
	_snapshot["remaining_seconds"] = int(snapshot.get("remaining_seconds", 85))
	_snapshot["overtime"] = bool(snapshot.get("round_overtime", false))
	_snapshot["match_finished"] = bool(snapshot.get("match_finished", false))
	_snapshot["player_one_hits"] = int(
		snapshot.get("round_hit_count_by_user", {}).get(_p1_user_id, 0)
	)
	_snapshot["player_two_hits"] = int(
		snapshot.get("round_hit_count_by_user", {}).get(_p2_user_id, 0)
	)
	_apply_round_wins(snapshot.get("round_wins_by_user", {}))
	_round_finished = bool(snapshot.get("round_finished", false))
	_round_countdown_active = bool(snapshot.get("round_countdown_active", false))
	_match_finished = bool(snapshot.get("match_finished", false))

	var combat_states: Dictionary = snapshot.get("combat_state_by_user", {})
	_apply_snapshot_combat_state(_p1_user_id, combat_states.get(_p1_user_id, {}))
	_apply_snapshot_combat_state(_p2_user_id, combat_states.get(_p2_user_id, {}))

	if _match_finished:
		_input_ready = false
		hud.set_connection_status("M1 AUTHORITATIVE: MATCH FINISHED")
		var winner_user_id := str(snapshot.get("match_winner_user_id", ""))
		var finish_cause := str(snapshot.get("match_finish_cause", ""))
		var result_prefix := "MATCH WINNER"
		if finish_cause == "DISCONNECT_TIMEOUT":
			result_prefix = "DISCONNECT WINNER"
		hud.flash_message(
			"%s: %s  %d-%d" % [
				result_prefix,
				_player_label(winner_user_id),
				int(_snapshot["player_one_rounds"]),
				int(_snapshot["player_two_rounds"]),
			]
		)

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


func _on_match_result(
	winner_user_id: String,
	_loser_user_id: String,
	round_wins_by_user: Dictionary,
	final_round_number: int,
	finish_cause: String,
	_server_tick: int
) -> void:
	_apply_round_wins(round_wins_by_user)
	_snapshot["round_number"] = final_round_number
	_snapshot["match_finished"] = true
	_match_finished = true
	_input_ready = false
	hud.set_connection_status("M1 AUTHORITATIVE: MATCH FINISHED")
	var result_prefix := "MATCH WINNER"
	if finish_cause == "DISCONNECT_TIMEOUT":
		result_prefix = "DISCONNECT WINNER"
	hud.flash_message(
		"%s: %s  %d-%d" % [
			result_prefix,
			_player_label(winner_user_id),
			int(_snapshot["player_one_rounds"]),
			int(_snapshot["player_two_rounds"]),
		]
	)
	_render()


func _apply_round_wins(round_wins_by_user: Dictionary) -> void:
	if not _p1_user_id.is_empty():
		_snapshot["player_one_rounds"] = int(round_wins_by_user.get(_p1_user_id, 0))
	if not _p2_user_id.is_empty():
		_snapshot["player_two_rounds"] = int(round_wins_by_user.get(_p2_user_id, 0))


func _state_for_user(user_id: String):
	if user_id == _p1_user_id:
		return _p1_state
	if user_id == _p2_user_id:
		return _p2_state
	return null


func _player_label(user_id: String) -> String:
	if user_id == _p1_user_id:
		return "P1"
	if user_id == _p2_user_id:
		return "P2"
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
	hud.render_authoritative(_snapshot, _p1_state, _p2_state)


func _maybe_finish_ci_smoke() -> void:
	if not _ci_smoke or _ci_completed or not _input_ready:
		return
	if not _has_timer or not _has_p1_count or not _has_p2_count:
		return
	if not _has_countdown or not _has_round_started:
		return
	_ci_completed = true
	print("AHOGE LEGEND M1 battle smoke: PASS")
	call_deferred("_finish_ci_smoke")


func _finish_ci_smoke() -> void:
	_cleanup()
	get_tree().quit(0)


func _fail(message: String) -> void:
	if not _p2_failure.is_empty() and _p2_failure != message:
		message = "%s / %s" % [message, _p2_failure]
	hud.set_connection_status("M1 AUTHORITATIVE: ERROR")
	hud.flash_message(message)
	push_error(message)
	if _ci_smoke and not _ci_completed:
		_ci_completed = true
		print("AHOGE LEGEND M1 battle smoke: FAIL")
		call_deferred("_finish_ci_failure")


func _finish_ci_failure() -> void:
	_cleanup()
	get_tree().quit(1)


func _on_exit_requested() -> void:
	_cleanup()
	exit_requested.emit()


func _cleanup() -> void:
	_input_ready = false
	if _p2_socket != null:
		_p2_socket.close()
		_p2_socket = null
	_online_session.clear_session()


func _exit_tree() -> void:
	if _p2_socket != null:
		_p2_socket.close()
