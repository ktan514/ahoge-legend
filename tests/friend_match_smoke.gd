extends SceneTree

const OnlineConfigScript := preload("res://src/config/online_config.gd")
const CombatInputProtocolScript := preload("res://src/online/combat_input_protocol.gd")

var _second_socket = null


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var online_session = get_root().get_node_or_null("OnlineSession")
	var nakama = get_root().get_node_or_null("Nakama")
	if online_session == null or nakama == null:
		_fail("OnlineSession / Nakama Autoloadが見つかりません。")
		return

	online_session.clear_session()

	var auth_result: Dictionary = await online_session.authenticate_local_device()
	if not bool(auth_result.get("ok", false)):
		_fail("P1 Device認証に失敗しました。")
		return
	var p1_user_id := str(auth_result.get("user_id", ""))

	var realtime_result: Dictionary = await online_session.connect_realtime_socket()
	if not bool(realtime_result.get("ok", false)):
		_fail("P1 Realtime Socket接続に失敗しました。")
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
		_fail("P2 Device認証に失敗しました。")
		return
	var p2_user_id := str(second_session.user_id)
	var p1_hit_count := [0]
	var p1_states: Array[Dictionary] = []
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

	# Room code形式、guest leave、host close後のcode無効化を先に検証する。
	var temporary_room: Dictionary = await online_session.create_friend_room()
	if not bool(temporary_room.get("ok", false)):
		_fail("検証用Friend roomを作成できませんでした。")
		return
	var temporary_code := str(temporary_room.get("room_code", ""))
	if not _valid_room_code(temporary_code):
		_fail("生成room codeが6文字の許可文字集合ではありません。")
		return
	var now_ms := int(Time.get_unix_time_from_system() * 1000.0)
	var expiry_delta := int(temporary_room.get("expires_at_unix_ms", 0)) - now_ms
	if expiry_delta < 7190000 or expiry_delta > 7210000:
		_fail("Friend roomの未使用失効時刻が約2時間後ではありません。")
		return

	var invalid_join = await second_client.rpc_async(
		second_session,
		OnlineConfigScript.FRIEND_ROOM_RPC_JOIN,
		JSON.stringify({"room_code": "OOOOOO"})
	)
	if invalid_join == null or not invalid_join.is_exception():
		_fail("禁止文字を含むroom codeが拒否されませんでした。")
		return

	var joined_temp := await _rpc_dict(
		second_client,
		second_session,
		OnlineConfigScript.FRIEND_ROOM_RPC_JOIN,
		{"room_code": temporary_code}
	)
	if joined_temp.is_empty() or str(joined_temp.get("role", "")) != "guest":
		_fail("P2が検証用Friend roomへ参加できませんでした。")
		return

	var guest_left := await _rpc_dict(
		second_client,
		second_session,
		OnlineConfigScript.FRIEND_ROOM_RPC_LEAVE,
		{"room_code": temporary_code}
	)
	if guest_left.is_empty() or str(guest_left.get("state", "")) != "WAITING":
		_fail("guest退出後にroomがWAITINGへ戻りませんでした。")
		return
	var temp_status: Dictionary = await online_session.get_friend_room_status(temporary_code)
	if not bool(temp_status.get("ok", false)) \
			or not str(temp_status.get("guest_user_id", "")).is_empty():
		_fail("guest退出後もguest slotが残っています。")
		return

	var host_closed: Dictionary = await online_session.leave_friend_room(temporary_code)
	if not bool(host_closed.get("ok", false)) or not bool(host_closed.get("closed", false)):
		_fail("hostがFriend roomを終了できませんでした。")
		return
	var closed_join = await second_client.rpc_async(
		second_session,
		OnlineConfigScript.FRIEND_ROOM_RPC_JOIN,
		JSON.stringify({"room_code": temporary_code})
	)
	if closed_join == null or not closed_join.is_exception():
		_fail("終了済みroom codeで再参加できました。")
		return

	# 実対戦用roomを作成し、2人のCharacter/ReadyからFriend matchを生成する。
	var room: Dictionary = await online_session.create_friend_room()
	if not bool(room.get("ok", false)):
		_fail("Friend roomを作成できませんでした。")
		return
	var room_code := str(room.get("room_code", ""))
	if not _valid_room_code(room_code):
		_fail("実対戦用room code形式が不正です。")
		return

	var p2_join := await _rpc_dict(
		second_client,
		second_session,
		OnlineConfigScript.FRIEND_ROOM_RPC_JOIN,
		{"room_code": room_code}
	)
	if p2_join.is_empty() \
			or str(p2_join.get("host_user_id", "")) != p1_user_id \
			or str(p2_join.get("guest_user_id", "")) != p2_user_id:
		_fail("Friend roomのhost/guestが期待値と一致しません。")
		return

	var p1_character: Dictionary = await online_session.set_friend_room_character(
		room_code,
		OnlineConfigScript.RANKED_CHARACTER_LONG_TEST
	)
	var p2_character := await _rpc_dict(
		second_client,
		second_session,
		OnlineConfigScript.FRIEND_ROOM_RPC_CHARACTER,
		{
			"room_code": room_code,
			"character_id": OnlineConfigScript.RANKED_CHARACTER_SHORT_TEST,
		}
	)
	if not bool(p1_character.get("ok", false)) or p2_character.is_empty():
		_fail("Friend roomのcharacter選択を保存できませんでした。")
		return

	var rating_p1_before := await _read_current_rating(
		online_session.client,
		online_session.session
	)
	var rating_p2_before := await _read_current_rating(second_client, second_session)
	var ahoge_before := await _read_ahoge_ranking(
		online_session.client,
		online_session.session
	)
	if rating_p1_before.is_empty() or rating_p2_before.is_empty() or ahoge_before.is_empty():
		_fail("Friend match前のRanking状態を取得できませんでした。")
		return
	var long_before := _ahoge_counts(
		ahoge_before,
		OnlineConfigScript.RANKED_CHARACTER_LONG_TEST
	)
	var short_before := _ahoge_counts(
		ahoge_before,
		OnlineConfigScript.RANKED_CHARACTER_SHORT_TEST
	)

	var p1_ready: Dictionary = await online_session.set_friend_room_ready(room_code, true)
	if not bool(p1_ready.get("ok", false)) \
			or str(p1_ready.get("state", "")) != "LOBBY" \
			or not bool(p1_ready.get("host_ready", false)):
		_fail("P1 Readyを保存できませんでした。")
		return

	var p2_ready := await _rpc_dict(
		second_client,
		second_session,
		OnlineConfigScript.FRIEND_ROOM_RPC_READY,
		{"room_code": room_code, "ready": true}
	)
	if p2_ready.is_empty() or str(p2_ready.get("state", "")) != "IN_MATCH":
		_fail("両者ReadyでFriend matchが生成されませんでした。")
		return
	var first_match_id := str(p2_ready.get("current_match_id", ""))
	if first_match_id.is_empty():
		_fail("Friend match IDがserverから返りませんでした。")
		return

	var p1_room: Dictionary = await online_session.get_friend_room_status(room_code)
	if not bool(p1_room.get("ok", false)) \
			or str(p1_room.get("current_match_id", "")) != first_match_id:
		_fail("hostからserver確定Friend match IDを取得できませんでした。")
		return

	_second_socket = nakama.create_socket_from(second_client)
	var second_connect = await _second_socket.connect_async(
		second_session,
		OnlineConfigScript.SOCKET_APPEAR_ONLINE,
		OnlineConfigScript.SOCKET_CONNECT_TIMEOUT_SECONDS
	)
	if second_connect == null or second_connect.is_exception():
		_fail("P2 Realtime Socket接続に失敗しました。")
		return

	var round_started := [false]
	var match_event := [{}]
	online_session.round_started.connect(
		func(round_number: int, _round_wins: Dictionary, _server_tick: int) -> void:
			if round_number == 1:
				round_started[0] = true
	)
	online_session.match_result.connect(
		func(
			winner_user_id: String,
			loser_user_id: String,
			_round_wins: Dictionary,
			_final_round: int,
			finish_cause: String,
			_server_tick: int
		) -> void:
			match_event[0] = {
				"winner_user_id": winner_user_id,
				"loser_user_id": loser_user_id,
				"finish_cause": finish_cause,
			}
	)

	var p1_match_join: Dictionary = await online_session.join_friend_match_from_room(p1_room)
	if not bool(p1_match_join.get("ok", false)):
		_fail("P1がFriend authoritative matchへjoinできませんでした。")
		return
	var second_join = await _second_socket.join_match_async(first_match_id)
	if second_join == null or second_join.is_exception() or not bool(second_join.authoritative):
		_fail("P2がFriend authoritative matchへjoinできませんでした。")
		return

	var active_before: Dictionary = await online_session.refresh_active_online_match()
	if not bool(active_before.get("ok", false)) 			or not bool(active_before.get("active", false)) 			or str(active_before.get("match_id", "")) != first_match_id 			or str(active_before.get("match_mode", "")) != OnlineConfigScript.MATCH_MODE_FRIEND 			or str(active_before.get("state", "")) != OnlineConfigScript.ACTIVE_MATCH_STATE_ACTIVE:
		_fail("Friend matchがserver-side active contextへ保存されていません。")
		return

	var start_deadline := Time.get_ticks_msec() + 7000
	while Time.get_ticks_msec() < start_deadline and not bool(round_started[0]):
		await create_timer(0.02).timeout
	if not bool(round_started[0]):
		_fail("Friend match Round 1が開始しませんでした。")
		return

	# P2切断後もactive Roundを進行し、P1がRound 1を終了した時点から
	# Round境界15秒timeoutでFriend Match Resultを確定する。
	_second_socket.close()
	_second_socket = null
	var disconnect_deadline := Time.get_ticks_msec() + 4000
	while Time.get_ticks_msec() < disconnect_deadline and not bool(p2_disconnected[0]):
		await create_timer(0.02).timeout
	if not bool(p2_disconnected[0]):
		_fail("Friend P2切断をserverが認識しませんでした。")
		return
	if not await _p1_finish_friend_round(online_session, p1_hit_count, p1_states):
		return

	var result_deadline := Time.get_ticks_msec() + 18000
	while Time.get_ticks_msec() < result_deadline and (match_event[0] as Dictionary).is_empty():
		await create_timer(0.05).timeout
	var first_result: Dictionary = match_event[0]
	if first_result.is_empty():
		_fail("Friend matchのDISCONNECT_TIMEOUT結果を受信できませんでした。")
		return
	if str(first_result.get("winner_user_id", "")) != p1_user_id \
			or str(first_result.get("loser_user_id", "")) != p2_user_id \
			or str(first_result.get("finish_cause", "")) != "DISCONNECT_TIMEOUT":
		_fail("Friend matchのserver authoritative結果が期待値と一致しません。")
		return

	var post_match := await _wait_room_state(
		online_session,
		room_code,
		"POST_MATCH",
		5000
	)
	if post_match.is_empty():
		_fail("Match Result後にFriend roomがPOST_MATCHへ戻りませんでした。")
		return
	if bool(post_match.get("host_ready", true)) or bool(post_match.get("guest_ready", true)):
		_fail("Friend Match終了後にReadyが解除されていません。")
		return

	# FriendはPlayer Rating / PLAYER Ranking / AHOGE LEGEND Rankingを更新しない。
	var rating_p1_after := await _read_current_rating(
		online_session.client,
		online_session.session
	)
	var rating_p2_after := await _read_current_rating(second_client, second_session)
	var ahoge_after := await _read_ahoge_ranking(
		online_session.client,
		online_session.session
	)
	if not _same_rating_record(rating_p1_before, rating_p1_after) \
			or not _same_rating_record(rating_p2_before, rating_p2_after):
		_fail("Friend matchでPlayer Rating / PLAYER Ranking値が変化しました。")
		return
	var long_after := _ahoge_counts(
		ahoge_after,
		OnlineConfigScript.RANKED_CHARACTER_LONG_TEST
	)
	var short_after := _ahoge_counts(
		ahoge_after,
		OnlineConfigScript.RANKED_CHARACTER_SHORT_TEST
	)
	if long_after != long_before or short_after != short_before:
		_fail("Friend matchでAHOGE LEGEND Rankingが変化しました。")
		return

	# 終了済みFriendへ再ログインした場合はResult再表示ではなくCharacter Selectへ戻す。
	online_session.clear_runtime_session_preserving_match()
	var reauth: Dictionary = await online_session.authenticate_local_device()
	if not bool(reauth.get("ok", false)) or str(reauth.get("user_id", "")) != p1_user_id:
		_fail("Friend終了後のP1再ログインに失敗しました。")
		return
	var resumed: Dictionary = await online_session.resume_active_match_after_login()
	if not bool(resumed.get("ok", false)) \
			or str(resumed.get("destination", "")) != "friend_character_select":
		_fail("終了済みFriend matchの復帰先がfriend_character_selectではありません。")
		return
	var snapshot: Dictionary = resumed.get("snapshot", {})
	if not bool(snapshot.get("match_finished", false)) \
			or str(snapshot.get("match_mode", "")) != "friend":
		_fail("終了済みFriend snapshotが不正です。")
		return

	var blocked_rematch: Dictionary = await online_session.set_friend_room_ready(
		room_code,
		true
	)
	if bool(blocked_rematch.get("ok", false)) \
			or str(blocked_rematch.get("step", "")) != "unresolved_match":
		_fail("終了済みFriendの遷移確定前に再戦Readyできました。")
		return

	var p1_ack: Dictionary = await online_session.acknowledge_active_match_destination()
	if not bool(p1_ack.get("ok", false)):
		_fail("終了済みFriendのP1 server contextを解除できませんでした。")
		return
	var p2_ack = await second_client.rpc_async(
		second_session,
		OnlineConfigScript.ACTIVE_MATCH_RPC_ACK,
		JSON.stringify({"match_id": first_match_id})
	)
	if p2_ack == null or p2_ack.is_exception():
		_fail("終了済みFriendのP2 server contextを解除できませんでした。")
		return

	# 同じroom・同じcharacterを維持し、両者が再度Readyすると新しいmatchを生成する。
	var rematch_p1: Dictionary = await online_session.set_friend_room_ready(room_code, true)
	if not bool(rematch_p1.get("ok", false)):
		_fail("P1が再戦Readyできませんでした。")
		return
	var rematch_p2 := await _rpc_dict(
		second_client,
		second_session,
		OnlineConfigScript.FRIEND_ROOM_RPC_READY,
		{"room_code": room_code, "ready": true}
	)
	var second_match_id := str(rematch_p2.get("current_match_id", ""))
	if rematch_p2.is_empty() \
			or str(rematch_p2.get("state", "")) != "IN_MATCH" \
			or second_match_id.is_empty() \
			or second_match_id == first_match_id:
		_fail("同じFriend roomで再戦用の新しいmatchを生成できませんでした。")
		return
	if int(rematch_p2.get("match_generation", 0)) != int(post_match.get("match_generation", 0)) + 1:
		_fail("Friend rematchのmatch_generationが増加していません。")
		return

	online_session.clear_session()
	print(
		"AHOGE LEGEND friend match smoke: PASS room=%s first=%s rematch=%s"
		% [room_code, first_match_id, second_match_id]
	)
	quit(0)


func _p1_finish_friend_round(online_session, p1_hit_count: Array, p1_states: Array[Dictionary]) -> bool:
	for hit_index in range(1, 6):
		var state_start := p1_states.size()
		var press: Dictionary = await online_session.send_combat_input(
			CombatInputProtocolScript.ACTION_ATTACK_PRESS
		)
		if not bool(press.get("ok", false)):
			_fail("Friend P1 ATTACK_PRESSを送信できませんでした。")
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
			_fail("Friend P1 CHARGINGを確認できませんでした。")
			return false

		var release: Dictionary = await online_session.send_combat_input(
			CombatInputProtocolScript.ACTION_ATTACK_RELEASE
		)
		if not bool(release.get("ok", false)):
			_fail("Friend P1 ATTACK_RELEASEを送信できませんでした。")
			return false

		var hit_deadline := Time.get_ticks_msec() + 4000
		while Time.get_ticks_msec() < hit_deadline and int(p1_hit_count[0]) < hit_index:
			await create_timer(0.02).timeout
		if int(p1_hit_count[0]) < hit_index:
			_fail("Friend P1 authoritative Hit count=%dを確認できませんでした。" % hit_index)
			return false

		if hit_index < 5:
			var idle_deadline := Time.get_ticks_msec() + 4000
			var idle_seen := false
			while Time.get_ticks_msec() < idle_deadline:
				for index in range(state_start, p1_states.size()):
					if str(p1_states[index].get("state", "")) == "IDLE":
						idle_seen = true
				if idle_seen:
					break
				await create_timer(0.02).timeout
			if not idle_seen:
				_fail("Friend P1が次の攻撃前にIDLEへ復帰しませんでした。")
				return false
	return true

func _rpc_dict(client, session, rpc_id: String, payload: Dictionary) -> Dictionary:
	var result = await client.rpc_async(session, rpc_id, JSON.stringify(payload))
	if result == null or result.is_exception():
		return {}
	var parsed = JSON.parse_string(str(result.payload))
	if not parsed is Dictionary:
		return {}
	return parsed


func _valid_room_code(room_code: String) -> bool:
	if room_code.length() != OnlineConfigScript.FRIEND_ROOM_CODE_LENGTH:
		return false
	for index in range(room_code.length()):
		if OnlineConfigScript.FRIEND_ROOM_CODE_CHARSET.find(room_code[index]) < 0:
			return false
	return true


func _read_current_rating(client, session) -> Dictionary:
	var result = await client.rpc_async(session, "ahoge_current_rating")
	if result == null or result.is_exception():
		return {}
	var parsed = JSON.parse_string(str(result.payload))
	return parsed if parsed is Dictionary else {}


func _read_ahoge_ranking(client, session) -> Dictionary:
	var result = await client.rpc_async(
		session,
		"ahoge_legend_ranking",
		JSON.stringify({"limit": 100})
	)
	if result == null or result.is_exception():
		return {}
	var parsed = JSON.parse_string(str(result.payload))
	return parsed if parsed is Dictionary else {}


func _same_rating_record(before: Dictionary, after: Dictionary) -> bool:
	for key in ["rating", "wins", "losses", "season_id"]:
		if str(before.get(key, "")) != str(after.get(key, "")):
			return false
	return true


func _ahoge_counts(ranking: Dictionary, character_id: String) -> Dictionary:
	var records = ranking.get("records", [])
	if not records is Array:
		return {"wins": 0, "matches": 0}
	for record in records:
		if record is Dictionary and str(record.get("character_id", "")) == character_id:
			return {
				"wins": int(record.get("total_match_wins", 0)),
				"matches": int(record.get("total_ranked_matches", 0)),
			}
	return {"wins": 0, "matches": 0}


func _wait_room_state(
	online_session,
	room_code: String,
	expected_state: String,
	timeout_ms: int
) -> Dictionary:
	var deadline := Time.get_ticks_msec() + timeout_ms
	while Time.get_ticks_msec() < deadline:
		var status: Dictionary = await online_session.get_friend_room_status(room_code)
		if bool(status.get("ok", false)) and str(status.get("state", "")) == expected_state:
			return status
		await create_timer(0.05).timeout
	return {}


func _fail(message: String) -> void:
	if _second_socket != null:
		_second_socket.close()
	var online_session = get_root().get_node_or_null("OnlineSession")
	if online_session != null:
		online_session.clear_session()
	push_error(message)
	print("AHOGE LEGEND friend match smoke: FAIL")
	quit(1)
