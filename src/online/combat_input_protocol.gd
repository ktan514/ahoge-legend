extends RefCounted

const OPCODE_COMBAT_INPUT: int = 1
const OPCODE_INPUT_ACCEPTED: int = 101

const ACTION_ATTACK_PRESS: String = "ATTACK_PRESS"
const ACTION_ATTACK_RELEASE: String = "ATTACK_RELEASE"
const ACTION_DEFEND: String = "DEFEND"

const _ALLOWED_ACTIONS := {
	ACTION_ATTACK_PRESS: true,
	ACTION_ATTACK_RELEASE: true,
	ACTION_DEFEND: true,
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
