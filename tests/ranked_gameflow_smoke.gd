extends SceneTree

const AppRootScene := preload("res://scenes/app/AppRoot.tscn")
const OnlineConfigScript := preload("res://src/config/online_config.gd")
const CombatInputProtocolScript := preload("res://src/online/combat_input_protocol.gd")

var _second_socket = null
var _second_ticket: String = ""
var _second_match_id: String = ""
var _second_failure: String = ""


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
		_fail("起動時のserver状態確認後にTopMenuが表示されません。", app)
		return

	var top = app.get_child(0)
	top.emit_signal("online_battle_requested")
	if not await _wait_screen(app, "BattleModeSelect", 5000):
		_fail("ONLINE BATTLEからserver状態確認後にBattleModeSelectへ遷移しません。", app)
		return

	var mode_screen = app.get_child(0)
	mode_screen.emit_signal("ranked_requested")
	if not await _wait_screen(app, "CharacterSelect", 6000):
		_fail("RANKED MATCHからCharacterSelectへ遷移しません。", app)
		return
	if not online_session.is_authenticated() or not online_session.is_realtime_connected():
		_fail("Ranked導線開始時に認証 / Realtime接続が成立していません。", app)
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
	var p2_user_id := str(second_session.user_id)
	var p1_hit_count := [0]
	var p1_states: Array[Dictionary] = []
	var p1_user_id := str(online_session.session.user_id)
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

	_second_socket = nakama.create_socket_from(second_client)
	_second_socket.received_matchmaker_matched.connect(_on_second_matchmaker_matched)
	var second_connect = await _second_socket.connect_async(
		second_session,
		OnlineConfigScript.SOCKET_APPEAR_ONLINE,
		OnlineConfigScript.SOCKET_CONNECT_TIMEOUT_SECONDS
	)
	if second_connect == null or second_connect.is_exception():
		_fail("P2 Realtime接続に失敗しました。", app)
		return

	var character_select = app.get_child(0)
	character_select.emit_signal(
		"ranked_character_selected",
		OnlineConfigScript.RANKED_CHARACTER_LONG_TEST
	)
	if not await _wait_screen(app, "RankedMatching", 5000):
		_fail("CharacterSelectからRankedMatchingへ遷移しません。", app)
		return

	var rating: Dictionary = await online_session.get_current_rating()
	if not bool(rating.get("ok", false)):
		_fail("P1 Ratingを取得できませんでした。", app)
		return
	var rating_value := int(rating.get("rating", 1500))
	var ticket_result = await _second_socket.add_matchmaker_async(
		online_session.build_ranked_matchmaker_query(rating_value),
		OnlineConfigScript.RANKED_MATCHMAKER_MIN_COUNT,
		OnlineConfigScript.RANKED_MATCHMAKER_MAX_COUNT,
		{
			"mode": OnlineConfigScript.RANKED_MATCHMAKER_MODE,
			"character_id": OnlineConfigScript.RANKED_CHARACTER_SHORT_TEST,
		},
		{"rating": float(rating_value)}
	)
	if ticket_result == null or ticket_result.is_exception():
		_fail("P2 Ranked Matchmakerを開始できませんでした。", app)
		return
	_second_ticket = str(ticket_result.ticket)

	if not await _wait_screen(app, "PreBattleDialogue", 40000):
		_fail("match成立後にPreBattleDialogueへ遷移しません。", app)
		return
	if not _second_failure.is_empty():
		_fail(_second_failure, app)
		return
	if _second_match_id.is_empty():
		_fail("P2がauthoritative matchへjoinしていません。", app)
		return

	if not await _wait_screen(app, "OnlineBattle", 5000):
		_fail("PreBattleDialogueからOnlineBattleへ遷移しません。", app)
		return
	if online_session.latest_match_snapshot.is_empty():
		_fail("通常join時のauthoritative snapshotを保持できていません。", app)
		return
	if str(online_session.latest_match_snapshot.get("match_mode", "")) != "ranked":
		_fail("Ranked初期snapshotのmatch_modeが不正です。", app)
		return

	var third_client = nakama.create_client(
		OnlineConfigScript.SERVER_KEY,
		OnlineConfigScript.HOST,
		OnlineConfigScript.PORT,
		OnlineConfigScript.SCHEME,
		OnlineConfigScript.CLIENT_TIMEOUT_SECONDS,
		OnlineConfigScript.CLIENT_LOG_LEVEL
	)
	var third_session = await third_client.authenticate_device_async(
		Crypto.new().generate_random_bytes(32).hex_encode(),
		null,
		true
	)
	if third_session == null or third_session.is_exception():
		_fail("P3 Device認証に失敗しました。", app)
		return
	var third_active_rpc = await third_client.rpc_async(
		third_session,
		OnlineConfigScript.ACTIVE_MATCH_RPC_GET
	)
	if third_active_rpc == null or third_active_rpc.is_exception():
		_fail("P3 active match確認に失敗しました。", app)
		return
	var third_active = JSON.parse_string(str(third_active_rpc.payload))
	if not third_active is Dictionary or bool((third_active as Dictionary).get("active", false)):
		_fail("P1/P2の未解決matchが別user P3へ混入しています。", app)
		return

	# runtime接続を失っても未解決match lockを保持し、TOPのONLINE BATTLE再選択で
	# 新規matchmakingへ行かず元のauthoritative matchへ強制復帰する。
	var original_match_id := str(online_session.current_match_id)
	online_session.clear_runtime_session_preserving_match()
	app.call("_show_top_menu")
	await process_frame
	if str(app.call("current_screen_name")) != "TopMenu":
		_fail("未解決match検証用にTopMenuへ戻れませんでした。", app)
		return
	var forced_resume_top = app.get_child(0)
	forced_resume_top.emit_signal("online_battle_requested")
	if not await _wait_screen(app, "OnlineBattle", 7000):
		_fail("TOPのONLINE BATTLE再選択で元の対戦へ強制復帰しません。", app)
		return
	if str(online_session.current_match_id) != original_match_id:
		_fail("強制復帰後のmatch IDが元のauthoritative matchと一致しません。", app)
		return

	# P2切断後もactive Roundは進行する。P1がRound 1を終了させた時点から
	# 15秒のRound境界復帰待機を開始し、timeoutでserver authoritativeに勝敗確定する。
	_second_socket.close()
	_second_socket = null
	if not await _p1_finish_round(online_session, app, p1_hit_count, p1_states):
		return

	if not await _wait_screen(app, "MatchResult", 25000):
		_fail("authoritative Match ResultからUI-11へ遷移しません。", app)
		return
	if not await _wait_no_active_match(online_session, 6000):
		_fail("UI-11表示確定後もserver-side active matchが残っています。", app)
		return
	if not online_session.can_start_new_online_match():
		_fail("UI-11表示確定後もruntime lockが残っています。", app)
		return

	var result_screen = app.get_child(0)
	if _has_button_text(result_screen, "REMATCH"):
		_fail("Ranked ResultにREMATCHが表示されています。", app)
		return
	if not _has_button_text(result_screen, "NEXT MATCH"):
		_fail("Ranked ResultにNEXT MATCHがありません。", app)
		return

	result_screen.emit_signal("next_match_requested")
	if not await _wait_screen(app, "CharacterSelect", 3000):
		_fail("NEXT MATCHでCharacterSelectへ戻りません。", app)
		return

	online_session.clear_session()
	app.queue_free()
	print("AHOGE LEGEND ranked gameflow smoke: PASS")
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
	_second_match_id = str(join_result.match_id)


func _wait_screen(app, screen_name: String, timeout_ms: int) -> bool:
	var deadline := Time.get_ticks_msec() + timeout_ms
	while Time.get_ticks_msec() < deadline:
		if not _second_failure.is_empty():
			return false
		if str(app.call("current_screen_name")) == screen_name:
			return true
		await create_timer(0.05).timeout
	return false


func _p1_finish_round(online_session, app, p1_hit_count: Array, p1_states: Array[Dictionary]) -> bool:
	for hit_index in range(1, 6):
		var state_start := p1_states.size()
		var press: Dictionary = await online_session.send_combat_input(
			CombatInputProtocolScript.ACTION_ATTACK_PRESS
		)
		if not bool(press.get("ok", false)):
			_fail("P1 ATTACK_PRESSを送信できませんでした。", app)
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
			_fail("P1 CHARGINGを確認できませんでした。", app)
			return false

		var release: Dictionary = await online_session.send_combat_input(
			CombatInputProtocolScript.ACTION_ATTACK_RELEASE
		)
		if not bool(release.get("ok", false)):
			_fail("P1 ATTACK_RELEASEを送信できませんでした。", app)
			return false

		var hit_deadline := Time.get_ticks_msec() + 4000
		while Time.get_ticks_msec() < hit_deadline and int(p1_hit_count[0]) < hit_index:
			await create_timer(0.02).timeout
		if int(p1_hit_count[0]) < hit_index:
			_fail("P1 authoritative Hit count=%dを確認できませんでした。" % hit_index, app)
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
				_fail("P1が次の攻撃前にIDLEへ復帰しませんでした。", app)
				return false
	return true

func _wait_no_active_match(online_session, timeout_ms: int) -> bool:
	var deadline := Time.get_ticks_msec() + timeout_ms
	while Time.get_ticks_msec() < deadline:
		var active: Dictionary = await online_session.refresh_active_online_match()
		if bool(active.get("ok", false)) and not bool(active.get("active", false)):
			return true
		await create_timer(0.05).timeout
	return false


func _has_button_text(root: Node, text: String) -> bool:
	if root is Button and str(root.text) == text:
		return true
	for child in root.get_children():
		if _has_button_text(child, text):
			return true
	return false


func _fail(message: String, app) -> void:
	if _second_socket != null:
		_second_socket.close()
	var online_session = get_root().get_node_or_null("OnlineSession")
	if online_session != null:
		online_session.clear_session()
	if app != null:
		app.queue_free()
	push_error(message)
	print("AHOGE LEGEND ranked gameflow smoke: FAIL")
	quit(1)
