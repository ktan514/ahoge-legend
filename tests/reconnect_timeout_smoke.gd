extends SceneTree

const OnlineConfigScript := preload("res://src/config/online_config.gd")

var _second_socket = null
var _second_ticket: String = ""
var _second_match_id: String = ""
var _second_failure: String = ""
var _match_result: Dictionary = {}
var _p2_disconnected: bool = false


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
	online_session.player_connection_changed.connect(
		func(user_id: String, connected: bool, _deadline: int, _server_tick: int) -> void:
			if user_id != p1_user_id and not connected:
				_p2_disconnected = true
	)
	online_session.match_result.connect(
		func(winner_user_id: String, loser_user_id: String, round_wins: Dictionary, final_round_number: int, finish_cause: String, server_tick: int) -> void:
			_match_result = {
				"winner_user_id": winner_user_id,
				"loser_user_id": loser_user_id,
				"round_wins_by_user": round_wins,
				"final_round_number": final_round_number,
				"finish_cause": finish_cause,
				"server_tick": server_tick,
			}
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

	var ticket_result = await _second_socket.add_matchmaker_async(
		online_session.build_ranked_matchmaker_query(1500),
		OnlineConfigScript.RANKED_MATCHMAKER_MIN_COUNT,
		OnlineConfigScript.RANKED_MATCHMAKER_MAX_COUNT,
		{
			"mode": OnlineConfigScript.RANKED_MATCHMAKER_MODE,
			"character_id": OnlineConfigScript.RANKED_CHARACTER_LONG_TEST,
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

	_second_socket.close()
	_second_socket = null

	var disconnect_deadline := Time.get_ticks_msec() + 3000
	while Time.get_ticks_msec() < disconnect_deadline and not _p2_disconnected:
		await create_timer(0.02).timeout
	if not _p2_disconnected:
		_fail("P2切断eventを受信できませんでした。")
		return

	var result_deadline := Time.get_ticks_msec() + 18000
	while Time.get_ticks_msec() < result_deadline and _match_result.is_empty():
		await create_timer(0.05).timeout
	if _match_result.is_empty():
		_fail("15秒超過後のMatch Resultを受信できませんでした。")
		return

	if str(_match_result.get("winner_user_id", "")) != p1_user_id 			or str(_match_result.get("loser_user_id", "")) != p2_user_id 			or str(_match_result.get("finish_cause", "")) != "DISCONNECT_TIMEOUT" 			or int(_match_result.get("final_round_number", -1)) != 1:
		_fail("DISCONNECT_TIMEOUT Match Resultが期待値と一致しません。")
		return

	var scores: Dictionary = _match_result.get("round_wins_by_user", {})
	if int(scores.get(p1_user_id, -1)) != 0 or int(scores.get(p2_user_id, -1)) != 0:
		_fail("切断敗北でBO3 scoreが人工的に変更されました。")
		return

	online_session.disconnect_realtime_socket()
	print("AHOGE LEGEND reconnect timeout smoke: PASS match_id=%s" % p1_joined[0])
	quit(0)


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
	push_error(message)
	print("AHOGE LEGEND reconnect timeout smoke: FAIL")
	quit(1)
