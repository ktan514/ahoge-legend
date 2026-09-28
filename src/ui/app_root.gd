extends Control

const TOP_MENU_SCENE := preload("res://scenes/screens/top_menu/TopMenu.tscn")
const BATTLE_MODE_SCENE := preload("res://scenes/screens/battle_mode/BattleModeSelect.tscn")
const CHARACTER_SELECT_SCENE := preload("res://scenes/screens/character_select/CharacterSelect.tscn")
const RANKED_MATCHING_SCENE := preload("res://scenes/screens/ranked_matching/RankedMatching.tscn")
const PRE_BATTLE_SCENE := preload("res://scenes/overlays/PreBattleDialogue.tscn")
const ONLINE_BATTLE_SCENE := preload("res://scenes/screens/battle/OnlineBattle.tscn")
const BATTLE_SCENE := preload("res://scenes/screens/battle/Battle.tscn")
const M1_BATTLE_SCENE := preload("res://scenes/screens/battle/BattleM1Debug.tscn")
const MATCH_RESULT_SCENE := preload("res://scenes/screens/result/MatchResult.tscn")

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

	if _online_session.has_saved_match_context_file():
		_show_loading("RESTORING ONLINE MATCH...")
		call_deferred("_restore_saved_match_flow")
	else:
		_show_top_menu()


func _restore_saved_match_flow() -> void:
	var auth_result: Dictionary = await _online_session.authenticate_local_device()
	if not bool(auth_result.get("ok", false)):
		_show_top_menu()
		return

	var resumed: Dictionary = await _online_session.resume_saved_match_after_login()
	if not bool(resumed.get("ok", false)) or not bool(resumed.get("resumed", false)):
		_show_top_menu()
		return

	var snapshot: Dictionary = resumed.get("snapshot", {})
	var destination := str(resumed.get("destination", ""))
	if str(snapshot.get("match_mode", "")) != "ranked":
		# Friend UIは工程4後半。lockは解除せず、新規対戦開始を防ぐ。
		_show_top_menu()
		return

	if destination == "battle":
		_ranked_rating_before = {}
		_show_ranked_online_battle(snapshot)
	elif destination == "ranked_result":
		_show_ranked_result_from_snapshot(snapshot)
	else:
		_show_top_menu()


func _show_top_menu() -> void:
	var screen = _replace_screen(TOP_MENU_SCENE)
	screen.connect("local_test_requested", Callable(self, "_show_local_character_select"))
	screen.connect("online_battle_requested", Callable(self, "_show_battle_mode_select"))
	screen.connect("exit_requested", Callable(self, "_on_exit_requested"))


func _show_battle_mode_select() -> void:
	var screen = _replace_screen(BATTLE_MODE_SCENE)
	screen.connect("ranked_requested", Callable(self, "_on_ranked_requested").bind(screen))
	screen.connect("back_requested", Callable(self, "_show_top_menu"))


func _on_ranked_requested(screen: Control) -> void:
	if _online_session.has_unresolved_match_context():
		await _force_resume_unresolved_ranked_match()
		return

	if is_instance_valid(screen):
		screen.call("set_status", "Nakamaへ接続中...")

	if not _online_session.is_authenticated():
		var auth_result: Dictionary = await _online_session.authenticate_local_device()
		if not bool(auth_result.get("ok", false)):
			if is_instance_valid(screen) and _current_screen == screen:
				screen.call("set_status", str(auth_result.get("message", "認証に失敗しました。")))
			return

	if _online_session.has_unresolved_match_context():
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

	if not _online_session.is_authenticated():
		var auth_result: Dictionary = await _online_session.authenticate_local_device()
		if not bool(auth_result.get("ok", false)):
			_show_battle_mode_select()
			if is_instance_valid(_current_screen):
				_current_screen.call(
					"set_status",
					str(auth_result.get("message", "元の対戦へ復帰するための認証に失敗しました。"))
				)
			return

	var repaired: Dictionary = await _online_session.repair_unresolved_match_context()
	if not bool(repaired.get("ok", false)):
		_show_battle_mode_select()
		if is_instance_valid(_current_screen):
			_current_screen.call(
				"set_status",
				str(repaired.get("message", "元の対戦への復帰に失敗しました。"))
			)
		return

	var destination := str(repaired.get("destination", ""))
	var snapshot: Dictionary = repaired.get("snapshot", {})
	if not bool(repaired.get("repaired", false)) or snapshot.is_empty():
		_show_battle_mode_select()
		if is_instance_valid(_current_screen):
			_current_screen.call("set_status", "元の対戦をserverで確認できませんでした。")
		return

	if str(snapshot.get("match_mode", "")) != "ranked":
		_show_top_menu()
		return

	if destination == "battle":
		_ranked_rating_before = {}
		_show_ranked_online_battle(snapshot)
		return

	if destination == "ranked_result":
		_show_ranked_result_from_snapshot(snapshot)
		return

	_show_battle_mode_select()
	if is_instance_valid(_current_screen):
		_current_screen.call("set_status", "元の対戦の復帰先を決定できませんでした。")


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
	if _online_session.has_unresolved_match_context():
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
	var loser_user_id := opponent_user_id if winner_user_id == local_user_id else local_user_id
	return {
		"mode": "ranked",
		"winner_user_id": winner_user_id,
		"loser_user_id": loser_user_id,
		"local_user_id": local_user_id,
		"local_won": winner_user_id == local_user_id,
		"local_character_id": str(character_map.get(local_user_id, _ranked_character_id)),
		"opponent_character_id": str(character_map.get(opponent_user_id, "")),
		"round_wins_by_user": snapshot.get("round_wins_by_user", {}).duplicate(true),
		"final_round_number": int(snapshot.get("round_number", 1)),
		"finish_cause": str(snapshot.get("match_finish_cause", "")),
		"rating_before": {},
	}


func _show_ranked_result(summary: Dictionary) -> void:
	_show_loading("SYNCING RESULT...")
	var rating_before: Dictionary = summary.get("rating_before", {})
	var rating_after: Dictionary = await _wait_for_ranked_rating_settlement(rating_before)
	var completed_summary := summary.duplicate(true)
	completed_summary["rating_after"] = rating_after

	var screen = MATCH_RESULT_SCENE.instantiate()
	screen.call("configure", completed_summary)
	_replace_screen_instance(screen)
	screen.connect("next_match_requested", Callable(self, "_show_ranked_character_select"))
	screen.connect("character_select_requested", Callable(self, "_show_ranked_character_select"))
	screen.connect("top_requested", Callable(self, "_show_top_menu"))

	# Result画面への遷移が確定した後だけ未解決match contextを解除する。
	_online_session.acknowledge_saved_match_destination()


func _wait_for_ranked_rating_settlement(rating_before: Dictionary) -> Dictionary:
	var deadline := Time.get_ticks_msec() + 5000
	var latest: Dictionary = {}
	while Time.get_ticks_msec() < deadline:
		var current: Dictionary = await _online_session.get_current_rating()
		if bool(current.get("ok", false)):
			latest = current.duplicate(true)
			if rating_before.is_empty() or _rating_record_changed(rating_before, current):
				return latest
		await get_tree().create_timer(0.05).timeout
	return latest


func _rating_record_changed(before: Dictionary, after: Dictionary) -> bool:
	return (
		int(before.get("rating", -1)) != int(after.get("rating", -1))
		or int(before.get("wins", -1)) != int(after.get("wins", -1))
		or int(before.get("losses", -1)) != int(after.get("losses", -1))
	)


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
