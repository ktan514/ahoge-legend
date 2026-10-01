extends Control

const OnlineConfigScript := preload("res://src/config/online_config.gd")
const TOP_MENU_SCENE := preload("res://scenes/screens/top_menu/TopMenu.tscn")
const SETTINGS_SCENE := preload("res://scenes/screens/settings/Settings.tscn")
const SettingsStoreScript := preload("res://src/settings/settings_store.gd")
const BATTLE_MODE_SCENE := preload("res://scenes/screens/battle_mode/BattleModeSelect.tscn")
const CHARACTER_SELECT_SCENE := preload("res://scenes/screens/character_select/CharacterSelect.tscn")
const RANKED_MATCHING_SCENE := preload("res://scenes/screens/ranked_matching/RankedMatching.tscn")
const PRE_BATTLE_SCENE := preload("res://scenes/overlays/PreBattleDialogue.tscn")
const ONLINE_BATTLE_SCENE := preload("res://scenes/screens/battle/OnlineBattle.tscn")
const BATTLE_SCENE := preload("res://scenes/screens/battle/Battle.tscn")
const M1_BATTLE_SCENE := preload("res://scenes/screens/battle/BattleM1Debug.tscn")
const MATCH_RESULT_SCENE := preload("res://scenes/screens/result/MatchResult.tscn")
const RANKING_SCENE := preload("res://scenes/screens/ranking/Ranking.tscn")
const FRIEND_MATCH_MENU_SCENE := preload("res://scenes/screens/friend_match/FriendMatchMenu.tscn")
const FRIEND_ROOM_JOIN_SCENE := preload("res://scenes/screens/friend_room_join/FriendRoomJoin.tscn")
const FRIEND_ROOM_LOBBY_SCENE := preload("res://scenes/screens/friend_room_lobby/FriendRoomLobby.tscn")

var _online_session = null
var _settings_store = null

var _current_screen: Control
var _last_player_one_id: String = "LONG_TEST"
var _last_player_two_id: String = "SHORT_TEST"
var _ranked_character_id: String = "LONG_TEST"
var _ranked_rating_before: Dictionary = {}
var _friend_room_code: String = ""
var _friend_room: Dictionary = {}
var _friend_last_role: String = ""
var _friend_character_id: String = "LONG_TEST"
var _friend_join_in_progress: bool = false
var _friend_refresh_in_progress: bool = false
var _m1_direct_mode: bool = false


func _ready() -> void:
	_online_session = get_node("/root/OnlineSession")
	var settings_path := OS.get_environment("AHOGE_SETTINGS_PATH")
	_settings_store = SettingsStoreScript.new(settings_path)
	_settings_store.load_and_apply()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_m1_direct_mode = OS.get_cmdline_user_args().has("--m1-battle")
	if _m1_direct_mode:
		_show_m1_authoritative_battle()
		return

	_show_loading("CHECKING ONLINE STATE...")
	call_deferred("_initialize_online_state")


func _initialize_online_state() -> void:
	if not _online_session.is_authenticated():
		var auth_result: Dictionary = await _online_session.authenticate_local_device()
		if not bool(auth_result.get("ok", false)):
			_show_top_menu()
			return

	var active: Dictionary = await _online_session.refresh_active_online_match()
	if not bool(active.get("ok", false)):
		_show_top_menu()
		return
	if bool(active.get("active", false)):
		await _force_resume_unresolved_online_match()
		return
	_show_top_menu()


func _show_top_menu() -> void:
	var screen = _replace_screen(TOP_MENU_SCENE)
	screen.connect("local_test_requested", Callable(self, "_show_local_character_select"))
	screen.connect("online_battle_requested", Callable(self, "_on_online_battle_requested"))
	screen.connect("ranking_requested", Callable(self, "_show_ranking").bind("player"))
	screen.connect("settings_requested", Callable(self, "_show_settings"))
	screen.connect("exit_requested", Callable(self, "_on_exit_requested"))


func _show_settings() -> void:
	var screen = SETTINGS_SCENE.instantiate()
	screen.call(
		"configure",
		_settings_store.load_settings(),
		_settings_store.defaults()
	)
	_replace_screen_instance(screen)
	screen.connect("apply_requested", Callable(self, "_apply_settings").bind(screen))
	screen.connect("back_requested", Callable(self, "_show_top_menu"))


func _apply_settings(settings: Dictionary, screen: Control) -> void:
	if not is_instance_valid(screen) or _current_screen != screen:
		return
	var result: Dictionary = _settings_store.apply_and_save(settings)
	if not is_instance_valid(screen) or _current_screen != screen:
		return
	if not bool(result.get("ok", false)):
		screen.call("set_status", "設定を保存できませんでした。")
		return
	screen.call("set_status", "APPLIED")


func _show_ranking(tab: String = "player") -> void:
	_show_loading("LOADING RANKING...")

	if not _online_session.is_authenticated():
		var auth_result: Dictionary = await _online_session.authenticate_local_device()
		if not bool(auth_result.get("ok", false)):
			_show_ranking_response(tab, {
				"ok": false,
				"message": str(auth_result.get("message", "認証に失敗しました。")),
			})
			return

	var season: Dictionary = await _online_session.get_season_metadata()
	if not bool(season.get("ok", false)):
		_show_ranking_response(tab, season)
		return

	var season_id := str(season.get("season_id", ""))
	var response: Dictionary
	if tab == "ahoge":
		response = await _online_session.get_ahoge_legend_ranking(
			OnlineConfigScript.RANKING_DEFAULT_LIMIT,
			season_id
		)
	else:
		response = await _online_session.get_player_ranking(
			OnlineConfigScript.RANKING_DEFAULT_LIMIT,
			season_id
		)

	if not response.has("season_id"):
		response["season_id"] = season_id
	_show_ranking_response(tab, response)


func _show_ranking_response(tab: String, response: Dictionary) -> void:
	var screen = RANKING_SCENE.instantiate()
	screen.call("configure", tab, response)
	_replace_screen_instance(screen)
	screen.connect("player_tab_requested", Callable(self, "_show_ranking").bind("player"))
	screen.connect("ahoge_tab_requested", Callable(self, "_show_ranking").bind("ahoge"))
	screen.connect("back_requested", Callable(self, "_show_top_menu"))


func _on_online_battle_requested() -> void:
	_show_loading("CHECKING ONLINE STATE...")
	if not _online_session.is_authenticated():
		var auth_result: Dictionary = await _online_session.authenticate_local_device()
		if not bool(auth_result.get("ok", false)):
			_show_top_menu()
			return

	var active: Dictionary = await _online_session.refresh_active_online_match()
	if not bool(active.get("ok", false)):
		_show_top_menu()
		return
	if bool(active.get("active", false)):
		await _force_resume_unresolved_online_match()
		return
	_show_battle_mode_select()


func _show_battle_mode_select() -> void:
	var screen = _replace_screen(BATTLE_MODE_SCENE)
	screen.connect("ranked_requested", Callable(self, "_on_ranked_requested").bind(screen))
	screen.connect("friend_requested", Callable(self, "_on_friend_requested").bind(screen))
	screen.connect("back_requested", Callable(self, "_show_top_menu"))


func _on_ranked_requested(screen: Control) -> void:
	if is_instance_valid(screen):
		screen.call("set_status", "Nakamaへ接続中...")

	if not _online_session.is_authenticated():
		var auth_result: Dictionary = await _online_session.authenticate_local_device()
		if not bool(auth_result.get("ok", false)):
			if is_instance_valid(screen) and _current_screen == screen:
				screen.call("set_status", str(auth_result.get("message", "認証に失敗しました。")))
			return

	var active: Dictionary = await _online_session.refresh_active_online_match()
	if not bool(active.get("ok", false)):
		if is_instance_valid(screen) and _current_screen == screen:
			screen.call("set_status", str(active.get("message", "未解決対戦を確認できませんでした。")))
		return
	if bool(active.get("active", false)):
		await _force_resume_unresolved_online_match()
		return

	var realtime_result: Dictionary = await _online_session.connect_realtime_socket()
	if not bool(realtime_result.get("ok", false)):
		if is_instance_valid(screen) and _current_screen == screen:
			screen.call("set_status", str(realtime_result.get("message", "Realtime接続に失敗しました。")))
		return

	var rating: Dictionary = await _online_session.get_current_rating()
	if not bool(rating.get("ok", false)):
		if is_instance_valid(screen) and _current_screen == screen:
			screen.call("set_status", str(rating.get("message", "Ratingを取得できませんでした。")))
		return

	_ranked_rating_before = rating.duplicate(true)
	_show_ranked_character_select()


func _force_resume_unresolved_online_match() -> void:
	_show_loading("RESTORING ORIGINAL MATCH...")

	var restored: Dictionary = await _online_session.restore_unresolved_match_with_retry()
	if not bool(restored.get("ok", false)):
		_show_top_menu()
		return

	var destination := str(restored.get("destination", ""))
	var snapshot: Dictionary = restored.get("snapshot", {})
	if (
		not bool(restored.get("repaired", false))
		or snapshot.is_empty()
	):
		_show_top_menu()
		return

	var match_mode := str(snapshot.get("match_mode", ""))
	if match_mode == "ranked":
		if destination == "battle":
			_ranked_rating_before = {}
			_show_ranked_online_battle(snapshot)
			return
		if destination == "ranked_result":
			_show_ranked_result_from_snapshot(snapshot)
			return
		_show_top_menu()
		return

	if match_mode == "friend":
		_friend_room_code = str(snapshot.get("friend_room_code", ""))
		_update_friend_character_from_snapshot(snapshot)
		if _friend_room_code.is_empty():
			_show_top_menu()
			return
		if destination == "battle":
			_show_friend_online_battle(snapshot)
			return
		if destination == "friend_result":
			_show_friend_result_from_snapshot(snapshot)
			return

	_show_top_menu()


func _on_friend_requested(screen: Control) -> void:
	if is_instance_valid(screen):
		screen.call("set_status", "Nakamaへ接続中...")

	if not _online_session.is_authenticated():
		var auth_result: Dictionary = await _online_session.authenticate_local_device()
		if not bool(auth_result.get("ok", false)):
			if is_instance_valid(screen) and _current_screen == screen:
				screen.call("set_status", str(auth_result.get("message", "認証に失敗しました。")))
			return

	var active: Dictionary = await _online_session.refresh_active_online_match()
	if not bool(active.get("ok", false)):
		if is_instance_valid(screen) and _current_screen == screen:
			screen.call("set_status", str(active.get("message", "未解決対戦を確認できませんでした。")))
		return
	if bool(active.get("active", false)):
		await _force_resume_unresolved_online_match()
		return

	var realtime_result: Dictionary = await _online_session.connect_realtime_socket()
	if not bool(realtime_result.get("ok", false)):
		if is_instance_valid(screen) and _current_screen == screen:
			screen.call("set_status", str(realtime_result.get("message", "Realtime接続に失敗しました。")))
		return

	_show_friend_menu()


func _show_friend_menu(message: String = "") -> void:
	var screen = _replace_screen(FRIEND_MATCH_MENU_SCENE)
	screen.connect("create_requested", Callable(self, "_create_friend_room"))
	screen.connect("join_requested", Callable(self, "_show_friend_join"))
	screen.connect("back_requested", Callable(self, "_show_battle_mode_select"))
	if not message.is_empty():
		screen.call("set_status", message)


func _create_friend_room() -> void:
	_show_loading("CREATING FRIEND ROOM...")
	var room: Dictionary = await _online_session.create_friend_room()
	if not bool(room.get("ok", false)):
		_show_friend_menu(str(room.get("message", "Friend roomを作成できませんでした。")))
		return
	_set_friend_room(room)
	_show_friend_lobby()


func _show_friend_join(message: String = "") -> void:
	var screen = _replace_screen(FRIEND_ROOM_JOIN_SCENE)
	screen.connect("join_requested", Callable(self, "_join_friend_room"))
	screen.connect("back_requested", Callable(self, "_show_friend_menu"))
	if not message.is_empty():
		screen.call("set_status", message)


func _join_friend_room(room_code: String) -> void:
	_show_loading("JOINING FRIEND ROOM...")
	var room: Dictionary = await _online_session.join_friend_room(room_code)
	if not bool(room.get("ok", false)):
		_show_friend_join(str(room.get("message", "Friend roomへ参加できませんでした。")))
		return
	_set_friend_room(room)
	_show_friend_lobby()


func _show_friend_lobby() -> void:
	if _friend_room.is_empty() or _friend_room_code.is_empty():
		_show_friend_menu("Friend room情報がありません。")
		return
	var local_user_id := _session_user_id()
	var screen = FRIEND_ROOM_LOBBY_SCENE.instantiate()
	screen.call("configure", _friend_room, local_user_id)
	_replace_screen_instance(screen)
	screen.connect("refresh_requested", Callable(self, "_refresh_friend_lobby").bind(screen))
	screen.connect("character_select_requested", Callable(self, "_show_friend_character_select"))
	screen.connect("ready_requested", Callable(self, "_set_friend_ready").bind(screen))
	screen.connect("leave_requested", Callable(self, "_leave_friend_room").bind(screen))
	call_deferred("_refresh_friend_lobby", screen)


func _refresh_friend_lobby(screen: Control) -> void:
	if _friend_refresh_in_progress or not is_instance_valid(screen) or _current_screen != screen:
		return
	if _friend_room_code.is_empty():
		return
	_friend_refresh_in_progress = true
	var room: Dictionary = await _online_session.get_friend_room_status(_friend_room_code)
	_friend_refresh_in_progress = false
	if not is_instance_valid(screen) or _current_screen != screen:
		return
	if not bool(room.get("ok", false)):
		if _online_session.is_friend_room_terminal_failure(room):
			_clear_friend_room_context()
			_show_friend_menu("Friend roomが終了しました。")
			return
		screen.call("set_status", str(room.get("message", "Friend room状態を取得できませんでした。")))
		return
	_set_friend_room(room)
	screen.call("update_room", room)
	if str(room.get("state", "")) == "IN_MATCH" and not str(room.get("current_match_id", "")).is_empty():
		await _join_friend_match(room)


func _show_friend_character_select() -> void:
	var screen = CHARACTER_SELECT_SCENE.instantiate()
	screen.call("configure_friend", _friend_character_id)
	_replace_screen_instance(screen)
	screen.connect("friend_character_selected", Callable(self, "_set_friend_character"))
	screen.connect("back_requested", Callable(self, "_show_friend_lobby"))


func _set_friend_character(character_id: String) -> void:
	_show_loading("UPDATING CHARACTER...")
	var room: Dictionary = await _online_session.set_friend_room_character(
		_friend_room_code,
		character_id
	)
	if not bool(room.get("ok", false)):
		_show_friend_lobby()
		if is_instance_valid(_current_screen):
			_current_screen.call("set_status", str(room.get("message", "Characterを更新できませんでした。")))
		return
	_friend_character_id = character_id
	_set_friend_room(room)
	_show_friend_lobby()


func _set_friend_ready(ready: bool, screen: Control) -> void:
	if not is_instance_valid(screen) or _current_screen != screen:
		return
	screen.call("set_status", "READY状態をserverへ送信中...")
	var room: Dictionary = await _online_session.set_friend_room_ready(_friend_room_code, ready)
	if not is_instance_valid(screen) or _current_screen != screen:
		return
	if not bool(room.get("ok", false)):
		screen.call("set_status", str(room.get("message", "Ready状態を更新できませんでした。")))
		return
	_set_friend_room(room)
	screen.call("update_room", room)
	screen.call("set_status", "")
	if str(room.get("state", "")) == "IN_MATCH" and not str(room.get("current_match_id", "")).is_empty():
		await _join_friend_match(room)


func _join_friend_match(room: Dictionary) -> void:
	if _friend_join_in_progress:
		return
	_friend_join_in_progress = true
	_set_friend_room(room)
	_show_loading("JOINING FRIEND MATCH...")

	if not _online_session.is_realtime_connected():
		var realtime_result: Dictionary = await _online_session.connect_realtime_socket()
		if not bool(realtime_result.get("ok", false)):
			_friend_join_in_progress = false
			_show_friend_lobby()
			if is_instance_valid(_current_screen):
				_current_screen.call("set_status", str(realtime_result.get("message", "Realtime接続に失敗しました。")))
			return

	var joined: Dictionary = await _online_session.join_friend_match_from_room(room)
	_friend_join_in_progress = false
	if not bool(joined.get("ok", false)):
		_show_friend_lobby()
		if is_instance_valid(_current_screen):
			_current_screen.call("set_status", str(joined.get("message", "Friend matchへjoinできませんでした。")))
		return
	_show_friend_pre_battle()


func _show_friend_pre_battle() -> void:
	var screen = PRE_BATTLE_SCENE.instantiate()
	screen.call("configure_match_mode", "friend")
	_replace_screen_instance(screen)
	screen.connect("completed", Callable(self, "_on_friend_pre_battle_completed"))


func _on_friend_pre_battle_completed(snapshot: Dictionary) -> void:
	if bool(snapshot.get("match_finished", false)):
		_show_friend_result_from_snapshot(snapshot)
		return
	_show_friend_online_battle(snapshot)


func _show_friend_online_battle(snapshot: Dictionary) -> void:
	_friend_room_code = str(snapshot.get("friend_room_code", _friend_room_code))
	_update_friend_character_from_snapshot(snapshot)
	var screen = ONLINE_BATTLE_SCENE.instantiate()
	screen.call("configure", snapshot, {})
	_replace_screen_instance(screen)
	screen.connect("friend_match_completed", Callable(self, "_show_friend_result"))


func _show_friend_result_from_snapshot(snapshot: Dictionary) -> void:
	var summary := _friend_summary_from_snapshot(snapshot)
	_show_friend_result(summary)


func _friend_summary_from_snapshot(snapshot: Dictionary) -> Dictionary:
	var local_user_id := _session_user_id()
	var character_map: Dictionary = snapshot.get("character_id_by_user", {})
	var opponent_user_id := ""
	for user_id in character_map.keys():
		if str(user_id) != local_user_id:
			opponent_user_id = str(user_id)
			break
	var winner_user_id := str(snapshot.get("match_winner_user_id", ""))
	var is_draw := bool(snapshot.get("match_draw", false)) \
		or str(snapshot.get("match_finish_cause", "")) == "BO3_DRAW"
	var loser_user_id := ""
	if not is_draw:
		loser_user_id = opponent_user_id if winner_user_id == local_user_id else local_user_id
	return {
		"mode": "friend",
		"match_id": str(_online_session.current_match_id),
		"friend_room_code": str(snapshot.get("friend_room_code", _friend_room_code)),
		"friend_role": _friend_last_role,
		"winner_user_id": winner_user_id,
		"loser_user_id": loser_user_id,
		"local_user_id": local_user_id,
		"local_won": not is_draw and winner_user_id == local_user_id,
		"is_draw": is_draw,
		"local_character_id": str(character_map.get(local_user_id, _friend_character_id)),
		"opponent_character_id": str(character_map.get(opponent_user_id, "")),
		"round_wins_by_user": snapshot.get("round_wins_by_user", {}).duplicate(true),
		"final_round_number": int(snapshot.get("round_number", 1)),
		"finish_cause": str(snapshot.get("match_finish_cause", "")),
	}


func _show_friend_result(summary: Dictionary) -> void:
	_friend_room_code = str(summary.get("friend_room_code", _friend_room_code))
	var completed_summary := summary.duplicate(true)
	completed_summary["friend_role"] = _friend_last_role
	var result_match_id := str(summary.get("match_id", ""))

	# Match Result自体はroom Storageのsettlementを待たず即表示する。
	# room同期中はResult画面内で操作を一時無効化し、pollで追従する。
	var screen = MATCH_RESULT_SCENE.instantiate()
	screen.call("configure", completed_summary)
	_replace_screen_instance(screen)
	screen.connect("rematch_requested", Callable(self, "_on_friend_result_rematch_requested").bind(screen))
	screen.connect(
		"character_select_requested",
		Callable(self, "_on_friend_result_change_character_requested").bind(screen)
	)
	screen.connect("leave_room_requested", Callable(self, "_on_friend_result_leave_requested").bind(screen))
	screen.connect(
		"friend_result_refresh_requested",
		Callable(self, "_refresh_friend_result").bind(screen, result_match_id)
	)
	screen.call("set_friend_result_actions_enabled", false)
	screen.set_meta("friend_result_ack_completed", false)
	screen.set_meta("friend_result_match_id", result_match_id)
	call_deferred("_synchronize_friend_result", screen, result_match_id)


func _synchronize_friend_result(screen: Control, result_match_id: String) -> void:
	while is_instance_valid(screen) and _current_screen == screen:
		var ack_result: Dictionary = await _online_session.acknowledge_active_match_destination()
		if bool(ack_result.get("ok", false)):
			if is_instance_valid(screen) and _current_screen == screen:
				screen.set_meta("friend_result_ack_completed", true)
			break

		printerr("Friend Result active match ack failed: %s" % str(ack_result.get("message", "")))
		if not is_instance_valid(screen) or _current_screen != screen:
			return
		screen.call("set_friend_result_actions_enabled", false)
		screen.call("set_status", "SYNCING MATCH RESULT...")
		await get_tree().create_timer(0.25).timeout

	if not is_instance_valid(screen) or _current_screen != screen:
		return
	await _refresh_friend_result(screen, result_match_id)


func _on_friend_result_rematch_requested(screen: Control) -> void:
	if _friend_last_role != "host" or not is_instance_valid(screen) or _current_screen != screen:
		return
	screen.call("set_friend_result_actions_enabled", false)
	screen.call("set_status", "REMATCHをserverへ送信中...")
	var room: Dictionary = await _online_session.submit_friend_result_action(
		_friend_room_code,
		"rematch"
	)
	if not is_instance_valid(screen) or _current_screen != screen:
		return
	if not bool(room.get("ok", false)):
		screen.call("set_status", str(room.get("message", "REMATCHを開始できませんでした。")))
		await _refresh_friend_result(
			screen,
			str(screen.get_meta("friend_result_match_id", ""))
		)
		return
	_set_friend_room(room)
	await _join_friend_match(room)


func _on_friend_result_change_character_requested(screen: Control) -> void:
	if _friend_last_role != "host" or not is_instance_valid(screen) or _current_screen != screen:
		return
	screen.call("set_friend_result_actions_enabled", false)
	screen.call("set_status", "LOBBYへ戻しています...")
	var room: Dictionary = await _online_session.submit_friend_result_action(
		_friend_room_code,
		"change_character"
	)
	if not is_instance_valid(screen) or _current_screen != screen:
		return
	if not bool(room.get("ok", false)):
		screen.call("set_status", str(room.get("message", "Lobbyへ戻れませんでした。")))
		await _refresh_friend_result(
			screen,
			str(screen.get_meta("friend_result_match_id", ""))
		)
		return
	_set_friend_room(room)
	_show_friend_lobby()


func _on_friend_result_leave_requested(screen: Control) -> void:
	if not is_instance_valid(screen) or _current_screen != screen:
		return

	if _friend_last_role == "guest":
		screen.call("set_friend_result_actions_enabled", false)
		screen.call("set_status", "Friend roomから退出しています...")
		var guest_result: Dictionary = await _online_session.leave_friend_room(_friend_room_code)
		if not is_instance_valid(screen) or _current_screen != screen:
			return
		if not bool(guest_result.get("ok", false)):
			if _online_session.is_friend_room_terminal_failure(guest_result):
				_clear_friend_room_context()
				_show_top_menu()
				return
			screen.call("set_status", str(guest_result.get("message", "Friend roomから退出できませんでした。")))
			await _refresh_friend_result(
				screen,
				str(screen.get_meta("friend_result_match_id", ""))
			)
			return
		_clear_friend_room_context()
		_show_top_menu()
		return

	if _friend_last_role != "host":
		return
	screen.call("set_friend_result_actions_enabled", false)
	screen.call("set_status", "Friend roomを終了しています...")
	var result: Dictionary = await _online_session.submit_friend_result_action(
		_friend_room_code,
		"leave"
	)
	if not is_instance_valid(screen) or _current_screen != screen:
		return
	if not bool(result.get("ok", false)):
		screen.call("set_status", str(result.get("message", "Friend roomを終了できませんでした。")))
		await _refresh_friend_result(
			screen,
			str(screen.get_meta("friend_result_match_id", ""))
		)
		return
	_clear_friend_room_context()
	_show_top_menu()


func _refresh_friend_result(screen: Control, result_match_id: String) -> void:
	if _friend_refresh_in_progress or not is_instance_valid(screen) or _current_screen != screen:
		return
	if _friend_room_code.is_empty():
		return

	_friend_refresh_in_progress = true
	var room: Dictionary = await _online_session.get_friend_room_status(_friend_room_code)
	_friend_refresh_in_progress = false
	if not is_instance_valid(screen) or _current_screen != screen:
		return

	if not bool(room.get("ok", false)):
		if _online_session.is_friend_room_terminal_failure(room):
			_clear_friend_room_context()
			_show_top_menu()
			return
		screen.call("set_friend_result_actions_enabled", false)
		screen.call("set_status", str(room.get("message", "Friend roomを同期しています...")))
		return

	_set_friend_room(room)
	screen.call("set_friend_role", _friend_last_role)

	var state := str(room.get("state", ""))
	if state == "POST_MATCH":
		var ack_completed := bool(screen.get_meta("friend_result_ack_completed", false))
		screen.call("set_friend_result_actions_enabled", ack_completed)
		if not ack_completed:
			screen.call("set_status", "SYNCING MATCH RESULT...")
		elif _friend_last_role == "guest":
			screen.call("set_status", "WAITING FOR HOST...")
		else:
			screen.call("set_status", "")
		return

	if state == "IN_MATCH":
		var current_match_id := str(room.get("current_match_id", ""))
		# 終了した旧matchがまだIN_MATCHの間はroom settlement待ち。
		# 新しいmatch IDへ変わった場合だけHost REMATCH確定としてjoinする。
		if not current_match_id.is_empty() and current_match_id != result_match_id:
			await _join_friend_match(room)
			return
		screen.call("set_friend_result_actions_enabled", false)
		if _friend_last_role == "guest":
			screen.call("set_status", "WAITING FOR HOST...")
		else:
			screen.call("set_status", "SYNCING FRIEND ROOM...")
		return

	if state == "STARTING":
		screen.call("set_friend_result_actions_enabled", false)
		screen.call("set_status", "STARTING REMATCH...")
		return

	if state == "LOBBY":
		_show_friend_lobby()
		return
	if state == "WAITING" and _friend_last_role == "host":
		_show_friend_lobby()
		return

	screen.call("set_friend_result_actions_enabled", false)
	if _friend_last_role == "guest":
		screen.call("set_status", "WAITING FOR HOST...")
	else:
		screen.call("set_status", "SYNCING FRIEND ROOM...")


func _leave_friend_room(_screen: Control = null) -> void:
	if _friend_room_code.is_empty():
		_clear_friend_room_context()
		_show_friend_menu()
		return
	_show_loading("LEAVING FRIEND ROOM...")
	var result: Dictionary = await _online_session.leave_friend_room(_friend_room_code)
	if not bool(result.get("ok", false)):
		if _online_session.is_friend_room_terminal_failure(result):
			_clear_friend_room_context()
			_show_friend_menu("Friend roomはすでに終了しています。")
			return
		_show_friend_lobby()
		if is_instance_valid(_current_screen):
			_current_screen.call("set_status", str(result.get("message", "Friend roomから退出できませんでした。")))
		return
	_clear_friend_room_context()
	_show_friend_menu()


func _set_friend_room(room: Dictionary) -> void:
	_friend_room = room.duplicate(true)
	_friend_room_code = str(room.get("room_code", _friend_room_code))
	var role := str(room.get("role", ""))
	if role in ["host", "guest"]:
		_friend_last_role = role
	var selected := ""
	if role == "host":
		selected = str(room.get("host_character_id", ""))
	elif role == "guest":
		selected = str(room.get("guest_character_id", ""))
	if not selected.is_empty():
		_friend_character_id = selected


func _update_friend_character_from_snapshot(snapshot: Dictionary) -> void:
	var local_user_id := _session_user_id()
	var character_map: Dictionary = snapshot.get("character_id_by_user", {})
	var selected := str(character_map.get(local_user_id, ""))
	if not selected.is_empty():
		_friend_character_id = selected


func _clear_friend_room_context() -> void:
	_friend_room_code = ""
	_friend_room = {}
	_friend_last_role = ""
	_friend_join_in_progress = false
	_friend_refresh_in_progress = false


func _session_user_id() -> String:
	return str(_online_session.session.user_id) if _online_session.session != null else ""


func _show_local_character_select() -> void:
	var screen = CHARACTER_SELECT_SCENE.instantiate()
	screen.call("configure", _last_player_one_id, _last_player_two_id)
	_replace_screen_instance(screen)
	screen.connect("battle_requested", Callable(self, "_show_local_battle"))
	screen.connect("back_requested", Callable(self, "_show_top_menu"))


func _show_ranked_character_select() -> void:
	var screen = CHARACTER_SELECT_SCENE.instantiate()
	screen.call("configure_ranked", _ranked_character_id)
	_replace_screen_instance(screen)
	screen.connect("ranked_character_selected", Callable(self, "_show_ranked_matching"))
	screen.connect("back_requested", Callable(self, "_show_battle_mode_select"))


func _show_ranked_matching(character_id: String) -> void:
	var active: Dictionary = await _online_session.refresh_active_online_match()
	if not bool(active.get("ok", false)):
		_show_battle_mode_select()
		if is_instance_valid(_current_screen):
			_current_screen.call("set_status", str(active.get("message", "未解決対戦を確認できませんでした。")))
		return
	if bool(active.get("active", false)):
		await _force_resume_unresolved_online_match()
		return

	_ranked_character_id = character_id
	var rating: Dictionary = await _online_session.get_current_rating()
	if not bool(rating.get("ok", false)):
		_show_battle_mode_select()
		if is_instance_valid(_current_screen):
			_current_screen.call("set_status", str(rating.get("message", "Ratingを取得できませんでした。")))
		return
	_ranked_rating_before = rating.duplicate(true)

	var screen = RANKED_MATCHING_SCENE.instantiate()
	screen.call("configure", _ranked_character_id, int(rating.get("rating", 1500)))
	_replace_screen_instance(screen)
	screen.connect("cancel_requested", Callable(self, "_show_ranked_character_select"))
	screen.connect("match_joined", Callable(self, "_show_ranked_pre_battle"))


func _show_ranked_pre_battle(_match_id: String) -> void:
	var screen = _replace_screen(PRE_BATTLE_SCENE)
	screen.connect("completed", Callable(self, "_on_ranked_pre_battle_completed"))


func _on_ranked_pre_battle_completed(snapshot: Dictionary) -> void:
	if bool(snapshot.get("match_finished", false)):
		_show_ranked_result_from_snapshot(snapshot)
		return
	_show_ranked_online_battle(snapshot)


func _show_ranked_online_battle(snapshot: Dictionary) -> void:
	var screen = ONLINE_BATTLE_SCENE.instantiate()
	screen.call("configure", snapshot, _ranked_rating_before)
	_replace_screen_instance(screen)
	screen.connect("ranked_match_completed", Callable(self, "_show_ranked_result"))


func _show_ranked_result_from_snapshot(snapshot: Dictionary) -> void:
	var summary := _ranked_summary_from_snapshot(snapshot)
	_ranked_rating_before = {}
	_show_ranked_result(summary)


func _ranked_summary_from_snapshot(snapshot: Dictionary) -> Dictionary:
	var local_user_id := ""
	if _online_session.session != null:
		local_user_id = str(_online_session.session.user_id)
	var character_map: Dictionary = snapshot.get("character_id_by_user", {})
	var opponent_user_id := ""
	for user_id in character_map.keys():
		if str(user_id) != local_user_id:
			opponent_user_id = str(user_id)
			break
	var winner_user_id := str(snapshot.get("match_winner_user_id", ""))
	var is_draw := bool(snapshot.get("match_draw", false)) \
		or str(snapshot.get("match_finish_cause", "")) == "BO3_DRAW"
	var loser_user_id := ""
	if not is_draw:
		loser_user_id = opponent_user_id if winner_user_id == local_user_id else local_user_id
	return {
		"mode": "ranked",
		"match_id": str(_online_session.current_match_id),
		"winner_user_id": winner_user_id,
		"loser_user_id": loser_user_id,
		"local_user_id": local_user_id,
		"local_won": not is_draw and winner_user_id == local_user_id,
		"is_draw": is_draw,
		"local_character_id": str(character_map.get(local_user_id, _ranked_character_id)),
		"opponent_character_id": str(character_map.get(opponent_user_id, "")),
		"round_wins_by_user": snapshot.get("round_wins_by_user", {}).duplicate(true),
		"final_round_number": int(snapshot.get("round_number", 1)),
		"finish_cause": str(snapshot.get("match_finish_cause", "")),
		"rating_before": {},
	}


func _show_ranked_result(summary: Dictionary) -> void:
	_show_loading("SYNCING RESULT...")
	var completed_summary := summary.duplicate(true)
	var match_id := str(summary.get("match_id", _online_session.current_match_id))
	var settlement := await _wait_for_ranked_settlement(match_id)
	completed_summary["settlement"] = settlement

	if bool(settlement.get("found", false)):
		if bool(settlement.get("player_rating_available", false)):
			completed_summary["rating_before"] = {
				"rating": int(settlement.get("player_rating_before", 1500)),
			}
			completed_summary["rating_after"] = {
				"rating": int(settlement.get("player_rating_after", 1500)),
			}
		if bool(settlement.get("ahoge_rating_available", false)):
			completed_summary["ahoge_rating_before"] = int(
				settlement.get("ahoge_rating_before", 1500)
			)
			completed_summary["ahoge_rating_after"] = int(
				settlement.get("ahoge_rating_after", 1500)
			)
			completed_summary["ahoge_rating_delta"] = int(
				settlement.get("ahoge_rating_delta", 0)
			)

	var screen = MATCH_RESULT_SCENE.instantiate()
	screen.call("configure", completed_summary)
	_replace_screen_instance(screen)
	screen.connect("next_match_requested", Callable(self, "_show_ranked_character_select"))
	screen.connect("character_select_requested", Callable(self, "_show_ranked_character_select"))
	screen.connect("top_requested", Callable(self, "_show_top_menu"))

	# server settlementまで取得できたResultだけ遷移先確定済みとしてactive contextを解除する。
	# settlement未取得ならlockを保持し、次操作時に同じserver Resultへ復帰可能にする。
	if bool(settlement.get("found", false)):
		var ack_result: Dictionary = await _online_session.acknowledge_active_match_destination()
		if not bool(ack_result.get("ok", false)):
			printerr("Ranked Result active match ack failed: %s" % str(ack_result.get("message", "")))
	else:
		printerr("Ranked settlement未取得のためactive match lockを保持します。")


func _wait_for_ranked_settlement(match_id: String) -> Dictionary:
	var deadline := Time.get_ticks_msec() + 5000
	var latest: Dictionary = {}
	while Time.get_ticks_msec() < deadline:
		var current: Dictionary = await _online_session.get_ranked_match_settlement(match_id)
		if bool(current.get("ok", false)):
			latest = current.duplicate(true)
			if bool(current.get("found", false)):
				return latest
		await get_tree().create_timer(0.05).timeout
	return latest


func _show_local_battle(player_one_id: String, player_two_id: String) -> void:
	_last_player_one_id = player_one_id
	_last_player_two_id = player_two_id

	var screen = BATTLE_SCENE.instantiate()
	screen.call("configure", player_one_id, player_two_id)
	_replace_screen_instance(screen)
	screen.connect("match_completed", Callable(self, "_show_local_match_result"))
	screen.connect("exit_requested", Callable(self, "_show_top_menu"))


func _show_m1_authoritative_battle() -> void:
	var screen = _replace_screen(M1_BATTLE_SCENE)
	screen.connect("exit_requested", Callable(self, "_on_m1_exit_requested"))


func _show_local_match_result(summary: Dictionary) -> void:
	var screen = MATCH_RESULT_SCENE.instantiate()
	screen.call("configure", summary)
	_replace_screen_instance(screen)
	screen.connect("rematch_requested", Callable(self, "_on_local_rematch_requested"))
	screen.connect("character_select_requested", Callable(self, "_show_local_character_select"))
	screen.connect("top_requested", Callable(self, "_show_top_menu"))


func _on_local_rematch_requested() -> void:
	_show_local_battle(_last_player_one_id, _last_player_two_id)


func _show_loading(message: String) -> void:
	var screen := Control.new()
	screen.name = "LoadingScreen"
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	screen.add_child(center)
	var label := Label.new()
	label.text = message
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 24)
	center.add_child(label)
	_replace_screen_instance(screen)


func current_screen_name() -> String:
	return _current_screen.name if is_instance_valid(_current_screen) else ""


func _replace_screen(scene: PackedScene) -> Control:
	var instance := scene.instantiate() as Control
	_replace_screen_instance(instance)
	return instance


func _replace_screen_instance(instance: Control) -> void:
	if is_instance_valid(_current_screen):
		remove_child(_current_screen)
		_current_screen.queue_free()
	_current_screen = instance
	add_child(_current_screen)


func _on_m1_exit_requested() -> void:
	if _m1_direct_mode:
		get_tree().quit()
	else:
		_show_top_menu()


func _on_exit_requested() -> void:
	get_tree().quit()
