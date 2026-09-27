extends SceneTree

const OnlineConfigScript := preload("res://src/config/online_config.gd")
const CombatInputProtocolScript := preload("res://src/online/combat_input_protocol.gd")

var _second_client = null
var _second_session = null
var _second_socket = null
var _second_ticket: String = ""
var _second_match_id: String = ""
var _second_failure: String = ""

var _p1_user_id: String = ""
var _p2_user_id: String = ""
var _p1_states: Array[Dictionary] = []
var _p1_counts: Array[Dictionary] = []
var _p1_timers: Array[Dictionary] = []
var _p1_results: Array[Dictionary] = []
var _p1_scores: Array[Dictionary] = []
var _p1_countdowns: Array[Dictionary] = []
var _p1_connections: Array[Dictionary] = []
var _round_started_numbers: Array[int] = []
var _rejoined_snapshot: Dictionary = {}


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var online_session = get_root().get_node_or_null("OnlineSession")
	var nakama = get_root().get_node_or_null("Nakama")
	if online_session == null or nakama == null:
		_fail("OnlineSession / Nakama Autoloadが見つかりません。")
		return

	var auth_result: Dictionary = await online_session.authenticate_local_device()
	if not bool(auth_result.get("ok", false)):
		_fail("P1 Device認証に失敗しました。")
		return
	_p1_user_id = str(auth_result.get("user_id", ""))

	var realtime_result: Dictionary = await online_session.connect_realtime_socket()
	if not bool(realtime_result.get("ok", false)):
		_fail("P1 Realtime Socket接続に失敗しました。")
		return

	online_session.combat_state_changed.connect(
		func(user_id: String, state_name: String, server_tick: int, charge_ratio: float) -> void:
			_p1_states.append({
				"user_id": user_id,
				"state": state_name,
				"server_tick": server_tick,
				"charge_ratio": charge_ratio,
			})
	)
	online_session.round_hit_count_changed.connect(
		func(user_id: String, hit_count: int, server_tick: int, input_sequence: int) -> void:
			_p1_counts.append({
				"user_id": user_id,
				"hit_count": hit_count,
				"server_tick": server_tick,
				"input_sequence": input_sequence,
			})
	)
	online_session.round_timer_changed.connect(
		func(remaining_seconds: int, server_tick: int) -> void:
			_p1_timers.append({
				"remaining_seconds": remaining_seconds,
				"server_tick": server_tick,
			})
	)
	online_session.round_result.connect(
		func(round_number: int, winner_user_id: String, loser_user_id: String, finish_cause: String, winner_hits: int, loser_hits: int, server_tick: int) -> void:
			_p1_results.append({
				"round_number": round_number,
				"winner_user_id": winner_user_id,
				"loser_user_id": loser_user_id,
				"finish_cause": finish_cause,
				"winner_hits": winner_hits,
				"loser_hits": loser_hits,
				"server_tick": server_tick,
			})
	)
	online_session.bo3_score_changed.connect(
		func(completed_round_number: int, round_winner_user_id: String, round_wins_by_user: Dictionary, match_finished: bool, server_tick: int) -> void:
			_p1_scores.append({
				"completed_round_number": completed_round_number,
				"round_winner_user_id": round_winner_user_id,
				"round_wins_by_user": round_wins_by_user,
				"match_finished": match_finished,
				"server_tick": server_tick,
			})
	)
	online_session.round_countdown_changed.connect(
		func(round_number: int, countdown_value: int, server_tick: int) -> void:
			_p1_countdowns.append({
				"round_number": round_number,
				"countdown_value": countdown_value,
				"server_tick": server_tick,
			})
	)
	online_session.round_started.connect(
		func(round_number: int, _round_wins: Dictionary, _server_tick: int) -> void:
			_round_started_numbers.append(round_number)
	)
	online_session.player_connection_changed.connect(
		func(user_id: String, connected: bool, reconnect_deadline_tick: int, server_tick: int) -> void:
			_p1_connections.append({
				"user_id": user_id,
				"connected": connected,
				"reconnect_deadline_tick": reconnect_deadline_tick,
				"server_tick": server_tick,
			})
	)

	_second_client = nakama.create_client(
		OnlineConfigScript.SERVER_KEY,
		OnlineConfigScript.HOST,
		OnlineConfigScript.PORT,
		OnlineConfigScript.SCHEME,
		OnlineConfigScript.CLIENT_TIMEOUT_SECONDS,
		OnlineConfigScript.CLIENT_LOG_LEVEL
	)
	var second_device_id := Crypto.new().generate_random_bytes(32).hex_encode()
	_second_session = await _second_client.authenticate_device_async(second_device_id, null, true)
	if _second_session == null or _second_session.is_exception():
		_fail("P2 Device認証に失敗しました。")
		return
	_p2_user_id = str(_second_session.user_id)

	if not await _connect_second_socket(true):
		return

	var p1_joined := [""]
	online_session.ranked_match_joined.connect(func(match_id: String) -> void:
		p1_joined[0] = match_id
	)

	var p1_start: Dictionary = await online_session.start_ranked_matchmaking(
		1500,
		OnlineConfigScript.RANKED_CHARACTER_LONG_TEST
	)
	if not bool(p1_start.get("ok", false)):
		_fail("P1 Matchmakerを開始できませんでした。")
		return

	var ticket_result = await _second_socket.add_matchmaker_async(
		online_session.build_ranked_matchmaker_query(1500),
		OnlineConfigScript.RANKED_MATCHMAKER_MIN_COUNT,
		OnlineConfigScript.RANKED_MATCHMAKER_MAX_COUNT,
		{
			"mode": OnlineConfigScript.RANKED_MATCHMAKER_MODE,
			"character_id": OnlineConfigScript.RANKED_CHARACTER_LONG_TEST,
		},
		{"rating": 1500.0}
	)
	if ticket_result == null or ticket_result.is_exception():
		_fail("P2 Matchmakerを開始できませんでした。")
		return
	_second_ticket = str(ticket_result.ticket)

	var join_deadline := Time.get_ticks_msec() + 40000
	while Time.get_ticks_msec() < join_deadline:
		if not _second_failure.is_empty():
			_fail(_second_failure)
			return
		if not p1_joined[0].is_empty() and not _second_match_id.is_empty():
			break
		await create_timer(0.05).timeout

	if p1_joined[0].is_empty() or _second_match_id.is_empty():
		_fail("2クライアントがauthoritative matchへjoinできませんでした。")
		return
	if p1_joined[0] != _second_match_id:
		_fail("P1/P2 match IDが一致しません。")
		return

	if not await _wait_round_started(1, 7000):
		_fail("Round 1開始を受信できませんでした。")
		return

	var timer_before_disconnect := _latest_timer()
	if timer_before_disconnect < 0:
		_fail("切断前timerを取得できませんでした。")
		return

	_second_socket.close()
	_second_socket = null

	if not await _wait_connection(_p2_user_id, false, 3000):
		_fail("P2切断eventをP1が受信できませんでした。")
		return

	if not await _wait_timer_less_than(timer_before_disconnect, 2500):
		_fail("active Round中のP2切断でtimerが停止しました。")
		return

	for hit_index in range(1, 6):
		if not await _p1_attack_once(online_session, hit_index):
			return

	var result := await _wait_round_result(1, 5000)
	if result.is_empty():
		_fail("P2切断中にRound 1を完了できませんでした。")
		return
	if str(result.get("winner_user_id", "")) != _p1_user_id 			or str(result.get("finish_cause", "")) != "HIT_LIMIT":
		_fail("P2切断中のRound Resultが期待値と一致しません。")
		return

	var score := await _wait_score(1, 5000)
	if score.is_empty():
		_fail("P2切断中のBO3 scoreを受信できませんでした。")
		return
	if int(score.get("round_wins_by_user", {}).get(_p1_user_id, -1)) != 1:
		_fail("P2切断中のRound取得数が1ではありません。")
		return

	await create_timer(2.5).timeout
	if _has_countdown_for_round(2):
		_fail("P2不在のままRound 2 Countdownが開始しました。")
		return

	_rejoined_snapshot = {}
	if not await _connect_second_socket(false):
		return
	var rejoin_result = await _second_socket.join_match_async(_second_match_id)
	if rejoin_result == null or rejoin_result.is_exception():
		_fail("P2同一user IDでauthoritative matchへ再joinできませんでした。")
		return

	var snapshot_deadline := Time.get_ticks_msec() + 4000
	while Time.get_ticks_msec() < snapshot_deadline and _rejoined_snapshot.is_empty():
		await create_timer(0.02).timeout
	if _rejoined_snapshot.is_empty():
		_fail("P2再join時にauthoritative snapshotを受信できませんでした。")
		return

	if int(_rejoined_snapshot.get("round_number", -1)) != 1 			or not bool(_rejoined_snapshot.get("round_finished", false)) 			or int(_rejoined_snapshot.get("round_hit_count_by_user", {}).get(_p1_user_id, -1)) != 5 			or int(_rejoined_snapshot.get("round_wins_by_user", {}).get(_p1_user_id, -1)) != 1:
		_fail("P2再join snapshotがRound終了時のauthoritative stateと一致しません。")
		return

	if not await _wait_connection(_p2_user_id, true, 3000):
		_fail("P2再接続eventをP1が受信できませんでした。")
		return

	if not await _wait_countdown(2, 3, 5000):
		_fail("P2復帰後にRound 2 Countdownが再開しませんでした。")
		return
	if not await _wait_round_started(2, 7000):
		_fail("P2復帰後にRound 2が開始しませんでした。")
		return

	await online_session.realtime_socket.leave_match_async(p1_joined[0])
	if _second_socket != null:
		await _second_socket.leave_match_async(_second_match_id)
		_second_socket.close()
	online_session.disconnect_realtime_socket()

	print("AHOGE LEGEND reconnect smoke: PASS match_id=%s" % p1_joined[0])
	quit(0)


func _connect_second_socket(for_matchmaker: bool) -> bool:
	var nakama = get_root().get_node_or_null("Nakama")
	_second_socket = nakama.create_socket_from(_second_client)
	if for_matchmaker:
		_second_socket.received_matchmaker_matched.connect(_on_second_matchmaker_matched)
	_second_socket.received_match_state.connect(_on_second_match_state)
	var result = await _second_socket.connect_async(
		_second_session,
		OnlineConfigScript.SOCKET_APPEAR_ONLINE,
		OnlineConfigScript.SOCKET_CONNECT_TIMEOUT_SECONDS
	)
	if result == null or result.is_exception():
		_fail("P2 Realtime Socket接続に失敗しました。")
		return false
	return true


func _on_second_matchmaker_matched(matched) -> void:
	if matched == null or matched.is_exception():
		_second_failure = "P2 matchmaker matched通知が不正です。"
		return
	if str(matched.ticket) != _second_ticket:
		return
	var match_id := str(matched.match_id)
	if match_id.is_empty():
		_second_failure = "P2 matched通知にmatch IDがありません。"
		return
	var join_result = await _second_socket.join_match_async(match_id)
	if join_result == null or join_result.is_exception():
		_second_failure = "P2 authoritative match joinに失敗しました。"
		return
	_second_match_id = str(join_result.match_id)


func _on_second_match_state(match_state) -> void:
	if _second_match_id.is_empty() or str(match_state.match_id) != _second_match_id:
		return
	if int(match_state.op_code) == CombatInputProtocolScript.OPCODE_MATCH_SNAPSHOT:
		var snapshot := CombatInputProtocolScript.parse_match_snapshot_payload(str(match_state.data))
		if not snapshot.is_empty():
			_rejoined_snapshot = snapshot


func _p1_attack_once(online_session, expected_hit_count: int) -> bool:
	var start_state := _p1_states.size()
	var press: Dictionary = await online_session.send_combat_input(
		CombatInputProtocolScript.ACTION_ATTACK_PRESS
	)
	if not bool(press.get("ok", false)):
		_fail("P1 ATTACK_PRESSを送信できませんでした。")
		return false
	if not await _wait_state(_p1_user_id, "CHARGING", start_state, 3000):
		_fail("P1 CHARGINGを確認できませんでした。")
		return false

	var release: Dictionary = await online_session.send_combat_input(
		CombatInputProtocolScript.ACTION_ATTACK_RELEASE
	)
	if not bool(release.get("ok", false)):
		_fail("P1 ATTACK_RELEASEを送信できませんでした。")
		return false
	var sequence := int(release.get("input_sequence", 0))

	if not await _wait_count(_p1_user_id, expected_hit_count, sequence, 4000):
		_fail("P1 Hit count=%dを確認できませんでした。" % expected_hit_count)
		return false

	if expected_hit_count < 5:
		if not await _wait_state(_p1_user_id, "IDLE", start_state, 4000):
			_fail("P1が次の攻撃前にIDLEへ復帰しませんでした。")
			return false
	return true


func _wait_state(user_id: String, state_name: String, start_index: int, timeout_ms: int) -> bool:
	var deadline := Time.get_ticks_msec() + timeout_ms
	while Time.get_ticks_msec() < deadline:
		for index in range(start_index, _p1_states.size()):
			var event := _p1_states[index]
			if str(event.get("user_id", "")) == user_id and str(event.get("state", "")) == state_name:
				return true
		await create_timer(0.02).timeout
	return false


func _wait_count(user_id: String, hit_count: int, sequence: int, timeout_ms: int) -> bool:
	var deadline := Time.get_ticks_msec() + timeout_ms
	while Time.get_ticks_msec() < deadline:
		for event in _p1_counts:
			if str(event.get("user_id", "")) == user_id 					and int(event.get("hit_count", -1)) == hit_count 					and int(event.get("input_sequence", -1)) == sequence:
				return true
		await create_timer(0.02).timeout
	return false


func _latest_timer() -> int:
	if _p1_timers.is_empty():
		return -1
	return int(_p1_timers[_p1_timers.size() - 1].get("remaining_seconds", -1))


func _wait_timer_less_than(value: int, timeout_ms: int) -> bool:
	var deadline := Time.get_ticks_msec() + timeout_ms
	while Time.get_ticks_msec() < deadline:
		var current := _latest_timer()
		if current >= 0 and current < value:
			return true
		await create_timer(0.02).timeout
	return false


func _wait_round_result(round_number: int, timeout_ms: int) -> Dictionary:
	var deadline := Time.get_ticks_msec() + timeout_ms
	while Time.get_ticks_msec() < deadline:
		for event in _p1_results:
			if int(event.get("round_number", -1)) == round_number:
				return event
		await create_timer(0.02).timeout
	return {}


func _wait_score(completed_round_number: int, timeout_ms: int) -> Dictionary:
	var deadline := Time.get_ticks_msec() + timeout_ms
	while Time.get_ticks_msec() < deadline:
		for event in _p1_scores:
			if int(event.get("completed_round_number", -1)) == completed_round_number:
				return event
		await create_timer(0.02).timeout
	return {}


func _has_countdown_for_round(round_number: int) -> bool:
	for event in _p1_countdowns:
		if int(event.get("round_number", -1)) == round_number:
			return true
	return false


func _wait_countdown(round_number: int, value: int, timeout_ms: int) -> bool:
	var deadline := Time.get_ticks_msec() + timeout_ms
	while Time.get_ticks_msec() < deadline:
		for event in _p1_countdowns:
			if int(event.get("round_number", -1)) == round_number 					and int(event.get("countdown_value", -1)) == value:
				return true
		await create_timer(0.02).timeout
	return false


func _wait_round_started(round_number: int, timeout_ms: int) -> bool:
	var deadline := Time.get_ticks_msec() + timeout_ms
	while Time.get_ticks_msec() < deadline:
		if round_number in _round_started_numbers:
			return true
		await create_timer(0.02).timeout
	return false


func _wait_connection(user_id: String, connected: bool, timeout_ms: int) -> bool:
	var deadline := Time.get_ticks_msec() + timeout_ms
	while Time.get_ticks_msec() < deadline:
		for event in _p1_connections:
			if str(event.get("user_id", "")) == user_id and bool(event.get("connected", false)) == connected:
				return true
		await create_timer(0.02).timeout
	return false


func _fail(message: String) -> void:
	if _second_socket != null:
		_second_socket.close()
	push_error(message)
	print("AHOGE LEGEND reconnect smoke: FAIL")
	quit(1)
