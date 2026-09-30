extends SceneTree


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var online_session = get_root().get_node_or_null("OnlineSession")
	if online_session == null:
		_fail("OnlineSession Autoloadが見つかりません。")
		return

	online_session.clear_session()

	var auth_result: Dictionary = await online_session.authenticate_local_device()
	if not bool(auth_result.get("ok", false)):
		_fail("Device認証に失敗しました。")
		return

	var client = online_session.client
	var session = online_session.session

	var current := await _rpc_dict(client, session, "ahoge_season_metadata", null)
	if current.is_empty():
		_fail("現在Season metadataを取得できませんでした。")
		return

	var current_id := str(current.get("season_id", ""))
	var current_start := int(current.get("starts_at_unix_ms", -1))
	var current_end := int(current.get("ends_at_unix_ms", -1))
	if not _valid_season_id(current_id):
		_fail("現在season_idの形式が不正です。")
		return
	if str(current.get("state", "")) != "CURRENT":
		_fail("現在Season stateがCURRENTではありません。")
		return
	if current_start < 0 or current_end <= current_start:
		_fail("現在Season境界時刻が不正です。")
		return
	if not _is_jst_month_boundary(current_start) or not _is_jst_month_boundary(current_end):
		_fail("Season境界がJST 1日00:00ではありません。")
		return

	var before_boundary := await _rpc_dict(
		client,
		session,
		"ahoge_season_metadata",
		JSON.stringify({"at_unix_ms": current_start - 1})
	)
	var at_boundary := await _rpc_dict(
		client,
		session,
		"ahoge_season_metadata",
		JSON.stringify({"at_unix_ms": current_start})
	)
	if before_boundary.is_empty() or at_boundary.is_empty():
		_fail("Season境界前後metadataを取得できませんでした。")
		return
	if str(at_boundary.get("season_id", "")) != current_id:
		_fail("JST 1日00:00ちょうどで現在Seasonへ切り替わりません。")
		return

	var previous_id := str(before_boundary.get("season_id", ""))
	if previous_id == current_id or not _valid_season_id(previous_id):
		_fail("境界1ms前が前Seasonではありません。")
		return
	if str(before_boundary.get("state", "")) != "HISTORICAL":
		_fail("前Season stateがHISTORICALではありません。")
		return
	if int(before_boundary.get("ends_at_unix_ms", -1)) != current_start:
		_fail("前Season終了時刻と現在Season開始時刻が連続していません。")
		return

	var previous_again := await _rpc_dict(
		client,
		session,
		"ahoge_season_metadata",
		JSON.stringify({"season_id": previous_id})
	)
	if previous_again.is_empty() 			or int(previous_again.get("starts_at_unix_ms", -1)) != int(before_boundary.get("starts_at_unix_ms", -2)) 			or int(previous_again.get("ends_at_unix_ms", -1)) != int(before_boundary.get("ends_at_unix_ms", -2)):
		_fail("前Season metadataが保持されていません。")
		return

	var current_rating := await _rpc_dict(client, session, "ahoge_current_rating", null)
	var previous_rating := await _rpc_dict(
		client,
		session,
		"ahoge_current_rating",
		JSON.stringify({"season_id": previous_id})
	)
	if not _assert_default_rating(current_rating, current_id):
		_fail("新Season Player Rating初期値が1500ではありません。")
		return
	if not _assert_default_rating(previous_rating, previous_id):
		_fail("未作成の過去Season Rating初期値が1500ではありません。")
		return

	var current_ahoge_rating := await _rpc_dict(
		client,
		session,
		"ahoge_character_rating",
		JSON.stringify({
			"character_id": OnlineConfigScript.RANKED_CHARACTER_LONG_TEST,
			"season_id": current_id,
		})
	)
	var previous_ahoge_rating := await _rpc_dict(
		client,
		session,
		"ahoge_character_rating",
		JSON.stringify({
			"character_id": OnlineConfigScript.RANKED_CHARACTER_LONG_TEST,
			"season_id": previous_id,
		})
	)
	if not _assert_default_ahoge_rating(
		current_ahoge_rating,
		current_id,
		OnlineConfigScript.RANKED_CHARACTER_LONG_TEST
	):
		_fail("新Season Ahoge Rating初期値が1500ではありません。")
		return
	if not _assert_default_ahoge_rating(
		previous_ahoge_rating,
		previous_id,
		OnlineConfigScript.RANKED_CHARACTER_LONG_TEST
	):
		_fail("未作成の過去Season Ahoge Rating初期値が1500ではありません。")
		return

	var previous_player_ranking := await _rpc_dict(
		client,
		session,
		"ahoge_player_ranking",
		JSON.stringify({"limit": 20, "season_id": previous_id})
	)
	if previous_player_ranking.is_empty() 			or str(previous_player_ranking.get("season_id", "")) != previous_id 			or not _records_empty(previous_player_ranking):
		_fail("過去Season PLAYER Rankingの空履歴取得が不正です。")
		return

	var current_ahoge := await _rpc_dict(
		client,
		session,
		"ahoge_legend_ranking",
		JSON.stringify({"limit": 20, "season_id": current_id})
	)
	var previous_ahoge := await _rpc_dict(
		client,
		session,
		"ahoge_legend_ranking",
		JSON.stringify({"limit": 20, "season_id": previous_id})
	)
	if current_ahoge.is_empty() or not _records_empty(current_ahoge):
		_fail("新Season AHOGE LEGEND集計が0から開始していません。")
		return
	if previous_ahoge.is_empty() 			or str(previous_ahoge.get("season_id", "")) != previous_id 			or not _records_empty(previous_ahoge):
		_fail("過去Season AHOGE LEGEND Ranking取得が不正です。")
		return

	var season_rpcs := [
		"ahoge_season_metadata",
		"ahoge_current_rating",
		"ahoge_player_ranking",
		"ahoge_legend_ranking",
	]
	var invalid_season_values := ["", null, false, 0]
	for rpc_id in season_rpcs:
		for invalid_value in invalid_season_values:
			var invalid_result = await client.rpc_async(
				session,
				str(rpc_id),
				JSON.stringify({"season_id": invalid_value})
			)
			if invalid_result == null or not invalid_result.is_exception():
				_fail("明示された不正season_idが拒否されませんでした。 rpc=%s" % str(rpc_id))
				return

	var future_id := _next_season_id(current_id)
	var future_result = await client.rpc_async(
		session,
		"ahoge_player_ranking",
		JSON.stringify({"limit": 20, "season_id": future_id})
	)
	if future_result == null or not future_result.is_exception():
		_fail("未来SeasonのPLAYER Ranking取得が拒否されませんでした。")
		return

	var future_metadata = await client.rpc_async(
		session,
		"ahoge_season_metadata",
		JSON.stringify({"season_id": future_id})
	)
	if future_metadata == null or not future_metadata.is_exception():
		_fail("未来Season metadata取得が拒否されませんでした。")
		return

	online_session.clear_session()
	print(
		"AHOGE LEGEND season smoke: PASS current=%s previous=%s" % [
			current_id,
			previous_id,
		]
	)
	quit(0)


func _rpc_dict(client, session, rpc_id: String, payload) -> Dictionary:
	var result = await client.rpc_async(session, rpc_id, payload)
	if result == null or result.is_exception():
		return {}
	var parsed = JSON.parse_string(str(result.payload))
	if not parsed is Dictionary:
		return {}
	return parsed


func _valid_season_id(value: String) -> bool:
	if value.length() != 7 or value[4] != "-":
		return false
	var year_text := value.substr(0, 4)
	var month_text := value.substr(5, 2)
	if not year_text.is_valid_int() or not month_text.is_valid_int():
		return false
	var month := int(month_text)
	return month >= 1 and month <= 12


func _is_jst_month_boundary(unix_ms: int) -> bool:
	var jst_seconds := int(unix_ms / 1000) + 9 * 60 * 60
	var dt := Time.get_datetime_dict_from_unix_time(jst_seconds)
	return int(dt.get("day", -1)) == 1 		and int(dt.get("hour", -1)) == 0 		and int(dt.get("minute", -1)) == 0 		and int(dt.get("second", -1)) == 0


func _assert_default_rating(value: Dictionary, season_id: String) -> bool:
	return not value.is_empty() 		and str(value.get("season_id", "")) == season_id 		and int(value.get("rating", -1)) == 1500 		and int(value.get("wins", -1)) == 0 		and int(value.get("losses", -1)) == 0


func _assert_default_ahoge_rating(
	value: Dictionary,
	season_id: String,
	character_id: String
) -> bool:
	return not value.is_empty() \
		and str(value.get("season_id", "")) == season_id \
		and str(value.get("character_id", "")) == character_id \
		and int(value.get("ahoge_rating", -1)) == 1500 \
		and int(value.get("total_match_wins", -1)) == 0 \
		and int(value.get("total_ranked_matches", -1)) == 0


func _records_empty(value: Dictionary) -> bool:
	var records = value.get("records", null)
	return records is Array and records.is_empty()


func _next_season_id(season_id: String) -> String:
	var year := int(season_id.substr(0, 4))
	var month := int(season_id.substr(5, 2)) + 1
	if month == 13:
		year += 1
		month = 1
	return "%04d-%02d" % [year, month]


func _fail(message: String) -> void:
	var online_session = get_root().get_node_or_null("OnlineSession")
	if online_session != null:
		online_session.clear_session()
	push_error(message)
	print("AHOGE LEGEND season smoke: FAIL")
	quit(1)
