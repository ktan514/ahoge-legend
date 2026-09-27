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
const OPCODE_BO3_SCORE_CHANGED: int = 111
const OPCODE_ROUND_STARTED: int = 112
const OPCODE_MATCH_RESULT: int = 113
const OPCODE_ROUND_COUNTDOWN_CHANGED: int = 114
const OPCODE_MATCH_SNAPSHOT: int = 115
const OPCODE_PLAYER_CONNECTION_CHANGED: int = 116

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


static func _valid_round_wins(value) -> bool:
	if not value is Dictionary:
		return false
	for user_id in value.keys():
		if str(user_id).is_empty():
			return false
		var rounds := int(value[user_id])
		if rounds < 0 or rounds > 2:
			return false
	return true


static func parse_bo3_score_changed_payload(payload: String) -> Dictionary:
	var parsed = JSON.parse_string(payload)
	if not parsed is Dictionary:
		return {}
	for key in [
		"completed_round_number",
		"round_winner_user_id",
		"round_wins_by_user",
		"match_finished",
		"server_tick",
	]:
		if not parsed.has(key):
			return {}
	if int(parsed["completed_round_number"]) < 1 or int(parsed["completed_round_number"]) > 3:
		return {}
	if str(parsed["round_winner_user_id"]).is_empty():
		return {}
	if not _valid_round_wins(parsed["round_wins_by_user"]):
		return {}
	if int(parsed["server_tick"]) < 0:
		return {}
	return parsed


static func parse_round_started_payload(payload: String) -> Dictionary:
	var parsed = JSON.parse_string(payload)
	if not parsed is Dictionary:
		return {}
	for key in ["round_number", "round_wins_by_user", "server_tick"]:
		if not parsed.has(key):
			return {}
	if int(parsed["round_number"]) < 1 or int(parsed["round_number"]) > 3:
		return {}
	if not _valid_round_wins(parsed["round_wins_by_user"]):
		return {}
	if int(parsed["server_tick"]) < 0:
		return {}
	return parsed


static func parse_match_result_payload(payload: String) -> Dictionary:
	var parsed = JSON.parse_string(payload)
	if not parsed is Dictionary:
		return {}
	for key in [
		"winner_user_id",
		"loser_user_id",
		"round_wins_by_user",
		"final_round_number",
		"finish_cause",
		"server_tick",
	]:
		if not parsed.has(key):
			return {}
	var winner_user_id := str(parsed["winner_user_id"])
	var loser_user_id := str(parsed["loser_user_id"])
	var finish_cause := str(parsed["finish_cause"])
	if winner_user_id.is_empty() or loser_user_id.is_empty() or winner_user_id == loser_user_id:
		return {}
	if finish_cause not in ["BO3", "DISCONNECT_TIMEOUT"]:
		return {}
	if not _valid_round_wins(parsed["round_wins_by_user"]):
		return {}
	var scores: Dictionary = parsed["round_wins_by_user"]
	var final_round_number := int(parsed["final_round_number"])
	if finish_cause == "BO3":
		if int(scores.get(winner_user_id, -1)) != 2:
			return {}
		var loser_rounds := int(scores.get(loser_user_id, -1))
		if loser_rounds < 0 or loser_rounds > 1:
			return {}
		if final_round_number < 2 or final_round_number > 3:
			return {}
	else:
		if int(scores.get(winner_user_id, -1)) < 0 or int(scores.get(loser_user_id, -1)) < 0:
			return {}
		if final_round_number < 1 or final_round_number > 3:
			return {}
	if int(parsed["server_tick"]) < 0:
		return {}
	return parsed


static func parse_round_countdown_changed_payload(payload: String) -> Dictionary:
	var parsed = JSON.parse_string(payload)
	if not parsed is Dictionary:
		return {}
	for key in ["round_number", "countdown_value", "server_tick"]:
		if not parsed.has(key):
			return {}
	var round_number := int(parsed["round_number"])
	var countdown_value := int(parsed["countdown_value"])
	if round_number < 1 or round_number > 3:
		return {}
	if countdown_value < 0 or countdown_value > 3:
		return {}
	if int(parsed["server_tick"]) < 0:
		return {}
	return parsed


static func parse_match_snapshot_payload(payload: String) -> Dictionary:
	var parsed = JSON.parse_string(payload)
	if not parsed is Dictionary:
		return {}
	for key in [
		"server_tick",
		"round_number",
		"round_wins_by_user",
		"round_hit_count_by_user",
		"remaining_seconds",
		"round_finished",
		"round_winner_user_id",
		"round_finish_cause",
		"round_awaiting_overtime",
		"round_overtime",
		"round_countdown_active",
		"round_countdown_value",
		"match_finished",
		"match_winner_user_id",
		"last_input_sequence",
		"combat_state_by_user",
	]:
		if not parsed.has(key):
			return {}

	if int(parsed["server_tick"]) < 0:
		return {}
	var round_number := int(parsed["round_number"])
	if round_number < 1 or round_number > 3:
		return {}
	if not _valid_round_wins(parsed["round_wins_by_user"]):
		return {}
	if not parsed["round_hit_count_by_user"] is Dictionary:
		return {}
	for user_id in parsed["round_hit_count_by_user"].keys():
		if str(user_id).is_empty():
			return {}
		var hit_count := int(parsed["round_hit_count_by_user"][user_id])
		if hit_count < 0 or hit_count > 5:
			return {}
	var remaining_seconds := int(parsed["remaining_seconds"])
	if remaining_seconds < 0 or remaining_seconds > 85:
		return {}
	var countdown_value := int(parsed["round_countdown_value"])
	if countdown_value < -1 or countdown_value > 3:
		return {}
	if int(parsed["last_input_sequence"]) < 0:
		return {}
	if not parsed["combat_state_by_user"] is Dictionary:
		return {}
	for user_id in parsed["combat_state_by_user"].keys():
		if str(user_id).is_empty():
			return {}
		var state_value = parsed["combat_state_by_user"][user_id]
		if not state_value is Dictionary:
			return {}
		if not state_value.has("state") 				or not state_value.has("charge_ratio") 				or not state_value.has("ahoge_available"):
			return {}
		if not bool(_ALLOWED_COMBAT_STATES.get(str(state_value["state"]), false)):
			return {}

	return parsed


static func parse_player_connection_changed_payload(payload: String) -> Dictionary:
	var parsed = JSON.parse_string(payload)
	if not parsed is Dictionary:
		return {}
	for key in ["user_id", "connected", "reconnect_deadline_tick", "server_tick"]:
		if not parsed.has(key):
			return {}
	if str(parsed["user_id"]).is_empty():
		return {}
	if int(parsed["server_tick"]) < 0:
		return {}
	var deadline_tick := int(parsed["reconnect_deadline_tick"])
	if bool(parsed["connected"]):
		if deadline_tick != -1:
			return {}
	elif deadline_tick < int(parsed["server_tick"]):
		return {}
	return parsed
