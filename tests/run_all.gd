extends SceneTree

const CombatConfigScript := preload("res://src/config/combat_config.gd")
const CombatantStateScript := preload("res://src/domain/combatant_state.gd")
const RoundCoordinatorScript := preload("res://src/services/round_coordinator.gd")
const MatchCoordinatorScript := preload("res://src/services/match_coordinator.gd")

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
