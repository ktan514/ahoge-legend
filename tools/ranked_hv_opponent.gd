extends SceneTree

const OnlineConfigScript := preload("res://src/config/online_config.gd")
const CombatInputProtocolScript := preload("res://src/online/combat_input_protocol.gd")

var _socket = null
var _ticket: String = ""
var _match_id: String = ""
var _completed: bool = false


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var nakama = get_root().get_node_or_null("Nakama")
	if nakama == null:
		_fail("Nakama Autoloadが見つかりません。")
		return

	var client = nakama.create_client(
		OnlineConfigScript.SERVER_KEY,
		OnlineConfigScript.HOST,
		OnlineConfigScript.PORT,
		OnlineConfigScript.SCHEME,
		OnlineConfigScript.CLIENT_TIMEOUT_SECONDS,
		OnlineConfigScript.CLIENT_LOG_LEVEL
	)
	var session = await client.authenticate_device_async(
		Crypto.new().generate_random_bytes(32).hex_encode(),
		null,
		true
	)
	if session == null or session.is_exception():
		_fail("HV opponentのDevice認証に失敗しました。")
		return

	_socket = nakama.create_socket_from(client)
	_socket.received_matchmaker_matched.connect(_on_matchmaker_matched)
	_socket.received_match_state.connect(_on_match_state)

	var connect_result = await _socket.connect_async(
		session,
		OnlineConfigScript.SOCKET_APPEAR_ONLINE,
		OnlineConfigScript.SOCKET_CONNECT_TIMEOUT_SECONDS
	)
	if connect_result == null or connect_result.is_exception():
		_fail("HV opponentのRealtime接続に失敗しました。")
		return

	var ticket_result = await _socket.add_matchmaker_async(
		"+properties.mode:ranked",
		OnlineConfigScript.RANKED_MATCHMAKER_MIN_COUNT,
		OnlineConfigScript.RANKED_MATCHMAKER_MAX_COUNT,
		{
			"mode": OnlineConfigScript.RANKED_MATCHMAKER_MODE,
			"character_id": OnlineConfigScript.RANKED_CHARACTER_SHORT_TEST,
		},
		{"rating": 1500.0}
	)
	if ticket_result == null or ticket_result.is_exception():
		_fail("HV opponentのRanked Matchmaking開始に失敗しました。")
		return

	_ticket = str(ticket_result.ticket)
	print("AHOGE LEGEND Ranked HV opponent: MATCHING")
	print("P1実画面で RANKED MATCH → CHARACTER SELECT → DECIDE を操作してください。")

	var deadline := Time.get_ticks_msec() + 180000
	while Time.get_ticks_msec() < deadline and not _completed:
		await create_timer(0.1).timeout

	if not _completed:
		_fail("3分以内にRanked matchがRound開始まで進みませんでした。")


func _on_matchmaker_matched(matched) -> void:
	if _completed:
		return
	if matched == null or matched.is_exception():
		_fail("HV opponentのmatched通知が不正です。")
		return
	if str(matched.ticket) != _ticket:
		return

	var match_id := str(matched.match_id)
	if match_id.is_empty():
		_fail("HV opponentのmatched通知にmatch IDがありません。")
		return

	var join_result = await _socket.join_match_async(match_id)
	if join_result == null or join_result.is_exception() or not bool(join_result.authoritative):
		_fail("HV opponentがauthoritative matchへjoinできませんでした。")
		return

	_match_id = str(join_result.match_id)
	print("AHOGE LEGEND Ranked HV opponent: MATCH JOINED")


func _on_match_state(match_state) -> void:
	if _completed or _match_id.is_empty():
		return
	if int(match_state.op_code) != CombatInputProtocolScript.OPCODE_ROUND_STARTED:
		return

	_completed = true
	print("AHOGE LEGEND Ranked HV opponent: ROUND STARTED")
	call_deferred("_disconnect_after_round_start")


func _disconnect_after_round_start() -> void:
	await create_timer(1.0).timeout
	if _socket != null:
		_socket.close()
		_socket = null
	print("AHOGE LEGEND Ranked HV opponent: DISCONNECTED")
	print("active Round中はtimeoutしません。P1でRoundを終了させると、その時点から15秒後にserver authoritative Match Resultへ遷移します。")
	quit(0)


func _fail(message: String) -> void:
	if _completed:
		return
	_completed = true
	if _socket != null:
		_socket.close()
		_socket = null
	push_error(message)
	print("AHOGE LEGEND Ranked HV opponent: FAIL")
	quit(1)
