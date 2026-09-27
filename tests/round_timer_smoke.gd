extends SceneTree

const OnlineConfigScript := preload("res://src/config/online_config.gd")
const CombatInputProtocolScript := preload("res://src/online/combat_input_protocol.gd")

var _second_socket = null
var _second_ticket: String = ""
var _second_match_id: String = ""
var _second_failure: String = ""
var _p1_timers: Array[Dictionary] = []
var _p2_timers: Array[Dictionary] = []


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

	var realtime_result: Dictionary = await online_session.connect_realtime_socket()
	if not bool(realtime_result.get("ok", false)):
		_fail("P1 Realtime Socket接続に失敗しました。")
		return
	online_session.realtime_socket.received_match_state.connect(_on_first_match_state)

	var second_client = nakama.create_client(
		OnlineConfigScript.SERVER_KEY,
		OnlineConfigScript.HOST,
		OnlineConfigScript.PORT,
		OnlineConfigScript.SCHEME,
		OnlineConfigScript.CLIENT_TIMEOUT_SECONDS,
		OnlineConfigScript.CLIENT_LOG_LEVEL
	)
	var second_device_id := Crypto.new().generate_random_bytes(32).hex_encode()
	var second_session = await second_client.authenticate_device_async(second_device_id, null, true)
	if second_session == null or second_session.is_exception():
		_fail("P2 Device認証に失敗しました。")
		return

	_second_socket = nakama.create_socket_from(second_client)
	_second_socket.received_matchmaker_matched.connect(_on_second_matchmaker_matched)
	_second_socket.received_match_state.connect(_on_second_match_state)
	var second_connect = await _second_socket.connect_async(
		second_session,
		OnlineConfigScript.SOCKET_APPEAR_ONLINE,
		OnlineConfigScript.SOCKET_CONNECT_TIMEOUT_SECONDS
	)
	if second_connect == null or second_connect.is_exception():
		_fail("P2 Realtime Socket接続に失敗しました。")
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

	var query: String = online_session.build_ranked_matchmaker_query(1500)
	var second_ticket_result = await _second_socket.add_matchmaker_async(
		query,
		OnlineConfigScript.RANKED_MATCHMAKER_MIN_COUNT,
		OnlineConfigScript.RANKED_MATCHMAKER_MAX_COUNT,
		{
			"mode": OnlineConfigScript.RANKED_MATCHMAKER_MODE,
			"character_id": OnlineConfigScript.RANKED_CHARACTER_LONG_TEST,
		},
		{"rating": 1500.0}
	)
	if second_ticket_result == null or second_ticket_result.is_exception():
		_fail("P2 Matchmakerを開始できませんでした。")
		return
	_second_ticket = str(second_ticket_result.ticket)

	var join_deadline := Time.get_ticks_msec() + 40000
	while Time.get_ticks_msec() < join_deadline:
		if not _second_failure.is_empty():
			_fail(_second_failure)
			return
		if not p1_joined[0].is_empty() and not _second_match_id.is_empty():
			break
		await create_timer(0.1).timeout

	if p1_joined[0].is_empty() or _second_match_id.is_empty():
		_fail("2クライアントがauthoritative matchへjoinできませんでした。")
		return
	if p1_joined[0] != _second_match_id:
		_fail("P1/P2 match IDが一致しません。")
		return

	var start_event := await _wait_for_timer_pair(85, 5000)
	if start_event.is_empty():
		_fail("85秒timer開始を両clientで受信できませんでした。")
		return

	var next_event := await _wait_for_timer_pair(84, 3000)
	if next_event.is_empty():
		_fail("timerが85から84へ進みませんでした。")
		return
	if int(next_event["server_tick"]) - int(start_event["server_tick"]) != 30:
		_fail("85→84が30 server tickではありません。")
		return

	var zero_event := await _wait_for_timer_pair(0, 95000)
	if zero_event.is_empty():
		_fail("85秒timerが0へ到達しませんでした。")
		return

	if int(zero_event["server_tick"]) - int(start_event["server_tick"]) != 2550:
		_fail("85→0の経過が2550 server tickではありません。")
		return

	if _p1_timers != _p2_timers:
		_fail("P1/P2のRound timer event列が一致しません。")
		return

	if _p1_timers.size() != 86:
		_fail("Round timer event数が86件ではありません: %d" % _p1_timers.size())
		return

	for index in range(_p1_timers.size()):
		var event := _p1_timers[index]
		var expected_seconds := 85 - index
		if int(event.get("remaining_seconds", -1)) != expected_seconds:
			_fail("Round timer値が連続していません。index=%d" % index)
			return
		if index > 0:
			var previous := _p1_timers[index - 1]
			if int(event.get("server_tick", -1)) - int(previous.get("server_tick", -1)) != 30:
				_fail("Round timer更新間隔が30tickではありません。index=%d" % index)
				return

	var count_at_zero := _p1_timers.size()
	await create_timer(1.2).timeout
	if _p1_timers.size() != count_at_zero or _p2_timers.size() != count_at_zero:
		_fail("0到達後もRound timer eventが増加しました。")
		return

	await online_session.realtime_socket.leave_match_async(p1_joined[0])
	await _second_socket.leave_match_async(_second_match_id)
	online_session.disconnect_realtime_socket()
	_second_socket.close()

	print("AHOGE LEGEND round timer smoke: PASS match_id=%s" % p1_joined[0])
	quit(0)


func _on_first_match_state(match_state) -> void:
	_collect_timer(match_state, _p1_timers)


func _on_second_match_state(match_state) -> void:
	if _second_match_id.is_empty() or str(match_state.match_id) != _second_match_id:
		return
	_collect_timer(match_state, _p2_timers)


func _collect_timer(match_state, events: Array[Dictionary]) -> void:
	if int(match_state.op_code) != CombatInputProtocolScript.OPCODE_ROUND_TIMER_CHANGED:
		return
	var event := CombatInputProtocolScript.parse_round_timer_changed_payload(
		str(match_state.data)
	)
	if not event.is_empty():
		events.append(event)


func _on_second_matchmaker_matched(matched) -> void:
	if matched == null or matched.is_exception():
		_second_failure = "P2 matchmaker matched通知が不正です。"
		return
	if str(matched.ticket) != _second_ticket:
		return
	var match_id := str(matched.match_id)
	if match_id.is_empty():
		_second_failure = "P2 matched通知にauthoritative match IDがありません。"
		return
	var join_result = await _second_socket.join_match_async(match_id)
	if join_result == null or join_result.is_exception():
		_second_failure = "P2 authoritative match joinに失敗しました。"
		return
	_second_match_id = str(join_result.match_id)


func _wait_for_timer_pair(remaining_seconds: int, timeout_ms: int) -> Dictionary:
	var deadline := Time.get_ticks_msec() + timeout_ms
	while Time.get_ticks_msec() < deadline:
		var first := _find_timer(_p1_timers, remaining_seconds)
		var second := _find_timer(_p2_timers, remaining_seconds)
		if not first.is_empty() and not second.is_empty():
			if first != second:
				_fail("P1/P2でRound timer payloadが一致しません。remaining=%d" % remaining_seconds)
				return {}
			return first
		await create_timer(0.02).timeout
	return {}


func _find_timer(events: Array[Dictionary], remaining_seconds: int) -> Dictionary:
	for event in events:
		if int(event.get("remaining_seconds", -1)) == remaining_seconds:
			return event
	return {}


func _fail(message: String) -> void:
	if _second_socket != null:
		_second_socket.close()
	push_error(message)
	print("AHOGE LEGEND round timer smoke: FAIL")
	quit(1)
