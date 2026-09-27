extends SceneTree

const OnlineConfigScript := preload("res://src/config/online_config.gd")
const CombatInputProtocolScript := preload("res://src/online/combat_input_protocol.gd")

var _second_socket = null
var _second_ticket: String = ""
var _second_match_id: String = ""
var _second_failure: String = ""
var _reconnect_started: bool = false
var _reconnect_succeeded: bool = false
var _snapshot: Dictionary = {}


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
	var p1_idle_after_attack := [false]
	online_session.ranked_match_joined.connect(func(match_id: String) -> void:
		p1_joined[0] = match_id
	)
	online_session.round_started.connect(
		func(round_number: int, _round_wins: Dictionary, _server_tick: int) -> void:
			if round_number == 1:
				round_one_started[0] = true
	)
	online_session.combat_state_changed.connect(
		func(user_id: String, state_name: String, _server_tick: int, _charge_ratio: float) -> void:
			if user_id == p1_user_id and state_name == "IDLE":
				p1_idle_after_attack[0] = true
	)
	online_session.reconnect_started.connect(func(_grace_seconds: int) -> void:
		_reconnect_started = true
	)
	online_session.match_snapshot_received.connect(func(value: Dictionary) -> void:
		_snapshot = value
	)
	online_session.reconnect_succeeded.connect(func(_match_id: String) -> void:
		_reconnect_succeeded = true
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
		_fail("P1 Matchmaker開始に失敗しました。")
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
		_fail("P2 Matchmaker開始に失敗しました。")
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

	if p1_joined[0].is_empty() or _second_match_id.is_empty() or p1_joined[0] != _second_match_id:
		_fail("P1/P2が同じauthoritative matchへjoinできませんでした。")
		return

	var start_deadline := Time.get_ticks_msec() + 7000
	while Time.get_ticks_msec() < start_deadline and not round_one_started[0]:
		await create_timer(0.02).timeout
	if not round_one_started[0]:
		_fail("Round 1開始を受信できませんでした。")
		return

	var press: Dictionary = await online_session.send_combat_input(
		CombatInputProtocolScript.ACTION_ATTACK_PRESS
	)
	if int(press.get("input_sequence", -1)) != 1:
		_fail("切断前ATTACK_PRESS sequenceが1ではありません。")
		return
	var release: Dictionary = await online_session.send_combat_input(
		CombatInputProtocolScript.ACTION_ATTACK_RELEASE
	)
	if int(release.get("input_sequence", -1)) != 2:
		_fail("切断前ATTACK_RELEASE sequenceが2ではありません。")
		return

	var idle_deadline := Time.get_ticks_msec() + 4000
	while Time.get_ticks_msec() < idle_deadline and not p1_idle_after_attack[0]:
		await create_timer(0.02).timeout
	if not p1_idle_after_attack[0]:
		_fail("切断前攻撃がIDLEへ復帰しませんでした。")
		return

	var original_match_id := online_session.current_match_id
	online_session.realtime_socket.close()

	var reconnect_deadline := Time.get_ticks_msec() + 8000
	while Time.get_ticks_msec() < reconnect_deadline:
		if _reconnect_started and _reconnect_succeeded and not _snapshot.is_empty():
			break
		await create_timer(0.02).timeout

	if not _reconnect_started:
		_fail("予期しないSocket切断でReconnectが開始しませんでした。")
		return
	if not _reconnect_succeeded or _snapshot.is_empty():
		_fail("OnlineSessionが15秒以内に自動Reconnectできませんでした。")
		return
	if online_session.current_match_id != original_match_id:
		_fail("Reconnect後にmatch IDが変わりました。")
		return
	if int(_snapshot.get("last_input_sequence", -1)) != 2:
		_fail("Reconnect snapshotのlast_input_sequenceが2ではありません。")
		return

	var post_press: Dictionary = await online_session.send_combat_input(
		CombatInputProtocolScript.ACTION_ATTACK_PRESS
	)
	if int(post_press.get("input_sequence", -1)) != 3:
		_fail("Reconnect後にinput sequenceを3から継続できませんでした。")
		return

	await online_session.realtime_socket.leave_match_async(original_match_id)
	if _second_socket != null:
		await _second_socket.leave_match_async(_second_match_id)
		_second_socket.close()
	online_session.disconnect_realtime_socket()

	print("AHOGE LEGEND auto reconnect smoke: PASS match_id=%s" % original_match_id)
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
	print("AHOGE LEGEND auto reconnect smoke: FAIL")
	quit(1)
