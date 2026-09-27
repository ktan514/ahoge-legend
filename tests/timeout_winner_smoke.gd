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
var _p1_counts: Array[Dictionary] = []
var _p2_counts: Array[Dictionary] = []
var _p1_timers: Array[Dictionary] = []
var _p2_timers: Array[Dictionary] = []
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
	var round_one_start_tick := [-1]
	online_session.round_started.connect(
		func(round_number: int, _round_wins: Dictionary, server_tick: int) -> void:
			if round_number == 1:
				round_one_start_tick[0] = server_tick
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

	# authoritative GO / ROUND_STARTEDを基準に85秒計測を開始する。
	var round_start_deadline := Time.get_ticks_msec() + 7000
	while Time.get_ticks_msec() < round_start_deadline and round_one_start_tick[0] < 0:
		await create_timer(0.02).timeout
	if round_one_start_tick[0] < 0:
		_fail("Round 1のauthoritative開始を受信できませんでした。")
		return

	var start_timer := await _wait_timer_pair_at_tick(85, round_one_start_tick[0], 5000)
	if start_timer.is_empty():
		_fail("GOと同tickのRound timer 85を受信できませんでした。")
		return

	# timeout前にP1だけ1 Hitを確定し、1-0を作る。
	var attack_start_p1 := _p1_states.size()
	var attack_start_p2 := _p2_states.size()
	var press: Dictionary = await online_session.send_combat_input(
		CombatInputProtocolScript.ACTION_ATTACK_PRESS
	)
	if not bool(press.get("ok", false)):
		_fail("P1 ATTACK_PRESSを送信できませんでした。")
		return
	if not await _wait_state_pair(
		p1_user_id,
		"CHARGING",
		attack_start_p1,
		attack_start_p2,
		5000
	):
		_fail("P1 CHARGINGを確認できませんでした。")
		return

	var release: Dictionary = await online_session.send_combat_input(
		CombatInputProtocolScript.ACTION_ATTACK_RELEASE
	)
	if not bool(release.get("ok", false)):
		_fail("P1 ATTACK_RELEASEを送信できませんでした。")
		return
	var attack_sequence := int(release.get("input_sequence", 0))
	if not await _wait_state_pair(
		p1_user_id,
		"STRIKE",
		attack_start_p1,
		attack_start_p2,
		5000
	):
		_fail("P1 STRIKEを確認できませんでした。")
		return
	if not await _wait_hit_pair(p1_user_id, attack_sequence, 5000):
		return
	if not await _wait_count_pair(p1_user_id, 1, attack_sequence, 5000):
		_fail("timeout前P1 Hit count=1を受信できませんでした。")
		return
	if not await _wait_state_pair(
		p1_user_id,
		"IDLE",
		attack_start_p1,
		attack_start_p2,
		5000
	):
		_fail("timeout待機前にP1がIDLEへ復帰しませんでした。")
		return

	var lock_start_p1 := _p1_states.size()
	var lock_start_p2 := _p2_states.size()
	var zero_timer := await _wait_timer_pair(0, 95000)
	if zero_timer.is_empty():
		_fail("Round timerが0へ到達しませんでした。")
		return
	if int(zero_timer["server_tick"]) - int(start_timer["server_tick"]) != 2550:
		_fail("85→0が2550 server tickではありません。")
		return

	if not await _wait_state_pair(
		p1_user_id,
		"ROUND_LOCKED",
		lock_start_p1,
		lock_start_p2,
		5000
	):
		_fail("timeout勝者確定後にP1がROUND_LOCKEDへ遷移しませんでした。")
		return
	if not await _wait_state_pair(
		p2_user_id,
		"ROUND_LOCKED",
		lock_start_p1,
		lock_start_p2,
		5000
	):
		_fail("timeout勝者確定後にP2がROUND_LOCKEDへ遷移しませんでした。")
		return

	var round_result := await _wait_round_result_pair(
		"TIMEOUT",
		p1_user_id,
		p2_user_id,
		1,
		0,
		int(zero_timer.get("server_tick", -1)),
		5000
	)
	if round_result.is_empty():
		return

	# BO3ではtimeout勝利の次server tickから次Roundへresetする。
	# このsmokeはtimeout終了tickのROUND_LOCKED / TIMEOUT Resultまでを検証する。

	await online_session.realtime_socket.leave_match_async(p1_joined[0])
	await _second_socket.leave_match_async(_second_match_id)
	online_session.disconnect_realtime_socket()
	_second_socket.close()

	print("AHOGE LEGEND timeout winner smoke: PASS match_id=%s" % p1_joined[0])
	quit(0)


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
	_collect(match_state, _p1_states, _p1_hits, _p1_counts, _p1_timers, _p1_results)


func _on_second_match_state(match_state) -> void:
	if _second_match_id.is_empty() or str(match_state.match_id) != _second_match_id:
		return
	_collect(match_state, _p2_states, _p2_hits, _p2_counts, _p2_timers, _p2_results)


func _collect(
	match_state,
	states: Array[Dictionary],
	hits: Array[Dictionary],
	counts: Array[Dictionary],
	timers: Array[Dictionary],
	results: Array[Dictionary]
) -> void:
	var op_code := int(match_state.op_code)
	if op_code == CombatInputProtocolScript.OPCODE_COMBAT_STATE_CHANGED:
		var state_event := CombatInputProtocolScript.parse_combat_state_changed_payload(
			str(match_state.data)
		)
		if not state_event.is_empty():
			states.append(state_event)
		return
	if op_code == CombatInputProtocolScript.OPCODE_HIT_CONFIRMED:
		var hit_event := CombatInputProtocolScript.parse_hit_confirmed_payload(str(match_state.data))
		if not hit_event.is_empty():
			hits.append(hit_event)
		return
	if op_code == CombatInputProtocolScript.OPCODE_ROUND_HIT_COUNT_CHANGED:
		var count_event := CombatInputProtocolScript.parse_round_hit_count_changed_payload(
			str(match_state.data)
		)
		if not count_event.is_empty():
			counts.append(count_event)
		return
	if op_code == CombatInputProtocolScript.OPCODE_ROUND_TIMER_CHANGED:
		var timer_event := CombatInputProtocolScript.parse_round_timer_changed_payload(
			str(match_state.data)
		)
		if not timer_event.is_empty():
			timers.append(timer_event)
		return
	if op_code == CombatInputProtocolScript.OPCODE_ROUND_RESULT:
		var result_event := CombatInputProtocolScript.parse_round_result_payload(
			str(match_state.data)
		)
		if not result_event.is_empty():
			results.append(result_event)


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


func _wait_state_pair(
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
			if first != second:
				_fail("P1/P2で%s stateが一致しません。" % state_name)
				return false
			return true
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
		if str(event.get("user_id", "")) == user_id \
				and str(event.get("state", "")) == state_name:
			return event
	return {}


func _wait_hit_pair(attacker_id: String, input_sequence: int, timeout_ms: int) -> bool:
	var deadline := Time.get_ticks_msec() + timeout_ms
	while Time.get_ticks_msec() < deadline:
		var first := _find_hit(_p1_hits, attacker_id, input_sequence)
		var second := _find_hit(_p2_hits, attacker_id, input_sequence)
		if not first.is_empty() and not second.is_empty():
			if first != second:
				_fail("P1/P2でHitConfirmedが一致しません。")
				return false
			return true
		await create_timer(0.02).timeout
	_fail("HitConfirmedを両clientで受信できませんでした。")
	return false


func _find_hit(
	events: Array[Dictionary],
	attacker_id: String,
	input_sequence: int
) -> Dictionary:
	for event in events:
		if str(event.get("attacker_id", "")) == attacker_id \
				and int(event.get("input_sequence", -1)) == input_sequence:
			return event
	return {}


func _wait_count_pair(
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
				_fail("P1/P2でHit countが一致しません。")
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
		if str(event.get("user_id", "")) == user_id \
				and int(event.get("hit_count", -1)) == hit_count \
				and int(event.get("input_sequence", -1)) == input_sequence:
			return event
	return {}


func _wait_timer_pair_at_tick(
	remaining_seconds: int,
	server_tick: int,
	timeout_ms: int
) -> Dictionary:
	var deadline := Time.get_ticks_msec() + timeout_ms
	while Time.get_ticks_msec() < deadline:
		var first := _find_timer_at_tick(_p1_timers, remaining_seconds, server_tick)
		var second := _find_timer_at_tick(_p2_timers, remaining_seconds, server_tick)
		if not first.is_empty() and not second.is_empty():
			if first != second:
				_fail("P1/P2でRound timer payloadが一致しません。")
				return {}
			return first
		await create_timer(0.02).timeout
	return {}


func _find_timer_at_tick(
	events: Array[Dictionary],
	remaining_seconds: int,
	server_tick: int
) -> Dictionary:
	for event in events:
		if int(event.get("remaining_seconds", -1)) == remaining_seconds \
				and int(event.get("server_tick", -1)) == server_tick:
			return event
	return {}


func _wait_timer_pair(remaining_seconds: int, timeout_ms: int) -> Dictionary:
	var deadline := Time.get_ticks_msec() + timeout_ms
	while Time.get_ticks_msec() < deadline:
		var first := _find_timer(_p1_timers, remaining_seconds)
		var second := _find_timer(_p2_timers, remaining_seconds)
		if not first.is_empty() and not second.is_empty():
			if first != second:
				_fail("P1/P2でtimer eventが一致しません。")
				return {}
			return first
		await create_timer(0.02).timeout
	return {}


func _find_timer(events: Array[Dictionary], remaining_seconds: int) -> Dictionary:
	for event in events:
		if int(event.get("remaining_seconds", -1)) == remaining_seconds:
			return event
	return {}


func _wait_round_result_pair(
	expected_cause: String,
	winner_user_id: String,
	loser_user_id: String,
	winner_hits: int,
	loser_hits: int,
	expected_server_tick: int,
	timeout_ms: int
) -> Dictionary:
	var deadline := Time.get_ticks_msec() + timeout_ms
	while Time.get_ticks_msec() < deadline:
		if not _p1_results.is_empty() and not _p2_results.is_empty():
			var first := _p1_results[0]
			var second := _p2_results[0]
			if first != second:
				_fail("P1/P2でRound Result payloadが一致しません。")
				return {}
			if int(first.get("round_number", -1)) != 1 \
					or str(first.get("winner_user_id", "")) != winner_user_id \
					or str(first.get("loser_user_id", "")) != loser_user_id \
					or str(first.get("finish_cause", "")) != expected_cause \
					or int(first.get("winner_hits", -1)) != winner_hits \
					or int(first.get("loser_hits", -1)) != loser_hits \
					or int(first.get("server_tick", -1)) != expected_server_tick:
				_fail("Round Result内容が期待値と一致しません。")
				return {}
			if _p1_results.size() != 1 or _p2_results.size() != 1:
				_fail("Round Resultが1回だけではありません。")
				return {}
			return first
		await create_timer(0.02).timeout
	_fail("Round Resultを両clientで受信できませんでした。")
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
	print("AHOGE LEGEND timeout winner smoke: FAIL")
	quit(1)
