extends RefCounted

const OPCODE_COMBAT_INPUT: int = 1
const OPCODE_INPUT_ACCEPTED: int = 101
const OPCODE_COMBAT_STATE_CHANGED: int = 102
const OPCODE_CONTACT_REACHED: int = 103
const OPCODE_DEFENSE_RESOLVED: int = 104

const ACTION_ATTACK_PRESS: String = "ATTACK_PRESS"
const ACTION_ATTACK_RELEASE: String = "ATTACK_RELEASE"
const ACTION_DEFEND: String = "DEFEND"

const _ALLOWED_ACTIONS := {
	ACTION_ATTACK_PRESS: true,
	ACTION_ATTACK_RELEASE: true,
	ACTION_DEFEND: true,
}

const _ALLOWED_COMBAT_STATES := {
	"IDLE": true,
	"CHARGING": true,
	"WINDUP": true,
	"STRIKE": true,
	"COOLDOWN": true,
	"PARRY": true,
	"DODGE": true,
}

const _ALLOWED_DEFENSE_RESULTS := {
	"NONE": true,
	"PARRY": true,
	"JUST_PARRY": true,
	"DODGE": true,
	"JUST_DODGE": true,
}


static func is_allowed_action(action: String) -> bool:
	return bool(_ALLOWED_ACTIONS.get(action, false))


static func build_input_payload(input_sequence: int, action: String) -> String:
	return JSON.stringify({
		"input_sequence": input_sequence,
		"action": action,
	})


static func parse_accepted_payload(payload: String) -> Dictionary:
	var parsed = JSON.parse_string(payload)
	if not parsed is Dictionary:
		return {}

	if not parsed.has("user_id") 			or not parsed.has("input_sequence") 			or not parsed.has("action") 			or not parsed.has("server_tick"):
		return {}

	if not is_allowed_action(str(parsed["action"])):
		return {}

	return parsed


static func parse_combat_state_changed_payload(payload: String) -> Dictionary:
	var parsed = JSON.parse_string(payload)
	if not parsed is Dictionary:
		return {}

	if not parsed.has("user_id") 			or not parsed.has("state") 			or not parsed.has("server_tick") 			or not parsed.has("charge_ratio"):
		return {}

	if not bool(_ALLOWED_COMBAT_STATES.get(str(parsed["state"]), false)):
		return {}

	return parsed


static func parse_contact_reached_payload(payload: String) -> Dictionary:
	var parsed = JSON.parse_string(payload)
	if not parsed is Dictionary:
		return {}

	if not parsed.has("attacker_id") 			or not parsed.has("defender_id") 			or not parsed.has("server_tick") 			or not parsed.has("input_sequence") 			or not parsed.has("charge_ratio"):
		return {}

	return parsed


static func is_allowed_defense_result(result: String) -> bool:
	return bool(_ALLOWED_DEFENSE_RESULTS.get(result, false))


static func parse_defense_resolved_payload(payload: String) -> Dictionary:
	var parsed = JSON.parse_string(payload)
	if not parsed is Dictionary:
		return {}

	if not parsed.has("attacker_id") \
			or not parsed.has("defender_id") \
			or not parsed.has("server_tick") \
			or not parsed.has("input_sequence") \
			or not parsed.has("result"):
		return {}

	if not is_allowed_defense_result(str(parsed["result"])):
		return {}

	return parsed
