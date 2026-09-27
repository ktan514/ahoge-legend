extends SceneTree

const OnlineConfigScript := preload("res://src/config/online_config.gd")

var _second_socket = null
var _second_ticket: String = ""
var _second_match_id: String = ""
var _second_joined_match = null
var _second_failure: String = ""


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var online_session = get_root().get_node_or_null("OnlineSession")
	if online_session == null:
		_fail("OnlineSession Autoloadが見つかりません。")
		return

	var auth_result: Dictionary = await online_session.authenticate_local_device()
	if not bool(auth_result.get("ok", false)):
		_fail("P1 Device認証に失敗しました。")
		return

	var realtime_result: Dictionary = await online_session.connect_realtime_socket()
	if not bool(realtime_result.get("ok", false)):
		_fail("P1 Realtime Socket接続に失敗しました。")
		return

	var cancel_start: Dictionary = await online_session.start_ranked_matchmaking(1500)
	if not bool(cancel_start.get("ok", false)):
		_fail("取消検証用ticketを作成できませんでした。")
		return
	if not online_session.is_matchmaking():
		_fail("ticket作成後にmatchmaking状態になっていません。")
		return

	var cancel_result: Dictionary = await online_session.cancel_ranked_matchmaking()
	if not bool(cancel_result.get("ok", false)):
		_fail("Matchmaker ticketを取消できませんでした。")
		return
	if online_session.is_matchmaking():
		_fail("ticket取消後もmatchmaking状態です。")
		return

	var second_client = Nakama.create_client(
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

	_second_socket = Nakama.create_socket_from(second_client)
	_second_socket.received_matchmaker_matched.connect(_on_second_matchmaker_matched)
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

	var query := online_session.build_ranked_matchmaker_query(1500)
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

	var deadline := Time.get_ticks_msec() + 40000
	while Time.get_ticks_msec() < deadline:
		if not _second_failure.is_empty():
			_fail(_second_failure)
			return
		if not p1_joined[0].is_empty() and not _second_match_id.is_empty():
			break
		await create_timer(0.1).timeout

	if p1_joined[0].is_empty():
		_fail("P1がauthoritative matchへjoinできませんでした。")
		return
	if _second_match_id.is_empty():
		_fail("P2がauthoritative matchへjoinできませんでした。")
		return
	if p1_joined[0] != _second_match_id:
		_fail("P1とP2のmatch IDが一致しません。")
		return
	if not online_session.is_in_authoritative_match():
		_fail("P1 join先がauthoritative matchではありません。")
		return
	if _second_joined_match == null or not bool(_second_joined_match.authoritative):
		_fail("P2 join先がauthoritative matchではありません。")
		return

	await online_session.realtime_socket.leave_match_async(p1_joined[0])
	await _second_socket.leave_match_async(_second_match_id)
	online_session.disconnect_realtime_socket()
	_second_socket.close()

	print("AHOGE LEGEND matchmaker smoke: PASS match_id=%s" % p1_joined[0])
	quit(0)


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
	_second_joined_match = join_result
	_second_match_id = str(join_result.match_id)


func _fail(message: String) -> void:
	if _second_socket != null:
		_second_socket.close()
	push_error(message)
	print("AHOGE LEGEND matchmaker smoke: FAIL")
	quit(1)
