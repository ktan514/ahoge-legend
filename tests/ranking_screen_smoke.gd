extends SceneTree

const AppRootScene := preload("res://scenes/app/AppRoot.tscn")
const RankingScene := preload("res://scenes/screens/ranking/Ranking.tscn")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var online_session = get_root().get_node_or_null("OnlineSession")
	if online_session == null:
		_fail("OnlineSession Autoloadが見つかりません。", null)
		return

	online_session.clear_session()

	var app = AppRootScene.instantiate()
	get_root().add_child(app)
	if not await _wait_screen(app, "TopMenu", 6000):
		_fail("起動後にTopMenuが表示されません。", app)
		return

	var top = app.get_child(0)
	var ranking_button := _find_button(top, "RANKING")
	if ranking_button == null:
		_fail("Top MenuにRANKING buttonがありません。", app)
		return
	if ranking_button.disabled:
		_fail("Top MenuのRANKING buttonが無効です。", app)
		return

	top.emit_signal("ranking_requested")
	if not await _wait_ranking_tab(app, "PLAYER", 6000):
		_fail("Top MenuからPLAYER Rankingへ遷移しません。", app)
		return

	var player_screen = app.get_child(0)
	if str(player_screen.call("view_state")) == "ERROR":
		_fail("PLAYER RankingがERROR状態です。", app)
		return
	if not _valid_season_id(str(player_screen.call("displayed_season_id"))):
		_fail("PLAYER Rankingのserver season_idが不正です。", app)
		return
	if _find_button(player_screen, "PLAYER") == null \
			or _find_button(player_screen, "AHOGE LEGEND") == null:
		_fail("Ranking tabがPLAYER / AHOGE LEGENDの2つではありません。", app)
		return
	if _find_button(player_screen, "LONG") != null \
			or _find_button(player_screen, "NORMAL") != null \
			or _find_button(player_screen, "SHORT") != null:
		_fail("UI-12にタイプ別Ranking tabが存在します。", app)
		return

	player_screen.emit_signal("ahoge_tab_requested")
	if not await _wait_ranking_tab(app, "AHOGE LEGEND", 6000):
		_fail("AHOGE LEGEND tabへ切り替わりません。", app)
		return

	var ahoge_screen = app.get_child(0)
	if str(ahoge_screen.call("view_state")) == "ERROR":
		_fail("AHOGE LEGEND RankingがERROR状態です。", app)
		return
	if not _valid_season_id(str(ahoge_screen.call("displayed_season_id"))):
		_fail("AHOGE LEGEND Rankingのserver season_idが不正です。", app)
		return

	ahoge_screen.emit_signal("back_requested")
	if not await _wait_screen(app, "TopMenu", 3000):
		_fail("Ranking BACKでTopMenuへ戻りません。", app)
		return

	app.queue_free()
	await process_frame

	var finalizing = RankingScene.instantiate()
	finalizing.call("configure", "ahoge", {
		"ok": true,
		"season_id": "2026-09",
		"ranking_public": false,
		"ranking_hidden_until_unix_ms": 1,
		"records": [],
	})
	get_root().add_child(finalizing)
	await process_frame
	if str(finalizing.call("view_state")) != "FINALIZING":
		_fail("非公開RankingがFINALIZING状態になりません。", finalizing)
		return
	if not _has_label_text(finalizing, "FINALIZING..."):
		_fail("非公開RankingにFINALIZING表示がありません。", finalizing)
		return
	finalizing.queue_free()
	await process_frame

	var server_rank = RankingScene.instantiate()
	server_rank.call("configure", "ahoge", {
		"ok": true,
		"season_id": "2026-10",
		"ranking_public": true,
		"records": [
			{
				"display_rank": 7,
				"character_id": "LONG_TEST",
				"ahoge_rating": 1777,
				"total_match_wins": 12,
				"total_ranked_matches": 20,
				"legendary": true,
			},
		],
	})
	get_root().add_child(server_rank)
	await process_frame
	if str(server_rank.call("view_state")) != "READY":
		_fail("server recordありRankingがREADY状態になりません。", server_rank)
		return
	if not _has_label_text(server_rank, "#7"):
		_fail("server display_rank=7をそのまま表示していません。", server_rank)
		return
	if not _has_label_text(server_rank, "AHOGE RATING 1777"):
		_fail("server Ahoge Ratingをそのまま表示していません。", server_rank)
		return
	if not _has_label_text(server_rank, "LEGENDARY AHOGE"):
		_fail("server legendary=trueの強調表示がありません。", server_rank)
		return

	server_rank.queue_free()
	online_session.clear_session()
	print("AHOGE LEGEND ranking screen smoke: PASS")
	quit(0)


func _wait_ranking_tab(app, tab_name: String, timeout_ms: int) -> bool:
	var deadline := Time.get_ticks_msec() + timeout_ms
	while Time.get_ticks_msec() < deadline:
		if str(app.call("current_screen_name")) == "Ranking":
			var screen = app.get_child(0)
			if screen.has_method("current_tab_name") \
					and str(screen.call("current_tab_name")) == tab_name:
				return true
		await create_timer(0.05).timeout
	return false


func _wait_screen(app, screen_name: String, timeout_ms: int) -> bool:
	var deadline := Time.get_ticks_msec() + timeout_ms
	while Time.get_ticks_msec() < deadline:
		if str(app.call("current_screen_name")) == screen_name:
			return true
		await create_timer(0.05).timeout
	return false


func _find_button(root: Node, text: String):
	if root is Button and str(root.text) == text:
		return root
	for child in root.get_children():
		var found = _find_button(child, text)
		if found != null:
			return found
	return null


func _has_label_text(root: Node, text: String) -> bool:
	if root is Label and str(root.text).contains(text):
		return true
	for child in root.get_children():
		if _has_label_text(child, text):
			return true
	return false


func _valid_season_id(value: String) -> bool:
	if value.length() != 7 or value.substr(4, 1) != "-":
		return false
	var year := value.substr(0, 4)
	var month := value.substr(5, 2)
	return year.is_valid_int() \
		and month.is_valid_int() \
		and int(month) >= 1 \
		and int(month) <= 12


func _fail(message: String, root) -> void:
	var online_session = get_root().get_node_or_null("OnlineSession")
	if online_session != null:
		online_session.clear_session()
	if root != null and is_instance_valid(root):
		root.queue_free()
	push_error(message)
	print("AHOGE LEGEND ranking screen smoke: FAIL")
	quit(1)
