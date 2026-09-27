extends Node

const OnlineConfigScript := preload("res://src/config/online_config.gd")
const DeviceIdentityStoreScript := preload("res://src/online/device_identity_store.gd")
const RankedMatchmakerQueryScript := preload("res://src/online/ranked_matchmaker_query.gd")
const CombatInputProtocolScript := preload("res://src/online/combat_input_protocol.gd")

signal authentication_succeeded(user_id: String, username: String)
signal authentication_failed(step: String, message: String)
signal realtime_connected(user_id: String)
signal realtime_disconnected
signal realtime_connection_failed(message: String)
signal ranked_matchmaking_started(min_rating: int, max_rating: int)
signal ranked_matchmaking_cancelled
signal ranked_match_found(match_id: String)
signal ranked_match_joined(match_id: String)
signal ranked_matchmaking_failed(step: String, message: String)
signal combat_input_accepted(user_id: String, input_sequence: int, action: String, server_tick: int)
signal combat_state_changed(user_id: String, state: String, server_tick: int, charge_ratio: float)
signal ahoge_state_changed(user_id: String, ahoge_available: bool, regrow_until_tick: int, server_tick: int)
signal contact_reached(attacker_id: String, defender_id: String, server_tick: int, input_sequence: int, charge_ratio: float)
signal defense_resolved(attacker_id: String, defender_id: String, server_tick: int, input_sequence: int, result: String)
signal hit_confirmed(attacker_id: String, defender_id: String, server_tick: int, input_sequence: int)
signal attack_clash(attacker_a_id: String, attacker_b_id: String, attacker_a_input_sequence: int, attacker_b_input_sequence: int, server_tick: int)
signal round_hit_count_changed(user_id: String, hit_count: int, server_tick: int, input_sequence: int)
signal round_timer_changed(remaining_seconds: int, server_tick: int)
signal combat_input_failed(message: String)

var client = null
var session = null
var account = null
var realtime_socket = null
var matchmaker_ticket: String = ""
var joined_match = null
var current_match_id: String = ""
var _next_input_sequence: int = 0
var _identity_store = null


func _ready() -> void:
	_identity_store = DeviceIdentityStoreScript.new(OnlineConfigScript.DEVICE_ID_PATH)


func create_local_client():
	client = Nakama.create_client(
		OnlineConfigScript.SERVER_KEY,
		OnlineConfigScript.HOST,
		OnlineConfigScript.PORT,
		OnlineConfigScript.SCHEME,
		OnlineConfigScript.CLIENT_TIMEOUT_SECONDS,
		OnlineConfigScript.CLIENT_LOG_LEVEL
	)
	return client


func get_or_create_device_id() -> String:
	if _identity_store == null:
		_identity_store = DeviceIdentityStoreScript.new(OnlineConfigScript.DEVICE_ID_PATH)
	return _identity_store.load_or_create()


func authenticate_local_device() -> Dictionary:
	if client == null:
		create_local_client()

	var device_id := get_or_create_device_id()
	if device_id.is_empty():
		return _fail("device_id", "Device IDを生成または保存できませんでした。")

	var auth_result = await client.authenticate_device_async(device_id, null, true)
	if auth_result == null or auth_result.is_exception():
		return _fail_from_result("authenticate_device", auth_result)

	session = auth_result

	var account_result = await client.get_account_async(session)
	if account_result == null or account_result.is_exception():
		session = null
		return _fail_from_result("get_account", account_result)

	account = account_result

	var user_id := str(session.user_id)
	var username := str(session.username)
	print("Nakama local authentication succeeded: user_id=%s username=%s" % [user_id, username])
	authentication_succeeded.emit(user_id, username)

	return {
		"ok": true,
		"user_id": user_id,
		"username": username,
		"created": bool(session.created),
		"account_user_id": str(account.user.id),
	}


func is_authenticated() -> bool:
	return session != null and session.valid and not session.expired


func connect_realtime_socket() -> Dictionary:
	if not is_authenticated():
		return _realtime_fail("Nakama認証前はRealtime Socketへ接続できません。")

	if realtime_socket != null:
		if realtime_socket.is_connected_to_host():
			return {
				"ok": true,
				"already_connected": true,
			}
		realtime_socket.close()
		realtime_socket = null

	var candidate = Nakama.create_socket_from(client)
	if candidate == null:
		return _realtime_fail("Realtime Socketを生成できませんでした。")

	candidate.connected.connect(_on_realtime_connected.bind(candidate))
	candidate.closed.connect(_on_realtime_closed.bind(candidate))
	candidate.connection_error.connect(_on_realtime_connection_error.bind(candidate))
	candidate.received_error.connect(_on_realtime_received_error.bind(candidate))
	candidate.received_matchmaker_matched.connect(_on_matchmaker_matched.bind(candidate))
	candidate.received_match_state.connect(_on_match_state_received.bind(candidate))
	realtime_socket = candidate

	var connect_result = await candidate.connect_async(
		session,
		OnlineConfigScript.SOCKET_APPEAR_ONLINE,
		OnlineConfigScript.SOCKET_CONNECT_TIMEOUT_SECONDS
	)

	if connect_result == null or connect_result.is_exception():
		var message := _result_error_message(connect_result, "Realtime Socket接続に失敗しました。")
		if realtime_socket == candidate:
			realtime_socket = null
		candidate.close()
		return _realtime_fail(message)

	if not candidate.is_connected_to_host():
		if realtime_socket == candidate:
			realtime_socket = null
		candidate.close()
		return _realtime_fail("Realtime Socketが接続状態になりませんでした。")

	return {
		"ok": true,
		"already_connected": false,
	}


func build_ranked_matchmaker_query(rating: int) -> String:
	return RankedMatchmakerQueryScript.build(rating)


# CharacterSelectで確定したIDをMatchmaker propertyとしてserverへ渡す。
# character_id自体は対戦相手の検索条件には使用しない。
func start_ranked_matchmaking(rating: int, character_id: String) -> Dictionary:
	if not is_realtime_connected():
		return _matchmaking_fail("start", "Realtime Socket接続前はMatchmakerを開始できません。")

	if not matchmaker_ticket.is_empty():
		return _matchmaking_fail("start", "既にMatchmaker ticketがあります。")

	if not OnlineConfigScript.is_supported_ranked_character_id(character_id):
		return _matchmaking_fail("start", "未対応character_idです: %s" % character_id)

	var min_rating := rating - OnlineConfigScript.RANKED_INITIAL_RATING_RANGE
	var max_rating := rating + OnlineConfigScript.RANKED_INITIAL_RATING_RANGE
	var query := build_ranked_matchmaker_query(rating)
	var string_properties := {
		"mode": OnlineConfigScript.RANKED_MATCHMAKER_MODE,
		"character_id": character_id,
	}
	var numeric_properties := {
		"rating": float(rating),
	}

	var ticket_result = await realtime_socket.add_matchmaker_async(
		query,
		OnlineConfigScript.RANKED_MATCHMAKER_MIN_COUNT,
		OnlineConfigScript.RANKED_MATCHMAKER_MAX_COUNT,
		string_properties,
		numeric_properties
	)

	if ticket_result == null or ticket_result.is_exception():
		return _matchmaking_fail(
			"add_matchmaker",
			_result_error_message(ticket_result, "Matchmaker ticketを作成できませんでした。")
		)

	matchmaker_ticket = str(ticket_result.ticket)
	ranked_matchmaking_started.emit(min_rating, max_rating)

	return {
		"ok": true,
		"min_rating": min_rating,
		"max_rating": max_rating,
		"character_id": character_id,
	}


func cancel_ranked_matchmaking() -> Dictionary:
	if matchmaker_ticket.is_empty():
		return _matchmaking_fail("cancel", "取消対象のMatchmaker ticketがありません。")

	if not is_realtime_connected():
		matchmaker_ticket = ""
		return _matchmaking_fail("cancel", "Realtime Socketが切断されています。")

	var ticket_to_remove := matchmaker_ticket
	var result = await realtime_socket.remove_matchmaker_async(ticket_to_remove)
	if result == null or result.is_exception():
		return _matchmaking_fail(
			"remove_matchmaker",
			_result_error_message(result, "Matchmaker ticketを取消できませんでした。")
		)

	if matchmaker_ticket == ticket_to_remove:
		matchmaker_ticket = ""
	ranked_matchmaking_cancelled.emit()
	return {"ok": true}


func is_matchmaking() -> bool:
	return not matchmaker_ticket.is_empty()


func is_in_authoritative_match() -> bool:
	return joined_match != null and bool(joined_match.authoritative) and not current_match_id.is_empty()


func _on_matchmaker_matched(matched, candidate) -> void:
	if realtime_socket != candidate:
		return

	if matched == null or matched.is_exception():
		_matchmaking_fail("matched", "Matchmaker matched通知を処理できませんでした。")
		return

	var matched_ticket := str(matched.ticket)
	if matchmaker_ticket.is_empty() or matched_ticket != matchmaker_ticket:
		return

	matchmaker_ticket = ""
	var match_id := str(matched.match_id)
	if match_id.is_empty():
		_matchmaking_fail("matched", "authoritative match IDがありません。")
		return

	ranked_match_found.emit(match_id)

	var join_result = await candidate.join_match_async(match_id)
	if join_result == null or join_result.is_exception():
		_matchmaking_fail(
			"join_match",
			_result_error_message(join_result, "authoritative matchへjoinできませんでした。")
		)
		return

	if not bool(join_result.authoritative):
		_matchmaking_fail("join_match", "join先がauthoritative matchではありません。")
		return

	joined_match = join_result
	current_match_id = str(join_result.match_id)
	_next_input_sequence = 0
	ranked_match_joined.emit(current_match_id)


func send_combat_input(action: String) -> Dictionary:
	if not is_in_authoritative_match():
		return _combat_input_fail("authoritative matchへjoinしていません。")

	if not CombatInputProtocolScript.is_allowed_action(action):
		return _combat_input_fail("不正な戦闘actionです: %s" % action)

	_next_input_sequence += 1
	var sequence := _next_input_sequence
	var payload := CombatInputProtocolScript.build_input_payload(sequence, action)
	var result = await realtime_socket.send_match_state_async(
		current_match_id,
		CombatInputProtocolScript.OPCODE_COMBAT_INPUT,
		payload
	)

	if result != null and result.has_method("is_exception") and result.is_exception():
		return _combat_input_fail(
			_result_error_message(result, "戦闘入力を送信できませんでした。")
		)

	return {
		"ok": true,
		"input_sequence": sequence,
	}


func _on_match_state_received(match_state, candidate) -> void:
	if realtime_socket != candidate:
		return
	if current_match_id.is_empty() or str(match_state.match_id) != current_match_id:
		return

	var op_code := int(match_state.op_code)
	if op_code == CombatInputProtocolScript.OPCODE_INPUT_ACCEPTED:
		var accepted := CombatInputProtocolScript.parse_accepted_payload(str(match_state.data))
		if accepted.is_empty():
			return

		combat_input_accepted.emit(
			str(accepted["user_id"]),
			int(accepted["input_sequence"]),
			str(accepted["action"]),
			int(accepted["server_tick"])
		)
		return

	if op_code == CombatInputProtocolScript.OPCODE_COMBAT_STATE_CHANGED:
		var state_event := CombatInputProtocolScript.parse_combat_state_changed_payload(
			str(match_state.data)
		)
		if state_event.is_empty():
			return

		combat_state_changed.emit(
			str(state_event["user_id"]),
			str(state_event["state"]),
			int(state_event["server_tick"]),
			float(state_event["charge_ratio"])
		)
		ahoge_state_changed.emit(
			str(state_event["user_id"]),
			bool(state_event.get("ahoge_available", true)),
			int(state_event.get("regrow_until_tick", -1)),
			int(state_event["server_tick"])
		)
		return

	if op_code == CombatInputProtocolScript.OPCODE_CONTACT_REACHED:
		var contact_event := CombatInputProtocolScript.parse_contact_reached_payload(
			str(match_state.data)
		)
		if contact_event.is_empty():
			return

		contact_reached.emit(
			str(contact_event["attacker_id"]),
			str(contact_event["defender_id"]),
			int(contact_event["server_tick"]),
			int(contact_event["input_sequence"]),
			float(contact_event["charge_ratio"])
		)
		return

	if op_code == CombatInputProtocolScript.OPCODE_DEFENSE_RESOLVED:
		var defense_event := CombatInputProtocolScript.parse_defense_resolved_payload(
			str(match_state.data)
		)
		if defense_event.is_empty():
			return

		defense_resolved.emit(
			str(defense_event["attacker_id"]),
			str(defense_event["defender_id"]),
			int(defense_event["server_tick"]),
			int(defense_event["input_sequence"]),
			str(defense_event["result"])
		)
		return

	if op_code == CombatInputProtocolScript.OPCODE_HIT_CONFIRMED:
		var hit_event := CombatInputProtocolScript.parse_hit_confirmed_payload(str(match_state.data))
		if hit_event.is_empty():
			return
		hit_confirmed.emit(str(hit_event["attacker_id"]), str(hit_event["defender_id"]), int(hit_event["server_tick"]), int(hit_event["input_sequence"]))
		return

	if op_code == CombatInputProtocolScript.OPCODE_ATTACK_CLASH:
		var clash_event := CombatInputProtocolScript.parse_attack_clash_payload(str(match_state.data))
		if clash_event.is_empty():
			return
		attack_clash.emit(str(clash_event["attacker_a_id"]), str(clash_event["attacker_b_id"]), int(clash_event["attacker_a_input_sequence"]), int(clash_event["attacker_b_input_sequence"]), int(clash_event["server_tick"]))
		return

	if op_code == CombatInputProtocolScript.OPCODE_ROUND_HIT_COUNT_CHANGED:
		var hit_count_event := CombatInputProtocolScript.parse_round_hit_count_changed_payload(str(match_state.data))
		if hit_count_event.is_empty():
			return
		round_hit_count_changed.emit(
			str(hit_count_event["user_id"]),
			int(hit_count_event["hit_count"]),
			int(hit_count_event["server_tick"]),
			int(hit_count_event["input_sequence"])
		)
		return

	if op_code == CombatInputProtocolScript.OPCODE_ROUND_TIMER_CHANGED:
		var timer_event := CombatInputProtocolScript.parse_round_timer_changed_payload(str(match_state.data))
		if timer_event.is_empty():
			return
		round_timer_changed.emit(
			int(timer_event["remaining_seconds"]),
			int(timer_event["server_tick"])
		)


func is_realtime_connected() -> bool:
	return realtime_socket != null and realtime_socket.is_connected_to_host()


func disconnect_realtime_socket() -> bool:
	if realtime_socket == null:
		return false

	var candidate = realtime_socket
	candidate.close()
	return true


func clear_session() -> void:
	disconnect_realtime_socket()
	matchmaker_ticket = ""
	joined_match = null
	current_match_id = ""
	_next_input_sequence = 0
	session = null
	account = null


func _on_realtime_connected(candidate) -> void:
	if realtime_socket != candidate:
		return
	print("Nakama realtime socket connected: user_id=%s" % str(session.user_id))
	realtime_connected.emit(str(session.user_id))


func _on_realtime_closed(candidate) -> void:
	if realtime_socket == candidate:
		realtime_socket = null
		matchmaker_ticket = ""
		joined_match = null
		current_match_id = ""
		_next_input_sequence = 0
	realtime_disconnected.emit()


func _on_realtime_connection_error(error, candidate) -> void:
	if realtime_socket == candidate:
		realtime_socket = null
	var message := "Realtime Socket connection error: %s" % str(error)
	printerr(message)
	realtime_connection_failed.emit(message)


func _on_realtime_received_error(error, candidate) -> void:
	if realtime_socket != candidate:
		return
	var message := "Realtime Socket server error: %s" % str(error)
	printerr(message)
	realtime_connection_failed.emit(message)


func _fail_from_result(step: String, result) -> Dictionary:
	return _fail(step, _result_error_message(result, "Unknown Nakama error"))


func _result_error_message(result, fallback: String) -> String:
	if result != null and result.has_method("get_exception"):
		var exception = result.get_exception()
		if exception != null and not str(exception.message).is_empty():
			return str(exception.message)
	return fallback


func _realtime_fail(message: String) -> Dictionary:
	printerr("Nakama realtime connection failed: %s" % message)
	realtime_connection_failed.emit(message)
	return {
		"ok": false,
		"message": message,
	}


func _combat_input_fail(message: String) -> Dictionary:
	printerr("Nakama combat input failed: %s" % message)
	combat_input_failed.emit(message)
	return {
		"ok": false,
		"message": message,
	}


func _matchmaking_fail(step: String, message: String) -> Dictionary:
	printerr("Nakama ranked matchmaking failed: step=%s message=%s" % [step, message])
	ranked_matchmaking_failed.emit(step, message)
	return {
		"ok": false,
		"step": step,
		"message": message,
	}


func _fail(step: String, message: String) -> Dictionary:
	printerr("Nakama local authentication failed: step=%s message=%s" % [step, message])
	authentication_failed.emit(step, message)
	return {
		"ok": false,
		"step": step,
		"message": message,
	}
