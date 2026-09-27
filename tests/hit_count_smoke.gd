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
var _p1_hits: Array[Dictionary] = []
var _p2_hits: Array[Dictionary] = []
var _p1_defense: Array[Dictionary] = []
var _p2_defense: Array[Dictionary] = []
var _p1_clashes: Array[Dictionary] = []
var _p2_clashes: Array[Dictionary] = []
var _p1_counts: Array[Dictionary] = []
var _p2_counts: Array[Dictionary] = []


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

	if not await _wait_for_count_pair(p1_user_id, 0, 0, 5000):
		_fail("P1初期Hit数0を両clientで受信できませんでした。")
		return
	if not await _wait_for_count_pair(p2_user_id, 0, 0, 5000):
		_fail("P2初期Hit数0を両clientで受信できませんでした。")
		return

	# P1 1Hit。
	var p1_first_state_start_p1 := _p1_states.size()
	var p1_first_state_start_p2 := _p2_states.size()
	var p1_first_sequence := await _p1_attack(online_session, p1_user_id)
	if p1_first_sequence <= 0:
		return
	if not await _wait_for_hit_pair(p1_user_id, p1_first_sequence, 5000):
		return
	if not await _wait_for_count_pair(p1_user_id, 1, p1_first_sequence, 5000):
		_fail("P1 1Hit目のcount=1を受信できませんでした。")
		return
	if not await _wait_for_state_pair(
		p1_user_id,
		"IDLE",
		p1_first_state_start_p1,
		p1_first_state_start_p2,
		5000
	):
		_fail("P1 1Hit後にIDLEへ復帰しませんでした。")
		return

	# PARRYではHit数を増やさない。
	var before_parry_count_events := _p1_counts.size()
	var parry_state_start_p1 := _p1_states.size()
	var parry_state_start_p2 := _p2_states.size()
	var parry_sequence := await _p1_attack(online_session, p1_user_id)
	if parry_sequence <= 0:
		return
	if not await _send_p2(CombatInputProtocolScript.ACTION_DEFEND):
		return
	if not await _wait_for_state_pair(
		p2_user_id,
		"PARRY",
		parry_state_start_p1,
		parry_state_start_p2,
		5000
	):
		_fail("PARRYへ遷移しませんでした。")
		return
	if not await _wait_for_defense_pair(parry_sequence, "PARRY", 5000):
		return
	await create_timer(0.25).timeout
	if _p1_counts.size() != before_parry_count_events or _p2_counts.size() != before_parry_count_events:
		_fail("PARRY成立時にHit数イベントが増えました。")
		return
	if not await _wait_for_state_pair(p1_user_id, "IDLE", parry_state_start_p1, parry_state_start_p2, 5000):
		_fail("PARRY検証後にP1がIDLEへ復帰しませんでした。")
		return
	if not await _wait_for_state_pair(p2_user_id, "IDLE", parry_state_start_p1, parry_state_start_p2, 5000):
		_fail("PARRY検証後にP2がIDLEへ復帰しませんでした。")
		return

	# ClashではHit数を増やさない。
	var before_clash_count_events := _p1_counts.size()
	var clash_state_start_p1 := _p1_states.size()
	var clash_state_start_p2 := _p2_states.size()
	var clash_start_p1 := _p1_clashes.size()
	var clash_start_p2 := _p2_clashes.size()

	var p1_press: Dictionary = await online_session.send_combat_input(
		CombatInputProtocolScript.ACTION_ATTACK_PRESS
	)
	if not bool(p1_press.get("ok", false)):
		_fail("Clash用P1 ATTACK_PRESSを送信できませんでした。")
		return
	if not await _send_p2(CombatInputProtocolScript.ACTION_ATTACK_PRESS):
		return
	if not await _wait_for_state_pair(p1_user_id, "CHARGING", clash_state_start_p1, clash_state_start_p2, 5000):
		_fail("Clash用P1 CHARGINGを確認できませんでした。")
		return
	if not await _wait_for_state_pair(p2_user_id, "CHARGING", clash_state_start_p1, clash_state_start_p2, 5000):
		_fail("Clash用P2 CHARGINGを確認できませんでした。")
		return

	var p1_release: Dictionary = await online_session.send_combat_input(
		CombatInputProtocolScript.ACTION_ATTACK_RELEASE
	)
	if not bool(p1_release.get("ok", false)):
		_fail("Clash用P1 ATTACK_RELEASEを送信できませんでした。")
		return
	if not await _send_p2(CombatInputProtocolScript.ACTION_ATTACK_RELEASE):
		return

	var clash_a := await _wait_new_event(_p1_clashes, clash_start_p1, 5000)
	var clash_b := await _wait_new_event(_p2_clashes, clash_start_p2, 5000)
	if clash_a.is_empty() or clash_b.is_empty() or clash_a != clash_b:
		_fail("AttackClashを両clientで同一受信できませんでした。")
		return
	await create_timer(0.25).timeout
	if _p1_counts.size() != before_clash_count_events or _p2_counts.size() != before_clash_count_events:
		_fail("AttackClashでHit数イベントが増えました。")
		return
	if not await _wait_for_state_pair(p1_user_id, "IDLE", clash_state_start_p1, clash_state_start_p2, 5000):
		_fail("Clash後にP1がIDLEへ復帰しませんでした。")
		return
	if not await _wait_for_state_pair(p2_user_id, "IDLE", clash_state_start_p1, clash_state_start_p2, 5000):
		_fail("Clash後にP2がIDLEへ復帰しませんでした。")
		return

	# P1 2Hit目。
	var p1_second_state_start_p1 := _p1_states.size()
	var p1_second_state_start_p2 := _p2_states.size()
	var p1_second_sequence := await _p1_attack(online_session, p1_user_id)
	if p1_second_sequence <= 0:
		return
	if not await _wait_for_hit_pair(p1_user_id, p1_second_sequence, 5000):
		return
	if not await _wait_for_count_pair(p1_user_id, 2, p1_second_sequence, 5000):
		_fail("P1 2Hit目のcount=2を受信できませんでした。")
		return
	if not await _wait_for_state_pair(
		p1_user_id,
		"IDLE",
		p1_second_state_start_p1,
		p1_second_state_start_p2,
		5000
	):
		_fail("P1 2Hit後にIDLEへ復帰しませんでした。")
		return

	# P2 1Hit。攻撃側だけ増える。
	var p2_sequence := await _p2_attack(p2_user_id)
	if p2_sequence <= 0:
		return
	if not await _wait_for_hit_pair(p2_user_id, p2_sequence, 5000):
		return
	if not await _wait_for_count_pair(p2_user_id, 1, p2_sequence, 5000):
		_fail("P2 1Hit目のcount=1を受信できませんでした。")
		return

	if _latest_count(_p1_counts, p1_user_id) != 2:
		_fail("最終P1 Hit数が2ではありません。")
		return
	if _latest_count(_p1_counts, p2_user_id) != 1:
		_fail("最終P2 Hit数が1ではありません。")
		return
	if _p1_counts != _p2_counts:
		_fail("P1/P2でRound Hit countイベント列が一致しません。")
		return

	await online_session.realtime_socket.leave_match_async(p1_joined[0])
	await _second_socket.leave_match_async(_second_match_id)
	online_session.disconnect_realtime_socket()
	_second_socket.close()

	print("AHOGE LEGEND hit count smoke: PASS match_id=%s" % p1_joined[0])
	quit(0)


func _p1_attack(online_session, user_id: String) -> int:
	var start_p1 := _p1_states.size()
	var start_p2 := _p2_states.size()
	var press: Dictionary = await online_session.send_combat_input(
		CombatInputProtocolScript.ACTION_ATTACK_PRESS
	)
	if not bool(press.get("ok", false)):
		_fail("P1 ATTACK_PRESSを送信できませんでした。")
		return -1
	if not await _wait_for_state_pair(user_id, "CHARGING", start_p1, start_p2, 5000):
		_fail("P1 CHARGINGを確認できませんでした。")
		return -1
	var release: Dictionary = await online_session.send_combat_input(
		CombatInputProtocolScript.ACTION_ATTACK_RELEASE
	)
	if not bool(release.get("ok", false)):
		_fail("P1 ATTACK_RELEASEを送信できませんでした。")
		return -1
	var sequence := int(release.get("input_sequence", 0))
	if not await _wait_for_state_pair(user_id, "STRIKE", start_p1, start_p2, 5000):
		_fail("P1 STRIKEを確認できませんでした。")
		return -1
	return sequence


func _p2_attack(user_id: String) -> int:
	var start_p1 := _p1_states.size()
	var start_p2 := _p2_states.size()
	if not await _send_p2(CombatInputProtocolScript.ACTION_ATTACK_PRESS):
		return -1
	if not await _wait_for_state_pair(user_id, "CHARGING", start_p1, start_p2, 5000):
		_fail("P2 CHARGINGを確認できませんでした。")
		return -1
	if not await _send_p2(CombatInputProtocolScript.ACTION_ATTACK_RELEASE):
		return -1
	var sequence := _second_sequence
	if not await _wait_for_state_pair(user_id, "STRIKE", start_p1, start_p2, 5000):
		_fail("P2 STRIKEを確認できませんでした。")
		return -1
	return sequence


func _send_p2(action: String) -> bool:
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
	_collect(match_state, _p1_states, _p1_hits, _p1_defense, _p1_clashes, _p1_counts)


func _on_second_match_state(match_state) -> void:
	if _second_match_id.is_empty() or str(match_state.match_id) != _second_match_id:
		return
	_collect(match_state, _p2_states, _p2_hits, _p2_defense, _p2_clashes, _p2_counts)


func _collect(
	match_state,
	states: Array[Dictionary],
	hits: Array[Dictionary],
	defense: Array[Dictionary],
	clashes: Array[Dictionary],
	counts: Array[Dictionary]
) -> void:
	var op_code := int(match_state.op_code)
	if op_code == CombatInputProtocolScript.OPCODE_COMBAT_STATE_CHANGED:
		var event := CombatInputProtocolScript.parse_combat_state_changed_payload(str(match_state.data))
		if not event.is_empty():
			states.append(event)
		return
	if op_code == CombatInputProtocolScript.OPCODE_HIT_CONFIRMED:
		var event := CombatInputProtocolScript.parse_hit_confirmed_payload(str(match_state.data))
		if not event.is_empty():
			hits.append(event)
		return
	if op_code == CombatInputProtocolScript.OPCODE_DEFENSE_RESOLVED:
		var event := CombatInputProtocolScript.parse_defense_resolved_payload(str(match_state.data))
		if not event.is_empty():
			defense.append(event)
		return
	if op_code == CombatInputProtocolScript.OPCODE_ATTACK_CLASH:
		var event := CombatInputProtocolScript.parse_attack_clash_payload(str(match_state.data))
		if not event.is_empty():
			clashes.append(event)
		return
	if op_code == CombatInputProtocolScript.OPCODE_ROUND_HIT_COUNT_CHANGED:
		var event := CombatInputProtocolScript.parse_round_hit_count_changed_payload(str(match_state.data))
		if not event.is_empty():
			counts.append(event)


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


func _wait_for_state_pair(
	user_id: String,
	state_name: String,
	start_p1: int,
	start_p2: int,
	timeout_ms: int
) -> bool:
	var deadline := Time.get_ticks_msec() + timeout_ms
	while Time.get_ticks_msec() < deadline:
		var first := _find_state(_p1_states, user_id, state_name, start_p1)
		var second := _find_state(_p2_states, user_id, state_name, start_p2)
		if not first.is_empty() and not second.is_empty():
			return first == second
		await create_timer(0.02).timeout
	return false


func _find_state(
	events: Array[Dictionary],
	user_id: String,
	state_name: String,
	start_index: int
) -> Dictionary:
	for index in range(maxi(start_index, 0), events.size()):
		var event := events[index]
		if str(event.get("user_id", "")) == user_id 				and str(event.get("state", "")) == state_name:
			return event
	return {}


func _wait_for_hit_pair(attacker_id: String, input_sequence: int, timeout_ms: int) -> bool:
	var first := await _wait_sequence(_p1_hits, attacker_id, input_sequence, timeout_ms)
	var second := await _wait_sequence(_p2_hits, attacker_id, input_sequence, timeout_ms)
	if first.is_empty() or second.is_empty() or first != second:
		_fail("HitConfirmedを両clientで同一受信できませんでした。")
		return false
	return true


func _wait_for_defense_pair(input_sequence: int, expected: String, timeout_ms: int) -> bool:
	var deadline := Time.get_ticks_msec() + timeout_ms
	while Time.get_ticks_msec() < deadline:
		var first := _find_defense(_p1_defense, input_sequence, expected)
		var second := _find_defense(_p2_defense, input_sequence, expected)
		if not first.is_empty() and not second.is_empty():
			if first != second:
				_fail("DefenseResultがP1/P2で一致しません。")
				return false
			return true
		await create_timer(0.02).timeout
	_fail("DefenseResult %sを受信できませんでした。" % expected)
	return false


func _find_defense(events: Array[Dictionary], input_sequence: int, expected: String) -> Dictionary:
	for event in events:
		if int(event.get("input_sequence", -1)) == input_sequence 				and str(event.get("result", "")) == expected:
			return event
	return {}


func _wait_for_count_pair(
	user_id: String,
	hit_count: int,
	input_sequence: int,
	timeout_ms: int
) -> bool:
	var deadline := Time.get_ticks_msec() + timeout_ms
	while Time.get_ticks_msec() < deadline:
		var first := _find_count(_p1_counts, user_id, hit_count, input_sequence)
		var second := _find_count(_p2_counts, user_id, hit_count, input_sequence)
		if not first.is_empty() and not second.is_empty():
			if first != second:
				_fail("Round Hit count payloadがP1/P2で一致しません。")
				return false
			return true
		await create_timer(0.02).timeout
	return false


func _find_count(
	events: Array[Dictionary],
	user_id: String,
	hit_count: int,
	input_sequence: int
) -> Dictionary:
	for event in events:
		if str(event.get("user_id", "")) == user_id 				and int(event.get("hit_count", -1)) == hit_count 				and int(event.get("input_sequence", -1)) == input_sequence:
			return event
	return {}


func _wait_sequence(
	events: Array[Dictionary],
	attacker_id: String,
	input_sequence: int,
	timeout_ms: int
) -> Dictionary:
	var deadline := Time.get_ticks_msec() + timeout_ms
	while Time.get_ticks_msec() < deadline:
		for event in events:
			if str(event.get("attacker_id", "")) == attacker_id \
					and int(event.get("input_sequence", -1)) == input_sequence:
				return event
		await create_timer(0.02).timeout
	return {}


func _wait_new_event(events: Array[Dictionary], start_index: int, timeout_ms: int) -> Dictionary:
	var deadline := Time.get_ticks_msec() + timeout_ms
	while Time.get_ticks_msec() < deadline:
		if events.size() > start_index:
			return events[start_index]
		await create_timer(0.02).timeout
	return {}


func _latest_count(events: Array[Dictionary], user_id: String) -> int:
	var latest := -1
	for event in events:
		if str(event.get("user_id", "")) == user_id:
			latest = int(event.get("hit_count", -1))
	return latest


func _fail(message: String) -> void:
	if _second_socket != null:
		_second_socket.close()
	push_error(message)
	print("AHOGE LEGEND hit count smoke: FAIL")
	quit(1)
