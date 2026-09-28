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
var _p1_match_results: Array[Dictionary] = []
var _p2_match_results: Array[Dictionary] = []
var _p1_result_order: Array[int] = []
var _p2_result_order: Array[int] = []


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

	var initial_p1_rating := await _read_current_rating(
		online_session.client,
		online_session.session
	)
	var initial_p2_rating := await _read_current_rating(second_client, second_session)
	if initial_p1_rating.is_empty() or initial_p2_rating.is_empty():
		_fail("Match開始前Ratingを取得できませんでした。")
		return
	var expected_after_match := _expected_elo_pair(
		initial_p1_rating,
		initial_p2_rating,
		true
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

	await create_timer(0.1).timeout
	if not _p1_match_results.is_empty() or not _p2_match_results.is_empty():
		_fail("1勝時にMatch Resultが通知されました。")
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

	await create_timer(0.1).timeout
	if not _p1_match_results.is_empty() or not _p2_match_results.is_empty():
		_fail("1-1時にMatch Resultが通知されました。")
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

	var final_score := _find_score(_p1_scores, 3)
	var match_result := await _wait_match_result_pair(
		p1_user_id,
		p2_user_id,
		2,
		1,
		3,
		int(final_score.get("server_tick", -1)),
		5000
	)
	if match_result.is_empty():
		return

	var final_tick := int(match_result.get("server_tick", -1))
	if not await _wait_state_at_tick_pair(p1_user_id, "ROUND_LOCKED", final_tick, 5000) \
			or not await _wait_state_at_tick_pair(p2_user_id, "ROUND_LOCKED", final_tick, 5000):
		_fail("Match Result時点で両者がROUND_LOCKEDではありません。")
		return

	if _p1_result_order.size() < 3 or _p2_result_order.size() < 3:
		_fail("最終Roundの結果通知順序を確認できませんでした。")
		return
	var p1_order_size := _p1_result_order.size()
	var p2_order_size := _p2_result_order.size()
	if _p1_result_order[p1_order_size - 3] != CombatInputProtocolScript.OPCODE_ROUND_RESULT \
			or _p1_result_order[p1_order_size - 2] != CombatInputProtocolScript.OPCODE_BO3_SCORE_CHANGED \
			or _p1_result_order[p1_order_size - 1] != CombatInputProtocolScript.OPCODE_MATCH_RESULT:
		_fail("P1の最終結果通知順序がRound Result → BO3 score → Match Resultではありません。")
		return
	if _p2_result_order[p2_order_size - 3] != CombatInputProtocolScript.OPCODE_ROUND_RESULT \
			or _p2_result_order[p2_order_size - 2] != CombatInputProtocolScript.OPCODE_BO3_SCORE_CHANGED \
			or _p2_result_order[p2_order_size - 1] != CombatInputProtocolScript.OPCODE_MATCH_RESULT:
		_fail("P2の最終結果通知順序がRound Result → BO3 score → Match Resultではありません。")
		return
	if _p1_result_order != _p2_result_order:
		_fail("P1/P2で結果通知順序が一致しません。")
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
	if _p1_match_results.size() != 1 or _p2_match_results.size() != 1:
		_fail("Match Resultが1matchにつき1回ではありません。")
		return
	if _p1_match_results != _p2_match_results:
		_fail("P1/P2でMatch Result payloadが一致しません。")
		return

	var ratings := await _wait_rating_pair(
		online_session.client,
		online_session.session,
		second_client,
		second_session,
		expected_after_match["p1"],
		expected_after_match["p2"],
		5000
	)
	if ratings.is_empty():
		_fail("通常BO3後のRatingがElo期待値へ更新されませんでした。")
		return

	var ranking := await _read_player_ranking(
		online_session.client,
		online_session.session,
		100
	)
	if ranking.is_empty():
		_fail("PLAYER Rankingを取得できませんでした。")
		return
	if not _assert_player_ranking(
		ranking,
		p1_user_id,
		expected_after_match["p1"],
		p2_user_id,
		expected_after_match["p2"]
	):
		return

	var season_id := str(ranking.get("season_id", ""))
	if season_id.is_empty():
		_fail("PLAYER Rankingにseason_idがありません。")
		return
	var direct_write = await online_session.client.write_leaderboard_record_async(
		online_session.session,
		"player_rating_%s" % season_id,
		999999,
		0,
		"{}"
	)
	if direct_write == null or not direct_write.is_exception():
		_fail("authoritative PLAYER Rankingへclientから直接writeできました。")
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
	var finished_rejoin = await online_session.realtime_socket.join_match_async(p1_joined[0])
	if finished_rejoin == null or finished_rejoin.is_exception():
		_fail("終了済みmatchへの再joinに失敗しました。")
		return
	await create_timer(0.4).timeout

	var ratings_after_rejoin := await _wait_rating_pair(
		online_session.client,
		online_session.session,
		second_client,
		second_session,
		expected_after_match["p1"],
		expected_after_match["p2"],
		3000
	)
	if ratings_after_rejoin.is_empty():
		_fail("終了済みmatch再join後にRatingが二重更新されました。")
		return

	await online_session.realtime_socket.leave_match_async(p1_joined[0])
	await _second_socket.leave_match_async(_second_match_id)
	online_session.disconnect_realtime_socket()
	_second_socket.close()

	print("AHOGE LEGEND match result smoke: PASS match_id=%s" % p1_joined[0])
	quit(0)


func _read_player_ranking(client, session, limit: int) -> Dictionary:
	var rpc_result = await client.rpc_async(
		session,
		"ahoge_player_ranking",
		JSON.stringify({"limit": limit})
	)
	if rpc_result == null or rpc_result.is_exception():
		return {}
	var parsed = JSON.parse_string(str(rpc_result.payload))
	if not parsed is Dictionary:
		return {}
	return parsed


func _rank_tier_for_rating(rating: int) -> String:
	if rating >= 2000:
		return "MASTER"
	if rating >= 1800:
		return "DIAMOND"
	if rating >= 1600:
		return "PLATINUM"
	if rating >= 1400:
		return "GOLD"
	if rating >= 1200:
		return "SILVER"
	return "BRONZE"


func _find_player_ranking_record(records: Array, player_id: String) -> Dictionary:
	for record in records:
		if record is Dictionary and str(record.get("player_id", "")) == player_id:
			return record
	return {}


func _assert_player_ranking(
	ranking: Dictionary,
	p1_user_id: String,
	expected_p1: Dictionary,
	p2_user_id: String,
	expected_p2: Dictionary
) -> bool:
	var records_value = ranking.get("records", [])
	if not records_value is Array:
		_fail("PLAYER Ranking recordsが配列ではありません。")
		return false
	var records: Array = records_value

	var previous_rating := 2147483647
	var previous_display_rank := 0
	var previous_index := 0
	for index in range(records.size()):
		var record = records[index]
		if not record is Dictionary:
			_fail("PLAYER Ranking recordがDictionaryではありません。")
			return false
		var rating := int(record.get("rating", -1))
		var display_rank := int(record.get("display_rank", -1))
		if rating > previous_rating:
			_fail("PLAYER RankingがRating降順ではありません。")
			return false
		if index > 0 and rating == previous_rating:
			if display_rank != previous_display_rank:
				_fail("同RatingのPLAYER Rankingが同順位ではありません。")
				return false
		else:
			if display_rank != index + 1:
				_fail("PLAYER Rankingのdisplay_rankがcompetition rankingではありません。")
				return false
		previous_rating = rating
		previous_display_rank = display_rank
		previous_index = index

	var p1_record := _find_player_ranking_record(records, p1_user_id)
	var p2_record := _find_player_ranking_record(records, p2_user_id)
	if p1_record.is_empty() or p2_record.is_empty():
		_fail("対戦playerがPLAYER Rankingに存在しません。")
		return false

	for pair in [
		{"record": p1_record, "expected": expected_p1},
		{"record": p2_record, "expected": expected_p2},
	]:
		var record: Dictionary = pair["record"]
		var expected: Dictionary = pair["expected"]
		var rating := int(expected.get("rating", -1))
		if int(record.get("rating", -2)) != rating 				or int(record.get("wins", -2)) != int(expected.get("wins", -1)) 				or int(record.get("losses", -2)) != int(expected.get("losses", -1)) 				or str(record.get("rank_tier", "")) != _rank_tier_for_rating(rating):
			_fail("PLAYER Ranking recordがRating Storageと一致しません。")
			return false

	return true


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
	_collect(
		match_state,
		_p1_states,
		_p1_hits,
		_p1_counts,
		_p1_timers,
		_p1_results,
		_p1_scores,
		_p1_started,
		_p1_match_results,
		_p1_result_order
	)


func _on_second_match_state(match_state) -> void:
	if _second_match_id.is_empty() or str(match_state.match_id) != _second_match_id:
		return
	_collect(
		match_state,
		_p2_states,
		_p2_hits,
		_p2_counts,
		_p2_timers,
		_p2_results,
		_p2_scores,
		_p2_started,
		_p2_match_results,
		_p2_result_order
	)


func _collect(
	match_state,
	states: Array[Dictionary],
	hits: Array[Dictionary],
	counts: Array[Dictionary],
	timers: Array[Dictionary],
	results: Array[Dictionary],
	scores: Array[Dictionary],
	started: Array[Dictionary],
	match_results: Array[Dictionary],
	result_order: Array[int]
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
			result_order.append(op_code)
		return
	if op_code == CombatInputProtocolScript.OPCODE_BO3_SCORE_CHANGED:
		var event := CombatInputProtocolScript.parse_bo3_score_changed_payload(str(match_state.data))
		if not event.is_empty():
			scores.append(event)
			result_order.append(op_code)
		return
	if op_code == CombatInputProtocolScript.OPCODE_ROUND_STARTED:
		var event := CombatInputProtocolScript.parse_round_started_payload(str(match_state.data))
		if not event.is_empty():
			started.append(event)
		return
	if op_code == CombatInputProtocolScript.OPCODE_MATCH_RESULT:
		var event := CombatInputProtocolScript.parse_match_result_payload(str(match_state.data))
		if not event.is_empty():
			match_results.append(event)
			result_order.append(op_code)


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


func _wait_match_result_pair(
	winner_user_id: String,
	loser_user_id: String,
	winner_rounds: int,
	loser_rounds: int,
	final_round_number: int,
	expected_server_tick: int,
	timeout_ms: int
) -> Dictionary:
	var deadline := Time.get_ticks_msec() + timeout_ms
	while Time.get_ticks_msec() < deadline:
		if not _p1_match_results.is_empty() and not _p2_match_results.is_empty():
			var first := _p1_match_results[0]
			var second := _p2_match_results[0]
			if first != second:
				_fail("P1/P2でMatch Result payloadが一致しません。")
				return {}
			var scores = first.get("round_wins_by_user", {})
			if str(first.get("winner_user_id", "")) != winner_user_id \
					or str(first.get("loser_user_id", "")) != loser_user_id \
					or int(scores.get(winner_user_id, -1)) != winner_rounds \
					or int(scores.get(loser_user_id, -1)) != loser_rounds \
					or int(first.get("final_round_number", -1)) != final_round_number \
					or int(first.get("server_tick", -1)) != expected_server_tick:
				_fail("Match Result内容が期待値と一致しません。")
				return {}
			return first
		await create_timer(0.02).timeout
	_fail("Match Resultを両clientで受信できませんでした。")
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
	print("AHOGE LEGEND match result smoke: FAIL")
	quit(1)
