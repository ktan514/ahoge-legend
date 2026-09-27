extends SceneTree

const OnlineConfigScript := preload("res://src/config/online_config.gd")
const CombatInputProtocolScript := preload("res://src/online/combat_input_protocol.gd")

var _second_socket = null
var _second_ticket: String = ""
var _second_match_id: String = ""
var _second_failure: String = ""
var _p2_states: Array[Dictionary] = []
var _p2_contacts: Array[Dictionary] = []


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
	var p2_user_id := str(second_session.user_id)

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

	var p1_states: Array[Dictionary] = []
	var p1_contacts: Array[Dictionary] = []
	online_session.combat_state_changed.connect(
		func(user_id: String, state: String, server_tick: int, charge_ratio: float) -> void:
			p1_states.append({
				"user_id": user_id,
				"state": state,
				"server_tick": server_tick,
				"charge_ratio": charge_ratio,
			})
	)
	online_session.contact_reached.connect(
		func(attacker_id: String, defender_id: String, server_tick: int, input_sequence: int, charge_ratio: float) -> void:
			p1_contacts.append({
				"attacker_id": attacker_id,
				"defender_id": defender_id,
				"server_tick": server_tick,
				"input_sequence": input_sequence,
				"charge_ratio": charge_ratio,
			})
	)

	var p1_start: Dictionary = await online_session.start_ranked_matchmaking(1500, OnlineConfigScript.RANKED_CHARACTER_LONG_TEST)
	if not bool(p1_start.get("ok", false)):
		_fail("P1 Ranked Matchmakerを開始できませんでした。")
		return

	var query: String = online_session.build_ranked_matchmaker_query(1500)
	var second_ticket_result = await _second_socket.add_matchmaker_async(
		query,
		OnlineConfigScript.RANKED_MATCHMAKER_MIN_COUNT,
		OnlineConfigScript.RANKED_MATCHMAKER_MAX_COUNT,
		{"mode": OnlineConfigScript.RANKED_MATCHMAKER_MODE, "character_id": OnlineConfigScript.RANKED_CHARACTER_LONG_TEST},
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

	# authoritative Round Countdown完了後に戦闘を開始する。
	await create_timer(3.5).timeout
	var p1_state_start := p1_states.size()
	var p2_state_start := _p2_states.size()

	var press_result: Dictionary = await online_session.send_combat_input(
		CombatInputProtocolScript.ACTION_ATTACK_PRESS
	)
	if not bool(press_result.get("ok", false)):
		_fail("ATTACK_PRESSを送信できませんでした。")
		return

	if not await _wait_for_state(p1_states, p1_user_id, "CHARGING", 5000):
		_fail("P1がCHARGINGを受信できませんでした。")
		return
	if not await _wait_for_state(_p2_states, p1_user_id, "CHARGING", 5000):
		_fail("P2がP1のCHARGINGを受信できませんでした。")
		return

	await create_timer(0.08).timeout

	var release_result: Dictionary = await online_session.send_combat_input(
		CombatInputProtocolScript.ACTION_ATTACK_RELEASE
	)
	if not bool(release_result.get("ok", false)):
		_fail("ATTACK_RELEASEを送信できませんでした。")
		return
	var release_sequence := int(release_result.get("input_sequence", 0))

	for expected_state in ["WINDUP", "STRIKE", "COOLDOWN", "IDLE"]:
		if not await _wait_for_state_from(p1_states, p1_user_id, expected_state, p1_state_start, 5000):
			_fail("P1が%sを受信できませんでした。" % expected_state)
			return
		if not await _wait_for_state_from(_p2_states, p1_user_id, expected_state, p2_state_start, 5000):
			_fail("P2がP1の%sを受信できませんでした。" % expected_state)
			return

	if not await _wait_for_contact(p1_contacts, p1_user_id, release_sequence, 5000):
		_fail("P1がContactEventを受信できませんでした。")
		return
	if not await _wait_for_contact(_p2_contacts, p1_user_id, release_sequence, 5000):
		_fail("P2がP1のContactEventを受信できませんでした。")
		return

	var p1_attack_states := _states_for_user_from(p1_states, p1_user_id, p1_state_start)
	var p2_attack_states := _states_for_user_from(_p2_states, p1_user_id, p2_state_start)
	var expected_states := ["CHARGING", "WINDUP", "STRIKE", "COOLDOWN", "IDLE"]
	if p1_attack_states != expected_states:
		_fail("P1の攻撃状態順序が不正です: %s" % str(p1_attack_states))
		return
	if p2_attack_states != expected_states:
		_fail("P2の攻撃状態順序が不正です: %s" % str(p2_attack_states))
		return

	var contact := _contact_for_user(p1_contacts, p1_user_id, release_sequence)
	if contact.is_empty():
		_fail("P1 ContactEventを取得できませんでした。")
		return
	if str(contact["defender_id"]) != p2_user_id:
		_fail("ContactEvent defenderがP2ではありません。")
		return
	if float(contact["charge_ratio"]) <= 0.0 or float(contact["charge_ratio"]) > 1.0:
		_fail("charge ratioが0.0..1.0の範囲外です。")
		return
	if _count_contacts(p1_contacts, p1_user_id, release_sequence) != 1:
		_fail("1攻撃でContactEventが複数発生しました。")
		return

	var states_before_invalid := p1_attack_states.size()
	var invalid_release: Dictionary = await online_session.send_combat_input(
		CombatInputProtocolScript.ACTION_ATTACK_RELEASE
	)
	if not bool(invalid_release.get("ok", false)):
		_fail("IDLE中のATTACK_RELEASE自体がtransport拒否されました。")
		return
	await create_timer(0.3).timeout
	if _states_for_user_from(p1_states, p1_user_id, p1_state_start).size() != states_before_invalid:
		_fail("IDLE中ATTACK_RELEASEが攻撃状態へ適用されました。")
		return

	await online_session.realtime_socket.leave_match_async(p1_joined[0])
	await _second_socket.leave_match_async(_second_match_id)
	online_session.disconnect_realtime_socket()
	_second_socket.close()

	print(
		"AHOGE LEGEND attack state smoke: PASS charge_ratio=%.3f match_id=%s"
		% [float(contact["charge_ratio"]), p1_joined[0]]
	)
	quit(0)


func _wait_for_state(
	events: Array[Dictionary],
	user_id: String,
	state: String,
	timeout_ms: int
) -> bool:
	var deadline := Time.get_ticks_msec() + timeout_ms
	while Time.get_ticks_msec() < deadline:
		for event in events:
			if str(event["user_id"]) == user_id and str(event["state"]) == state:
				return true
		await create_timer(0.05).timeout
	return false


func _wait_for_state_from(
	events: Array[Dictionary],
	user_id: String,
	state: String,
	start_index: int,
	timeout_ms: int
) -> bool:
	var deadline := Time.get_ticks_msec() + timeout_ms
	while Time.get_ticks_msec() < deadline:
		for index in range(maxi(start_index, 0), events.size()):
			var event := events[index]
			if str(event["user_id"]) == user_id and str(event["state"]) == state:
				return true
		await create_timer(0.05).timeout
	return false


func _wait_for_contact(
	events: Array[Dictionary],
	attacker_id: String,
	input_sequence: int,
	timeout_ms: int
) -> bool:
	var deadline := Time.get_ticks_msec() + timeout_ms
	while Time.get_ticks_msec() < deadline:
		if not _contact_for_user(events, attacker_id, input_sequence).is_empty():
			return true
		await create_timer(0.05).timeout
	return false


func _states_for_user(events: Array[Dictionary], user_id: String) -> Array:
	var states: Array = []
	for event in events:
		if str(event["user_id"]) == user_id:
			states.append(str(event["state"]))
	return states


func _states_for_user_from(events: Array[Dictionary], user_id: String, start_index: int) -> Array:
	var states: Array = []
	for index in range(maxi(start_index, 0), events.size()):
		var event := events[index]
		if str(event["user_id"]) == user_id:
			states.append(str(event["state"]))
	return states


func _contact_for_user(
	events: Array[Dictionary],
	attacker_id: String,
	input_sequence: int
) -> Dictionary:
	for event in events:
		if str(event["attacker_id"]) == attacker_id 				and int(event["input_sequence"]) == input_sequence:
			return event
	return {}


func _count_contacts(
	events: Array[Dictionary],
	attacker_id: String,
	input_sequence: int
) -> int:
	var count := 0
	for event in events:
		if str(event["attacker_id"]) == attacker_id 				and int(event["input_sequence"]) == input_sequence:
			count += 1
	return count


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


func _on_second_match_state(match_state) -> void:
	if _second_match_id.is_empty() or str(match_state.match_id) != _second_match_id:
		return

	var op_code := int(match_state.op_code)
	if op_code == CombatInputProtocolScript.OPCODE_COMBAT_STATE_CHANGED:
		var state_event := CombatInputProtocolScript.parse_combat_state_changed_payload(
			str(match_state.data)
		)
		if not state_event.is_empty():
			_p2_states.append(state_event)
		return

	if op_code == CombatInputProtocolScript.OPCODE_CONTACT_REACHED:
		var contact_event := CombatInputProtocolScript.parse_contact_reached_payload(
			str(match_state.data)
		)
		if not contact_event.is_empty():
			_p2_contacts.append(contact_event)


func _fail(message: String) -> void:
	if _second_socket != null:
		_second_socket.close()
	push_error(message)
	print("AHOGE LEGEND attack state smoke: FAIL")
	quit(1)
