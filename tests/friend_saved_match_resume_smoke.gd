extends SceneTree

const AppRootScene := preload("res://scenes/app/AppRoot.tscn")
const OnlineConfigScript := preload("res://src/config/online_config.gd")
const CombatInputProtocolScript := preload("res://src/online/combat_input_protocol.gd")

var _host_socket = null


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var online_session = get_root().get_node_or_null("OnlineSession")
	var nakama = get_root().get_node_or_null("Nakama")
	if online_session == null or nakama == null:
		_fail("OnlineSession / Nakama Autoloadが見つかりません。")
		return

	online_session.clear_session()

	var guest_auth: Dictionary = await online_session.authenticate_local_device()
	if not bool(guest_auth.get("ok", false)):
		_fail("P2 Device認証に失敗しました。")
		return
	var guest_user_id := str(guest_auth.get("user_id", ""))

	var guest_connect: Dictionary = await online_session.connect_realtime_socket()
	if not bool(guest_connect.get("ok", false)):
		_fail("P2 Realtime接続に失敗しました。")
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
		_fail("P1 Device認証に失敗しました。")
		return

	var host_room := await _rpc_dict(
		host_client,
		host_session,
		OnlineConfigScript.FRIEND_ROOM_RPC_CREATE,
		{}
	)
	var room_code := str(host_room.get("room_code", ""))
	if room_code.length() != OnlineConfigScript.FRIEND_ROOM_CODE_LENGTH:
		_fail("P1 Friend roomを作成できませんでした。")
		return

	var guest_room: Dictionary = await online_session.join_friend_room(room_code)
	if not bool(guest_room.get("ok", false)) or str(guest_room.get("role", "")) != "guest":
		_fail("P2がFriend roomへGuest参加できませんでした。")
		return

	var host_character := await _rpc_dict(
		host_client,
		host_session,
		OnlineConfigScript.FRIEND_ROOM_RPC_CHARACTER,
		{
			"room_code": room_code,
			"character_id": OnlineConfigScript.RANKED_CHARACTER_LONG_TEST,
		}
	)
	if host_character.is_empty():
		_fail("P1 Characterを保存できませんでした。")
		return

	var guest_character: Dictionary = await online_session.set_friend_room_character(
		room_code,
		OnlineConfigScript.RANKED_CHARACTER_SHORT_TEST
	)
	if not bool(guest_character.get("ok", false)):
		_fail("P2 Characterを保存できませんでした。")
		return

	_host_socket = nakama.create_socket_from(host_client)
	var host_connect = await _host_socket.connect_async(
		host_session,
		OnlineConfigScript.SOCKET_APPEAR_ONLINE,
		OnlineConfigScript.SOCKET_CONNECT_TIMEOUT_SECONDS
	)
	if host_connect == null or host_connect.is_exception():
		_fail("P1 Realtime接続に失敗しました。")
		return

	var host_ready := await _rpc_dict(
		host_client,
		host_session,
		OnlineConfigScript.FRIEND_ROOM_RPC_READY,
		{"room_code": room_code, "ready": true}
	)
	if host_ready.is_empty():
		_fail("P1 Readyを保存できませんでした。")
		return

	var started: Dictionary = await online_session.set_friend_room_ready(room_code, true)
	var match_id := str(started.get("current_match_id", ""))
	if not bool(started.get("ok", false)) \
			or str(started.get("state", "")) != "IN_MATCH" \
			or match_id.is_empty():
		_fail("両者ReadyでFriend matchが生成されませんでした。")
		return

	var host_join = await _host_socket.join_match_async(match_id)
	if host_join == null or host_join.is_exception() or not bool(host_join.authoritative):
		_fail("P1がFriend authoritative matchへjoinできませんでした。")
		return

	var guest_join: Dictionary = await online_session.join_friend_match_from_room(started)
	if not bool(guest_join.get("ok", false)):
		_fail("P2がFriend authoritative matchへjoinできませんでした。")
		return

	var initial_snapshot := await _wait_friend_snapshot(online_session, room_code, 7000)
	if initial_snapshot.is_empty():
		_fail("P2がFriend MATCH_SNAPSHOTを受信できませんでした。")
		return

	var active_before: Dictionary = await online_session.refresh_active_online_match()
	if not bool(active_before.get("ok", false)) \
			or not bool(active_before.get("active", false)) \
			or str(active_before.get("match_id", "")) != match_id \
			or str(active_before.get("match_mode", "")) != OnlineConfigScript.MATCH_MODE_FRIEND:
		_fail("P2のserver-side active Friend matchが保存されていません。")
		return

	# アプリ再起動相当。AppRoot起動時に同じDevice IDで再認証し、
	# ONLINE BATTLEの新規導線へ入る前に元Friend Battleへ自動復帰する。
	online_session.clear_runtime_session_preserving_match()
	var resumed_app = AppRootScene.instantiate()
	get_root().add_child(resumed_app)
	if not await _wait_screen(resumed_app, "OnlineBattle", 15000):
		_fail("P2アプリ再起動後に元Friend Battleへ自動復帰しませんでした。")
		return
	if online_session.session == null or str(online_session.session.user_id) != guest_user_id:
		_fail("P2再起動後のNakama user_idが変化しました。")
		return
	if str(online_session.current_match_id) != match_id \
			or str(online_session.current_match_mode) != OnlineConfigScript.MATCH_MODE_FRIEND:
		_fail("P2再起動後のruntime matchが元Friend matchと一致しません。")
		return
	var resumed_snapshot: Dictionary = online_session.latest_match_snapshot
	if str(resumed_snapshot.get("friend_room_code", "")) != room_code:
		_fail("P2再起動後のFriend snapshotから元roomを復元できませんでした。")
		return

	# 未解決Friend matchを持つ同一userは新しいroomを開始できない。
	var forbidden: Dictionary = await online_session.create_friend_room()
	if bool(forbidden.get("ok", false)):
		_fail("未解決Friend matchがあるP2で新しいFriend roomを作成できてしまいました。")
		return

	resumed_app.queue_free()
	await process_frame
	if not await _wait_round_ready(online_session, 5000):
		_fail("P2復帰後に元Friend Roundを再開できませんでした。")
		return

	# 元P1を切断し、P2の通常攻撃5Hit + Round境界timeoutでserver Resultまで進める。
	var guest_hit_count := [0]
	var guest_states: Array[Dictionary] = []
	var finished_result := [{}]
	online_session.round_hit_count_changed.connect(
		func(user_id: String, hit_count: int, _server_tick: int, _input_sequence: int) -> void:
			if user_id == guest_user_id:
				guest_hit_count[0] = hit_count
	)
	online_session.combat_state_changed.connect(
		func(user_id: String, state_name: String, _server_tick: int, _charge_ratio: float) -> void:
			if user_id == guest_user_id:
				guest_states.append({"state": state_name})
	)
	online_session.match_result.connect(
		func(
			winner_user_id: String,
			_loser_user_id: String,
			_round_wins: Dictionary,
			_final_round: int,
			finish_cause: String,
			_server_tick: int
		) -> void:
			finished_result[0] = {
				"winner_user_id": winner_user_id,
				"finish_cause": finish_cause,
			}
	)

	if _host_socket != null:
		_host_socket.close()
		_host_socket = null

	if not await _finish_round(online_session, guest_hit_count, guest_states):
		return

	var finish_deadline := Time.get_ticks_msec() + 24000
	while Time.get_ticks_msec() < finish_deadline and (finished_result[0] as Dictionary).is_empty():
		await create_timer(0.05).timeout
	if (finished_result[0] as Dictionary).is_empty():
		_fail("P1切断後にFriend Match Resultへ到達しませんでした。")
		return
	if str((finished_result[0] as Dictionary).get("winner_user_id", "")) != guest_user_id:
		_fail("Friend Match ResultのwinnerがP2ではありません。")
		return

	var pending := await _wait_active_match_state(
		online_session,
		OnlineConfigScript.ACTIVE_MATCH_STATE_RESULT_PENDING,
		5000
	)
	if pending.is_empty():
		_fail("P2 Friend resultがRESULT_PENDINGへ遷移しませんでした。")
		return

	# 終了済み状態でも同じDevice IDで再起動する。
	# AppRootはRESULT_PENDINGをserver snapshotから解決し、ack後に元roomのCharacter Selectへ戻す。
	online_session.clear_runtime_session_preserving_match()
	var finished_app = AppRootScene.instantiate()
	get_root().add_child(finished_app)
	if not await _wait_screen(finished_app, "CharacterSelect", 15000):
		_fail("終了済みFriend matchのP2再起動後に元room Character Selectへ復帰しませんでした。")
		return
	if online_session.session == null or str(online_session.session.user_id) != guest_user_id:
		_fail("終了済みFriend match後のP2再認証でuser_idが変化しました。")
		return
	var active_after_app: Dictionary = await online_session.refresh_active_online_match()
	if not bool(active_after_app.get("ok", false)) or bool(active_after_app.get("active", false)):
		_fail("Friend Result復帰後もP2のactive match lockが残っています。")
		return

	finished_app.queue_free()
	await process_frame

	var room_after: Dictionary = await online_session.get_friend_room_status(room_code)
	if not bool(room_after.get("ok", false)) \
			or str(room_after.get("role", "")) != "guest":
		_fail("P2再起動後に元Friend roomのGuest membershipを復元できませんでした。")
		return

	# 同じP2 userの再JOINは満員扱いせず既存Guestとして返す。
	var same_guest_join: Dictionary = await online_session.join_friend_room(room_code)
	if not bool(same_guest_join.get("ok", false)) \
			or str(same_guest_join.get("role", "")) != "guest":
		_fail("同じP2 userの再JOINが既存Guestとして扱われませんでした。")
		return

	var guest_leave: Dictionary = await online_session.leave_friend_room(room_code)
	if not bool(guest_leave.get("ok", false)):
		_fail("P2をFriend roomから退出できませんでした。")
		return

	await _ack_host_result(host_client, host_session, match_id, 5000)
	var host_leave := await _rpc_dict(
		host_client,
		host_session,
		OnlineConfigScript.FRIEND_ROOM_RPC_LEAVE,
		{"room_code": room_code}
	)
	if not bool(host_leave.get("closed", false)):
		_fail("P1 Friend roomをcleanupできませんでした。")
		return

	online_session.clear_session()
	print(
		"AHOGE LEGEND friend saved match resume smoke: PASS room=%s match=%s guest=%s"
		% [room_code, match_id, guest_user_id]
	)
	quit(0)


func _wait_screen(app, screen_name: String, timeout_ms: int) -> bool:
	var deadline := Time.get_ticks_msec() + timeout_ms
	while Time.get_ticks_msec() < deadline:
		if is_instance_valid(app) and str(app.call("current_screen_name")) == screen_name:
			return true
		await create_timer(0.05).timeout
	return false


func _wait_round_ready(online_session, timeout_ms: int) -> bool:
	var deadline := Time.get_ticks_msec() + timeout_ms
	while Time.get_ticks_msec() < deadline:
		var snapshot: Dictionary = online_session.latest_match_snapshot
		if not snapshot.is_empty() \
				and not bool(snapshot.get("match_finished", false)) \
				and not bool(snapshot.get("round_finished", false)) \
				and not bool(snapshot.get("round_countdown_active", false)):
			return true
		await create_timer(0.05).timeout
	return false


func _wait_friend_snapshot(online_session, room_code: String, timeout_ms: int) -> Dictionary:
	var deadline := Time.get_ticks_msec() + timeout_ms
	while Time.get_ticks_msec() < deadline:
		var snapshot: Dictionary = online_session.latest_match_snapshot
		if str(snapshot.get("match_mode", "")) == OnlineConfigScript.MATCH_MODE_FRIEND \
				and str(snapshot.get("friend_room_code", "")) == room_code:
			return snapshot.duplicate(true)
		await create_timer(0.05).timeout
	return {}


func _finish_round(
	online_session,
	hit_count: Array,
	states: Array[Dictionary]
) -> bool:
	for hit_index in range(1, 6):
		var state_start := states.size()
		var press: Dictionary = await online_session.send_combat_input(
			CombatInputProtocolScript.ACTION_ATTACK_PRESS
		)
		if not bool(press.get("ok", false)):
			_fail("P2 ATTACK_PRESSを送信できませんでした。")
			return false

		var charging_deadline := Time.get_ticks_msec() + 3000
		var charging_seen := false
		while Time.get_ticks_msec() < charging_deadline:
			for index in range(state_start, states.size()):
				if str(states[index].get("state", "")) == "CHARGING":
					charging_seen = true
					break
			if charging_seen:
				break
			await create_timer(0.02).timeout
		if not charging_seen:
			_fail("P2 CHARGINGを確認できませんでした。")
			return false

		var release: Dictionary = await online_session.send_combat_input(
			CombatInputProtocolScript.ACTION_ATTACK_RELEASE
		)
		if not bool(release.get("ok", false)):
			_fail("P2 ATTACK_RELEASEを送信できませんでした。")
			return false

		var hit_deadline := Time.get_ticks_msec() + 4000
		while Time.get_ticks_msec() < hit_deadline and int(hit_count[0]) < hit_index:
			await create_timer(0.02).timeout
		if int(hit_count[0]) < hit_index:
			_fail("P2 authoritative Hit count=%dを確認できませんでした。" % hit_index)
			return false

		if hit_index < 5:
			var idle_deadline := Time.get_ticks_msec() + 4000
			var idle_seen := false
			while Time.get_ticks_msec() < idle_deadline:
				for index in range(state_start, states.size()):
					if str(states[index].get("state", "")) == "IDLE":
						idle_seen = true
						break
				if idle_seen:
					break
				await create_timer(0.02).timeout
			if not idle_seen:
				_fail("P2が次攻撃前にIDLEへ復帰しませんでした。")
				return false
	return true


func _wait_active_match_state(
	online_session,
	state_name: String,
	timeout_ms: int
) -> Dictionary:
	var deadline := Time.get_ticks_msec() + timeout_ms
	while Time.get_ticks_msec() < deadline:
		var active: Dictionary = await online_session.refresh_active_online_match()
		if bool(active.get("ok", false)) \
				and bool(active.get("active", false)) \
				and str(active.get("state", "")) == state_name:
			return active
		await create_timer(0.05).timeout
	return {}


func _ack_host_result(client, session, match_id: String, timeout_ms: int) -> bool:
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


func _fail(message: String) -> void:
	if _host_socket != null:
		_host_socket.close()
		_host_socket = null
	var online_session = get_root().get_node_or_null("OnlineSession")
	if online_session != null:
		online_session.clear_session()
	push_error(message)
	print("AHOGE LEGEND friend saved match resume smoke: FAIL")
	quit(1)
