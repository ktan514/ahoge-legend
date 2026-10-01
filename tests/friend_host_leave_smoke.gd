extends SceneTree

const AppRootScene := preload("res://scenes/app/AppRoot.tscn")
const OnlineConfigScript := preload("res://src/config/online_config.gd")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var online_session = get_root().get_node_or_null("OnlineSession")
	var nakama = get_root().get_node_or_null("Nakama")
	if online_session == null or nakama == null:
		_fail("OnlineSession / Nakama Autoloadが見つかりません。", null)
		return

	online_session.clear_session()

	var app = AppRootScene.instantiate()
	get_root().add_child(app)
	if not await _wait_screen(app, "TopMenu", 6000):
		_fail("起動後にTopMenuが表示されません。", app)
		return

	var top = app.get_child(0)
	top.emit_signal("online_battle_requested")
	if not await _wait_screen(app, "BattleModeSelect", 5000):
		_fail("ONLINE BATTLEからBattleModeSelectへ遷移しません。", app)
		return

	var mode_screen = app.get_child(0)
	mode_screen.emit_signal("friend_requested")
	if not await _wait_screen(app, "FriendMatchMenu", 6000):
		_fail("FRIEND MATCHからFriendMatchMenuへ遷移しません。", app)
		return

	var host_client = nakama.create_client(
		OnlineConfigScript.SERVER_KEY,
		OnlineConfigScript.HOST,
		OnlineConfigScript.PORT,
		OnlineConfigScript.SCHEME,
		OnlineConfigScript.CLIENT_TIMEOUT_SECONDS,
		OnlineConfigScript.CLIENT_LOG_LEVEL
	)
	var host_session = await host_client.authenticate_device_async(
		Crypto.new().generate_random_bytes(32).hex_encode(),
		null,
		true
	)
	if host_session == null or host_session.is_exception():
		_fail("Host Device認証に失敗しました。", app)
		return

	# Case 1: Hostが先にLeaveしたらGuestはpollでroom終了を検知してFriend Menuへ戻る。
	var first_room := await _rpc_dict(
		host_client,
		host_session,
		OnlineConfigScript.FRIEND_ROOM_RPC_CREATE,
		{}
	)
	var first_code := str(first_room.get("room_code", ""))
	if first_code.is_empty():
		_fail("Case 1 Host roomを作成できませんでした。", app)
		return

	if not await _join_as_guest_via_ui(app, first_code):
		_fail("Case 1 Guestがroomへ参加できませんでした。", app)
		return

	var first_close := await _rpc_dict(
		host_client,
		host_session,
		OnlineConfigScript.FRIEND_ROOM_RPC_LEAVE,
		{"room_code": first_code}
	)
	if not bool(first_close.get("closed", false)):
		_fail("Case 1 Hostがroomを閉じられませんでした。", app)
		return

	if not await _wait_screen(app, "FriendMatchMenu", 4000):
		_fail("Host退出後もGuestがFriendRoomLobbyへ取り残されています。", app)
		return

	# Case 2: Host close直後にGuestがLeaveを押してもterminal failureを退出成功相当で扱う。
	var second_room := await _rpc_dict(
		host_client,
		host_session,
		OnlineConfigScript.FRIEND_ROOM_RPC_CREATE,
		{}
	)
	var second_code := str(second_room.get("room_code", ""))
	if second_code.is_empty():
		_fail("Case 2 Host roomを作成できませんでした。", app)
		return

	if not await _join_as_guest_via_ui(app, second_code):
		_fail("Case 2 Guestがroomへ参加できませんでした。", app)
		return

	var second_lobby = app.get_child(0)
	var second_close := await _rpc_dict(
		host_client,
		host_session,
		OnlineConfigScript.FRIEND_ROOM_RPC_LEAVE,
		{"room_code": second_code}
	)
	if not bool(second_close.get("closed", false)):
		_fail("Case 2 Hostがroomを閉じられませんでした。", app)
		return

	if is_instance_valid(second_lobby) and str(app.call("current_screen_name")) == "FriendRoomLobby":
		second_lobby.emit_signal("leave_requested")

	if not await _wait_screen(app, "FriendMatchMenu", 4000):
		_fail("削除済みroomでGuest LEAVEしてもLobbyから抜けられません。", app)
		return

	online_session.clear_session()
	app.queue_free()
	print("AHOGE LEGEND friend host leave smoke: PASS")
	quit(0)


func _join_as_guest_via_ui(app, room_code: String) -> bool:
	if str(app.call("current_screen_name")) != "FriendMatchMenu":
		return false
	var friend_menu = app.get_child(0)
	friend_menu.emit_signal("join_requested")
	if not await _wait_screen(app, "FriendRoomJoin", 3000):
		return false
	var join_screen = app.get_child(0)
	join_screen.emit_signal("join_requested", room_code)
	return await _wait_screen(app, "FriendRoomLobby", 6000)


func _rpc_dict(client, session, rpc_id: String, payload: Dictionary) -> Dictionary:
	var result = await client.rpc_async(session, rpc_id, JSON.stringify(payload))
	if result == null or result.is_exception():
		return {}
	var parsed = JSON.parse_string(str(result.payload))
	return parsed if parsed is Dictionary else {}


func _wait_screen(app, screen_name: String, timeout_ms: int) -> bool:
	var deadline := Time.get_ticks_msec() + timeout_ms
	while Time.get_ticks_msec() < deadline:
		if is_instance_valid(app) and str(app.call("current_screen_name")) == screen_name:
			return true
		await create_timer(0.05).timeout
	return false


func _fail(message: String, app) -> void:
	var online_session = get_root().get_node_or_null("OnlineSession")
	if online_session != null:
		online_session.clear_session()
	if app != null and is_instance_valid(app):
		app.queue_free()
	push_error(message)
	print("AHOGE LEGEND friend host leave smoke: FAIL")
	quit(1)
