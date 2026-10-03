extends SceneTree

const CombatConfigScript := preload("res://src/config/combat_config.gd")
const CombatantStateScript := preload("res://src/domain/combatant_state.gd")
const CharacterCatalogScript := preload("res://src/domain/character_catalog.gd")
const RoundCoordinatorScript := preload("res://src/services/round_coordinator.gd")
const MatchCoordinatorScript := preload("res://src/services/match_coordinator.gd")
const CombatResolverScript := preload("res://src/services/combat_resolver.gd")
const DeviceIdentityStoreScript := preload("res://src/online/device_identity_store.gd")
const MatchResumeRouterScript := preload("res://src/online/match_resume_router.gd")
const RankedMatchmakerQueryScript := preload("res://src/online/ranked_matchmaker_query.gd")
const OnlineConfigScript := preload("res://src/config/online_config.gd")
const CombatInputProtocolScript := preload("res://src/online/combat_input_protocol.gd")
const SettingsStoreScript := preload("res://src/settings/settings_store.gd")
const TopMenuScene := preload("res://scenes/screens/top_menu/TopMenu.tscn")
const AhogeImageRigScript := preload("res://src/ui/ahoge_image_rig.gd")

var _failures: Array[String] = []
var _checks: int = 0


func _init() -> void:
	_test_round_timer_enters_overtime()
	_test_timeout_leader_wins()
	_test_five_hits_wins_round()
	_test_best_of_three()
	_test_overtime_next_hit_wins()
	_test_attack_state_transitions()
	_test_defense_cancel_and_dodge()
	_test_real_attack_registers_hit()
	_test_parry_blocks_hit()
	_test_just_parry_staggers_attacker()
	_test_dodge_blocks_hit()
	_test_just_dodge_staggers_attacker()
	_test_attack_clash()
	_test_short_throw_detach_and_regrow()
	_test_real_attacks_complete_best_of_three()
	_test_device_identity_persists()
	_test_settings_store_contract()
	_test_top_menu_asset_contract()
	_test_match_resume_router()
	_test_ranked_matchmaker_query()
	_test_ranked_recovery_policy()
	_test_ranked_character_contract()
	_test_character_catalog_ui_contract()
	_test_ahoge_image_rig_uv_contract()
	_test_combat_input_protocol()
	_test_authoritative_attack_protocol()
	_test_authoritative_defense_protocol()
	_test_authoritative_defense_result_protocol()
	_test_authoritative_contact_outcome_protocol()
	_test_authoritative_stagger_protocol()
	_test_authoritative_hit_count_protocol()
	_test_authoritative_round_timer_protocol()
	_test_authoritative_round_locked_protocol()
	_test_authoritative_draw_protocol()
	_test_authoritative_round_result_protocol()
	_test_authoritative_bo3_protocol()
	_test_authoritative_match_result_protocol()
	_test_authoritative_round_countdown_protocol()
	_test_authoritative_match_snapshot_protocol()
	_test_authoritative_player_connection_protocol()

	if _failures.is_empty():
		print("AHOGE LEGEND tests: PASS (%d checks)" % _checks)
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		print("AHOGE LEGEND tests: FAIL (%d failures / %d checks)" % [_failures.size(), _checks])
		quit(1)


func _test_round_timer_enters_overtime() -> void:
	var config = CombatConfigScript.new()
	var round_flow = RoundCoordinatorScript.new(config, 1)
	round_flow.tick(85.1)
	_expect_true(round_flow.state.overtime, "同点時間切れでOvertimeへ入る")
	_expect_false(round_flow.state.finished, "Overtime開始時点ではラウンド終了しない")


func _test_timeout_leader_wins() -> void:
	var config = CombatConfigScript.new()
	var round_flow = RoundCoordinatorScript.new(config, 1)
	round_flow.register_hit(0)
	round_flow.register_hit(0)
	round_flow.register_hit(1)
	round_flow.tick(85.1)
	_expect_equal(round_flow.state.winner, 0, "時間切れ時はヒット数が多い側が勝つ")
	_expect_true(round_flow.state.finished, "時間切れ勝敗確定でラウンド終了する")


func _test_five_hits_wins_round() -> void:
	var config = CombatConfigScript.new()
	var round_flow = RoundCoordinatorScript.new(config, 1)
	for _index in range(config.hits_to_win_round):
		round_flow.register_hit(1)
	_expect_equal(round_flow.state.winner, 1, "5ヒット到達側がラウンドを取る")
	_expect_equal(round_flow.state.player_two_hits, 5, "5ヒットを保持する")


func _test_best_of_three() -> void:
	var config = CombatConfigScript.new()
	var match_flow = MatchCoordinatorScript.new(config)

	for _round_index in range(2):
		for _hit_index in range(config.hits_to_win_round):
			match_flow.register_hit(0)

	_expect_equal(match_flow.player_one_rounds, 2, "2ラウンド取得を記録する")
	_expect_equal(match_flow.match_winner, 0, "2ラウンド先取でマッチ勝利する")


func _test_overtime_next_hit_wins() -> void:
	var config = CombatConfigScript.new()
	var round_flow = RoundCoordinatorScript.new(config, 1)
	round_flow.tick(config.round_seconds)
	round_flow.register_hit(1)
	_expect_equal(round_flow.state.winner, 1, "Overtimeは次の有効ヒットで決着する")
	_expect_true(round_flow.state.finished, "Overtime有効ヒットでラウンド終了する")


func _test_attack_state_transitions() -> void:
	var config = CombatConfigScript.new()
	var state = CombatantStateScript.new(config)
	_expect_true(state.begin_attack(), "IdleからChargeを開始できる")
	state.tick(config.max_charge_seconds)
	_expect_true(state.release_attack(), "Chargeから攻撃を解放できる")
	_expect_equal(state.action_state, CombatantStateScript.ActionState.WINDUP, "Release後はWindup")
	state.tick(config.normal_windup_seconds + config.charged_release_windup_seconds)
	_expect_equal(state.action_state, CombatantStateScript.ActionState.STRIKE, "Windup後はStrike")
	state.tick(config.normal_strike_seconds + config.charged_strike_seconds)
	_expect_equal(state.action_state, CombatantStateScript.ActionState.COOLDOWN, "Strike後はCooldown")


func _test_defense_cancel_and_dodge() -> void:
	var config = CombatConfigScript.new()
	var state = CombatantStateScript.new(config)
	state.begin_attack()
	state.tick(0.2)
	state.release_attack()
	_expect_true(state.start_defense(), "攻撃途中から防御キャンセルできる")
	_expect_equal(state.action_state, CombatantStateScript.ActionState.PARRY, "アホ毛ありではParry")

	state.tick(config.parry_active_seconds + 0.01)
	state.set_ahoge_available(false)
	_expect_true(state.start_defense(), "アホ毛なしでも防御操作を受け付ける")
	_expect_equal(state.action_state, CombatantStateScript.ActionState.DODGE, "アホ毛なしではDodge")


func _test_real_attack_registers_hit() -> void:
	var fixture = _combat_fixture("LONG_TEST", "LONG_TEST")
	var combat = fixture["combat"]
	var match_flow = fixture["match"]
	_attack_once(combat, 0)
	_expect_equal(match_flow.round.state.player_one_hits, 1, "実攻撃到達でP1ヒットが加算される")


func _test_parry_blocks_hit() -> void:
	var fixture = _combat_fixture("LONG_TEST", "LONG_TEST")
	var combat = fixture["combat"]
	var match_flow = fixture["match"]
	combat.press_attack(0)
	combat.release_attack(0)
	_advance_combat(combat, 0.20)
	combat.defend(1)
	_advance_combat(combat, 0.30)
	_expect_equal(match_flow.round.state.player_one_hits, 0, "Parry中はヒットを受けない")


func _test_just_parry_staggers_attacker() -> void:
	var fixture = _combat_fixture("LONG_TEST", "LONG_TEST")
	var combat = fixture["combat"]
	combat.press_attack(0)
	combat.release_attack(0)
	_advance_combat(combat, 0.29)
	combat.defend(1)
	_advance_combat(combat, 0.05)
	_expect_equal(
		combat.get_state(0).action_state,
		CombatantStateScript.ActionState.STAGGER,
		"Just Parryで攻撃側がStaggerになる"
	)


func _test_dodge_blocks_hit() -> void:
	var fixture = _combat_fixture("LONG_TEST", "LONG_TEST")
	var combat = fixture["combat"]
	var match_flow = fixture["match"]
	combat.get_state(1).set_ahoge_available(false)
	combat.press_attack(0)
	combat.release_attack(0)
	_advance_combat(combat, 0.18)
	combat.defend(1)
	_advance_combat(combat, 0.30)
	_expect_equal(match_flow.round.state.player_one_hits, 0, "Dodge中はヒットを受けない")


func _test_just_dodge_staggers_attacker() -> void:
	var fixture = _combat_fixture("LONG_TEST", "LONG_TEST")
	var combat = fixture["combat"]
	combat.get_state(1).set_ahoge_available(false)
	combat.press_attack(0)
	combat.release_attack(0)
	_advance_combat(combat, 0.29)
	combat.defend(1)
	_advance_combat(combat, 0.05)
	_expect_equal(
		combat.get_state(0).action_state,
		CombatantStateScript.ActionState.STAGGER,
		"Just Dodgeで攻撃側がStaggerになる"
	)


func _test_attack_clash() -> void:
	var fixture = _combat_fixture("LONG_TEST", "LONG_TEST")
	var combat = fixture["combat"]
	var match_flow = fixture["match"]
	combat.press_attack(0)
	combat.press_attack(1)
	combat.release_attack(0)
	combat.release_attack(1)
	_advance_combat(combat, 0.36)
	_expect_equal(match_flow.round.state.player_one_hits, 0, "ClashでP1ヒットは増えない")
	_expect_equal(match_flow.round.state.player_two_hits, 0, "ClashでP2ヒットは増えない")
	_expect_equal(combat.get_state(0).action_state, CombatantStateScript.ActionState.STAGGER, "ClashでP1 Stagger")
	_expect_equal(combat.get_state(1).action_state, CombatantStateScript.ActionState.STAGGER, "ClashでP2 Stagger")


func _test_short_throw_detach_and_regrow() -> void:
	var fixture = _combat_fixture("SHORT_TEST", "LONG_TEST")
	var combat = fixture["combat"]
	combat.press_attack(0)
	combat.release_attack(0)
	_advance_combat(combat, 0.20)
	_expect_false(combat.get_state(0).ahoge_available, "SHORT投擲開始後はアホ毛不在")
	_expect_true(combat.defend(0), "アホ毛不在中も防御入力可能")
	_expect_equal(combat.get_state(0).action_state, CombatantStateScript.ActionState.DODGE, "SHORT投擲中はDodge")
	_advance_combat(combat, 0.65)
	_expect_true(combat.get_state(0).ahoge_available, "Regrow後はアホ毛復帰")


func _test_real_attacks_complete_best_of_three() -> void:
	var fixture = _combat_fixture("LONG_TEST", "SHORT_TEST")
	var combat = fixture["combat"]
	var match_flow = fixture["match"]

	for _round_index in range(2):
		for _hit_index in range(5):
			_attack_once(combat, 0)

	_expect_equal(match_flow.player_one_rounds, 2, "実攻撃だけで2ラウンド取得できる")
	_expect_equal(match_flow.match_winner, 0, "実攻撃だけでBO3を完了できる")


func _test_device_identity_persists() -> void:
	var test_path := "user://ahoge_device_test_%d.txt" % Time.get_ticks_usec()
	var store = DeviceIdentityStoreScript.new(test_path)
	var first := store.load_or_create()
	var second := store.load_or_create()

	_expect_true(first.length() >= 32, "Device IDは十分な長さで生成される")
	_expect_equal(second, first, "Device IDは同じ保存値を再利用する")
	_expect_true(FileAccess.file_exists(test_path), "Device IDはuser領域へ保存される")

	var absolute_path := ProjectSettings.globalize_path(test_path)
	if FileAccess.file_exists(test_path):
		DirAccess.remove_absolute(absolute_path)



func _test_settings_store_contract() -> void:
	var store = SettingsStoreScript.new("user://settings-unit-unused.cfg")
	var defaults: Dictionary = store.defaults()
	var default_audio: Dictionary = defaults.get("audio", {})
	var default_display: Dictionary = defaults.get("display", {})
	_expect_equal(default_audio.get("master_volume"), 100.0, "Settings Master初期値は100")
	_expect_equal(default_audio.get("bgm_volume"), 100.0, "Settings BGM初期値は100")
	_expect_equal(default_audio.get("se_volume"), 100.0, "Settings SE初期値は100")
	_expect_equal(default_audio.get("voice_volume"), 100.0, "Settings Voice初期値は100")
	_expect_equal(default_display.get("mode"), "windowed", "Settings Mode初期値はwindowed")
	_expect_equal(default_display.get("resolution"), "1280x720", "Settings解像度初期値は1280x720")
	_expect_true(bool(default_display.get("vsync", false)), "Settings VSync初期値はON")

	var normalized: Dictionary = store.normalize({
		"audio": {
			"master_volume": 150,
			"bgm_volume": -10,
			"se_volume": 42,
			"voice_volume": 75,
		},
		"display": {
			"mode": "invalid",
			"resolution": "999x999",
			"vsync": false,
		},
	})
	var audio: Dictionary = normalized.get("audio", {})
	var display: Dictionary = normalized.get("display", {})
	_expect_equal(audio.get("master_volume"), 100.0, "Settings volume上限を100へ正規化する")
	_expect_equal(audio.get("bgm_volume"), 0.0, "Settings volume下限を0へ正規化する")
	_expect_equal(audio.get("se_volume"), 42.0, "Settings有効volumeを維持する")
	_expect_equal(audio.get("voice_volume"), 75.0, "Settings Voice volumeを維持する")
	_expect_equal(display.get("mode"), "windowed", "未知Modeは初期値へ戻す")
	_expect_equal(display.get("resolution"), "1280x720", "未知Resolutionは初期値へ戻す")
	_expect_false(bool(display.get("vsync", true)), "Settings VSync OFFを維持する")


func _test_top_menu_asset_contract() -> void:
	var top_menu = TopMenuScene.instantiate()
	top_menu.call("_ready")

	var background = top_menu.find_child("TopMenuBackgroundPlaceholder", true, false)
	var speed_lines = top_menu.find_child("SpeedLinesTexture", true, false)
	var logo = top_menu.find_child("LogoTexture", true, false)
	var battle_button = top_menu.find_child("OnlineBattleButton", true, false)
	var ranking_button = top_menu.find_child("RankingButton", true, false)
	var settings_button = top_menu.find_child("SettingsButton", true, false)
	var exit_button = top_menu.find_child("ExitButton", true, false)

	_expect_true(background is ColorRect, "Top Menuは専用背景asset導入までBattle背景を使わない")
	_expect_true(speed_lines == null, "Top MenuではBattle用集中線を表示しない")
	_expect_true(logo is TextureRect, "Top Menu logoはTextureRect")
	_expect_true(battle_button is TextureButton, "Top Menu対戦buttonはTextureButton")
	_expect_true(ranking_button is TextureButton, "Top Menu Ranking buttonはTextureButton")
	_expect_true(settings_button is TextureButton, "Top Menu Settings buttonはTextureButton")
	_expect_true(exit_button is TextureButton, "Top Menu Exit buttonはTextureButton")

	if battle_button is TextureButton:
		var texture_button := battle_button as TextureButton
		_expect_true(texture_button.texture_normal != null, "Top Menu button normal assetをloadする")
		_expect_true(texture_button.texture_hover != null, "Top Menu button focus assetをhoverへloadする")
		_expect_true(texture_button.texture_focused != null, "Top Menu button focus assetをfocusへloadする")
		_expect_true(texture_button.texture_pressed != null, "Top Menu button pressed assetをloadする")
		_expect_true(texture_button.texture_disabled != null, "Top Menu button disabled assetをloadする")
		_expect_true(
			texture_button.get_parent() is Control,
			"Top Menu buttonはanimation用row wrapper内へ配置する"
		)

	top_menu.free()


func _test_match_resume_router() -> void:
	_expect_equal(
		MatchResumeRouterScript.resolve({
			"match_mode": "ranked",
			"match_finished": false,
		}),
		MatchResumeRouterScript.DESTINATION_BATTLE,
		"進行中RankedはBattleへ復帰する"
	)
	_expect_equal(
		MatchResumeRouterScript.resolve({
			"match_mode": "ranked",
			"match_finished": true,
		}),
		MatchResumeRouterScript.DESTINATION_RANKED_RESULT,
		"終了済みRankedはResultだけ表示する"
	)
	_expect_equal(
		MatchResumeRouterScript.resolve({
			"match_mode": "friend",
			"match_finished": true,
		}),
		MatchResumeRouterScript.DESTINATION_FRIEND_RESULT,
		"終了済みFriendはResultへ復帰する"
	)
	_expect_equal(
		MatchResumeRouterScript.resolve({}),
		MatchResumeRouterScript.DESTINATION_NONE,
		"空snapshotには復帰先を与えない"
	)

func _test_ranked_matchmaker_query() -> void:
	var query: String = RankedMatchmakerQueryScript.build(1500)
	_expect_equal(
		query,
		"+properties.mode:ranked +properties.rating:>=1400 +properties.rating:<=1600",
		"Ranked Matchmaker初期queryはRating ±100"
	)
	_expect_equal(
		RankedMatchmakerQueryScript.build_with_range(1500, 500),
		"+properties.mode:ranked +properties.rating:>=1000 +properties.rating:<=2000",
		"Ranked Matchmaker最大queryはRating ±500"
	)

	var expected_ranges := {
		0: 100,
		9: 100,
		10: 200,
		20: 300,
		30: 400,
		40: 500,
		50: 500,
		60: 500,
		120: 500,
	}
	for elapsed_seconds in expected_ranges.keys():
		_expect_equal(
			RankedMatchmakerQueryScript.rating_range_for_elapsed_seconds(
				int(elapsed_seconds)
			),
			int(expected_ranges[elapsed_seconds]),
			"Ranked検索幅は経過秒に応じて段階拡大する: %d秒" % int(elapsed_seconds)
		)

	_expect_false(
		RankedMatchmakerQueryScript.is_prolonged_wait(59),
		"59秒では待機延長扱いにしない"
	)
	_expect_true(
		RankedMatchmakerQueryScript.is_prolonged_wait(60),
		"60秒から待機延長扱いにする"
	)


func _test_ranked_recovery_policy() -> void:
	_expect_equal(
		OnlineConfigScript.MATCH_RECOVERY_TIMEOUT_SECONDS,
		10,
		"未解決match復帰の1回timeoutは10秒"
	)
	_expect_equal(
		OnlineConfigScript.MATCH_RECOVERY_RETRY_LIMIT,
		2,
		"未解決match復帰のretry上限は2回"
	)
	_expect_equal(
		OnlineConfigScript.ROUND_BOUNDARY_RECONNECT_WAIT_SECONDS,
		15,
		"Round境界の切断復帰待機は15秒"
	)


func _test_ranked_character_contract() -> void:
	_expect_true(OnlineConfigScript.is_supported_ranked_character_id("LONG_TEST"), "LONG_TESTをRanked characterとして許可する")
	_expect_true(OnlineConfigScript.is_supported_ranked_character_id("SHORT_TEST"), "SHORT_TESTをRanked characterとして許可する")
	_expect_false(OnlineConfigScript.is_supported_ranked_character_id("UNKNOWN"), "未知character_idを拒否する")


func _test_character_catalog_ui_contract() -> void:
	var long_character = CharacterCatalogScript.get_by_id("LONG_TEST")
	var short_character = CharacterCatalogScript.get_by_id("SHORT_TEST")
	_expect_true(not str(long_character.feature_text).is_empty(), "LONG_TESTはCharacter Select特徴文を持つ")
	_expect_true(not str(short_character.feature_text).is_empty(), "SHORT_TESTはCharacter Select特徴文を持つ")
	_expect_true(
		str(long_character.feature_text).contains("長いアホ毛"),
		"LONG_TEST特徴文はLONG型の見た目を説明する"
	)
	_expect_true(
		str(short_character.feature_text).contains("投げ"),
		"SHORT_TEST特徴文はTHROW型の戦い方を説明する"
	)
	_expect_equal(
		str(long_character.head_asset_path),
		"res://assets/characters/prototype/charactor_01/head.png",
		"LONG_TESTはprototype頭部asset pathを固定で持つ"
	)
	_expect_equal(
		str(long_character.ahoge_asset_path),
		"res://assets/characters/prototype/charactor_01/ahoge.png",
		"LONG_TESTはprototypeアホ毛asset pathを固定で持つ"
	)
	_expect_true(
		str(short_character.head_asset_path).is_empty()
			and str(short_character.ahoge_asset_path).is_empty(),
		"SHORT_TESTは未素材のため従来fallbackを維持する"
	)


func _test_ahoge_image_rig_uv_contract() -> void:
	var texture := load("res://assets/characters/prototype/charactor_01/ahoge.png") as Texture2D
	_expect_true(texture != null, "prototypeアホ毛画像をloadできる")
	if texture == null:
		return

	var rig = AhogeImageRigScript.new()
	rig.call("_ready")
	rig.configure(texture, 1.0)

	var polygon = rig.find_child("AhogePolygon", true, false) as Polygon2D
	_expect_true(polygon != null, "画像アホ毛rigはPolygon2Dを生成する")
	if polygon == null:
		rig.free()
		return

	var uv: PackedVector2Array = polygon.uv
	_expect_true(uv.size() > 0, "画像アホ毛rigはUVを生成する")
	if uv.size() > 0:
		var max_x := 0.0
		var max_y := 0.0
		for point in uv:
			max_x = maxf(max_x, point.x)
			max_y = maxf(max_y, point.y)
		var source_size := texture.get_size()
		_expect_true(max_x >= source_size.x - 1.0, "画像アホ毛UVはtexture全幅を参照する")
		_expect_true(max_y >= source_size.y - 1.0, "画像アホ毛UVはtexture全高を参照する")

	rig.free()


func _test_combat_input_protocol() -> void:
	_expect_true(
		CombatInputProtocolScript.is_allowed_action("ATTACK_PRESS"),
		"ATTACK_PRESSは許可された戦闘入力"
	)
	_expect_true(
		CombatInputProtocolScript.is_allowed_action("ATTACK_RELEASE"),
		"ATTACK_RELEASEは許可された戦闘入力"
	)
	_expect_true(
		CombatInputProtocolScript.is_allowed_action("DEFEND"),
		"DEFENDは許可された戦闘入力"
	)
	_expect_false(
		CombatInputProtocolScript.is_allowed_action("UNKNOWN"),
		"未知の戦闘入力は拒否する"
	)

	var payload := CombatInputProtocolScript.build_input_payload(7, "DEFEND")
	var parsed = JSON.parse_string(payload)
	_expect_equal(parsed["input_sequence"], 7.0, "input_sequenceをpayloadへ保持する")
	_expect_equal(parsed["action"], "DEFEND", "actionをpayloadへ保持する")


func _test_authoritative_attack_protocol() -> void:
	var state_payload := JSON.stringify({
		"user_id": "player-1",
		"state": "STRIKE",
		"server_tick": 42,
		"charge_ratio": 0.5,
	})
	var state_event := CombatInputProtocolScript.parse_combat_state_changed_payload(
		state_payload
	)
	_expect_equal(state_event["state"], "STRIKE", "authoritative攻撃状態をdecodeできる")
	_expect_equal(int(state_event["server_tick"]), 42, "攻撃状態のserver tickを保持する")
	_expect_equal(float(state_event["charge_ratio"]), 0.5, "攻撃状態のcharge ratioを保持する")

	var invalid_state := CombatInputProtocolScript.parse_combat_state_changed_payload(
		JSON.stringify({
			"user_id": "player-1",
			"state": "UNKNOWN",
			"server_tick": 42,
			"charge_ratio": 0.5,
		})
	)
	_expect_true(invalid_state.is_empty(), "未知のauthoritative攻撃状態を拒否する")

	var contact_payload := JSON.stringify({
		"attacker_id": "player-1",
		"defender_id": "player-2",
		"server_tick": 48,
		"input_sequence": 2,
		"charge_ratio": 0.5,
	})
	var contact_event := CombatInputProtocolScript.parse_contact_reached_payload(
		contact_payload
	)
	_expect_equal(contact_event["attacker_id"], "player-1", "ContactEvent attackerをdecodeできる")
	_expect_equal(contact_event["defender_id"], "player-2", "ContactEvent defenderをdecodeできる")
	_expect_equal(int(contact_event["input_sequence"]), 2, "ContactEvent release sequenceを保持する")


func _test_authoritative_defense_protocol() -> void:
	var parry_payload := JSON.stringify({
		"user_id": "player-1",
		"state": "PARRY",
		"server_tick": 100,
		"charge_ratio": 0.0,
		"ahoge_available": true,
		"defense_active_until_tick": 106,
		"defense_just_until_tick": 103,
	})
	var parry_event := CombatInputProtocolScript.parse_combat_state_changed_payload(
		parry_payload
	)
	_expect_equal(parry_event["state"], "PARRY", "authoritative PARRY状態をdecodeできる")
	_expect_equal(
		int(parry_event["defense_active_until_tick"]) - int(parry_event["server_tick"]),
		6,
		"PARRY active 0.18秒を30Hzで6tick保持する"
	)
	_expect_equal(
		int(parry_event["defense_just_until_tick"]) - int(parry_event["server_tick"]),
		3,
		"Just受付0.07秒を30Hzで3tick保持する"
	)

	var dodge_payload := JSON.stringify({
		"user_id": "player-1",
		"state": "DODGE",
		"server_tick": 200,
		"charge_ratio": 0.0,
		"ahoge_available": false,
		"defense_active_until_tick": 207,
		"defense_just_until_tick": 203,
	})
	var dodge_event := CombatInputProtocolScript.parse_combat_state_changed_payload(
		dodge_payload
	)
	_expect_equal(dodge_event["state"], "DODGE", "authoritative DODGE状態をdecodeできる")
	_expect_false(bool(dodge_event["ahoge_available"]), "DODGEはahoge unavailable状態を保持できる")


func _test_authoritative_defense_result_protocol() -> void:
	for result in ["NONE", "PARRY", "JUST_PARRY", "DODGE", "JUST_DODGE"]:
		var payload := JSON.stringify({
			"attacker_id": "player-1",
			"defender_id": "player-2",
			"server_tick": 321,
			"input_sequence": 9,
			"result": result,
		})
		var event := CombatInputProtocolScript.parse_defense_resolved_payload(payload)
		_expect_equal(event["result"], result, "DefenseResult %sをdecodeできる" % result)
		_expect_equal(int(event["input_sequence"]), 9, "DefenseResultは攻撃release sequenceを保持する")

	var invalid := CombatInputProtocolScript.parse_defense_resolved_payload(
		JSON.stringify({
			"attacker_id": "player-1",
			"defender_id": "player-2",
			"server_tick": 321,
			"input_sequence": 9,
			"result": "UNKNOWN",
		})
	)
	_expect_true(invalid.is_empty(), "未知のDefenseResultを拒否する")


func _test_authoritative_contact_outcome_protocol() -> void:
	var hit_payload := JSON.stringify({
		"attacker_id": "player-1",
		"defender_id": "player-2",
		"server_tick": 410,
		"input_sequence": 12,
	})
	var hit_event := CombatInputProtocolScript.parse_hit_confirmed_payload(hit_payload)
	_expect_equal(hit_event["attacker_id"], "player-1", "HitConfirmed attackerをdecodeできる")
	_expect_equal(int(hit_event["input_sequence"]), 12, "HitConfirmed sequenceを保持する")

	var clash_payload := JSON.stringify({
		"attacker_a_id": "player-1",
		"attacker_b_id": "player-2",
		"attacker_a_input_sequence": 12,
		"attacker_b_input_sequence": 8,
		"server_tick": 411,
	})
	var clash_event := CombatInputProtocolScript.parse_attack_clash_payload(clash_payload)
	_expect_equal(clash_event["attacker_a_id"], "player-1", "AttackClash attacker Aをdecodeできる")
	_expect_equal(clash_event["attacker_b_id"], "player-2", "AttackClash attacker Bをdecodeできる")
	_expect_equal(int(clash_event["attacker_a_input_sequence"]), 12, "AttackClash A sequenceを保持する")
	_expect_equal(int(clash_event["attacker_b_input_sequence"]), 8, "AttackClash B sequenceを保持する")


func _test_authoritative_stagger_protocol() -> void:
	var stagger_payload := JSON.stringify({
		"user_id": "player-1",
		"state": "STAGGER",
		"server_tick": 500,
		"charge_ratio": 0.0,
		"ahoge_available": true,
		"defense_active_until_tick": -1,
		"defense_just_until_tick": -1,
		"stagger_until_tick": 514,
	})
	var event := CombatInputProtocolScript.parse_combat_state_changed_payload(stagger_payload)
	_expect_equal(event["state"], "STAGGER", "authoritative STAGGER状態をdecodeできる")
	_expect_equal(
		int(event["stagger_until_tick"]) - int(event["server_tick"]),
		14,
		"Stagger 0.45秒を30Hzで14tick保持する"
	)


func _test_authoritative_hit_count_protocol() -> void:
	var payload := JSON.stringify({
		"user_id": "player-1",
		"hit_count": 2,
		"server_tick": 600,
		"input_sequence": 14,
	})
	var event := CombatInputProtocolScript.parse_round_hit_count_changed_payload(payload)
	_expect_equal(event["user_id"], "player-1", "Round Hit count userをdecodeできる")
	_expect_equal(int(event["hit_count"]), 2, "Round Hit countをdecodeできる")
	_expect_equal(int(event["input_sequence"]), 14, "Round Hit countはHit元sequenceを保持する")

	var invalid := CombatInputProtocolScript.parse_round_hit_count_changed_payload(
		JSON.stringify({
			"user_id": "player-1",
			"hit_count": -1,
			"server_tick": 600,
			"input_sequence": 14,
		})
	)
	_expect_true(invalid.is_empty(), "負のRound Hit countを拒否する")


func _test_authoritative_round_timer_protocol() -> void:
	var start_payload := JSON.stringify({
		"remaining_seconds": 85,
		"server_tick": 700,
	})
	var start_event := CombatInputProtocolScript.parse_round_timer_changed_payload(start_payload)
	_expect_equal(int(start_event["remaining_seconds"]), 85, "Round timer 85をdecodeできる")
	_expect_equal(int(start_event["server_tick"]), 700, "Round timer server tickを保持する")

	var zero_payload := JSON.stringify({
		"remaining_seconds": 0,
		"server_tick": 3250,
	})
	var zero_event := CombatInputProtocolScript.parse_round_timer_changed_payload(zero_payload)
	_expect_equal(int(zero_event["remaining_seconds"]), 0, "Round timer 0をdecodeできる")

	for invalid_seconds in [-1, 86]:
		var invalid := CombatInputProtocolScript.parse_round_timer_changed_payload(
			JSON.stringify({
				"remaining_seconds": invalid_seconds,
				"server_tick": 700,
			})
		)
		_expect_true(invalid.is_empty(), "範囲外Round timerを拒否する")


func _test_authoritative_round_locked_protocol() -> void:
	var payload := JSON.stringify({
		"user_id": "player-1",
		"state": "ROUND_LOCKED",
		"server_tick": 800,
		"charge_ratio": 0.0,
	})
	var event := CombatInputProtocolScript.parse_combat_state_changed_payload(payload)
	_expect_equal(event["state"], "ROUND_LOCKED", "ROUND_LOCKED状態をdecodeできる")


func _test_authoritative_draw_protocol() -> void:
	var draw_round := CombatInputProtocolScript.parse_round_result_payload(
		JSON.stringify({
			"round_number": 1,
			"winner_user_id": "",
			"loser_user_id": "",
			"finish_cause": "TIMEOUT_DRAW",
			"winner_hits": 2,
			"loser_hits": 2,
			"is_draw": true,
			"server_tick": 900,
		})
	)
	_expect_true(bool(draw_round.get("is_draw", false)), "timeout同点RoundをDrawとしてdecodeできる")
	_expect_equal(str(draw_round.get("finish_cause", "")), "TIMEOUT_DRAW", "Draw Round finish causeを保持する")

	var legacy_overtime := CombatInputProtocolScript.parse_round_result_payload(
		JSON.stringify({
			"round_number": 1,
			"winner_user_id": "player-1",
			"loser_user_id": "player-2",
			"finish_cause": "OVERTIME_HIT",
			"winner_hits": 3,
			"loser_hits": 2,
			"server_tick": 901,
		})
	)
	_expect_true(legacy_overtime.is_empty(), "旧OVERTIME_HIT Round Resultを拒否する")


func _test_authoritative_round_result_protocol() -> void:
	var payload := JSON.stringify({
		"round_number": 1,
		"winner_user_id": "player-1",
		"loser_user_id": "player-2",
		"finish_cause": "HIT_LIMIT",
		"winner_hits": 5,
		"loser_hits": 2,
		"is_draw": false,
		"server_tick": 1000,
	})
	var event := CombatInputProtocolScript.parse_round_result_payload(payload)
	_expect_equal(int(event["round_number"]), 1, "Round Result round_numberをdecodeできる")
	_expect_equal(event["winner_user_id"], "player-1", "Round Result winnerをdecodeできる")
	_expect_equal(event["finish_cause"], "HIT_LIMIT", "Round Result finish causeをdecodeできる")
	_expect_equal(int(event["winner_hits"]), 5, "Round Result winner hitsをdecodeできる")

	var forfeit_event := CombatInputProtocolScript.parse_round_result_payload(
		JSON.stringify({
			"round_number": 2,
			"winner_user_id": "player-1",
			"loser_user_id": "player-2",
			"finish_cause": "DISCONNECT_FORFEIT",
			"winner_hits": 0,
			"loser_hits": 0,
			"is_draw": false,
			"server_tick": 2000,
		})
	)
	_expect_equal(
		str(forfeit_event.get("finish_cause", "")),
		"DISCONNECT_FORFEIT",
		"Round境界timeoutの不戦敗Resultをdecodeできる"
	)

	var invalid := CombatInputProtocolScript.parse_round_result_payload(
		JSON.stringify({
			"round_number": 0,
			"winner_user_id": "player-1",
			"loser_user_id": "player-1",
			"finish_cause": "UNKNOWN",
			"winner_hits": -1,
			"loser_hits": 0,
			"server_tick": -1,
		})
	)
	_expect_true(invalid.is_empty(), "不正なRound Resultを拒否する")


func _test_authoritative_bo3_protocol() -> void:
	var score_payload := JSON.stringify({
		"completed_round_number": 2,
		"round_winner_user_id": "player-2",
		"round_draw": false,
		"round_wins_by_user": {"player-1": 1, "player-2": 1},
		"match_finished": false,
		"server_tick": 1200,
	})
	var score_event := CombatInputProtocolScript.parse_bo3_score_changed_payload(score_payload)
	_expect_equal(int(score_event["completed_round_number"]), 2, "BO3 completed roundをdecodeできる")
	_expect_equal(int(score_event["round_wins_by_user"]["player-1"]), 1, "BO3 P1 scoreをdecodeできる")
	_expect_equal(bool(score_event["match_finished"]), false, "BO3継続状態をdecodeできる")

	var draw_score := CombatInputProtocolScript.parse_bo3_score_changed_payload(
		JSON.stringify({
			"completed_round_number": 2,
			"round_winner_user_id": "",
			"round_draw": true,
			"round_wins_by_user": {"player-1": 2, "player-2": 2},
			"match_finished": true,
			"server_tick": 1200,
		})
	)
	_expect_true(bool(draw_score.get("round_draw", false)), "BO3 Draw Roundをdecodeできる")

	var started_payload := JSON.stringify({
		"round_number": 3,
		"round_wins_by_user": {"player-1": 1, "player-2": 1},
		"server_tick": 1201,
	})
	var started_event := CombatInputProtocolScript.parse_round_started_payload(started_payload)
	_expect_equal(int(started_event["round_number"]), 3, "Round Started round番号をdecodeできる")
	_expect_equal(int(started_event["round_wins_by_user"]["player-2"]), 1, "Round Started scoreをdecodeできる")

	var invalid := CombatInputProtocolScript.parse_round_started_payload(
		JSON.stringify({
			"round_number": 4,
			"round_wins_by_user": {"player-1": 3},
			"server_tick": -1,
		})
	)
	_expect_true(invalid.is_empty(), "不正なBO3 Round Startedを拒否する")


func _test_authoritative_match_result_protocol() -> void:
	var payload := JSON.stringify({
		"winner_user_id": "player-1",
		"loser_user_id": "player-2",
		"round_wins_by_user": {"player-1": 2, "player-2": 1},
		"final_round_number": 3,
		"finish_cause": "BO3",
		"is_draw": false,
		"server_tick": 1300,
	})
	var event := CombatInputProtocolScript.parse_match_result_payload(payload)
	_expect_equal(event["winner_user_id"], "player-1", "Match Result winnerをdecodeできる")
	_expect_equal(int(event["round_wins_by_user"]["player-1"]), 2, "Match Result winner scoreをdecodeできる")
	_expect_equal(int(event["final_round_number"]), 3, "Match Result final roundをdecodeできる")
	_expect_equal(str(event["finish_cause"]), "BO3", "Match Result finish causeをdecodeできる")

	var draw_event := CombatInputProtocolScript.parse_match_result_payload(
		JSON.stringify({
			"winner_user_id": "",
			"loser_user_id": "",
			"round_wins_by_user": {"player-1": 2, "player-2": 2},
			"final_round_number": 2,
			"finish_cause": "BO3_DRAW",
			"is_draw": true,
			"server_tick": 1301,
		})
	)
	_expect_true(bool(draw_event.get("is_draw", false)), "Match Drawをdecodeできる")
	_expect_equal(str(draw_event.get("finish_cause", "")), "BO3_DRAW", "Match Draw finish causeを保持する")

	var legacy_disconnect_payload := JSON.stringify({
		"winner_user_id": "player-1",
		"loser_user_id": "player-2",
		"round_wins_by_user": {"player-1": 0, "player-2": 0},
		"final_round_number": 1,
		"finish_cause": "DISCONNECT_TIMEOUT",
		"server_tick": 700,
	})
	var legacy_disconnect_event := CombatInputProtocolScript.parse_match_result_payload(
		legacy_disconnect_payload
	)
	_expect_true(
		legacy_disconnect_event.is_empty(),
		"旧Match強制敗北DISCONNECT_TIMEOUTを拒否する"
	)

	var invalid := CombatInputProtocolScript.parse_match_result_payload(
		JSON.stringify({
			"winner_user_id": "player-1",
			"loser_user_id": "player-2",
			"round_wins_by_user": {"player-1": 1, "player-2": 1},
			"final_round_number": 1,
			"finish_cause": "BO3",
			"server_tick": -1,
		})
	)
	_expect_true(invalid.is_empty(), "不正なMatch Resultを拒否する")


func _test_authoritative_round_countdown_protocol() -> void:
	var payload := JSON.stringify({
		"round_number": 2,
		"countdown_value": 3,
		"server_tick": 900,
	})
	var event := CombatInputProtocolScript.parse_round_countdown_changed_payload(payload)
	_expect_equal(int(event["round_number"]), 2, "Round Countdown round番号をdecodeできる")
	_expect_equal(int(event["countdown_value"]), 3, "Round Countdown値をdecodeできる")
	_expect_equal(int(event["server_tick"]), 900, "Round Countdown server tickをdecodeできる")

	var go_event := CombatInputProtocolScript.parse_round_countdown_changed_payload(
		JSON.stringify({
			"round_number": 3,
			"countdown_value": 0,
			"server_tick": 1200,
		})
	)
	_expect_equal(int(go_event["countdown_value"]), 0, "Round Countdown GOをdecodeできる")

	var invalid := CombatInputProtocolScript.parse_round_countdown_changed_payload(
		JSON.stringify({
			"round_number": 4,
			"countdown_value": 4,
			"server_tick": -1,
		})
	)
	_expect_true(invalid.is_empty(), "不正なRound Countdownを拒否する")


func _test_authoritative_match_snapshot_protocol() -> void:
	var payload := JSON.stringify({
		"server_tick": 1500,
		"match_mode": "ranked",
		"round_number": 2,
		"round_wins_by_user": {"player-1": 1, "player-2": 0},
		"round_hit_count_by_user": {"player-1": 3, "player-2": 1},
		"remaining_seconds": 47,
		"round_finished": false,
		"round_winner_user_id": "",
		"round_finish_cause": "NONE",
		"round_draw": false,
		"round_awaiting_overtime": false,
		"round_overtime": false,
		"round_countdown_active": false,
		"round_countdown_value": 0,
		"match_finished": false,
		"match_winner_user_id": "",
		"match_finish_cause": "NONE",
		"match_draw": false,
		"character_id_by_user": {"player-1": "LONG_TEST", "player-2": "SHORT_TEST"},
		"last_input_sequence": 12,
		"combat_state_by_user": {
			"player-1": {
				"state": "IDLE",
				"charge_ratio": 0.0,
				"ahoge_available": true,
			},
			"player-2": {
				"state": "STAGGER",
				"charge_ratio": 0.0,
				"ahoge_available": false,
			},
		},
	})
	var event := CombatInputProtocolScript.parse_match_snapshot_payload(payload)
	_expect_equal(int(event["server_tick"]), 1500, "Match Snapshot server tickをdecodeできる")
	_expect_equal(str(event["match_mode"]), "ranked", "Match Snapshot modeをdecodeできる")
	_expect_equal(int(event["round_number"]), 2, "Match Snapshot Roundをdecodeできる")
	_expect_equal(int(event["remaining_seconds"]), 47, "Match Snapshot timerをdecodeできる")
	_expect_equal(int(event["last_input_sequence"]), 12, "Match Snapshot input sequenceをdecodeできる")
	_expect_equal(
		str(event["combat_state_by_user"]["player-2"]["state"]),
		"STAGGER",
		"Match Snapshot combat stateをdecodeできる"
	)

	var invalid := CombatInputProtocolScript.parse_match_snapshot_payload(
		JSON.stringify({
			"server_tick": -1,
			"round_number": 4,
		})
	)
	_expect_true(invalid.is_empty(), "不正なMatch Snapshotを拒否する")


func _test_authoritative_player_connection_protocol() -> void:
	var disconnected := CombatInputProtocolScript.parse_player_connection_changed_payload(
		JSON.stringify({
			"user_id": "player-2",
			"connected": false,
			"reconnect_deadline_tick": 1950,
			"server_tick": 1500,
		})
	)
	_expect_equal(str(disconnected["user_id"]), "player-2", "切断user IDをdecodeできる")
	_expect_false(bool(disconnected["connected"]), "切断状態をdecodeできる")
	_expect_equal(int(disconnected["reconnect_deadline_tick"]), 1950, "再接続deadlineをdecodeできる")

	var active_round_disconnected := CombatInputProtocolScript.parse_player_connection_changed_payload(
		JSON.stringify({
			"user_id": "player-2",
			"connected": false,
			"reconnect_deadline_tick": -1,
			"server_tick": 1550,
		})
	)
	_expect_false(
		bool(active_round_disconnected["connected"]),
		"active Round切断状態をdecodeできる"
	)
	_expect_equal(
		int(active_round_disconnected["reconnect_deadline_tick"]),
		-1,
		"active Round切断のdeadlineなしをdecodeできる"
	)

	var connected := CombatInputProtocolScript.parse_player_connection_changed_payload(
		JSON.stringify({
			"user_id": "player-2",
			"connected": true,
			"reconnect_deadline_tick": -1,
			"server_tick": 1600,
		})
	)
	_expect_true(bool(connected["connected"]), "再接続状態をdecodeできる")

	var invalid := CombatInputProtocolScript.parse_player_connection_changed_payload(
		JSON.stringify({
			"user_id": "",
			"connected": false,
			"reconnect_deadline_tick": 1,
			"server_tick": 2,
		})
	)
	_expect_true(invalid.is_empty(), "不正な接続状態eventを拒否する")


func _combat_fixture(player_one_id: String, player_two_id: String) -> Dictionary:
	var config = CombatConfigScript.new()
	var match_flow = MatchCoordinatorScript.new(config)
	var player_one = CharacterCatalogScript.get_by_id(player_one_id)
	var player_two = CharacterCatalogScript.get_by_id(player_two_id)
	var combat = CombatResolverScript.new(config, match_flow, player_one, player_two)
	return {
		"config": config,
		"match": match_flow,
		"combat": combat,
	}


func _attack_once(combat, attacker_index: int) -> void:
	while combat.get_state(attacker_index).action_state != CombatantStateScript.ActionState.IDLE:
		_advance_combat(combat, 0.05)
	combat.press_attack(attacker_index)
	combat.release_attack(attacker_index)
	_advance_combat(combat, 0.90)


func _advance_combat(combat, seconds: float) -> void:
	var remaining := seconds
	while remaining > 0.0:
		var step := minf(0.01, remaining)
		combat.tick(step)
		remaining -= step


func _expect_true(value: bool, message: String) -> void:
	_checks += 1
	if not value:
		_failures.append("FAIL: %s" % message)


func _expect_false(value: bool, message: String) -> void:
	_expect_true(not value, message)


func _expect_equal(actual: Variant, expected: Variant, message: String) -> void:
	_checks += 1
	if actual != expected:
		_failures.append("FAIL: %s (actual=%s expected=%s)" % [message, str(actual), str(expected)])
