extends SceneTree

const OnlineConfigScript := preload("res://src/config/online_config.gd")
const CombatInputProtocolScript := preload("res://src/online/combat_input_protocol.gd")

var _second_socket = null
var _second_ticket: String = ""
var _second_match_id: String = ""
var _second_failure: String = ""
var _second_match_result: Dictionary = {}
var _second_round_result: Dictionary = {}
var _second_connection_events: Array[Dictionary] = []
var _second_input_sequence: int = 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var online_session = get_root().get_node_or_null("OnlineSession")
	var nakama = get_root().get_node_or_null("Nakama")
	if online_session == null or nakama == null:
		_fail("OnlineSession / Nakama Autoloadが見つかりません。")
		return

	online_session.clear_session()

	var auth_result: Dictionary = await online_session.authenticate_local_device()
	if not bool(auth_result.get("ok", false)):
		_fail("P1 Device認証に失敗しました。")
		return
	var p1_user_id := str(auth_result.get("user_id", ""))

	var realtime_result: Dictionary = await online_session.connect_realtime_socket()
	if not bool(realtime_result.get("ok", false)):
		_fail("P1 Realtime Socket接続に失敗しました。")
		return

	var p1_joined := [""]
	var round_one_started := [false]
	online_session.ranked_match_joined.connect(func(match_id: String) -> void:
		p1_joined[0] = match_id
	)
	online_session.round_started.connect(
		func(round_number: int, _round_wins: Dictionary, _server_tick: int) -> void:
			if round_number == 1:
				round_one_started[0] = true
	)

	var second_client = nakama.create_client(
		OnlineConfigScript.SERVER_KEY,
		OnlineConfigScript.HOST,
		OnlineConfigScript.PORT,
		OnlineConfigScript.SCHEME,
		OnlineConfigScript.CLIENT_TIMEOUT_SECONDS,
		OnlineConfigScript.CLIENT_LOG_LEVEL
	)
	var second_session = await second_client.authenticate_device_async(
		Crypto.new().generate_random_bytes(32).hex_encode(),
		null,
		true
	)
	if second_session == null or second_session.is_exception():
		_fail("P2 Device認証に失敗しました。")
		return
	var p2_user_id := str(second_session.user_id)

	var initial_p1_rating := await _read_current_rating(
		online_session.client,
		online_session.session
	)
	var initial_p2_rating := await _read_current_rating(second_client, second_session)
	if initial_p1_rating.is_empty() or initial_p2_rating.is_empty():
		_fail("切断試験開始前Ratingを取得できませんでした。")
		return
	var expected_after_disconnect := _expected_elo_pair(
		initial_p1_rating,
		initial_p2_rating,
		false
	)

	var ahoge_before := await _read_ahoge_ranking(
		online_session.client,
		online_session.session,
		100
	)
	if ahoge_before.is_empty():
		_fail("切断試験開始前AHOGE LEGEND Rankingを取得できませんでした。")
		return
	var long_before := _ahoge_counts(
		ahoge_before,
		OnlineConfigScript.RANKED_CHARACTER_LONG_TEST
	)
	var short_before := _ahoge_counts(
		ahoge_before,
		OnlineConfigScript.RANKED_CHARACTER_SHORT_TEST
	)

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

	var p1_start: Dictionary = await online_session.start_ranked_matchmaking(
		1500,
		OnlineConfigScript.RANKED_CHARACTER_LONG_TEST
	)
	if not bool(p1_start.get("ok", false)):
		_fail("P1 Matchmakerを開始できませんでした。")
		return

	var ticket_result = await _second_socket.add_matchmaker_async(
		online_session.build_ranked_matchmaker_query(1500),
		OnlineConfigScript.RANKED_MATCHMAKER_MIN_COUNT,
		OnlineConfigScript.RANKED_MATCHMAKER_MAX_COUNT,
		{
			"mode": OnlineConfigScript.RANKED_MATCHMAKER_MODE,
			"character_id": OnlineConfigScript.RANKED_CHARACTER_SHORT_TEST,
		},
		{"rating": 1500.0}
	)
	if ticket_result == null or ticket_result.is_exception():
		_fail("P2 Matchmakerを開始できませんでした。")
		return
	_second_ticket = str(ticket_result.ticket)

	var join_deadline := Time.get_ticks_msec() + 40000
	while Time.get_ticks_msec() < join_deadline:
		if not _second_failure.is_empty():
			_fail(_second_failure)
			return
		if not p1_joined[0].is_empty() and not _second_match_id.is_empty():
			break
		await create_timer(0.05).timeout

	if p1_joined[0].is_empty() or _second_match_id.is_empty():
		_fail("2クライアントがjoinできませんでした。")
		return

	var start_deadline := Time.get_ticks_msec() + 7000
	while Time.get_ticks_msec() < start_deadline and not round_one_started[0]:
		await create_timer(0.02).timeout
	if not round_one_started[0]:
		_fail("Round 1が開始しませんでした。")
		return

	var original_match_id: String = str(p1_joined[0])
	var active_before: Dictionary = await online_session.refresh_active_online_match()
	if not bool(active_before.get("ok", false)) or not bool(active_before.get("active", false)) or str(active_before.get("match_id", "")) != original_match_id or str(active_before.get("state", "")) != OnlineConfigScript.ACTIVE_MATCH_STATE_ACTIVE:
		_fail("P1のserver-side active matchが保存されていません。")
		return

	# P1のアプリ終了相当。active Round中なのでこの時点では15秒deadlineを開始しない。
	var disconnect_event_start := _second_connection_events.size()
	online_session.clear_runtime_session_preserving_match()

	var active_disconnect := await _wait_second_connection_event(
		p1_user_id,
		false,
		disconnect_event_start,
		3000
	)
	if active_disconnect.is_empty():
		_fail("P1切断eventをP2が受信できませんでした。")
		return
	if int(active_disconnect.get("reconnect_deadline_tick", 0)) != -1:
		_fail("active Round中の切断で15秒deadlineが開始されています。")
		return

	# active Round中は15秒を超えてもmatchを終了しない。
	await create_timer(16.2).timeout
	if not _second_match_result.is_empty():
		_fail("active Round中に15秒経過しただけでMatch Resultが確定しました。")
		return
	var active_rpc = await second_client.rpc_async(
		second_session,
		OnlineConfigScript.ACTIVE_MATCH_RPC_GET
	)
	if active_rpc == null or active_rpc.is_exception():
		_fail("15秒経過後のactive match状態を確認できませんでした。")
		return
	var active_parsed = JSON.parse_string(str(active_rpc.payload))
	if not active_parsed is Dictionary 			or not bool((active_parsed as Dictionary).get("active", false)) 			or str((active_parsed as Dictionary).get("state", "")) != OnlineConfigScript.ACTIVE_MATCH_STATE_ACTIVE:
		_fail("active Round中15秒経過後もACTIVEが維持されていません。")
		return

	# P2が切断中P1へ5Hit取り、Round 1を通常ルールで終了させる。
	var boundary_event_start := _second_connection_events.size()
	for hit_index in range(1, 6):
		if not await _second_attack_once(hit_index):
			return

	var round_result_deadline := Time.get_ticks_msec() + 5000
	while Time.get_ticks_msec() < round_result_deadline and _second_round_result.is_empty():
		await create_timer(0.05).timeout
	if _second_round_result.is_empty():
		_fail("P1切断中にRound 1を終了できませんでした。")
		return
	if str(_second_round_result.get("winner_user_id", "")) != p2_user_id:
		_fail("P1切断中のRound 1 winnerがP2ではありません。")
		return

	var boundary_disconnect := await _wait_second_boundary_deadline(
		p1_user_id,
		boundary_event_start,
		3000
	)
	if boundary_disconnect.is_empty():
		_fail("Round終了後にP1の15秒boundary deadlineが開始されませんでした。")
		return

	# Round取得だけではRatingを更新しない。
	var p2_rating_after_round := await _read_current_rating(second_client, second_session)
	if not _same_rating_record(initial_p2_rating, p2_rating_after_round):
		_fail("Round 1終了時点でPlayer Ratingが更新されました。")
		return

	# Round境界15秒timeoutで初めてP2のMatch Win / P1のMatch Loseを確定する。
	var result_deadline := Time.get_ticks_msec() + 18000
	while Time.get_ticks_msec() < result_deadline and _second_match_result.is_empty():
		await create_timer(0.05).timeout
	if _second_match_result.is_empty():
		_fail("Round境界15秒超過後のMatch ResultをP2が受信できませんでした。")
		return

	if str(_second_match_result.get("winner_user_id", "")) != p2_user_id 			or str(_second_match_result.get("loser_user_id", "")) != p1_user_id 			or str(_second_match_result.get("finish_cause", "")) != "DISCONNECT_TIMEOUT" 			or int(_second_match_result.get("final_round_number", -1)) != 1:
		_fail("DISCONNECT_TIMEOUT Match Resultが期待値と一致しません。")
		return

	var scores: Dictionary = _second_match_result.get("round_wins_by_user", {})
	if int(scores.get(p1_user_id, -1)) != 0 or int(scores.get(p2_user_id, -1)) != 1:
		_fail("切断敗北時のRound scoreが通常Round Resultと一致しません。")
		return

	# 15秒を超えても元matchは未解決lockとして残る。
	var reauth: Dictionary = await online_session.authenticate_local_device()
	if not bool(reauth.get("ok", false)) or str(reauth.get("user_id", "")) != p1_user_id:
		_fail("P1再ログインに失敗しました。")
		return

	var ratings := await _wait_rating_pair(
		online_session.client,
		online_session.session,
		second_client,
		second_session,
		expected_after_disconnect["p1"],
		expected_after_disconnect["p2"],
		5000
	)
	if ratings.is_empty():
		_fail("DISCONNECT_TIMEOUT後のRatingがElo期待値へ更新されませんでした。")
		return

	var ahoge_after := await _wait_ahoge_counts(
		online_session.client,
		online_session.session,
		long_before,
		short_before,
		5000
	)
	if ahoge_after.is_empty():
		_fail("DISCONNECT_TIMEOUT後AHOGE LEGEND Rankingが期待集計へ更新されませんでした。")
		return

	var forbidden: Dictionary = await online_session.start_ranked_matchmaking(
		1500,
		OnlineConfigScript.RANKED_CHARACTER_LONG_TEST
	)
	if bool(forbidden.get("ok", false)) or str(forbidden.get("step", "")) != "unresolved_match":
		_fail("切断敗北後の結果未解決中に新しいRankedを開始できました。")
		return

	var resumed: Dictionary = await online_session.resume_active_match_after_login()
	if not bool(resumed.get("ok", false)) or not bool(resumed.get("resumed", false)):
		_fail("15秒超過後の終了済みmatchへ再接続できませんでした。")
		return
	if str(resumed.get("destination", "")) != "ranked_result":
		_fail("終了済みRankedの復帰先がranked_resultではありません。")
		return

	var snapshot: Dictionary = resumed.get("snapshot", {})
	if not bool(snapshot.get("match_finished", false)) 			or str(snapshot.get("match_mode", "")) != "ranked" 			or str(snapshot.get("match_winner_user_id", "")) != p2_user_id 			or str(snapshot.get("match_finish_cause", "")) != "DISCONNECT_TIMEOUT":
		_fail("終了済みRanked snapshotがMatch Resultと一致しません。")
		return

	if online_session.can_start_new_online_match():
		_fail("Result遷移確定前に未解決match lockが解除されています。")
		return

	var ack_result: Dictionary = await online_session.acknowledge_active_match_destination()
	if not bool(ack_result.get("ok", false)):
		_fail("Result遷移確定後にserver-side active matchを解除できませんでした。")
		return
	var active_after_ack: Dictionary = await online_session.refresh_active_online_match()
	if not bool(active_after_ack.get("ok", false)) or bool(active_after_ack.get("active", false)):
		_fail("Result遷移確定後もserver-side active matchが残っています。")
		return

	if _second_socket != null:
		await _second_socket.leave_match_async(_second_match_id)
		_second_socket.close()
	online_session.clear_session()

	print("AHOGE LEGEND reconnect timeout smoke: PASS match_id=%s" % original_match_id)
	quit(0)


func _read_ahoge_ranking(client, session, limit: int) -> Dictionary:
	var rpc_result = await client.rpc_async(
		session,
		"ahoge_legend_ranking",
		JSON.stringify({"limit": limit})
	)
	if rpc_result == null or rpc_result.is_exception():
		return {}
	var parsed = JSON.parse_string(str(rpc_result.payload))
	if not parsed is Dictionary:
		return {}
	return parsed


func _find_ahoge_record(ranking: Dictionary, character_id: String) -> Dictionary:
	var records = ranking.get("records", [])
	if not records is Array:
		return {}
	for record in records:
		if record is Dictionary and str(record.get("character_id", "")) == character_id:
			return record
	return {}


func _ahoge_counts(ranking: Dictionary, character_id: String) -> Dictionary:
	var record := _find_ahoge_record(ranking, character_id)
	if record.is_empty():
		return {"wins": 0, "matches": 0}
	return {
		"wins": int(record.get("total_match_wins", 0)),
		"matches": int(record.get("total_ranked_matches", 0)),
	}


func _wait_ahoge_counts(
	client,
	session,
	long_before: Dictionary,
	short_before: Dictionary,
	timeout_ms: int
) -> Dictionary:
	var deadline := Time.get_ticks_msec() + timeout_ms
	while Time.get_ticks_msec() < deadline:
		var ranking := await _read_ahoge_ranking(client, session, 100)
		if not ranking.is_empty():
			var long_after := _ahoge_counts(
				ranking,
				OnlineConfigScript.RANKED_CHARACTER_LONG_TEST
			)
			var short_after := _ahoge_counts(
				ranking,
				OnlineConfigScript.RANKED_CHARACTER_SHORT_TEST
			)
			if (
				int(long_after.get("wins", -1)) == int(long_before.get("wins", 0))
				and int(long_after.get("matches", -1)) == int(long_before.get("matches", 0)) + 1
				and int(short_after.get("wins", -1)) == int(short_before.get("wins", 0)) + 1
				and int(short_after.get("matches", -1)) == int(short_before.get("matches", 0)) + 1
			):
				return ranking
		await create_timer(0.05).timeout
	return {}


func _read_current_rating(client, session) -> Dictionary:
	var rpc_result = await client.rpc_async(session, "ahoge_current_rating")
	if rpc_result == null or rpc_result.is_exception():
		return {}
	var parsed = JSON.parse_string(str(rpc_result.payload))
	if not parsed is Dictionary:
		return {}
	return parsed


func _expected_elo_pair(
	p1_before: Dictionary,
	p2_before: Dictionary,
	p1_wins: bool
) -> Dictionary:
	var p1_rating := int(p1_before.get("rating", 1500))
	var p2_rating := int(p2_before.get("rating", 1500))
	var p1_expected := 1.0 / (1.0 + pow(10.0, float(p2_rating - p1_rating) / 400.0))
	var p2_expected := 1.0 / (1.0 + pow(10.0, float(p1_rating - p2_rating) / 400.0))
	var p1_score := 1.0 if p1_wins else 0.0
	var p2_score := 0.0 if p1_wins else 1.0
	return {
		"p1": {
			"rating": int(round(p1_rating + 32.0 * (p1_score - p1_expected))),
			"wins": int(p1_before.get("wins", 0)) + (1 if p1_wins else 0),
			"losses": int(p1_before.get("losses", 0)) + (0 if p1_wins else 1),
		},
		"p2": {
			"rating": int(round(p2_rating + 32.0 * (p2_score - p2_expected))),
			"wins": int(p2_before.get("wins", 0)) + (0 if p1_wins else 1),
			"losses": int(p2_before.get("losses", 0)) + (1 if p1_wins else 0),
		},
	}


func _wait_rating_pair(
	p1_client,
	p1_session,
	p2_client,
	p2_session,
	expected_p1: Dictionary,
	expected_p2: Dictionary,
	timeout_ms: int
) -> Dictionary:
	var deadline := Time.get_ticks_msec() + timeout_ms
	while Time.get_ticks_msec() < deadline:
		var p1_rating := await _read_current_rating(p1_client, p1_session)
		var p2_rating := await _read_current_rating(p2_client, p2_session)
		if not p1_rating.is_empty() and not p2_rating.is_empty():
			if int(p1_rating.get("rating", -1)) == int(expected_p1.get("rating", -2)) 					and int(p2_rating.get("rating", -1)) == int(expected_p2.get("rating", -2)) 					and int(p1_rating.get("wins", -1)) == int(expected_p1.get("wins", -2)) 					and int(p1_rating.get("losses", -1)) == int(expected_p1.get("losses", -2)) 					and int(p2_rating.get("wins", -1)) == int(expected_p2.get("wins", -2)) 					and int(p2_rating.get("losses", -1)) == int(expected_p2.get("losses", -2)):
				return {
					"p1": p1_rating,
					"p2": p2_rating,
				}
		await create_timer(0.05).timeout
	return {}


func _on_second_matchmaker_matched(matched) -> void:
	if matched == null or matched.is_exception():
		_second_failure = "P2 matchmaker matched通知が不正です。"
		return
	if str(matched.ticket) != _second_ticket:
		return
	var match_id := str(matched.match_id)
	if match_id.is_empty():
		_second_failure = "P2 matched通知にmatch IDがありません。"
		return
	var join_result = await _second_socket.join_match_async(match_id)
	if join_result == null or join_result.is_exception():
		_second_failure = "P2 authoritative match joinに失敗しました。"
		return
	_second_match_id = str(join_result.match_id)


func _on_second_match_state(match_state) -> void:
	if _second_match_id.is_empty() or str(match_state.match_id) != _second_match_id:
		return
	if int(match_state.op_code) != CombatInputProtocolScript.OPCODE_MATCH_RESULT:
		return
	var event := CombatInputProtocolScript.parse_match_result_payload(str(match_state.data))
	if not event.is_empty():
		_second_match_result = event


func _fail(message: String) -> void:
	if _second_socket != null:
		_second_socket.close()
	var online_session = get_root().get_node_or_null("OnlineSession")
	if online_session != null:
		online_session.clear_session()
	push_error(message)
	print("AHOGE LEGEND reconnect timeout smoke: FAIL")
	quit(1)
