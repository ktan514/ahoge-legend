extends RefCounted

const CombatantStateScript := preload("res://src/domain/combatant_state.gd")

enum DefenseResult {
	NONE,
	PARRY,
	JUST_PARRY,
	DODGE,
	JUST_DODGE,
}


static func resolve(defender_state, config) -> int:
	if defender_state.action_state == CombatantStateScript.ActionState.PARRY:
		if defender_state.state_elapsed_seconds <= config.just_parry_seconds:
			return DefenseResult.JUST_PARRY
		return DefenseResult.PARRY

	if defender_state.action_state == CombatantStateScript.ActionState.DODGE:
		if defender_state.state_elapsed_seconds <= config.just_dodge_seconds:
			return DefenseResult.JUST_DODGE
		return DefenseResult.DODGE

	return DefenseResult.NONE


static func result_name(result: int) -> String:
	return str(DefenseResult.keys()[result])
