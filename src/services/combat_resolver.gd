extends RefCounted

const CombatantStateScript := preload("res://src/domain/combatant_state.gd")
const AttackDefinitionScript := preload("res://src/domain/attack_definition.gd")
const DefenseResolverScript := preload("res://src/services/defense_resolver.gd")

signal combat_event(event_name: String, actor_index: int)
signal ahoge_availability_changed(player_index: int, available: bool)

var config
var match_flow
var characters: Array = []
var states: Array = []
var attack_definitions: Array = []

var _attacks: Array = [{}, {}]
var _regrow_remaining: Array = [0.0, 0.0]
var _clock_seconds: float = 0.0


func _init(config_value, match_value, player_one_character, player_two_character) -> void:
	config = config_value
	match_flow = match_value
	characters = [player_one_character, player_two_character]
	states = [
		CombatantStateScript.new(config),
		CombatantStateScript.new(config),
	]
	attack_definitions = [
		AttackDefinitionScript.create_for_character(player_one_character, config),
		AttackDefinitionScript.create_for_character(player_two_character, config),
	]

	match_flow.round_finished.connect(_on_round_finished)
	match_flow.round_started.connect(_on_round_started)


func press_attack(player_index: int) -> bool:
	if not _valid_player_index(player_index):
		return false
	return states[player_index].begin_attack()


func release_attack(player_index: int) -> bool:
	if not _valid_player_index(player_index):
		return false
	if not states[player_index].release_attack():
		return false

	_attacks[player_index] = {
		"active": true,
		"scheduled": false,
		"contact_at": 0.0,
	}
	return true


func defend(player_index: int) -> bool:
	if not _valid_player_index(player_index):
		return false

	var state = states[player_index]
	var previous_state: int = state.action_state
	if not state.start_defense():
		return false

	if previous_state in [
		CombatantStateScript.ActionState.CHARGING,
		CombatantStateScript.ActionState.WINDUP,
		CombatantStateScript.ActionState.STRIKE,
	]:
		_clear_attack(player_index)

	combat_event.emit(state.action_state_name(), player_index)
	return true


func tick(delta: float) -> void:
	if delta <= 0.0:
		return

	_clock_seconds += delta
	match_flow.tick(delta)

	for player_index in range(2):
		var state = states[player_index]
		var previous_state: int = state.action_state
		state.tick(delta)

		if previous_state != CombatantStateScript.ActionState.STRIKE 			and state.action_state == CombatantStateScript.ActionState.STRIKE 			and bool(_attacks[player_index].get("active", false)):
			_on_strike_started(player_index)

		_tick_regrow(player_index, delta)

	_resolve_contacts()


func get_state(player_index: int):
	return states[player_index]


func get_character(player_index: int):
	return characters[player_index]


func _on_strike_started(player_index: int) -> void:
	var attack_definition = attack_definitions[player_index]
	var state = states[player_index]
	var strike_seconds: float = state.action_remaining_seconds

	_attacks[player_index]["scheduled"] = true
	_attacks[player_index]["contact_at"] = (
		_clock_seconds + strike_seconds * attack_definition.contact_ratio
	)

	if attack_definition.ahoge_detach:
		state.set_ahoge_available(false)
		_regrow_remaining[player_index] = attack_definition.ahoge_regrow_seconds
		ahoge_availability_changed.emit(player_index, false)
		combat_event.emit("THROW", player_index)


func _tick_regrow(player_index: int, delta: float) -> void:
	if float(_regrow_remaining[player_index]) <= 0.0:
		return

	_regrow_remaining[player_index] = maxf(
		float(_regrow_remaining[player_index]) - delta,
		0.0
	)

	if float(_regrow_remaining[player_index]) <= 0.0:
		states[player_index].set_ahoge_available(true)
		ahoge_availability_changed.emit(player_index, true)
		combat_event.emit("REGROW", player_index)


func _resolve_contacts() -> void:
	var first_active := _has_scheduled_attack(0)
	var second_active := _has_scheduled_attack(1)

	if first_active and second_active:
		var first_time := float(_attacks[0]["contact_at"])
		var second_time := float(_attacks[1]["contact_at"])
		if absf(first_time - second_time) <= config.attack_clash_window_seconds:
			if _clock_seconds >= maxf(first_time, second_time):
				_resolve_clash()
			return

	var due: Array = []
	for player_index in range(2):
		if _has_scheduled_attack(player_index):
			if _clock_seconds >= float(_attacks[player_index]["contact_at"]):
				due.append(player_index)

	due.sort_custom(func(a, b) -> bool:
		return float(_attacks[a]["contact_at"]) < float(_attacks[b]["contact_at"])
	)

	for player_index in due:
		if _has_scheduled_attack(player_index):
			_resolve_contact(player_index)


func _resolve_contact(attacker_index: int) -> void:
	var defender_index := 1 - attacker_index
	var defense_result := DefenseResolverScript.resolve(states[defender_index], config)

	_clear_attack(attacker_index)

	match defense_result:
		DefenseResolverScript.DefenseResult.JUST_PARRY:
			states[attacker_index].apply_stagger()
			combat_event.emit("JUST PARRY", defender_index)
		DefenseResolverScript.DefenseResult.PARRY:
			combat_event.emit("PARRY", defender_index)
		DefenseResolverScript.DefenseResult.JUST_DODGE:
			states[attacker_index].apply_stagger()
			combat_event.emit("JUST DODGE", defender_index)
		DefenseResolverScript.DefenseResult.DODGE:
			combat_event.emit("DODGE", defender_index)
		_:
			match_flow.register_hit(attacker_index)
			combat_event.emit("HIT", attacker_index)


func _resolve_clash() -> void:
	_clear_attack(0)
	_clear_attack(1)
	states[0].apply_stagger()
	states[1].apply_stagger()
	combat_event.emit("CLASH", -1)


func _on_round_finished(_round_number: int, _winner: int, _p1_rounds: int, _p2_rounds: int) -> void:
	for player_index in range(2):
		_clear_attack(player_index)
		states[player_index].lock_round()


func _on_round_started(_round_number: int) -> void:
	for player_index in range(2):
		_clear_attack(player_index)
		_regrow_remaining[player_index] = 0.0
		states[player_index].unlock_round()


func _has_scheduled_attack(player_index: int) -> bool:
	return (
		bool(_attacks[player_index].get("active", false))
		and bool(_attacks[player_index].get("scheduled", false))
	)


func _clear_attack(player_index: int) -> void:
	_attacks[player_index] = {}


func _valid_player_index(player_index: int) -> bool:
	return player_index == 0 or player_index == 1
