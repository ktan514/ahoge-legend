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
var _p1_clashes: Array[Dictionary] = []
var _p2_clashes: Array[Dictionary] = []


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

	# JUST_PARRY → 攻撃側STAGGER。
	var p1_just_start := _p1_states.size()
	var p2_just_start := _p2_states.size()

	var press: Dictionary = await online_session.send_combat_input(
		CombatInputProtocolScript.ACTION_ATTACK_PRESS
	)
	if not bool(press.get("ok", false)):
		_fail("Just検証用P1 ATTACK_PRESSを送信できませんでした。")
		return
	if not await _wait_for_state(_p1_states, p1_user_id, "CHARGING", p1_just_start, 5000):
		_fail("Just検証用P1 CHARGINGを受信できませんでした。")
		return

	await create_timer(0.65).timeout
	var release: Dictionary = await online_session.send_combat_input(
		CombatInputProtocolScript.ACTION_ATTACK_RELEASE
	)
	if not bool(release.get("ok", false)):
		_fail("Just検証用P1 ATTACK_RELEASEを送信できませんでした。")
		return
	var just_sequence := int(release.get("input_sequence", 0))
	if not await _wait_for_state(_p1_states, p1_user_id, "STRIKE", p1_just_start, 5000):
		_fail("Just検証用P1 STRIKEを受信できませんでした。")
		return

	if not await _send_second_input(CombatInputProtocolScript.ACTION_DEFEND):
		return

	var defense_p1 := await _wait_for_defense_result(
		_p1_defense_results,
		just_sequence,
		"JUST_PARRY",
		5000
	)
	var defense_p2 := await _wait_for_defense_result(
		_p2_defense_results,
		just_sequence,
		"JUST_PARRY",
		5000
	)
	if defense_p1.is_empty() or defense_p2.is_empty():
		return

	var stagger_p1 := await _wait_for_state_event(
		_p1_states,
		p1_user_id,
		"STAGGER",
		p1_just_start,
		5000
	)
	var stagger_p2 := await _wait_for_state_event(
		_p2_states,
		p1_user_id,
		"STAGGER",
		p2_just_start,
		5000
	)
	if not _assert_same_stagger(stagger_p1, stagger_p2, "Just Defense"):
		return

	var stagger_index := _index_of_state(_p1_states, p1_user_id, "STAGGER", p1_just_start)
	if stagger_index < 0:
		_fail("P1 STAGGER indexを取得できませんでした。")
		return

	# Stagger中DEFENDを送ってもPARRY / DODGEへ遷移しない。
	var defend_during_stagger: Dictionary = await online_session.send_combat_input(
		CombatInputProtocolScript.ACTION_DEFEND
	)
	if not bool(defend_during_stagger.get("ok", false)):
		_fail("Stagger中DEFENDを送信できませんでした。")
		return
	await create_timer(0.15).timeout
	if _has_state_from(_p1_states, p1_user_id, "PARRY", stagger_index + 1) 			or _has_state_from(_p1_states, p1_user_id, "DODGE", stagger_index + 1):
		_fail("Stagger中DEFENDでDefense状態へ遷移しました。")
		return

	if not await _wait_for_state(
		_p1_states,
		p1_user_id,
		"IDLE",
		stagger_index + 1,
		5000
	):
		_fail("Just Defense Stagger終了後にP1がIDLEへ復帰しませんでした。")
		return

	if not await _wait_for_state(
		_p2_states,
		p2_user_id,
		"IDLE",
		p2_just_start,
		5000
	):
		_fail("Just Defense検証後にP2がIDLEへ復帰しませんでした。")
		return

	# AttackClash → 両者STAGGER。
	var p1_clash_start := _p1_states.size()
	var p2_clash_start := _p2_states.size()
	var p1_clash_event_start := _p1_clashes.size()
	var p2_clash_event_start := _p2_clashes.size()

	var p1_press: Dictionary = await online_session.send_combat_input(
		CombatInputProtocolScript.ACTION_ATTACK_PRESS
	)
	if not bool(p1_press.get("ok", false)):
		_fail("Clash用P1 ATTACK_PRESSを送信できませんでした。")
		return
	if not await _send_second_input(CombatInputProtocolScript.ACTION_ATTACK_PRESS):
		return

	if not await _wait_for_state(_p1_states, p1_user_id, "CHARGING", p1_clash_start, 5000):
		_fail("Clash用P1 CHARGINGを受信できませんでした。")
		return
	if not await _wait_for_state(_p2_states, p2_user_id, "CHARGING", p2_clash_start, 5000):
		_fail("Clash用P2 CHARGINGを受信できませんでした。")
		return

	var p1_release: Dictionary = await online_session.send_combat_input(
		CombatInputProtocolScript.ACTION_ATTACK_RELEASE
	)
	if not bool(p1_release.get("ok", false)):
		_fail("Clash用P1 ATTACK_RELEASEを送信できませんでした。")
		return
	if not await _send_second_input(CombatInputProtocolScript.ACTION_ATTACK_RELEASE):
		return

	var clash_p1 := await _wait_for_any_clash(_p1_clashes, p1_clash_event_start, 5000)
	var clash_p2 := await _wait_for_any_clash(_p2_clashes, p2_clash_event_start, 5000)
	if clash_p1.is_empty() or clash_p2.is_empty():
		return
	if clash_p1 != clash_p2:
		_fail("P1/P2でAttackClashイベントが一致しません。")
		return

	var p1_stagger_client1 := await _wait_for_state_event(
		_p1_states,
		p1_user_id,
		"STAGGER",
		p1_clash_start,
		5000
	)
	var p1_stagger_client2 := await _wait_for_state_event(
		_p2_states,
		p1_user_id,
		"STAGGER",
		p2_clash_start,
		5000
	)
	if not _assert_same_stagger(p1_stagger_client1, p1_stagger_client2, "Clash P1"):
		return

	var p2_stagger_client1 := await _wait_for_state_event(
		_p1_states,
		p2_user_id,
		"STAGGER",
		p1_clash_start,
		5000
	)
	var p2_stagger_client2 := await _wait_for_state_event(
		_p2_states,
		p2_user_id,
		"STAGGER",
		p2_clash_start,
		5000
	)
	if not _assert_same_stagger(p2_stagger_client1, p2_stagger_client2, "Clash P2"):
		return

	var p1_stagger_index := _index_of_state(_p1_states, p1_user_id, "STAGGER", p1_clash_start)
	var p2_stagger_index := _index_of_state(_p1_states, p2_user_id, "STAGGER", p1_clash_start)
	if not await _wait_for_state(_p1_states, p1_user_id, "IDLE", p1_stagger_index + 1, 5000):
		_fail("Clash Stagger終了後にP1がIDLEへ復帰しませんでした。")
		return
	if not await _wait_for_state(_p1_states, p2_user_id, "IDLE", p2_stagger_index + 1, 5000):
		_fail("Clash Stagger終了後にP2がIDLEへ復帰しませんでした。")
		return

	await online_session.realtime_socket.leave_match_async(p1_joined[0])
	await _second_socket.leave_match_async(_second_match_id)
	online_session.disconnect_realtime_socket()
	_second_socket.close()

	print("AHOGE LEGEND stagger smoke: PASS match_id=%s" % p1_joined[0])
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
	_collect_match_state(
		match_state,
		_p1_states,
		_p1_defense_results,
		_p1_clashes
	)


func _on_second_match_state(match_state) -> void:
	if _second_match_id.is_empty() or str(match_state.match_id) != _second_match_id:
		return
	_collect_match_state(
		match_state,
		_p2_states,
		_p2_defense_results,
		_p2_clashes
	)


func _collect_match_state(
	match_state,
	state_events: Array[Dictionary],
	defense_events: Array[Dictionary],
	clash_events: Array[Dictionary]
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
		return
	if op_code == CombatInputProtocolScript.OPCODE_ATTACK_CLASH:
		var clash_event := CombatInputProtocolScript.parse_attack_clash_payload(
			str(match_state.data)
		)
		if not clash_event.is_empty():
			clash_events.append(clash_event)


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
	return not (await _wait_for_state_event(
		events,
		user_id,
		state_name,
		start_index,
		timeout_ms
	)).is_empty()


func _wait_for_state_event(
	events: Array[Dictionary],
	user_id: String,
	state_name: String,
	start_index: int,
	timeout_ms: int
) -> Dictionary:
	var deadline := Time.get_ticks_msec() + timeout_ms
	while Time.get_ticks_msec() < deadline:
		var index := _index_of_state(events, user_id, state_name, start_index)
		if index >= 0:
			return events[index]
		await create_timer(0.02).timeout
	return {}


func _index_of_state(
	events: Array[Dictionary],
	user_id: String,
	state_name: String,
	start_index: int
) -> int:
	for index in range(maxi(start_index, 0), events.size()):
		if str(events[index].get("user_id", "")) == user_id 				and str(events[index].get("state", "")) == state_name:
			return index
	return -1


func _has_state_from(
	events: Array[Dictionary],
	user_id: String,
	state_name: String,
	start_index: int
) -> bool:
	return _index_of_state(events, user_id, state_name, start_index) >= 0


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


func _wait_for_any_clash(
	events: Array[Dictionary],
	start_index: int,
	timeout_ms: int
) -> Dictionary:
	var deadline := Time.get_ticks_msec() + timeout_ms
	while Time.get_ticks_msec() < deadline:
		if events.size() > start_index:
			return events[start_index]
		await create_timer(0.02).timeout
	_fail("AttackClashを受信できませんでした。")
	return {}


func _assert_same_stagger(
	first: Dictionary,
	second: Dictionary,
	label: String
) -> bool:
	if first.is_empty() or second.is_empty():
		_fail("%sのSTAGGERを両clientで受信できませんでした。" % label)
		return false
	if first != second:
		_fail("%sのSTAGGER eventがP1/P2で一致しません。" % label)
		return false
	if int(first.get("stagger_until_tick", -1)) - int(first.get("server_tick", -1)) != 14:
		_fail("%sのStagger時間が14tickではありません。" % label)
		return false
	return true


func _fail(message: String) -> void:
	if _second_socket != null:
		_second_socket.close()
	push_error(message)
	print("AHOGE LEGEND stagger smoke: FAIL")
	quit(1)
