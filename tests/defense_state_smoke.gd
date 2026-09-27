extends SceneTree

const OnlineConfigScript := preload("res://src/config/online_config.gd")
const CombatInputProtocolScript := preload("res://src/online/combat_input_protocol.gd")

var _second_socket = null
var _second_ticket: String = ""
var _second_match_id: String = ""
var _second_failure: String = ""
var _p1_states: Array[Dictionary] = []
var _p2_states: Array[Dictionary] = []
var _p1_contacts: Array[Dictionary] = []
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

	# IDLE → PARRY → IDLE
	var start_index := _p1_states.size()
	var defend_idle: Dictionary = await online_session.send_combat_input(
		CombatInputProtocolScript.ACTION_DEFEND
	)
	if not bool(defend_idle.get("ok", false)):
		_fail("IDLEからDEFENDを送信できませんでした。")
		return
	if not await _wait_for_state(_p1_states, p1_user_id, "PARRY", start_index, 5000):
		_fail("P1がPARRYを受信できませんでした。")
		return
	if not await _wait_for_state(_p2_states, p1_user_id, "PARRY", 0, 5000):
		_fail("P2がP1のPARRYを受信できませんでした。")
		return
	if not await _wait_for_state(_p1_states, p1_user_id, "IDLE", start_index, 5000):
		_fail("PARRY終了後にIDLEへ復帰しませんでした。")
		return

	var parry_event := _first_state_from(_p1_states, p1_user_id, "PARRY", start_index)
	if parry_event.is_empty():
		_fail("PARRY詳細eventを取得できませんでした。")
		return
	if int(parry_event.get("defense_active_until_tick", -1)) - int(parry_event["server_tick"]) != 6:
		_fail("PARRY active tickが6ではありません。")
		return
	if int(parry_event.get("defense_just_until_tick", -1)) - int(parry_event["server_tick"]) != 3:
		_fail("Just受付tickが3ではありません。")
		return

	# CHARGING中DEFENDで攻撃キャンセル
	start_index = _p1_states.size()
	var press: Dictionary = await online_session.send_combat_input(
		CombatInputProtocolScript.ACTION_ATTACK_PRESS
	)
	if not bool(press.get("ok", false)):
		_fail("ATTACK_PRESSを送信できませんでした。")
		return
	if not await _wait_for_state(_p1_states, p1_user_id, "CHARGING", start_index, 5000):
		_fail("CHARGINGを受信できませんでした。")
		return
	var contact_count_before := _count_contacts(_p1_contacts, p1_user_id)
	var defend_charge: Dictionary = await online_session.send_combat_input(
		CombatInputProtocolScript.ACTION_DEFEND
	)
	if not bool(defend_charge.get("ok", false)):
		_fail("CHARGING中DEFENDを送信できませんでした。")
		return
	if not await _wait_for_state(_p1_states, p1_user_id, "PARRY", start_index, 5000):
		_fail("CHARGINGからPARRYへ遷移しませんでした。")
		return
	if not await _wait_for_state(_p1_states, p1_user_id, "IDLE", start_index, 5000):
		_fail("CHARGING cancel後にIDLEへ復帰しませんでした。")
		return
	await create_timer(0.4).timeout
	if _count_contacts(_p1_contacts, p1_user_id) != contact_count_before:
		_fail("CHARGING cancel後にContactEventが発生しました。")
		return

	# WINDUP中DEFENDで予定攻撃をキャンセル
	start_index = _p1_states.size()
	await online_session.send_combat_input(CombatInputProtocolScript.ACTION_ATTACK_PRESS)
	if not await _wait_for_state(_p1_states, p1_user_id, "CHARGING", start_index, 5000):
		_fail("WINDUP検証用CHARGINGを受信できませんでした。")
		return
	var release: Dictionary = await online_session.send_combat_input(
		CombatInputProtocolScript.ACTION_ATTACK_RELEASE
	)
	if not bool(release.get("ok", false)):
		_fail("WINDUP検証用ATTACK_RELEASEを送信できませんでした。")
		return
	var release_sequence := int(release.get("input_sequence", 0))
	if not await _wait_for_state(_p1_states, p1_user_id, "WINDUP", start_index, 5000):
		_fail("WINDUPを受信できませんでした。")
		return
	var defend_windup: Dictionary = await online_session.send_combat_input(
		CombatInputProtocolScript.ACTION_DEFEND
	)
	if not bool(defend_windup.get("ok", false)):
		_fail("WINDUP中DEFENDを送信できませんでした。")
		return
	if not await _wait_for_state(_p1_states, p1_user_id, "PARRY", start_index, 5000):
		_fail("WINDUPからPARRYへ遷移しませんでした。")
		return
	if not await _wait_for_state(_p1_states, p1_user_id, "IDLE", start_index, 5000):
		_fail("WINDUP cancel後にIDLEへ復帰しませんでした。")
		return
	await create_timer(0.2).timeout
	if _has_contact(_p1_contacts, p1_user_id, release_sequence):
		_fail("WINDUP cancel後にContactEventが発生しました。")
		return

	# STRIKE中DEFENDで未到達Contactをキャンセル
	start_index = _p1_states.size()
	await online_session.send_combat_input(CombatInputProtocolScript.ACTION_ATTACK_PRESS)
	if not await _wait_for_state(_p1_states, p1_user_id, "CHARGING", start_index, 5000):
		_fail("STRIKE検証用CHARGINGを受信できませんでした。")
		return
	release = await online_session.send_combat_input(
		CombatInputProtocolScript.ACTION_ATTACK_RELEASE
	)
	release_sequence = int(release.get("input_sequence", 0))
	if not await _wait_for_state(_p1_states, p1_user_id, "STRIKE", start_index, 5000):
		_fail("STRIKEを受信できませんでした。")
		return
	var defend_strike: Dictionary = await online_session.send_combat_input(
		CombatInputProtocolScript.ACTION_DEFEND
	)
	if not bool(defend_strike.get("ok", false)):
		_fail("STRIKE中DEFENDを送信できませんでした。")
		return
	if not await _wait_for_state(_p1_states, p1_user_id, "PARRY", start_index, 5000):
		_fail("STRIKEからPARRYへ遷移しませんでした。")
		return
	if not await _wait_for_state(_p1_states, p1_user_id, "IDLE", start_index, 5000):
		_fail("STRIKE cancel後にIDLEへ復帰しませんでした。")
		return
	await create_timer(0.2).timeout
	if _has_contact(_p1_contacts, p1_user_id, release_sequence):
		_fail("STRIKE cancel後に未到達ContactEventが発生しました。")
		return

	# COOLDOWN中DEFENDはPARRY後に残りCOOLDOWNへ復帰
	start_index = _p1_states.size()
	await online_session.send_combat_input(CombatInputProtocolScript.ACTION_ATTACK_PRESS)
	if not await _wait_for_state(_p1_states, p1_user_id, "CHARGING", start_index, 5000):
		_fail("COOLDOWN検証用CHARGINGを受信できませんでした。")
		return
	await online_session.send_combat_input(CombatInputProtocolScript.ACTION_ATTACK_RELEASE)
	if not await _wait_for_state(_p1_states, p1_user_id, "COOLDOWN", start_index, 5000):
		_fail("COOLDOWNを受信できませんでした。")
		return
	var cooldown_index := _index_of_state(_p1_states, p1_user_id, "COOLDOWN", start_index)
	var defend_cooldown: Dictionary = await online_session.send_combat_input(
		CombatInputProtocolScript.ACTION_DEFEND
	)
	if not bool(defend_cooldown.get("ok", false)):
		_fail("COOLDOWN中DEFENDを送信できませんでした。")
		return
	if not await _wait_for_state(_p1_states, p1_user_id, "PARRY", cooldown_index + 1, 5000):
		_fail("COOLDOWNからPARRYへ遷移しませんでした。")
		return
	var parry_index := _index_of_state(_p1_states, p1_user_id, "PARRY", cooldown_index + 1)
	if not await _wait_for_state(_p1_states, p1_user_id, "COOLDOWN", parry_index + 1, 5000):
		_fail("PARRY終了後に残りCOOLDOWNへ復帰しませんでした。")
		return
	var resumed_index := _index_of_state(_p1_states, p1_user_id, "COOLDOWN", parry_index + 1)
	if not await _wait_for_state(_p1_states, p1_user_id, "IDLE", resumed_index + 1, 5000):
		_fail("再開COOLDOWN終了後にIDLEへ復帰しませんでした。")
		return

	if not _same_states_for_user(_p1_states, _p2_states, p1_user_id):
		_fail("P1/P2でDefense state列が一致しません。")
		return

	await online_session.realtime_socket.leave_match_async(p1_joined[0])
	await _second_socket.leave_match_async(_second_match_id)
	online_session.disconnect_realtime_socket()
	_second_socket.close()

	print("AHOGE LEGEND defense state smoke: PASS match_id=%s" % p1_joined[0])
	quit(0)


func _on_first_match_state(match_state) -> void:
	_collect_match_state(match_state, _p1_states, _p1_contacts)


func _on_second_match_state(match_state) -> void:
	if _second_match_id.is_empty() or str(match_state.match_id) != _second_match_id:
		return
	_collect_match_state(match_state, _p2_states, _p2_contacts)


func _collect_match_state(
	match_state,
	state_events: Array[Dictionary],
	contact_events: Array[Dictionary]
) -> void:
	var op_code := int(match_state.op_code)
	if op_code == CombatInputProtocolScript.OPCODE_COMBAT_STATE_CHANGED:
		var state_event := CombatInputProtocolScript.parse_combat_state_changed_payload(
			str(match_state.data)
		)
		if not state_event.is_empty():
			state_events.append(state_event)
		return
	if op_code == CombatInputProtocolScript.OPCODE_CONTACT_REACHED:
		var contact_event := CombatInputProtocolScript.parse_contact_reached_payload(
			str(match_state.data)
		)
		if not contact_event.is_empty():
			contact_events.append(contact_event)


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
		if _index_of_state(events, user_id, state, start_index) >= 0:
			return true
		await create_timer(0.02).timeout
	return false


func _wait_until_idle(
	events: Array[Dictionary],
	user_id: String,
	start_index: int,
	timeout_ms: int
) -> bool:
	return await _wait_for_state(events, user_id, "IDLE", start_index, timeout_ms)


func _index_of_state(
	events: Array[Dictionary],
	user_id: String,
	state: String,
	start_index: int
) -> int:
	for index in range(maxi(start_index, 0), events.size()):
		if str(events[index].get("user_id", "")) == user_id 				and str(events[index].get("state", "")) == state:
			return index
	return -1


func _first_state_from(
	events: Array[Dictionary],
	user_id: String,
	state: String,
	start_index: int
) -> Dictionary:
	var index := _index_of_state(events, user_id, state, start_index)
	return events[index] if index >= 0 else {}


func _count_contacts(events: Array[Dictionary], attacker_id: String) -> int:
	var count := 0
	for event in events:
		if str(event.get("attacker_id", "")) == attacker_id:
			count += 1
	return count


func _has_contact(
	events: Array[Dictionary],
	attacker_id: String,
	input_sequence: int
) -> bool:
	for event in events:
		if str(event.get("attacker_id", "")) == attacker_id 				and int(event.get("input_sequence", 0)) == input_sequence:
			return true
	return false


func _states_for_user(events: Array[Dictionary], user_id: String) -> Array[String]:
	var states: Array[String] = []
	for event in events:
		if str(event.get("user_id", "")) == user_id:
			states.append(str(event.get("state", "")))
	return states


func _same_states_for_user(
	first: Array[Dictionary],
	second: Array[Dictionary],
	user_id: String
) -> bool:
	return _states_for_user(first, user_id) == _states_for_user(second, user_id)


func _fail(message: String) -> void:
	if _second_socket != null:
		_second_socket.close()
	push_error(message)
	print("AHOGE LEGEND defense state smoke: FAIL")
	quit(1)
