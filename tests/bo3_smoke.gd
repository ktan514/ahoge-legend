extends SceneTree

const OnlineConfigScript := preload("res://src/config/online_config.gd")
const CombatInputProtocolScript := preload("res://src/online/combat_input_protocol.gd")

var _second_socket = null
var _second_ticket: String = ""
var _second_match_id: String = ""
var _second_failure: String = ""
var _second_sequence: int = 0
var _last_p1_release_sequence: int = 0
var _last_p2_release_sequence: int = 0

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
var _p1_scores: Array[Dictionary] = []
var _p2_scores: Array[Dictionary] = []
var _p1_started: Array[Dictionary] = []
var _p2_started: Array[Dictionary] = []


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

	var round_one := await _wait_round_started_pair(1, p1_user_id, 0, p2_user_id, 0, 5000)
	if round_one.is_empty():
		_fail("Round 1開始通知を受信できませんでした。")
		return
	if (await _wait_timer_pair_at_tick(85, int(round_one["server_tick"]), 5000)).is_empty():
		_fail("Round 1 timer 85を受信できませんでした。")
		return
	if not await _wait_zero_count_pair(p1_user_id, p2_user_id, int(round_one["server_tick"]), 5000):
		_fail("Round 1 Hit数0 snapshotを受信できませんでした。")
		return

	if not await _play_round(
		online_session,
		p1_user_id,
		p2_user_id,
		true,
		1,
		1,
		0,
		false
	):
		return

	var round_two := await _wait_round_started_pair(2, p1_user_id, 1, p2_user_id, 0, 5000)
	if round_two.is_empty():
		_fail("Round 2開始通知を受信できませんでした。")
		return
	if not await _assert_round_reset(round_two, p1_user_id, p2_user_id, 5000):
		return

	if not await _play_round(
		online_session,
		p1_user_id,
		p2_user_id,
		false,
		2,
		1,
		1,
		false
	):
		return

	var round_three := await _wait_round_started_pair(3, p1_user_id, 1, p2_user_id, 1, 5000)
	if round_three.is_empty():
		_fail("Round 3開始通知を受信できませんでした。")
		return
	if not await _assert_round_reset(round_three, p1_user_id, p2_user_id, 5000):
		return

	if not await _play_round(
		online_session,
		p1_user_id,
		p2_user_id,
		true,
		3,
		2,
		1,
		true
	):
		return

	if _p1_started.size() != 3 or _p2_started.size() != 3:
		_fail("BO3終了後にRound 4が開始されたか、Round Started回数が不正です。")
		return
	if _p1_results.size() != 3 or _p2_results.size() != 3:
		_fail("BO3のRound Result回数が3ではありません。")
		return
	if _p1_scores.size() != 3 or _p2_scores.size() != 3:
		_fail("BO3 score event回数が3ではありません。")
		return
	if _p1_started != _p2_started or _p1_results != _p2_results or _p1_scores != _p2_scores:
		_fail("P1/P2でBO3イベント列が一致しません。")
		return

	var state_count_p1 := _p1_states.size()
	var state_count_p2 := _p2_states.size()
	var hit_count := _p1_hits.size()
	var count_event_count := _p1_counts.size()
	var timer_count := _p1_timers.size()
	var started_count := _p1_started.size()

	var post_press: Dictionary = await online_session.send_combat_input(
		CombatInputProtocolScript.ACTION_ATTACK_PRESS
	)
	if not bool(post_press.get("ok", false)):
		_fail("Match終了後P1 ATTACK_PRESS送信に失敗しました。")
		return
	if not await _send_p2(CombatInputProtocolScript.ACTION_ATTACK_PRESS):
		return

	await create_timer(0.6).timeout

	if _p1_states.size() != state_count_p1 or _p2_states.size() != state_count_p2:
		_fail("Match終了後に新規combat stateが発生しました。")
		return
	if _p1_hits.size() != hit_count or _p2_hits.size() != hit_count:
		_fail("Match終了後に新規Hitが発生しました。")
		return
	if _p1_counts.size() != count_event_count or _p2_counts.size() != count_event_count:
		_fail("Match終了後にHit countが増加しました。")
		return
	if _p1_timers.size() != timer_count or _p2_timers.size() != timer_count:
		_fail("Match終了後にtimerが進みました。")
		return
	if _p1_started.size() != started_count or _p2_started.size() != started_count:
		_fail("Match終了後に新規Roundが開始しました。")
		return

	await online_session.realtime_socket.leave_match_async(p1_joined[0])
	await _second_socket.leave_match_async(_second_match_id)
	online_session.disconnect_realtime_socket()
	_second_socket.close()

	print("AHOGE LEGEND BO3 smoke: PASS match_id=%s" % p1_joined[0])
	quit(0)


func _play_round(
	online_session,
	p1_user_id: String,
	p2_user_id: String,
	p1_wins: bool,
	round_number: int,
	expected_p1_rounds: int,
	expected_p2_rounds: int,
	expected_match_finished: bool
) -> bool:
	var winner_id := p1_user_id if p1_wins else p2_user_id
	var loser_id := p2_user_id if p1_wins else p1_user_id

	for hit_index in range(1, 6):
		var state_start_p1 := _p1_states.size()
		var state_start_p2 := _p2_states.size()
		var sequence := -1
		if p1_wins:
			sequence = await _p1_attack(
				online_session,
				p1_user_id,
				state_start_p1,
				state_start_p2
			)
		else:
			sequence = await _p2_attack(
				p2_user_id,
				state_start_p1,
				state_start_p2
			)
		if sequence <= 0:
			return false

		if not await _wait_hit_pair(winner_id, sequence, 5000):
			return false
		if not await _wait_count_pair(winner_id, hit_index, sequence, 5000):
			_fail("Round %d / Hit %dのcountを受信できませんでした。" % [round_number, hit_index])
			return false

		if hit_index < 5:
			if not await _wait_state_pair(
				winner_id,
				"IDLE",
				state_start_p1,
				state_start_p2,
				5000
			):
				_fail("Round %d / Hit %d後にwinnerがIDLEへ復帰しませんでした。" % [round_number, hit_index])
				return false

	var result := await _wait_round_result_pair(
		round_number,
		winner_id,
		loser_id,
		"HIT_LIMIT",
		5,
		0,
		5000
	)
	if result.is_empty():
		return false

	var score := await _wait_score_pair(
		round_number,
		winner_id,
		p1_user_id,
		expected_p1_rounds,
		p2_user_id,
		expected_p2_rounds,
		expected_match_finished,
		5000
	)
	if score.is_empty():
		return false

	if int(score.get("server_tick", -1)) != int(result.get("server_tick", -2)):
		_fail("Round ResultとBO3 scoreのserver tickが一致しません。")
		return false

	return true


func _p1_attack(
	online_session,
	user_id: String,
	start_p1: int,
	start_p2: int
) -> int:
	var press: Dictionary = await online_session.send_combat_input(
		CombatInputProtocolScript.ACTION_ATTACK_PRESS
	)
	if not bool(press.get("ok", false)):
		_fail("P1 ATTACK_PRESSを送信できませんでした。")
		return -1
	if not await _wait_state_pair(user_id, "CHARGING", start_p1, start_p2, 5000):
		_fail("P1 CHARGINGを確認できませんでした。")
		return -1

	var release: Dictionary = await online_session.send_combat_input(
		CombatInputProtocolScript.ACTION_ATTACK_RELEASE
	)
	if not bool(release.get("ok", false)):
		_fail("P1 ATTACK_RELEASEを送信できませんでした。")
		return -1
	var sequence := int(release.get("input_sequence", 0))
	if sequence <= _last_p1_release_sequence:
		_fail("P1 input sequenceがRound間で単調増加していません。")
		return -1
	_last_p1_release_sequence = sequence
	if not await _wait_state_pair(user_id, "STRIKE", start_p1, start_p2, 5000):
		_fail("P1 STRIKEを確認できませんでした。")
		return -1
	return sequence


func _p2_attack(
	user_id: String,
	start_p1: int,
	start_p2: int
) -> int:
	if not await _send_p2(CombatInputProtocolScript.ACTION_ATTACK_PRESS):
		return -1
	if not await _wait_state_pair(user_id, "CHARGING", start_p1, start_p2, 5000):
		_fail("P2 CHARGINGを確認できませんでした。")
		return -1
	if not await _send_p2(CombatInputProtocolScript.ACTION_ATTACK_RELEASE):
		return -1
	var sequence := _second_sequence
	if sequence <= _last_p2_release_sequence:
		_fail("P2 input sequenceがRound間で単調増加していません。")
		return -1
	_last_p2_release_sequence = sequence
	if not await _wait_state_pair(user_id, "STRIKE", start_p1, start_p2, 5000):
		_fail("P2 STRIKEを確認できませんでした。")
		return -1
	return sequence


func _assert_round_reset(
	started: Dictionary,
	p1_user_id: String,
	p2_user_id: String,
	timeout_ms: int
) -> bool:
	var start_tick := int(started.get("server_tick", -1))
	if not await _wait_zero_count_pair(p1_user_id, p2_user_id, start_tick, timeout_ms):
		_fail("次RoundのHit数0 resetを確認できませんでした。")
		return false
	if (await _wait_timer_pair_at_tick(85, start_tick, timeout_ms)).is_empty():
		_fail("次Roundのtimer 85 resetを確認できませんでした。")
		return false
	if not await _wait_state_at_tick_pair(p1_user_id, "IDLE", start_tick, timeout_ms):
		_fail("次Round開始tickでP1がIDLEではありません。")
		return false
	if not await _wait_state_at_tick_pair(p2_user_id, "IDLE", start_tick, timeout_ms):
		_fail("次Round開始tickでP2がIDLEではありません。")
		return false
	return true


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
	_collect(match_state, _p1_states, _p1_hits, _p1_counts, _p1_timers, _p1_results, _p1_scores, _p1_started)


func _on_second_match_state(match_state) -> void:
	if _second_match_id.is_empty() or str(match_state.match_id) != _second_match_id:
		return
	_collect(match_state, _p2_states, _p2_hits, _p2_counts, _p2_timers, _p2_results, _p2_scores, _p2_started)


func _collect(
	match_state,
	states: Array[Dictionary],
	hits: Array[Dictionary],
	counts: Array[Dictionary],
	timers: Array[Dictionary],
	results: Array[Dictionary],
	scores: Array[Dictionary],
	started: Array[Dictionary]
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
	if op_code == CombatInputProtocolScript.OPCODE_ROUND_HIT_COUNT_CHANGED:
		var event := CombatInputProtocolScript.parse_round_hit_count_changed_payload(str(match_state.data))
		if not event.is_empty():
			counts.append(event)
		return
	if op_code == CombatInputProtocolScript.OPCODE_ROUND_TIMER_CHANGED:
		var event := CombatInputProtocolScript.parse_round_timer_changed_payload(str(match_state.data))
		if not event.is_empty():
			timers.append(event)
		return
	if op_code == CombatInputProtocolScript.OPCODE_ROUND_RESULT:
		var event := CombatInputProtocolScript.parse_round_result_payload(str(match_state.data))
		if not event.is_empty():
			results.append(event)
		return
	if op_code == CombatInputProtocolScript.OPCODE_BO3_SCORE_CHANGED:
		var event := CombatInputProtocolScript.parse_bo3_score_changed_payload(str(match_state.data))
		if not event.is_empty():
			scores.append(event)
		return
	if op_code == CombatInputProtocolScript.OPCODE_ROUND_STARTED:
		var event := CombatInputProtocolScript.parse_round_started_payload(str(match_state.data))
		if not event.is_empty():
			started.append(event)


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


func _wait_state_at_tick_pair(
	user_id: String,
	state_name: String,
	server_tick: int,
	timeout_ms: int
) -> bool:
	var deadline := Time.get_ticks_msec() + timeout_ms
	while Time.get_ticks_msec() < deadline:
		var first := _find_state_at_tick(_p1_states, user_id, state_name, server_tick)
		var second := _find_state_at_tick(_p2_states, user_id, state_name, server_tick)
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
		if str(event.get("user_id", "")) == user_id and str(event.get("state", "")) == state_name:
			return event
	return {}


func _find_state_at_tick(
	events: Array[Dictionary],
	user_id: String,
	state_name: String,
	server_tick: int
) -> Dictionary:
	for event in events:
		if str(event.get("user_id", "")) == user_id 				and str(event.get("state", "")) == state_name 				and int(event.get("server_tick", -1)) == server_tick:
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
		if str(event.get("attacker_id", "")) == attacker_id 				and int(event.get("input_sequence", -1)) == input_sequence:
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
		if str(event.get("user_id", "")) == user_id 				and int(event.get("hit_count", -1)) == hit_count 				and int(event.get("input_sequence", -1)) == input_sequence:
			return event
	return {}


func _wait_zero_count_pair(
	p1_user_id: String,
	p2_user_id: String,
	server_tick: int,
	timeout_ms: int
) -> bool:
	var deadline := Time.get_ticks_msec() + timeout_ms
	while Time.get_ticks_msec() < deadline:
		var a1 := _find_count_at_tick(_p1_counts, p1_user_id, 0, 0, server_tick)
		var a2 := _find_count_at_tick(_p1_counts, p2_user_id, 0, 0, server_tick)
		var b1 := _find_count_at_tick(_p2_counts, p1_user_id, 0, 0, server_tick)
		var b2 := _find_count_at_tick(_p2_counts, p2_user_id, 0, 0, server_tick)
		if not a1.is_empty() and not a2.is_empty() and a1 == b1 and a2 == b2:
			return true
		await create_timer(0.02).timeout
	return false


func _find_count_at_tick(
	events: Array[Dictionary],
	user_id: String,
	hit_count: int,
	input_sequence: int,
	server_tick: int
) -> Dictionary:
	for event in events:
		if str(event.get("user_id", "")) == user_id 				and int(event.get("hit_count", -1)) == hit_count 				and int(event.get("input_sequence", -1)) == input_sequence 				and int(event.get("server_tick", -1)) == server_tick:
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
				_fail("P1/P2でRound timerが一致しません。")
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
		if int(event.get("remaining_seconds", -1)) == remaining_seconds 				and int(event.get("server_tick", -1)) == server_tick:
			return event
	return {}


func _wait_round_result_pair(
	round_number: int,
	winner_user_id: String,
	loser_user_id: String,
	finish_cause: String,
	winner_hits: int,
	loser_hits: int,
	timeout_ms: int
) -> Dictionary:
	var deadline := Time.get_ticks_msec() + timeout_ms
	while Time.get_ticks_msec() < deadline:
		var first := _find_result(_p1_results, round_number)
		var second := _find_result(_p2_results, round_number)
		if not first.is_empty() and not second.is_empty():
			if first != second:
				_fail("P1/P2でRound Resultが一致しません。")
				return {}
			if str(first.get("winner_user_id", "")) != winner_user_id 					or str(first.get("loser_user_id", "")) != loser_user_id 					or str(first.get("finish_cause", "")) != finish_cause 					or int(first.get("winner_hits", -1)) != winner_hits 					or int(first.get("loser_hits", -1)) != loser_hits:
				_fail("Round Result内容が期待値と一致しません。")
				return {}
			return first
		await create_timer(0.02).timeout
	_fail("Round Resultを受信できませんでした。")
	return {}


func _find_result(events: Array[Dictionary], round_number: int) -> Dictionary:
	for event in events:
		if int(event.get("round_number", -1)) == round_number:
			return event
	return {}


func _wait_score_pair(
	completed_round_number: int,
	winner_user_id: String,
	p1_user_id: String,
	expected_p1_rounds: int,
	p2_user_id: String,
	expected_p2_rounds: int,
	expected_match_finished: bool,
	timeout_ms: int
) -> Dictionary:
	var deadline := Time.get_ticks_msec() + timeout_ms
	while Time.get_ticks_msec() < deadline:
		var first := _find_score(_p1_scores, completed_round_number)
		var second := _find_score(_p2_scores, completed_round_number)
		if not first.is_empty() and not second.is_empty():
			if first != second:
				_fail("P1/P2でBO3 scoreが一致しません。")
				return {}
			var scores = first.get("round_wins_by_user", {})
			if str(first.get("round_winner_user_id", "")) != winner_user_id 					or int(scores.get(p1_user_id, -1)) != expected_p1_rounds 					or int(scores.get(p2_user_id, -1)) != expected_p2_rounds 					or bool(first.get("match_finished", false)) != expected_match_finished:
				_fail("BO3 score内容が期待値と一致しません。")
				return {}
			return first
		await create_timer(0.02).timeout
	_fail("BO3 scoreを受信できませんでした。")
	return {}


func _find_score(events: Array[Dictionary], completed_round_number: int) -> Dictionary:
	for event in events:
		if int(event.get("completed_round_number", -1)) == completed_round_number:
			return event
	return {}


func _wait_round_started_pair(
	round_number: int,
	p1_user_id: String,
	expected_p1_rounds: int,
	p2_user_id: String,
	expected_p2_rounds: int,
	timeout_ms: int
) -> Dictionary:
	var deadline := Time.get_ticks_msec() + timeout_ms
	while Time.get_ticks_msec() < deadline:
		var first := _find_started(_p1_started, round_number)
		var second := _find_started(_p2_started, round_number)
		if not first.is_empty() and not second.is_empty():
			if first != second:
				_fail("P1/P2でRound Startedが一致しません。")
				return {}
			var scores = first.get("round_wins_by_user", {})
			if int(scores.get(p1_user_id, -1)) != expected_p1_rounds 					or int(scores.get(p2_user_id, -1)) != expected_p2_rounds:
				_fail("Round Startedのscoreが期待値と一致しません。")
				return {}
			return first
		await create_timer(0.02).timeout
	return {}


func _find_started(events: Array[Dictionary], round_number: int) -> Dictionary:
	for event in events:
		if int(event.get("round_number", -1)) == round_number:
			return event
	return {}


func _fail(message: String) -> void:
	if _second_socket != null:
		_second_socket.close()
	push_error(message)
	print("AHOGE LEGEND BO3 smoke: FAIL")
	quit(1)
