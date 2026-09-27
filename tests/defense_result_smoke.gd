extends SceneTree

const OnlineConfigScript := preload("res://src/config/online_config.gd")
const CombatInputProtocolScript := preload("res://src/online/combat_input_protocol.gd")

var _second_socket = null
var _second_ticket: String = ""
var _second_match_id: String = ""
var _second_failure: String = ""
var _second_sequence: int = 0
var _p1_states: Array[Dictionary] = []
var _p2_states: Array[Dictionary] = []
var _p1_results: Array[Dictionary] = []
var _p2_results: Array[Dictionary] = []


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
	var round_one_started := [false]
	online_session.round_started.connect(
		func(round_number: int, _round_wins: Dictionary, _server_tick: int) -> void:
			if round_number == 1:
				round_one_started[0] = true
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

	# 固定時間ではなくauthoritative ROUND_STARTEDを待ってから戦闘を開始する。
	var round_start_deadline := Time.get_ticks_msec() + 7000
	while Time.get_ticks_msec() < round_start_deadline and not round_one_started[0]:
		await create_timer(0.02).timeout
	if not round_one_started[0]:
		_fail("Round 1のauthoritative開始を受信できませんでした。")
		return

	# DefenseなしContactはNONE。
	var none_state_index := _p1_states.size()
	var none_sequence := await _start_p1_attack(online_session, p1_user_id, 0.0)
	if none_sequence <= 0:
		return
	var none_p1 := await _wait_for_result(_p1_results, p1_user_id, none_sequence, 5000)
	var none_p2 := await _wait_for_result(_p2_results, p1_user_id, none_sequence, 5000)
	if not _assert_result_pair(none_p1, none_p2, "NONE"):
		return
	if not await _wait_for_state(_p1_states, p1_user_id, "IDLE", none_state_index, 5000):
		_fail("NONE検証後にP1がIDLEへ復帰しませんでした。")
		return

	# 通常攻撃のSTRIKE開始直後にDefenseし、通常PARRYを成立させる。
	var parry_state_index := _p1_states.size()
	var parry_p2_state_index := _p2_states.size()
	var parry_sequence := await _start_p1_attack(online_session, p1_user_id, 0.0)
	if parry_sequence <= 0:
		return
	if not await _send_second_defend():
		return
	if not await _wait_for_state(_p2_states, p2_user_id, "PARRY", parry_p2_state_index, 5000):
		_fail("P2がPARRYへ遷移しませんでした。")
		return
	var parry_p1 := await _wait_for_result(_p1_results, p1_user_id, parry_sequence, 5000)
	var parry_p2 := await _wait_for_result(_p2_results, p1_user_id, parry_sequence, 5000)
	if not _assert_result_pair(parry_p1, parry_p2, "PARRY"):
		return
	if not await _wait_for_state(_p1_states, p1_user_id, "IDLE", parry_state_index, 5000):
		_fail("PARRY検証後にP1がIDLEへ復帰しませんでした。")
		return
	if not await _wait_for_state(_p2_states, p2_user_id, "IDLE", parry_p2_state_index, 5000):
		_fail("PARRY検証後にP2がIDLEへ復帰しませんでした。")
		return

	# 最大ChargeではContactがSTRIKE開始から3tick後。STRIKE受信直後のDefenseでJUST_PARRYを成立させる。
	var just_state_index := _p1_states.size()
	var just_sequence := await _start_p1_attack(online_session, p1_user_id, 0.65)
	if just_sequence <= 0:
		return
	if not await _send_second_defend():
		return
	var just_p1 := await _wait_for_result(_p1_results, p1_user_id, just_sequence, 5000)
	var just_p2 := await _wait_for_result(_p2_results, p1_user_id, just_sequence, 5000)
	if not _assert_result_pair(just_p1, just_p2, "JUST_PARRY"):
		return
	if not await _wait_for_state(_p1_states, p1_user_id, "IDLE", just_state_index, 5000):
		_fail("JUST_PARRY検証後にP1がIDLEへ復帰しませんでした。")
		return

	await online_session.realtime_socket.leave_match_async(p1_joined[0])
	await _second_socket.leave_match_async(_second_match_id)
	online_session.disconnect_realtime_socket()
	_second_socket.close()

	print("AHOGE LEGEND defense result smoke: PASS match_id=%s" % p1_joined[0])
	quit(0)


func _start_p1_attack(online_session, p1_user_id: String, charge_seconds: float) -> int:
	var start_index := _p1_states.size()
	var press: Dictionary = await online_session.send_combat_input(
		CombatInputProtocolScript.ACTION_ATTACK_PRESS
	)
	if not bool(press.get("ok", false)):
		_fail("ATTACK_PRESSを送信できませんでした。")
		return -1
	if not await _wait_for_state(_p1_states, p1_user_id, "CHARGING", start_index, 5000):
		_fail("P1がCHARGINGへ遷移しませんでした。")
		return -1

	if charge_seconds > 0.0:
		await create_timer(charge_seconds).timeout

	var release: Dictionary = await online_session.send_combat_input(
		CombatInputProtocolScript.ACTION_ATTACK_RELEASE
	)
	if not bool(release.get("ok", false)):
		_fail("ATTACK_RELEASEを送信できませんでした。")
		return -1
	var sequence := int(release.get("input_sequence", 0))
	if not await _wait_for_state(_p1_states, p1_user_id, "STRIKE", start_index, 5000):
		_fail("P1がSTRIKEへ遷移しませんでした。")
		return -1
	return sequence


func _send_second_defend() -> bool:
	_second_sequence += 1
	var result = await _second_socket.send_match_state_async(
		_second_match_id,
		CombatInputProtocolScript.OPCODE_COMBAT_INPUT,
		CombatInputProtocolScript.build_input_payload(
			_second_sequence,
			CombatInputProtocolScript.ACTION_DEFEND
		)
	)
	if result != null and result.has_method("is_exception") and result.is_exception():
		_fail("P2 DEFENDを送信できませんでした。")
		return false
	return true


func _on_first_match_state(match_state) -> void:
	_collect_match_state(match_state, _p1_states, _p1_results)


func _on_second_match_state(match_state) -> void:
	if _second_match_id.is_empty() or str(match_state.match_id) != _second_match_id:
		return
	_collect_match_state(match_state, _p2_states, _p2_results)


func _collect_match_state(
	match_state,
	state_events: Array[Dictionary],
	result_events: Array[Dictionary]
) -> void:
	var op_code := int(match_state.op_code)
	if op_code == CombatInputProtocolScript.OPCODE_COMBAT_STATE_CHANGED:
		var state_event := CombatInputProtocolScript.parse_combat_state_changed_payload(
			str(match_state.data)
		)
		if not state_event.is_empty():
			state_events.append(state_event)
		return
	if op_code == CombatInputProtocolScript.OPCODE_DEFENSE_RESOLVED:
		var result_event := CombatInputProtocolScript.parse_defense_resolved_payload(
			str(match_state.data)
		)
		if not result_event.is_empty():
			result_events.append(result_event)


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


func _wait_for_state(
	events: Array[Dictionary],
	user_id: String,
	state: String,
	start_index: int,
	timeout_ms: int
) -> bool:
	var deadline := Time.get_ticks_msec() + timeout_ms
	while Time.get_ticks_msec() < deadline:
		for index in range(maxi(start_index, 0), events.size()):
			if str(events[index].get("user_id", "")) == user_id \
					and str(events[index].get("state", "")) == state:
				return true
		await create_timer(0.02).timeout
	return false


func _wait_for_result(
	events: Array[Dictionary],
	attacker_id: String,
	input_sequence: int,
	timeout_ms: int
) -> Dictionary:
	var deadline := Time.get_ticks_msec() + timeout_ms
	while Time.get_ticks_msec() < deadline:
		for event in events:
			if str(event.get("attacker_id", "")) == attacker_id \
					and int(event.get("input_sequence", 0)) == input_sequence:
				return event
		await create_timer(0.02).timeout
	_fail("DefenseResultを受信できませんでした。sequence=%d" % input_sequence)
	return {}


func _assert_result_pair(first: Dictionary, second: Dictionary, expected: String) -> bool:
	if first.is_empty() or second.is_empty():
		return false
	if str(first.get("result", "")) != expected:
		_fail("P1 DefenseResultが%sではありません: %s" % [expected, str(first.get("result", ""))])
		return false
	if str(second.get("result", "")) != expected:
		_fail("P2 DefenseResultが%sではありません: %s" % [expected, str(second.get("result", ""))])
		return false
	if int(first.get("server_tick", -1)) != int(second.get("server_tick", -2)):
		_fail("P1/P2でDefenseResult server tickが一致しません。")
		return false
	if str(first.get("defender_id", "")) != str(second.get("defender_id", "")):
		_fail("P1/P2でDefenseResult defenderが一致しません。")
		return false
	return true


func _fail(message: String) -> void:
	if _second_socket != null:
		_second_socket.close()
	push_error(message)
	print("AHOGE LEGEND defense result smoke: FAIL")
	quit(1)
