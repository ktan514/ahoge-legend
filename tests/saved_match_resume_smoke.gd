extends SceneTree

const OnlineConfigScript := preload("res://src/config/online_config.gd")

var _second_socket = null
var _second_ticket: String = ""
var _second_match_id: String = ""
var _second_failure: String = ""


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var online_session = get_root().get_node_or_null("OnlineSession")
	var nakama = get_root().get_node_or_null("Nakama")
	if online_session == null or nakama == null:
		_fail("OnlineSession / Nakama Autoloadが見つかりません。")
		return

	# 前smokeの保存情報が残っていても、この試験は独立して開始する。
	online_session.clear_session()

	var auth_result: Dictionary = await online_session.authenticate_local_device()
	if not bool(auth_result.get("ok", false)):
		_fail("P1 Device認証に失敗しました。")
		return
	var p1_user_id := str(auth_result.get("user_id", ""))

	var ahoge_before := await _read_ahoge_ranking(
		online_session.client,
		online_session.session,
		100
	)
	if ahoge_before.is_empty():
		_fail("保存済みmatch復帰試験前のAHOGE Rankingを取得できませんでした。")
		return
	var long_before := _ahoge_counts(
		ahoge_before,
		OnlineConfigScript.RANKED_CHARACTER_LONG_TEST
	)
	var short_before := _ahoge_counts(
		ahoge_before,
		OnlineConfigScript.RANKED_CHARACTER_SHORT_TEST
	)

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

	_second_socket = nakama.create_socket_from(second_client)
	_second_socket.received_matchmaker_matched.connect(_on_second_matchmaker_matched)
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

	var second_ticket_result = await _second_socket.add_matchmaker_async(
		online_session.build_ranked_matchmaker_query(1500),
		OnlineConfigScript.RANKED_MATCHMAKER_MIN_COUNT,
		OnlineConfigScript.RANKED_MATCHMAKER_MAX_COUNT,
		{
			"mode": OnlineConfigScript.RANKED_MATCHMAKER_MODE,
			"character_id": OnlineConfigScript.RANKED_CHARACTER_SHORT_TEST,
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
		await create_timer(0.05).timeout

	if p1_joined[0].is_empty() or _second_match_id.is_empty():
		_fail("2クライアントがauthoritative matchへjoinできませんでした。")
		return

	var start_deadline := Time.get_ticks_msec() + 7000
	while Time.get_ticks_msec() < start_deadline and not round_one_started[0]:
		await create_timer(0.02).timeout
	if not round_one_started[0]:
		_fail("Round 1が開始しませんでした。")
		return

	var original_match_id: String = str(p1_joined[0])
	var saved_before: Dictionary = online_session.get_saved_match_for_current_user()
	if str(saved_before.get("match_id", "")) != original_match_id:
		_fail("対戦join時に未解決match情報が保存されていません。")
		return

	# アプリ再起動相当: runtime sessionだけ失い、未解決match情報は保持する。
	online_session.clear_runtime_session_preserving_match()

	var reauth: Dictionary = await online_session.authenticate_local_device()
	if not bool(reauth.get("ok", false)):
		_fail("再ログインDevice認証に失敗しました。")
		return
	if str(reauth.get("user_id", "")) != p1_user_id:
		_fail("再ログイン後のuser IDが変化しました。")
		return

	# 未解決matchを無視して別Rankedを開始できてはならない。
	var forbidden: Dictionary = await online_session.start_ranked_matchmaking(
		1500,
		OnlineConfigScript.RANKED_CHARACTER_LONG_TEST
	)
	if bool(forbidden.get("ok", false)):
		_fail("未解決matchがあるのに新しいRankedを開始できました。")
		return
	if str(forbidden.get("step", "")) != "unresolved_match":
		_fail("新規Ranked拒否理由がunresolved_matchではありません。")
		return

	var resumed: Dictionary = await online_session.resume_saved_match_after_login()
	if not bool(resumed.get("ok", false)) or not bool(resumed.get("resumed", false)):
		_fail("保存済みmatchへ再ログイン復帰できませんでした。")
		return
	if str(resumed.get("destination", "")) != "battle":
		_fail("進行中matchの復帰先がBattleではありません。")
		return

	var snapshot: Dictionary = resumed.get("snapshot", {})
	if str(snapshot.get("match_mode", "")) != "ranked" 			or bool(snapshot.get("match_finished", true)) 			or int(snapshot.get("round_number", -1)) != 1:
		_fail("再ログインsnapshotが進行中Rankedの状態と一致しません。")
		return

	if online_session.can_start_new_online_match():
		_fail("Battle復帰後に未解決match lockが解除されています。")
		return

	# P2を切断してserver authoritativeにMatch Resultを確定させる。
	var finished_result := [{}]
	online_session.match_result.connect(
		func(
			winner_user_id: String,
			loser_user_id: String,
			_round_wins: Dictionary,
			_final_round: int,
			finish_cause: String,
			_server_tick: int
		) -> void:
			finished_result[0] = {
				"winner_user_id": winner_user_id,
				"loser_user_id": loser_user_id,
				"finish_cause": finish_cause,
			}
	)
	if _second_socket != null:
		_second_socket.close()
		_second_socket = null

	var finish_deadline := Time.get_ticks_msec() + 18000
	while Time.get_ticks_msec() < finish_deadline and (finished_result[0] as Dictionary).is_empty():
		await create_timer(0.05).timeout
	if (finished_result[0] as Dictionary).is_empty():
		_fail("P2切断後に終了済みRanked Resultを受信できませんでした。")
		return
	if str((finished_result[0] as Dictionary).get("winner_user_id", "")) != p1_user_id:
		_fail("終了済みRankedのserver確定winnerがP1ではありません。")
		return
	if str((finished_result[0] as Dictionary).get("finish_cause", "")) != "DISCONNECT_TIMEOUT":
		_fail("終了済みRankedのfinish causeがDISCONNECT_TIMEOUTではありません。")
		return

	# 次のsmokeがbaselineを読む前に、今回のAHOGE projection完了まで待つ。
	var settlement := await _wait_ahoge_settlement(
		online_session.client,
		online_session.session,
		long_before,
		short_before,
		5000
	)
	if settlement.is_empty():
		_fail("保存済みmatch復帰試験のAHOGE settlementが完了しませんでした。")
		return

	# Result遷移確定前のlockを保持したまま再起動相当にし、
	# serverの終了済みsnapshotからranked_resultへ復帰する。
	online_session.clear_runtime_session_preserving_match()
	var finished_resume: Dictionary = await online_session.restore_unresolved_match_with_retry()
	if not bool(finished_resume.get("ok", false)) \
			or not bool(finished_resume.get("repaired", false)):
		_fail("終了済みRankedへ再接続できませんでした。")
		return
	if str(finished_resume.get("destination", "")) != "ranked_result":
		_fail("終了済みRankedの復帰先がranked_resultではありません。")
		return
	var finished_snapshot: Dictionary = finished_resume.get("snapshot", {})
	if not bool(finished_snapshot.get("match_finished", false)):
		_fail("終了済みRankedのserver snapshotがmatch_finishedではありません。")
		return
	if str(finished_snapshot.get("match_winner_user_id", "")) != p1_user_id:
		_fail("終了済みRanked snapshotのwinnerがserver結果と一致しません。")
		return

	if not online_session.acknowledge_saved_match_destination():
		_fail("Ranked Result遷移確定後に未解決match lockを解除できませんでした。")
		return
	if not online_session.can_start_new_online_match():
		_fail("Ranked Result遷移確定後も新規対戦lockが残っています。")
		return

	online_session.clear_session()
	print("AHOGE LEGEND saved match resume smoke: PASS match_id=%s" % original_match_id)
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


func _ahoge_counts(ranking: Dictionary, character_id: String) -> Dictionary:
	var records = ranking.get("records", [])
	if not records is Array:
		return {"wins": 0, "matches": 0}
	for record in records:
		if record is Dictionary and str(record.get("character_id", "")) == character_id:
			return {
				"wins": int(record.get("total_match_wins", 0)),
				"matches": int(record.get("total_ranked_matches", 0)),
			}
	return {"wins": 0, "matches": 0}


func _wait_ahoge_settlement(
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
				int(long_after.get("wins", -1)) == int(long_before.get("wins", 0)) + 1
				and int(long_after.get("matches", -1)) == int(long_before.get("matches", 0)) + 1
				and int(short_after.get("wins", -1)) == int(short_before.get("wins", 0))
				and int(short_after.get("matches", -1)) == int(short_before.get("matches", 0)) + 1
			):
				return ranking
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


func _fail(message: String) -> void:
	if _second_socket != null:
		_second_socket.close()
	var online_session = get_root().get_node_or_null("OnlineSession")
	if online_session != null:
		online_session.clear_session()
	push_error(message)
	print("AHOGE LEGEND saved match resume smoke: FAIL")
	quit(1)
