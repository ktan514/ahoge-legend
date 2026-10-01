extends SceneTree

const AppRootScene := preload("res://scenes/app/AppRoot.tscn")
const OnlineConfigScript := preload("res://src/config/online_config.gd")
const CombatInputProtocolScript := preload("res://src/online/combat_input_protocol.gd")

var _second_socket = null


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
	if not mode_screen.has_signal("friend_requested"):
		_fail("BattleModeSelectにfriend_requestedがありません。", app)
		return
	mode_screen.emit_signal("friend_requested")
	if not await _wait_screen(app, "FriendMatchMenu", 6000):
		_fail("FRIEND MATCHからFriendMatchMenuへ遷移しません。", app)
		return

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
		_fail("P2 Device認証に失敗しました。", app)
		return

	# UI-07: P2が作ったroomへP1がJOINし、Lobbyへ入れることを確認する。
	var temporary_room := await _rpc_dict(
		second_client,
		second_session,
		OnlineConfigScript.FRIEND_ROOM_RPC_CREATE,
		{}
	)
	var temporary_code := str(temporary_room.get("room_code", ""))
	if not _valid_room_code(temporary_code):
		_fail("P2検証用room codeが不正です。", app)
		return

	var friend_menu = app.get_child(0)
	friend_menu.emit_signal("join_requested")
	if not await _wait_screen(app, "FriendRoomJoin", 3000):
		_fail("JOIN ROOMでUI-07へ遷移しません。", app)
		return

	var join_screen = app.get_child(0)
	join_screen.emit_signal("join_requested", temporary_code)
	if not await _wait_screen(app, "FriendRoomLobby", 6000):
		_fail("room code参加後にUI-08 Lobbyへ遷移しません。", app)
		return
	var guest_lobby = app.get_child(0)
	if str(guest_lobby.call("room_code")) != temporary_code:
		_fail("UI-08がserver room codeを表示していません。", app)
		return
	if str(guest_lobby.call("local_role")) != "guest":
		_fail("JOIN ROOM後のlocal roleがguestではありません。", app)
		return

	guest_lobby.emit_signal("leave_requested")
	if not await _wait_screen(app, "FriendMatchMenu", 5000):
		_fail("guest LEAVE ROOMでFriendMatchMenuへ戻りません。", app)
		return
	var p2_close := await _rpc_dict(
		second_client,
		second_session,
		OnlineConfigScript.FRIEND_ROOM_RPC_LEAVE,
		{"room_code": temporary_code}
	)
	if not bool(p2_close.get("closed", false)):
		_fail("P2検証用roomを終了できませんでした。", app)
		return

	# UI-06 CREATE ROOM → UI-08 Lobby.
	friend_menu = app.get_child(0)
	friend_menu.emit_signal("create_requested")
	if not await _wait_screen(app, "FriendRoomLobby", 6000):
		_fail("CREATE ROOMでUI-08 Lobbyへ遷移しません。", app)
		return

	var lobby = app.get_child(0)
	var room_code := str(lobby.call("room_code"))
	if not _valid_room_code(room_code):
		_fail("CREATE ROOMの6文字room codeが不正です。", app)
		return
	if str(lobby.call("local_role")) != "host":
		_fail("CREATE ROOM後のlocal roleがhostではありません。", app)
		return

	var p2_join := await _rpc_dict(
		second_client,
		second_session,
		OnlineConfigScript.FRIEND_ROOM_RPC_JOIN,
		{"room_code": room_code}
	)
	if p2_join.is_empty() or str(p2_join.get("role", "")) != "guest":
		_fail("P2がP1 roomへ参加できませんでした。", app)
		return

	# P1は共通UI-04をFriend modeで使用する。
	lobby.emit_signal("character_select_requested")
	if not await _wait_screen(app, "CharacterSelect", 3000):
		_fail("Friend LobbyからCharacterSelectへ遷移しません。", app)
		return
	var character_select = app.get_child(0)
	if not character_select.has_signal("friend_character_selected"):
		_fail("CharacterSelectがFriend modeに対応していません。", app)
		return
	character_select.emit_signal(
		"friend_character_selected",
		OnlineConfigScript.RANKED_CHARACTER_LONG_TEST
	)
	if not await _wait_screen(app, "FriendRoomLobby", 5000):
		_fail("Friend Character決定後にLobbyへ戻りません。", app)
		return

	var p2_character := await _rpc_dict(
		second_client,
		second_session,
		OnlineConfigScript.FRIEND_ROOM_RPC_CHARACTER,
		{
			"room_code": room_code,
			"character_id": OnlineConfigScript.RANKED_CHARACTER_SHORT_TEST,
		}
	)
	if p2_character.is_empty():
		_fail("P2 characterをserverへ保存できませんでした。", app)
		return
	if not await _wait_label_text(app, OnlineConfigScript.RANKED_CHARACTER_SHORT_TEST, 4000):
		_fail("LobbyへP2 characterが反映されません。", app)
		return

	# Battle開始前にP1 authoritative event監視を開始する。
	var p1_user_id := str(online_session.session.user_id)
	var p1_hit_count := [0]
	var p1_states: Array[Dictionary] = []
	var round_one_started := [false]
	var match_result_seen_at := [0]
	online_session.round_hit_count_changed.connect(
		func(user_id: String, hit_count: int, _server_tick: int, _input_sequence: int) -> void:
			if user_id == p1_user_id:
				p1_hit_count[0] = hit_count
	)
	online_session.combat_state_changed.connect(
		func(user_id: String, state_name: String, _server_tick: int, _charge_ratio: float) -> void:
			if user_id == p1_user_id:
				p1_states.append({"state": state_name})
	)
	online_session.round_started.connect(
		func(round_number: int, _round_wins: Dictionary, _server_tick: int) -> void:
			if round_number == 1:
				round_one_started[0] = true
	)
	online_session.match_result.connect(
		func(
			_winner_user_id: String,
			_loser_user_id: String,
			_round_wins: Dictionary,
			_final_round: int,
			_finish_cause: String,
			_server_tick: int
		) -> void:
			match_result_seen_at[0] = Time.get_ticks_msec()
	)

	_second_socket = nakama.create_socket_from(second_client)
	var second_connect = await _second_socket.connect_async(
		second_session,
		OnlineConfigScript.SOCKET_APPEAR_ONLINE,
		OnlineConfigScript.SOCKET_CONNECT_TIMEOUT_SECONDS
	)
	if second_connect == null or second_connect.is_exception():
		_fail("P2 Realtime接続に失敗しました。", app)
		return

	lobby = app.get_child(0)
	lobby.emit_signal("ready_requested", true)
	if not await _wait_room_flag(online_session, room_code, "host_ready", true, 5000):
		_fail("P1 Readyがserverへ反映されません。", app)
		return

	var p2_ready := await _rpc_dict(
		second_client,
		second_session,
		OnlineConfigScript.FRIEND_ROOM_RPC_READY,
		{"room_code": room_code, "ready": true}
	)
	var match_id := str(p2_ready.get("current_match_id", ""))
	if p2_ready.is_empty() \
			or str(p2_ready.get("state", "")) != "IN_MATCH" \
			or match_id.is_empty():
		_fail("両者ReadyでFriend matchが生成されません。", app)
		return

	var second_join = await _second_socket.join_match_async(match_id)
	if second_join == null or second_join.is_exception() or not bool(second_join.authoritative):
		_fail("P2がFriend authoritative matchへjoinできません。", app)
		return

	if not await _wait_screen(app, "OnlineBattle", 10000):
		_fail("Friend LobbyからPreBattle経由でOnlineBattleへ進みません。", app)
		return
	if str(online_session.current_match_mode) != OnlineConfigScript.MATCH_MODE_FRIEND:
		_fail("P1 runtime match_modeがfriendではありません。", app)
		return
	if str(online_session.latest_match_snapshot.get("friend_room_code", "")) != room_code:
		_fail("Friend authoritative snapshotにroom codeがありません。", app)
		return

	var start_deadline := Time.get_ticks_msec() + 7000
	while Time.get_ticks_msec() < start_deadline and not bool(round_one_started[0]):
		await create_timer(0.02).timeout
	if not bool(round_one_started[0]):
		_fail("Friend Round 1が開始しませんでした。", app)
		return

	# P2切断後もRound 1を進め、Round 2境界timeoutで2-0 Resultまで通す。
	_second_socket.close()
	_second_socket = null
	if not await _p1_finish_friend_round(online_session, app, p1_hit_count, p1_states):
		return

	var result_event_deadline := Time.get_ticks_msec() + 26000
	while Time.get_ticks_msec() < result_event_deadline and int(match_result_seen_at[0]) <= 0:
		await create_timer(0.05).timeout
	if int(match_result_seen_at[0]) <= 0:
		_fail("Friend Match Result eventを受信できませんでした。", app)
		return
	if not await _wait_screen(app, "MatchResult", 1000):
		_fail("Friend Match Result受信後1秒以内にResult画面を表示できませんでした。", app)
		return
	var result_screen = app.get_child(0)
	if not _has_label_text(result_screen, "NO RATING CHANGE (FRIEND MATCH)"):
		_fail("Friend ResultにRating非対象表示がありません。", app)
		return
	if _has_label_text(result_screen, "PLAYER RATING") \
			or _has_label_text(result_screen, "AHOGE RATING"):
		_fail("Friend ResultにRating変動が表示されています。", app)
		return
	var rematch_button = _find_button(result_screen, "REMATCH")
	var change_character_button = _find_button(result_screen, "CHANGE CHARACTER")
	var leave_room_button = _find_button(result_screen, "LEAVE ROOM")
	if rematch_button == null or change_character_button == null or leave_room_button == null:
		_fail("Host Friend Resultの3ボタンが揃っていません。", app)
		return
	if rematch_button.get_parent() != change_character_button.get_parent() \
			or change_character_button.get_parent() != leave_room_button.get_parent() \
			or not (
				rematch_button.get_index() < change_character_button.get_index()
				and change_character_button.get_index() < leave_room_button.get_index()
			):
		_fail("Host Friend Resultのボタン順がREMATCH / CHANGE CHARACTER / LEAVE ROOMではありません。", app)
		return

	# P2 result lockも解除し、Host REMATCHが同じP2で次matchを生成できる状態にする。
	await _ack_second_result(second_client, second_session, match_id, 6000)

	result_screen.emit_signal("rematch_requested")
	if not await _wait_screen(app, "OnlineBattle", 10000):
		_fail("Host REMATCHでLobbyを挟まず次Friend Battleへ進みません。", app)
		return
	var rematch_room: Dictionary = await online_session.get_friend_room_status(room_code)
	var rematch_match_id := str(rematch_room.get("current_match_id", ""))
	if not bool(rematch_room.get("ok", false)) \
			or str(rematch_room.get("state", "")) != "IN_MATCH" \
			or rematch_match_id.is_empty() \
			or rematch_match_id == match_id \
			or str(rematch_room.get("guest_user_id", "")) != str(second_session.user_id) \
			or str(rematch_room.get("host_character_id", "")) != OnlineConfigScript.RANKED_CHARACTER_LONG_TEST \
			or str(rematch_room.get("guest_character_id", "")) != OnlineConfigScript.RANKED_CHARACTER_SHORT_TEST:
		_fail("REMATCHが同じGuest / Characterの新matchになっていません。", app)
		return

	online_session.clear_session()
	app.queue_free()
	print("AHOGE LEGEND friend gameflow smoke: PASS room=%s first=%s rematch=%s" % [room_code, match_id, rematch_match_id])
	quit(0)


func _p1_finish_friend_round(
	online_session,
	app,
	p1_hit_count: Array,
	p1_states: Array[Dictionary]
) -> bool:
	for hit_index in range(1, 6):
		var state_start := p1_states.size()
		var press: Dictionary = await online_session.send_combat_input(
			CombatInputProtocolScript.ACTION_ATTACK_PRESS
		)
		if not bool(press.get("ok", false)):
			_fail("Friend P1 ATTACK_PRESSを送信できませんでした。", app)
			return false

		var charging_deadline := Time.get_ticks_msec() + 3000
		var charging_seen := false
		while Time.get_ticks_msec() < charging_deadline:
			for index in range(state_start, p1_states.size()):
				if str(p1_states[index].get("state", "")) == "CHARGING":
					charging_seen = true
					break
			if charging_seen:
				break
			await create_timer(0.02).timeout
		if not charging_seen:
			_fail("Friend P1 CHARGINGを確認できませんでした。", app)
			return false

		var release: Dictionary = await online_session.send_combat_input(
			CombatInputProtocolScript.ACTION_ATTACK_RELEASE
		)
		if not bool(release.get("ok", false)):
			_fail("Friend P1 ATTACK_RELEASEを送信できませんでした。", app)
			return false

		var hit_deadline := Time.get_ticks_msec() + 4000
		while Time.get_ticks_msec() < hit_deadline and int(p1_hit_count[0]) < hit_index:
			await create_timer(0.02).timeout
		if int(p1_hit_count[0]) < hit_index:
			_fail("Friend P1 Hit count=%dを確認できませんでした。" % hit_index, app)
			return false

		if hit_index < 5:
			var idle_deadline := Time.get_ticks_msec() + 4000
			var idle_seen := false
			while Time.get_ticks_msec() < idle_deadline:
				for index in range(state_start, p1_states.size()):
					if str(p1_states[index].get("state", "")) == "IDLE":
						idle_seen = true
						break
				if idle_seen:
					break
				await create_timer(0.02).timeout
			if not idle_seen:
				_fail("Friend P1が次攻撃前にIDLEへ復帰しませんでした。", app)
				return false
	return true


func _wait_room_flag(
	online_session,
	room_code: String,
	key: String,
	expected: bool,
	timeout_ms: int
) -> bool:
	var deadline := Time.get_ticks_msec() + timeout_ms
	while Time.get_ticks_msec() < deadline:
		var room: Dictionary = await online_session.get_friend_room_status(room_code)
		if bool(room.get("ok", false)) and bool(room.get(key, not expected)) == expected:
			return true
		await create_timer(0.05).timeout
	return false


func _ack_second_result(client, session, match_id: String, timeout_ms: int) -> bool:
	var deadline := Time.get_ticks_msec() + timeout_ms
	while Time.get_ticks_msec() < deadline:
		var active := await _rpc_dict(
			client,
			session,
			OnlineConfigScript.ACTIVE_MATCH_RPC_GET,
			{}
		)
		if not active.is_empty() \
				and bool(active.get("active", false)) \
				and str(active.get("match_id", "")) == match_id \
				and str(active.get("state", "")) == OnlineConfigScript.ACTIVE_MATCH_STATE_RESULT_PENDING:
			var ack := await _rpc_dict(
				client,
				session,
				OnlineConfigScript.ACTIVE_MATCH_RPC_ACK,
				{"match_id": match_id}
			)
			return not ack.is_empty()
		await create_timer(0.05).timeout
	return false


func _rpc_dict(client, session, rpc_id: String, payload: Dictionary) -> Dictionary:
	var result = await client.rpc_async(session, rpc_id, JSON.stringify(payload))
	if result == null or result.is_exception():
		return {}
	var parsed = JSON.parse_string(str(result.payload))
	return parsed if parsed is Dictionary else {}


func _wait_screen(app, screen_name: String, timeout_ms: int) -> bool:
	var deadline := Time.get_ticks_msec() + timeout_ms
	while Time.get_ticks_msec() < deadline:
		if str(app.call("current_screen_name")) == screen_name:
			return true
		await create_timer(0.05).timeout
	return false


func _wait_label_text(root: Node, text: String, timeout_ms: int) -> bool:
	var deadline := Time.get_ticks_msec() + timeout_ms
	while Time.get_ticks_msec() < deadline:
		if _has_label_text(root, text):
			return true
		await create_timer(0.05).timeout
	return false


func _has_label_text(root: Node, text: String) -> bool:
	if root is Label and str(root.text).contains(text):
		return true
	for child in root.get_children():
		if _has_label_text(child, text):
			return true
	return false


func _find_button(root: Node, text: String):
	if root is Button and str(root.text) == text:
		return root
	for child in root.get_children():
		var found = _find_button(child, text)
		if found != null:
			return found
	return null


func _valid_room_code(room_code: String) -> bool:
	if room_code.length() != OnlineConfigScript.FRIEND_ROOM_CODE_LENGTH:
		return false
	for index in range(room_code.length()):
		if OnlineConfigScript.FRIEND_ROOM_CODE_CHARSET.find(room_code[index]) < 0:
			return false
	return true


func _fail(message: String, app) -> void:
	if _second_socket != null:
		_second_socket.close()
		_second_socket = null
	var online_session = get_root().get_node_or_null("OnlineSession")
	if online_session != null:
		online_session.clear_session()
	if app != null and is_instance_valid(app):
		app.queue_free()
	push_error(message)
	print("AHOGE LEGEND friend gameflow smoke: FAIL")
	quit(1)
