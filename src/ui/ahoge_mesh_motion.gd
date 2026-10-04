extends RefCounted

const CombatantStateScript := preload("res://src/domain/combatant_state.gd")

var contact_ratio: float = 0.70
var recover_seconds: float = 0.16
var value: float = 0.0
var _state: int = CombatantStateScript.ActionState.IDLE
var _recovery_from: float = 0.0
var _hidden_during_attack: bool = false


func advance(action_state: int, elapsed: float, duration: float, available: bool) -> float:
	if not available:
		_state = action_state
		value = 0.0
		_recovery_from = 0.0
		_hidden_during_attack = true
		return value
	if action_state != _state:
		_recovery_from = value
		_state = action_state
		# 非表示になった古い攻撃は再表示だけでは再発させない。
		if action_state == CombatantStateScript.ActionState.STRIKE:
			_hidden_during_attack = false
	if action_state == CombatantStateScript.ActionState.ROUND_LOCKED:
		value = 0.0
		_recovery_from = 0.0
	elif action_state == CombatantStateScript.ActionState.STRIKE and not _hidden_during_attack:
		var progress: float = maxf(elapsed, 0.0) / maxf(duration, 0.001)
		value = smoothstep(0.04, clampf(contact_ratio, 0.05, 1.0), progress)
	else:
		value = _recovery_from * (1.0 - smoothstep(0.0, maxf(recover_seconds, 0.001), maxf(elapsed, 0.0)))
	return value
