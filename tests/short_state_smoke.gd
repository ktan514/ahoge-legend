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
var _p1_defense_results: Array[Dictionary] = []
var _p2_defense_results: Array[Dictionary] = []


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

	var p1_start: Dictionary = await online_session.start_ranked_matchmaking(
		1500,
		OnlineConfigScript.RANKED_CHARACTER_SHORT_TEST
	)
	if not bool(p1_start.get("ok", false)):
		_fail("P1 SHORT_TESTでRanked Matchmakerを開始できませんでした。")
		return
	if str(p1_start.get("character_id", "")) != OnlineConfigScript.RANKED_CHARACTER_SHORT_TEST:
		_fail("P1 Matchmaker結果にSHORT_TESTが保持されていません。")
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
		_fail("P2 LONG_TESTでRanked Matchmakerを開始できませんでした。")
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

	# P2 LONG_TESTを先にChargeしておき、P1 SHORT detach後に最大Chargeをreleaseする。
	var p2_charge_index := _p1_states.size()
	if not await _send_second_input(CombatInputProtocolScript.ACTION_ATTACK_PRESS):
		return
	if not await _wait_for_state(_p1_states, p2_user_id, "CHARGING", p2_charge_index, 5000):
		_fail("P2 LONG_TESTがCHARGINGへ遷移しませんでした。")
		return

	await create_timer(0.42).timeout

	var p1_attack_index := _p1_states.size()
	var p1_press: Dictionary = await online_session.send_combat_input(
		CombatInputProtocolScript.ACTION_ATTACK_PRESS
	)
	if not bool(p1_press.get("ok", false)):
		_fail("P1 SHORT ATTACK_PRESSを送信できませんでした。")
		return
	if not await _wait_for_state(_p1_states, p1_user_id, "CHARGING", p1_attack_index, 5000):
		_fail("P1 SHORTがCHARGINGへ遷移しませんでした。")
		return

	var p1_release: Dictionary = await online_session.send_combat_input(
		CombatInputProtocolScript.ACTION_ATTACK_RELEASE
	)
	if not bool(p1_release.get("ok", false)):
		_fail("P1 SHORT ATTACK_RELEASEを送信できませんでした。")
		return

	var short_strike := await _wait_for_state_event(
		_p1_states,
		p1_user_id,
		"STRIKE",
		p1_attack_index,
		5000
	)
	if short_strike.is_empty():
		_fail("P1 SHORTのSTRIKEを受信できませんでした。")
		return
	if bool(short_strike.get("ahoge_available", true)):
		_fail("SHORT_TESTがSTRIKE開始時にdetachしていません。")
		return
	var regrow_until_tick := int(short_strike.get("regrow_until_tick", -1))
	if regrow_until_tick - int(short_strike.get("server_tick", -1)) != 18:
		_fail("SHORT regrow時間が18tickではありません。")
		return

	# P2はLONG_TESTなのでStrikeへ入ってもdetachしない。
	if not await _send_second_input(CombatInputProtocolScript.ACTION_ATTACK_RELEASE):
		return
	var p2_release_sequence := _second_sequence
	var long_strike := await _wait_for_state_event(
		_p1_states,
		p2_user_id,
		"STRIKE",
		p2_charge_index,
		5000
	)
	if long_strike.is_empty():
		_fail("P2 LONG_TESTのSTRIKEを受信できませんでした。")
		return
	if not bool(long_strike.get("ahoge_available", false)):
		_fail("LONG_TESTがSTRIKE時にdetachしました。")
		return
	if int(long_strike.get("regrow_until_tick", -1)) != -1:
		_fail("LONG_TESTにregrow timerが設定されました。")
		return

	# P2最大ChargeのContact直前に、detach中P1がDEFENDしてJUST_DODGEを成立させる。
	var dodge_index := _p1_states.size()
	var p2_stagger_index := _p1_states.size()
	var p1_defend: Dictionary = await online_session.send_combat_input(
		CombatInputProtocolScript.ACTION_DEFEND
	)
	if not bool(p1_defend.get("ok", false)):
		_fail("P1 detach中DEFENDを送信できませんでした。")
		return

	var dodge_state := await _wait_for_state_event(
		_p1_states,
		p1_user_id,
		"DODGE",
		dodge_index,
		5000
	)
	if dodge_state.is_empty():
		_fail("detach中DEFENDがDODGEへ遷移しませんでした。")
		return
	if bool(dodge_state.get("ahoge_available", true)):
		_fail("DODGE中にahoge_availableがtrueです。")
		return

	var dodge_result_p1 := await _wait_for_defense_result(
		_p1_defense_results,
		p2_release_sequence,
		"JUST_DODGE",
		5000
	)
	var dodge_result_p2 := await _wait_for_defense_result(
		_p2_defense_results,
		p2_release_sequence,
		"JUST_DODGE",
		5000
	)
	if dodge_result_p1.is_empty() or dodge_result_p2.is_empty():
		return
	if dodge_result_p1 != dodge_result_p2:
		_fail("P1/P2でJUST_DODGE結果が一致しません。")
		return

	if not await _wait_for_state(
		_p1_states,
		p2_user_id,
		"STAGGER",
		p2_stagger_index,
		5000
	):
		_fail("JUST_DODGE成功後に攻撃側P2がSTAGGERへ遷移しませんでした。")
		return

	# Regrowはaction stateと独立して進み、指定tickでtrueへ戻る。
	var regrow_event := await _wait_for_availability(
		_p1_states,
		p1_user_id,
		true,
		regrow_until_tick,
		5000
	)
	var regrow_event_p2 := await _wait_for_availability(
		_p2_states,
		p1_user_id,
		true,
		regrow_until_tick,
		5000
	)
	if regrow_event.is_empty() or regrow_event_p2.is_empty():
		return
	if regrow_event != regrow_event_p2:
		_fail("P1/P2でRegrow状態が一致しません。")
		return
	if int(regrow_event.get("regrow_until_tick", 0)) != -1:
		_fail("Regrow後もregrow_until_tickが残っています。")
		return

	# Regrow後は再びPARRYへ戻る。
	var ready_index := _p1_states.size()
	if not await _wait_for_state(_p1_states, p1_user_id, "IDLE", ready_index - 1, 5000):
		# Regrow event自体がIDLEの場合を許容し、次のDEFENDを試す。
		pass

	var parry_index := _p1_states.size()
	var final_defend: Dictionary = await online_session.send_combat_input(
		CombatInputProtocolScript.ACTION_DEFEND
	)
	if not bool(final_defend.get("ok", false)):
		_fail("Regrow後DEFENDを送信できませんでした。")
		return
	if not await _wait_for_state(_p1_states, p1_user_id, "PARRY", parry_index, 5000):
		_fail("Regrow後DEFENDがPARRYへ戻りませんでした。")
		return

	await online_session.realtime_socket.leave_match_async(p1_joined[0])
	await _second_socket.leave_match_async(_second_match_id)
	online_session.disconnect_realtime_socket()
	_second_socket.close()

	print("AHOGE LEGEND short state smoke: PASS match_id=%s" % p1_joined[0])
	quit(0)


func _send_second_input(action: String) -> bool:
	_second_sequence += 1
	var result = await _second_socket.send_match_state_async(
		_second_match_id,
		CombatInputProtocolScript.OPCODE_COMBAT_INPUT,
		CombatInputProtocolScript.build_input_payload(_second_sequence, action)
	)
	if result != null and result.has_method("is_exception") and result.is_exception():
		_fail("P2 %sを送信できませんでした。" % action)
		return false
	return true


func _on_first_match_state(match_state) -> void:
	_collect_match_state(match_state, _p1_states, _p1_defense_results)


func _on_second_match_state(match_state) -> void:
	if _second_match_id.is_empty() or str(match_state.match_id) != _second_match_id:
		return
	_collect_match_state(match_state, _p2_states, _p2_defense_results)


func _collect_match_state(
	match_state,
	state_events: Array[Dictionary],
	defense_events: Array[Dictionary]
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
		var defense_event := CombatInputProtocolScript.parse_defense_resolved_payload(
			str(match_state.data)
		)
		if not defense_event.is_empty():
			defense_events.append(defense_event)


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
	state_name: String,
	start_index: int,
	timeout_ms: int
) -> bool:
	return not (await _wait_for_state_event(events, user_id, state_name, start_index, timeout_ms)).is_empty()


func _wait_for_state_event(
	events: Array[Dictionary],
	user_id: String,
	state_name: String,
	start_index: int,
	timeout_ms: int
) -> Dictionary:
	var deadline := Time.get_ticks_msec() + timeout_ms
	while Time.get_ticks_msec() < deadline:
		for index in range(maxi(start_index, 0), events.size()):
			var event := events[index]
			if str(event.get("user_id", "")) == user_id 					and str(event.get("state", "")) == state_name:
				return event
		await create_timer(0.02).timeout
	return {}


func _wait_for_availability(
	events: Array[Dictionary],
	user_id: String,
	available: bool,
	minimum_server_tick: int,
	timeout_ms: int
) -> Dictionary:
	var deadline := Time.get_ticks_msec() + timeout_ms
	while Time.get_ticks_msec() < deadline:
		for event in events:
			if str(event.get("user_id", "")) == user_id 					and bool(event.get("ahoge_available", not available)) == available 					and int(event.get("server_tick", -1)) >= minimum_server_tick:
				return event
		await create_timer(0.02).timeout
	_fail("ahoge_available=%sの更新を受信できませんでした。" % str(available))
	return {}


func _wait_for_defense_result(
	events: Array[Dictionary],
	input_sequence: int,
	expected_result: String,
	timeout_ms: int
) -> Dictionary:
	var deadline := Time.get_ticks_msec() + timeout_ms
	while Time.get_ticks_msec() < deadline:
		for event in events:
			if int(event.get("input_sequence", -1)) == input_sequence 					and str(event.get("result", "")) == expected_result:
				return event
		await create_timer(0.02).timeout
	_fail("DefenseResult %sを受信できませんでした。" % expected_result)
	return {}


func _fail(message: String) -> void:
	if _second_socket != null:
		_second_socket.close()
	push_error(message)
	print("AHOGE LEGEND short state smoke: FAIL")
	quit(1)
