extends Node

const OnlineConfigScript := preload("res://src/config/online_config.gd")
const DeviceIdentityStoreScript := preload("res://src/online/device_identity_store.gd")
const MatchResumeRouterScript := preload("res://src/online/match_resume_router.gd")
const RankedMatchmakerQueryScript := preload("res://src/online/ranked_matchmaker_query.gd")
const CombatInputProtocolScript := preload("res://src/online/combat_input_protocol.gd")

signal authentication_succeeded(user_id: String, username: String)
signal authentication_failed(step: String, message: String)
signal realtime_connected(user_id: String)
signal realtime_disconnected
signal realtime_connection_failed(message: String)
signal ranked_matchmaking_started(min_rating: int, max_rating: int)
signal ranked_matchmaking_range_changed(min_rating: int, max_rating: int, elapsed_seconds: int)
signal ranked_matchmaking_prolonged_wait(elapsed_seconds: int, min_rating: int, max_rating: int)
signal ranked_matchmaking_cancelled
signal ranked_match_found(match_id: String)
signal ranked_match_joined(match_id: String)
signal ranked_matchmaking_failed(step: String, message: String)
signal friend_room_created(room_code: String, room: Dictionary)
signal friend_room_joined(room_code: String, room: Dictionary)
signal friend_room_updated(room: Dictionary)
signal friend_match_joined(match_id: String)
signal friend_room_failed(step: String, message: String)
signal combat_input_accepted(user_id: String, input_sequence: int, action: String, server_tick: int)
signal combat_state_changed(user_id: String, state: String, server_tick: int, charge_ratio: float)
signal ahoge_state_changed(user_id: String, ahoge_available: bool, regrow_until_tick: int, server_tick: int)
signal contact_reached(attacker_id: String, defender_id: String, server_tick: int, input_sequence: int, charge_ratio: float)
signal defense_resolved(attacker_id: String, defender_id: String, server_tick: int, input_sequence: int, result: String)
signal hit_confirmed(attacker_id: String, defender_id: String, server_tick: int, input_sequence: int)
signal attack_clash(attacker_a_id: String, attacker_b_id: String, attacker_a_input_sequence: int, attacker_b_input_sequence: int, server_tick: int)
signal round_hit_count_changed(user_id: String, hit_count: int, server_tick: int, input_sequence: int)
signal round_timer_changed(remaining_seconds: int, server_tick: int)
signal round_overtime_started(server_tick: int)
signal round_result(round_number: int, winner_user_id: String, loser_user_id: String, finish_cause: String, winner_hits: int, loser_hits: int, server_tick: int)
signal bo3_score_changed(completed_round_number: int, round_winner_user_id: String, round_wins_by_user: Dictionary, match_finished: bool, server_tick: int)
signal round_started(round_number: int, round_wins_by_user: Dictionary, server_tick: int)
signal match_result(winner_user_id: String, loser_user_id: String, round_wins_by_user: Dictionary, final_round_number: int, finish_cause: String, server_tick: int)
signal round_countdown_changed(round_number: int, countdown_value: int, server_tick: int)
signal match_snapshot_received(snapshot: Dictionary)
signal player_connection_changed(user_id: String, connected: bool, reconnect_deadline_tick: int, server_tick: int)
signal reconnect_started(grace_seconds: int)
signal reconnect_succeeded(match_id: String)
signal reconnect_failed(message: String)
signal saved_match_resume_resolved(destination: String, snapshot: Dictionary)
signal saved_match_resume_failed(message: String)
signal combat_input_failed(message: String)

var client = null
var _client_timeout_seconds: int = 0
var session = null
var account = null
var realtime_socket = null
var matchmaker_ticket: String = ""
var _matchmaking_generation: int = 0
var _ranked_matchmaking_rating: int = 0
var _ranked_matchmaking_character_id: String = ""
var _ranked_matchmaking_range: int = 0
var _ranked_matchmaking_started_msec: int = 0
var joined_match = null
var current_match_id: String = ""
var current_match_mode: String = ""
var _pending_join_match_id: String = ""
var latest_match_snapshot: Dictionary = {}
var _next_input_sequence: int = 0
var _identity_store = null
var _active_match_context: Dictionary = {}
var _saved_resume_waiting: bool = false
var _saved_resume_snapshot: Dictionary = {}
var _intentional_disconnect: bool = false
var _reconnect_in_progress: bool = false
var _reconnect_generation: int = 0
var _reconnect_deadline_msec: int = 0


func _ready() -> void:
	_identity_store = DeviceIdentityStoreScript.new(OnlineConfigScript.DEVICE_ID_PATH)


func create_local_client(
	timeout_seconds: int = OnlineConfigScript.CLIENT_TIMEOUT_SECONDS
):
	var safe_timeout := maxi(1, timeout_seconds)
	client = Nakama.create_client(
		OnlineConfigScript.SERVER_KEY,
		OnlineConfigScript.HOST,
		OnlineConfigScript.PORT,
		OnlineConfigScript.SCHEME,
		safe_timeout,
		OnlineConfigScript.CLIENT_LOG_LEVEL
	)
	_client_timeout_seconds = safe_timeout
	return client


func get_or_create_device_id() -> String:
	var override := OS.get_environment("AHOGE_DEVICE_ID_OVERRIDE").strip_edges()
	if not override.is_empty():
		return override
	if _identity_store == null:
		_identity_store = DeviceIdentityStoreScript.new(OnlineConfigScript.DEVICE_ID_PATH)
	return _identity_store.load_or_create()


func authenticate_local_device(
	timeout_seconds: int = OnlineConfigScript.CLIENT_TIMEOUT_SECONDS
) -> Dictionary:
	var safe_timeout := maxi(1, timeout_seconds)
	if client == null or _client_timeout_seconds != safe_timeout:
		create_local_client(safe_timeout)

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


func get_current_rating() -> Dictionary:
	if not is_authenticated():
		return {
			"ok": false,
			"message": "Rating取得には認証が必要です。",
		}

	var result = await client.rpc_async(session, "ahoge_current_rating")
	if result == null or result.is_exception():
		return {
			"ok": false,
			"message": _result_error_message(result, "現在Ratingを取得できませんでした。"),
		}

	var parsed = JSON.parse_string(str(result.payload))
	if not parsed is Dictionary:
		return {
			"ok": false,
			"message": "現在Ratingのserver応答を解析できませんでした。",
		}

	var response: Dictionary = parsed
	response["ok"] = true
	return response


func refresh_active_online_match() -> Dictionary:
	if not is_authenticated():
		return {
			"ok": false,
			"active": false,
			"message": "未解決対戦の確認には認証が必要です。",
		}

	var result = await client.rpc_async(
		session,
		OnlineConfigScript.ACTIVE_MATCH_RPC_GET
	)
	if result == null or result.is_exception():
		return {
			"ok": false,
			"active": false,
			"message": _result_error_message(
				result,
				"未解決対戦をserverで確認できませんでした。"
			),
		}

	var parsed = JSON.parse_string(str(result.payload))
	if not parsed is Dictionary:
		return {
			"ok": false,
			"active": false,
			"message": "未解決対戦のserver応答を解析できませんでした。",
		}

	var response: Dictionary = parsed
	response["ok"] = true
	if not bool(response.get("active", false)):
		_active_match_context = {}
		return response

	var match_id := str(response.get("match_id", ""))
	var match_mode := str(response.get("match_mode", ""))
	var state := str(response.get("state", ""))
	if match_id.is_empty() 			or match_mode not in [
				OnlineConfigScript.MATCH_MODE_RANKED,
				OnlineConfigScript.MATCH_MODE_FRIEND,
			] 			or state not in [
				OnlineConfigScript.ACTIVE_MATCH_STATE_ACTIVE,
				OnlineConfigScript.ACTIVE_MATCH_STATE_RESULT_PENDING,
			]:
		_active_match_context = {}
		return {
			"ok": false,
			"active": false,
			"message": "未解決対戦のserver状態が不正です。",
		}

	_active_match_context = response.duplicate(true)
	return response


func get_active_online_match_context() -> Dictionary:
	return _active_match_context.duplicate(true)


func has_unresolved_match_context() -> bool:
	return not current_match_id.is_empty() or not _active_match_context.is_empty()


func can_start_new_online_match() -> bool:
	return not has_unresolved_match_context()


func register_joined_online_match(match_id: String, match_mode: String) -> bool:
	if not is_authenticated() or match_id.is_empty():
		return false
	if match_mode not in [
		OnlineConfigScript.MATCH_MODE_RANKED,
		OnlineConfigScript.MATCH_MODE_FRIEND,
	]:
		return false
	if not current_match_id.is_empty() and current_match_id != match_id:
		return false

	current_match_id = match_id
	current_match_mode = match_mode
	return true


func acknowledge_active_match_destination() -> Dictionary:
	if not is_authenticated():
		return {
			"ok": false,
			"message": "対戦結果の確定には認証が必要です。",
		}

	var deadline := Time.get_ticks_msec() + 5000
	var active: Dictionary = {}
	while Time.get_ticks_msec() < deadline:
		active = await refresh_active_online_match()
		if not bool(active.get("ok", false)):
			return active
		if not bool(active.get("active", false)):
			_clear_runtime_match_state()
			return {
				"ok": true,
				"cleared": false,
			}
		if str(active.get("state", "")) == OnlineConfigScript.ACTIVE_MATCH_STATE_RESULT_PENDING:
			break
		await get_tree().create_timer(0.05).timeout

	if active.is_empty() 			or str(active.get("state", "")) != OnlineConfigScript.ACTIVE_MATCH_STATE_RESULT_PENDING:
		return {
			"ok": false,
			"message": "serverの対戦結果確定を確認できませんでした。",
		}

	var result = await client.rpc_async(
		session,
		OnlineConfigScript.ACTIVE_MATCH_RPC_ACK,
		JSON.stringify({"match_id": str(active.get("match_id", ""))})
	)
	if result == null or result.is_exception():
		return {
			"ok": false,
			"message": _result_error_message(
				result,
				"対戦結果の確認済み状態をserverへ保存できませんでした。"
			),
		}

	var parsed = JSON.parse_string(str(result.payload))
	if not parsed is Dictionary:
		return {
			"ok": false,
			"message": "対戦結果ackのserver応答を解析できませんでした。",
		}

	_active_match_context = {}
	_clear_runtime_match_state()
	var response: Dictionary = parsed
	response["ok"] = true
	return response


func restore_unresolved_match_with_retry() -> Dictionary:
	var max_attempts := OnlineConfigScript.MATCH_RECOVERY_RETRY_LIMIT + 1
	var last_message := "元の対戦をserverで確認できませんでした。"

	for attempt_index in range(max_attempts):
		if not is_authenticated():
			var auth_result: Dictionary = await authenticate_local_device(
				OnlineConfigScript.MATCH_RECOVERY_TIMEOUT_SECONDS
			)
			if not bool(auth_result.get("ok", false)):
				last_message = str(
					auth_result.get("message", "元の対戦へ復帰するための認証に失敗しました。")
				)
				if attempt_index < max_attempts - 1:
					clear_runtime_session_preserving_match()
					continue
				break

		var repaired: Dictionary = await repair_unresolved_match_context(
			OnlineConfigScript.MATCH_RECOVERY_TIMEOUT_SECONDS
		)
		if bool(repaired.get("ok", false)):
			var completed := repaired.duplicate(true)
			completed["attempts"] = attempt_index + 1
			return completed

		last_message = str(
			repaired.get("message", "元の対戦をserverで確認できませんでした。")
		)
		if str(repaired.get("reason", "")) != "server_unconfirmed":
			var non_retryable := repaired.duplicate(true)
			non_retryable["attempts"] = attempt_index + 1
			return non_retryable

		if attempt_index < max_attempts - 1:
			clear_runtime_session_preserving_match()

	clear_runtime_session_preserving_match()
	return {
		"ok": false,
		"repaired": false,
		"reason": "retry_exhausted",
		"attempts": max_attempts,
		"message": last_message,
	}


func repair_unresolved_match_context(
	connect_timeout_seconds: int = OnlineConfigScript.SOCKET_CONNECT_TIMEOUT_SECONDS
) -> Dictionary:
	if not is_authenticated():
		return {
			"ok": false,
			"repaired": false,
			"reason": "not_authenticated",
			"message": "対戦状態の再確認には認証が必要です。",
		}

	var active: Dictionary = await refresh_active_online_match()
	if not bool(active.get("ok", false)):
		return {
			"ok": false,
			"repaired": false,
			"reason": "server_unconfirmed",
			"message": str(active.get("message", "server確認に失敗しました。")),
		}
	if not bool(active.get("active", false)):
		_clear_runtime_match_state()
		return {
			"ok": true,
			"repaired": false,
			"reason": "no_lock",
			"destination": MatchResumeRouterScript.DESTINATION_NONE,
		}

	if str(active.get("state", "")) == OnlineConfigScript.ACTIVE_MATCH_STATE_RESULT_PENDING:
		var result_snapshot = active.get("result_snapshot", {})
		if not result_snapshot is Dictionary or (result_snapshot as Dictionary).is_empty():
			return {
				"ok": false,
				"repaired": false,
				"reason": "server_unconfirmed",
				"message": "終了済み対戦のserver確定Resultを取得できませんでした。",
			}
		var snapshot: Dictionary = (result_snapshot as Dictionary).duplicate(true)
		var destination := MatchResumeRouterScript.resolve(snapshot)
		if destination == MatchResumeRouterScript.DESTINATION_NONE:
			return {
				"ok": false,
				"repaired": false,
				"reason": "server_unconfirmed",
				"message": "server確定Resultから復帰先を決定できませんでした。",
			}
		current_match_id = str(active.get("match_id", ""))
		current_match_mode = str(active.get("match_mode", ""))
		saved_match_resume_resolved.emit(destination, snapshot)
		return {
			"ok": true,
			"repaired": true,
			"reason": "match_resolved",
			"destination": destination,
			"snapshot": snapshot,
		}

	var result: Dictionary = await resume_active_match_after_login(
		connect_timeout_seconds
	)
	if bool(result.get("ok", false)):
		if bool(result.get("resumed", false)):
			return {
				"ok": true,
				"repaired": true,
				"reason": "match_resolved",
				"destination": str(result.get("destination", "")),
				"snapshot": result.get("snapshot", {}),
			}
		if bool(result.get("match_not_found", false)):
			return {
				"ok": true,
				"repaired": true,
				"reason": "match_not_found",
				"destination": MatchResumeRouterScript.DESTINATION_NONE,
			}
		return {
			"ok": true,
			"repaired": false,
			"reason": "no_lock",
			"destination": MatchResumeRouterScript.DESTINATION_NONE,
		}

	return {
		"ok": false,
		"repaired": false,
		"reason": "server_unconfirmed",
		"message": str(result.get("message", "server確認に失敗したためlockを維持します。")),
	}


func resume_active_match_after_login(
	connect_timeout_seconds: int = OnlineConfigScript.SOCKET_CONNECT_TIMEOUT_SECONDS
) -> Dictionary:
	if not is_authenticated():
		return _saved_resume_fail("再ログイン復帰には認証が必要です。")

	var active := get_active_online_match_context()
	if active.is_empty():
		active = await refresh_active_online_match()
	if not bool(active.get("ok", false)):
		return _saved_resume_fail(
			str(active.get("message", "未解決対戦をserverで確認できませんでした。"))
		)
	if not bool(active.get("active", false)):
		return {
			"ok": true,
			"resumed": false,
			"destination": MatchResumeRouterScript.DESTINATION_NONE,
		}

	if str(active.get("state", "")) == OnlineConfigScript.ACTIVE_MATCH_STATE_RESULT_PENDING:
		var pending_snapshot = active.get("result_snapshot", {})
		if not pending_snapshot is Dictionary or (pending_snapshot as Dictionary).is_empty():
			return _saved_resume_fail("終了済み対戦のserver確定Resultがありません。")
		var result_snapshot: Dictionary = (pending_snapshot as Dictionary).duplicate(true)
		current_match_id = str(active.get("match_id", ""))
		current_match_mode = str(active.get("match_mode", ""))
		var result_destination := MatchResumeRouterScript.resolve(result_snapshot)
		if result_destination == MatchResumeRouterScript.DESTINATION_NONE:
			return _saved_resume_fail("server確定Resultから復帰先を決定できませんでした。")
		saved_match_resume_resolved.emit(result_destination, result_snapshot)
		return {
			"ok": true,
			"resumed": true,
			"destination": result_destination,
			"snapshot": result_snapshot,
		}

	var connect_result: Dictionary = await connect_realtime_socket(connect_timeout_seconds)
	if not bool(connect_result.get("ok", false)):
		return _saved_resume_fail("未解決対戦へのRealtime再接続に失敗しました。")

	current_match_id = str(active.get("match_id", ""))
	current_match_mode = str(active.get("match_mode", ""))
	_saved_resume_waiting = true
	_saved_resume_snapshot = {}

	var join_result = await realtime_socket.join_match_async(current_match_id)
	if join_result == null or join_result.is_exception():
		_saved_resume_waiting = false
		_saved_resume_snapshot = {}
		joined_match = null
		if _is_match_not_found_result(join_result) or _is_invalid_match_id_result(join_result):
			var refreshed := await refresh_active_online_match()
			if bool(refreshed.get("ok", false)) and not bool(refreshed.get("active", false)):
				_clear_runtime_match_state()
				return {
					"ok": true,
					"resumed": false,
					"match_not_found": true,
					"destination": MatchResumeRouterScript.DESTINATION_NONE,
				}
		return _saved_resume_fail(
			_result_error_message(join_result, "未解決authoritative matchへjoinできませんでした。")
		)

	if not bool(join_result.authoritative):
		_saved_resume_waiting = false
		_saved_resume_snapshot = {}
		joined_match = null
		return _saved_resume_fail("未解決matchがauthoritative matchではありません。")

	joined_match = join_result
	current_match_id = str(join_result.match_id)

	var snapshot_timeout_seconds := maxi(4, connect_timeout_seconds)
	var deadline := Time.get_ticks_msec() + snapshot_timeout_seconds * 1000
	while Time.get_ticks_msec() < deadline and _saved_resume_snapshot.is_empty():
		await get_tree().create_timer(0.02).timeout

	if _saved_resume_snapshot.is_empty():
		_saved_resume_waiting = false
		return _saved_resume_fail("未解決matchのauthoritative snapshotを受信できませんでした。")

	var snapshot := _saved_resume_snapshot.duplicate(true)
	_saved_resume_waiting = false
	_saved_resume_snapshot = {}

	var destination := MatchResumeRouterScript.resolve(snapshot)
	if destination == MatchResumeRouterScript.DESTINATION_NONE:
		return _saved_resume_fail("未解決match snapshotから復帰先を決定できませんでした。")

	saved_match_resume_resolved.emit(destination, snapshot)
	return {
		"ok": true,
		"resumed": true,
		"destination": destination,
		"snapshot": snapshot,
	}


func connect_realtime_socket(
	timeout_seconds: int = OnlineConfigScript.SOCKET_CONNECT_TIMEOUT_SECONDS
) -> Dictionary:
	_intentional_disconnect = false
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
		maxi(1, timeout_seconds)
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


func current_ranked_matchmaking_range() -> int:
	return _ranked_matchmaking_range


func ranked_matchmaking_elapsed_seconds() -> int:
	if _ranked_matchmaking_started_msec <= 0:
		return 0
	return maxi(0, int((Time.get_ticks_msec() - _ranked_matchmaking_started_msec) / 1000))


func _create_ranked_matchmaker_ticket(
	rating: int,
	character_id: String,
	rating_range: int
) -> Dictionary:
	if not is_realtime_connected():
		return {
			"ok": false,
			"message": "Realtime Socketが切断されています。",
		}

	var query := RankedMatchmakerQueryScript.build_with_range(rating, rating_range)
	var result = await realtime_socket.add_matchmaker_async(
		query,
		OnlineConfigScript.RANKED_MATCHMAKER_MIN_COUNT,
		OnlineConfigScript.RANKED_MATCHMAKER_MAX_COUNT,
		{
			"mode": OnlineConfigScript.RANKED_MATCHMAKER_MODE,
			"character_id": character_id,
		},
		{"rating": float(rating)}
	)
	if result == null or result.is_exception():
		return {
			"ok": false,
			"message": _result_error_message(result, "Matchmaker ticketを作成できませんでした。"),
		}

	return {
		"ok": true,
		"ticket": str(result.ticket),
		"min_rating": rating - rating_range,
		"max_rating": rating + rating_range,
	}


func _start_ranked_matchmaking_expansion(rating: int, character_id: String) -> void:
	_matchmaking_generation += 1
	_ranked_matchmaking_rating = rating
	_ranked_matchmaking_character_id = character_id
	_ranked_matchmaking_range = OnlineConfigScript.RANKED_INITIAL_RATING_RANGE
	_ranked_matchmaking_started_msec = Time.get_ticks_msec()
	var generation := _matchmaking_generation
	call_deferred("_run_ranked_matchmaking_expansion", generation)


func _stop_ranked_matchmaking_expansion() -> void:
	_matchmaking_generation += 1
	_ranked_matchmaking_rating = 0
	_ranked_matchmaking_character_id = ""
	_ranked_matchmaking_range = 0
	_ranked_matchmaking_started_msec = 0


func _run_ranked_matchmaking_expansion(generation: int) -> void:
	while (
		generation == _matchmaking_generation
		and not matchmaker_ticket.is_empty()
		and _ranked_matchmaking_range < OnlineConfigScript.RANKED_MAX_RATING_RANGE
	):
		await get_tree().create_timer(
			float(OnlineConfigScript.RANKED_RANGE_EXPAND_INTERVAL_SECONDS)
		).timeout

		if generation != _matchmaking_generation 				or matchmaker_ticket.is_empty() 				or not is_realtime_connected():
			return

		var next_range := mini(
			_ranked_matchmaking_range + OnlineConfigScript.RANKED_RATING_RANGE_STEP,
			OnlineConfigScript.RANKED_MAX_RATING_RANGE
		)
		var previous_ticket := matchmaker_ticket
		var remove_result = await realtime_socket.remove_matchmaker_async(previous_ticket)

		# matched/cancel/切断がawait中に成立した場合、後続ticketを作らない。
		if generation != _matchmaking_generation or matchmaker_ticket != previous_ticket:
			return

		if remove_result == null or remove_result.is_exception():
			_matchmaking_fail(
				"expand_remove",
				_result_error_message(remove_result, "検索幅拡大前のticket取消に失敗しました。")
			)
			return

		var create_result: Dictionary = await _create_ranked_matchmaker_ticket(
			_ranked_matchmaking_rating,
			_ranked_matchmaking_character_id,
			next_range
		)

		if generation != _matchmaking_generation:
			if bool(create_result.get("ok", false)) and is_realtime_connected():
				var superseded_ticket := str(create_result.get("ticket", ""))
				if not superseded_ticket.is_empty():
					await realtime_socket.remove_matchmaker_async(superseded_ticket)
			return

		if not bool(create_result.get("ok", false)):
			matchmaker_ticket = ""
			_stop_ranked_matchmaking_expansion()
			_matchmaking_fail(
				"expand_add",
				str(create_result.get("message", "検索幅拡大後のticket作成に失敗しました。"))
			)
			return

		matchmaker_ticket = str(create_result["ticket"])
		_ranked_matchmaking_range = next_range
		ranked_matchmaking_range_changed.emit(
			int(create_result["min_rating"]),
			int(create_result["max_rating"]),
			ranked_matchmaking_elapsed_seconds()
		)

	if generation != _matchmaking_generation or matchmaker_ticket.is_empty():
		return

	var elapsed := ranked_matchmaking_elapsed_seconds()
	var prolonged_wait_remaining := maxi(
		0,
		OnlineConfigScript.RANKED_PROLONGED_WAIT_SECONDS - elapsed
	)
	if prolonged_wait_remaining > 0:
		await get_tree().create_timer(float(prolonged_wait_remaining)).timeout

	if generation != _matchmaking_generation 			or matchmaker_ticket.is_empty() 			or not is_realtime_connected():
		return

	ranked_matchmaking_prolonged_wait.emit(
		ranked_matchmaking_elapsed_seconds(),
		_ranked_matchmaking_rating - _ranked_matchmaking_range,
		_ranked_matchmaking_rating + _ranked_matchmaking_range
	)


# CharacterSelectで確定したIDをMatchmaker propertyとしてserverへ渡す。
# character_id自体は対戦相手の検索条件には使用しない。
func start_ranked_matchmaking(rating: int, character_id: String) -> Dictionary:
	var active_check: Dictionary = await refresh_active_online_match()
	if not bool(active_check.get("ok", false)):
		return _matchmaking_fail(
			"active_match_check",
			str(active_check.get("message", "未解決対戦をserverで確認できませんでした。"))
		)
	if bool(active_check.get("active", false)) or has_unresolved_match_context():
		return _matchmaking_fail(
			"unresolved_match",
			"未解決の対戦があります。元の対戦を復帰または終了処理してから新しい対戦を開始してください。"
		)

	if not is_realtime_connected():
		return _matchmaking_fail("start", "Realtime Socket接続前はMatchmakerを開始できません。")

	if not matchmaker_ticket.is_empty():
		return _matchmaking_fail("start", "既にMatchmaker ticketがあります。")

	if not OnlineConfigScript.is_supported_ranked_character_id(character_id):
		return _matchmaking_fail("start", "未対応character_idです: %s" % character_id)

	var ticket_result: Dictionary = await _create_ranked_matchmaker_ticket(
		rating,
		character_id,
		OnlineConfigScript.RANKED_INITIAL_RATING_RANGE
	)
	if not bool(ticket_result.get("ok", false)):
		return _matchmaking_fail(
			"add_matchmaker",
			str(ticket_result.get("message", "Matchmaker ticketを作成できませんでした。"))
		)

	matchmaker_ticket = str(ticket_result["ticket"])
	_start_ranked_matchmaking_expansion(rating, character_id)
	ranked_matchmaking_started.emit(
		int(ticket_result["min_rating"]),
		int(ticket_result["max_rating"])
	)

	return {
		"ok": true,
		"min_rating": int(ticket_result["min_rating"]),
		"max_rating": int(ticket_result["max_rating"]),
		"character_id": character_id,
	}


func cancel_ranked_matchmaking() -> Dictionary:
	if matchmaker_ticket.is_empty():
		return _matchmaking_fail("cancel", "取消対象のMatchmaker ticketがありません。")

	var ticket_to_remove := matchmaker_ticket
	_stop_ranked_matchmaking_expansion()

	if not is_realtime_connected():
		matchmaker_ticket = ""
		return _matchmaking_fail("cancel", "Realtime Socketが切断されています。")

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

	_stop_ranked_matchmaking_expansion()
	matchmaker_ticket = ""
	var match_id := str(matched.match_id)
	if match_id.is_empty():
		_matchmaking_fail("matched", "authoritative match IDがありません。")
		return

	ranked_match_found.emit(match_id)

	# 前matchのsnapshotだけをjoin開始前に破棄する。
	# join直後にserverから届いた新snapshotをawait完了後に消してはならない。
	latest_match_snapshot = {}
	_next_input_sequence = 0
	_pending_join_match_id = match_id
	var join_result = await candidate.join_match_async(match_id)
	if join_result == null or join_result.is_exception():
		_pending_join_match_id = ""
		_matchmaking_fail(
			"join_match",
			_result_error_message(join_result, "authoritative matchへjoinできませんでした。")
		)
		return

	if not bool(join_result.authoritative):
		_pending_join_match_id = ""
		_matchmaking_fail("join_match", "join先がauthoritative matchではありません。")
		return

	joined_match = join_result
	if not register_joined_online_match(
		str(join_result.match_id),
		OnlineConfigScript.MATCH_MODE_RANKED
	):
		_pending_join_match_id = ""
		_matchmaking_fail("runtime_match", "対戦runtime状態を確定できませんでした。")
		return
	var active_context: Dictionary = await refresh_active_online_match()
	if not bool(active_context.get("ok", false)) 			or not bool(active_context.get("active", false)) 			or str(active_context.get("match_id", "")) != current_match_id:
		_pending_join_match_id = ""
		_matchmaking_fail("active_match", "対戦のserver-side active contextを確認できませんでした。")
		return
	_pending_join_match_id = ""
	ranked_match_joined.emit(current_match_id)


func _friend_room_rpc(rpc_id: String, payload: Dictionary, step: String) -> Dictionary:
	if not is_authenticated():
		return _friend_room_fail(step, "Friend room操作には認証が必要です。")

	var result = await client.rpc_async(session, rpc_id, JSON.stringify(payload))
	if result == null or result.is_exception():
		return _friend_room_fail(
			step,
			_result_error_message(result, "Friend roomのserver処理に失敗しました。")
		)

	var parsed = JSON.parse_string(str(result.payload))
	if not parsed is Dictionary:
		return _friend_room_fail(step, "Friend roomのserver応答を解析できませんでした。")

	var response: Dictionary = parsed
	response["ok"] = true
	friend_room_updated.emit(response)
	return response


func create_friend_room() -> Dictionary:
	var active_check: Dictionary = await refresh_active_online_match()
	if not bool(active_check.get("ok", false)):
		return _friend_room_fail(
			"active_match_check",
			str(active_check.get("message", "未解決対戦をserverで確認できませんでした。"))
		)
	if bool(active_check.get("active", false)) or has_unresolved_match_context():
		return _friend_room_fail(
			"create",
			"未解決の対戦があります。元の対戦を復帰または終了処理してからFriend roomを作成してください。"
		)

	var response := await _friend_room_rpc(
		OnlineConfigScript.FRIEND_ROOM_RPC_CREATE,
		{},
		"create"
	)
	if bool(response.get("ok", false)):
		friend_room_created.emit(str(response.get("room_code", "")), response)
	return response


func join_friend_room(room_code: String) -> Dictionary:
	var active_check: Dictionary = await refresh_active_online_match()
	if not bool(active_check.get("ok", false)):
		return _friend_room_fail(
			"active_match_check",
			str(active_check.get("message", "未解決対戦をserverで確認できませんでした。"))
		)
	if bool(active_check.get("active", false)) or has_unresolved_match_context():
		return _friend_room_fail(
			"join",
			"未解決の対戦があります。元の対戦を復帰または終了処理してからFriend roomへ参加してください。"
		)

	var response := await _friend_room_rpc(
		OnlineConfigScript.FRIEND_ROOM_RPC_JOIN,
		{"room_code": room_code},
		"join"
	)
	if bool(response.get("ok", false)):
		friend_room_joined.emit(str(response.get("room_code", "")), response)
	return response


func get_friend_room_status(room_code: String) -> Dictionary:
	return await _friend_room_rpc(
		OnlineConfigScript.FRIEND_ROOM_RPC_STATUS,
		{"room_code": room_code},
		"status"
	)


func set_friend_room_character(room_code: String, character_id: String) -> Dictionary:
	if not OnlineConfigScript.is_supported_online_character_id(character_id):
		return _friend_room_fail(
			"character",
			"未対応character_idです: %s" % character_id
		)
	return await _friend_room_rpc(
		OnlineConfigScript.FRIEND_ROOM_RPC_CHARACTER,
		{
			"room_code": room_code,
			"character_id": character_id,
		},
		"character"
	)


func set_friend_room_ready(room_code: String, ready: bool) -> Dictionary:
	if ready:
		var active_check: Dictionary = await refresh_active_online_match()
		if not bool(active_check.get("ok", false)):
			return _friend_room_fail(
				"active_match_check",
				str(active_check.get("message", "未解決対戦をserverで確認できませんでした。"))
			)
	if ready and (bool(_active_match_context.get("active", false)) or has_unresolved_match_context()):
		return _friend_room_fail(
			"unresolved_match",
			"未解決の対戦があります。元の対戦を復帰または終了処理してからFriend matchを開始してください。"
		)
	return await _friend_room_rpc(
		OnlineConfigScript.FRIEND_ROOM_RPC_READY,
		{
			"room_code": room_code,
			"ready": ready,
		},
		"ready"
	)


func leave_friend_room(room_code: String) -> Dictionary:
	return await _friend_room_rpc(
		OnlineConfigScript.FRIEND_ROOM_RPC_LEAVE,
		{"room_code": room_code},
		"leave"
	)


func join_friend_match_from_room(room: Dictionary) -> Dictionary:
	var active_check: Dictionary = await refresh_active_online_match()
	if not bool(active_check.get("ok", false)):
		return _friend_room_fail(
			"active_match_check",
			str(active_check.get("message", "未解決対戦をserverで確認できませんでした。"))
		)
	if bool(active_check.get("active", false)) or has_unresolved_match_context():
		return _friend_room_fail(
			"join_match",
			"未解決の対戦があります。元の対戦を復帰または終了処理してから新しいFriend matchへ参加してください。"
		)
	if not is_realtime_connected():
		return _friend_room_fail(
			"join_match",
			"Realtime Socket接続前はFriend matchへ参加できません。"
		)

	var match_id := str(room.get("current_match_id", ""))
	if match_id.is_empty():
		return _friend_room_fail("join_match", "Friend match IDがまだ確定していません。")
	if str(room.get("state", "")) != "IN_MATCH":
		return _friend_room_fail("join_match", "Friend roomが対戦開始状態ではありません。")

	latest_match_snapshot = {}
	_next_input_sequence = 0
	_pending_join_match_id = match_id
	var join_result = await realtime_socket.join_match_async(match_id)
	if join_result == null or join_result.is_exception():
		_pending_join_match_id = ""
		return _friend_room_fail(
			"join_match",
			_result_error_message(join_result, "Friend authoritative matchへjoinできませんでした。")
		)
	if not bool(join_result.authoritative):
		_pending_join_match_id = ""
		return _friend_room_fail("join_match", "join先がauthoritative matchではありません。")

	joined_match = join_result
	if not register_joined_online_match(
		str(join_result.match_id),
		OnlineConfigScript.MATCH_MODE_FRIEND
	):
		_pending_join_match_id = ""
		return _friend_room_fail("runtime_match", "Friend対戦runtime状態を確定できませんでした。")
	var active_context: Dictionary = await refresh_active_online_match()
	if not bool(active_context.get("ok", false)) 			or not bool(active_context.get("active", false)) 			or str(active_context.get("match_id", "")) != current_match_id:
		_pending_join_match_id = ""
		return _friend_room_fail("active_match", "Friend対戦のserver-side active contextを確認できませんでした。")

	_pending_join_match_id = ""
	friend_match_joined.emit(current_match_id)
	return {
		"ok": true,
		"match_id": current_match_id,
	}


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
	var expected_match_id := current_match_id
	if expected_match_id.is_empty():
		expected_match_id = _pending_join_match_id
	if expected_match_id.is_empty() or str(match_state.match_id) != expected_match_id:
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
		return

	if op_code == CombatInputProtocolScript.OPCODE_ROUND_OVERTIME_STARTED:
		var overtime_event := CombatInputProtocolScript.parse_round_overtime_started_payload(str(match_state.data))
		if overtime_event.is_empty():
			return
		round_overtime_started.emit(int(overtime_event["server_tick"]))
		return

	if op_code == CombatInputProtocolScript.OPCODE_ROUND_RESULT:
		var result_event := CombatInputProtocolScript.parse_round_result_payload(str(match_state.data))
		if result_event.is_empty():
			return
		round_result.emit(
			int(result_event["round_number"]),
			str(result_event["winner_user_id"]),
			str(result_event["loser_user_id"]),
			str(result_event["finish_cause"]),
			int(result_event["winner_hits"]),
			int(result_event["loser_hits"]),
			int(result_event["server_tick"])
		)
		return

	if op_code == CombatInputProtocolScript.OPCODE_BO3_SCORE_CHANGED:
		var score_event := CombatInputProtocolScript.parse_bo3_score_changed_payload(str(match_state.data))
		if score_event.is_empty():
			return
		bo3_score_changed.emit(
			int(score_event["completed_round_number"]),
			str(score_event["round_winner_user_id"]),
			score_event["round_wins_by_user"],
			bool(score_event["match_finished"]),
			int(score_event["server_tick"])
		)
		return

	if op_code == CombatInputProtocolScript.OPCODE_ROUND_STARTED:
		var started_event := CombatInputProtocolScript.parse_round_started_payload(str(match_state.data))
		if started_event.is_empty():
			return
		round_started.emit(
			int(started_event["round_number"]),
			started_event["round_wins_by_user"],
			int(started_event["server_tick"])
		)
		return

	if op_code == CombatInputProtocolScript.OPCODE_MATCH_RESULT:
		var match_event := CombatInputProtocolScript.parse_match_result_payload(str(match_state.data))
		if match_event.is_empty():
			return
		match_result.emit(
			str(match_event["winner_user_id"]),
			str(match_event["loser_user_id"]),
			match_event["round_wins_by_user"],
			int(match_event["final_round_number"]),
			str(match_event["finish_cause"]),
			int(match_event["server_tick"])
		)

		return

	if op_code == CombatInputProtocolScript.OPCODE_ROUND_COUNTDOWN_CHANGED:
		var countdown_event := CombatInputProtocolScript.parse_round_countdown_changed_payload(
			str(match_state.data)
		)
		if countdown_event.is_empty():
			return
		round_countdown_changed.emit(
			int(countdown_event["round_number"]),
			int(countdown_event["countdown_value"]),
			int(countdown_event["server_tick"])
		)

		return

	if op_code == CombatInputProtocolScript.OPCODE_MATCH_SNAPSHOT:
		var snapshot := CombatInputProtocolScript.parse_match_snapshot_payload(
			str(match_state.data)
		)
		if snapshot.is_empty():
			return
		_next_input_sequence = int(snapshot["last_input_sequence"])
		current_match_mode = str(snapshot.get("match_mode", current_match_mode))
		latest_match_snapshot = snapshot.duplicate(true)
		if _saved_resume_waiting:
			_saved_resume_snapshot = snapshot.duplicate(true)
		match_snapshot_received.emit(snapshot)
		if _reconnect_in_progress:
			_reconnect_in_progress = false
			reconnect_succeeded.emit(current_match_id)
		return

	if op_code == CombatInputProtocolScript.OPCODE_PLAYER_CONNECTION_CHANGED:
		var connection_event := CombatInputProtocolScript.parse_player_connection_changed_payload(
			str(match_state.data)
		)
		if connection_event.is_empty():
			return
		player_connection_changed.emit(
			str(connection_event["user_id"]),
			bool(connection_event["connected"]),
			int(connection_event["reconnect_deadline_tick"]),
			int(connection_event["server_tick"])
		)


func is_realtime_connected() -> bool:
	return realtime_socket != null and realtime_socket.is_connected_to_host()


func disconnect_realtime_socket() -> bool:
	if realtime_socket == null:
		return false

	_intentional_disconnect = true
	_cancel_reconnect()
	var candidate = realtime_socket
	candidate.close()
	return true


func _clear_runtime_match_state() -> void:
	joined_match = null
	current_match_id = ""
	current_match_mode = ""
	_pending_join_match_id = ""
	latest_match_snapshot = {}
	_next_input_sequence = 0


func clear_runtime_session_preserving_match() -> void:
	_intentional_disconnect = true
	_cancel_reconnect()
	_stop_ranked_matchmaking_expansion()
	disconnect_realtime_socket()
	matchmaker_ticket = ""
	_clear_runtime_match_state()
	_active_match_context = {}
	session = null
	account = null


func clear_session() -> void:
	clear_runtime_session_preserving_match()


func is_reconnecting() -> bool:
	return _reconnect_in_progress


func reconnect_remaining_seconds() -> int:
	if not _reconnect_in_progress:
		return 0
	var remaining_ms := maxi(0, _reconnect_deadline_msec - Time.get_ticks_msec())
	return int(ceil(float(remaining_ms) / 1000.0))


func _on_realtime_connected(candidate) -> void:
	if realtime_socket != candidate:
		return
	print("Nakama realtime socket connected: user_id=%s" % str(session.user_id))
	realtime_connected.emit(str(session.user_id))


func _on_realtime_closed(candidate) -> void:
	if realtime_socket != candidate:
		return

	realtime_socket = null
	_stop_ranked_matchmaking_expansion()
	matchmaker_ticket = ""
	joined_match = null
	realtime_disconnected.emit()

	if _intentional_disconnect:
		_intentional_disconnect = false
		return

	if current_match_id.is_empty() or not is_authenticated():
		return

	_begin_reconnect()


func _begin_reconnect() -> void:
	if _reconnect_in_progress:
		return
	if current_match_id.is_empty() or not is_authenticated():
		return

	_reconnect_in_progress = true
	_reconnect_generation += 1
	var generation := _reconnect_generation
	_reconnect_deadline_msec = Time.get_ticks_msec() + OnlineConfigScript.RECONNECT_GRACE_SECONDS * 1000
	reconnect_started.emit(OnlineConfigScript.RECONNECT_GRACE_SECONDS)
	call_deferred("_run_reconnect_loop", generation)


func _cancel_reconnect() -> void:
	_reconnect_generation += 1
	_reconnect_in_progress = false
	_reconnect_deadline_msec = 0


func _run_reconnect_loop(generation: int) -> void:
	while _reconnect_in_progress and generation == _reconnect_generation:
		var connect_result: Dictionary = await connect_realtime_socket()
		if bool(connect_result.get("ok", false)) and realtime_socket != null:
			var reconnect_match_id := current_match_id
			var join_result = await realtime_socket.join_match_async(reconnect_match_id)
			if join_result != null and not join_result.is_exception() and bool(join_result.authoritative):
				joined_match = join_result
				current_match_id = str(join_result.match_id)
				# 15秒以内なら進行中snapshot、超過後なら終了済みsnapshotをserverが返す。
				# MATCH_SNAPSHOT受信時点でreconnect_succeededとする。
				return

			if _is_match_not_found_result(join_result):
				_reconnect_in_progress = false
				var active_refresh: Dictionary = await refresh_active_online_match()
				if bool(active_refresh.get("ok", false)) and not bool(active_refresh.get("active", false)):
					_clear_runtime_match_state()
				var missing_message := "元の対戦はserver上に存在せず、復帰できませんでした。"
				reconnect_failed.emit(missing_message)
				return

			var failed_socket = realtime_socket
			realtime_socket = null
			if failed_socket != null:
				failed_socket.close()

		await get_tree().create_timer(OnlineConfigScript.RECONNECT_RETRY_SECONDS).timeout


func _on_realtime_connection_error(error, candidate) -> void:
	if realtime_socket != candidate:
		return
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


func _is_match_not_found_result(result) -> bool:
	if result == null or not result.has_method("get_exception"):
		return false
	var exception = result.get_exception()
	if exception == null:
		return false
	return int(exception.grpc_status_code) == 5 or int(exception.status_code) == 404


func _is_invalid_match_id_result(result) -> bool:
	if result == null or not result.has_method("get_exception"):
		return false
	var exception = result.get_exception()
	if exception == null:
		return false
	return str(exception.message).to_lower().contains("invalid match id")


func _result_error_message(result, fallback: String) -> String:
	if result != null and result.has_method("get_exception"):
		var exception = result.get_exception()
		if exception != null and not str(exception.message).is_empty():
			return str(exception.message)
	return fallback


func _saved_resume_fail(message: String) -> Dictionary:
	printerr("Nakama saved match resume failed: %s" % message)
	saved_match_resume_failed.emit(message)
	return {
		"ok": false,
		"message": message,
	}


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


func _friend_room_fail(step: String, message: String) -> Dictionary:
	printerr("Nakama friend room failed: step=%s message=%s" % [step, message])
	friend_room_failed.emit(step, message)
	return {
		"ok": false,
		"step": step,
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
