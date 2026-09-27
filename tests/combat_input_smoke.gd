extends SceneTree

const OnlineConfigScript := preload("res://src/config/online_config.gd")
const CombatInputProtocolScript := preload("res://src/online/combat_input_protocol.gd")

var _second_socket = null
var _second_ticket: String = ""
var _second_match_id: String = ""
var _second_joined_match = null
var _second_failure: String = ""
var _p2_accepted: Array[Dictionary] = []


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
	var p1_user_id := str(auth_result.get("user_id", ""))

	var realtime_result: Dictionary = await online_session.connect_realtime_socket()
	if not bool(realtime_result.get("ok", false)):
		_fail("P1 Realtime Socket接続に失敗しました。")
		return

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

	var p1_accepted: Array[Dictionary] = []
	online_session.combat_input_accepted.connect(
		func(user_id: String, input_sequence: int, action: String, server_tick: int) -> void:
			p1_accepted.append({
				"user_id": user_id,
				"input_sequence": input_sequence,
				"action": action,
				"server_tick": server_tick,
			})
	)

	var p1_start: Dictionary = await online_session.start_ranked_matchmaking(1500)
	if not bool(p1_start.get("ok", false)):
		_fail("P1 Ranked Matchmakerを開始できませんでした。")
		return

	var query: String = online_session.build_ranked_matchmaker_query(1500)
	var second_ticket_result = await _second_socket.add_matchmaker_async(
		query,
		OnlineConfigScript.RANKED_MATCHMAKER_MIN_COUNT,
		OnlineConfigScript.RANKED_MATCHMAKER_MAX_COUNT,
		{"mode": OnlineConfigScript.RANKED_MATCHMAKER_MODE},
		{"rating": 1500.0}
	)
	if second_ticket_result == null or second_ticket_result.is_exception():
		_fail("P2 Ranked Matchmakerを開始できませんでした。")
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
		_fail("P1とP2のmatch IDが一致しません。")
		return

	var send_result: Dictionary = await online_session.send_combat_input(
		CombatInputProtocolScript.ACTION_ATTACK_PRESS
	)
	if not bool(send_result.get("ok", false)) or int(send_result.get("input_sequence", 0)) != 1:
		_fail("P1の初回戦闘入力を送信できませんでした。")
		return

	if not await _wait_for_sequence(p1_accepted, p1_user_id, 1, 5000):
		_fail("P1がsequence=1のINPUT_ACCEPTEDを受信できませんでした。")
		return
	if not await _wait_for_sequence(_p2_accepted, p1_user_id, 1, 5000):
		_fail("P2がP1 sequence=1のINPUT_ACCEPTEDを受信できませんでした。")
		return

	await create_timer(0.1).timeout
	var accepted_before_duplicate := _count_user_events(p1_accepted, p1_user_id)
	await _send_explicit(p1_joined[0], 1, CombatInputProtocolScript.ACTION_ATTACK_PRESS)
	await create_timer(0.2).timeout
	if _count_user_events(p1_accepted, p1_user_id) != accepted_before_duplicate:
		_fail("duplicate sequenceが受理されました。")
		return

	await _send_explicit(p1_joined[0], 3, CombatInputProtocolScript.ACTION_DEFEND)
	if not await _wait_for_sequence(p1_accepted, p1_user_id, 3, 5000):
		_fail("sequence=3の正常入力が受理されませんでした。")
		return

	await create_timer(0.1).timeout
	var accepted_before_out_of_order := _count_user_events(p1_accepted, p1_user_id)
	await _send_explicit(p1_joined[0], 2, CombatInputProtocolScript.ACTION_ATTACK_RELEASE)
	await create_timer(0.2).timeout
	if _count_user_events(p1_accepted, p1_user_id) != accepted_before_out_of_order:
		_fail("out-of-order sequenceが受理されました。")
		return

	await create_timer(0.1).timeout
	var accepted_before_invalid := _count_user_events(p1_accepted, p1_user_id)
	await _send_explicit(p1_joined[0], 4, "INVALID_ACTION")
	await create_timer(0.2).timeout
	if _count_user_events(p1_accepted, p1_user_id) != accepted_before_invalid:
		_fail("不正actionが受理されました。")
		return

	await create_timer(0.1).timeout
	var burst_start_count := _count_user_events(p1_accepted, p1_user_id)
	for sequence in range(4, 44):
		online_session.realtime_socket.send_match_state_async(
			p1_joined[0],
			CombatInputProtocolScript.OPCODE_COMBAT_INPUT,
			CombatInputProtocolScript.build_input_payload(
				sequence,
				CombatInputProtocolScript.ACTION_ATTACK_RELEASE
			)
		)
	await create_timer(0.6).timeout

	var burst_events := _user_events_from(p1_accepted, p1_user_id, burst_start_count)
	if burst_events.is_empty():
		_fail("burst入力が1件も受理されませんでした。")
		return
	if burst_events.size() >= 40:
		_fail("同一tick制限が機能せずburst入力がすべて受理されました。")
		return

	var seen_ticks := {}
	for event in burst_events:
		var server_tick := int(event["server_tick"])
		if seen_ticks.has(server_tick):
			_fail("同じserver tickで同一userの入力が複数受理されました。")
			return
		seen_ticks[server_tick] = true

	await online_session.realtime_socket.leave_match_async(p1_joined[0])
	await _second_socket.leave_match_async(_second_match_id)
	online_session.disconnect_realtime_socket()
	_second_socket.close()

	print(
		"AHOGE LEGEND combat input smoke: PASS accepted=%d match_id=%s"
		% [_count_user_events(p1_accepted, p1_user_id), p1_joined[0]]
	)
	quit(0)


func _send_explicit(match_id: String, sequence: int, action: String) -> void:
	await get_root().get_node("OnlineSession").realtime_socket.send_match_state_async(
		match_id,
		CombatInputProtocolScript.OPCODE_COMBAT_INPUT,
		CombatInputProtocolScript.build_input_payload(sequence, action)
	)


func _wait_for_sequence(
	events: Array[Dictionary],
	user_id: String,
	sequence: int,
	timeout_ms: int
) -> bool:
	var deadline := Time.get_ticks_msec() + timeout_ms
	while Time.get_ticks_msec() < deadline:
		for event in events:
			if str(event["user_id"]) == user_id and int(event["input_sequence"]) == sequence:
				return true
		await create_timer(0.05).timeout
	return false


func _count_user_events(events: Array[Dictionary], user_id: String) -> int:
	var count := 0
	for event in events:
		if str(event["user_id"]) == user_id:
			count += 1
	return count


func _user_events_from(events: Array[Dictionary], user_id: String, start_count: int) -> Array[Dictionary]:
	var user_events: Array[Dictionary] = []
	for event in events:
		if str(event["user_id"]) == user_id:
			user_events.append(event)
	if start_count >= user_events.size():
		return []
	return user_events.slice(start_count)


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
	_second_joined_match = join_result
	_second_match_id = str(join_result.match_id)


func _on_second_match_state(match_state) -> void:
	if int(match_state.op_code) != CombatInputProtocolScript.OPCODE_INPUT_ACCEPTED:
		return
	if _second_match_id.is_empty() or str(match_state.match_id) != _second_match_id:
		return
	var accepted := CombatInputProtocolScript.parse_accepted_payload(str(match_state.data))
	if not accepted.is_empty():
		_p2_accepted.append(accepted)


func _fail(message: String) -> void:
	if _second_socket != null:
		_second_socket.close()
	push_error(message)
	print("AHOGE LEGEND combat input smoke: FAIL")
	quit(1)
