extends RefCounted

const OPCODE_COMBAT_INPUT: int = 1
const OPCODE_INPUT_ACCEPTED: int = 101
const OPCODE_COMBAT_STATE_CHANGED: int = 102
const OPCODE_CONTACT_REACHED: int = 103
const OPCODE_DEFENSE_RESOLVED: int = 104
const OPCODE_HIT_CONFIRMED: int = 105
const OPCODE_ATTACK_CLASH: int = 106
const OPCODE_ROUND_HIT_COUNT_CHANGED: int = 107
const OPCODE_ROUND_TIMER_CHANGED: int = 108
const OPCODE_ROUND_OVERTIME_STARTED: int = 109
const OPCODE_ROUND_RESULT: int = 110

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
	"STAGGER": true,
	"ROUND_LOCKED": true,
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

	if str(parsed["state"]) == "STAGGER" and not parsed.has("stagger_until_tick"):
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


static func parse_hit_confirmed_payload(payload: String) -> Dictionary:
	var parsed = JSON.parse_string(payload)
	if not parsed is Dictionary:
		return {}
	if not parsed.has("attacker_id") \
			or not parsed.has("defender_id") \
			or not parsed.has("server_tick") \
			or not parsed.has("input_sequence"):
		return {}
	return parsed


static func parse_attack_clash_payload(payload: String) -> Dictionary:
	var parsed = JSON.parse_string(payload)
	if not parsed is Dictionary:
		return {}
	if not parsed.has("attacker_a_id") \
			or not parsed.has("attacker_b_id") \
			or not parsed.has("attacker_a_input_sequence") \
			or not parsed.has("attacker_b_input_sequence") \
			or not parsed.has("server_tick"):
		return {}
	return parsed


static func parse_round_hit_count_changed_payload(payload: String) -> Dictionary:
	var parsed = JSON.parse_string(payload)
	if not parsed is Dictionary:
		return {}
	if not parsed.has("user_id") \
			or not parsed.has("hit_count") \
			or not parsed.has("server_tick") \
			or not parsed.has("input_sequence"):
		return {}
	if int(parsed["hit_count"]) < 0:
		return {}
	return parsed


static func parse_round_timer_changed_payload(payload: String) -> Dictionary:
	var parsed = JSON.parse_string(payload)
	if not parsed is Dictionary:
		return {}
	if not parsed.has("remaining_seconds") \
			or not parsed.has("server_tick"):
		return {}
	var remaining_seconds := int(parsed["remaining_seconds"])
	if remaining_seconds < 0 or remaining_seconds > 85:
		return {}
	return parsed


static func parse_round_overtime_started_payload(payload: String) -> Dictionary:
	var parsed = JSON.parse_string(payload)
	if not parsed is Dictionary:
		return {}
	if not parsed.has("server_tick"):
		return {}
	if int(parsed["server_tick"]) < 0:
		return {}
	return parsed


static func parse_round_result_payload(payload: String) -> Dictionary:
	var parsed = JSON.parse_string(payload)
	if not parsed is Dictionary:
		return {}
	for key in [
		"round_number",
		"winner_user_id",
		"loser_user_id",
		"finish_cause",
		"winner_hits",
		"loser_hits",
		"server_tick",
	]:
		if not parsed.has(key):
			return {}
	var round_number := int(parsed["round_number"])
	var winner_user_id := str(parsed["winner_user_id"])
	var loser_user_id := str(parsed["loser_user_id"])
	var finish_cause := str(parsed["finish_cause"])
	if round_number < 1:
		return {}
	if winner_user_id.is_empty() or loser_user_id.is_empty() or winner_user_id == loser_user_id:
		return {}
	if finish_cause not in ["HIT_LIMIT", "TIMEOUT", "OVERTIME_HIT"]:
		return {}
	if int(parsed["winner_hits"]) < 0 or int(parsed["loser_hits"]) < 0:
		return {}
	if int(parsed["server_tick"]) < 0:
		return {}
	return parsed
