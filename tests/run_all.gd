extends SceneTree

const CombatConfigScript := preload("res://src/config/combat_config.gd")
const CombatantStateScript := preload("res://src/domain/combatant_state.gd")
const CharacterCatalogScript := preload("res://src/domain/character_catalog.gd")
const RoundCoordinatorScript := preload("res://src/services/round_coordinator.gd")
const MatchCoordinatorScript := preload("res://src/services/match_coordinator.gd")
const CombatResolverScript := preload("res://src/services/combat_resolver.gd")
const DeviceIdentityStoreScript := preload("res://src/online/device_identity_store.gd")
const RankedMatchmakerQueryScript := preload("res://src/online/ranked_matchmaker_query.gd")
const OnlineConfigScript := preload("res://src/config/online_config.gd")
const CombatInputProtocolScript := preload("res://src/online/combat_input_protocol.gd")

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
	_test_ranked_matchmaker_query()
	_test_ranked_character_contract()
	_test_combat_input_protocol()
	_test_authoritative_attack_protocol()
	_test_authoritative_defense_protocol()
	_test_authoritative_defense_result_protocol()
	_test_authoritative_contact_outcome_protocol()
	_test_authoritative_stagger_protocol()
	_test_authoritative_hit_count_protocol()
	_test_authoritative_round_timer_protocol()

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


func _test_ranked_matchmaker_query() -> void:
	var query: String = RankedMatchmakerQueryScript.build(1500)
	_expect_equal(
		query,
		"+properties.mode:ranked +properties.rating:>=1400 +properties.rating:<=1600",
		"Ranked Matchmaker初期queryはRating ±100"
	)


func _test_ranked_character_contract() -> void:
	_expect_true(OnlineConfigScript.is_supported_ranked_character_id("LONG_TEST"), "LONG_TESTをRanked characterとして許可する")
	_expect_true(OnlineConfigScript.is_supported_ranked_character_id("SHORT_TEST"), "SHORT_TESTをRanked characterとして許可する")
	_expect_false(OnlineConfigScript.is_supported_ranked_character_id("UNKNOWN"), "未知character_idを拒否する")


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
