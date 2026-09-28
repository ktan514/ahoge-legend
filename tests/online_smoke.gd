extends SceneTree


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var online_session = get_root().get_node_or_null("OnlineSession")
	if online_session == null:
		_fail("OnlineSession Autoloadが見つかりません。")
		return

	var first_device_id: String = online_session.get_or_create_device_id()
	var second_device_id: String = online_session.get_or_create_device_id()

	if first_device_id.is_empty():
		_fail("Device IDを生成できませんでした。")
		return

	if first_device_id != second_device_id:
		_fail("Device IDが再利用されていません。")
		return

	var first_result: Dictionary = await online_session.authenticate_local_device()
	if not bool(first_result.get("ok", false)):
		_fail("初回Device認証に失敗しました: %s" % str(first_result))
		return

	if first_result.get("user_id", "") != first_result.get("account_user_id", ""):
		_fail("SessionとAccountのuser_idが一致しません。")
		return

	var first_user_id := str(first_result.get("user_id", ""))
	online_session.clear_session()

	var second_result: Dictionary = await online_session.authenticate_local_device()
	if not bool(second_result.get("ok", false)):
		_fail("再Device認証に失敗しました: %s" % str(second_result))
		return

	if first_user_id != str(second_result.get("user_id", "")):
		_fail("同じDevice IDで同じNakama Userへ再認証されませんでした。")
		return

	var rating_rpc = await online_session.client.rpc_async(
		online_session.session,
		"ahoge_current_rating"
	)
	if rating_rpc == null or rating_rpc.is_exception():
		_fail("初期Rating RPCを取得できませんでした。")
		return
	var rating = JSON.parse_string(str(rating_rpc.payload))
	if not rating is Dictionary:
		_fail("初期Rating RPC payloadが不正です。")
		return
	if int(rating.get("rating", -1)) != 1500 			or int(rating.get("wins", -1)) != 0 			or int(rating.get("losses", -1)) != 0:
		_fail("新規Playerの初期Ratingが1500 / 0勝 / 0敗ではありません。")
		return

	print("AHOGE LEGEND online smoke: PASS user_id=%s" % first_user_id)
	quit(0)


func _fail(message: String) -> void:
	push_error(message)
	print("AHOGE LEGEND online smoke: FAIL")
	quit(1)
