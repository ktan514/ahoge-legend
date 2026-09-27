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
var _p1_contacts: Array[Dictionary] = []
var _p2_contacts: Array[Dictionary] = []
var _p1_hits: Array[Dictionary] = []
var _p2_hits: Array[Dictionary] = []
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

	# DefenseなしContactはHIT。
	var hit_state_index := _p1_states.size()
	var hit_sequence := await _p1_attack(online_session, p1_user_id, 0.0)
	if hit_sequence <= 0:
		return
	var hit_p1 := await _wait_for_event(_p1_hits, "input_sequence", hit_sequence, 5000)
	var hit_p2 := await _wait_for_event(_p2_hits, "input_sequence", hit_sequence, 5000)
	if not _same_hit(hit_p1, hit_p2, p1_user_id, p2_user_id):
		return
	if not await _wait_for_state(_p1_states, p1_user_id, "IDLE", hit_state_index, 5000):
		_fail("HIT検証後にP1がIDLEへ復帰しませんでした。")
		return

	# Defense成功時はHITを出さない。
	var defense_p1_state_index := _p1_states.size()
	var defense_p2_state_index := _p2_states.size()
	var defended_sequence := await _p1_attack(online_session, p1_user_id, 0.65)
	if defended_sequence <= 0:
		return
	if not await _send_second_input(CombatInputProtocolScript.ACTION_DEFEND):
		return
	var defense_event := await _wait_for_event(
		_p1_defense_results,
		"input_sequence",
		defended_sequence,
		5000
	)
	if defense_event.is_empty() or str(defense_event.get("result", "")) == "NONE":
		_fail("Defense成功結果を受信できませんでした。")
		return
	await create_timer(0.35).timeout
	if _has_event(_p1_hits, "input_sequence", defended_sequence):
		_fail("Defense成立ContactでHITが発生しました。")
		return
	if not await _wait_for_state(_p1_states, p1_user_id, "IDLE", defense_p1_state_index, 5000):
		_fail("Defense検証後にP1がIDLEへ復帰しませんでした。")
		return
	if not await _wait_for_state(_p2_states, p2_user_id, "IDLE", defense_p2_state_index, 5000):
		_fail("Defense検証後にP2がIDLEへ復帰しませんでした。")
		return

	# 両者をほぼ同時に攻撃させ、許容3tick以内のContactをCLASHへする。
	var p1_start_index := _p1_states.size()
	var p2_start_index := _p2_states.size()
	var p1_press: Dictionary = await online_session.send_combat_input(
		CombatInputProtocolScript.ACTION_ATTACK_PRESS
	)
	if not bool(p1_press.get("ok", false)):
		_fail("Clash用P1 ATTACK_PRESSを送信できませんでした。")
		return
	if not await _send_second_input(CombatInputProtocolScript.ACTION_ATTACK_PRESS):
		return
	if not await _wait_for_state(_p1_states, p1_user_id, "CHARGING", p1_start_index, 5000):
		_fail("Clash用P1 CHARGINGを受信できませんでした。")
		return
	if not await _wait_for_state(_p2_states, p2_user_id, "CHARGING", p2_start_index, 5000):
		_fail("Clash用P2 CHARGINGを受信できませんでした。")
		return

	var p1_release: Dictionary = await online_session.send_combat_input(
		CombatInputProtocolScript.ACTION_ATTACK_RELEASE
	)
	if not bool(p1_release.get("ok", false)):
		_fail("Clash用P1 ATTACK_RELEASEを送信できませんでした。")
		return
	var p1_clash_sequence := int(p1_release.get("input_sequence", 0))
	if not await _send_second_input(CombatInputProtocolScript.ACTION_ATTACK_RELEASE):
		return
	var p2_clash_sequence := _second_sequence

	var clash_p1 := await _wait_for_clash(
		_p1_clashes,
		p1_user_id,
		p2_user_id,
		p1_clash_sequence,
		p2_clash_sequence,
		5000
	)
	var clash_p2 := await _wait_for_clash(
		_p2_clashes,
		p1_user_id,
		p2_user_id,
		p1_clash_sequence,
		p2_clash_sequence,
		5000
	)
	if clash_p1.is_empty() or clash_p2.is_empty():
		return
	if int(clash_p1.get("server_tick", -1)) != int(clash_p2.get("server_tick", -2)):
		_fail("P1/P2でAttackClash server tickが一致しません。")
		return
	var p1_contact := _event_for_sequence(_p1_contacts, p1_clash_sequence)
	var p2_contact := _event_for_sequence(_p1_contacts, p2_clash_sequence)
	if p1_contact.is_empty() or p2_contact.is_empty():
		_fail("Clash対象の両ContactEventを取得できませんでした。")
		return
	var later_contact_tick := maxi(
		int(p1_contact.get("server_tick", -1)),
		int(p2_contact.get("server_tick", -1))
	)
	if int(clash_p1.get("server_tick", -1)) < later_contact_tick:
		_fail("AttackClashが遅い側Contact到達前に確定しました。")
		return
	await create_timer(0.25).timeout
	if _has_event(_p1_hits, "input_sequence", p1_clash_sequence) 			or _has_event(_p1_hits, "input_sequence", p2_clash_sequence):
		_fail("AttackClashでHITが発生しました。")
		return

	await online_session.realtime_socket.leave_match_async(p1_joined[0])
	await _second_socket.leave_match_async(_second_match_id)
	online_session.disconnect_realtime_socket()
	_second_socket.close()
	print("AHOGE LEGEND contact outcome smoke: PASS match_id=%s" % p1_joined[0])
	quit(0)


func _p1_attack(online_session, p1_user_id: String, charge_seconds: float) -> int:
	var start_index := _p1_states.size()
	var press: Dictionary = await online_session.send_combat_input(
		CombatInputProtocolScript.ACTION_ATTACK_PRESS
	)
	if not bool(press.get("ok", false)):
		_fail("P1 ATTACK_PRESSを送信できませんでした。")
		return -1
	if not await _wait_for_state(_p1_states, p1_user_id, "CHARGING", start_index, 5000):
		_fail("P1 CHARGINGを受信できませんでした。")
		return -1
	if charge_seconds > 0.0:
		await create_timer(charge_seconds).timeout
	var release: Dictionary = await online_session.send_combat_input(
		CombatInputProtocolScript.ACTION_ATTACK_RELEASE
	)
	if not bool(release.get("ok", false)):
		_fail("P1 ATTACK_RELEASEを送信できませんでした。")
		return -1
	var sequence := int(release.get("input_sequence", 0))
	if not await _wait_for_state(_p1_states, p1_user_id, "STRIKE", start_index, 5000):
		_fail("P1 STRIKEを受信できませんでした。")
		return -1
	return sequence


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
	_collect_match_state(match_state, _p1_states, _p1_defense_results, _p1_contacts, _p1_hits, _p1_clashes)


func _on_second_match_state(match_state) -> void:
	if _second_match_id.is_empty() or str(match_state.match_id) != _second_match_id:
		return
	_collect_match_state(match_state, _p2_states, _p2_defense_results, _p2_contacts, _p2_hits, _p2_clashes)


func _collect_match_state(
	match_state,
	states: Array[Dictionary],
	defense_results: Array[Dictionary],
	contacts: Array[Dictionary],
	hits: Array[Dictionary],
	clashes: Array[Dictionary]
) -> void:
	var op_code := int(match_state.op_code)
	if op_code == CombatInputProtocolScript.OPCODE_COMBAT_STATE_CHANGED:
		var state_event := CombatInputProtocolScript.parse_combat_state_changed_payload(str(match_state.data))
		if not state_event.is_empty():
			states.append(state_event)
		return
	if op_code == CombatInputProtocolScript.OPCODE_CONTACT_REACHED:
		var contact_event := CombatInputProtocolScript.parse_contact_reached_payload(str(match_state.data))
		if not contact_event.is_empty():
			contacts.append(contact_event)
		return
	if op_code == CombatInputProtocolScript.OPCODE_DEFENSE_RESOLVED:
		var defense_event := CombatInputProtocolScript.parse_defense_resolved_payload(str(match_state.data))
		if not defense_event.is_empty():
			defense_results.append(defense_event)
		return
	if op_code == CombatInputProtocolScript.OPCODE_HIT_CONFIRMED:
		var hit_event := CombatInputProtocolScript.parse_hit_confirmed_payload(str(match_state.data))
		if not hit_event.is_empty():
			hits.append(hit_event)
		return
	if op_code == CombatInputProtocolScript.OPCODE_ATTACK_CLASH:
		var clash_event := CombatInputProtocolScript.parse_attack_clash_payload(str(match_state.data))
		if not clash_event.is_empty():
			clashes.append(clash_event)


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
	var deadline := Time.get_ticks_msec() + timeout_ms
	while Time.get_ticks_msec() < deadline:
		for index in range(maxi(start_index, 0), events.size()):
			if str(events[index].get("user_id", "")) == user_id 					and str(events[index].get("state", "")) == state_name:
				return true
		await create_timer(0.02).timeout
	return false


func _wait_for_event(
	events: Array[Dictionary],
	key: String,
	value: int,
	timeout_ms: int
) -> Dictionary:
	var deadline := Time.get_ticks_msec() + timeout_ms
	while Time.get_ticks_msec() < deadline:
		for event in events:
			if int(event.get(key, -1)) == value:
				return event
		await create_timer(0.02).timeout
	_fail("イベント待機がtimeoutしました。key=%s value=%d" % [key, value])
	return {}


func _wait_for_clash(
	events: Array[Dictionary],
	p1_id: String,
	p2_id: String,
	p1_sequence: int,
	p2_sequence: int,
	timeout_ms: int
) -> Dictionary:
	var deadline := Time.get_ticks_msec() + timeout_ms
	while Time.get_ticks_msec() < deadline:
		for event in events:
			var a_id := str(event.get("attacker_a_id", ""))
			var b_id := str(event.get("attacker_b_id", ""))
			var a_seq := int(event.get("attacker_a_input_sequence", 0))
			var b_seq := int(event.get("attacker_b_input_sequence", 0))
			if (
				a_id == p1_id and b_id == p2_id and a_seq == p1_sequence and b_seq == p2_sequence
			) or (
				a_id == p2_id and b_id == p1_id and a_seq == p2_sequence and b_seq == p1_sequence
			):
				return event
		await create_timer(0.02).timeout
	_fail("AttackClashを受信できませんでした。")
	return {}


func _event_for_sequence(events: Array[Dictionary], input_sequence: int) -> Dictionary:
	for event in events:
		if int(event.get("input_sequence", -1)) == input_sequence:
			return event
	return {}


func _has_event(events: Array[Dictionary], key: String, value: int) -> bool:
	for event in events:
		if int(event.get(key, -1)) == value:
			return true
	return false


func _same_hit(
	first: Dictionary,
	second: Dictionary,
	attacker_id: String,
	defender_id: String
) -> bool:
	if first.is_empty() or second.is_empty():
		return false
	if str(first.get("attacker_id", "")) != attacker_id 			or str(first.get("defender_id", "")) != defender_id:
		_fail("HITのattacker / defenderが不正です。")
		return false
	if first != second:
		_fail("P1/P2でHITイベントが一致しません。")
		return false
	return true


func _fail(message: String) -> void:
	if _second_socket != null:
		_second_socket.close()
	push_error(message)
	print("AHOGE LEGEND contact outcome smoke: FAIL")
	quit(1)
