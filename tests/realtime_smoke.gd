extends SceneTree


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var online_session = get_root().get_node_or_null("OnlineSession")
	if online_session == null:
		_fail("OnlineSession Autoloadが見つかりません。")
		return

	var preauth_result: Dictionary = await online_session.connect_realtime_socket()
	if bool(preauth_result.get("ok", false)):
		_fail("認証前にRealtime Socketへ接続できてしまいました。")
		return

	var auth_result: Dictionary = await online_session.authenticate_local_device()
	if not bool(auth_result.get("ok", false)):
		_fail("Device認証に失敗しました: %s" % str(auth_result))
		return

	var connected_count := [0]
	var disconnected_count := [0]
	online_session.realtime_connected.connect(func(_user_id: String) -> void:
		connected_count[0] += 1
	)
	online_session.realtime_disconnected.connect(func() -> void:
		disconnected_count[0] += 1
	)

	var connect_result: Dictionary = await online_session.connect_realtime_socket()
	if not bool(connect_result.get("ok", false)):
		_fail("Realtime Socket接続に失敗しました: %s" % str(connect_result))
		return

	if not online_session.is_realtime_connected():
		_fail("Realtime Socketが接続状態ではありません。")
		return

	if connected_count[0] < 1:
		_fail("Realtime Socket接続signalが通知されませんでした。")
		return

	if not online_session.disconnect_realtime_socket():
		_fail("Realtime Socketの明示切断を開始できませんでした。")
		return

	await create_timer(0.2).timeout

	if online_session.is_realtime_connected():
		_fail("明示切断後もRealtime Socketが接続状態です。")
		return

	if disconnected_count[0] < 1:
		_fail("Realtime Socket切断signalが通知されませんでした。")
		return

	print("AHOGE LEGEND realtime smoke: PASS user_id=%s" % str(auth_result.get("user_id", "")))
	quit(0)


func _fail(message: String) -> void:
	push_error(message)
	print("AHOGE LEGEND realtime smoke: FAIL")
	quit(1)
