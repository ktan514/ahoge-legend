extends RefCounted

signal state_changed(new_state: int)

enum ActionState {
	IDLE,
	CHARGING,
	WINDUP,
	STRIKE,
	COOLDOWN,
	PARRY,
	DODGE,
	STAGGER,
	ROUND_LOCKED,
}

var config
var action_state: int = ActionState.IDLE
var ahoge_available: bool = true
var charge_elapsed_seconds: float = 0.0
var attack_charge_ratio: float = 0.0
var action_remaining_seconds: float = 0.0
var state_elapsed_seconds: float = 0.0

var _resume_state: int = ActionState.IDLE
var _resume_remaining_seconds: float = 0.0


func _init(config_value) -> void:
	config = config_value


func begin_attack() -> bool:
	if action_state != ActionState.IDLE:
		return false
	charge_elapsed_seconds = 0.0
	attack_charge_ratio = 0.0
	_set_state(ActionState.CHARGING)
	return true


func release_attack() -> bool:
	if action_state != ActionState.CHARGING:
		return false
	attack_charge_ratio = config.charge_ratio(charge_elapsed_seconds)
	action_remaining_seconds = config.attack_windup_seconds(attack_charge_ratio)
	_set_state(ActionState.WINDUP)
	return true


func start_defense() -> bool:
	if action_state == ActionState.ROUND_LOCKED or action_state == ActionState.STAGGER:
		return false

	if action_state == ActionState.COOLDOWN:
		_resume_state = ActionState.COOLDOWN
		_resume_remaining_seconds = action_remaining_seconds
	else:
		_resume_state = ActionState.IDLE
		_resume_remaining_seconds = 0.0

	if ahoge_available:
		action_remaining_seconds = config.parry_active_seconds
		_set_state(ActionState.PARRY)
	else:
		action_remaining_seconds = config.dodge_active_seconds
		_set_state(ActionState.DODGE)
	return true


func apply_stagger() -> void:
	_resume_state = ActionState.IDLE
	_resume_remaining_seconds = 0.0
	action_remaining_seconds = config.stagger_seconds
	_set_state(ActionState.STAGGER)


func set_ahoge_available(value: bool) -> void:
	ahoge_available = value


func lock_round() -> void:
	action_remaining_seconds = 0.0
	_set_state(ActionState.ROUND_LOCKED)


func unlock_round() -> void:
	charge_elapsed_seconds = 0.0
	attack_charge_ratio = 0.0
	action_remaining_seconds = 0.0
	ahoge_available = true
	_set_state(ActionState.IDLE)


func tick(delta: float) -> void:
	if delta <= 0.0:
		return

	state_elapsed_seconds += delta

	if action_state == ActionState.CHARGING:
		charge_elapsed_seconds = minf(charge_elapsed_seconds + delta, config.max_charge_seconds)
		return

	if action_state in [
		ActionState.WINDUP,
		ActionState.STRIKE,
		ActionState.COOLDOWN,
		ActionState.PARRY,
		ActionState.DODGE,
		ActionState.STAGGER,
	]:
		action_remaining_seconds = maxf(action_remaining_seconds - delta, 0.0)
		if action_remaining_seconds <= 0.0:
			_advance_timed_state()


func action_state_name() -> String:
	return str(ActionState.keys()[action_state])


func _advance_timed_state() -> void:
	match action_state:
		ActionState.WINDUP:
			action_remaining_seconds = config.attack_strike_seconds(attack_charge_ratio)
			_set_state(ActionState.STRIKE)
		ActionState.STRIKE:
			action_remaining_seconds = config.attack_cooldown_seconds(attack_charge_ratio)
			_set_state(ActionState.COOLDOWN)
		ActionState.COOLDOWN:
			action_remaining_seconds = 0.0
			_set_state(ActionState.IDLE)
		ActionState.PARRY, ActionState.DODGE:
			if _resume_state == ActionState.COOLDOWN and _resume_remaining_seconds > 0.0:
				action_remaining_seconds = _resume_remaining_seconds
				_set_state(ActionState.COOLDOWN)
			else:
				action_remaining_seconds = 0.0
				_set_state(ActionState.IDLE)
		ActionState.STAGGER:
			action_remaining_seconds = 0.0
			_set_state(ActionState.IDLE)


func _set_state(new_state: int) -> void:
	if action_state == new_state:
		return
	action_state = new_state
	state_elapsed_seconds = 0.0
	state_changed.emit(action_state)
