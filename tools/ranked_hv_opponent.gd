extends SceneTree

const OnlineConfigScript := preload("res://src/config/online_config.gd")
const CombatInputProtocolScript := preload("res://src/online/combat_input_protocol.gd")

const MODE_NEW := "new"
const MODE_RECONNECT := "reconnect"

var _socket = null
var _ticket: String = ""
var _match_id: String = ""
var _completed: bool = false
var _mode: String = MODE_NEW


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var nakama = get_root().get_node_or_null("Nakama")
	if nakama == null:
		_fail("Nakama Autoloadが見つかりません。")
		return

	_mode = OS.get_environment("AHOGE_HV_OPPONENT_MODE").strip_edges().to_lower()
	if _mode.is_empty():
		_mode = MODE_NEW
	if _mode not in [MODE_NEW, MODE_RECONNECT]:
		_fail("不正なHV opponent modeです: %s" % _mode)
		return

	var device_id := OS.get_environment("AHOGE_HV_OPPONENT_DEVICE_ID").strip_edges()
	if device_id.is_empty():
		device_id = Crypto.new().generate_random_bytes(32).hex_encode()

	var client = nakama.create_client(
		OnlineConfigScript.SERVER_KEY,
		OnlineConfigScript.HOST,
		OnlineConfigScript.PORT,
		OnlineConfigScript.SCHEME,
		OnlineConfigScript.CLIENT_TIMEOUT_SECONDS,
		OnlineConfigScript.CLIENT_LOG_LEVEL
	)
	var session = await client.authenticate_device_async(
		device_id,
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

	if _mode == MODE_RECONNECT:
		await _run_reconnect(client, session)
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


func _run_reconnect(client, session) -> void:
	var active_result = await client.rpc_async(
		session,
		OnlineConfigScript.ACTIVE_MATCH_RPC_GET
	)
	if active_result == null or active_result.is_exception():
		_fail("P2の未解決matchをserverから取得できませんでした。")
		return

	var parsed = JSON.parse_string(str(active_result.payload))
	if not parsed is Dictionary:
		_fail("P2の未解決match応答を解析できませんでした。")
		return
	var active: Dictionary = parsed
	if not bool(active.get("active", false)):
		_fail("P2に復帰対象の未解決matchがありません。")
		return
	if str(active.get("state", "")) != OnlineConfigScript.ACTIVE_MATCH_STATE_ACTIVE:
		_fail("P2のmatchは既に進行中ではありません: %s" % str(active.get("state", "")))
		return

	_match_id = str(active.get("match_id", ""))
	if _match_id.is_empty():
		_fail("P2のserver-side active matchにmatch IDがありません。")
		return

	var join_result = await _socket.join_match_async(_match_id)
	if join_result == null or join_result.is_exception() or not bool(join_result.authoritative):
		_fail("HV opponentが元authoritative matchへ再joinできませんでした。")
		return

	print("AHOGE LEGEND Ranked HV opponent: RECONNECTED")
	print("same P2 user / match_id=%s" % _match_id)
	print("このTerminalはMatch終了までP2接続を維持します。")

	var deadline := Time.get_ticks_msec() + 180000
	while Time.get_ticks_msec() < deadline and not _completed:
		await create_timer(0.1).timeout

	if not _completed:
		print("AHOGE LEGEND Ranked HV opponent: reconnect確認時間終了")
		print("必要なら再度 reconnect を実行してください。")
		quit(0)


func _on_matchmaker_matched(matched) -> void:
	if _completed or _mode != MODE_NEW:
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
	var op_code := int(match_state.op_code)

	if _mode == MODE_RECONNECT:
		if op_code == CombatInputProtocolScript.OPCODE_ROUND_STARTED:
			print("AHOGE LEGEND Ranked HV opponent: RECONNECTED ROUND STARTED")
			return
		if op_code == CombatInputProtocolScript.OPCODE_MATCH_RESULT:
			_completed = true
			print("AHOGE LEGEND Ranked HV opponent: MATCH RESULT RECEIVED")
			call_deferred("_finish_success")
		return

	if op_code != CombatInputProtocolScript.OPCODE_ROUND_STARTED:
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
	print("active Round中はtimeoutしません。P1でRound 1を取るとResult表示後にRound 2開始側へ切り替わり、そこからWAITING FOR OPPONENTの15秒待機が始まります。")
	print("15秒待機中のP2復帰確認は ./scripts/client-ranked-hv-opponent.sh reconnect を実行してください。")
	quit(0)


func _finish_success() -> void:
	if _socket != null:
		_socket.close()
		_socket = null
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
