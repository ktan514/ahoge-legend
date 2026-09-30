extends SceneTree

const OnlineConfigScript := preload("res://src/config/online_config.gd")
const CombatInputProtocolScript := preload("res://src/online/combat_input_protocol.gd")

var _second_socket = null
var _second_ticket: String = ""
var _second_match_id: String = ""
var _second_failure: String = ""

var _p1_round_results: Array[Dictionary] = []
var _p2_round_results: Array[Dictionary] = []
var _p1_scores: Array[Dictionary] = []
var _p2_scores: Array[Dictionary] = []
var _p1_match_results: Array[Dictionary] = []
var _p2_match_results: Array[Dictionary] = []
var _p1_round_started: Array[Dictionary] = []
var _p2_round_started: Array[Dictionary] = []
var _overtime_received: bool = false


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var online_session = get_root().get_node_or_null("OnlineSession")
	var nakama = get_root().get_node_or_null("Nakama")
	if online_session == null or nakama == null:
		_fail("OnlineSession / Nakama Autoloadが見つかりません。")
		return

	var auth: Dictionary = await online_session.authenticate_local_device()
	if not bool(auth.get("ok", false)):
		_fail("P1 Device認証に失敗しました。")
		return
	var p1_user_id := str(auth.get("user_id", ""))

	var realtime: Dictionary = await online_session.connect_realtime_socket()
	if not bool(realtime.get("ok", false)):
		_fail("P1 Realtime接続に失敗しました。")
		return

	online_session.round_result.connect(_on_p1_round_result)
	online_session.bo3_score_changed.connect(_on_p1_score)
	online_session.round_started.connect(_on_p1_round_started)
	online_session.match_result.connect(_on_p1_match_result)
	online_session.round_overtime_started.connect(func(_tick: int) -> void:
		_overtime_received = true
	)

	var second_client = nakama.create_client(
		OnlineConfigScript.SERVER_KEY,
		OnlineConfigScript.HOST,
		OnlineConfigScript.PORT,
		OnlineConfigScript.SCHEME,
		OnlineConfigScript.CLIENT_TIMEOUT_SECONDS,
		OnlineConfigScript.CLIENT_LOG_LEVEL
	)
	var second_device_id := OS.get_environment("AHOGE_TEST_SECOND_DEVICE_ID").strip_edges()
	if second_device_id.is_empty():
		second_device_id = Crypto.new().generate_random_bytes(32).hex_encode()
	var second_session = await second_client.authenticate_device_async(second_device_id, null, true)
	if second_session == null or second_session.is_exception():
		_fail("P2 Device認証に失敗しました。")
		return
	var p2_user_id := str(second_session.user_id)

	var p1_rating_before := await _read_current_rating(
		online_session.client,
		online_session.session
	)
	var p2_rating_before := await _read_current_rating(second_client, second_session)
	if p1_rating_before.is_empty() or p2_rating_before.is_empty():
		_fail("Draw前Player Ratingを取得できませんでした。")
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
		_fail("P2 Realtime接続に失敗しました。")
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
		_fail("P1 Matchmaking開始に失敗しました。")
		return

	var ticket = await _second_socket.add_matchmaker_async(
		online_session.build_ranked_matchmaker_query(1500),
		OnlineConfigScript.RANKED_MATCHMAKER_MIN_COUNT,
		OnlineConfigScript.RANKED_MATCHMAKER_MAX_COUNT,
		{
			"mode": OnlineConfigScript.RANKED_MATCHMAKER_MODE,
			"character_id": OnlineConfigScript.RANKED_CHARACTER_SHORT_TEST,
		},
		{"rating": 1500.0}
	)
	if ticket == null or ticket.is_exception():
		_fail("P2 Matchmaking開始に失敗しました。")
		return
	_second_ticket = str(ticket.ticket)

	var join_deadline := Time.get_ticks_msec() + 40000
	while Time.get_ticks_msec() < join_deadline:
		if not _second_failure.is_empty():
			_fail(_second_failure)
			return
		if not p1_joined[0].is_empty() and not _second_match_id.is_empty():
			break
		await create_timer(0.05).timeout
	if p1_joined[0].is_empty() or p1_joined[0] != _second_match_id:
		_fail("2clientが同じauthoritative matchへjoinできませんでした。")
		return

	if not await _wait_round_started_pair(1, 7000):
		_fail("Round 1が開始しませんでした。")
		return

	if not await _wait_round_draw_pair(1, 100000):
		return
	if _overtime_received:
		_fail("時間切れ同点でOvertimeが開始されました。")
		return

	var score_one := await _wait_score_pair(1, p1_user_id, 1, p2_user_id, 1, false, 5000)
	if score_one.is_empty():
		_fail("Round 1 Draw後に1-1へなりませんでした。")
		return

	if not await _wait_round_started_pair(2, 7000):
		_fail("Round 2が開始しませんでした。")
		return

	if not await _wait_round_draw_pair(2, 100000):
		return
	if _overtime_received:
		_fail("Round 2同点でOvertimeが開始されました。")
		return

	var score_two := await _wait_score_pair(2, p1_user_id, 2, p2_user_id, 2, true, 5000)
	if score_two.is_empty():
		_fail("Round 2 Draw後に2-2へなりませんでした。")
		return

	var match_result := await _wait_match_draw_pair(2, p1_user_id, p2_user_id, 5000)
	if match_result.is_empty():
		return

	var settlement := await _wait_settlement(
		online_session.client,
		online_session.session,
		p1_joined[0],
		5000
	)
	if settlement.is_empty():
		_fail("Draw settlementを取得できませんでした。")
		return
	if not bool(settlement.get("is_draw", false)):
		_fail("Draw settlementがis_draw=trueではありません。")
		return
	if bool(settlement.get("ahoge_mirror_match", true)):
		_fail("異character Drawがmirror settlementになっています。")
		return
	if int(settlement.get("ahoge_total_activity_count", -1)) != 0:
		_fail("完全無操作Drawのactivity countが0ではありません。")
		return
	if int(settlement.get("ahoge_pair_match_count_before", -1)) != 1:
		_fail("同一player pairの前回対戦数が1として記録されていません。")
		return
	if absf(float(settlement.get("ahoge_trust_multiplier", -1.0))) > 0.000001:
		_fail("完全無操作DrawのAhoge trustが0ではありません。")
		return
	if int(settlement.get("ahoge_raw_delta", 0)) == 0:
		_fail("Rating差ありDrawのraw Ahoge deltaが0で、trust抑制を検証できません。")
		return
	if int(settlement.get("ahoge_rating_delta", 999)) != 0:
		_fail("完全無操作DrawでAhoge Ratingが変動しました。")
		return

	var second_settlement := await _wait_settlement(
		second_client,
		second_session,
		p1_joined[0],
		5000
	)
	if second_settlement.is_empty():
		_fail("P2 Draw settlementを取得できませんでした。")
		return
	if int(second_settlement.get("ahoge_rating_delta", 999)) != 0:
		_fail("完全無操作DrawでP2 Ahoge Ratingが変動しました。")
		return

	var p1_rating := int(p1_rating_before.get("rating", 1500))
	var p2_rating := int(p2_rating_before.get("rating", 1500))
	var p1_expected := 1.0 / (
		1.0 + pow(10.0, float(p2_rating - p1_rating) / 400.0)
	)
	var p2_expected := 1.0 - p1_expected
	var raw_p1_delta := 32.0 * (0.5 - p1_expected)
	var expected_p1_delta := (
		-int(round(absf(raw_p1_delta)))
		if raw_p1_delta < 0.0
		else int(round(raw_p1_delta))
	)
	var expected_p2_delta := -expected_p1_delta
	if int(settlement.get("player_rating_delta", 999)) != expected_p1_delta:
		_fail("P1 DrawのPlayer Rating deltaがElo期待値と一致しません。")
		return
	if int(second_settlement.get("player_rating_delta", 999)) != expected_p2_delta:
		_fail("P2 DrawのPlayer Rating deltaがElo期待値と一致しません。")
		return
	if int(settlement.get("player_rating_delta", 0)) \
			+ int(second_settlement.get("player_rating_delta", 0)) != 0:
		_fail("DrawのPlayer Rating delta合計が0ではありません。")
		return

	if p1_rating != p2_rating:
		if p1_rating > p2_rating:
			if expected_p1_delta >= 0 or expected_p2_delta <= 0:
				_fail("格上P1とのDrawでPlayer Ratingの増減方向が不正です。")
				return
		else:
			if expected_p1_delta <= 0 or expected_p2_delta >= 0:
				_fail("格上P2とのDrawでPlayer Ratingの増減方向が不正です。")
				return

	var p1_rating_after := await _read_current_rating(
		online_session.client,
		online_session.session
	)
	var p2_rating_after := await _read_current_rating(second_client, second_session)
	if int(p1_rating_after.get("rating", -1)) != p1_rating + expected_p1_delta \
			or int(p2_rating_after.get("rating", -1)) != p2_rating + expected_p2_delta:
		_fail("Draw後Player Rating Storageがsettlementと一致しません。")
		return
	if int(p1_rating_after.get("draws", -1)) != int(p1_rating_before.get("draws", 0)) + 1 \
			or int(p2_rating_after.get("draws", -1)) != int(p2_rating_before.get("draws", 0)) + 1:
		_fail("Draw統計が両playerへ1件加算されていません。")
		return

	var ack_result: Dictionary = await online_session.acknowledge_active_match_destination()
	if not bool(ack_result.get("ok", false)):
		_fail("Draw Result確認後にP1 active matchをackできませんでした。")
		return

	await online_session.realtime_socket.leave_match_async(p1_joined[0])
	await _second_socket.leave_match_async(_second_match_id)
	online_session.disconnect_realtime_socket()
	_second_socket.close()

	print("AHOGE LEGEND timeout draw smoke: PASS match_id=%s" % p1_joined[0])
	quit(0)


func _on_p1_round_result(
	round_number: int,
	winner_user_id: String,
	loser_user_id: String,
	finish_cause: String,
	winner_hits: int,
	loser_hits: int,
	server_tick: int
) -> void:
	_p1_round_results.append({
		"round_number": round_number,
		"winner_user_id": winner_user_id,
		"loser_user_id": loser_user_id,
		"finish_cause": finish_cause,
		"winner_hits": winner_hits,
		"loser_hits": loser_hits,
		"server_tick": server_tick,
	})


func _on_p1_score(
	completed_round_number: int,
	round_winner_user_id: String,
	round_wins_by_user: Dictionary,
	match_finished: bool,
	server_tick: int
) -> void:
	_p1_scores.append({
		"completed_round_number": completed_round_number,
		"round_winner_user_id": round_winner_user_id,
		"round_wins_by_user": round_wins_by_user.duplicate(true),
		"match_finished": match_finished,
		"server_tick": server_tick,
	})


func _on_p1_round_started(
	round_number: int,
	round_wins_by_user: Dictionary,
	server_tick: int
) -> void:
	_p1_round_started.append({
		"round_number": round_number,
		"round_wins_by_user": round_wins_by_user.duplicate(true),
		"server_tick": server_tick,
	})


func _on_p1_match_result(
	winner_user_id: String,
	loser_user_id: String,
	round_wins_by_user: Dictionary,
	final_round_number: int,
	finish_cause: String,
	server_tick: int
) -> void:
	_p1_match_results.append({
		"winner_user_id": winner_user_id,
		"loser_user_id": loser_user_id,
		"round_wins_by_user": round_wins_by_user.duplicate(true),
		"final_round_number": final_round_number,
		"finish_cause": finish_cause,
		"server_tick": server_tick,
	})


func _on_second_matchmaker_matched(matched) -> void:
	if matched == null or matched.is_exception():
		_second_failure = "P2 matched通知が不正です。"
		return
	if str(matched.ticket) != _second_ticket:
		return
	var match_id := str(matched.match_id)
	if match_id.is_empty():
		_second_failure = "P2 matched通知にmatch IDがありません。"
		return
	var joined = await _second_socket.join_match_async(match_id)
	if joined == null or joined.is_exception() or not bool(joined.authoritative):
		_second_failure = "P2 authoritative match joinに失敗しました。"
		return
	_second_match_id = str(joined.match_id)


func _on_second_match_state(match_state) -> void:
	if _second_match_id.is_empty() or str(match_state.match_id) != _second_match_id:
		return
	var op_code := int(match_state.op_code)
	if op_code == CombatInputProtocolScript.OPCODE_ROUND_RESULT:
		var event := CombatInputProtocolScript.parse_round_result_payload(str(match_state.data))
		if not event.is_empty():
			_p2_round_results.append(event)
		return
	if op_code == CombatInputProtocolScript.OPCODE_BO3_SCORE_CHANGED:
		var event := CombatInputProtocolScript.parse_bo3_score_changed_payload(str(match_state.data))
		if not event.is_empty():
			_p2_scores.append(event)
		return
	if op_code == CombatInputProtocolScript.OPCODE_ROUND_STARTED:
		var event := CombatInputProtocolScript.parse_round_started_payload(str(match_state.data))
		if not event.is_empty():
			_p2_round_started.append(event)
		return
	if op_code == CombatInputProtocolScript.OPCODE_MATCH_RESULT:
		var event := CombatInputProtocolScript.parse_match_result_payload(str(match_state.data))
		if not event.is_empty():
			_p2_match_results.append(event)
		return
	if op_code == CombatInputProtocolScript.OPCODE_ROUND_OVERTIME_STARTED:
		_overtime_received = true


func _wait_round_started_pair(round_number: int, timeout_ms: int) -> bool:
	var deadline := Time.get_ticks_msec() + timeout_ms
	while Time.get_ticks_msec() < deadline:
		for first in _p1_round_started:
			if int(first.get("round_number", -1)) != round_number:
				continue
			for second in _p2_round_started:
				if int(second.get("round_number", -1)) != round_number:
					continue
				if _same_round_started_event(first, second):
					return true
		await create_timer(0.02).timeout
	return false


func _same_round_started_event(first: Dictionary, second: Dictionary) -> bool:
	if int(first.get("round_number", -1)) != int(second.get("round_number", -2)):
		return false
	if int(first.get("server_tick", -1)) != int(second.get("server_tick", -2)):
		return false
	return _same_score_map(
		first.get("round_wins_by_user", {}),
		second.get("round_wins_by_user", {})
	)


func _wait_round_draw_pair(round_number: int, timeout_ms: int) -> bool:
	var deadline := Time.get_ticks_msec() + timeout_ms
	while Time.get_ticks_msec() < deadline:
		var first := _find_round_result(_p1_round_results, round_number)
		var second := _find_round_result(_p2_round_results, round_number)
		if not first.is_empty() and not second.is_empty():
			if first != second:
				_fail("P1/P2のDraw Round Resultが一致しません。")
				return false
			if str(first.get("finish_cause", "")) != "TIMEOUT_DRAW" \
					or not str(first.get("winner_user_id", "")).is_empty() \
					or not str(first.get("loser_user_id", "")).is_empty() \
					or int(first.get("winner_hits", -1)) != int(first.get("loser_hits", -2)):
				_fail("TIMEOUT_DRAW Resultが期待値と一致しません。")
				return false
			return true
		await create_timer(0.05).timeout
	_fail("Round %d TIMEOUT_DRAWを受信できませんでした。" % round_number)
	return false


func _wait_score_pair(
	round_number: int,
	p1_user_id: String,
	p1_score: int,
	p2_user_id: String,
	p2_score: int,
	match_finished: bool,
	timeout_ms: int
) -> Dictionary:
	var deadline := Time.get_ticks_msec() + timeout_ms
	while Time.get_ticks_msec() < deadline:
		for first in _p1_scores:
			if int(first.get("completed_round_number", -1)) != round_number:
				continue
			for second in _p2_scores:
				if int(second.get("completed_round_number", -1)) != round_number:
					continue
				if not _same_score_event(first, second):
					continue
				var scores: Dictionary = first.get("round_wins_by_user", {})
				if not str(first.get("round_winner_user_id", "")).is_empty():
					return {}
				if int(scores.get(p1_user_id, -1)) != p1_score \
						or int(scores.get(p2_user_id, -1)) != p2_score:
					return {}
				if bool(first.get("match_finished", false)) != match_finished:
					return {}
				return first
		await create_timer(0.02).timeout
	return {}


func _same_score_event(first: Dictionary, second: Dictionary) -> bool:
	if int(first.get("completed_round_number", -1)) != int(second.get("completed_round_number", -2)):
		return false
	if str(first.get("round_winner_user_id", "")) != str(second.get("round_winner_user_id", "__missing__")):
		return false
	if bool(first.get("match_finished", false)) != bool(second.get("match_finished", true)):
		return false
	if int(first.get("server_tick", -1)) != int(second.get("server_tick", -2)):
		return false
	return _same_score_map(
		first.get("round_wins_by_user", {}),
		second.get("round_wins_by_user", {})
	)


func _wait_match_draw_pair(
	final_round: int,
	p1_user_id: String,
	p2_user_id: String,
	timeout_ms: int
) -> Dictionary:
	var deadline := Time.get_ticks_msec() + timeout_ms
	while Time.get_ticks_msec() < deadline:
		for first in _p1_match_results:
			for second in _p2_match_results:
				if not _same_match_result_event(first, second):
					continue
				if str(first.get("finish_cause", "")) != "BO3_DRAW" \
						or not str(first.get("winner_user_id", "")).is_empty() \
						or not str(first.get("loser_user_id", "")).is_empty() \
						or int(first.get("final_round_number", -1)) != final_round:
					_fail("BO3_DRAW Resultが期待値と一致しません。")
					return {}
				var scores: Dictionary = first.get("round_wins_by_user", {})
				if int(scores.get(p1_user_id, -1)) != 2 \
						or int(scores.get(p2_user_id, -1)) != 2:
					_fail("Match Draw scoreが2-2ではありません。")
					return {}
				return first
		await create_timer(0.02).timeout
	_fail("BO3_DRAW Resultを受信できませんでした。")
	return {}


func _same_match_result_event(first: Dictionary, second: Dictionary) -> bool:
	for key in [
		"winner_user_id",
		"loser_user_id",
		"final_round_number",
		"finish_cause",
		"server_tick",
	]:
		if first.get(key) != second.get(key):
			return false
	return _same_score_map(
		first.get("round_wins_by_user", {}),
		second.get("round_wins_by_user", {})
	)


func _same_score_map(first_value, second_value) -> bool:
	if not first_value is Dictionary or not second_value is Dictionary:
		return false
	var first: Dictionary = first_value
	var second: Dictionary = second_value
	if first.size() != second.size():
		return false
	for user_id in first.keys():
		if not second.has(user_id):
			return false
		if int(first[user_id]) != int(second[user_id]):
			return false
	return true


func _read_current_rating(client, session) -> Dictionary:
	var result = await client.rpc_async(session, "ahoge_current_rating")
	if result == null or result.is_exception():
		return {}
	var parsed = JSON.parse_string(str(result.payload))
	return parsed if parsed is Dictionary else {}


func _wait_settlement(client, session, match_id: String, timeout_ms: int) -> Dictionary:
	var deadline := Time.get_ticks_msec() + timeout_ms
	while Time.get_ticks_msec() < deadline:
		var result = await client.rpc_async(
			session,
			OnlineConfigScript.RANKED_SETTLEMENT_RPC,
			JSON.stringify({"match_id": match_id})
		)
		if result != null and not result.is_exception():
			var parsed = JSON.parse_string(str(result.payload))
			if parsed is Dictionary and bool((parsed as Dictionary).get("found", false)):
				return parsed
		await create_timer(0.05).timeout
	return {}


func _find_round_result(events: Array[Dictionary], round_number: int) -> Dictionary:
	for event in events:
		if int(event.get("round_number", -1)) == round_number:
			return event
	return {}


func _find_score(events: Array[Dictionary], round_number: int) -> Dictionary:
	for event in events:
		if int(event.get("completed_round_number", -1)) == round_number:
			return event
	return {}


func _find_round_started(events: Array[Dictionary], round_number: int) -> Dictionary:
	for event in events:
		if int(event.get("round_number", -1)) == round_number:
			return event
	return {}


func _fail(message: String) -> void:
	if _second_socket != null:
		_second_socket.close()
	push_error(message)
	print("AHOGE LEGEND timeout draw smoke: FAIL")
	quit(1)
