extends Control

const OnlineConfigScript := preload("res://src/config/online_config.gd")
const TOP_MENU_SCENE := preload("res://scenes/screens/top_menu/TopMenu.tscn")
const BATTLE_MODE_SCENE := preload("res://scenes/screens/battle_mode/BattleModeSelect.tscn")
const CHARACTER_SELECT_SCENE := preload("res://scenes/screens/character_select/CharacterSelect.tscn")
const RANKED_MATCHING_SCENE := preload("res://scenes/screens/ranked_matching/RankedMatching.tscn")
const PRE_BATTLE_SCENE := preload("res://scenes/overlays/PreBattleDialogue.tscn")
const ONLINE_BATTLE_SCENE := preload("res://scenes/screens/battle/OnlineBattle.tscn")
const BATTLE_SCENE := preload("res://scenes/screens/battle/Battle.tscn")
const M1_BATTLE_SCENE := preload("res://scenes/screens/battle/BattleM1Debug.tscn")
const MATCH_RESULT_SCENE := preload("res://scenes/screens/result/MatchResult.tscn")
const RANKING_SCENE := preload("res://scenes/screens/ranking/Ranking.tscn")

var _online_session = null

var _current_screen: Control
var _last_player_one_id: String = "LONG_TEST"
var _last_player_two_id: String = "SHORT_TEST"
var _ranked_character_id: String = "LONG_TEST"
var _ranked_rating_before: Dictionary = {}
var _m1_direct_mode: bool = false


func _ready() -> void:
	_online_session = get_node("/root/OnlineSession")
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
		await _force_resume_unresolved_ranked_match()
		return
	_show_top_menu()


func _show_top_menu() -> void:
	var screen = _replace_screen(TOP_MENU_SCENE)
	screen.connect("local_test_requested", Callable(self, "_show_local_character_select"))
	screen.connect("online_battle_requested", Callable(self, "_on_online_battle_requested"))
	screen.connect("ranking_requested", Callable(self, "_show_ranking").bind("player"))
	screen.connect("exit_requested", Callable(self, "_on_exit_requested"))


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
		await _force_resume_unresolved_ranked_match()
		return
	_show_battle_mode_select()


func _show_battle_mode_select() -> void:
	var screen = _replace_screen(BATTLE_MODE_SCENE)
	screen.connect("ranked_requested", Callable(self, "_on_ranked_requested").bind(screen))
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
		await _force_resume_unresolved_ranked_match()
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


func _force_resume_unresolved_ranked_match() -> void:
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

	if str(snapshot.get("match_mode", "")) != "ranked":
		# Friend UIは工程4後半。lockは解除せずTopへ戻す。
		_show_top_menu()
		return

	if destination == "battle":
		_ranked_rating_before = {}
		_show_ranked_online_battle(snapshot)
		return

	if destination == "ranked_result":
		_show_ranked_result_from_snapshot(snapshot)
		return

	_show_top_menu()


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
		await _force_resume_unresolved_ranked_match()
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
